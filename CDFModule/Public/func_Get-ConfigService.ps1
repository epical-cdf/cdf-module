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
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory = $false)]
    [string] $ServiceName = $env:CDF_SERVICE_NAME,
    [Parameter(Mandatory = $false)]
    [switch] $Deployed,
    [Parameter(Mandatory = $false)]
    [string] $SourceDir = $env:CDF_INFRA_SOURCE_PATH ?? './src'
  )

  Begin {
    $haveCdfParameters = $true
    if ([String]::IsNullOrWhiteSpace($ServiceName)) { Write-Error "Missing required CDF Parameter 'ServiceName' or environment variable 'CDF_SERVICE_NAME'"; $haveCdfParameters = $false }
    if (!$haveCdfParameters) {
      throw("Missing required CDF parameters")
    }
  }
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
    $DomainName = $CdfConfig.Domain.Config.domainName

    # Get service configuration
    if (Test-Path "$sourcePath/service/service.$platformEnvKey-$applicationEnvKey-$DomainName-$ServiceName-$regionCode.json" ) {
      Write-Verbose "Loading configuration file"
      $CdfService = Get-Content "$sourcePath/service/service.$platformEnvKey-$applicationEnvKey-$DomainName-$ServiceName-$regionCode.json" | ConvertFrom-Json -AsHashtable
    }
    if (Test-Path "cdf-config.json" ) {
      Write-Verbose "Loading cdf-config.json file"
      $serviceConfig = Get-Content "cdf-config.json" | ConvertFrom-Json -AsHashtable
      $CdfService = [ordered] @{
        IsDeployed = $false
        Env        = [ordered] @{}
        Config     = [ordered] @{
          serviceName     = $serviceConfig.ServiceDefaults.ServiceName
          serviceType     = $serviceConfig.ServiceDefaults.ServiceType
          serviceGroup    = $serviceConfig.ServiceDefaults.ServiceGroup
          serviceTemplate = $serviceConfig.ServiceDefaults.ServiceTemplate
        }
        Features   = [ordered] @{}
        $CdfService.ConfigSource = "FILE"
      }
    }
    else {
      Write-Verbose "No service configuration file found '$ServiceName' with platform key '$platformEnvKey', application key '$applicationEnvKey', domain name '$DomainName' and region code '$regionCode'."
      $CdfService = [ordered] @{
        IsDeployed = $false
        Env        = [ordered] @{}
        Config     = [ordered] @{}
        Features   = [ordered] @{}
        ConfigSource = "NO-SOURCE"
      }
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
            -EnvKey "$platformEnvKey-$applicationEnvKey-$DomainName-$ServiceName" `
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
          ConfigSource = 'DEPLOYMENTOUTPUT'
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
          Write-Warning "Using service defaults in cdf-config.json ."
        }
        else {
          Write-Warning "Returning service configuration from file, if available."
        }
      }
    }
    else{
      $cdfConfigOutput.Add("ConfigSource",$CdfConfig.Platform.Config.configStoreType.ToUpper())
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
