Function Get-ConfigApplication {
  <#
    .SYNOPSIS
    Get configuration for a deployed application instance for given platform instance.

    .DESCRIPTION
    Retrieves the configuration for a deployed application instance from output files stored at SourceDir for the platform instance.
    .PARAMETER CdfConfig
    Instance configuration

    .PARAMETER ApplicationId
    Name of the application instance template

    .PARAMETER InstanceId
    Specific id of the application instance

    .PARAMETER EnvDefinitionId
    Name of the environment configuration.

    .PARAMETER SourceDir
    Path to the platform source directory. Defaults to "./src".

    .INPUTS
    CdfPlatform

    .OUTPUTS
    CdfApplication

    .EXAMPLE
    Get-CdfConfigApplication `
      -Region "swedencentral" `
      -PlatformId "capim" `
      -instanceId "01" `
      -EnvDefinitionId "intg-dev"
    .EXAMPLE
    Get-CdfConfigApplication `
      -Region "swedencentral" `
      -PlatformId "capim" `
      -instanceId "01" `
      -EnvDefinitionId "intg-dev" `
      -SourceDir "../cdf-infra/src"

    .LINK
    Get-CdfConfigPlatform
    .LINK
    Deploy-CdfTemplateApplication
    #>
  [CmdletBinding()]
  Param(
    [ValidateNotNullOrEmpty()]
    [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
    [hashtable]$CdfConfig,
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory = $false)]
    [string] $Region = $env:CDF_REGION,
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory = $false)]
    [string] $ApplicationId = $env:CDF_APPLICATION_ID,
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory = $false)]
    [string] $InstanceId = $env:CDF_APPLICATION_INSTANCE,
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory = $false)]
    [string] $EnvDefinitionId = $env:CDF_APPLICATION_ENV_ID,
    [Parameter(Mandatory = $false)]
    [switch] $Deployed,
    [Parameter(Mandatory = $false)]
    [string] $SourceDir = $env:CDF_INFRA_SOURCE_PATH ?? './src'
  )

  Begin {
    $haveCdfParameters = $true
    if ([String]::IsNullOrWhiteSpace($Region)) { Write-Error "Missing required CDF Parameter 'Region' or environment variable 'CDF_REGION'"; $haveCdfParameters = $false }
    if ([String]::IsNullOrWhiteSpace($ApplicationId)) { Write-Error "Missing required CDF Parameter 'ApplicationId' or environment variable 'CDF_APPLICATION_ID'"; $haveCdfParameters = $false }
    if ([String]::IsNullOrWhiteSpace($InstanceId)) { Write-Error "Missing required CDF Parameter 'Region' or environment variable 'CDF_APPLICATION_INSTANCE'"; $haveCdfParameters = $false }
    if ([String]::IsNullOrWhiteSpace($EnvDefinitionId)) { Write-Error "Missing required CDF Parameter 'Region' or environment variable 'CDF_APPLICATION_ENV_ID'"; $haveCdfParameters = $false }
    if (!$haveCdfParameters) {
      throw("Missing required CDF parameters")
    }

  }
  Process {
    if (!$CdfConfig.Platform.IsDeployed) {
      Write-Warning "Platform config is not deployed, this may cause errors in using the application configuration."
    }

    $platformKey = "$($CdfConfig.Platform.Config.platformId)$($CdfConfig.Platform.Config.instanceId)"
    $applicationKey = "$ApplicationId$InstanceId"

    # Fetch definitions
    $sourcePath = "$SourceDir/$($CdfConfig.Platform.Config.platformId)/$($CdfConfig.Platform.Config.instanceId)"

    # Setup deployment variables from configuration
    $applicationEnvs = Get-Content -Raw "$sourcePath/application/environments.$applicationKey.json" | ConvertFrom-Json -AsHashtable
    $applicationEnv = $applicationEnvs[$EnvDefinitionId]

    # Application currently uses platform config for region, prepared for multiregion application on single region platform
    $region = $CdfConfig.Platform.Env.region
    $regionCode = $CdfConfig.Platform.Env.regionCode
    $regionName = $CdfConfig.Platform.Env.regionName

    $platformEnvKey = "$platformKey$($CdfConfig.Platform.Env.nameId)"
    $applicationEnvKey = "$applicationKey$($applicationEnv.nameId)"

    # Get application configuration
    if (Test-Path "$sourcePath/application/application.$platformEnvKey-$applicationEnvKey-$regionCode.json" ) {
      Write-Verbose "Loading configuration file"
      $CdfApplication = Get-Content "$sourcePath/application/application.$platformEnvKey-$applicationEnvKey-$regionCode.json" | ConvertFrom-Json -AsHashtable
      $CdfApplication.Env = $applicationEnv
    }
    else {
      throw "No application configuration file found for platform key '$platformEnvKey', application key '$applicationEnvKey' and region code '$regionCode'."
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
          -Scope 'Application' `
          -EnvKey "$($platformEnvKey)-$($applicationEnvKey)" `
          -RegionDetails $regionDetails `
          -ErrorAction Continue
      }
      if ($cdfConfigOutput -ne $null -and $cdfConfigOutput.Count -eq 0) {

        # Get latest deployment result outputs
        $deploymentName = "application-$platformEnvKey-$applicationEnvKey-$regionCode"

        $azCtx = Get-AzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId
        Write-Verbose "Fetching deployment of '$deploymentName' at '$region' using subscription [$($azCtx.Subscription.Name)] for runtime environment '$($applicationEnv.name)'."

        $result = Get-AzSubscriptionDeployment  `
          -DefaultProfile $azCtx `
          -Name "$deploymentName" `
          -ErrorAction SilentlyContinue

        if ($result -and $result.ProvisioningState -eq 'Succeeded') {
          # Setup application definitions
          $CdfApplication = [ordered] @{
            IsDeployed    = $true
            Env           = $result.Outputs.applicationEnv.Value
            Tags          = $result.Outputs.applicationTags.Value
            Config        = $result.Outputs.applicationConfig.Value
            Features      = $result.Outputs.applicationFeatures.Value
            ResourceNames = $result.Outputs.applicationResourceNames.Value
            NetworkConfig = $result.Outputs.applicationNetworkConfig.Value
            AccessControl = $result.Outputs.applicationAccessControl.Value
          }

          # Convert to normalized hashtable
          $CdfApplication = $CdfApplication | ConvertTo-Json -depth 10 | ConvertFrom-Json -AsHashtable
        }
        elseif ($result -and $result.ProvisioningState -ne 'Succeeded') {
          Write-Warning "Deployment state is [$($result.ProvisioningState)] for '$deploymentName' at '$region' using subscription [$($azCtx.Subscription.Name)] for runtime environment '$($applicationEnv.name)'."
          Write-Warning "Returning configuration from file."
        }
        else {
          Write-Warning "No deployment found for '$deploymentName' at '$region' using subscription [$($azCtx.Subscription.Name)] for runtime environment '$($applicationEnv.name)'."
          Write-Warning "Returning configuration from file."
        }
      }
      else {
        $CdfApplication = $cdfConfigOutput
      }
    }
    else {
      if ($CdfApplication.IsDeployed) {
        Write-Warning "Application config on file is a deployed version, use -Deployed to get latest"
      }
    }

    $CdfApplication.Env.region = $region
    $CdfApplication.Env.regionCode = $regionCode
    $CdfApplication.Env.regionName = $regionName
    $CdfApplication.Config.templateScope = 'application'
    $CdfApplication.Config.applicationId = $ApplicationId # TODO: Add named application identities
    $CdfApplication.Config.instanceId = $InstanceId

    $CdfApplication | ConvertTo-Json -Depth 10 | Write-Verbose

    $CdfConfig.Application = $CdfApplication
    return $CdfConfig
  }
  End {
  }
}