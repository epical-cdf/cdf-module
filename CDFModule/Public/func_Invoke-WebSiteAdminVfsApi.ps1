
Function Invoke-WebSiteAdminVfsApi {
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true, Position = 0, HelpMessage = "CDF Configuration hashtable")]
        [hashtable]$CdfConfig,
        [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Web site vfs path")]
        [string]$Uri,
        [Parameter(Mandatory = $false, HelpMessage = "HTTP Method for Uri")]
        [string]$Method = 'GET',
        [Parameter(Mandatory = $false, HelpMessage = "Azure Mgmt API Version")]
        [string]$ApiVersion = '2018-11-01',
        [Parameter(Mandatory = $false, HelpMessage = "Azure Mgmt API Version")]
        [string]$ETag,
        [Parameter(Mandatory = $false, HelpMessage = "Body of request when applicable")]
        [object]$Body
    )

    $subscriptionId = $CdfConfig.Platform.Env.subscriptionId
    $serviceRG = $CdfConfig.Domain.ResourceNames.domainResourceGroupName
    $serviceName = $CdfConfig.Service.ResourceNames.logicAppName

    $webAppUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$serviceRG/providers/Microsoft.Web/sites/$serviceName"
    $vfsPath = "/hostruntime/admin/vfs"
    $apiUrl = $webAppUri + $vfsPath + $Uri + "?api-version=" + $ApiVersion
    Write-Verbose "Invoke-AzRestMethod -Method $Method -Uri $apiUrl"
    if ($Body) {
        return Invoke-AzRestMethod -Method $Method -Uri $apiUrl -Payload $Body
    }
    else {
        return Invoke-AzRestMethod -Method $Method -Uri $apiUrl
    }
    # if ($Body) {
    #     $Headers = @{
    #         'If-Match' = '*'
    #     }
    #     return Invoke-AzRestMethod `
    #         -SubscriptionId $CdfConfig.Platform.Env.subscriptionId `
    #         -ResourceGroupName $CdfConfig.Domain.ResourceNames.domainResourceGroupName `
    #         -ResourceProviderName 'Microsoft.Web' `
    #         -ResourceType 'sites' `
    #         -Name $CdfConfig.Service.ResourceNames.logicAppName `
    #         -ApiVersion $ApiVersion `
    #         -Method $Method `
    #         -Uri "$vfsPath$Uri"  `
    #         -Payload $Body `
    #         -Headers $Headers
    # }
    # else {
    #     $result = Invoke-AzRestMethod `
    #         -SubscriptionId $CdfConfig.Platform.Env.subscriptionId `
    #         -ResourceGroupName $CdfConfig.Domain.ResourceNames.domainResourceGroupName `
    #         -ResourceProviderName 'Microsoft.Web' `
    #         -ResourceType 'sites' `
    #         -Name $CdfConfig.Service.ResourceNames.logicAppName `
    #         -ApiVersion $ApiVersion `
    #         -Method $Method `
    #         -Uri "$vfsPath$Uri"

    #     Write-Verbose $result
    #     return $result
    # }
}