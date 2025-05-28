Function Add-ServiceConnectionSettings {
    <#
    .SYNOPSIS
    Add connection parameters for service

    .DESCRIPTION

    .PARAMETER UseCS
    Switch indicating that connections should use connection strings instead of managed identities.

    .PARAMETER CdfConfig
    The Config object from the target scope (Platform, Application and Domain)

    .PARAMETER Settings
    Hashtable with app settings. See examples.

    .PARAMETER ConnectionName
    The name of the service provider connection

    .PARAMETER ConnectionDefinition
    Connection details

    .PARAMETER ParameterName
    Name of parameter within the target scope Config object.

    .EXAMPLE
    appsettings.json:
    {
        "AzureWebJobsStorage": "",
        "WORKFLOWS_SUBSCRIPTION_ID": ""
    }

    $appSettings = Get-Content "appsettings.json" | ConvertFrom-Json -AsHashtable
    $appSettings = Add-CdfServiceConnectionSettings `
        -CdfConfig $cdfConfig `
        -Settings $appSettings `
        -ConnectionName  "PlatformKeyVault" `
        -ParameterName "platformKeyVault" `
        -ConnectionDefinition $definition
    $appSettings | ConvertTo-Json -Depth 10 | Set-Content -Path "appsettings.json"

    appsettings.json (result):
    {
        "AzureWebJobsStorage": "",
        "WORKFLOWS_SUBSCRIPTION_ID": "",
        "PlatformKeyVaultUri": "<KeyVaultName>.vault.azure.net"
        "DomainStorageAccountUri": "<StorageAccountName>.vault.azure.net"
    }

    .LINK
    Deploy-CdfServiceContainerApp
    Deploy-CdfServiceFunctionApp
    Deploy-CdfServiceLogicAppStd
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)]
        [switch] $UseCS,
        [Parameter(Mandatory = $true)]
        [hashtable]$CdfConfig,
        [Parameter(Mandatory = $true)]
        [hashtable]$ConnectionDefinition,
        [Parameter(Mandatory = $true)]
        [object]$Settings,
        [Parameter(Mandatory = $true)]
        [string] $ConnectionName,
        [Parameter(Mandatory = $true)]
        [string] $ParameterName
    )

    # $connectionParams = $Config.Config[$ParameterName]
    $connectionParams = $ConnectionDefinition.connectionConfig

    $azCtx = Get-AzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId
    $SettingName = 'CON_' + $ConnectionDefinition.Scope.ToUpper() + '_' + $ConnectionDefinition.ServiceProvider.ToUpper() + '_'

    if ($UseCS) {
        switch ($ConnectionDefinition.ServiceProvider.ToLower()) {
            'keyvault' {
                # No support for connection string
                $Settings["$($SettingName)Uri"] = "$($connectionParams.name).vault.azure.net"
            }
            'azureeventgridpublish' {
                switch ($connectionParams.type) {
                    'EventGridTopic' {
                        Write-Host "DEBUG: Adding ConnectionString for '$ConnectionName' [$($connectionParams.type)]"
                        $eventGridTopic = Get-AzEventGridTopic -DefaultProfile $AzCtx `
                            -ResourceGroupName $connectionParams.resourceGroup `
                            -Name $connectionParams.name
                        $eventGridTopicKeys = Get-AzEventGridTopicKey $eventGridTopic

                        $Settings["$($SettingName)_accessKey"] = $eventGridTopicKeys.Key1
                        $Settings["$($SettingName)_topicEndpoint"] = $eventGridTopic.Endpoint
                    }
                    default {
                        Write-Host "DEBUG: Adding ConnectionString for '$ConnectionName' [$($connectionParams.type)]"
                        $eventGridTopic = Get-AzEventGridTopic -DefaultProfile $AzCtx `
                            -ResourceGroupName $connectionParams.resourceGroup `
                            -Name $connectionParams.name
                        $eventGridTopicKeys = Get-AzEventGridTopicKey $eventGridTopic

                        $Settings["$($SettingName)_accessKey"] = $eventGridTopicKeys.Key1
                        $Settings["$($SettingName)_topicEndpoint"] = $eventGridTopic.Endpoint
                    }
                }
            }
            'servicebus' {
                $serviceBusKey = Get-AzServiceBusKey `
                    -SubscriptionId $AzCtx.Subscription.Id `
                    -ResourceGroupName $connectionParams.resourceGroup `
                    -NamespaceName $connectionParams.name `
                    -Name RootManageSharedAccessKey `
                    -WarningAction:SilentlyContinue

                $Settings["$($SettingName)_connectionString"] = $serviceBusKey.PrimaryConnectionString
            }
            'eventhubs' {
                $eventHubKey = Get-AzEventHubKey `
                    -SubscriptionId $AzCtx.Subscription.Id `
                    -ResourceGroupName $connectionParams.resourceGroup `
                    -NamespaceName $connectionParams.name `
                    -Name RootManageSharedAccessKey `
                    -WarningAction:SilentlyContinue

                $Settings["$($ConnectionName)_connectionString"] = $eventHubKey.PrimaryConnectionString
            }
            'azureblob' {
                $storageContext = (
                    Get-AzStorageAccount `
                        -DefaultProfile $AzCtx `
                        -ResourceGroupName $connectionParams.resourceGroup `
                        -Name $connectionParams.name
                ).Context
                $Settings["$($SettingName)_connectionString"] = $storageContext.ConnectionString
            }
            'azurefile' {
                $storageContext = (
                    Get-AzStorageAccount `
                        -DefaultProfile $AzCtx `
                        -ResourceGroupName $connectionParams.resourceGroup `
                        -Name $connectionParams.name
                ).Context
                $Settings["$($SettingName)_connectionString"] = $storageContext.ConnectionString
            }
            'azuretables' {
                $storageContext = (
                    Get-AzStorageAccount `
                        -DefaultProfile $AzCtx `
                        -ResourceGroupName $connectionParams.resourceGroup `
                        -Name $connectionParams.name
                ).Context
                $Settings["$($SettingName)_connectionString"] = $storageContext.ConnectionString
            }
            'azurequeues' {
                $storageContext = (
                    Get-AzStorageAccount `
                        -DefaultProfile $AzCtx `
                        -ResourceGroupName $connectionParams.resourceGroup `
                        -Name $connectionParams.name
                ).Context
                $Settings["$($SettingName)_connectionString"] = $storageContext.ConnectionString
            }
            'postgresql' {
                $Settings["$($SettingName)_ServerName"] = $connectionParams.databaseServerFQDN
                $Settings["$($SettingName)_Database"] = $connectionParams.database
                if ($ConnectionDefinition.Scope.ToLower() -eq 'platform') {
                    $keyVaultName = $CdfConfig.Platform.ResourceNames.keyVaultName
                }
                else {
                    $keyVaultName = $CdfConfig.Domain.ResourceNames.keyVaultName
                }
                $Settings["$($SettingName)_UserName"] = "@Microsoft.KeyVault(VaultName=$keyVaultName;SecretName=$($connectionParams.userSecretName))"
                $Settings["$($SettingName)_Password"] = "@Microsoft.KeyVault(VaultName=$keyVaultName;SecretName=$($connectionParams.passwordSecretName))"
            }
            default {
                if ($ConnectionDefinition.Scope -in @('Platform', 'Application', 'Domain')) {
                    Write-Warning "Unsupported service provider: $($ConnectionDefinition.ServiceProvider)"
                }
            }
        }

    }
    else {
        # Using managed identity
        switch ($ConnectionDefinition.ServiceProvider.ToLower()) {
            'keyvault' {
                $Settings["$($SettingName)URI"] = "https://$($connectionParams.name).vault.azure.net"
            }
            'azureeventgridpublish' {
                switch ($connectionParams.type) {
                    'EventGridTopic' {
                        Write-Host "DEBUG: Adding ManagedIdentity for '$ConnectionName' [$($connectionParams.type)]"
                        $eventGridTopic = Get-AzEventGridTopic `
                            -SubscriptionId $azCtx.Subscription.Id `
                            -ResourceGroupName $connectionParams.resourceGroup `
                            -Name $connectionParams.name
                        $eventGridTopicKeys = Get-AzEventGridTopicKey `
                            -SubscriptionId $azCtx.Subscription.Id `
                            -ResourceGroupName $connectionParams.resourceGroup `
                            -TopicName $eventGridTopic.name

                        $Settings["$($SettingName)ACCESSKEY"] = $eventGridTopicKeys.Key1
                        $Settings["$($SettingName)TOPICENDPOINT"] = $eventGridTopic.Endpoint
                    }
                    default {
                        Write-Host "DEBUG: Adding ConnectionString for '$ConnectionName' [$($connectionParams.type)]"
                        $eventGridTopic = Get-AzEventGridTopic `
                            -SubscriptionId $azCtx.Subscription.Id `
                            -ResourceGroupName $connectionParams.resourceGroup `
                            -Name $connectionParams.name
                        $eventGridTopicKeys = Get-AzEventGridTopicKey `
                            -SubscriptionId $azCtx.Subscription.Id `
                            -ResourceGroupName $connectionParams.resourceGroup `
                            -TopicName $eventGridTopic.name


                        $Settings["$($SettingName)ACCESSKEY"] = $eventGridTopicKeys.Key1
                        $Settings["$($SettingName)TOPICENDPOINT"] = $eventGridTopic.Endpoint
                    }
                }
            }
            'servicebus' {
                $Settings["$($SettingName)FULLYQUALIFIEDNAMESPACE"] = "$($connectionParams.name).servicebus.windows.net"
            }
            'eventhubs' {
                $Settings["$($SettingName)FULLYQUALIFIEDNAMESPACE"] = "$($connectionParams.name).servicebus.windows.net"
            }
            'azureblob' {
                $Settings["$($SettingName)URI"] = "https://$($connectionParams.name).blob.core.windows.net"
            }
            'azurefile' {
                # NOTE: Azure Storage Account File Share does not support managed identities for access yet.
                $azCtx = Get-AzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId
                $storageContext = (
                    Get-AzStorageAccount `
                        -DefaultProfile $AzCtx `
                        -ResourceGroupName $connectionParams.resourceGroup `
                        -Name $connectionParams.name
                ).Context

                $storageKey = (
                    Get-AzStorageAccountKey `
                        -DefaultProfile $AzCtx `
                        -ResourceGroupName $connectionParams.resourceGroup `
                        -Name $connectionParams.name
                    | Where-Object { $_.KeyName -eq "key1" }
                ).Value


                # $sasToken = New-StorageAccountFileToken `
                #     -AzCtx $azCtx `
                #     -StorageAccountRG $connectionParams.resourceGroup `
                #     -StorageAccountName $connectionParams.name `
                #     -ValidityDays 60

                $Settings["$($SettingName)CONNECTIONSTRING"] = "DefaultEndpointsProtocol=https;EndpointSuffix=$($storageContext.EndPointSuffix);AccountName=$($connectionParams.name);AccountKey=$storageKey"

                # $Settings["$($SettingName)Uri"] = "FileEndpoint=https://$($connectionParams.name).file.core.windows.net;SharedAccessSignature=$sasToken"
                # $Settings["$($SettingName)Uri"] = "https://$($connectionParams.name).file.core.windows.net$sasToken"
            }
            'azuretables' {
                $Settings["$($SettingName)URI"] = "https://$($connectionParams.name).table.core.windows.net"
            }
            'azurequeues' {
                $Settings["$($SettingName)URI"] = "https://$($connectionParams.name).queue.core.windows.net"
            }
            'postgresql' {
                #No support for managed identity
                $Settings["$($SettingName)SERVERNAME"] = $connectionParams.databaseServerFQDN
                $Settings["$($SettingName)DATABASE"] = $connectionParams.database
                if ($ConnectionDefinition.Scope.ToLower() -eq 'platform') {
                    $keyVaultName = $CdfConfig.Platform.ResourceNames.keyVaultName
                }
                else {
                    $keyVaultName = $CdfConfig.Domain.ResourceNames.keyVaultName
                }
                $Settings["$($SettingName)USERNAME"] = "@Microsoft.KeyVault(VaultName=$keyVaultName;SecretName=$($connectionParams.userSecretName))"
                $Settings["$($SettingName)PASSWORD"] = "@Microsoft.KeyVault(VaultName=$keyVaultName;SecretName=$($connectionParams.passwordSecretName))"
            }
            default {
                Write-Warning "Unsupported service provider: $($ConnectionDefinition.ServiceProvider)"
            }
        }
    }
    Write-Output -InputObject $Settings
}

