Function Get-ConfigService {
  <#
    .SYNOPSIS
    Get configuration for a deployed application instance for given platform instance.

    .DESCRIPTION
    Retrieves the configuration for a deployed application instance from output files stored at SourceDir for the platform instance.

    .PARAMETER CdfConfig
    Instance configuration

    .PARAMETER ServiceName
    Name of the service

    .PARAMETER ServiceSrcPath
    Path to the service source directory. Defaults to current directory.

    .PARAMETER SourceDir
    Path to the platform source directory. Defaults to "./src".

    .INPUTS
    CdfPlatform

    .OUTPUTS
    CdfApplication

    .EXAMPLE
    $config | Get-ConfigService `
        -CdfConfig $config
        -ServiceName "my-service"

    .EXAMPLE
    $config = Get-CdfConfigDomain ...
    Get-ConfigService `
        -CdfConfig $config
        -ServiceName "api-expense" `
        -SourceDir "../cdf-infra/src"

    .LINK
    Get-CdfConfigApplication
    .LINK
    Deploy-CdfTemplateDomain

    #>

  [CmdletBinding()]
  Param(
    [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
    [Object]$CdfConfig,
    [Parameter(Mandatory = $false)]
    [string] $ServiceName = $env:CDF_SERVICE_NAME,
    [Parameter(Mandatory = $false)]
    [string] $ServiceType = $env:CDF_SERVICE_TYPE,
    [Parameter(Mandatory = $false)]
    [string] $ServiceGroup = $env:CDF_SERVICE_GROUP,
    [Parameter(Mandatory = $false)]
    [string] $ServiceTemplate = $env:CDF_SERVICE_TEMPLATE,
    [Parameter(Mandatory = $false)]
    [string] $ServiceSrcPath = ".",
    [Parameter(Mandatory = $false)]
    [switch] $Deployed,
    [Parameter(Mandatory = $false)]
    [string] $SourceDir = $env:CDF_INFRA_SOURCE_PATH ?? './src'
  )

  Process {
    if (!$CdfConfig.Domain.IsDeployed) {
      Write-Warning "Domain config is not deployed, this may cause errors in using the service configuration."
    }

    $sourcePath = "$SourceDir/$($CdfConfig.Platform.Config.platformId)/$($CdfConfig.Platform.Config.instanceId)"
    $platformEnvKey = "$($CdfConfig.Platform.Config.platformId)$($CdfConfig.Platform.Config.instanceId)$($CdfConfig.Platform.Env.nameId)"
    $applicationEnvKey = "$($CdfConfig.Application.Config.applicationId ?? $CdfConfig.Application.Config.templateName)$($CdfConfig.Application.Config.instanceId)$($CdfConfig.Application.Env.nameId)"
    $regionCode = $CdfConfig.Platform.Env.regionCode
    $region = $CdfConfig.Platform.Env.region
    $applicationEnv = $CdfConfig.Application.Env
    $domainName = $CdfConfig.Domain.Config.domainName

    $cdfConfigFile = Join-Path -Path $ServiceSrcPath  -ChildPath 'cdf-config.json'
    if (Test-Path $cdfConfigFile) {
      Write-Verbose "Loading cdf-config.json file"
      $cdfSchemaPath = Join-Path -Path $MyInvocation.MyCommand.Module.ModuleBase -ChildPath 'Resources/Schemas/cdf-service-config.schema.json'
      if (!(Test-Json -SchemaFile $cdfSchemaPath -Path $cdfConfigFile)) {
        Write-Error "Service configuration file did not validate. Please check errors above and correct."
        Write-Error "File path:  $cdfConfigFile"
        return
      }

      $serviceCdfConfig = Get-Content $cdfConfigFile | ConvertFrom-Json -AsHashtable

      $ServiceName = $MyInvocation.BoundParameters.Keys.Contains("ServiceName") ? $ServiceName : $serviceCdfConfig.ServiceDefaults.ServiceName
      $ServiceGroup = $MyInvocation.BoundParameters.Keys.Contains("ServiceGroup") ? $ServiceGroup : $serviceCdfConfig.ServiceDefaults.ServiceGroup
      $ServiceType = $MyInvocation.BoundParameters.Keys.Contains("ServiceType") ? $ServiceType : $serviceCdfConfig.ServiceDefaults.ServiceType
      $ServiceTemplate = $MyInvocation.BoundParameters.Keys.Contains("ServiceTemplate") ? $ServiceTemplate : $serviceCdfConfig.ServiceDefaults.ServiceTemplate

      # Get service configuration from infra config file
      $CdfService = Get-InfraServiceConfig `
        -ServiceName $ServiceName `
        -ServiceType $ServiceType `
        -ServiceGroup $ServiceGroup `
        -ServiceTemplate $ServiceTemplate `
        -ServiceConfigPath "$sourcePath/service/service.$platformEnvKey-$applicationEnvKey-$domainName-$ServiceName-$regionCode.json"
      $CdfService.ConfigSource = "FILE" # Using infra config and/or cdf-config.json file as base
      # TODO: Merge any additional overrides from cdf-config.json here
    }
    else {
      # Get service configuration from infra config file
      $CdfService = Get-InfraServiceConfig `
        -ServiceName $ServiceName `
        -ServiceType $ServiceType `
        -ServiceGroup $ServiceGroup `
        -ServiceTemplate $ServiceTemplate `
        -ServiceConfigPath "$sourcePath/service/service.$platformEnvKey-$applicationEnvKey-$domainName-$ServiceName-$regionCode.json"
    }

    if ($Deployed) {
      if ($CdfConfig.Platform.Config.configStoreType) {
        $regionDetails = [ordered] @{
          region = $region
          code   = $regionCode
          name   = $regionName
        }
        $cdfConfigOutput = Get-ConfigFromStore `
          -CdfConfig $CdfConfig `
          -Scope 'Service' `
          -EnvKey "$platformEnvKey-$applicationEnvKey-$domainName-$ServiceName" `
          -RegionDetails $regionDetails `
          -ErrorAction Continue
      }
      if ($cdfConfigOutput -eq $null -or ($cdfConfigOutput -ne $null -and $cdfConfigOutput.Count -eq 0)) {

        # Get latest deployment result outputs
        $deploymentName = "service-$platformEnvKey-$applicationEnvKey-$($CdfConfig.Domain.Config.domainName)-$ServiceName-$regionCode"

        $azCtx = Get-AzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId
        Write-Verbose "Fetching deployment of '$deploymentName' at '$region' using resourceGroup [$($CdfConfig.Domain.ResourceNames.domainResourceGroupName)] for runtime environment '$($applicationEnv.name)'."

        $result = Get-AzResourceGroupDeployment  `
          -DefaultProfile $azCtx `
          -Name "$deploymentName" `
          -ResourceGroupName $CdfConfig.Domain.ResourceNames.domainResourceGroupName `
          -ErrorAction SilentlyContinue

        While ($result -and -not($result.ProvisioningState -eq 'Succeeded' -or $result.ProvisioningState -eq 'Failed' -or $result.ProvisioningState -eq 'Cancelled')) {
          Write-Host 'Deployment still running...'
          Start-Sleep 30
          $result = Get-AzSubscriptionDeployment -DefaultProfile $azCtx -Name "$deploymentName"
          Write-Verbose $result
        }

        if ($result -and $result.ProvisioningState -eq "Succeeded") {
          # Setup domain definitions
          $CdfService = [ordered] @{
            IsDeployed    = $true
            Tags          = $result.Outputs.serviceTags.Value
            Config        = $result.Outputs.serviceConfig.Value
            Features      = $result.Outputs.serviceFeatures.Value
            ResourceNames = $result.Outputs.serviceResourceNames.Value
            NetworkConfig = $result.Outputs.serviceNetworkConfig.Value
            AccessControl = $result.Outputs.serviceAccessControl.Value
            ConfigSource  = 'DEPLOYMENTOUTPUT'
          }

          # Convert to normalized hashtable
          $CdfService = $CdfService | ConvertTo-Json -depth 10 | ConvertFrom-Json -AsHashtable
        }
        elseif ($result -and ($result.ProvisioningState -eq "Failed" -or $result.ProvisioningState -eq "Cancelled")) {
          Write-Warning "Deployment in invalid state [$($result.ProvisioningState)] for '$deploymentName' at '$region' using subscription [$($azCtx.Subscription.Name)] for runtime environment '$($applicationEnv.name)'."
          Write-Warning "Returning configuration from file, if available."
        }
        else {
          Write-Warning "No deployment found for '$deploymentName' at '$region' using subscription [$($azCtx.Subscription.Name)] for runtime environment '$($applicationEnv.name)'."
          if (Test-Path "cdf-config.json") {
            Write-Warning "Using service defaults in cdf-config.json."
          }
          else {
            Write-Warning "Returning service configuration from file, if available."
          }
        }
      }
      else {
        $cdfConfigOutput.Add("ConfigSource", $CdfConfig.Platform.Config.configStoreType.ToUpper())
        $CdfService = $cdfConfigOutput
      }
    }
    else {
      if ($CdfService.IsDeployed) {
        Write-Warning "Service config on file is a deployed version, use -Deployed to get latest"
      }
    }

    $CdfConfig.Service = $CdfService
    return $CdfConfig
  }
  End {
  }
}

Function Get-InfraServiceConfig {

  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $true)]
    [string] $ServiceName,
    [Parameter(Mandatory = $true)]
    [string] $ServiceType,
    [Parameter(Mandatory = $true)]
    [string] $ServiceGroup,
    [Parameter(Mandatory = $true)]
    [string] $ServiceTemplate,
    [Parameter(Mandatory = $true)]
    [string] $ServiceConfigPath
  )


  # Get service configuration from infra config file
  if (Test-Path -Path $ServiceConfigPath) {
    Write-Verbose "Loading configuration file"
    $cdfService = Get-Content -Path $ServiceConfigPath | ConvertFrom-Json -AsHashtable
    $cdfService.Env = $cdfService.Env ?? [ordered] @{}
    $cdfService.Config.serviceName = $ServiceName
    $cdfService.Config.serviceType = $ServiceType
    $cdfService.Config.serviceGroup = $ServiceGroup
    $cdfService.Config.serviceTemplate = $ServiceTemplate
    $cdfService.ConfigSource = "FILE"
    $cdfService.Features = $cdfService.Features ?? [ordered] @{}
  }
  else {
    Write-Verbose "No infra service configuration file found: $ServiceConfigPath"
    $cdfService = [ordered] @{
      IsDeployed   = $false
      Env          = [ordered] @{}
      Config       = [ordered] @{
        serviceName     = $ServiceName
        serviceType     = $ServiceType
        serviceGroup    = $ServiceGroup
        serviceTemplate = $ServiceTemplate
      }
      Features     = [ordered] @{}
      ConfigSource = "NO-SOURCE"
    }
  }
  return $cdfService
}