Function Get-ConfigDomain {
  <#
    .SYNOPSIS
    Get configuration for a deployed application instance for given platform instance.

    .DESCRIPTION
    Retrieves the configuration for a deployed application instance from output files stored at SourceDir for the platform instance.

    .PARAMETER CdfConfig
    Instance configuration

    .PARAMETER DomainName
    Name of the domain

    .PARAMETER SourceDir
    Path to the platform source directory. Defaults to "./src".

    .INPUTS
    CdfPlatform

    .OUTPUTS
    CdfApplication

    .EXAMPLE
    $config | Get-CdfConfigDomain `
      -DomainName "ops" `
      -EnvDefinitionId "intg-dev"

    .EXAMPLE
    $config = Get-CdfConfigDomain ...
    Get-CdfConfigDomain `
      -CdfConfig $config
      -DomainName "hr" `
      -EnvDefinitionId "apim-dev" `
      -SourceDir "../cdf-infra/src"

    .LINK
    Get-CdfConfigApplication
    .LINK
    Deploy-CdfTemplateDomain

    #>

  [CmdletBinding()]
  Param(
    [ValidateNotNullOrEmpty()]
    [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
    [hashtable]$CdfConfig,
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory = $false)]
    [string] $DomainName = $env:CDF_DOMAIN_NAME,
    [Parameter(Mandatory = $false)]
    [switch] $Deployed,
    [Parameter(Mandatory = $false)]
    [string] $SourceDir = $env:CDF_INFRA_SOURCE_PATH ?? './src'
  )

  Begin {
    $haveCdfParameters = $true
    if ([String]::IsNullOrWhiteSpace($DomainName)) { Write-Error "Missing required CDF Parameter 'DomainName' or environment variable 'CDF_DOMAIN_NAME'"; $haveCdfParameters = $false }
    if (!$haveCdfParameters) {
      throw("Missing required CDF parameters")
    }

  }
  Process {
    if (!$CdfConfig.Application.IsDeployed) {
      Write-Warning "Application config is not deployed, this may cause errors in using the domain configuration."
    }

    # Load runtime settings from file or package (no Azure needed)
    $runtimeSetting = Get-RuntimeSetting `
      -Scope 'Domain' `
      -SourceDir $SourceDir `
      -CdfConfig $CdfConfig `
      -DomainName $DomainName

    $platformEnvKey = $runtimeSetting.Definitions.PlatformEnvKey
    $applicationEnvKey = $runtimeSetting.Definitions.ApplicationEnvKey
    $regionCode = $runtimeSetting.Definitions.RegionCode
    $region = $CdfConfig.Platform.Env.region
    $applicationEnv = $CdfConfig.Application.Env

    $CdfDomain = $runtimeSetting.ScopeConfig

    if ($Deployed) {
      try {
        if ($CdfConfig.Platform.Config.configStoreType) {
          $regionDetails = [ordered] @{
            region = $region
            code   = $regionCode
            name   = $regionName
          }
          $cdfConfigOutput = Get-ConfigFromStore `
            -CdfConfig $CdfConfig `
            -Scope 'Domain' `
            -EnvKey "$platformEnvKey-$applicationEnvKey-$DomainName" `
            -RegionDetails $regionDetails `
            -ErrorAction Continue
        }
        if ($cdfConfigOutput -eq $null -or ($cdfConfigOutput -ne $null -and $cdfConfigOutput.Count -eq 0)) {

          # Get latest deployment result outputs
          $deploymentName = "domain-$platformEnvKey-$applicationEnvKey-$DomainName-$regionCode"

          $azCtx = Get-AzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId -TenantId $CdfConfig.Platform.Env.tenantId
          Write-Verbose "Fetching deployment of '$deploymentName' at '$region' using subscription [$($azCtx.Subscription.Name)] for runtime environment '$($applicationEnv.name)'."

          $result = Get-AzSubscriptionDeployment  `
            -DefaultProfile $azCtx `
            -Name "$deploymentName" `
            -ErrorAction SilentlyContinue

          if ($result -and $result.ProvisioningState -eq 'Succeeded') {
            # Setup domain definitions
            $CdfDomain = [ordered] @{
              IsDeployed    = $true
              Env           = $result.Outputs.domainEnv.Value
              Tags          = $result.Outputs.domainTags.Value
              Config        = $result.Outputs.domainConfig.Value
              Features      = $result.Outputs.domainFeatures.Value
              ResourceNames = $result.Outputs.domainResourceNames.Value
              NetworkConfig = $result.Outputs.domainNetworkConfig.Value
              AccessControl = $result.Outputs.domainAccessControl.Value
              ConfigSource  = 'DEPLOYMENTOUTPUT'
            }

            # Convert to normalized hashtable
            $CdfDomain = $CdfDomain | ConvertTo-Json -depth 10 | ConvertFrom-Json -AsHashtable
          }
          elseif ($result -and $result.ProvisioningState -ne 'Succeeded') {
            Write-Warning "Deployment state is [$($result.ProvisioningState)] for '$deploymentName' at '$region' using subscription [$($azCtx.Subscription.Name)] for runtime environment '$($applicationEnv.name)'."
            Write-Warning "Returning configuration from $($runtimeSetting.ConfigSource)."
          }
          else {
            Write-Warning "No deployment found for '$deploymentName' at '$region' using subscription [$($azCtx.Subscription.Name)] for runtime environment '$($applicationEnv.name)'."
            Write-Warning "Returning configuration from $($runtimeSetting.ConfigSource)."
          }
        }
        else {
          $cdfConfigOutput.Add("ConfigSource", $CdfConfig.Platform.Config.configStoreType.ToUpper())
          $CdfDomain = $cdfConfigOutput
        }
      }
      catch {
        Write-Warning "Cannot fetch deployed configuration: $($_.Exception.Message)"
        Write-Warning "Returning settings from $($runtimeSetting.ConfigSource)$(if ($runtimeSetting.ConfigVersion) { " version $($runtimeSetting.ConfigVersion)" })."
      }
    }
    else {
      if ($CdfDomain.IsDeployed) {
        Write-Warning "Domain config on file is a deployed version, use -Deployed to get latest"
      }
    }

    $CdfDomain.Config.domainName = $DomainName
    $CdfDomain.Config.templateScope = 'domain'
    $CdfDomain | ConvertTo-Json -Depth 10 | Write-Verbose

    $CdfConfig.Domain = $CdfDomain
    return $CdfConfig
  }
  End {
  }
}
