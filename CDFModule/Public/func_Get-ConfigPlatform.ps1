Function Get-ConfigPlatform {
  <#
    .SYNOPSIS
    Get configuration for a deployed platform instance

    .DESCRIPTION
    Retrieves the configuration for a deployed platform instance from output files stored at SourceDir.

    .PARAMETER PlatformId
    Name of the platform instance

    .PARAMETER InstanceId
    Specific id of the platform instance

    .PARAMETER EnvDefinitionId
    Name of the environment configuration.

    .PARAMETER SourceDir
    Path to the platform source directory. Defaults to "./src".

    .INPUTS
    CdfPlatform

    .OUTPUTS
    CdfApplication

    .EXAMPLE
    Get-CdfConfigPlatform `
      -Region "swedencentral" `
      -PlatformId "capim" `
      -InstanceId "01" `
      -EnvDefinitionId "intg-dev"

    .EXAMPLE
    Get-CdfConfigPlatform `
        -Region "swedencentral" `
        -PlatformId "capim" `
        -InstanceId "01" `
        -EnvDefinitionId "intg-dev" `
        -SourceDir "../cdf-infra/src"

    .LINK
    Get-CdfConfigApplication
    .LINK
    Deploy-CdfTemplatePlatform

    #>

  [CmdletBinding()]
  Param(
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory = $false)]
    [string] $Region = $env:CDF_REGION,
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory = $false)]
    [string] $PlatformId = $env:CDF_PLATFORM_ID,
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory = $false)]
    [string] $InstanceId = $env:CDF_PLATFORM_INSTANCE,
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory = $false)]
    [string] $EnvDefinitionId = $env:CDF_PLATFORM_ENV_ID,
    [Parameter(Mandatory = $false)]
    [switch] $Deployed,
    [Parameter(Mandatory = $false)]
    [string] $SourceDir = $env:CDF_INFRA_SOURCE_PATH ?? './src'
  )
  Begin {
    $haveCdfParameters = $true
    if ([String]::IsNullOrWhiteSpace($Region)) { Write-Error "Missing required CDF Parameter 'Region' or environment variable 'CDF_REGION'"; $haveCdfParameters = $false }
    if ([String]::IsNullOrWhiteSpace($PlatformId)) { Write-Error "Missing required CDF Parameter 'PlatformId' or environment variable 'CDF_PLATFORM_ID'"; $haveCdfParameters = $false }
    if ([String]::IsNullOrWhiteSpace($InstanceId)) { Write-Error "Missing required CDF Parameter 'InstanceId' or environment variable 'CDF_PLATFORM_INSTANCE'"; $haveCdfParameters = $false }
    if ([String]::IsNullOrWhiteSpace($EnvDefinitionId)) { Write-Error "Missing required CDF Parameter 'EnvDefinitionId' or environment variable 'CDF_PLATFORM_ENV_ID'"; $haveCdfParameters = $false }
    if (!$haveCdfParameters) {
      throw("Missing required CDF parameters")
    }

    # Fetch definitions
    $sourcePath = "$SourceDir/$PlatformId/$InstanceId"
    $platformEnvs = Get-Content -Raw "$sourcePath/platform/environments.json" | ConvertFrom-Json -AsHashtable
    $regionCodes = Get-Content -Raw "$sourcePath/platform/regioncodes.json" | ConvertFrom-Json -AsHashtable
    $regionNames = Get-Content -Raw "$sourcePath/platform/regionnames.json" | ConvertFrom-Json -AsHashtable

    # Setup deployment variables from configuration

    $platformEnv = $platformEnvs[$EnvDefinitionId]
    $regionCode = $regionCodes[$Region.ToLower()]
    $regionName = $regionNames[$regionCode]

    $platformEnvKey = "$PlatformId$InstanceId$($platformEnv.nameId)"
  }
  Process {
    # Get platform configuration

    #TODO: Replace with release package
    $platformConfigFile = "$sourcePath/platform/platform.$platformEnvKey-$regionCode.json"
    if (Test-Path $platformConfigFile) {
      Write-Verbose "Loading configuration from output json"
      $CdfPlatform = Get-Content  $platformConfigFile | ConvertFrom-Json -AsHashtable
      $CdfPlatform.Env = $platformEnv
    }
    else {
      Write-Error "Platform configuration file not found. Path: $platformConfigFile"
      Throw "Platform configuration file not found. Path: $platformConfigFile"
    }

    if ($CdfPlatform.IsDeployed) {
      Write-Warning "Platform config on file is a deployed version, use -Deployed to get latest"
    }

    if ($Deployed) {

      if ($CdfPlatform.Config.configStoreType.ToUpper() -ne 'DEPLOYMENTOUTPUT') {
        $regionDetails = [ordered] @{
          region = $region
          code   = $regionCode
          name   = $regionName
        }
        $cdfConfigOutput = Get-ConfigFromStore `
          -CdfConfig $CdfPlatform `
          -Scope 'Platform' `
          -EnvKey $platformEnvKey `
          -RegionDetails $regionDetails `
          -ErrorAction Continue
      }

      if ($CdfPlatform.Config.configStoreType.ToUpper() -eq 'DEPLOYMENTOUTPUT' -or ($cdfConfigOutput -ne $null -and $cdfConfigOutput.Count -eq 0)) {
        # Get latest deployment result outputs
        $deploymentName = "platform-$platformEnvKey-$regionCode"

        $azCtx = Get-AzureContext -SubscriptionId $CdfPlatform.Env.subscriptionId
        Write-Verbose "Fetching deployment of '$deploymentName' at '$region' using subscription [$($azCtx.Subscription.Name)] for runtime environment '$($platformEnv.name)'."

        $result = Get-AzSubscriptionDeployment  `
          -DefaultProfile $azCtx `
          -Name "$deploymentName" `
          -ErrorAction SilentlyContinue

        if ($result -and $result.ProvisioningState -eq 'Succeeded') {
          # Setup platform definitions
          $CdfPlatform = [ordered] @{
            IsDeployed    = $true
            Env           = $result.Outputs.platformEnv.Value
            Tags          = $result.Outputs.platformTags.Value
            Config        = $result.Outputs.platformConfig.Value
            Features      = $result.Outputs.platformFeatures.Value
            ResourceNames = $result.Outputs.platformResourceNames.Value
            NetworkConfig = $result.Outputs.platformNetworkConfig.Value
            AccessControl = $result.Outputs.platformAccessControl.Value
          }
          # Convert to normalized hashtable
          $CdfPlatform = $CdfPlatform | ConvertTo-Json -depth 10 | ConvertFrom-Json -AsHashtable
        }
        elseif ($result -and $result.ProvisioningState -ne 'Succeeded') {
          Write-Warning "Deployment state is [$($result.ProvisioningState)] for '$deploymentName' at '$region' using subscription [$($azCtx.Subscription.Name)] for runtime environment '$($applicationEnv.name)'."
          Write-Warning "Returning configuration from file."
        }
        else {
          Write-Warning "No deployment found for '$deploymentName' at '$region' using subscription [$($azCtx.Subscription.Name)] for runtime environment '$($platformEnv.name)'."
          Write-Warning "Returning configuration from file."
        }
      }
      else {
        $CdfPlatform = $cdfConfigOutput
      }
    }

    if ($CdfPlatform.Env) {

      # SpokeNetworkConfig is not yet included in platform template output
      if (Test-Path "$sourcePath/platform/spokeconfig.$platformEnvKey-$regionCode.json") {
        Write-Verbose "Loading enterprise spoke network configuration"
        $CdfPlatform.SpokeNetworkConfig = Get-Content "$sourcePath/platform/spokeconfig.$platformEnvKey-$regionCode.json" | ConvertFrom-Json -AsHashtable
      }
      # Update platform configuration with current settings
      $CdfPlatform.Env.region = $region
      $CdfPlatform.Env.regionCode = $regionCode
      $CdfPlatform.Env.regionName = $regionName
      $CdfPlatform.Config.templateScope = 'platform'
      $CdfPlatform.Config.platformId = $PlatformId
      $CdfPlatform.Config.instanceId = $InstanceId

      $CdfPlatform | ConvertTo-Json -Depth 10 | Write-Verbose

      $CdfConfig = [ordered] @{
        Platform = $CdfPlatform
      }
      return $CdfConfig
    }
    else {
      Write-Error "Platform configuration not complete."
    }
  }

  End {
  }
}

