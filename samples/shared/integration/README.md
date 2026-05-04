# Integration Shared Scope — Sample

This scope provides reusable Bicep modules for provisioning resources on shared infrastructure that has been deployed by the CDF platform/domain templates.

## Directory structure

```
integration/
├── modules/
│   ├── storageaccount-config/        Storage Account resource provisioning
│   │   ├── main.bicep                Orchestrator: containers, file shares, queues, tables
│   │   ├── storage-containers.bicep  Blob container provisioning
│   │   ├── storage-fileshares.bicep  File share provisioning
│   │   ├── storage-queues.bicep      Storage queue provisioning
│   │   ├── storage-tables.bicep      Storage table provisioning
│   │   └── storageaccount.sample.config.json
│   └── servicebus-config/            Service Bus queue/topic provisioning
│       ├── main.bicep                Orchestrator: queues, topics, subscriptions
│       ├── servicebus-topic-to-queue-subscription.bicep
│       └── servicebus.sample.config.json
└── README.md
```

## How it works

Services declare their infrastructure resource needs in JSON config files alongside `cdf-config.json`:

- **`storageaccount.config.json`** — containers, file shares, queues, tables
- **`servicebus.config.json`** — queues, topics, topic-to-queue subscriptions

CDFModule deploys these configs using the bicep modules in this scope:

```powershell
# Deploy storage account resources for a service
Deploy-CdfStorageAccountConfig -CdfConfig $config -ServiceSrcPath ./src/my-service

# Deploy service bus resources for a service
Deploy-CdfServiceBusConfig -CdfConfig $config -ServiceSrcPath ./src/my-service
```

The modules resolve from `$env:CDF_SHARED_SOURCE_PATH`:
- `$CDF_SHARED_SOURCE_PATH/modules/storageaccount-config/main.bicep`
- `$CDF_SHARED_SOURCE_PATH/modules/servicebus-config/main.bicep`

## Config file reference

### storageaccount.config.json

```json
{
  "scope": "domain",
  "containers": [
    {
      "name": "{{EnvNameId}}-{{ServiceGroup}}-{{ServiceName}}-myblobcontainer",
      "publicAccess": "None",
      "immutableVersioning": false,
      "metadata": {
        "DomainName": "{{DomainName}}",
        "ServiceGroup": "{{ServiceGroup}}",
        "ServiceName": "{{ServiceName}}"
      }
    }
  ],
  "fileShares": [],
  "queues": [],
  "tables": []
}
```

| Field | Description |
|---|---|
| `scope` | Which scope's storage account to target: `platform` or `domain` |
| `containers` | Blob containers with public access and immutable versioning settings |
| `fileShares` | Azure File shares with quota |
| `queues` | Storage queues |
| `tables` | Storage tables |

### servicebus.config.json

```json
{
  "scope": "platform",
  "queues": [
    {
      "name": "{{EnvNameId}}.{{ServiceGroup}}.{{ServiceName}}.myqueuename"
    }
  ],
  "topics": [],
  "topicSubscriptions": [],
  "topicForwards": []
}
```

| Field | Description |
|---|---|
| `scope` | Which scope's Service Bus namespace to target: `platform` |
| `queues` | Service Bus queues |
| `topics` | Service Bus topics |
| `topicSubscriptions` | Subscriptions that forward from a topic to a queue with SQL filter rules |

### Token substitution

Resource names use `{{...}}` tokens resolved at deploy time from the CDF config cascade:

| Token | Example value | Source |
|---|---|---|
| `{{EnvNameId}}` | `dev` | Environment definition |
| `{{DomainName}}` | `demo` | Domain config |
| `{{ServiceName}}` | `la-sample` | Service config |
| `{{ServiceGroup}}` | `starters` | Service config |
