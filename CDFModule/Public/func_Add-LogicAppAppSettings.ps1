Function Add-LogicAppAppSettings {
    <#
    .SYNOPSIS
    Update logic app parameters for domain and environment

    .DESCRIPTION

    .PARAMETER UseCS
    Switch indicating that connections should use connection strings instead of managed identities.

    .PARAMETER Config
    The Config object from the target scope (Platform, Application and Domain)

    .PARAMETER SubscriptionId
    Platform subscriptionId

    .PARAMETER Settings
    Hashtable with app settings. See examples.

    .PARAMETER ConnectionName
    The name of the service provider connection

    .PARAMETER ServiceProvider
    The azure service provider identified e.g. AzureBlob, servicebus, keyvault

    .PARAMETER ParameterName
    Name of parameter within the target scope Config object.

    .EXAMPLE
    appsettings.json:
    {
        "AzureWebJobsStorage": "",
        "WORKFLOWS_SUBSCRIPTION_ID": ""
    }

    $appSettings = Get-Content "appsettings.json" | ConvertFrom-Json -AsHashtable
    $appSettings = Add-CdfLogicAppAppSettings `
        -Config $platformConfig `
        -Settings $appSettings `
        -ConnectionName  "PlatformKeyVault" `
        -ParameterName "platformKeyVault" `
        -ServiceProvider "keyvault"
    $appSettings = Add-CdfLogicAppAppSettings `
        -Config $domainConfig `
        -Settings $appSettings `
        -ConnectionName  "DomainStorageAccount" `
        -ParameterName "domainStorageAccount" `
        -ServiceProvider "AzureBlob"

    $appSettings | ConvertTo-Json -Depth 10 | Set-Content -Path "appsettings.json"

    appsettings.json (result):
    {
        "AzureWebJobsStorage": "",
        "WORKFLOWS_SUBSCRIPTION_ID": "",
        "PlatformKeyVaultUri": "<KeyVaultName>.vault.azure.net"
        "DomainStorageAccountUri": "<StorageAccountName>.vault.azure.net"
    }
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)]
        [switch] $UseCS,
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        # [Parameter(Mandatory = $true)]
        # [hashtable]$Config,
        [Parameter(Mandatory = $true)]
        [hashtable]$ConnectionDefinition,
        [Parameter(Mandatory = $true)]
        [hashtable]$Settings,
        [Parameter(Mandatory = $true)]
        [string] $ConnectionName,
        [Parameter(Mandatory = $true)]
        [string] $ServiceProvider,
        [Parameter(Mandatory = $true)]
        [string] $ParameterName
    )

    # $connectionParams = $Config.Config[$ParameterName]
    $connectionParams = $ConnectionDefinition.connectionConfig

    $azCtx = Get-AzureContext -SubscriptionId $SubscriptionId

    if ($UseCS) {
        switch ($ConnectionDefinition.ServiceProvider.ToLower()) {
            'keyvault' {
                # No support for connection string
                $Settings["$($ConnectionName)Uri"] = "$($connectionParams.name).vault.azure.net"
            }
            'azureeventgridpublish' {
                switch ($connectionParams.type) {
                    'EventGridTopic' {
                        Write-Host "DEBUG: Adding ConnectionString for '$ConnectionName' [$($connectionParams.type)]"
                        $eventGridTopic = Get-AzEventGridTopic -DefaultProfile $AzCtx `
                            -ResourceGroupName $connectionParams.resourceGroup `
                            -Name $connectionParams.name
                        $eventGridTopicKeys = Get-AzEventGridTopicKey $eventGridTopic

                        $Settings["$($ConnectionName)_accessKey"] = $eventGridTopicKeys.Key1
                        $Settings["$($ConnectionName)_topicEndpoint"] = $eventGridTopic.Endpoint
                    }
                    default {
                        Write-Host "DEBUG: Adding ConnectionString for '$ConnectionName' [$($connectionParams.type)]"
                        $eventGridTopic = Get-AzEventGridTopic -DefaultProfile $AzCtx `
                            -ResourceGroupName $connectionParams.resourceGroup `
                            -Name $connectionParams.name
                        $eventGridTopicKeys = Get-AzEventGridTopicKey $eventGridTopic

                        $Settings["$($ConnectionName)_accessKey"] = $eventGridTopicKeys.Key1
                        $Settings["$($ConnectionName)_topicEndpoint"] = $eventGridTopic.Endpoint
                    }
                }
            }
            'servicebus' {
                $eventHubKey = Get-AzServiceBusKey `
                    -SubscriptionId $AzCtx.Subscription.Id `
                    -ResourceGroupName $connectionParams.resourceGroup `
                    -NamespaceName $connectionParams.name `
                    -Name RootManageSharedAccessKey `
                    -WarningAction:SilentlyContinue

                $Settings["$($ConnectionName)_connectionString"] = $eventHubKey.PrimaryConnectionString
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
                $Settings["$($ConnectionName)_connectionString"] = $storageContext.ConnectionString
            }
            'azurefile' {
                $storageContext = (
                    Get-AzStorageAccount `
                        -DefaultProfile $AzCtx `
                        -ResourceGroupName $connectionParams.resourceGroup `
                        -Name $connectionParams.name
                ).Context
                $Settings["$($ConnectionName)_connectionString"] = $storageContext.ConnectionString
            }
            'azuretables' {
                $storageContext = (
                    Get-AzStorageAccount `
                        -DefaultProfile $AzCtx `
                        -ResourceGroupName $connectionParams.resourceGroup `
                        -Name $connectionParams.name
                ).Context
                $Settings["$($ConnectionName)_connectionString"] = $storageContext.ConnectionString
            }
            'azurequeues' {
                $storageContext = (
                    Get-AzStorageAccount `
                        -DefaultProfile $AzCtx `
                        -ResourceGroupName $connectionParams.resourceGroup `
                        -Name $connectionParams.name
                ).Context
                $Settings["$($ConnectionName)_connectionString"] = $storageContext.ConnectionString
            }
            default {
                if ($ConnectionDefinition.Scope -in @('Platform', 'Application', 'Domain')) {
                    Write-Warning "Unsupported service provider: $ServiceProvider"
                }
            }
        }

    }
    else {
        # Using managed identity
        switch ($ServiceProvider.ToLower()) {
            'keyvault' {
                $Settings["$($ConnectionName)Uri"] = "https://$($connectionParams.name).vault.azure.net"
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

                        $Settings["$($ConnectionName)_accessKey"] = $eventGridTopicKeys.Key1
                        $Settings["$($ConnectionName)_topicEndpoint"] = $eventGridTopic.Endpoint
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


                        $Settings["$($ConnectionName)_accessKey"] = $eventGridTopicKeys.Key1
                        $Settings["$($ConnectionName)_topicEndpoint"] = $eventGridTopic.Endpoint
                    }
                }
            }
            'servicebus' {
                $Settings["$($ConnectionName)_fullyQualifiedNamespace"] = "$($connectionParams.name).servicebus.windows.net"
            }
            'eventhubs' {
                $Settings["$($ConnectionName)_fullyQualifiedNamespace"] = "$($connectionParams.name).servicebus.windows.net"
            }
            'azureblob' {
                $Settings["$($ConnectionName)Uri"] = "https://$($connectionParams.name).blob.core.windows.net"
            }
            'azurefile' {
                # NOTE: Azure Storage Account File Share does not support managed identities for access yet.
                $azCtx = Get-AzureContext -SubscriptionId $SubscriptionId
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

                $Settings["$($ConnectionName)_connectionString"] = "DefaultEndpointsProtocol=https;EndpointSuffix=$($storageContext.EndPointSuffix);AccountName=$($connectionParams.name);AccountKey=$storageKey"

                # $Settings["$($ConnectionName)Uri"] = "FileEndpoint=https://$($connectionParams.name).file.core.windows.net;SharedAccessSignature=$sasToken"
                # $Settings["$($ConnectionName)Uri"] = "https://$($connectionParams.name).file.core.windows.net$sasToken"
            }
            'azuretables' {
                $Settings["$($ConnectionName)Uri"] = "https://$($connectionParams.name).table.core.windows.net"
            }
            'azurequeues' {
                $Settings["$($ConnectionName)Uri"] = "https://$($connectionParams.name).queue.core.windows.net"
            }
            default {
                Write-Warning "Unsupported service provider: $ServiceProvider"
            }
        }
    }
}

