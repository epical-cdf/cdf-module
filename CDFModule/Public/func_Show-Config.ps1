Function Show-Config {
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
    [switch] $Load,
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

  $templatePathPlatform = "$CdfInfraTemplatePath/service/$($CdfConfig.Domain.Config.templateName)/$($CdfConfig.Domain.Config.templateVersion)"
  $templatePathApplication = "$CdfInfraTemplatePath/service/$($CdfConfig.Domain.Config.templateName)/$($CdfConfig.Domain.Config.templateVersion)"
  $templatePathDomain = "$CdfInfraTemplatePath/service/$($CdfConfig.Domain.Config.templateName)/$($CdfConfig.Domain.Config.templateVersion)"
  
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

  $outputInstallation = [ordered] @{
    "Infra Template Path"  = $CdfInfraTemplatePath
    "Infra Source Path"    = $CdfInfraSourcePath
    "Shared Source Path"   = $CdfSharedPath
    "Shared Template Path" = $SharedTemplatePath
    "PowerShell Version"   = $PSVersionTable.PSVersion
    "CDF Version"          = $cdfModule.Version.ToString() + ($cdfModule.PrivateData.PSData.Prerelease ? "-" + $cdfModule.PrivateData.PSData.Prerelease :'')
  }
  
  Write-Host "CDF" -ForegroundColor Blue -NoNewLine
  Write-Host (" v" + $($cdfModule.Version)) -ForegroundColor White -NoNewLine
  if ($cdfModule.PrivateData.PSData.Prerelease ) {
    Write-Host ("-" + $cdfModule.PrivateData.PSData.Prerelease) -ForegroundColor White -NoNewLine
  }
  Write-Host "PowerShell " -ForegroundColor Blue -NoNewLine
  Write-Host "v$($PSVersionTable.PSVersion)" -ForegroundColor White -NoNewLine

  Write-Host ""
  Write-Host -NoNewline "-------- | Installation | ------------------------------------------"
  $outputInstallation | Format-Table -HideTableHeaders
  

  # Platform
  $outputPlatform = [ordered] @{
    "Key"               = $platformKey
    "Env Definition Id" = $PlatformEnvId
    "Region"            = $Region
  }

  if ($Load -or $Deployed) {   
    $config = Get-ConfigPlatform `
      -Region $Region `
      -PlatformId $PlatformId `
      -Instance $PlatformInstance `
      -EnvDefinitionId $PlatformEnvId  `
      -SourceDir $CdfInfraSourcePath `
      -ErrorAction SilentlyContinue
    
    $platformEnvKey = "$platformKey$($CdfConfig.Platform.Env.nameId)"
    
    # Continue Platform configuration
    $outputPlatform["Region Code"] = $config.Platform.Env.regionCode
    $outputPlatform["Region Name"] = $config.Platform.Env.regionName
    $outputPlatform["Env Name Id"] = $config.Platform.Env.nameId
    $outputPlatform["Env Name"] = $config.Platform.Env.name
    $outputPlatform["Env Desc"] = $config.Platform.Env.description
    $outputPlatform["TenantId"] = $config.Platform.Env.tenantId
    $outputPlatform["SubscriptionId"] = $config.Platform.Env.subscriptionId

  }

  if ($Deployed) {
    $config = Get-ConfigPlatform `
      -Region $Region `
      -PlatformId $PlatformId `
      -Instance $PlatformInstance `
      -EnvDefinitionId $PlatformEnvId  `
      -SourceDir $CdfInfraSourcePath `
      -Deployed -ErrorAction SilentlyContinue
      
    if ($config -and $config.Platform -and $config.Platform.ResourceNames) {  
      # Continue Platform runtime configuration
      $config.Platform.ResourceNames.Keys `
      | Where-Object -FilterScript { $_.Contains('ResourceGroupName') } `
      | ForEach-Object -Process { $outputPlatform["Resource Group"] = $config.Platform.ResourceNames[$_] }
    }
  }
  Write-Host -NoNewline "-------- | Platform | ----------------------------------------------"
  $outputPlatform | Format-Table -HideTableHeaders
  
  # Application
  $outputApplication = [ordered] @{
    "Key"               = $applicationKey
    "Env Definition Id" = $ApplicationEnvId
    "Region"            = $Region
  }
  
  if ($Load -or $Deployed) {
    $config = Get-ConfigApplication `
      -CdfConfig $config `
      -Region $Region `
      -ApplicationId $ApplicationId  `
      -InstanceId $ApplicationInstance `
      -EnvDefinitionId $ApplicationEnvId  `
      -SourceDir $CdfInfraSourcePath `
      -WarningAction:SilentlyContinue `
      -ErrorAction Stop 
 
    $applicationEnvKey = "$applicationKey$($CdfConfig.Application.Env.nameId)"

    # Continue Application configuration
    $outputApplication["Region Code"] = $config.Application.Env.regionCode
    $outputApplication["Region Name"] = $config.Application.Env.regionName
    $outputApplication["Env Name Id"] = $config.Application.Env.nameId
    $outputApplication["Env Name"] = $config.Application.Env.name
    $outputApplication["Env Desc"] = $config.Application.Env.description
  }
  if ($Deployed) {
    $config = Get-ConfigApplication `
      -CdfConfig $config `
      -Region $Region `
      -ApplicationId $ApplicationId  `
      -InstanceId $ApplicationInstance `
      -EnvDefinitionId $ApplicationEnvId  `
      -SourceDir $CdfInfraSourcePath `
      -WarningAction:SilentlyContinue `
      -Deployed -ErrorAction Stop
      
    if ($config -and $config.Application -and $config.Application.ResourceNames) {  
      # Continue Application runtime configuration
      $config.Application.ResourceNames.Keys `
      | Where-Object -FilterScript { $_.Contains('ResourceGroupName') } `
      | ForEach-Object -Process { $outputApplication["Resource Group"] = $config.Application.ResourceNames[$_] }
    }
  }
  Write-Host -NoNewline "-------- | Application | -------------------------------------------"
  $outputApplication | Format-Table -HideTableHeaders
  
  if ($DomainName) {

    # Domain
    $outputDomain = [ordered] @{
      "Name" = $DomainName ?? ""
    }

    if ($Load -or $Deployed) {
      $config = Get-ConfigDomain `
        -CdfConfig $config `
        -DomainName $DomainName `
        -SourceDir $CdfInfraSourcePath `
        -WarningAction:SilentlyContinue `
        -ErrorAction Stop
      # Continue Domain configuration
    }

    if ($Deployed) {
      $config = Get-ConfigDomain `
        -CdfConfig $config `
        -DomainName $DomainName `
        -SourceDir $CdfInfraSourcePath `
        -WarningAction:SilentlyContinue `
        -Deployed -ErrorAction Stop
      # Continue Domain runtime configuration
      $config.Domain.ResourceNames.Keys `
    | Where-Object -FilterScript { $_.Contains('ResourceGroupName') } `
    | ForEach-Object -Process { $outputDomain["Resource Group"] = $config.Domain.ResourceNames[$_] }
    }
    Write-Host -NoNewline "-------- | Domain | ------------------------------------------------"
    $outputDomain | Format-Table -HideTableHeaders
  
    # Service
    $outputService = [ordered] @{
      "Name"     = $ServiceName ?? ""
      "Group"    = $ServiceGroup ?? ""
      "Type"     = $ServiceType ?? ""
      "Template" = $ServiceTemplate ?? ""
    }

    if ($ServiceName -and $Deployed) {
      $config = Get-ConfigService `
        -CdfConfig $config `
        -ServiceName $ServiceName `
        -SourceDir $CdfInfraSourcePath `
        -WarningAction:SilentlyContinue `
        -Deployed -ErrorAction Stop

      # Continue Service runtime configuration
      if ($config.Service.ResourceNames.logicAppName) {
        # $outputService["Logic App Id"] = $config.Service.ResourceNames.logicAppIdentity
        $outputService["Logic App Name"] = $config.Service.ResourceNames.logicAppName
      }
    }
    Write-Host -NoNewline "-------- | Service | ------------------------------------------------"
    $outputService | Format-Table -HideTableHeaders

      
  }
}
