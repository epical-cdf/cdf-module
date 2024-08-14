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
      
    $sourcePath = "$SourceDir/$($CdfConfig.Platform.Config.platformId)/$($CdfConfig.Platform.Config.instanceId)"
    $platformEnvKey = "$($CdfConfig.Platform.Config.platformId)$($CdfConfig.Platform.Config.instanceId)$($CdfConfig.Platform.Env.nameId)"
    $applicationEnvKey = "$($CdfConfig.Application.Config.templateName)$($CdfConfig.Application.Config.instanceId)$($CdfConfig.Application.Env.nameId)"
    $region = $CdfConfig.Platform.Env.region
    $regionCode = $CdfConfig.Platform.Env.regionCode
    $applicationEnv = $CdfConfig.Application.Env
  }
  Process {
    if ($Deployed) {
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
        Write-Warning "Returning configuration from file, if available."
      }
    }
    else {
      $serviceConfigFile = "$sourcePath/service/service.$platformEnvKey-$applicationEnvKey-$($CdfConfig.Domain.Config.domainName)-$ServiceName-$regionCode.json"
      $CdfService = Get-Content $serviceConfigFile | ConvertFrom-Json -AsHashtable
    }

    $CdfConfig.Service = $CdfService
    return $CdfConfig
  }
  End {
  }
}
