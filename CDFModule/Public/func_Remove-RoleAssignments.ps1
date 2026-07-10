Function Remove-RoleAssignments {
    <#
    .SYNOPSIS
    Remove CDF-managed role assignments at a selected CDF scope, and optionally sweep orphans.

    .DESCRIPTION
    Given a resolved CdfConfig, traverses the resources of a selected scope (Platform,
    Application, Domain or Service) and removes the role assignments that CDF templates
    created there. This is the durable remedy when a role-assignment name (its Bicep
    `guid()` seed) has changed between deployments: Azure keys RoleAssignmentExists on the
    (principal, role, scope) triple, not on the assignment name, so a reseeded assignment
    collides with the stale one it orphaned. Removing the CDF-managed assignments at the
    scope lets the next Deploy-CdfTemplate* run recreate a clean, self-consistent set.

    Selection is deliberately conservative. By default only assignments defined *directly*
    at the traversed scope, and whose principal is in the CDF-managed set for that scope,
    are removed. The CDF-managed set is the deployer service principals
    (Env.infraDeployerSPObjectId / Env.solutionDeployerSPObjectId) plus every principal in
    AccessControl.keyVaultRBAC. Inherited assignments (from the subscription or a management
    group) and foreign principals are never touched unless -RemoveAll is given.

    Unlike a subscription-wide orphan sweep (which targets deleted principals only), this
    cmdlet is CdfConfig-driven and scope-targeted, and can remove assignments for *live*
    principals — the case a guid()-seed change produces.

    .PARAMETER CdfConfig
    A resolved CdfConfig (from Get-CdfConfig* / the pipeline). Must contain at least the
    Platform sub-config; Application/Domain/Service are used when those scopes are selected.

    .PARAMETER Scope
    Which CDF scope(s) to traverse: Platform, Application, Domain or Service. Defaults to
    Platform. Each scope's resources are resolved from its ResourceNames.

    .PARAMETER ResourceType
    Which CDF resource types to traverse for role assignments: KeyVault (default) or
    ResourceGroup. KeyVault targets the vaults named in ResourceNames (Platform also
    includes the dedicated certificate Key Vault). ResourceGroup targets the scope's
    resource groups.

    .PARAMETER IncludeOrphans
    Also remove assignments whose principal no longer exists (ObjectType 'Unknown') at the
    traversed scopes — a scope-targeted orphan sweep.

    .PARAMETER RemoveAll
    Remove every assignment defined directly at the traversed scopes, regardless of
    principal. A hard reset; use with care (still respects -WhatIf / -Confirm).

    .EXAMPLE
    # Preview which cert-KV / platform-KV assignments would be removed
    Get-CdfConfigPlatform | Remove-CdfRoleAssignments -Scope Platform -ResourceType KeyVault -WhatIf

    .EXAMPLE
    # Clear the CDF-managed KeyVault assignments so a reseeded platform deploy is clean
    Get-CdfConfigPlatform | Remove-CdfRoleAssignments -Scope Platform -ResourceType KeyVault -Confirm:$false

    .EXAMPLE
    # Sweep orphaned (deleted-principal) assignments across the platform resource groups
    Get-CdfConfigPlatform | Remove-CdfRoleAssignments -Scope Platform -ResourceType ResourceGroup -IncludeOrphans
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object] $CdfConfig,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Platform', 'Application', 'Domain', 'Service')]
        [string[]] $Scope = @('Platform'),

        [Parameter(Mandatory = $false)]
        [ValidateSet('KeyVault', 'ResourceGroup')]
        [string[]] $ResourceType = @('KeyVault'),

        [Parameter(Mandatory = $false)]
        [switch] $IncludeOrphans,

        [Parameter(Mandatory = $false)]
        [switch] $RemoveAll
    )

    process {
        # ResourceNames keys that hold Key Vault names / resource group names, per scope.
        $vaultKeysByScope = @{
            Platform    = @('certKeyVaultName', 'keyVaultName')
            Application = @('keyVaultName')
            Domain      = @('keyVaultName')
            Service     = @()
        }
        $rgKeysByScope = @{
            Platform    = @('networkResourceGroupName', 'platformResourceGroupName', 'monitoringResourceGroupName', 'apiConnResourceGroupName')
            Application = @('appResourceGroupName')
            Domain      = @('domainResourceGroupName')
            Service     = @()
        }

        $removed = [System.Collections.Generic.List[object]]::new()

        foreach ($scopeName in $Scope) {
            $scopeCfg = $CdfConfig.$scopeName
            if ($null -eq $scopeCfg) {
                Write-Warning "CdfConfig has no '$scopeName' scope - skipping."
                continue
            }

            $subscriptionId = $scopeCfg.Env.subscriptionId
            if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
                $subscriptionId = $CdfConfig.Platform.Env.subscriptionId
            }
            if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
                Write-Warning "Could not resolve subscriptionId for scope '$scopeName' - skipping."
                continue
            }
            $azCtx = Get-AzureContext -SubscriptionId $subscriptionId

            # Build the CDF-managed principal set for this scope (unless a hard reset is requested).
            $cdfPrincipalIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            if (-not $RemoveAll) {
                foreach ($sp in @($CdfConfig.Platform.Env.infraDeployerSPObjectId, $CdfConfig.Platform.Env.solutionDeployerSPObjectId)) {
                    if (-not [string]::IsNullOrWhiteSpace($sp)) { [void]$cdfPrincipalIds.Add($sp) }
                }
                foreach ($rbac in @($scopeCfg.AccessControl.keyVaultRBAC) + @($CdfConfig.Platform.AccessControl.keyVaultRBAC)) {
                    if ($null -ne $rbac -and -not [string]::IsNullOrWhiteSpace($rbac.principalId)) {
                        [void]$cdfPrincipalIds.Add($rbac.principalId)
                    }
                }
            }

            # Resolve the concrete Azure scopes (resourceIds) to traverse.
            $targets = [System.Collections.Generic.List[object]]::new()

            if ($ResourceType -contains 'KeyVault') {
                foreach ($key in $vaultKeysByScope[$scopeName]) {
                    $vaultName = $scopeCfg.ResourceNames.$key
                    if ([string]::IsNullOrWhiteSpace($vaultName)) { continue }
                    $kv = Get-AzKeyVault -DefaultProfile $azCtx -VaultName $vaultName -ErrorAction SilentlyContinue
                    if ($null -eq $kv) {
                        Write-Warning "[$scopeName] Key Vault '$vaultName' not found in subscription - skipping."
                        continue
                    }
                    $targets.Add([pscustomobject]@{ Kind = 'KeyVault'; Name = $vaultName; ScopeId = $kv.ResourceId })
                }
            }

            if ($ResourceType -contains 'ResourceGroup') {
                foreach ($key in $rgKeysByScope[$scopeName]) {
                    $rgName = $scopeCfg.ResourceNames.$key
                    if ([string]::IsNullOrWhiteSpace($rgName)) { continue }
                    $targets.Add([pscustomobject]@{
                            Kind    = 'ResourceGroup'
                            Name    = $rgName
                            ScopeId = "/subscriptions/$subscriptionId/resourceGroups/$rgName"
                        })
                }
            }

            foreach ($target in $targets) {
                $assignments = Get-AzRoleAssignment -DefaultProfile $azCtx -Scope $target.ScopeId -ErrorAction SilentlyContinue |
                    # Only assignments defined directly at this scope - never inherited ones.
                    Where-Object { $_.Scope -eq $target.ScopeId }

                foreach ($ra in $assignments) {
                    $isOrphan = ($ra.ObjectType -eq 'Unknown')
                    $isCdf = $cdfPrincipalIds.Contains([string]$ra.ObjectId)

                    $selected = $RemoveAll -or $isCdf -or ($IncludeOrphans -and $isOrphan)
                    if (-not $selected) { continue }

                    $reason = if ($RemoveAll) { 'all' } elseif ($isCdf) { 'cdf-managed' } else { 'orphan' }
                    $desc = "$($ra.RoleDefinitionName) for $($ra.ObjectId) ($reason) at [$($target.Kind)] $($target.Name)"

                    if ($PSCmdlet.ShouldProcess($target.ScopeId, "Remove role assignment: $desc")) {
                        Remove-AzRoleAssignment `
                            -DefaultProfile $azCtx `
                            -ObjectId $ra.ObjectId `
                            -RoleDefinitionName $ra.RoleDefinitionName `
                            -Scope $target.ScopeId `
                            -ErrorAction SilentlyContinue | Out-Null
                        Write-Host "Removed: $desc"
                    }

                    $removed.Add([pscustomobject]@{
                            Scope              = $scopeName
                            ResourceKind       = $target.Kind
                            ResourceName       = $target.Name
                            ScopeId            = $target.ScopeId
                            PrincipalId        = $ra.ObjectId
                            PrincipalType      = $ra.ObjectType
                            RoleDefinitionName = $ra.RoleDefinitionName
                            Reason             = $reason
                        })
                }
            }
        }

        Write-Host "Selected $($removed.Count) CDF role assignment(s) across scope(s): $($Scope -join ', ')."
        return $removed
    }
}
