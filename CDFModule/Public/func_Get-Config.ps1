Function Get-Config {
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

  if ($DomainName -and $config.Application.IsDeployed) {


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
        -SourceDir $CdfInfraSourcePath `
        -WarningAction:Continue `
        -Deployed -ErrorAction Stop
    }
  }
  return $config
}
