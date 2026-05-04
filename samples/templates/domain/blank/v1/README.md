# Blank Domain Template v1

Starter template for the **domain** scope in the CDF deployment chain.

## What it deploys

- A domain resource group with standard CDF tagging.
- A feature-gated **Storage Account** (`enableStorageAccount`).

## Deployment chain

```
platform/blank/v1
  └─ application/blank/v1
       └─ domain/blank/v1  ←  you are here
            └─ service/blank/v1
```

## Dependencies

| Template | Required features |
|---|---|
| `platform/blank/v1` | `enableStorageAccount` |
| `application/blank/v1` | `enableStorageAccount` |

## Provided features

| Feature | Description |
|---|---|
| `enableStorageAccount` | Deploys a general-purpose v2 storage account into the domain resource group. |

## Configuration

See [`config/`](config/) for sample template configuration files.

| File | Purpose |
|---|---|
| `config/template.domain.json` | Feature flags, access control, and template metadata |
