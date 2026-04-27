# CDF Shared Resources — Samples

CDF shared resources provide reusable building blocks for service development and deployment. They are resolved at runtime via two environment variables:

| Variable | Description | Default |
|---|---|---|
| `$env:CDF_SHARED_SOURCE_PATH` | Root of the shared repository | `../../shared-infra` |
| `$env:CDF_SHARED_TEMPLATES_PATH` | Service type templates | `$CDF_SHARED_SOURCE_PATH/templates` |

## Composable scopes

The shared root is organised into scopes. Each scope is independent — organisations can compose them as needed: all in one repo, split across multiple repos, or a subset only.

```
$CDF_SHARED_SOURCE_PATH/
├── policies/              APIM enterprise policies (Level 1)
├── resources/             APIM bicep templates for API deployment
├── modules/               Reusable bicep modules
│   ├── storageaccount-config/    Storage Account resource provisioning
│   ├── servicebus-config/        Service Bus queue/topic provisioning
│   └── api-connections/          Logic App managed API connectors
├── connections/           API connection definitions (per-env)
└── templates/             Service type templates ($CDF_SHARED_TEMPLATES_PATH)
    ├── la-base/           Logic App Standard base scaffold
    └── <serviceType>/     Service type with cdf-config.json
```

## Which CDFModule commands use which scope

| Scope | Subdirectory | Commands |
|---|---|---|
| **APIM policies** | `policies/` | `Build-CdfApimGlobalPolicies`, `Build-CdfApimOperationPolicies` |
| **APIM resources** | `resources/` | `Build-CdfApimServiceTemplates`, `Build-CdfApimDomainBackendTemplates`, `Build-CdfApimDomainProductTemplates`, `Build-CdfApimDomainNamedValuesTemplate` |
| **Storage Account** | `modules/storageaccount-config/` | `Deploy-CdfStorageAccountConfig` |
| **Service Bus** | `modules/servicebus-config/` | `Deploy-CdfServiceBusConfig` |
| **API connections** | `modules/api-connections/` | `Deploy-CdfService` (connection deployment steps) |
| **Service templates** | `templates/` | `New-CdfServiceLogicAppStd`, `New-CdfServiceFunctionApp`, `Update-CdfServiceLogicAppStd` |

## Sample layout

Each sample scope below is self-contained with its own README:

| Sample | Description |
|---|---|
| [`apim/`](apim/) | APIM enterprise policies and API bicep templates (minimal `sample` service type) |
| [`integration/`](integration/) | Storage Account and Service Bus configuration modules with sample configs |
| [`service-templates/`](service-templates/) | Service type templates (Logic App sample with workflows, connections, and cdf-config.json) |

## Composing a shared repository

To create a shared repository for your organisation, combine the scopes you need:

```
my-shared-infra/
├── policies/              ← Copy from apim/ sample
├── resources/             ← Copy from apim/ sample
├── modules/               ← Copy from integration/ sample
├── templates/             ← Copy from service-templates/ sample
└── README.md
```

Then set the environment variable:

```powershell
$env:CDF_SHARED_SOURCE_PATH = './my-shared-infra'
# CDF_SHARED_TEMPLATES_PATH defaults to $CDF_SHARED_SOURCE_PATH/templates
```

Or split across repos for larger organisations:

```powershell
# Shared APIM (for the API platform team)
$env:CDF_SHARED_SOURCE_PATH = './shared-apim'

# Shared integration (for the integration team)
# Commands like Deploy-CdfServiceBusConfig accept -SharedDir parameter
Deploy-CdfServiceBusConfig -SharedDir ./shared-intg
```
