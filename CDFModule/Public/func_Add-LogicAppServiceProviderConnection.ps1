Function Add-LogicAppServiceProviderConnection {
    <#
    .SYNOPSIS
    Adds a Service Provice Connection to a Logic App Standard

    .DESCRIPTION
    Adds a Service Provice Connection to a Logic App Standard

    .PARAMETER UseCS
    Switch indicating that connections should use connection strings instead of managed identities.

    .PARAMETER CdfConfig
    The CDFConfig object that holds the current scope configurations (Platform, Application and Domain)

    .PARAMETER Connections
    Hashtable with contents of logic app standard connection.json. See examples.

    .PARAMETER ConnectionName
    The name of the service provider connection

    .PARAMETER ServiceProvider
    The azure service provider identified e.g. AzureBlob, servicebus, keyvault

    .PARAMETER ManagedIdentityResourceId
    ResourceId of the user managed indentity to use for access

    .EXAMPLE
    connections.json:
    {
        "managedApiConnections": {},
        "serviceProviderConnections": {}
    }

    $connections = Get-Content "connections.json" | ConvertFrom-Json -AsHashtable
    Get-CdfServiceProviderConnection `
        -Connections $connections `
        -ConnectionName "PlatformServiceBus" `
        -ServiceProvider "servicebus"

    $connections | ConvertTo-Json -Depth 10 | Set-Content -Path "connections.json"

    connections.json (result):
    {
        "managedApiConnections": {},
        "serviceProviderConnections": {
            "PlatformServiceBus": {
                "displayName": "PlatformServiceBus Connection",
                "parameterSetName": "ManagedServiceIdentity",
                "parameterValues": {
                    "authProvider": {
                    "Type": "ManagedServiceIdentity"
                    },
                    "fullyQualifiedNamespace": "@appsetting('PlatformServiceBusUri')"
                },
                "serviceProvider": {
                    "id": "/serviceProviders/servicebus"
                }
            },
        }
    }
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)]
        [switch] $UseCS,
        [Parameter(Mandatory = $true)]
        [hashtable] $Connections,
        [Parameter(Mandatory = $true)]
        [string] $ConnectionName,
        [Parameter(Mandatory = $true)]
        [string] $ServiceProvider,
        [Parameter(Mandatory = $true)]
        [string] $ManagedIdentityResourceId
    )

    $providerSettings = $Connections.serviceProviderConnections
    if ($null -eq $providerSettings ) {
        $providerSettings = [ordered] @{}
        $Connections.serviceProviderConnections = $providerSettings
    }

    if ($UseCS) {
        $connectionConfig = [ordered] @{
            displayName      = "$($ConnectionName) Connection"
            parameterSetName = "connectionString"
            parameterValues  = @{
            }
            serviceProvider  = @{
                id = "/serviceProviders/$ServiceProvider"
            }
        }

        $Connections.serviceProviderConnections["$ConnectionName"] = $connectionConfig

        switch ($ServiceProvider.ToLower()) {
            'keyvault' {
                # No support for connection string
                $connectionConfig.parameterSetName = "ManagedServiceIdentity"
                $connectionConfig.parameterValues.VaultUri = "@appsetting('$($ConnectionName)Uri')"
                $connectionConfig.parameterValues.authProvider = @{
                    Identity = $ManagedIdentityResourceId
                    Type     = "ManagedServiceIdentity"
                }
            }
            'eventGridPublisher' {
                $connectionConfig.parameterSetName = "accessKey"
                $connectionConfig.parameterValues.accessKey = "@appsetting('$($ConnectionName)_accessKey')"
                $connectionConfig.parameterValues.topicEndpoint = "@appsetting('$($ConnectionName)_topicEndpoint')"
            }
            Default {
                $connectionConfig.parameterValues.connectionString = "@appsetting('$($ConnectionName)_connectionString')"
            }
        }
    }
    else {
        $connectionConfig = [ordered] @{
            displayName      = "$($ConnectionName) Connection"
            parameterSetName = "ManagedServiceIdentity"
            parameterValues  = @{
                authProvider = @{
                    Identity = $ManagedIdentityResourceId
                    Type     = "ManagedServiceIdentity"
                }
            }
            serviceProvider  = @{
                id = "/serviceProviders/$ServiceProvider"
            }
        }

        # $connectionConfig = $connectionConfigJson | ConvertFrom-Json -AsHashtable
        $Connections.serviceProviderConnections["$ConnectionName"] = $connectionConfig

        switch ($ServiceProvider.ToLower()) {
            'keyvault' {
                $connectionConfig.parameterValues.VaultUri = "@appsetting('$($ConnectionName)Uri')"
            }
            'eventGridPublisher' {
                # No support for manged identity
                $connectionConfig.parameterSetName = "accessKey"
                $connectionConfig.parameterValues.accessKey = "@appsetting('$($ConnectionName)_accessKey')"
                $connectionConfig.parameterValues.topicEndpoint = "@appsetting('$($ConnectionName)_topicEndpoint')"
            }
            'servicebus' {
                $connectionConfig.parameterValues.fullyQualifiedNamespace = "@appsetting('$($ConnectionName)_fullyQualifiedNamespace')"
            }
            'azureblob' {
                $connectionConfig.parameterValues.blobStorageEndpoint = "@appsetting('$($connectionName)Uri')"
            }
            'azuretables' {
                $connectionConfig.parameterValues.tableStorageEndpoint = "@appsetting('$($connectionName)Uri')"
            }
            'azurequeues' {
                $connectionConfig.parameterValues.queueStorageEndpoint = "@appsetting('$($connectionName)Uri')"
            }
            'azurefile' {
                # Azure Storage Account File Shares do not support managed identities, must always use connection string
                $Connections.serviceProviderConnections["$ConnectionName"] = [ordered] @{
                    displayName      = "$($ConnectionName) Connection"
                    parameterSetName = "connectionString"
                    parameterValues  = @{
                    }
                    serviceProvider  = @{
                        id = "/serviceProviders/$ServiceProvider"
                    }
                }
                $connectionConfig.parameterValues.connectionString = "@appsetting('$($connectionName)_connectionString')"
            }
            Default {
                # # It is common for custom connections to not use connection strings
                # $connectionConfig.parameterValues.connectionString = "@appsetting('$($ConnectionName)Uri')"
            }
        }
    }


}

