Function Remove-TemplatePlatform {
    <#
        .SYNOPSIS
        Removes a platform runtime instance.

        .DESCRIPTION
        Remove Azure resources for a CDF template platform.

        .PARAMETER CdfConfig
        The CDFConfig object that holds the current scope configuration

        .PARAMETER DryRun
        Shows what resources would be removed when command is run.

        .INPUTS
        CDFConfig

        .EXAMPLE
        PS> $config = Get-CdfConfigPlatform
        PS> Remove-CdfTemplatePlatform `
            -CdfConfig $config `
            -DryRun
        PS> Remove-CdfTemplatePlatform `
            -CdfConfig $config

        .LINK
        Deploy-CdfTemplatePlatform
        Get-CdfConfigPlatform

        #>


    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
        [Object]$CdfConfig,
        [Parameter(Mandatory = $false)]
        [switch] $DryRun
    )

    Begin {
        if (-not (Get-Module Az.ResourceGraph -ListAvailable)) {
            Install-Module -Name Az.ResourceGraph -Scope CurrentUser -Force
        }
        Import-Module -Force -Name Az.ResourceGraph
    }
    Process {


        if ($CdfConfig.Platform.IsDeployed -eq $false) {
            $errMsg = 'Provided platform configuration is not deployed versions.'
            Write-Warning -Message $errMsg
            # Write-Error -Message $errMsg
            # throw $errMsg
        }

        $region = $CdfConfig.Platform.Env.region
        $regionCode = $CdfConfig.Platform.Env.regionCode
        $platformKey = "$($CdfConfig.Platform.Config.platformId)$($CdfConfig.Platform.Config.instanceId)"
        $platformEnvKey = "$platformKey$($CdfConfig.Platform.Env.nameId)"
        $templateInstance = "$platformKey-$regionCode"
        $templateEnvInstance = "$platformEnvKey-$regionCode"
        $deploymentName = "platform-$templateEnvInstance"

        $azCtx = Get-CdfAzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId

        Write-Host "Starting removal of platform resources for '$templateInstance' at '$region' within subscription [$($azCtx.Subscription.Name)]."

        Write-Host "-- Begin Phase #1 (Resources without dependencies) -----------------------"
        $azJobs = @()

        # Remove resources in Phase #1 - exclude those that fail on dependencies in first run.
        $excludedResoureTypeP1 = ' "Microsoft.Compute/disks"' # Must have virtual machine removed first.
        $excludedResoureTypeP1 += ', "Microsoft.Network/publicIPAddresses"'  # Resources using Public IPs always have to be removed first
        $excludedResoureTypeP1 += ', "Microsoft.Network/privateDnsZones"' # Any Virtual Network Links have to be removed first
        $excludedResoureTypeP1 += ', "Microsoft.Network/virtualNetworks/subnets"'  # Network specific
        $excludedResoureTypeP1 += ', "Microsoft.Network/networkSecurityGroups"' # Network specific, after subnet
        $excludedResoureTypeP1 += ', "Microsoft.Network/routeTables"' # Network specific, after subnet

        $query = "Resources "
        $query += " | where not(type in~ ( $excludedResoureTypeP1 )) "
        $query += " | where type != 'Microsoft.Network/VirtualNetwork' " # Explicitly exclude virtual networks not accidentally remove spoke vnet.
        $query += " | where tags.TemplateScope=~'$($CdfConfig.Platform.Config.templateScope)' "
        $query += "     and tags.TemplateName=~'$($CdfConfig.Platform.Config.templateName)' "
        $query += "     and tags.TemplateVersion=~'$($CdfConfig.Platform.Config.templateVersion)' "
        $query += "     and tags.TemplateEnv=~'$($CdfConfig.Platform.Env.definitionId)' "
        $query += "     and tags.TemplateInstance=~'$templateInstance' "
        $query += " | project id, name, tags "
        $resourcesP1 = Search-AzGraph -DefaultProfile $azCtx  -Query $query
        $allResources = $resourcesP1

        foreach ($resource in $resourcesP1) {

            Write-Host "`tRemoving resource $($resource.Name)"
            if ($false -eq $DryRun) {
                Write-Verbose " resource id: $($resource.Id)"
                $azJobs += Remove-AzResource `
                    -DefaultProfile $azCtx `
                    -ResourceId $resource.Id `
                    -Force  `
                    -AsJob
            }
        }

        # Wait for jobs to complete
        if ($azJobs.Length -gt 0) {
            if ($true -eq $DryRun) {
                Write-Error "Dry-run, but still found jobs."
            }

            Write-Host -NoNewline "`tWaiting for jobs to complete"
            $azJobs | ForEach-Object {
                Write-Host -NoNewline "."
                $_ | Receive-Job -Wait -AutoRemoveJob -Force  -ErrorAction:Continue | Out-Null
            }
            Write-Host " Done."
        }

        Write-Host "-- End Phase #1"


        # $azJobs = @()

        # $query = "Resources "
        # $query += " | where type != 'Microsoft.Network/VirtualNetwork' "
        # $query += " | where tags.TemplateScope=~'$($CdfConfig.Platform.Config.templateScope)' "
        # $query += "     and tags.TemplateName=~'$($CdfConfig.Platform.Config.templateName)' "
        # $query += "     and tags.TemplateVersion=~'$($CdfConfig.Platform.Config.templateVersion)' "
        # $query += "     and tags.TemplateEnv=~'$($CdfConfig.Platform.Env.definitionId)' "
        # $query += "     and tags.TemplateInstance=~'$templateInstance' "
        # $query += " | project id, name, tags "
        # $resources = Search-AzGraph -DefaultProfile $azCtx  -Query $query
        # foreach ($resource in $resources) {

        #     Write-Host "Removing resource $($resource.Name)"
        #     if ($false -eq $DryRun) {
        #         Write-Verbose " resource id: $($resource.Id)"
        #         $azJobs += Remove-AzResource `
        #             -DefaultProfile $azCtx `
        #             -ResourceId $resource.Id `
        #             -Force  `
        #             -AsJob
        #     }
        # }

        # Start second phase
        $azJobs = @()
        Write-Host "-- Begin Phase #2 (Resource Groups, Networks, Dependencies) -----------------------"

        # Remove Platform resource groups
        Write-Verbose "Phase #2 (Resource Group)"
        $query = "ResourceContainers "
        $query += " | where type =~ 'Microsoft.Resources/subscriptions/resourceGroups' "
        $query += " | where tags.TemplateScope=~'$($CdfConfig.Platform.Config.templateScope)' "
        $query += "     and tags.TemplateName=~'$($CdfConfig.Platform.Config.templateName)' "
        $query += "     and tags.TemplateVersion=~'$($CdfConfig.Platform.Config.templateVersion)' "
        $query += "     and tags.TemplateEnv=~'$($CdfConfig.Platform.Env.definitionId)' "
        $query += "     and tags.TemplateInstance=~'$templateInstance' "
        $query += " | project id, name, tags "
        $resourceGroups = Search-AzGraph -DefaultProfile $azCtx  -Query $query
        Write-Verbose "Phase #2 (Resource Group) Query: "
        Write-Verbose $query
        foreach ($resourceGroup in $resourceGroups) {
            $locked = Get-AzResourceLock -DefaultProfile $azCtx -ResourceGroupName $resourceGroup.Name
            if (!$locked) {

                # Recovery Service Vault require specific removal procedures and will block resource group removal if not deleted.
                $query = "Resources "
                $query += " | where type =~ 'Microsoft.RecoveryServices/vaults' "
                $query += " | where resourceGroup =~'$($resourceGroup.Name)' "
                $query += " | project id, name, resourceGroup, tags "

                Write-Verbose "Phase #2 (Recovery Services Vault) Query: "
                Write-Verbose $query
                $rsvResources = Search-AzGraph -DefaultProfile $azCtx  -Query $query
                $allResources += $rsvResources
                $rsvResources | ForEach-Object -Process {
                    Write-Host "`tRemoving recovery services vault $($_.Name)"
                    if ($false -eq $DryRun) {
                        Write-Verbose " recovery services id: $($_.Id)"
                        $CdfConfig | Remove-RecoveryServicesVault -VaultName $_.Name -ResourceGroup $_.ResourceGroup
                    }
                }

                Write-Host "`tRemoving resource group $($resourceGroup.Name)"
                if ($false -eq $DryRun) {
                    Write-Verbose " resource group id: $($resourceGroup.Id)"
                    $azJobs += Remove-AzResource `
                        -DefaultProfile $azCtx `
                        -ResourceId $resourceGroup.Id `
                        -Force  `
                        -AsJob
                }
            }
            else {
                Write-Host "`tLeaving locked resource group: $($resourceGroup.Name)"
            }
        }
        Write-Verbose "Phase #2 End (Resource Group)"

        if ($CdfConfig.Platform.IsDeployed) {
            # Get Network Configuration and clean up
            $vNetRGName = $CdfConfig.Platform.ResourceNames.networkingResourceGroupName
            $vNetName = $CdfConfig.Platform.ResourceNames.alzSpokeVNetName
            if ($vNetRGName -and $vNetName) {
                Write-Verbose "Phase #2 Begin (Networking)"
                $vNet = Get-AzVirtualNetwork `
                    -DefaultProfile $azCtx `
                    -Name $vNetName `
                    -ResourceGroupName $vNetRGName

                if ($null -ne $vNet) {
                    # Remove subnets
                    $CdfConfig.Platform.ResourceNames.GetEnumerator() | Where-Object Key -like '*SubNetName*' | ForEach-Object -Process {
                        if ($vNet -and $vNet.Subnets -and ($vNet.Subnets | Foreach-Object -Process { $_.Name }).Contains($_.Value)) {
                            Write-Host "`tRemoving Subnet [$($_.Value)] of vnet [$($vNet.Name)]"
                            if ($false -eq $DryRun) {
                                Remove-AzVirtualNetworkSubnetConfig `
                                    -DefaultProfile $azCtx `
                                    -VirtualNetwork $vNet `
                                    -Name $_.Value `
                                | Set-AzVirtualNetwork | Out-Null
                            }
                        }
                    }
                }
                Write-Verbose "Phase #2 End (Networking)"
            }
        }
        else {
            Write-Warning "Network resources may not have been removed (Application config is not deployed version)"
        }

        # Remove resources in Phase #2 - those that were not removed in first run.

        $query = "Resources "
        $query += " | where type != 'Microsoft.Network/VirtualNetwork' " # Explicitly exclude virtual networks not accidentally remove spoke vnet.
        $query += " | where tags.TemplateScope=~'$($CdfConfig.Platform.Config.templateScope)' "
        $query += "     and tags.TemplateName=~'$($CdfConfig.Platform.Config.templateName)' "
        $query += "     and tags.TemplateVersion=~'$($CdfConfig.Platform.Config.templateVersion)' "
        $query += "     and tags.TemplateEnv=~'$($CdfConfig.Platform.Env.definitionId)' "
        $query += "     and tags.TemplateInstance=~'$templateInstance' "
        $query += " | project id, name, tags "
        $resourcesP2 = Search-AzGraph -DefaultProfile $azCtx  -Query $query
        $allResources += $resourcesP2

        foreach ($resource in $resourcesP2) {

            Write-Host "`tRemoving resource $($resource.Name)"
            if ($false -eq $DryRun) {
                Write-Verbose " resource id: $($resource.Id)"
                $azJobs += Remove-AzResource `
                    -DefaultProfile $azCtx `
                    -ResourceId $resource.Id `
                    -Force  `
                    -AsJob
            }
        }

        # Remove deployment
        Write-Host "Removing deployment [$deploymentName]"
        if ($false -eq $DryRun) {
            Remove-AzDeployment -DefaultProfile $azCtx -Name $deploymentName -ErrorAction SilentlyContinue
        }

        if ($azJobs.Length -gt 0) {
            if ($true -eq $DryRun) {
                Write-Error "Dry-run, but still found jobs."
            }

            Write-Host -NoNewline "Waiting for long running jobs such as removing resource groups to complete "
            $azJobs | ForEach-Object {
                Write-Host -NoNewline "."
                $_ | Receive-Job -Wait -AutoRemoveJob -Force | Out-Null
            }
            Write-Host " Done."
        }
    }
    End {
    }
}
