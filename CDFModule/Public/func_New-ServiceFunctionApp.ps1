Function New-ServiceFunctionApp {
    <#
        .SYNOPSIS
        Creates a new Function App service.

        .DESCRIPTION
        Sets up a Function App project at the specified path based on the provided template.

        .PARAMETER TemplateName
        Specifies the template to use for generating the Function App project.

        .PARAMETER ServiceName
        Specifies the design-time name of the service. The value must be provided either as a parameter or through the environment variable `CDF_SERVICE_NAME`.

        .PARAMETER ServiceGroup
        Specifies the design-time group name for the service. The value can be provided either as a parameter or through the environment variable `CDF_SERVICE_GROUP`.
        If not provided, the value is taken from the template’s configuration file.

        .PARAMETER ServiceType
        Specifies the service type, which defines the target runtime and version (for example, `dotnet-version-8.0` or `node-version-20`).
        The value can be provided either as a parameter or through the environment variable `CDF_SERVICE_TYPE`.
        If not provided, the value is taken from the template’s configuration file.

        .PARAMETER ServiceTemplate
        Specifies the CDF infrastructure template for the service implementation.
        The value can be provided either as a parameter or through the environment variable `CDF_SERVICE_TEMPLATE`.
        If not provided, the value is taken from the template’s configuration file.

        .PARAMETER ServicePath
        Specifies the path where the Function App project will be created. Defaults to the current directory (`.`).

        .PARAMETER Region
        Specifies the region where the platform is deployed. The value must be provided either as a parameter or through the environment variable `CDF_REGION`.
        This is typically provided via an environment variable.

        .PARAMETER PlatformId
        Specifies the name of the platform instance. The value must be provided either as a parameter or through the environment variable `CDF_PLATFORM_ID`.
        This is typically provided via an environment variable.

        .PARAMETER PlatformInstance
        Specifies the specific ID of the platform instance. The value must be provided either as a parameter or through the environment variable `CDF_PLATFORM_INSTANCE`.
        This is typically provided via an environment variable.

        .PARAMETER PlatformEnvId
        Specifies the name of the platform environment configuration. The value must be provided either as a parameter or through the environment variable `CDF_PLATFORM_ENV_ID`.
        This is typically provided via an environment variable.

        .PARAMETER ApplicationId
        Specifies the name of the application instance. The value must be provided either as a parameter or through the environment variable `CDF_APPLICATION_ID`.
        This is typically provided via an environment variable.

        .PARAMETER ApplicationInstance
        Specifies the specific ID of the application instance. The value must be provided either as a parameter or through the environment variable `CDF_APPLICATION_INSTANCE`.
        This is typically provided via an environment variable.

        .PARAMETER ApplicationEnvId
        Specifies the name of the application environment configuration. The value must be provided either as a parameter or through the environment variable `CDF_APPLICATION_ENV_ID`.
        This is typically provided via an environment variable.

        .PARAMETER CdfInfraSourcePath
        Specifies the path to the platform instance source directory. Defaults to `"../../cdf-infra/src"`.

        .PARAMETER CdfSharedPath
        Specifies the path to the shared repository root directory. Defaults to `"../../shared-infra"`.

        .PARAMETER SharedTemplatePath
        Specifies the path to the platform template root directory. Defaults to `"$CdfSharedPath/templates"`.

        .INPUTS
        None.

        .OUTPUTS
        None.

        .EXAMPLE
        New-ServiceFunctionApp -TemplateName "fa-dotnet" -ServiceName "orders"

        Creates a new Function App project named `fa-orders` in the current directory using the `fa-dotnet` template.

        .LINK
        Get-CdfConfigPlatform
        Get-CdfConfigApplication
        Get-CdfConfigDomain
        Update-CdfServiceFunctionApp
    #>

    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
        [Object]$CdfConfig,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $true)]
        [string] $TemplateName,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $Region = $env:CDF_REGION,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $PlatformId = $env:CDF_PLATFORM_ID,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $PlatformInstance = $env:CDF_PLATFORM_INSTANCE,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $PlatformEnvId = $env:CDF_PLATFORM_ENV_ID,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ApplicationId = $env:CDF_APPLICATION_ID,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ApplicationInstance = $env:CDF_APPLICATION_INSTANCE,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ApplicationEnvId = $env:CDF_APPLICATION_ENV_ID,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $DomainName = $env:CDF_DOMAIN_NAME,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ServiceName = $env:CDF_SERVICE_NAME,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ServiceType = $env:CDF_SERVICE_TYPE,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ServiceGroup = $env:CDF_SERVICE_GROUP,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ServiceTemplate = $env:CDF_SERVICE_TEMPLATE,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ServicePath = ".",
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $CdfInfraSourcePath = $env:CDF_INFRA_SOURCE_PATH ?? "../../cdf-infra/src",
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $CdfSharedPath = $env:CDF_SHARED_SOURCE_PATH ?? "../../shared-infra",
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $SharedTemplatePath = $env:CDF_SHARED_TEMPLATES_PATH ?? "$CdfSharedPath/templates"
    )
    if (-not $ServiceName) {
        throw "ServiceName is required. Either pass the parameter or set environment variable 'CDF_SERVICE_NAME'."
    }

    if (!(Test-Path $CdfSharedPath)) {
        Write-Error "Could not find the CDF Infra shared path [$CdfSharedPath]"
        Throw "Could not find the CDF Infra shared path [$CdfSharedPath]"
    }

    if (!(Test-Path $CdfInfraSourcePath)) {
        Write-Error "Could not find the CDF Infra source path [$CdfInfraSourcePath]"
        Throw "Could not find the CDF Infra source path [$CdfInfraSourcePath]"
    }

    if (!(Test-Path $SharedTemplatePath/$TemplateName)) {
        Write-Error "Could not find template [$TemplateName] at the CDF service templates path [$SharedTemplatePath]"
        Write-Error "Please make sure you have the correct path to shared templates and have given a correct template reference."
        Throw "Could not find template [$TemplateName] at the CDF service templates path [$SharedTemplatePath]"
    }

    if (!$CdfConfig) {
        Write-Host "Get Platform Config [$PlatformId$PlatformInstance]"
        $CdfConfig = Get-CdfConfigPlatform `
            -Region $Region `
            -PlatformId $PlatformId `
            -Instance $PlatformInstance `
            -EnvDefinitionId $PlatformEnvId  `
            -SourceDir $CdfInfraSourcePath `
            -Deployed -ErrorAction Continue

        Write-Host "Get Application Config [$ApplicationId$ApplicationInstance]"
        $CdfConfig = Get-CdfConfigApplication `
            -CdfConfig $CdfConfig `
            -Region $Region `
            -ApplicationId $ApplicationId  `
            -InstanceId $ApplicationInstance `
            -EnvDefinitionId $ApplicationEnvId  `
            -SourceDir $CdfInfraSourcePath `
            -Deployed -ErrorAction Continue

        Write-Host "Get Domain Config [$DomainName]"
        $CdfConfig = Get-CdfConfigDomain `
            -CdfConfig $CdfConfig `
            -DomainName $DomainName `
            -SourceDir $CdfInfraSourcePath `
            -Deployed -ErrorAction Continue

    }

    #############################################################
    # Validate and get cdf config for template service
    ############################################################
    $cdfConfigFile = Join-Path -Path $SharedTemplatePath -ChildPath $TemplateName/$TemplateName -AdditionalChildPath 'cdf-config.json'
    $cdfSchemaPath = Join-Path -Path $MyInvocation.MyCommand.Module.ModuleBase -ChildPath 'Resources/Schemas/cdf-service-config.schema.json'
    if (!(Test-Json -SchemaFile $cdfSchemaPath -Path $cdfConfigFile)) {
        Write-Error "Service configuration file did not validate. Please check errors above and correct."
        Write-Error "File path:  $cdfConfigFile"
        return
    }
    $svcConfig = Get-Content -Raw $cdfConfigFile | ConvertFrom-Json -AsHashtable


    #############################################################
    # Copy template for service type
    #############################################################

    $serviceFolderPrefix = 'fa-'
    $ServicePath = "$ServicePath/$($serviceFolderPrefix)$ServiceName"
    # Copy template items to service path
    mkdir $ServicePath
    mkdir "$ServicePath/$($serviceFolderPrefix)$ServiceName"
    mkdir "$ServicePath/$($serviceFolderPrefix)$ServiceName-tests"
    Copy-Item -Recurse `
        -Path "$SharedTemplatePath/$TemplateName/$TemplateName/*" `
        -Destination "$ServicePath/$($serviceFolderPrefix)$ServiceName" `
        -ErrorAction SilentlyContinue
    Rename-Item -Path "$ServicePath/$($serviceFolderPrefix)$ServiceName/$TemplateName.csproj" -NewName "$ServiceName.csproj"

    Copy-Item -Recurse `
        -Path "$SharedTemplatePath/$TemplateName/$TemplateName-tests/*" `
        -Destination "$ServicePath/$($serviceFolderPrefix)$ServiceName-tests" `
        -ErrorAction SilentlyContinue
    Rename-Item -Path "$ServicePath/$($serviceFolderPrefix)$ServiceName-tests/$TemplateName-tests.csproj" -NewName "$ServiceName-tests.csproj"

    $ServicePath = "$ServicePath/$($serviceFolderPrefix)$ServiceName"
    # Prepare (local) app settings
    if (Test-Path "$ServicePath/local.settings.json.template") {
        Write-Host "Loading settings from local.settings.json"
        $appSettings = Get-Content -Raw "$ServicePath/local.settings.json.template" | ConvertFrom-Json -AsHashtable
    }
    else {
        $appSettings = [ordered] @{
            "IsEncrypted" = $false
            "Values"      = [ordered] @{
                "AzureWebJobsStorage" = "UseDevelopmentStorage=true"
            }
        }
    }

    # Use override input parameters if not null
    $ServiceName = $ServiceName ?  $ServiceName : $svcConfig.ServiceDefaults.ServiceName
    $ServiceGroup = $ServiceGroup ? $ServiceGroup : $svcConfig.ServiceDefaults.ServiceGroup
    $ServiceType = $ServiceType ? $ServiceType : $svcConfig.ServiceDefaults.ServiceType
    $ServiceTemplate = $ServiceTemplate ? $ServiceTemplate : $svcConfig.ServiceDefaults.ServiceTemplate

    #############################################################
    # Setup the service CDF Config file from template
    #############################################################
    $svcConfig.ServiceDefaults.ServiceName = $ServiceName
    $svcConfig.ServiceDefaults.ServiceGroup = $ServiceGroup
    $svcConfig.ServiceDefaults.ServiceType = $ServiceType
    $svcConfig.ServiceDefaults.ServiceTemplate = $ServiceTemplate

    $svcConfig | ConvertTo-Json -Depth 5 | Set-Content -Path "$ServicePath/cdf-config.json"

    $appSettings | ConvertTo-Json -Depth 5 | Set-Content -Path "$ServicePath/local.settings.json"
    Write-Debug "Settings: $($appSettings | ConvertTo-Json -Depth 5 | Out-String)"
    Write-Host "Wrote updated local.setttings.json"
    Write-Host "Successfully created function app project. Please change your working directory to $ServicePath to start making changes."
}