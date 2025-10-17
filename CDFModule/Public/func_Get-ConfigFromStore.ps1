Function Get-ConfigFromStore {
  <#
    .SYNOPSIS
    Get configuration from config store(AppConfig or keyVault or StorageAccount)

    .DESCRIPTION
    Retrieves the configuration for a deployed environment instance from config store.

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
    Get-ConfigFromStore `
          -CdfConfig $CdfPlatform `
          -Scope 'Platform' `
          -EnvKey $platformEnvKey `
          -RegionDetails $regionDetails

    .EXAMPLE
    Get-ConfigFromStore `
          -CdfConfig $CdfConfig `
          -Scope 'Application' `
          -EnvKey "$($platformEnvKey)-$($applicationEnvKey)" `
          -RegionDetails $regionDetails `
          -ErrorAction Continue

    .LINK
    Get-CdfConfigPlatform
    .LINK
    Get-CdfConfigApplication
    .LINK
    Get-CdfConfigDomain
    .LINK
    Get-CdfConfigService

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
    Write-Verbose "Fetching config of '$($Scope.ToLower())' from custom config store '$configStoreName' in resource group '$configStoreResourceGroupName'  under subscription [$($azCtx.Subscription.Name)] with key '$EnvKey'."
    $CdfConfigOutput = @{}
    if ($configStoreType.ToUpper() -eq 'APPCONFIG') {

      $lableName = "$templateName-$templateVersion"
      $result = Get-AzAppConfigurationKeyValue -EndPoint $configStoreEndpoint -Label $lableName -Key "$($keyName)*" | Select-Object Key, Value
      if ($result) {
        $isEnvKeyExists = $result | Where-Object { $_.Key -eq "$($keyName)-Env" }
        if ($isEnvKeyExists) {
          $CdfConfigOutput = [ordered] @{
            IsDeployed    = $true
            Env           = ($result | Where-Object { $_.Key -eq "$($keyName)-Env" }).Value | ConvertFrom-Json -AsHashtable
            Tags          = ($result | Where-Object { $_.Key -eq "$($keyName)-Tags" }).Value | ConvertFrom-Json -AsHashtable
            Config        = ($result | Where-Object { $_.Key -eq "$($keyName)-Config" }).Value | ConvertFrom-Json -AsHashtable
            Features      = ($result | Where-Object { $_.Key -eq "$($keyName)-Features" }).Value | ConvertFrom-Json -AsHashtable
            ResourceNames = ($result | Where-Object { $_.Key -eq "$($keyName)-ResourceNames" }).Value | ConvertFrom-Json -AsHashtable
            AccessControl = ($result | Where-Object { $_.Key -eq "$($keyName)-AccessControl" }).Value | ConvertFrom-Json -AsHashtable
            NetworkConfig = ($result | Where-Object { $_.Key -eq "$($keyName)-NetworkConfig" }).Value | ConvertFrom-Json -AsHashtable

          }
          $CdfConfigOutput = $CdfConfigOutput | ConvertTo-Json -depth 10 | ConvertFrom-Json -AsHashtable
        }
        else {
          Write-Warning "No configuration found in custom config store '$configStoreName' with label '$lableName' in resource group '$configStoreResourceGroupName' under subscription [$($azCtx.Subscription.Name)] with key '$EnvKey'."
          Write-Warning "Trying to return configuration from deployment output."
        }
      }
      else {
        Write-Warning "No configuration found in custom config store '$configStoreName' with label '$lableName' in resource group '$configStoreResourceGroupName' under subscription [$($azCtx.Subscription.Name)]."
        Write-Warning "Trying to return configuration from deployment output."
      }

    }
    elseif ($configStoreType.ToUpper() -eq 'KEYVAULT') {
      $result = Get-AzKeyVaultSecret `
        -VaultName $configStoreName `
        -Name $keyName `
        -AsPlainText
      if ($result) {
        $CdfConfigOutput = $result | ConvertFrom-Json -AsHashtable
      }
      else {
        Write-Warning "No configuration found in KeyVault '$configStoreName' with key '$keyName' in resource group '$configStoreResourceGroupName' using subscription [$($azCtx.Subscription.Name)]."
        Write-Warning "Trying to return configuration from deployment output."
      }

    }
    elseif ($configStoreType.ToUpper() -eq 'STORAGEACCOUNT') {
      $azStorageCtx = New-AzStorageContext -StorageAccountName $configStoreName -UseConnectedAccount
      $containerName = 'cdfconfig'
      $blob = Get-AzStorageBlob -Container $containerName -Blob $keyName -Context $azStorageCtx
      if ($blob) {
        $stream = $blob.ICloudBlob.OpenRead()
        $reader = New-Object System.IO.StreamReader($stream)
        $result = $reader.ReadToEnd()
        $reader.Close()
        $stream.Close()
        $CdfConfigOutput = $result | ConvertFrom-Json -AsHashtable
      }
      else {
        Write-Warning "No configuration found in Storage Account '$configStoreName' and container '$containerName'  with blob name '$keyName' in subscription [$($azCtx.Subscription.Name)]."
        Write-Warning "Trying to return configuration from deployment output."
      }
    }
    return $CdfConfigOutput;
  }

  End {
  }
}

