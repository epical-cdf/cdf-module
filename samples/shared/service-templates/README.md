# Service Templates Shared Scope — Sample

This scope provides service type templates used by CDFModule to scaffold new services. Templates are resolved from `$env:CDF_SHARED_TEMPLATES_PATH` (defaults to `$CDF_SHARED_SOURCE_PATH/templates`).

## Directory structure

```
service-templates/
├── templates/
│   ├── la-base/                      Logic App Standard base scaffold (required for all LA types)
│   │   ├── host.json                 Azure Functions host configuration
│   │   ├── Artifacts/
│   │   │   ├── Maps/keep.md          BizTalk map files placeholder
│   │   │   └── Schemas/keep.md       XML/JSON schema files placeholder
│   │   └── lib/
│   │       └── custom/
│   │           └── net472/keep.md    Custom connector assemblies placeholder
│   └── la-sample/                    Sample Logic App service type
│       ├── cdf-config.json           Service configuration (ServiceDefaults, Settings, Connections)
│       ├── app.settings.json         Default app settings for the service type
│       ├── storageaccount.config.json   Storage Account resources for this service
│       ├── servicebus.config.json       Service Bus resources for this service
│       └── wf-basic-http/
│           └── workflow.json         HTTP-triggered stateful workflow
└── README.md
```

## How it works

`New-CdfServiceLogicAppStd` (and `New-CdfServiceFunctionApp`) scaffolds a new service by:

1. Copying `la-base/` as the foundation (host.json, Artifacts/, lib/).
2. Overlaying the service type template (e.g. `la-sample/`) with cdf-config.json, workflows, settings.
3. Resolving CDF config parameters and token substitution.
4. Generating `local.settings.json`, `parameters.json`, and `connections.json`.

```powershell
New-CdfServiceLogicAppStd `
    -CdfConfig $config `
    -ServiceName my-new-service `
    -ServiceType la-sample `
    -ServiceGroup starters `
    -ServiceTemplate logicapp-standard `
    -ServicePath ./src/my-new-service
```

## The cdf-config.json

Every service type template has a `cdf-config.json` that defines:

| Section | Purpose |
|---|---|
| `ServiceDefaults` | `ServiceName`, `ServiceGroup`, `ServiceType`, `ServiceTemplate` |
| `ServiceSettings` | Internal config values (Constant, Setting per-env, or Secret) |
| `ExternalSettings` | External dependency config (same value types) |
| `Connections` | Named connections this service requires (e.g. `PlatformServiceBus`, `DomainStorageAccountBlob`) |

### Setting value types

| Type | Description | Example |
|---|---|---|
| `Constant` | Static value with `{{token}}` substitution | Queue names, blob container names |
| `Setting` | Per-purpose values (development/validation/production) | Environment-specific URLs |
| `Secret` | KeyVault reference by identifier | API keys, connection strings |

## Creating custom service types

To add a new service type:

1. Create a directory under `templates/` with the type name (e.g. `la-my-custom`).
2. Add a `cdf-config.json` with the required sections.
3. Add workflow definitions, app settings, and resource configs.
4. Reference in your service: `New-CdfServiceLogicAppStd -ServiceType la-my-custom`.

The `ServiceType` in `cdf-config.json` must match the directory name.
