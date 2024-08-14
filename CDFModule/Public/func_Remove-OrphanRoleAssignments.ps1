Function Remove-OrphanRoleAssignments {
    <#
    .SYNOPSIS
    Remove orphan access policies for Api Connections
    .DESCRIPTION
    Deleting a logic app will leave managed identity access policies for Api Connections as unknown entries.
    These potentially stop redeployment of logic apps.  
    .EXAMPLE
    $platform =  Get-PlatformConfig ...
    Remove-CdfOrphanRoleAssignments -Scope $platform
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )

    Write-Host "Preparing to remove role assignments for discarded identities."
    
    $azCtx = Get-AzureContext -SubscriptionId $SubscriptionId

    $objectType = "Unknown"
    $orphanedIdentities = Get-AzRoleAssignment `
        -DefaultProfile $azCtx `
        -Scope "/subscriptions/$SubscriptionId" `
    | Where-object -Property ObjectType -eq $objectType
    
    foreach ($identity in $orphanedIdentities) {
        # Role assignment removals will require the principal, definition name/id and scope of assignment to work
        if ($identity.Scope.StartsWith("/subscriptions/$SubscriptionId")) {
            Write-Host "Missing identity, removing obsolete role assignment for:"
            Write-Host "   RoleAssignmentName: $($identity.RoleAssignmentName)"
            Write-Host "   RoleDefinitionName: $($identity.RoleDefinitionName)"
            Write-Host "   ObjectId: $($identity.ObjectId)"
            Write-Host "   Scope: $($identity.Scope)"

            $identity

            if (($identity.ObjectId -ne "d1dc50f0-db45-41f6-9b35-334f5881fea2") -and 
                 ($identity.ObjectId -ne "9bed2009-2a7b-42fe-948f-26bb866bad8e")) {

                Remove-AzRoleAssignment `
                    -ErrorAction SilentlyContinue  `
                    -ObjectId $identity.ObjectId  `
                    -RoleDefinitionName $identity.RoleDefinitionName `
                    -Scope $identity.Scope `
                | Out-Null
            }
        }
    }
}