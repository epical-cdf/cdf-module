Function Update-ServiceFunctionApp {
    <#
        .SYNOPSIS
        Updates a function app service.

        .DESCRIPTION
        Updates a function app service.

        .PARAMETER UseCS
        Specifies a switch whether to include connection strings in settings file.

        .PARAMETER ServiceName
        Specifies the design-time name of the service. The value can be provided either as a parameter or through the environment variable `CDF_SERVICE_NAME`.
        If not provided, the value is taken from the function’s cdf-config file.

        .PARAMETER ServiceGroup
        Specifies the design-time group name for the service. The value can be provided either as a parameter or through the environment variable `CDF_SERVICE_GROUP`.
        If not provided, the value is taken from the function’s cdf-config file.

        .PARAMETER ServiceType
        Specifies the service type, which defines the target runtime and version (for example, `dotnet-version-8.0` or `node-version-20`).
        The value can be provided either as a parameter or through the environment variable `CDF_SERVICE_TYPE`.
        If not provided, the value is taken from the function’s cdf-config file.

        .PARAMETER ServiceTemplate
        Specifies the CDF infrastructure template for the service implementation.
        The value can be provided either as a parameter or through the environment variable `CDF_SERVICE_TEMPLATE`.
        If not provided, the value is taken from the function’s cdf-config file.

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

        .INPUTS
        None.

        .OUTPUTS
        None.

        .EXAMPLE
        Update-CdfServiceFunctionApp -UseCS

        .LINK
        Get-CdfConfig
        Deploy-CdfService

      #>

    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
        [Object]$CdfConfig,
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
        [Parameter(Mandatory = $false)]
        [switch] $UseCS
    )

    if (!(Test-Path $CdfInfraSourcePath)) {
        Write-Error "Could not find the CDF Infra source path [$CdfInfraSourcePath]"
        Throw "Could not find the CDF Infra source path [$CdfInfraSourcePath]"
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
    $cdfConfigFile = Join-Path -Path $ServicePath -ChildPath 'cdf-config.json'
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

    # Prepare (local) app settings
    if (Test-Path "$ServicePath/local.settings.json") {
        Write-Host "Loading settings from local.settings.json"
        $appSettings = Get-Content -Raw "$ServicePath/local.settings.json" | ConvertFrom-Json -AsHashtable
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
    $CdfConfig.Service = [ordered] @{
        "Config" = @{
            ServiceName     = $ServiceName
            ServiceGroup    = $ServiceGroup
            ServiceType     = $ServiceType
            ServiceTemplate = $ServiceTemplate
        }
        "Tags"   = @{
            BuildRun         = "456123789"
            BuildRepo        = "local"
            BuildBranch      = "local"
            BuildCommit      = "c3b2a1"
            TemplateEnv      = $CdfConfig.Domain.Tags.TemplateEnv
            TemplateName     = $CdfConfig.Domain.Tags.TemplateName
            TemplateVersion  = $CdfConfig.Domain.Tags.TemplateVersion
            TemplateInstance = $CdfConfig.Domain.Tags.TemplateInstance
        }
    }

    $svcConfig.ServiceDefaults.ServiceName = $ServiceName
    $svcConfig.ServiceDefaults.ServiceGroup = $ServiceGroup
    $svcConfig.ServiceDefaults.ServiceType = $ServiceType
    $svcConfig.ServiceDefaults.ServiceTemplate = $ServiceTemplate

    $svcConfig | ConvertTo-Json -Depth 5 | Set-Content -Path "$ServicePath/cdf-config.json"
    if($UseCS){
    $appSettings.Values = $CdfConfig | Get-CdfServiceConfigSettings -UpdateSettings $appSettings.Values -SecretValue -UseCS
    Write-Warning "Connection String variables starting with 'CON' are only available for local development."
    Write-Warning "Please run the command again without -useCS switch to get list of variables without connection string."
    }
    else {
    $appSettings.Values = $CdfConfig | Get-CdfServiceConfigSettings -UpdateSettings $appSettings.Values -SecretValue
    }
    $appSettings | ConvertTo-Json -Depth 5 | Set-Content -Path "local.settings.json"
    Write-Debug "Settings: $($appSettings | ConvertTo-Json -Depth 5 | Out-String)"
    Write-Host "Wrote updated local.setttings.json"
}