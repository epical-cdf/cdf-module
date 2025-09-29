
Function Get-Config {
 <#
    .SYNOPSIS
    Get configuration for a deployed application instance for given platform instance.

    .DESCRIPTION
    Retrieves the configuration for a deployed application instance from output files stored at SourceDir for the platform instance.
    The command will retrieve configuration for the platform, application, domain and service (if specified).
    The command will look for configuration files in the following order:
    1) Service cdf-config.json file (if present) for service defaults (ServiceName, ServiceGroup, ServiceType, ServiceTemplate)
    2) Platform configuration (Get-ConfigPlatform)
    3) Application configuration (Get-ConfigApplication)
    4) Domain configuration (Get-ConfigDomain) (if DomainName is specified)
    5) Service configuration (Get-ConfigService) (if ServiceName is specified)
  
    .PARAMETER Region
    Azure region where the platform is deployed.
    Defaults to value of env var CDF_REGION.

    .PARAMETER PlatformId
    Platform identifier.  
    Defaults to value of env var CDF_PLATFORM_ID.
    Required if env var CDF_PLATFORM_ID is not set.
    Example: "axlint"

    .PARAMETER PlatformInstance
    Platform instance identifier.
    Defaults to value of env var CDF_PLATFORM_INSTANCE.
    Required if env var CDF_PLATFORM_INSTANCE is not set.
    Example: "01"
  
    .PARAMETER PlatformEnvId
    Platform environment definition identifier.
    Defaults to value of env var CDF_PLATFORM_ENV_ID.
    Optional. If not specified, the default environment definition for the platform instance will be used.
    Example: "axl-tst"

    .PARAMETER ApplicationId
    Application identifier.  
    Defaults to value of env var CDF_APPLICATION_ID.
    Required if env var CDF_APPLICATION_ID is not set.
    Example: "intg"

    .PARAMETER ApplicationInstance
    Application instance identifier.
    Defaults to value of env var CDF_APPLICATION_INSTANCE.
    Required if env var CDF_APPLICATION_INSTANCE is not set.
    Example: "01"

    .PARAMETER ApplicationEnvId
    Application environment definition identifier.
    Defaults to value of env var CDF_APPLICATION_ENV_ID.
    Optional. If not specified, the default environment definition for the application instance will be used.
    Example: "axl-uat"

    .PARAMETER DomainName
    Name of the domain to retrieve configuration for.
    Defaults to value of env var CDF_DOMAIN_NAME.
    Optional. If not specified, domain configuration will not be retrieved.
    Example: "b2b"

    .PARAMETER ServiceName
    Name of the service to retrieve configuration for.
    Defaults to cdf-config.json ServiceDefaults.ServiceName if present.
    Or defaults to value of env var CDF_SERVICE_NAME.
    Optional. If not specified, service configuration will not be retrieved.
    Example: "svc01"

    .PARAMETER ServiceType
    Service type to use if service configuration is not found in a configuration file.
    Defaults to cdf-config.json ServiceDefaults.ServiceType if present.
    Or defaults to value of env var CDF_SERVICE_TYPE.
    Example: "javascript" "donnet", "la-sample"

    .PARAMETER ServiceGroup
    Service group to use if service configuration is not found in a configuration file.
    Defaults to cdf-config.json ServiceDefaults.ServiceGroup if present.
    Or defaults to value of env var CDF_SERVICE_GROUP.
    Example: "api", "worker", "core"

    .PARAMETER ServiceTemplate
    Service template to use if service configuration is not found in a configuration file.
    Defaults to cdf-config.json ServiceDefaults.ServiceTemplate if present.
    Or defaults to value of env var CDF_SERVICE_TEMPLATE.
    Example: "logicapp-standard-v1", "containerapp-api-v1", "functionapp-api-v1"

    .PARAMETER Deployed
    Switch to indicate that only deployed configuration should be retrieved.
    If specified, the command will return a warning if the platform, application, domain or service
    is not marked as deployed in the configuration files.
    Defaults to $false.

    .PARAMETER ServiceSrcPath
    Path to the service source directory. Defaults to current directory.

    .PARAMETER CdfInfraTemplatePath
    Path to the cdf-infra templates directory.
    Defaults to "../../cdf-infra".

    .PARAMETER CdfInfraSourcePath
    Path to the cdf-infra source directory.
    Defaults to "../../cdf-infra/src".

    .PARAMETER CdfSharedPath
    Path to the shared-infra source directory.
    Defaults to "../../shared-infra".

    .PARAMETER SharedTemplatePath
    Path to the shared-infra templates directory.
    Defaults to "$CdfSharedPath/templates". 

    .INPUTS
    None.

    .OUTPUTS
    CdfConfiguration

    .EXAMPLE
    Get-CdfConfig -Deployed

    .EXAMPLE
    $config = Get-Config `
        -Region "northeurope" `
        -PlatformId "axlint" `
        -PlatformInstance "01" `
        -PlatformEnvId "axl-tst" `
        -ApplicationId "intg" `
        -ApplicationInstance "01" `
        -ApplicationEnvId "axl-uat" `
        -DomainName "b2b" `
        -ServiceName "svc01" `
        -Deployed

    .LINK
    Show-CdfConfig

    #>

  [CmdletBinding()]
  Param(

    [Parameter(Mandatory = $false)]
    [string] $Region = $env:CDF_REGION,
    [Parameter(Mandatory = $false)]
    [string] $PlatformId = $env:CDF_PLATFORM_ID,
    [Parameter(Mandatory = $false)]
    [string] $PlatformInstance = $env:CDF_PLATFORM_INSTANCE,
    [Parameter(Mandatory = $false)]
    [string] $PlatformEnvId = $env:CDF_PLATFORM_ENV_ID,
    [Parameter(Mandatory = $false)]
    [string] $ApplicationId = $env:CDF_APPLICATION_ID,
    [Parameter(Mandatory = $false)]
    [string] $ApplicationInstance = $env:CDF_APPLICATION_INSTANCE,
    [Parameter(Mandatory = $false)]
    [string] $ApplicationEnvId = $env:CDF_APPLICATION_ENV_ID,
    [Parameter(Mandatory = $false)]
    [string] $DomainName = $env:CDF_DOMAIN_NAME,
    [Parameter(Mandatory = $false)]
    [string] $ServiceName = $env:CDF_SERVICE_NAME,
    [Parameter(Mandatory = $false)]
    [string] $ServiceType = $env:CDF_SERVICE_TYPE,
    [Parameter(Mandatory = $false)]
    [string] $ServiceGroup = $env:CDF_SERVICE_GROUP,
    [Parameter(Mandatory = $false)]
    [string] $ServiceTemplate = $env:CDF_SERVICE_TEMPLATE,
    [Parameter(Mandatory = $false)]
    [switch] $Deployed,
    [Parameter(Mandatory = $false)]
    [string] $ServiceSrcPath = ".",
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory = $false)]
    [string] $CdfInfraTemplatePath = $env:CDF_INFRA_TEMPLATES_PATH ?? "../../cdf-infra",
    [Parameter(Mandatory = $false)]
    [string] $CdfInfraSourcePath = $env:CDF_INFRA_SOURCE_PATH ?? "../../cdf-infra/src",
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory = $false)]
    [string] $CdfSharedPath = $env:CDF_SHARED_SOURCE_PATH ?? "../../shared-infra",
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory = $false)]
    [string] $SharedTemplatePath = $env:CDF_SHARED_TEMPLATES_PATH ?? "$CdfSharedPath/templates"
  )

  # Parameters
  $platformKey = "$PlatformId$PlatformInstance"
  $applicationKey = "$ApplicationId$ApplicationInstance"

  $sourcePath = "$CdfInfraSourcePath/$PlatformId/$PlatformInstance"
  if (!(Test-Path -Path $sourcePath )) {
    Write-Error -Message "Cannot find the instance configuration and give location [$sourcePath]"
    Write-Error -Message 'Correct parameter "-CdfInfraSourcePath" or env var "$env:CDF_INFRA_SOURCE_PATH" is correct'
    throw "Cannot find the instance configuration and give location [$sourcePath]"
  }

  $cdfModule = Get-Module -Name CDFModule
  if (!$cdfModule) {
    Write-Error "Unable get information for the CDFModule loaded. That's weird, how did you get to run this command?"
    Write-Error "Please check your setup and make sure CDFModule is loaded."
    throw "Unable get information for the CDFModule loaded. That's weird, how did you get to run this command?"
  }
  if ($cdfModule.Length -and ($cdfModule.Length -gt 1)) {
    Write-Error "You have multiple CDFModule versions loaded."
    Write-Error "Please remove all modules and reload the version you want to use. [Remove-Module CDFModule -Force]"
    throw "You have multiple CDFModule versions loaded."
  }

  # Use "cdf-config.json" if available, but if parameter is bound it overrides / takes precendens
  $cdfConfigFile = Join-Path -Path $ServiceSrcPath  -ChildPath 'cdf-config.json'
  if (Test-Path $cdfConfigFile) {
    $cdfSchemaPath = Join-Path -Path $MyInvocation.MyCommand.Module.ModuleBase -ChildPath 'Resources/Schemas/cdf-service-config.schema.json'
    if (!(Test-Json -SchemaFile $cdfSchemaPath -Path $cdfConfigFile)) {
      Write-Error "Service configuration file did not validate. Please check errors above and correct."
      Write-Error "File path:  $cdfConfigFile"
      return
    }
    $svcConfig = Get-Content -Raw $cdfConfigFile | ConvertFrom-Json -AsHashtable

    $ServiceName = $MyInvocation.BoundParameters.Keys.Contains("ServiceName") ? $ServiceName : $svcConfig.ServiceDefaults.ServiceName
    $ServiceGroup = $MyInvocation.BoundParameters.Keys.Contains("ServiceGroup") ? $ServiceGroup : $svcConfig.ServiceDefaults.ServiceGroup
    $ServiceType = $MyInvocation.BoundParameters.Keys.Contains("ServiceType") ? $ServiceType : $svcConfig.ServiceDefaults.ServiceType
    $ServiceTemplate = $MyInvocation.BoundParameters.Keys.Contains("ServiceTemplate") ? $ServiceTemplate : $svcConfig.ServiceDefaults.ServiceTemplate
  }

  if ($Deployed) {
    $config = Get-ConfigPlatform `
      -Region $Region `
      -PlatformId $PlatformId `
      -Instance $PlatformInstance `
      -EnvDefinitionId $PlatformEnvId  `
      -SourceDir $CdfInfraSourcePath `
      -Deployed -ErrorAction SilentlyContinue

  }
  else {
    $config = Get-ConfigPlatform `
      -Region $Region `
      -PlatformId $PlatformId `
      -Instance $PlatformInstance `
      -EnvDefinitionId $PlatformEnvId  `
      -SourceDir $CdfInfraSourcePath `
      -ErrorAction SilentlyContinue
  }

  if ($Deployed) {
    $config = Get-ConfigApplication `
      -CdfConfig $config `
      -ApplicationId $ApplicationId  `
      -InstanceId $ApplicationInstance `
      -EnvDefinitionId $ApplicationEnvId  `
      -SourceDir $CdfInfraSourcePath `
      -WarningAction:SilentlyContinue `
      -Deployed -ErrorAction Stop
  }
  else {
    $config = Get-ConfigApplication `
      -CdfConfig $config `
      -Region $Region `
      -ApplicationId $ApplicationId  `
      -InstanceId $ApplicationInstance `
      -EnvDefinitionId $ApplicationEnvId  `
      -SourceDir $CdfInfraSourcePath `
      -WarningAction:SilentlyContinue `
      -ErrorAction Stop
  }

  if ($DomainName) {


    if ($Deployed) {
      $config = Get-ConfigDomain `
        -CdfConfig $config `
        -DomainName $DomainName `
        -SourceDir $CdfInfraSourcePath `
        -WarningAction:SilentlyContinue `
        -Deployed -ErrorAction Stop

    }
    else {
      $config = Get-ConfigDomain `
        -CdfConfig $config `
        -DomainName $DomainName `
        -SourceDir $CdfInfraSourcePath `
        -WarningAction:SilentlyContinue `
        -ErrorAction Stop
      # Continue Domain configuration
    }

    if ($ServiceName -and $Deployed -and $config.Domain.IsDeployed) {
      $config = Get-ConfigService `
        -CdfConfig $config `
        -ServiceName $ServiceName `
        -ServiceSrcPath $ServiceSrcPath `
        -SourceDir $CdfInfraSourcePath `
        -WarningAction:Continue `
        -Deployed -ErrorAction Stop
    }
  }
  return $config
}
