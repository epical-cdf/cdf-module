# Cloud Deployment Framework (CDF)

## What is CDF?

The **Cloud Deployment Framework** (CDF) is a structured approach to deploying and managing Azure infrastructure across multiple environments. It provides:

- A **layered deployment model** with four scopes that separate concerns and enable reuse.
- **Versioned Bicep templates** that define the infrastructure for each scope.
- **Runtime configurations** that bind templates to specific environments with feature flags, access control, and network settings.
- A **PowerShell module** (CDFModule) that orchestrates configuration loading, template deployment, and package management.

CDF is designed for organisations that operate multiple Azure environments (dev, test, production) across multiple tenants or business units, where infrastructure patterns are shared but configurations differ.

## The four-scope deployment chain

Every CDF deployment follows a strict hierarchy. Each scope builds on the outputs of the previous one:

```text
Platform                  Subscription-level foundation
  └─ Application          Shared application resources (service plans, registries)
       └─ Domain          Business domain resources (storage, key vault, service bus)
            └─ Service    Individual workloads (Function Apps, Logic Apps, Container Apps)
```

| Scope           | Target         | Typical resources                                   | Example                 |
|-----------------|----------------|-----------------------------------------------------|-------------------------|
| **Platform**    | Subscription   | Resource groups, networking, shared storage         | `platform/cas/v2pub`    |
| **Application** | Subscription   | App service plans, container registries, key vaults | `application/cas/v2pub` |
| **Domain**      | Subscription   | Domain-specific storage, service bus topics         | `domain/cas/v2pub`      |
| **Service**     | Resource Group | Function Apps, Logic Apps, Container Apps, APIM     | `service/cas/v2pub`     |

Each scope receives the outputs from all parent scopes as parameters. A service deployment has access to platform, application, and domain resource names, features, and configuration.

## Settings + Template → Config pipeline

Every CDF deployment follows a two-phase pattern: **load settings**, then **deploy template**. The output of one scope becomes the input to the next.

### The two data types

| Concept     | Meaning                                                                                             | Source                                                    | Azure needed? |
|-------------|-----------------------------------------------------------------------------------------------------|-----------------------------------------------------------|---------------|
| **Setting** | Static input to a template — environment definitions, feature flags, access control, network config | Files on disk or setting packages from registry           | No            |
| **Config**  | Deployed output — resource names, endpoints, resolved features, tags                                | Azure deployment outputs, App Configuration, or Key Vault | Yes           |

Settings are what you _author_. Config is what the deployment _produces_.

### How it flows

```text
                          Setting (input)         Template (Bicep)        Config (output)
                          ──────────────          ────────────────        ───────────────
Platform scope        →   platform.*.json    +    platform.bicep     →   platformConfig,
                          environments.json       (subscription)         platformResourceNames,
                          features, RBAC                                 platformFeatures, ...
                                                                              │
Application scope     →   application.*.json +    application.bicep  →   applicationConfig,
                          app environments        (subscription)         applicationResourceNames,
                          + platformConfig ──────────────────────────────────→ applicationFeatures, ...
                                                                              │
Domain scope          →   domain.*.json      +    domain.bicep       →   domainConfig,
                          + platformConfig ──────────────────────────────────→ domainResourceNames,
                          + applicationConfig ───────────────────────────────→ domainFeatures, ...
                                                                              │
Service scope         →   service.*.json     +    <svcTemplate>.bicep →  serviceConfig,
                          + cdf-config.json       (resourceGroup)        serviceResourceNames,
                          + all parent configs ──────────────────────────────→ ...
```

Each `Get-CdfConfig*` function loads the **setting** (from file or package, no Azure connection required). When called with `-Deployed`, it also fetches the latest **config** from Azure deployment outputs or a config store.

The `Deploy-CdfTemplate*` functions take the loaded setting, merge parent config outputs, and run the Bicep deployment. The deployment outputs become the **config** for downstream scopes.

### In practice

```powershell
# 1. Load setting → deploy template → config output cascades down
$config = Get-CdfConfigPlatform -PlatformId my -InstanceId 01 -EnvDefinitionId my-dev -Region swedencentral
$config | Deploy-CdfTemplatePlatform

# 2. Load application setting + platform config → deploy → application config cascades
$config = $config | Get-CdfConfigApplication -Deployed -ApplicationId app01 -InstanceId 01 -EnvDefinitionId app01-dev
$config | Deploy-CdfTemplateApplication

# 3. Load domain setting + platform/application config → deploy
$config = $config | Get-CdfConfigDomain -Deployed -DomainName demo
$config | Deploy-CdfTemplateDomain

# 4. Load service setting + all parent config → deploy
$config = $config | Get-CdfConfigService -Deployed -ServiceName hello -ServiceType functionapp-api -ServiceGroup grp1 -ServiceTemplate v1
$config | Deploy-CdfTemplateService
```

**Without `-Deployed`**: `Get-CdfConfig*` returns only the setting from file/package — useful for validation, dry runs, or environments not yet deployed.

**With `-Deployed`**: It also fetches the latest config from Azure. If Azure auth fails, it falls back to the setting with a warning.

## Three-repo architecture

CDF separates infrastructure code, instance configuration, and orchestration tooling into distinct repositories:

```text
┌──────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  cdf-templates   │     │   cdf-config     │     │   CDFModule     │
│                  │     │                  │     │                 │
│ Bicep templates  │     │ Runtime settings │     │ PowerShell      │
│ per scope/name/  │     │ per platform/    │     │ orchestration   │
│ version          │     │ instance         │     │ + package mgmt  │
│                  │     │                  │     │                 │
│ cdf-template.json│     │ cdf-runtime.json │     │ Published to    │
│ (manifest)       │     │ (manifest)       │     │ PSGallery       │
└────────┬─────────┘     └────────┬─────────┘     └────────┬────────┘
         │                        │                        │
         │    $env:CDF_INFRA_     │   $env:CDF_INFRA_      │
         │    TEMPLATES_PATH      │   SOURCE_PATH          │
         └────────────────────────┴────────────────────────┘
                    Deploy-CdfTemplatePlatform
                    Deploy-CdfTemplateApplication
                    Deploy-CdfTemplateDomain
                    Deploy-CdfTemplateService
```

| Repository        | Purpose                                                           | Key manifest           |
|-------------------|-------------------------------------------------------------------|------------------------|
| **cdf-templates** | Reusable Bicep templates with feature contracts                   | `cdf-template.json`    |
| **cdf-config**    | Instance-specific configuration (environments, features, RBAC)    | `cdf-runtime.json`     |
| **CDFModule**     | PowerShell module: config loading, deployment, package management | Published to PSGallery |

## Key concepts

| Concept                      | Description                                                                                                                                                          |
|------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Template**                 | A Bicep deployment for one scope, identified by `<scope>/<name>/<version>` (e.g. `platform/cas/v2pub`)                                                               |
| **Version**                  | Template variant/architecture identifier (e.g. `v2pub`, `v2net`). Not a semver — think of it as a template flavour                                                   |
| **Release**                  | Semver lifecycle version of a template (e.g. `2.1.0`, `2.1.0-pre.1`). Used for package registry                                                                      |
| **Config instance**          | A runtime configuration for a specific platform+instance (e.g. `tscx01`). Contains environment definitions, feature flags, and access control                        |
| **Features**                 | Boolean flags that gate optional infrastructure (e.g. `enableStorageAccount`, `enableServiceBus`). Declared in templates via `providedFeatures`, activated in config |
| **Feature contract**         | Templates declare `providedFeatures` (what they can enable) and `requiredFeatures` (what they need from dependencies)                                                |
| **Registry**                 | An OCI-compatible container registry (Azure Container Registry) used to publish and consume template/setting packages                                                |
| **CDF_INFRA_TEMPLATES_PATH** | Environment variable pointing to the template root directory. Set by `Install-CdfPackage` or manually                                                                |
| **CDF_INFRA_SOURCE_PATH**    | Environment variable pointing to the config source directory. Set by `Install-CdfPackage` or manually                                                                |

## Two audiences, two workflows

CDF serves two distinct user groups with different concerns:

### Infrastructure developers

Author Bicep templates, manage feature contracts, configure runtime instances, and publish packages to the registry.

**Guide**: [Infrastructure Development](infrastructure-development.md)

### Solution developers

Consume deployed infrastructure to build and deploy services (Function Apps, Logic Apps, Container Apps, APIM APIs).

**Guide**: [Solution Development](solution-development.md)

## Prerequisites

| Tool                     | Version | Purpose                                         |
|--------------------------|---------|-------------------------------------------------|
| **PowerShell**           | 7.4+    | CDFModule requires PowerShell Core              |
| **Az PowerShell module** | Latest  | Azure resource deployments                      |
| **Azure CLI**            | Latest  | Authentication, ACR login                       |
| **Bicep CLI**            | Latest  | Template compilation (bundled with Azure CLI)   |
| **oras CLI**             | 1.0+    | OCI artifact push/pull for package registry     |
| **CDFModule**            | 1.1.0+  | `Install-Module -Name CDFModule` from PSGallery |

## Quick start

```powershell
# Install the module
Install-Module -Name CDFModule -Scope CurrentUser

# Import it (adds the Cdf command prefix)
Import-Module CDFModule

# Set up package resolution and install templates + settings
Install-CdfPackage -ManifestPath ./cdf-packages.json

# Load configuration and deploy
Get-CdfConfigPlatform -Region swedencentral -PlatformId my -InstanceId 01 -EnvDefinitionId my-dev `
| Deploy-CdfTemplatePlatform
```

## Samples

The CDFModule repository includes reference samples under [`samples/`](../samples/):

| Sample                                        | Description                                                                     |
|-----------------------------------------------|---------------------------------------------------------------------------------|
| [`samples/templates/`](../samples/templates/) | Blank starter templates for all four scopes with `cdf-template.json` manifests  |
| [`samples/settings/`](../samples/settings/)   | A sample runtime setting instance (`my/01`) with environments and feature flags |
| [`samples/workspace/`](../samples/workspace/) | A `cdf-packages.json` workspace manifest showing registry configuration         |
