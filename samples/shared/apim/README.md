# APIM Shared Scope — Sample

This scope provides the APIM policy hierarchy and API deployment bicep templates consumed by CDFModule APIM commands.

## Directory structure

```
apim/
├── policies/                Enterprise policies (Level 1)
│   ├── sample-global.xml    Global policy for 'sample' service type
│   └── sample-operation.xml Operation policy for 'sample' service type
├── resources/               Bicep templates for API deployment
│   └── api-sample-v1.bicep  Minimal API deployment template
└── README.md
```

## Policy composition (3-level hierarchy)

APIM policies are composed at **build time** by CDFModule into flat XML. The hierarchy:

```
Level 1: Enterprise (service-type)    ← THIS scope: policies/<serviceType>-{global|operation}.xml
  └─ <apim-policy-global /> replaced by:
Level 2: Domain                       ← API repo: domain-policies/<type>_<domain>_<scope>.xml
  └─ <apim-policy-global /> replaced by:
Level 3: API-Specific                 ← API repo: <api>/policies/{scope}-{name}.xml
  └─ <base />                        ← APIM runtime inheritance
```

### Placeholder tags

| Tag | Purpose |
|---|---|
| `<apim-policy-global />` | Replaced with the next level's global policy content (per section) |
| `<apim-policy-operation />` | Replaced with the next level's operation policy content (per section) |
| `<base />` | Standard APIM runtime inheritance (used at Level 3) |

### Token substitution

| Syntax | When | Source |
|---|---|---|
| `#{...}#` | Deploy time (CI/CD) | CDF config values (e.g. `#{PlatformEnvKey}#`, `#{DomainName}#`) |
| `{{...}}` | APIM runtime | APIM named values (often KeyVault-backed) |

## Service types

The `ServiceType` in `cdf-config.json` selects which Level 1 policies to use. This sample includes `sample` as a minimal starting point.

Real implementations typically define types like:
- `internal-v1` — IP filtering only
- `external-v1` — JWT validation + IP filtering
- `internal-v2` / `external-v2` — Full auth with BSP grant checks

## Bicep templates

The `ServiceTemplate` in `cdf-config.json` selects which bicep file from `resources/` to use for API deployment. The sample includes a minimal template.

Real implementations typically include:
- `api-openapi-yaml-v1` — API from OpenAPI YAML spec
- `api-openapi-json-v1` — API from OpenAPI JSON spec
- `api-passthrough-v1` — API without spec import
- `api-internal-openapi-yaml` — Internal API variants

## CDFModule commands using this scope

```powershell
# Build global policy (Level 1 + 2 + 3 → flat XML)
Build-CdfApimGlobalPolicies -SharedPath $env:CDF_SHARED_SOURCE_PATH ...

# Build operation policies
Build-CdfApimOperationPolicies -SharedPath $env:CDF_SHARED_SOURCE_PATH ...

# Build full API deployment package (policies + bicep + parameters)
Build-CdfApimServiceTemplates -CdfConfig $config -SharedPath $env:CDF_SHARED_SOURCE_PATH ...

# Build domain backends
Build-CdfApimDomainBackendTemplates -CdfConfig $config -SharedPath $env:CDF_SHARED_SOURCE_PATH ...

# Build domain products
Build-CdfApimDomainProductTemplates -CdfConfig $config -SharedPath $env:CDF_SHARED_SOURCE_PATH ...
```
