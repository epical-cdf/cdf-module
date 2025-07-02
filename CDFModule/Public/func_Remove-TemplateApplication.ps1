Function Remove-TemplateApplication {
    <#
        .SYNOPSIS
        Removes a application runtime instance.

        .DESCRIPTION
        Remove Azure resources for a CDF template application.

        .PARAMETER CdfConfig
        The CDFConfig object that holds the current scope configurations (Platform, Application)

        .PARAMETER DryRun
        Shows what resources would be removed when command is run.

        .INPUTS
        CDFConfig

        .EXAMPLE
        PS> $config = Get-CdfConfigPlatform
        PS> Remove-CdfTemplateApplication `
            -CdfConfig $config `
            -DryRun
        PS> Remove-CdfTemplateApplication `
            -CdfConfig $config

        .LINK
        Get-CdfConfigPlatform
        Get-CdfConfigApplication
        Deploy-CdfTemplatePlatform
        Deploy-CdfTemplateApplication
        Remove-CdfTemplatePlatform

        #>


    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
        [Object]$CdfConfig,
        [Parameter(Mandatory = $false)]
        [switch] $Purge = $true,
        [Parameter(Mandatory = $false)]
        [switch] $DryRun
    )

    Begin {
    }
    Process {
        if ($CdfConfig.Platform.IsDeployed -eq $false -or $CdfConfig.Application.IsDeployed -eq $false) {
            $errMsg = 'Provided platform and application configurations are not deployed versions. Resources will be removed using template tags only.'
            Write-Warning -Message $errMsg
            # Write-Error -Message $errMsg
            # throw $errMsg
        }

        $region = $CdfConfig.Platform.Env.region
        $regionCode = $CdfConfig.Platform.Env.regionCode
        $platformKey = "$($CdfConfig.Platform.Config.platformId)$($CdfConfig.Platform.Config.instanceId)"
        $platformEnvKey = "$platformKey$($CdfConfig.Platform.Env.nameId)"
        $applicationKey = "$($CdfConfig.Application.Config.applicationId ?? $CdfConfig.Application.Config.templateName)$($CdfConfig.Application.Config.instanceId)"
        $applicationEnvKey = "$applicationKey$($CdfConfig.Application.Env.nameId)"
        $templateInstance = "$platformKey-$applicationKey-$regionCode"
        $templateEnvInstance = "$platformEnvKey-$applicationEnvKey-$regionCode"
        $deploymentName = "application-$templateEnvInstance"

        $cdfTagsWhereClause = " | where tags.TemplateScope=~'$($CdfConfig.Application.Config.templateScope)' "
        $cdfTagsWhereClause += "     and tags.TemplateName=~'$($CdfConfig.Application.Config.templateName)' "
        $cdfTagsWhereClause += "     and tags.TemplateVersion=~'$($CdfConfig.Application.Config.templateVersion)' "
        $cdfTagsWhereClause += "     and tags.TemplateEnv=~'$($CdfConfig.Application.Env.definitionId)' "
        $cdfTagsWhereClause += "     and tags.TemplateInstance=~'$templateInstance' "

        $azCtx = Get-CdfAzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId

        Write-Host "Starting removal of application resources for '$templateInstance' at '$region' within subscription [$($azCtx.Subscription.Name)]."

        Write-Host "-- Begin Phase #0 (Resources requiring special attention) -----------------------"

        # APIM Services tend to be sensitive to having its referenced resources removed before it is deleted.
        $query = "Resources "
        $query += " | where type =~ 'Microsoft.ApiManagement/service' "
        $query += $cdfTagsWhereClause
        $query += " | project id, name, resourceGroup, tags "

        Write-Verbose "Phase #0 ('APIM') Query: "
        Write-Verbose $query
        $apimResources = Search-AzGraph -DefaultProfile $azCtx  -Query $query
        $allResources = $apimResources

        foreach ($resource in $apimResources) {
            Write-Host "`tRemoving APIM service $($resource.Name)"
            if ($false -eq $DryRun) {
                Write-Verbose " resource id: $($resource.Id)"
                Remove-AzApiManagement  `
                    -DefaultProfile $azCtx `
                    -ResourceGroup $resource.ResourceGroup `
                    -Name $resource.Name

            }
        }

        Write-Host "-- End Phase #0"

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
        $query += $cdfTagsWhereClause
        $query += " | project id, name, resourceGroup, tags "

        Write-Verbose "Phase #1 (Resources without dependencies) Query: "
        Write-Verbose $query
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

        # Start second phase
        $azJobs = @()
        Write-Host "-- Begin Phase #2 (Resource Groups, Networks, Dependencies) -----------------------"

        # Remove Application resource groups
        Write-Verbose "Phase #2 (Resource Group)"
        $query = "ResourceContainers "
        $query += $cdfTagsWhereClause
        $query += " | project id, name, resourceGroup, tags "

        Write-Verbose "Phase #2 (Resource Group) Query: "
        Write-Verbose $query
        $resourceGroups = Search-AzGraph -DefaultProfile $azCtx  -Query $query
        foreach ($resourceGroup in $resourceGroups) {
            $locked = Get-AzResourceLock -DefaultProfile $azCtx -ResourceGroupName $resourceGroup.Name
            if (!$locked) {

                # Recovery Service Vault require specific removal procedures and will block resource group removal if not deleted.

                $query = "Resources "
                $query += " | where type =~ 'Microsoft.RecoveryServices/vaults' "
                $query += " | where resourceGroup =~'$resourceGroup.Name' "
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

        if ($CdfConfig.Application.IsDeployed) {

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
                    $CdfConfig.Application.ResourceNames.GetEnumerator()  | Where-Object Key -like '*SubNetName*' | ForEach-Object -Process {
                        if ( ($vNet.Subnets | Foreach-Object -Process { $_.Name }).Contains($_.Value)) {
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
        $query += $cdfTagsWhereClause
        $query += " | project id, name, resourceGroup, tags "
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
        $deployment = Get-AzDeployment -DefaultProfile $azCtx -Name $deploymentName -ErrorAction SilentlyContinue
        if ($Deployment) {
            Write-Host "`tRemoving deployment [$deploymentName]"

            if ($false -eq $DryRun) {
                Remove-AzDeployment -DefaultProfile $azCtx -Name $deploymentName -ErrorAction SilentlyContinue
            }
        }

        if ($azJobs.Length -gt 0) {
            if ($true -eq $DryRun) {
                Write-Error "Dry-run, but still found jobs."
            }

            Write-Host -NoNewline "`tWaiting for jobs to complete"
            $azJobs | ForEach-Object {
                Write-Host -NoNewline "."
                $_ | Receive-Job -Wait -AutoRemoveJob -Force -ErrorAction:Continue | Out-Null
            }
            Write-Host " Done."
        }
        Write-Host "-- End Phase #2"

        if ($Purge) {
            Write-Host "-- Begin Phase #3 (Purging soft-deleted resources) -----------------------"
            # Remove any pending key vault and api mangement deletion

            $azCtx = Get-AzureContext $CdfConfig.Platform.Env.subscriptionId
            Get-AzKeyVault -DefaultProfile $azCtx -InRemovedState | ForEach-Object -Process {
                if ($allResources -and ($allResources | ForEach-Object -Process { $_.Name }).Contains($_.VaultName)) {
                    Write-Host "`tPurging deleted Key Vault [$($_.VaultName)] (can be really slow, be patient)"
                    Remove-AzKeyVault -DefaultProfile $azCtx -VaultName $_.VaultName -InRemovedState -Force -Location $CdfConfig.Platform.Env.region
                }
            }

            # TODO: Replace with Az Module commands once available.
            $CdfConfig | Get-ApiManagementDeletedService | ForEach-Object -Process {
                if ($allResources -and ($allResources | ForEach-Object -Process { $_.Name }).Contains($_.name)) {
                    Write-Host "`tPurging deleted API Management service [$($_.name)] "
                    $CdfConfig | Remove-ApiManagementDeletedService -Name $_.name
                }
            }
            Write-Host "-- End Phase #3"
        }

        if ($CdfConfig.Platform.Config.configStoreType.ToUpper() -ne 'DEPLOYMENTOUTPUT' -and $false -eq $DryRun) {
            $regionDetails = [ordered] @{
              region = $region
              code   = $regionCode
              name   = $region
            }
            Remove-ConfigFromStore `
              -CdfConfig $CdfConfig `
              -Scope 'Application' `
              -EnvKey $platformEnvKey-$applicationEnvKey `
              -RegionDetails $regionDetails `
              -ErrorAction Continue
          }

        Write-Host "Completed."
    }
    End {
    }
}
