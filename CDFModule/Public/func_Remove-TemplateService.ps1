
Function Remove-TemplateService {
    <#
        .SYNOPSIS
        Removes a service runtime instance.

        .DESCRIPTION
        Remove Azure resources for a CDF template service.

        .PARAMETER CdfConfig
        The CDFConfig object that holds the current scope configurations (Platform, Application, Domain and Service)

        .PARAMETER DryRun
        Shows what resources would be removed when command is run.

        .INPUTS
        CDFConfig

        .OUTPUTS
        None.

        .EXAMPLE
        PS> $config = Get-CdfConfigApplication
        PS> Remove-CdfTemplateApplication `
            -CdfConfig $config `
            -DryRun
        PS> Remove-CdfTemplateApplication `
            -CdfConfig $config

        .LINK
        Deploy-CdfTemplatePlatform
        Deploy-CdfTemplateApplication
        Deploy-CdfTemplateDomain
        Deploy-CdfTemplateService
        Remove-CdfTemplatePlatform
        Remove-CdfTemplateApplication
        Remove-CdfTemplateDomain
        Remove-CdfTemplateService

        #>


    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
        [Object]$CdfConfig,
        [Parameter(Mandatory = $false)]
        [switch] $DryRun
    )

    Begin {
    }
    Process {
        if ($CdfConfig.Platform.IsDeployed -eq $false -or $CdfConfig.Application.IsDeployed -eq $false -or $CdfConfig.Domain.IsDeployed -eq $false -or $CdfConfig.Service.IsDeployed -eq $false) {
            $errMsg = 'Provided platform, application, domain and service configurations are not deployed versions.'
            Write-Error -Message $errMsg
            throw $errMsg
        }

        $region = $CdfConfig.Platform.Env.region
        $regionCode = $CdfConfig.Platform.Env.regionCode
        $platformKey = "$($CdfConfig.Platform.Config.platformId)$($CdfConfig.Platform.Config.instanceId)"
        $platformEnvKey = "$platformKey$($CdfConfig.Platform.Env.nameId)"
        $applicationKey = "$($CdfConfig.Application.Config.applicationId ?? $CdfConfig.Application.Config.templateName)$($CdfConfig.Application.Config.instanceId)"
        $applicationEnvKey = "$applicationKey$($CdfConfig.Application.Env.nameId)"
        $templateInstance = "$platformKey-$applicationKey-$($CdfConfig.Domain.Config.domainName)-$($CdfConfig.Service.Config.serviceName)-$regionCode"
        $templateEnvInstance = "$platformEnvKey-$applicationEnvKey-$($CdfConfig.Domain.Config.domainName)-$($CdfConfig.Service.Config.serviceName)-$regionCode"
        $deploymentName = "service-$templateEnvInstance"

        $azCtx = Get-CdfAzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId

        Write-Host "Starting removal of service resources for '$templateEnvInstance' at '$region' within subscription [$($azCtx.Subscription.Name)]."

        $azJobs = @()

        # TODO: Add optional removal of storage fileshares etc that belong to the domain?
        # TODO: Add optional removal of platform/application managed identity access related to domain?

        try {
            # Get all managed identities, then remove role assignments
            $query = "Resources "
            $query += " | where type=~'Microsoft.ManagedIdentity/userAssignedIdentities' "
            $query += "     and tags.TemplateScope=~'$($CdfConfig.Service.Config.templateScope)' "
            $query += "     and tags.TemplateName=~'$($CdfConfig.Service.Config.templateName)' "
            $query += "     and tags.TemplateVersion=~'$($CdfConfig.Service.Config.templateVersion)' "
            $query += "     and tags.TemplateEnv=~'$($CdfConfig.Application.Env.definitionId)' "
            $query += "     and tags.TemplateInstance=~'$templateInstance' "
            $query += " | project id, name, tags, properties.principalId "

            Write-Verbose "Executing: Search-AzGraph -DefaultProfile <azCtx>  -Query $query"
            $managedIdentities = Search-AzGraph -DefaultProfile $azCtx  -Query $query
            foreach ($mgdId in $managedIdentities) {
                Get-AzRoleAssignment -ObjectId $mgdId.properties_principalId `
                | Where-Object { $_.Description -and $_.Description.IndexOf($templateInstance) -gt -1 } | ForEach-Object -Process {
                    Write-Host " - Removing role assignment [$($_.RoleAssignmentName)] for service [$($_.Description)] role name [$($_.RoleDefinitionName)]"
                    Remove-AzRoleAssignment -DefaultProfile $azCtx -InputObject $_ | Out-Null
                }
            }

            if ($CdfConfig.Service.Config.serviceTemplate -eq 'logicapp-standard') {
                # Get all api connections, then remove obsolete accessPolicies
                $query = "Resources "
                $query += " | where type=~'Microsoft.Web/connections' "
                $query += "     and resourceGroup=='$($CdfConfig.Platform.ResourceNames.apiConnResourceGroupName)' "
                $query += " | project id, name, tags "

                Write-Verbose "Executing: Search-AzGraph -DefaultProfile <azCtx>  -Query $query"
                $apiConnections = Search-AzGraph -DefaultProfile $azCtx  -Query $query
                foreach ($api in $apiConnections) {
                    Get-AzResource `
                        -ResourceId "$($api.id)/accessPolicies" `
                        -WarningAction:SilentlyContinue `
                        -ErrorAction:SilentlyContinue `
                    | Where-Object { $_.Name.IndexOf($templateInstance) -gt -1 } | ForEach-Object -Process {
                        Write-Host " - Removing access policy for service [$($_.Name)] of API Connection [$($api.Name)]"
                        $azJobs += Remove-AzResource `
                            -DefaultProfile $azCtx `
                            -ResourceId $_.ResourceId `
                            -Force `
                            -AsJob
                    }
                }
            }

            $query = "Resources "
            $query += " | where tags.TemplateScope=~'$($CdfConfig.Service.Config.templateScope)' "
            $query += "     and tags.TemplateName=~'$($CdfConfig.Service.Config.templateName)' "
            $query += "     and tags.TemplateVersion=~'$($CdfConfig.Service.Config.templateVersion)' "
            $query += "     and tags.TemplateEnv=~'$($CdfConfig.Application.Env.definitionId)' "
            $query += "     and tags.TemplateInstance=~'$templateInstance' "
            $query += " | project id, name, tags "
            Write-Verbose "Executing: Search-AzGraph -DefaultProfile <azCtx>  -Query $query"
            $resources = Search-AzGraph -DefaultProfile $azCtx  -Query $query
            foreach ($resource in $resources) {

                Write-Host "Removing resource $($resource.Name)"
                if ($false -eq $DryRun) {
                    Write-Verbose " resource id: $($resource.Id)"
                    $azJobs += Remove-AzResource `
                        -DefaultProfile $azCtx `
                        -ResourceId $resource.Id `
                        -Force  `
                        -AsJob
                }
            }

            foreach ($resourceNameKey in $CdfConfig.Service.ResourceNames.Keys) {
                if ($resourceNameKey.Contains('ResourceGroupName')) {
                    $resourceGroup = Get-AzResourceGroup `
                        -ErrorAction SilentlyContinue `
                        -DefaultProfile $azCtx `
                        -Name  $CdfConfig.Domain.ResourceNames[$resourceNameKey]

                    if ($null -ne $resourceGroup -And $resourceGroup.ResourceGroupName -eq $CdfConfig.Service.ResourceNames[$resourceNameKey]) {
                        Write-Host "Removing resource group $($resourceGroup.ResourceGroupName)"
                        if ($false -eq $DryRun) {
                            $azJobs += Remove-AzResourceGroup `
                                -DefaultProfile $azCtx `
                                -Name $resourceGroup.ResourceGroupName `
                                -Force -AsJob
                        }
                    }
                }
            }

            $vNetRGName = $CdfConfig.Platform.ResourceNames.networkingResourceGroupName
            $vNetName = $CdfConfig.Platform.ResourceNames.alzSpokeVNetName
            if ($vNetRGName -and $vNetName) {
                # TODO: Remove any service network resources

                # Remove subnet
                # $subNetName = $appResourceNames["appSubnetName"]

                # $vNet = Get-AzVirtualNetwork `
                #     -DefaultProfile $azCtx `
                #     -Name $vNetName `
                #     -ResourceGroupName $vNetRGName

                # if ($null -ne $vNet) {
                #     Write-Host "Removing subnet [$subNetName] from vNet [$($vNet.Name)]"
                #     if ($false -eq $DryRun) {
                #         Remove-AzVirtualNetworkSubnetConfig `
                #             -DefaultProfile $azCtx `
                #             -VirtualNetwork $vNet `
                #             -Name $subNetName `
                #         | Set-AzVirtualNetwork | Out-Null
                #     }
                # }
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

            # Remove deployment - last record of deployed resources if above fails with partial removal the process can be restarted if deployment is available.
            Write-Host "Removing deployment [$deploymentName]"
            if ($false -eq $DryRun) {
                Remove-AzResourceGroupDeployment `
                    -DefaultProfile $azCtx `
                    -ResourceGroupName $CdfConfig.Domain.ResourceNames.domainResourceGroupName `
                    -Name $deploymentName `
                    -ErrorAction SilentlyContinue
            }
            if ($CdfConfig.Platform.Config.configStoreType.ToUpper() -ne 'DEPLOYMENTOUTPUT' -and $false -eq $DryRun) {
                $regionDetails = [ordered] @{
                  region = $region
                  code   = $regionCode
                  name   = $region
                }
                Remove-ConfigFromStore `
                  -CdfConfig $CdfConfig `
                  -Scope 'Service' `
                  -EnvKey $platformEnvKey-$applicationEnvKey-$($CdfConfig.Domain.Config.domainName)-$($CdfConfig.Service.Config.serviceName) `
                  -RegionDetails $regionDetails `
                  -ErrorAction Continue
              }
        }
        catch {
            Write-Error $_
            throw $_
        }
    }
    End {
    }
}
