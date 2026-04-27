# Blank Service Template v1

Starter template for the **service** scope in the CDF deployment chain.

## What it deploys

- A placeholder Network Security Group (NSG) resource.
- References the domain-level storage account as an existing resource.

## Deployment chain

```
platform/blank/v1
  └─ application/blank/v1
       └─ domain/blank/v1
            └─ service/blank/v1  ←  you are here
```

## Dependencies

| Template | Required features |
|---|---|
| `platform/blank/v1` | — |
| `application/blank/v1` | `enableStorageAccount` |
| `domain/blank/v1` | `enableStorageAccount` |

## Provided features

None. This is a leaf template in the deployment chain.
