# Solution Development Guide

This guide is for **solution developers** who deploy services (Function Apps, Logic Apps, Container Apps, APIM APIs) onto CDF-managed infrastructure.

For authoring Bicep templates and managing runtime settings, see [Infrastructure Development](infrastructure-development.md).

---

## Getting started

### Install packages
─
Solution repositories declare infrastructure dependencies in `cdf-packages.json`:

```json
{
  "$schema": "https://cdf.epical.net/schemas/cdf-packages.schema.json",
  "registries": {
    "default": {
      "type": "acr",
      "endpoint": "myregistry.azurecr.io"
    }
  },
  "templates": {
    "platform/cas/v2pub": "^2.1.0",
    "application/cas/v2pub": "^2.1.0",
    "domain/cas/v2pub": "^2.1.0",
    "service/cas/v2pub": "^2.1.0"
  },
  "settings": {
    "my01": ">=1.0.0"
  }
}
```

Install all dependencies:

```powershell
Install-Module -Name CDFModule -Scope CurrentUser
Import-Module CDFModule

Install-CdfPackage -ManifestPath ./cdf-packages.json
```

This resolves semver ranges, downloads packages to the local cache (`~/.cdf/packages/`), and sets:
- `$env:CDF_INFRA_TEMPLATES_PATH` — path to the template root
- `$env:CDF_INFRA_SOURCE_PATH` — path to the config source root

All downstream commands use these automatically.

---

## Loading runtime configuration

### The config cascade

CDFModule loads configuration scope by scope. Each step enriches the `$CdfConfig` hashtable with the current scope's data:

```powershell
# 1. Platform config
$config = Get-CdfConfigPlatform `
    -Region swedencentral `
    -PlatformId my `
    -InstanceId 01 `
    -EnvDefinitionId my-dev

# 2. Application config (receives platform from $config)
$config = $config | Get-CdfConfigApplication `
    -ApplicationId app01 `
    -InstanceId 01 `
    -EnvDefinitionId app01-dev

# 3. Domain config (receives platform + application)
$config = $config | Get-CdfConfigDomain -DomainName demo

# 4. Service config (receives platform + application + domain)
$config = $config | Get-CdfConfigService `
    -ServiceName hello `
    -ServiceType functionapp-api `
    -ServiceGroup grp1 `
    -ServiceTemplate v1
```

At any point, `$config` contains all parent scope data:

```powershell
$config.Platform.Env.subscriptionId      # From platform
$config.Platform.ResourceNames            # Resource names from platform deployment
$config.Application.Features              # Feature flags from application
$config.Domain.ResourceNames              # Domain resource names
```

### Environment variables as defaults

Most parameters default to `$env:CDF_*` variables. In CI/CD where these are set, the calls simplify:

```powershell
# When CDF_REGION, CDF_PLATFORM_ID, CDF_PLATFORM_INSTANCE,
# CDF_PLATFORM_ENV_ID, etc. are set:
$config = Get-CdfConfigPlatform
$config = $config | Get-CdfConfigApplication
$config = $config | Get-CdfConfigDomain
$config = $config | Get-CdfConfigService
```

### The service-level cdf-config.json

Service repositories use `cdf-config.json` to define service-specific settings:

```json
{
  "ServiceSettings": {
    "StorageConnection": "DefaultEndpointsProtocol=https;AccountName=...",
    "ApiBaseUrl": "https://{{DomainName}}-records-api.intg01.int01.dev.axlhub.net"
  }
}
```

CDFModule substitutes `{{DomainName}}` and other tokens at deploy time. The resolved settings are merged into the service deployment configuration.

> **Note**: `cdf-config.json` is the _service-level_ config file in your application repo. Do not confuse it with `cdf-runtime.json`, which is the _infrastructure_ manifest in the cdf-config repo.

---

## Deploying services

### Full service deployment

`Deploy-CdfService` handles the complete deployment of a service including infrastructure and application code:

```powershell
Deploy-CdfService `
    -Region swedencentral `
    -PlatformId my `
    -PlatformInstance 01 `
    -PlatformEnvId my-dev `
    -ApplicationId app01 `
    -ApplicationInstance 01 `
    -ApplicationEnvId app01-dev `
    -DomainName demo `
    -ServiceName hello `
    -ServiceType functionapp-api `
    -ServiceGroup grp1 `
    -ServiceTemplate v1
```

This command:
1. Loads the full config cascade (platform → application → domain → service).
2. Builds deployment artifacts (Bicep compilation, APIM templates).
3. Deploys the service template.
4. Deploys the application code.
5. Applies APIM configuration if applicable.

### Service template deployment only

To deploy just the infrastructure template for a service:

```powershell
$config = Get-CdfConfigPlatform -EnvDefinitionId my-dev `
| Get-CdfConfigApplication -ApplicationId app01 -InstanceId 01 -EnvDefinitionId app01-dev `
| Get-CdfConfigDomain -DomainName demo `
| Get-CdfConfigService -ServiceName hello -ServiceType functionapp-api -ServiceGroup grp1 -ServiceTemplate v1

$config | Deploy-CdfTemplateService
```

### Service-specific deployments

For container apps, function apps, and logic apps there are specialised deploy commands:

```powershell
# Container App
Deploy-CdfServiceContainerApp -CdfConfig $config -ServiceSrcPath ./src/my-container-app

# Function App
Deploy-CdfServiceFunctionApp -CdfConfig $config -ServiceSrcPath ./src/my-function-app

# Logic App Standard
Deploy-CdfServiceLogicAppStd -CdfConfig $config -ServiceSrcPath ./src/my-logic-app
```

---

## APIM integration

### Building APIM templates

CDFModule compiles APIM configuration from source XML policies and OpenAPI specs into deployment-ready ARM/Bicep templates:

```powershell
# Build all APIM templates for a service
Build-CdfApimServiceTemplates -CdfConfig $config -ServiceSrcPath ./src/my-api

# Build domain-level backends
Build-CdfApimDomainBackendTemplates -CdfConfig $config

# Build domain-level products
Build-CdfApimDomainProductTemplates -CdfConfig $config

# Build operation-level policies
Build-CdfApimOperationPolicies -CdfConfig $config -ServiceSrcPath ./src/my-api
```

### Policy composition

APIM policies are composed by CDFModule into flat XML. The composition order follows the CDF scope hierarchy:

```
Enterprise (product-level) policy
  └─ <apim-policy-global /> ← replaced with domain policy content
       └─ <apim-policy-global /> ← replaced with API policy content
```

Content **before** `<apim-policy-global />` in a parent policy runs before child content. Content **after** runs after. This gives enterprise policies control over the execution order (e.g. JWT validation before API logic, response headers after).

### Named values and secrets

Deploy secrets from Key Vault as APIM named values:

```powershell
# Domain-level named values
Deploy-CdfApimKeyVaultDomainNamedValues -CdfConfig $config

# Service-level named values
Deploy-CdfApimKeyVaultServiceNamedValues -CdfConfig $config
```

### Build global policies

```powershell
Build-CdfApimGlobalPolicies -CdfConfig $config -ServiceSrcPath ./src/my-api
```

The composed policy XML is written to `tmp/build/<service>/domain-api/policies/global-api.xml` for inspection before deployment.

---

## Secrets and connections

### Service connection settings

Apply app settings and connection strings to deployed services:

```powershell
Add-CdfServiceConnectionSettings -CdfConfig $config -ServiceSrcPath ./src/my-app
```

### Logic App connections

```powershell
# Add a managed API connection (e.g. Office 365, Dataverse)
Add-CdfLogicAppManagedApiConnection -CdfConfig $config -ConnectionName office365

# Add a service provider connection (e.g. Service Bus, SQL)
Add-CdfLogicAppServiceProviderConnection -CdfConfig $config -ConnectionName servicebus

# Configure connection access policies
Add-CdfManagedApiConnectionAccess -CdfConfig $config

# Apply app settings to the Logic App
Add-CdfLogicAppAppSettings -CdfConfig $config -ServiceSrcPath ./src/my-logic-app
```

### GitHub secrets

Deploy secrets to GitHub Actions environments for CI/CD:

```powershell
Deploy-CdfGitHubKeyVaultSecrets -CdfConfig $config
```

---

## CI/CD for solutions

### Deployment matrix

CDFModule generates GitHub Actions matrix configurations for multi-environment deployments:

```powershell
$matrix = Get-CdfGitHubMatrix `
    -PlatformId my `
    -PlatformInstance 01 `
    -ApplicationId app01 `
    -ApplicationInstance 01

# Output as JSON for GitHub Actions
$matrix | ConvertTo-Json -Compress
```

### Example workflow

```yaml
# .github/workflows/deploy-service.yaml
name: Deploy Service
on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  matrix:
    runs-on: ubuntu-latest
    outputs:
      environments: ${{ steps.matrix.outputs.environments }}
    steps:
      - uses: actions/checkout@v4
      - name: Install CDFModule and packages
        shell: pwsh
        run: |
          Install-Module -Name CDFModule -Force
          Install-CdfPackage -ManifestPath ./cdf-packages.json
      - name: Build matrix
        id: matrix
        shell: pwsh
        run: |
          $matrix = Get-CdfGitHubMatrix `
              -PlatformId my `
              -PlatformInstance 01 `
              -ApplicationId app01 `
              -ApplicationInstance 01
          "environments=$($matrix | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT

  deploy:
    needs: matrix
    runs-on: ubuntu-latest
    strategy:
      matrix:
        environment: ${{ fromJson(needs.matrix.outputs.environments) }}
    environment: ${{ matrix.environment.name }}
    steps:
      - uses: actions/checkout@v4

      - name: Checkout cdf-templates
        uses: actions/checkout@v4
        with:
          repository: org/cdf-templates
          path: cdf-templates

      - name: Checkout cdf-config
        uses: actions/checkout@v4
        with:
          repository: org/cdf-config
          path: cdf-config

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Install CDFModule
        shell: pwsh
        run: Install-Module -Name CDFModule -Force

      - name: Deploy
        shell: pwsh
        env:
          CDF_INFRA_TEMPLATES_PATH: cdf-templates
          CDF_INFRA_SOURCE_PATH: cdf-config/src
        run: |
          Deploy-CdfService `
              -Region ${{ matrix.environment.region }} `
              -PlatformId ${{ matrix.environment.platformId }} `
              -PlatformInstance ${{ matrix.environment.instanceId }} `
              -PlatformEnvId ${{ matrix.environment.envId }} `
              -ApplicationId ${{ matrix.environment.appId }} `
              -ApplicationInstance ${{ matrix.environment.appInstance }} `
              -DomainName demo `
              -ServiceName hello `
              -ServiceType functionapp-api `
              -ServiceGroup grp1 `
              -ServiceTemplate v1
```

### GitHub environment setup

CDFModule can configure GitHub environments with the required secrets and variables:

```powershell
# Add platform environment config to GitHub
Add-CdfGitHubPlatformEnv -CdfConfig $config

# Add application environment config to GitHub
Add-CdfGitHubApplicationEnv -CdfConfig $config
```

---

## Command reference (solution-focused)

| Category | Commands |
|---|---|
| **Config loading** | `Get-CdfConfigPlatform`, `Get-CdfConfigApplication`, `Get-CdfConfigDomain`, `Get-CdfConfigService` |
| **Service deployment** | `Deploy-CdfService`, `Deploy-CdfTemplateService`, `Deploy-CdfServiceFunctionApp`, `Deploy-CdfServiceContainerApp`, `Deploy-CdfServiceContainerAppService`, `Deploy-CdfServiceLogicAppStd` |
| **APIM** | `Build-CdfApimServiceTemplates`, `Build-CdfApimDomainBackendTemplates`, `Build-CdfApimDomainProductTemplates`, `Build-CdfApimGlobalPolicies`, `Build-CdfApimOperationPolicies`, `Build-CdfApimDomainNamedValuesTemplate` |
| **APIM deployment** | `Deploy-CdfApimKeyVaultDomainNamedValues`, `Deploy-CdfApimKeyVaultServiceNamedValues`, `Export-CdfApimPortalConfig` |
| **Connections** | `Add-CdfServiceConnectionSettings`, `Add-CdfLogicAppAppSettings`, `Add-CdfLogicAppManagedApiConnection`, `Add-CdfLogicAppServiceProviderConnection`, `Add-CdfManagedApiConnectionAccess` |
| **GitHub** | `Get-CdfGitHubMatrix`, `Add-CdfGitHubPlatformEnv`, `Add-CdfGitHubApplicationEnv`, `Deploy-CdfGitHubKeyVaultSecrets` |
| **Service Bus** | `Deploy-CdfServiceBusConfig` |
| **Packages** | `Install-CdfPackage`, `Get-CdfPackage`, `Test-CdfDependency` |

For full parameter details, use PowerShell help:

```powershell
Get-Help Deploy-CdfService -Detailed
Get-Help Get-CdfConfigPlatform -Examples
```
