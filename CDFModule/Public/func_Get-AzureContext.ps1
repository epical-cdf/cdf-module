Function Get-AzureContext {
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $true)]
    [string] $SubscriptionId
  )

  $test = Get-AzContext -WarningAction:SilentlyContinue
  [Microsoft.Azure.Common.Authentication.AzureSession]::ClientFactory.AddUserAgent("pid-af839e51-6ff3-40ff-89d9-8b1afdb8adeb")

  $azSub = Get-AzSubscription -WarningAction:SilentlyContinue `
  | Where-Object { $_.Name -eq $SubscriptionId -or $_.Id -eq $SubscriptionId }

  if ( $null -eq $azSub) {
    Get-AzSubscription -WarningAction:SilentlyContinue | Format-Table
    Get-AzContext -WarningAction:SilentlyContinue -ListAvailable | Format-Table
    throw "Could not find subscription [$SubscriptionId] in available azure subscriptions."
  }
  $env:AZURE_HTTP_USER_AGENT = 'pid-af839e51-6ff3-40ff-89d9-8b1afdb8adeb'
  Set-AzContext -SubscriptionObject $azSub -WarningAction:SilentlyContinue | Out-Null
  $azCtx = Get-AzContext -WarningAction:SilentlyContinue

  return $azCtx
}


## Alternative implementation which will list all matching contexts and require additional filter on Account.
# Function Get-AzureContext {
#   [CmdletBinding()]
#   Param(
#     [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
#     [hashtable]$CdfConfig,
#     [Parameter(Mandatory = $false)]
#     [string] $SubscriptionId
#   )

#   $triggerAzureSession = Get-AzContext -WarningAction:SilentlyContinue
#   $triggerAzureSession -or [Microsoft.Azure.Common.Authentication.AzureSession]::ClientFactory.AddUserAgent("pid-af839e51-6ff3-40ff-89d9-8b1afdb8adeb") | Out-Null
#   $env:AZURE_HTTP_USER_AGENT = 'pid-af839e51-6ff3-40ff-89d9-8b1afdb8adeb'

#   if ($CdfConfig -and $CdfConfig.Platform -and $CdfConfig.Platform.Env) {
#     $SubscriptionId = $CdfConfig.Platform.Env.subscriptionId
#     Write-Verbose "Setting Azure Context from CdfConfig subscription: $SubscriptionId"
#     $azCtx = Get-AzContext -ListAvailable | Where-Object { $_.Subscription.Id -eq $CdfConfig.Platform.Env.subscriptionId -and $_.Tenant.Id -eq $CdfConfig.Platform.Env.tenantId }
#   }
#   else {
#     $azCtx = Get-AzContext -ListAvailable | Where-Object { $_.Subscription.Id -eq $CdfConfig.Platform.Env.subscriptionId -and $_.Tenant.Id -eq $CdfConfig.Platform.Env.tenantId }
#   }

#   if ( $null -eq $azCtx) {
#     Get-AzSubscription -WarningAction:SilentlyContinue | Format-Table
#     Get-AzContext -WarningAction:SilentlyContinue -ListAvailable | Format-Table
#     throw "Could not find subscription [$SubscriptionId] in available azure subscriptions."
#   }
#   return $azCtx
# }