Function Remove-OrphanAccessPolicies {
    <#
    .SYNOPSIS
    Remove orphan access policies for Api Connections
    .DESCRIPTION
    Deleting a logic app will leave managed identity access policies for Api Connections as unknown entries.
    These potentially stop redeployment of logic apps.
    .EXAMPLE
    $platform =  Get-PlatformConfig ...
    Remove-CdfOrphanAccessPolicies -Scope $platform
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )

    Write-Output "Preparing to remove access policies for discarded logic app identities."
    $azCtx = Get-AzureContext -SubscriptionId $SubscriptionId

    # Verify that the pipeline service principal has neccessary rights to query identities
    if ($azCtxd.Account.Type -eq "ServicePrincipal") {
        try {
            $sp = Get-AzADServicePrincipal -AppId $azCtxd.Account.Id
            $cdfInfraDeployerName = "Epical CDF Infrastructure Deployer"
            Get-AzADServicePrincipal -DisplayName $cdfInfraDeployerName
        }
        catch {
            if ((Get-Error).ErrorDetails.StartsWith("Insufficient privileges")) {
                throw "Service Principal for Deployment does not have required permission"
            }
        }
    }

    # Get all api connections
    $apiConnections = Get-AzResource `
        -DefaultProfile $azCtx `
        -ResourceType 'Microsoft.Web/connections'

    foreach ($api in $apiConnections) {
        # Handle API connections for Logic App V2 only - ensure the cdf templates deploy only V2 version.
        if ($api.Kind -ne "V2") {
            continue;
        }
        $apiConnAccessPolicies = Get-AzResource `
            -ResourceId "$($api.ResourceId)/accessPolicies" `
            -WarningAction:SilentlyContinue `
            -ErrorAction:SilentlyContinue
        foreach ($apiAccessPolicy in $apiConnAccessPolicies) {
            $policy = Get-AzResource  `
                -ResourceId $apiAccessPolicy.ResourceId  `
                -ExpandProperties `
                -WarningAction:SilentlyContinue `
                -ErrorAction:SilentlyContinue

            if ($null -ne $policy) {
                try {
                    $sp = Get-AzADServicePrincipal `
                        -ObjectId $policy.Properties.principal.identity.objectId `
                        -WarningAction SilentlyContinue `
                        -ErrorAction SilentlyContinue
                }
                catch {
                    $err = Get-Error
                    if (!($err.ErrorDetails -like "*does not exist*")) {
                        throw "Could not get service principal details: $($err|ConvertTo-Json)"
                    }
                }

                if ($null -eq $sp) {
                    Write-Output "Identity [$($policy.Properties.principal.identity.objectId)] is missing."
                    Write-Output " - Removing access policy for service [$($apiAccessPolicy.Name)] at [$($api.Name)]"
                    Remove-AzResource -Force `
                        -ResourceId $apiAccessPolicy.ResourceId `
                        -WarningAction:SilentlyContinue `
                        -ErrorAction:SilentlyContinue `
                    | Out-Null
                }
            }
        }
    }
}