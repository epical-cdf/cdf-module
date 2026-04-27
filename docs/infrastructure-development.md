# Infrastructure Development Guide

This guide is for **infrastructure developers** who author Bicep templates, manage runtime configurations, and publish packages to the CDF registry.

For deploying services onto existing infrastructure, see [Solution Development](solution-development.md).

---

## Template authoring

### Directory conventions

Templates follow a strict directory structure: `<scope>/<name>/<version>/`

```
platform/
  cas/v2pub/              platform.bicep, modules/, cdf-template.json
  cas/v2net/              private networking variant
  microservices/v2pub/
application/
  cas/v2pub/              application.bicep, modules/, cdf-template.json
domain/
  cas/v2pub/              domain.bicep, modules/, cdf-template.json
service/
  cas/v2pub/              <serviceTemplate>.bicep (e.g. functionapp-api-v1.bicep)
```

- **scope**: One of `platform`, `application`, `domain`, `service`.
- **name**: Template family (e.g. `cas`, `microservices`, `intg`, `blank`).
- **version**: Template variant/architecture (e.g. `v2pub` for public, `v2net` for private networking). This is _not_ a semver — it identifies a structural variant.

### The cdf-template.json manifest

Every template directory must contain a `cdf-template.json` manifest:

```json
{
  "$schema": "https://cdf.epical.net/schemas/cdf-template.schema.json",
  "scope": "platform",
  "name": "blank",
  "version": "v1",
  "release": "0.1.0",
  "description": "Blank platform starter template with feature-gated storage account.",
  "providedFeatures": [
    "enableStorageAccount"
  ],
  "dependencies": {}
}
```

| Field | Required | Description |
|---|---|---|
| `scope` | Yes | Must match the directory scope (`platform`, `application`, `domain`, `service`) |
| `name` | Yes | Must match the directory name |
| `version` | Yes | Must match the directory version |
| `release` | Yes | Semver for the package lifecycle (e.g. `2.1.0`, `2.1.0-pre.1`) |
| `description` | No | Human-readable description |
| `providedFeatures` | No | Features this template can enable (array of strings) |
| `dependencies` | No | Required upstream templates with release ranges and feature requirements |

### Feature contracts

Features are the contract between templates across scopes. They control which optional infrastructure gets deployed.

**Providing features** — a template declares what it _can_ enable:

```json
"providedFeatures": ["enableStorageAccount", "enableKeyVault", "enableServiceBus"]
```

**Requiring features** — a downstream template declares what it _needs_ from an upstream dependency:

```json
"dependencies": {
  "platform/cas/v2pub": {
    "release": ">=2.0.0",
    "requiredFeatures": ["enableStorageAccount", "enableKeyVault"]
  }
}
```

The dependency chain follows the scope hierarchy:

- **Platform** → no dependencies (root of the chain)
- **Application** → depends on its platform
- **Domain** → depends on its platform and application
- **Service** → depends on platform, application, and domain

Validate feature compatibility across installed packages:

```powershell
Test-CdfDependency
```

### Bicep conventions

Each scope follows a consistent Bicep pattern:

```bicep
targetScope = 'subscription'           // 'resourceGroup' for service scope
metadata template = 'platform-blank-v1'
var templateScope = 'platform'
var templateName = 'blank'
var templateVersion = 'v1'

// Parameters: receive config from CDFModule
param platformEnv object
param platformConfig object
param platformFeatures object
param platformNetworkConfig object
param platformAccessControl object
param platformTags object = {}

// Feature-gated resources
module modStorageAccount 'modules/platform-storageaccount.bicep' = if (platformFeatures.enableStorageAccount) {
  name: '${envKey}-platform-storageaccount'
  scope: platformRG
  params: { ... }
}

// Outputs: deployment config flows to downstream scopes
output platformEnv object = deploymentConfig.Env
output platformConfig object = deploymentConfig.Config
output platformFeatures object = deploymentConfig.Features
output platformResourceNames object = deploymentConfig.ResourceNames
// ... etc
```

Key patterns:

- **Tags**: Every scope unions its tags with CDF template metadata (`TemplateName`, `TemplateVersion`, `TemplateScope`, `TemplateInstance`, `TemplateEnv`).
- **Resource names**: Computed as variables, included in `ResourceNames` output. Downstream scopes reference resources by name from the output.
- **Feature gating**: Conditional deployment with `if (scopeFeatures.enableXxx)`. Resource names are set to `null` when the feature is disabled.
- **Outputs**: A `deploymentConfig` object collects all outputs. CDFModule captures these and passes them to the next scope.

See the [blank/v1 sample templates](../samples/templates/) for a complete working example across all four scopes.

---

## Runtime configuration

### Directory layout

Runtime configurations live in a separate repository with the structure: `src/<platformId>/<instanceId>/`

```
src/my/01/
  cdf-runtime.json                           # Runtime manifest
  platform/
    environments.json                        # Environment definitions
    regioncodes.json                         # Azure region → short code mapping
    regionnames.json                         # Short code → display name mapping
    platform.my01dev-sdc.json                # Config for env "dev", region "swedencentral"
  application/
    environments.app01.json                  # Application environment definitions
    application.my01dev-app01dev-sdc.json    # Application config
  domain/
    domain.my01dev-app01dev-demo-sdc.json    # Domain config
  service/
    service.my01dev-app01dev-demo-hello-sdc.json  # Service config
  output/                                    # Deployment outputs (auto-generated)
```

### The cdf-runtime.json manifest

Each config instance declares which templates it uses:

```json
{
  "$schema": "https://cdf.epical.net/schemas/cdf-runtime.schema.json",
  "platformId": "my",
  "instanceId": "01",
  "release": "0.1.0",
  "description": "Sample runtime config instance using blank starter templates",
  "templates": {
    "platform/blank/v1": ">=0.1.0",
    "application/blank/v1": ">=0.1.0",
    "domain/blank/v1": ">=0.1.0",
    "service/blank/v1": ">=0.1.0"
  }
}
```

> **Note**: `cdf-runtime.json` is the _infrastructure_ manifest. Do not confuse it with `cdf-config.json`, which is the _service-level_ configuration file used by solution developers.

### Config file naming

Config files follow a deterministic naming pattern:

```
<scope>.<platformEnvKey>[-<appEnvKey>][-<domainName>][-<serviceName>]-<regionCode>.json
```

Where:

- `platformEnvKey` = `<platformId><instanceId><envNameId>` (e.g. `my01dev`)
- `regionCode` = Short Azure region code (e.g. `sdc` for swedencentral)

Examples:

- `platform.my01dev-sdc.json`
- `application.my01dev-app01dev-sdc.json`
- `domain.my01dev-app01dev-demo-sdc.json`
- `service.my01dev-app01dev-demo-hello-sdc.json`

### Config file structure

Each config file controls what gets deployed:

```json
{
  "IsDeployed": false,
  "Config": {
    "templateName": "blank",
    "templateVersion": "v1"
  },
  "Features": {
    "enableStorageAccount": true
  },
  "AccessControl": {
    "storageAccountRBAC": [
      {
        "roleDefinitionId": "17d1049b-9a84-46fb-8f53-869881c3d3ab",
        "description": "Assign 'admin@sample.onmicrosoft.com' role 'Storage Account Contributor'",
        "principalId": "00000000-0000-0000-0000-000000000002",
        "principalType": "User",
        "tenantId": "00000000-0000-0000-0000-000000000000"
      }
    ]
  }
}
```

- **IsDeployed**: Set to `true` by CDFModule after successful deployment. Used as a safety check.
- **Config**: Binds to a specific template name and version.
- **Features**: Activates the features declared in the template's `providedFeatures`.
- **AccessControl**: RBAC assignments applied during deployment.

### Environment definitions

The `environments.json` file defines the deployment targets:

```json
{
  "my-dev": {
    "definitionId": "my-dev",
    "nameId": "dev",
    "name": "Primary Dev",
    "purpose": "development",
    "tenantId": "",
    "subscriptionId": "",
    "infraDeployerName": "sp-my-deployer-dev",
    "isEnabled": true,
    "parentDnsZone": "dev.mydomain.net"
  }
}
```

Each environment maps to a separate config file per scope. The `definitionId` is the key used by `Get-CdfConfigPlatform -EnvDefinitionId my-dev`.

### Creating a new config instance

```powershell
# Scaffold a new platform config from a template's seed files
New-CdfConfigPlatform `
    -Region swedencentral `
    -TemplateName blank `
    -TemplateVersion v1 `
    -PlatformId my `
    -InstanceId 01
```

This copies seed files from the template directory into `$SourceDir/my/01/platform/` and generates initial config files for each enabled environment.

See the [sample config instance](../samples/configs/my/01/) for the complete structure.

---

## Package registry

### Overview

CDF templates and configs are published as OCI artifacts to an Azure Container Registry (ACR). This enables versioned, immutable releases that can be consumed by any team.

```
┌──────────────┐    Publish-CdfTemplate    ┌──────────────┐    Install-CdfPackage    ┌──────────────┐
│ cdf-templates│ ─────────────────────────→│     ACR      │ ───────────────────────→ │ Local cache  │
│ (git repo)   │                           │  (registry)  │                          │ ~/.cdf/      │
└──────────────┘                           └──────────────┘                          │ packages/    │
                                                                                     └──────┬───────┘
┌──────────────┐    Publish-CdfConfig      ┌──────────────┐                                 │
│  cdf-config  │ ─────────────────────────→│     ACR      │                                 │
│ (git repo)   │                           └──────────────┘             $env:CDF_INFRA_TEMPLATES_PATH
└──────────────┘                                                        $env:CDF_INFRA_SOURCE_PATH
                                                                                    │
                                                                          Deploy-CdfTemplatePlatform
```

### Version vs release

These are distinct concepts:

| Concept | Example | Meaning |
|---|---|---|
| **Version** | `v2pub`, `v2net`, `v1` | Template variant/architecture. Part of the directory path. Does not change. |
| **Release** | `2.1.0`, `2.1.0-pre.1` | Semver lifecycle version. Changes with each publish. |

A template is identified as `<scope>/<name>/<version>` (e.g. `platform/cas/v2pub`). Each identity can have many releases (`2.0.0`, `2.1.0`, `2.2.0-pre.1`, etc.).

### Publishing templates

```powershell
# Publish from the template directory
Publish-CdfTemplate -TemplatePath ./platform/blank/v1

# Override the release version (useful in CI)
Publish-CdfTemplate -TemplatePath ./platform/blank/v1 -Release 1.0.0
```

The command reads `cdf-template.json`, packs the directory, and pushes it to the registry at: `<acr>/cdf/templates/<scope>/<name>/<version>:<release>`

### Publishing configs

```powershell
# Publish from the config instance directory
Publish-CdfConfig -ConfigPath ./src/my/01

# Override the release version
Publish-CdfConfig -ConfigPath ./src/my/01 -Release 1.0.0
```

The command reads `cdf-runtime.json` and pushes to: `<acr>/cdf/configs/<platformId><instanceId>:<release>`

### The cdf-packages.json workspace manifest

Consumer repositories declare their dependencies in `cdf-packages.json`:

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
    "platform/blank/v1": ">=0.1.0",
    "application/blank/v1": ">=0.1.0",
    "domain/blank/v1": ">=0.1.0",
    "service/blank/v1": ">=0.1.0"
  },
  "configs": {
    "my01": ">=0.1.0"
  }
}
```

Values are semver ranges. Supported operators: `>=`, `^` (compatible), `~` (patch-level), exact match.

### Installing packages

```powershell
# Install all packages from the workspace manifest
Install-CdfPackage -ManifestPath ./cdf-packages.json

# Install a single template
Install-CdfPackage -TemplateRef platform/blank/v1:0.1.0 -Registry myregistry.azurecr.io

# Force re-download
Install-CdfPackage -ManifestPath ./cdf-packages.json -Force
```

`Install-CdfPackage` resolves semver ranges, downloads packages to the local cache (`~/.cdf/packages/`), and sets the environment variables:

- `$env:CDF_INFRA_TEMPLATES_PATH` → points to the cached template root
- `$env:CDF_INFRA_SOURCE_PATH` → points to the cached config root

All downstream `Deploy-CdfTemplate*` commands read these variables automatically.

### Listing packages

```powershell
# Show available releases from the registry
Get-CdfPackage -ManifestPath ./cdf-packages.json

# Show installed (cached) packages
Get-CdfPackage -Installed
```

### Registry configuration

Registries can be configured at three levels, resolved with fallback:

| Priority | Location | Use case |
|---|---|---|
| 1 | `<project>/.cdf/registries/<name>.json` | Project-level (committed or gitignored) |
| 2 | `$HOME/.cdf/registries/<name>.json` | User-level defaults |
| 3 | Inline `registries` in `cdf-packages.json` | Fallback (committed) |

Registry config file format:

```json
{
  "type": "acr",
  "endpoint": "myregistry.azurecr.io"
}
```

### Multi-registry support

Reference packages from different registries using the `@<registry>` suffix:

```json
{
  "registries": {
    "default": { "type": "acr", "endpoint": "team-registry.azurecr.io" },
    "shared":  { "type": "acr", "endpoint": "org-registry.azurecr.io" }
  },
  "templates": {
    "platform/cas/v2pub": "^2.1.0",
    "platform/microservices/v2pub@shared": ">=3.0.0"
  }
}
```

---

## Local development

### Using local templates (inner loop)

During template development, you want to deploy from your local git checkout without publishing to a registry. Configure a `local` registry:

```json
// <project>/.cdf/registries/default.json
{
  "type": "local",
  "path": "../cdf-templates"
}
```

Then run the same `Install-CdfPackage` command:

```powershell
Install-CdfPackage -ManifestPath ./cdf-packages.json
```

With a `local` registry, `Install-CdfPackage`:

1. Validates manifests and dependencies from the filesystem.
2. Sets `$env:CDF_INFRA_TEMPLATES_PATH` to the local path (e.g. `../cdf-templates`).
3. Does **not** download or cache anything.

Every edit to the local template checkout is immediately available. No publish step needed.

### Deployment workflow

Once packages are installed (local or remote), deployment is the same:

```powershell
# Load config and deploy — pipeline style
$config = Get-CdfConfigPlatform `
    -Region swedencentral `
    -PlatformId my `
    -InstanceId 01 `
    -EnvDefinitionId my-dev

$config = $config | Deploy-CdfTemplatePlatform
$config = $config | Get-CdfConfigApplication -ApplicationId app01 -InstanceId 01 -EnvDefinitionId my-dev
$config = $config | Deploy-CdfTemplateApplication
$config = $config | Get-CdfConfigDomain -DomainName demo
$config = $config | Deploy-CdfTemplateDomain
```

The deployment commands resolve the template path from `$env:CDF_INFRA_TEMPLATES_PATH`:

```
$TemplateDir/platform/<templateName>/<templateVersion>/platform.bicep
```

This path works identically whether `$env:CDF_INFRA_TEMPLATES_PATH` points to a local checkout or the package cache.

### Environment variables

Instead of `Install-CdfPackage`, you can set the paths directly:

```powershell
$env:CDF_INFRA_TEMPLATES_PATH = '../cdf-templates'
$env:CDF_INFRA_SOURCE_PATH = '../cdf-config/src'
```

Or pass them as parameters:

```powershell
Deploy-CdfTemplatePlatform -CdfConfig $config `
    -TemplateDir ../cdf-templates `
    -SourceDir ../cdf-config/src
```

---

## CI/CD for infrastructure

### Publishing templates on release

```yaml
# .github/workflows/publish-templates.yaml
name: Publish CDF Templates
on:
  push:
    tags: ['v[0-9]+.[0-9]+.[0-9]+']

jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      id-token: write    # OIDC
      contents: read
    steps:
      - uses: actions/checkout@v4
      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - name: Install CDFModule
        shell: pwsh
        run: Install-Module -Name CDFModule -Force
      - name: Publish templates
        shell: pwsh
        run: |
          $release = "${{ github.ref_name }}".TrimStart('v')
          foreach ($manifest in Get-ChildItem -Recurse -Filter 'cdf-template.json') {
              Publish-CdfTemplate -TemplatePath $manifest.DirectoryName -Release $release
          }
```

### Deploying infrastructure

```yaml
# .github/workflows/deploy-platform.yaml
name: Deploy Platform
on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment definition ID'
        required: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Azure Login
        uses: azure/login@v2
        with: { ... }
      - name: Install CDFModule and packages
        shell: pwsh
        run: |
          Install-Module -Name CDFModule -Force
          Install-CdfPackage -ManifestPath ./cdf-packages.json
      - name: Deploy Platform
        shell: pwsh
        run: |
          Get-CdfConfigPlatform `
              -Region swedencentral `
              -PlatformId my `
              -InstanceId 01 `
              -EnvDefinitionId '${{ inputs.environment }}' `
          | Deploy-CdfTemplatePlatform
```

The workflow installs packages from the registry (setting `CDF_INFRA_TEMPLATES_PATH` and `CDF_INFRA_SOURCE_PATH`), then deploys using the standard CDFModule pipeline.
