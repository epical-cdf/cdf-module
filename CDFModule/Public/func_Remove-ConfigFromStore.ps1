Function Remove-ConfigFromStore {
  <#
    .SYNOPSIS
    Remove configuration from config store(AppConfig or keyVault or StorageAccount)

    .DESCRIPTION
    Removes configuration for a deployed environment instance from config store.

    .PARAMETER CdfConfig
    Config object having config store and other details.

    .PARAMETER Scope
    Scope : Platform or Application or Domain or Service

    .PARAMETER EnvKey
    Env specific key to be used for fetching config.

    .PARAMETER RegionDetails
    Object having region details like name,code.

    .INPUTS
    None

    .OUTPUTS
    CdfConfigOutput

    .EXAMPLE
    Remove-ConfigFromStore `
          -CdfConfig $CdfPlatform `
          -Scope 'Platform' `
          -EnvKey $platformEnvKey `
          -RegionDetails $regionDetails

    .EXAMPLE
    Remove-ConfigFromStore `
          -CdfConfig $CdfConfig `
          -Scope 'Application' `
          -EnvKey "$($platformEnvKey)-$($applicationEnvKey)" `
          -RegionDetails $regionDetails `
          -ErrorAction Continue

    .LINK
    Remove-CdfConfigPlatform
    .LINK
    Remove-CdfConfigApplication
    .LINK
    Remove-CdfConfigDomain
    .LINK
    Remove-CdfConfigService

    #>

  [CmdletBinding()]
  Param(
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory = $true)]
    [hashtable]$CdfConfig,
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory = $true)]
    [string] $Scope,
    [Parameter(Mandatory = $true)]
    [string] $EnvKey,
    [Parameter(Mandatory = $true)]
    [hashtable] $RegionDetails
  )
  Begin {}
  Process {
    if ($Scope.ToUpper() -ne 'PLATFORM') {
      $configStoreType = $CdfConfig.Platform.Config.configStoreType
      $configStoreSubscriptionId = $CdfConfig.Platform.Config.configStoreSubscriptionId
      $configStoreResourceGroupName = $CdfConfig.Platform.Config.configStoreResourceGroupName
      $configStoreName = $CdfConfig.Platform.Config.configStoreName
      $configStoreEndpoint = $CdfConfig.Platform.Config.configStoreEndpoint
      $templateName = $CdfConfig.Platform.Config.templateName
      $templateVersion = $CdfConfig.Platform.Config.templateVersion
    }
    else {
      $configStoreType = $CdfConfig.Config.configStoreType
      $configStoreSubscriptionId = $CdfConfig.Config.configStoreSubscriptionId
      $configStoreResourceGroupName = $CdfConfig.Config.configStoreResourceGroupName
      $configStoreName = $CdfConfig.Config.configStoreName
      $configStoreEndpoint = $CdfConfig.Config.configStoreEndpoint
      $templateName = $CdfConfig.Config.templateName
      $templateVersion = $CdfConfig.Config.templateVersion
    }
    $keyName = "CdfConfig-$($Scope)-$EnvKey-$($RegionDetails.code)"

    $azCtx = Get-AzureContext -SubscriptionId $configStoreSubscriptionId
    Write-Host "Removing config of '$($Scope.ToLower())' from custom config store '$configStoreName' in resource group '$configStoreResourceGroupName'  under subscription [$($azCtx.Subscription.Name)] with key '$EnvKey'."
    $CdfConfigOutput = @{}
    if ($configStoreType.ToUpper() -eq 'APPCONFIG') {
      $configNames = @("Config", "Env", "Tags", "Features", "NetworkConfig", "AccessControl", "ResourceNames")
            foreach ($configName in $configNames) {
                $null = Remove-AzAppConfigurationKeyValue `
                    -Endpoint $configStoreEndpoint `
                    -Key "$keyName-$configName" `
                    -Label  "$templateName-$templateVersion"
            }
    }
    elseif ($configStoreType.ToUpper() -eq 'KEYVAULT') {
      $null = Remove-AzKeyVaultSecret `
        -VaultName $configStoreName `
        -Name $keyName
    }
    elseif ($configStoreType.ToUpper() -eq 'STORAGEACCOUNT') {
      $azStorageCtx = New-AzStorageContext -StorageAccountName $configStoreName -UseConnectedAccount
      $containerName = 'cdfconfig'
      $null = Remove-AzStorageBlob -Container $containerName -Blob $keyName -Context $azStorageCtx
    }
  }

  End {
  }
}

