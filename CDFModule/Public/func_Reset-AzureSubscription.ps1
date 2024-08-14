Function Reset-AzureSubscription {
    <#
    .SYNOPSIS
    Removes all resources and deployments from subscription.

    .DESCRIPTION
    Deploy Azure resources for a platform template and configuration.

    .PARAMETER CdfConfig
    Instance configuration

    .PARAMETER Purge
    Enables purging for resources with soft-delete (KeyVaults and API Management instances)

    .PARAMETER IncludeRoles
    Enables removal of role assignments on the subscription. Be careful and ensure there is access through mgmt group.

    .EXAMPLE
    Reset-CdfAzureSubscription 41bd7a49-5748-438d-b225-d2c2763406c5 -SubscriptionId  -Purge

    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        [Parameter(Mandatory = $false)]
        [switch] $Purge,
        [Parameter(Mandatory = $false)]
        [switch] $IncludeRoles
    )

    $jobs = @()

    $azSubCtx = Get-AzContext -ListAvailable | Where-Object { $_.Subscription.Id -eq $SubscriptionId -and $_.Account.Id -eq $((Get-AzContext).Account.Id) }
    $groups = Get-AzResourceGroup -DefaultProfile $azSubCtx
    foreach ($group in $groups) {
        $locked = Get-AzResourceLock -DefaultProfile $azSubCtx -ResourceGroupName $group.ResourceGroupName
        if (!$locked) {
            Write-Host "Adding job for removing resource group: $($group.ResourceGroupName)"
            $jobs += Remove-AzResourceGroup -DefaultProfile $azSubCtx -Name $group.ResourceGroupName -Force -AsJob
        }
        else {
            Write-Host "Leaving locked resource group: $($group.ResourceGroupName)"
        }
    }

    if ($Purge -eq $true ) {
        # Purge removed keyvaults
        Get-AzKeyVault -DefaultProfile $azSubCtx -InRemovedState | ForEach-Object {
            Write-Host "Adding job for purging removed KeyVault: $($_.VaultName)"
            $jobs += Remove-AzKeyVault -DefaultProfile $azSubCtx -InRemovedState -Name $_.VaultName -Location $_.Location -Force -AsJob
        }

        # Purge removed APIM instances
        Get-AzApiManagementDeletedServices -DefaultProfile $azSubCtx | ForEach-Object {
            if ($null -ne $_.name -and '' -ne $_.name ) {
                Write-Host "Purging removed APIM Instance: $($_.name)"
                Remove-AzApiManagementDeletedService -DefaultProfile $azSubCtx -Name $_.name -Location $_.location
            }
        }
    }

    # Remove history of old deployments
    Get-AzSubscriptionDeployment -DefaultProfile $azSubCtx | ForEach-Object {
        Write-Host "Adding job for removing deployment: $($_.DeploymentName)"
        $jobs += Remove-AzSubscriptionDeployment -DefaultProfile $azSubCtx -Name $_.DeploymentName -AsJob
    }

    if ($IncludeRoles -eq $true ) {
        $scope = "/subscriptions/$($azSubCtx.Subscription.Id)"
        Get-AzRoleAssignment -DefaultProfile $azSubCtx -Scope $scope | ForEach-Object {
            if ($_.Scope -eq $scope) {
                Write-Host "Removing subscription role assignment: $($_.DisplayName)"
                Remove-AzRoleAssignment -DefaultProfile $azSubCtx  -InputObject $_ | Out-Null
            }
        }
    }

    if ($jobs.Length -gt 0) {
        Write-Host "Waiting for long running jobs such as removing resource groups to complete."
        $jobs | ForEach-Object {
            # Write-Verbose -Verbose "Output from job { $($_.Command) }"
            $_ | Receive-Job -Wait -AutoRemoveJob -Force
        }
    }
}

function Get-AzApiManagementDeletedServices {

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false, HelpMessage = 'Azure Context')]
        [System.Management.Automation.PSObject]
        $DefaultProfile,
        [Parameter(Mandatory = $false, HelpMessage = 'APIM API Version')]
        [string] $APIVersion = '2023-03-01-preview'
    )

    if ($DefaultProfile) {
        $azContext = $DefaultProfile
    }
    else {
        $azContext = Get-AzContext
    }
    $token = Get-AzAccessToken -DefaultProfile $azContext
    $authHeader = @{
        'Content-Type'  = 'application/json'
        'Authorization' = 'Bearer ' + $token.Token
    }
    $baseUri = "https://management.azure.com/subscriptions/$($azContext.Subscription)/providers/Microsoft.ApiManagement"
    $apiVersionQuery = "?api-version=$APIVersion"

    $restUri = "${baseUri}/deletedservices${apiVersionQuery}"
    try {
        $result = Invoke-RestMethod -ErrorAction SilentlyContinue -Uri $restUri -Method GET -Header $authHeader
        return $result.value
    }
    catch {}
    return $null
}

function Remove-AzApiManagementDeletedService {

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, HelpMessage = 'APIM Instance Name')]
        [string] $Name,
        [Parameter(Mandatory = $true, HelpMessage = 'APIM Instance Location')]
        [string] $Location,
        [Parameter(Mandatory = $false, HelpMessage = 'Azure Context')]
        [System.Management.Automation.PSObject]
        $DefaultProfile,
        [Parameter(Mandatory = $false, HelpMessage = 'APIM API Version')]
        [string] $APIVersion = '2023-03-01-preview'
    )

    if ($DefaultProfile) {
        $azContext = $DefaultProfile
    }
    else {
        $azContext = Get-AzContext
    }

    $token = Get-AzAccessToken -DefaultProfile $azContext
    $authHeader = @{
        'Content-Type'  = 'application/json'
        'Authorization' = 'Bearer ' + $token.Token
    }
    $baseUri = "https://management.azure.com/subscriptions/$($azContext.Subscription)/providers/Microsoft.ApiManagement"
    $apiVersionQuery = "?api-version=$APIVersion"

    $restUri = "${baseUri}/locations/${Location}/deletedservices/${Name}${apiVersionQuery}"
    Invoke-RestMethod -Uri $restUri -Method DELETE -Header $authHeader
}
