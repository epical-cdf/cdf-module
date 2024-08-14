
Function Invoke-LogicAppStdMgmtApi {
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $false, Position = 0, HelpMessage = "CDF Configuration hashtable")]
        [hashtable]$CdfConfig,
        [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Mgmt API uri")]
        [string]$Uri,
        [Parameter(Mandatory = $false, HelpMessage = "HTTP Method for Uri")]
        [string]$Method = 'GET',
        [Parameter(Mandatory = $false, HelpMessage = "Azure Mgmt API Version")]
        [string]$ApiVersion = '2018-11-01',
        [Parameter(Mandatory = $false, HelpMessage = "Body of request when applicable")]
        [string]$Body,
        [Parameter(Mandatory = $false, HelpMessage = "Indicates local development (Mgmt base url: http://7071)")]
        [switch]$Local
    )

    $logicAppMgmtPath = "/runtime/webhooks/workflow/api/management"
    if ($Local) {
        $logicAppUri = "http://localhost:7071"
        $apiUrl = $logicAppUri + $logicAppMgmtPath + $Uri + "?api-version=" + $ApiVersion
        Write-Verbose "Invoke-RestMethod -Method $Method -Uri $apiUrl"
        if ($Body) {
            $result = Invoke-RestMethod -Method $Method -Uri $apiUrl -Payload $Body
            return $result
        }
        else {
            $result = Invoke-RestMethod -Method $Method -Uri $apiUrl
            return $result
        }
    }
    else {
        $subscriptionId = $CdfConfig.Platform.Env.subscriptionId
        $serviceRG = $CdfConfig.Domain.ResourceNames.domainResourceGroupName
        $serviceName = $CdfConfig.Service.ResourceNames.logicAppName

        $logicAppUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$serviceRG/providers/Microsoft.Web/sites/$serviceName/hostruntime"
        $apiUrl = $logicAppUri + $logicAppMgmtPath + $Uri + "?api-version=" + $ApiVersion
        Write-Verbose "Invoke-AzRestMethod -Method $Method -Uri $apiUrl"
        if ($Body) {
            return Invoke-AzRestMethod -Method $Method -Uri $apiUrl -Payload $Body
        }
        else {
            return Invoke-AzRestMethod -Method $Method -Uri $apiUrl
        }
    }
}