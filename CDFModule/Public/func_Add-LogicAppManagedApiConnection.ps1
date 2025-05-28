Function Add-LogicAppManagedApiConnection {
    <#
    .SYNOPSIS
    Adds a managed API Connection to a Logic App Standard

    .DESCRIPTION
    Adds a managed API Connection to a Logic App Standard

    .PARAMETER UseCS
    Switch indicating that connections should use connection strings instead of managed identities.

    .PARAMETER ConnectionName
    The name of the managed API connection

    .PARAMETER Connections
    Hashtable with contents of logic app standard connection.json. See examples.

    .PARAMETER ConnectionConfig
    Hashtable with connection configuration

    .EXAMPLE
    TBD
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)]
        [switch] $UseCS,
        [Parameter(Mandatory = $true)]
        [string] $ConnectionName,
        [Parameter(Mandatory = $true)]
        [hashtable] $Connections,
        [Parameter(Mandatory = $true)]
        [hashtable] $ConnectionConfig
    )

    $apiSettings = $Connections.managedApiConnections
    if ($null -eq $apiSettings ) {
        $apiSettings = [ordered] @{}
        $Connections.managedApiConnections = $apiSettings
    }

    if ($UseCS) {
        # not implemented

    }
    else {
        $connectionDef = [ordered] @{
            api                  = @{
                id = $ConnectionConfig.connectionApiId
            }
            authentication       = @{
                type     = 'ManagedServiceIdentity'
                identity = $ConnectionConfig.Identity
            }
            connection           = @{
                id = $ConnectionConfig.connectionId
            }
            connectionRuntimeUrl = $ConnectionConfig.connectionRuntimeUrl
        }
        $serviceProvider = $ConnectionConfig.connectionApiId.split('/')[-1]
        switch ($serviceProvider.ToLower()) {
            'azureeventgridpublish' {
            }
            'eventhubs' {
                $connectionDef.connectionProperties = @{
                    authentication = @{
                        audience = 'https://eventhubs.azure.net/'
                        identity = $ConnectionConfig.Identity
                        type     = 'ManagedServiceIdentity'
                    }
                }
            }
        }

        # $connectionConfig = $connectionConfigJson | ConvertFrom-Json -AsHashtable
        $Connections.managedApiConnections["$ConnectionName"] = $connectionDef
    }

}

