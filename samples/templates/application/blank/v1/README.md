# Blank Application Template v1

Starter template for the **application** scope in the CDF deployment chain.

## What it deploys

- An application resource group with standard CDF tagging.
- A feature-gated **Storage Account** (`enableStorageAccount`).

## Deployment chain

```
platform/blank/v1
  └─ application/blank/v1  ←  you are here
       └─ domain/blank/v1
            └─ service/blank/v1
```

## Dependencies

| Template | Required features |
|---|---|
| `platform/blank/v1` | `enableStorageAccount` |

## Provided features

| Feature | Description |
|---|---|
| `enableStorageAccount` | Deploys a general-purpose v2 storage account into the application resource group. |

## Configuration

See [`config/`](config/) for sample environment and template configuration files.

| File | Purpose |
|---|---|
| `config/environments.json` | Environment definitions (dev, tst, prd) with platform cross-reference |
| `config/template.application.json` | Feature flags, access control, and template metadata |
