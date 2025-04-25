Function Get-ConnectionDefinitions {
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
        [hashtable]$CdfConfig
    )

    $platformKey = $CdfConfig.Platform.Config.platformId + $CdfConfig.Platform.Config.instanceId
    $applicationKey = $platformKey + "-" + $CdfConfig.Application.Config.applicationId + $CdfConfig.Application.Config.instanceId
    $domainKey = $applicationKey + "-" + $CdfConfig.Domain.Config.domainName

    # Fetch all deployed API Connections and build a hashtable of connection definitions
    $connectionDefinitions = @{}
    Get-AzResourceGroupDeployment  -ResourceGroupName $CdfConfig.Platform.ResourceNames.apiConnResourceGroupName `
    | Where-Object {
        $_.DeploymentName -like "$platformKey-connection-*" -or `
            $_.DeploymentName -like "$applicationKey-connection-*" -or `
            $_.DeploymentName -like "$domainKey-connection-*"
    } `
    | ForEach-Object { 
        if ($_.DeploymentName -match '.+-connection-(.+)') {
            $deploymentName = $_.DeploymentName
            $connectionName = $matches[1]
            $connectionConfig = ($_.Outputs.connectionConfig | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable).Value
            $templateParameters = ($_.Parameters | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable)
            $connectionIds = @()
            $connectionConfig.Keys | ForEach-Object {
                if ($_ -match '(.+).onnectionId') {
                    $connectionIds += $matches[1]
                }
                elseif ($_ -eq 'connectionId') {
                    $connectionIds += $_
                }
            }
            $_.Parameters.Keys | ForEach-Object {
                if ($_ -like '*tags*') {
                    $connectionScope = $templateParameters[$_].Value.TemplateScope
                    # TODO: Add Provider Type check for ManagedApiConnection or ServiceProviderConnection to be used?
                    $isManagedApiConnection = $false 
                    Write-Verbose "Connection Scope: $connectionScope"
                }
            } 
            if (!$connectionScope -and $connectionName -like 'External*') {
                $connectionScope = 'external'
                $isManagedApiConnection = $true
            }
            if (!$connectionScope -and $connectionName -like 'Internal*') {
                $connectionScope = 'internal'
                $isManagedApiConnection = $true
            }
            if (!$connectionScope -and $connectionName -like 'Enterprise*') {
                $connectionScope = 'enterprise'
                $isManagedApiConnection = $true
            }

            Write-Verbose "Processing connection: $connectionName"
            Write-Verbose "DeploymentName: $deploymentName"
            Write-Verbose "Connection Config: $($connectionConfig | ConvertTo-Json -Depth 10)"

            foreach ($connectionId in $connectionIds) {
                Write-Verbose "Processing connectionId: $connectionId"
                if ($connectionId -eq 'connectionId') {
                    $serviceProvider = $connectionConfig['connectionApiId'].split('/')[-1]
                    $connectionDefinitions[$connectionName] = @{
                        ConnectionKey    = $connectionName
                        ServiceProvider  = $serviceProvider
                        Scope            = (Get-Culture).TextInfo.ToTitleCase($connectionScope)
                        IsEnabled        = $true
                        IsApiConnection  = $isManagedApiConnection
                        connectionConfig = $connectionConfig
                    }
                }
                else {
                    $serviceProvider = $connectionConfig["${connectionId}ConnectionApiId"].split('/')[-1]
                    $connectionSuffix = ( Get-Culture ).TextInfo.ToTitleCase( $connectionId )
                    $connectionDefinitions["${connectionName}$connectionSuffix"] = @{
                        ConnectionKey    = $connectionName
                        ServiceProvider  = $serviceProvider
                        Scope            = (Get-Culture).TextInfo.ToTitleCase($connectionScope)
                        IsEnabled        = $true
                        IsApiConnection  = $isManagedApiConnection
                        connectionConfig = @{
                            id                   = $connectionConfig.id
                            name                 = $connectionConfig.name
                            type                 = $connectionConfig.type
                            resourceGroup        = $connectionConfig.resourceGroup
                            apiResourceGroup     = $connectionConfig.apiResourceGroup
                            connectionId         = $connectionConfig["${connectionId}ConnectionId"]
                            connectionApiId      = $connectionConfig["${connectionId}ConnectionApiId"]
                            connectionRuntimeUrl = $connectionConfig["${connectionId}ConnectionRuntimeUrl"]
                        }
                    }
                }
            }
        }
    }

    return $connectionDefinitions
}