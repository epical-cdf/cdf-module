Function Add-LogicAppServiceProviderConnection {
    <#
    .SYNOPSIS
    Adds a Service Provice Connection to a Logic App Standard

    .DESCRIPTION
    Adds a Service Provice Connection to a Logic App Standard

    .PARAMETER UseCS
    Switch indicating that connections should use connection strings instead of managed identities.

    .PARAMETER Connections
    Hashtable with contents of logic app standard connection.json. See examples.

    .PARAMETER ConnectionName
    The name of the service provider connection

    .PARAMETER ConnectionDefinition
    connection definition

    .PARAMETER ManagedIdentityResourceId
    ResourceId of the user managed indentity to use for access

    .EXAMPLE
    connections.json:
    {
        "managedApiConnections": {},
        "serviceProviderConnections": {}
    }

    $connections = Get-Content "connections.json" | ConvertFrom-Json -AsHashtable
    $connectionDefinitions = $CdfConfig | Get-ConnectionDefinitions

    Add-CdfLogicAppServiceProviderConnection `
        -Connections $connections `
        -ConnectionName "PlatformServiceBus" `
        -ConnectionDefinition $connectionDefinitions[index] `
        -ManagedIdentityResourceId "identity id"

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
        [hashtable]$ConnectionDefinition,
        [Parameter(Mandatory = $true)]
        [string] $ManagedIdentityResourceId
    )

    $providerSettings = $Connections.serviceProviderConnections
    if ($null -eq $providerSettings ) {
        $providerSettings = [ordered] @{}
        $Connections.serviceProviderConnections = $providerSettings
    }
    $ServiceProvider = $ConnectionDefinition.ServiceProvider
    $SettingName = 'CON_' + $ConnectionDefinition.Scope.ToUpper() + '_' + $ServiceProvider.ToUpper() + '_'
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
                $connectionConfig.parameterValues.VaultUri = "@appsetting('$($SettingName)URI')"
                $connectionConfig.parameterValues.authProvider = @{
                    Identity = $ManagedIdentityResourceId
                    Type     = "ManagedServiceIdentity"
                }
            }
            'azureeventgridpublish' {
                $connectionConfig.parameterSetName = "accessKey"
                $connectionConfig.parameterValues.accessKey = "@appsetting('$($SettingName)ACCESSKEY')"
                $connectionConfig.parameterValues.topicEndpoint = "@appsetting('$($SettingName)TOPICENDPOINT')"
            }
            Default {
                $connectionConfig.parameterValues.connectionString = "@appsetting('$($SettingName)CONNECTIONSTRING')"
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
                $connectionConfig.parameterValues.VaultUri = "@appsetting('$($SettingName)URI')"
            }
            'azureeventgridpublish' {
                # No support for manged identity
                $connectionConfig.parameterSetName = "accessKey"
                $connectionConfig.parameterValues.accessKey = "@appsetting('$($SettingName)ACCESSKEY')"
                $connectionConfig.parameterValues.topicEndpoint = "@appsetting('$($SettingName)TOPICENDPOINT')"
            }
            'servicebus' {
                $connectionConfig.parameterValues.fullyQualifiedNamespace = "@appsetting('$($SettingName)FULLYQUALIFIEDNAMESPACE')"
            }
            'eventhubs' {
                $connectionConfig.parameterValues.fullyQualifiedNamespace = "@appsetting('$($SettingName)FULLYQUALIFIEDNAMESPACE')"
            }
            'azureblob' {
                $connectionConfig.parameterValues.blobStorageEndpoint = "@appsetting('$($SettingName)URI')"
            }
            'azuretables' {
                $connectionConfig.parameterValues.tableStorageEndpoint = "@appsetting('$($SettingName)URI')"
            }
            'azurequeues' {
                $connectionConfig.parameterValues.queueStorageEndpoint = "@appsetting('$($SettingName)URI')"
            }
            'azurefile' {
                # Azure Storage Account File Shares do not support managed identities, must always use connection string
                $Connections.serviceProviderConnections["$ConnectionName"] = [ordered] @{
                    displayName      = "$($SettingName) Connection"
                    parameterSetName = "connectionString"
                    parameterValues  = @{
                    }
                    serviceProvider  = @{
                        id = "/serviceProviders/$ServiceProvider"
                    }
                }
                $connectionConfig.parameterValues.connectionString = "@appsetting('$($SettingName)CONNECTIONSTRING')"
            }
            Default {
                # # It is common for custom connections to not use connection strings
                # $connectionConfig.parameterValues.connectionString = "@appsetting('$($SettingName)Uri')"
            }
        }
    }


}

