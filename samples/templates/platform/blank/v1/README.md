# Blank Platform Template v1

Starter template for the **platform** scope in the CDF deployment chain.

## What it deploys

- A platform resource group with standard CDF tagging.
- A feature-gated **Storage Account** (`enableStorageAccount`).

## Deployment chain

```
platform/blank/v1  ←  you are here
  └─ application/blank/v1
       └─ domain/blank/v1
            └─ service/blank/v1
```

## Provided features

| Feature | Description |
|---|---|
| `enableStorageAccount` | Deploys a general-purpose v2 storage account into the platform resource group. |

## Configuration

See [`config/`](config/) for sample environment and template configuration files.

| File | Purpose |
|---|---|
| `config/environments.json` | Environment definitions (dev, tst, prd) |
| `config/template.platform.json` | Feature flags, access control, and template metadata | 
