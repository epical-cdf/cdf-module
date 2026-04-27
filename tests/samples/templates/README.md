# Integration template for Epical Cloud Deployment Framework

This repository contains a integration infrastructure as code framework (IaC) for an Azure Landing Zone. The framework is owned and developed by [Epical](https://www.epicalgroup.com/) and uses a concepts of platform and application to be able to lifecycle manage the Azure workload, application landing zone.

![Epical cloud deployment framework](.docs/images/epical-framework-concepts.drawio.svg)

More information regarding the [Cloud Deployment Framework here](.docs/deployment-framework.md).

This repository contains two templates - [Epical Integration Platform - integration v1](platform/integration/v1/README.md) and [Integration Application - blank v1](application/blank/v1/README.md). These two templates builds on the cloud deployment framework concepts for [Platform](.docs/platform-template.md) and [Application](.docs/application-template.md).

## Local deploy of sample template for a target runtime environment

Update template `environment.json` definition files with subcriptionId to use for the `lcl` environment.

- [Platform env definition](platform/blank/v1pub/templates/environments.json)
- [Application env definition](application/blank/v1pub/templates/environments.json)
- [Domain env definition](domain/blank/v1pub/templates/environments.json)

Run a sample deployment. These commands will build the configuration for platform `test01` and application instance `01` with a sample `dom1` domain.

```pwsh


$env:CDF_REGION = 'westeurope'
$env:CDF_PLATFORM_ID = 'test'
$env:CDF_PLATFORM_INSTANCE = '01'
$env:CDF_PLATFORM_ENV_ID = 'lcl'
$env:CDF_APPLICATION_ID = 'app'
$env:CDF_APPLICATION_INSTANCE = '01'
$env:CDF_APPLICATION_ENV_ID = 'lcl'
$env:CDF_DOMAIN_NAME = 'dom1'

$config = Get-CdfConfigPlatform | Deploy-CdfTemplatePlatform
Starting deployment of 'platform-test01lcl-sdc' at 'swedencentral' using subscription [fake-unittest-sub] for runtime environment 'Primary Dev'.
Successfully deployed 'platform-test01lcl-sdc' at 'swedencentral'.
$config = $config | Get-CdfConfigApplication | Deploy-CdfTemplateApplication
Starting deployment of 'application-test01lcl-app01lcl-sdc' at 'swedencentral' using subscription [fake-unittest-sub].
Successfully deployed 'application-test01lcl-app01lcl-sdc' at 'swedencentral'.
$config = $config | Get-CdfConfigApplication | Deploy-CdfTemplateApplication
Starting deployment of 'domain-test01lcl-app01lcl-dom1-sdc' at 'swedencentral' using subscription [fake-unittest-sub].
Successfully deployed 'domain-test01lcl-app01lcl-dom1-sdc' at 'swedencentral'.
```

