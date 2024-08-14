function Get-ApiManagementDeletedService {
    param(
        [ValidateNotNullOrEmpty()]
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [hashtable]$CdfConfig
    )

    $azCtx = Get-AzureContext $CdfConfig.Platform.Env.subscriptionId
    $apiVersion = '2022-04-01-preview'
    $baseUri = "https://management.azure.com/subscriptions/$($CdfConfig.Platform.Env.subscriptionId)/providers/Microsoft.ApiManagement"

    $restUri = "${baseUri}/deletedservices?api-version=${apiVersion}"
    $result = Invoke-AzRestMethod -DefaultProfile $azCtx -Uri "$restUri" -Method GET
    $instances = ConvertFrom-Json -AsHashtable $result.Content
    return $instances.value
}
