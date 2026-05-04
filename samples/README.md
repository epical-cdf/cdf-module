# CDF Samples

Sample templates, runtime configurations, and workspace setup for the Cloud Deployment Framework.

## Structure

```
samples/
├── templates/          Starter Bicep templates with CDF manifests
│   ├── platform/blank/v1/
│   ├── application/blank/v1/
│   ├── domain/blank/v1/
│   └── service/blank/v1/
│
├── configs/            Sample runtime config instance
│   └── my/01/          Platform "my", instance "01"
│       ├── cdf-runtime.json
│       ├── platform/
│       ├── application/
│       ├── domain/
│       └── service/
│
├── shared/             Shared resources (composable scopes)
│   ├── apim/           APIM enterprise policies and API bicep templates
│   │   ├── policies/
│   │   └── resources/
│   ├── integration/    Storage Account and Service Bus modules
│   │   └── modules/
│   └── service-templates/  Service type templates (Logic App, Function App)
│       └── templates/
│
└── workspace/          Consumer workspace setup
    └── cdf-packages.json
```

## Getting started

### 1. Publish the blank templates

```powershell
# From the samples/templates directory
foreach ($scope in 'platform','application','domain','service') {
    Publish-CdfTemplate -TemplatePath "./$scope/blank/v1"
}
```

### 2. Publish the sample config

```powershell
Publish-CdfConfig -ConfigPath ./samples/configs/my/01
```

### 3. Install packages in a consuming workspace

```powershell
# Copy cdf-packages.json to your workspace root, then:
Install-CdfPackage -ManifestPath ./cdf-packages.json
```

This resolves template and config packages from the registry, downloads them to
the local cache (`~/.cdf/packages/`), and sets the `CDF_INFRA_TEMPLATES_PATH`
and `CDF_INFRA_SOURCE_PATH` environment variables for the deployment commands.

### 4. Deploy

```powershell
# With packages installed, deploy the platform:
Deploy-CdfTemplatePlatform -CdfConfig (Get-CdfConfig my01 my-dev sdc)
```
