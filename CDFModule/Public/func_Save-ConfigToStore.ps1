Function Save-ConfigToStore {
    <#
    .SYNOPSIS
    Save configuration to config store(AppConfig or keyVault or StorageAccount)

    .DESCRIPTION
    Saves the configuration for a deployed environment instance in a config store.

    .PARAMETER CdfConfig
    Config object having config store and other details.

    .PARAMETER ScopeConfig
    Object having config for env in scope..

    .PARAMETER Scope
    Scope : Platform or Application or Domain or Service

    .PARAMETER EnvKey
    Env specific key to be used for fetching config.

    .PARAMETER OutputConfigFilePath
    Json file path to be uploaded to blob in case config store is StorageAccount

    .PARAMETER RegionDetails
    Object having region details like name,code.

    .INPUTS
    CdfConfig

    .OUTPUTS
    Updated CDFConfig and json config files at SourceDir


    .EXAMPLE
    $regionDetails = [ordered] @{
                    region = $region
                    code   = $regionCode
                    name   = $regionName
                }
    Save-ConfigToStore `
                    -CdfConfig $CdfConfig `
                    -ScopeConfig $CdfApplication `
                    -Scope 'Application' `
                    -OutputConfigFilePath $configOutput `
                    -EnvKey "$($platformEnvKey)-$($applicationEnvKey)" `
                    -RegionDetails $regionDetails


    .LINK
    Remove-CdfTemplatePlatform
    .LINK
    Deploy-CdfTemplatePlatform
    .LINK
    Deploy-CdfTemplateApplication
    .LINK
    Deploy-CdfTemplateDomain
    .LINK
    Deploy-CdfTemplateService

    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [Object]$CdfConfig,
        [Parameter(Mandatory = $true)]
        [Object]$ScopeConfig,
        [Parameter(Mandatory = $true)]
        [string] $Scope,
        [Parameter(Mandatory = $true)]
        [string] $OutputConfigFilePath,
        [Parameter(Mandatory = $true)]
        [string] $EnvKey,
        [Parameter(Mandatory = $true)]
        [hashtable] $RegionDetails
    )

    Begin {
    }
    Process {

        $configStoreType = $CdfConfig.Platform.Config.configStoreType
        $configStoreSubscriptionId = $CdfConfig.Platform.Config.configStoreSubscriptionId
        $configStoreResourceGroupName = $CdfConfig.Platform.Config.configStoreResourceGroupName
        $configStoreName = $CdfConfig.Platform.Config.configStoreName
        $configStoreEndpoint = $CdfConfig.Platform.Config.configStoreEndpoint
        $templateName = $CdfConfig.Platform.Config.templateName
        $templateVersion = $CdfConfig.Platform.Config.templateVersion

        Write-Host "Saving $($Scope.ToLower()) config to $configStoreName."

        $keyName = "CdfConfig-$($Scope)-$EnvKey-$($RegionDetails.code)"

        if ($configStoreType.ToUpper() -eq 'APPCONFIG') {
            $configNames = @("Config", "Env", "Tags", "Features", "NetworkConfig", "AccessControl", "ResourceNames")
            foreach ($configName in $configNames) {
                $jsonValue = $ScopeConfig[$configName] | ConvertTo-Json -Depth 10 -Compress
                $size = ([System.Text.Encoding]::UTF8.GetByteCount("$templateName-$templateVersion" + "$keyName-$configName" + $jsonValue))
                #App Conifg kas size limit of 10KB for key-Value
                if ($size -gt 10000) {
                    Write-Warning "Supplied configuration '$keyName-$configName' size is higher than allowed limit of 10KB. Trying to reduce size by removing 'description'."
                    foreach ( $item in $ScopeConfig[$configName]) {
                        Remove-DescriptionFields $item
                    }
                    $jsonValue = $ScopeConfig[$configName] | ConvertTo-Json -Depth 10 -Compress
                    $size = ([System.Text.Encoding]::UTF8.GetByteCount("$templateName-$templateVersion" + "$keyName-$configName" + $jsonValue))
                }

                if ($size -gt 10000) {
                    Write-Warning "Supplied configuration size is still is higher than allowed limit of 10KB. So saving empty '{}' config instead."
                    $jsonValue = '{}' | ConvertTo-Json
                }

                $null = Set-AzAppConfigurationKeyValue `
                    -Endpoint $configStoreEndpoint `
                    -Key "$keyName-$configName" `
                    -Label  "$templateName-$templateVersion" `
                    -Value $jsonValue `
                    -ContentType 'application/json'

            }
        }
        elseif ($configStoreType.ToUpper() -eq 'KEYVAULT') {
            $jsonValue = $ScopeConfig | ConvertTo-Json -Depth 10
            $jsonValue = ConvertTo-SecureString -String $jsonValue -AsPlainText -Force
            $null = Set-AzKeyVaultSecret `
                -VaultName $configStoreName `
                -Name $keyName `
                -SecretValue $jsonValue `
                -ContentType 'application/json'
        }
        elseif ($configStoreType.ToUpper() -eq 'STORAGEACCOUNT') {
            $ctx = New-AzStorageContext -StorageAccountName $configStoreName -UseConnectedAccount
            $containerName = 'cdfconfig'
            $container = Get-AzStorageContainer -Name $containerName -Context $ctx -ErrorAction SilentlyContinue
            if (!$container) {
                $container = New-AzStorageContainer -Name $containerName  -Context $ctx
            }
            Set-AzStorageBlobContent -File $OutputConfigFilePath -Force -Container $containerName -Blob $keyName -Context $ctx
        }
    }
    End {
    }
}

function Remove-DescriptionFields {
    param (
        [Parameter(Mandatory = $true)]
        [object] $Data
    )

    # Stop if null
    if ($null -eq $Data) { return }

    # If array / list
    if ($Data -is [System.Management.Automation.OrderedHashtable]) {
        foreach ($item in $Data.Keys.Clone()) {
            if ($item -eq 'description') {
                $Data.Remove('description')
            }
            if ($item -is [System.Object[]] -or $item -is [System.String]) {
                foreach ($arrayItem in $Data[$item]) {
                    if ($arrayItem -eq 'description') {
                        $Data[$item].Remove('description')
                    }
                    if ($arrayItem -is [System.Management.Automation.OrderedHashtable]) {
                        foreach ($hashItem in $arrayItem.Keys.Clone()) {
                            if ($hashItem -eq 'description') {
                                $arrayItem.Remove('description')
                            }
                        }
                    }
                }
            }

        }

    }
    return


}