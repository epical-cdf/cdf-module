function Remove-ApiManagementDeletedService {
    param(
        [ValidateNotNullOrEmpty()]
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [hashtable]$CdfConfig,
        [Parameter(Mandatory = $true)]
        [string] $Name
    )
    $azCtx = Get-AzureContext $CdfConfig.Platform.Env.subscriptionId
    $apiVersion = '?api-version=2022-04-01-preview'
    $baseUri = "https://management.azure.com/subscriptions/$($CdfConfig.Platform.Env.subscriptionId)/providers/Microsoft.ApiManagement/locations/$($CdfConfig.Platform.Env.region)"

    $restUri = "${baseUri}/deletedservices/${Name}${apiVersion}"
    $result = Invoke-AzRestMethod -DefaultProfile $azCtx -Uri $restUri -Method DELETE
    return $result.StatusCode
}
