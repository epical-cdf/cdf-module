
Function Add-ManagedApiConnectionAccess {
    <#
    .SYNOPSIS
    Adds an API Connection access policy for a user managed identity

    .DESCRIPTION
    User managed identities requires an access policy to be able to use API Connections and this commands adds the required access policy resource.

    .PARAMETER CdfConfig
    The CDFConfig object that holds the current scope configurations (Platform, Application and Domain)
    
    .PARAMETER ConnectionName
    The name of the managed API connection

    .PARAMETER ManagedIdentityResourceId
    ResourceId of the user managed indentity to give access

    .INPUTS
    CDF Config

    .OUTPUTS
    None.

    .EXAMPLE
    Add-CdfManagedApiConnectionAccess `
        -CdfConfig $config `
        -ConnectionName ExternalSystemA
        -ManagedIdentityResourceId /subscriptions/<guid>/resourceGroups/<rg>/provider/Microsoft.ManagedIdentity/userAssignedIdentities/<name>
    .LINK
    Deploy-CdfManagedApiConnection
    Get-CdfManagedApiConnection

    #>

    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [Object]$CdfConfig,
        [Parameter(Mandatory = $true)]
        [string] $ConnectionName,
        [Parameter(Mandatory = $true)]
        [string] $ManagedIdentityResourceId
    )

    $apiConfig = $CdfConfig | Get-CdfManagedApiConnection -ConnectionKey $ConnectionName
    $azCtx = Get-CdfAzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId

    if ($apiConfig) {
        Write-Information "Got connection details, validating Api Connection and Managed Identity..."
        $apiConnection = Get-AzResource  `
            -DefaultProfile $azCtx `
            -ResourceId $apiConfig.connectionId
        
        $managedIdentity = Get-AzResource  `
            -DefaultProfile $azCtx `
            -ResourceId $ManagedIdentityResourceId
        
        if ($apiConnection -and $managedIdentity) {
            Write-Information "Validated, adding access for identity '$($managedIdentity.Name)'"

            # # Debug accessPolicy:
            # $accessPolicies = Get-AzResource -ResourceId "$($apiConnection.id)/accessPolicies"
            # $accessPolicies | ConvertTo-Json -Depth 10 | Write-Information
            # return
            $accessPolicy = @{
                principal = @{
                    type     = "ActiveDirectory"
                    identity = @{
                        tenantId = $CdfConfig.Platform.Env.tenantId
                        objectId = $managedIdentity.Properties.principalId
                    }
                }
            }
            $output = New-AzResource `
                -DefaultProfile $azCtx `
                -Location $CdfConfig.Platform.Env.region `
                -ResourceGroup $apiConnection.ResourceGroupName `
                -ResourceName "$($apiConnection.ResourceName)/CDF-$($managedIdentity.Name)" `
                -ResourceType "Microsoft.Web/connections/accessPolicies" `
                -Properties $accessPolicy `
                -Force

            if ($output) {
                Write-Information "Done."
            }
            else {
                Write-Warning "Unexpected result."
            }
        }
        else {
            Write-Warning "Could not validate API connection resource with name '$ConnectionName'"
        }
    }
    else {
        Write-Warning "Could not fetch API connection configuration for connection with name '$ConnectionName'"
    }

}