Function Get-AzureContext {
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $true)]
    [string] $SubscriptionId,
    [Parameter(Mandatory = $false)]
    [string] $TenantId
  )

  # Epical CDF Module CUA/PID for tracking usage
  if ($null -eq $env:CDF_TELEMETRY_OPT_OUT -or $env:CDF_TELEMETRY_OPT_OUT -ne 'true') {
    $env:AZURE_HTTP_USER_AGENT = 'pid-af839e51-6ff3-40ff-89d9-8b1afdb8adeb'
  }

  # Verify credentials and subscription availability for the target tenant
  $getSubParams = @{ WarningAction = 'SilentlyContinue'; ErrorAction = 'Stop' }
  if ($TenantId) { $getSubParams.TenantId = $TenantId }

  try {
    $availableSubs = Get-AzSubscription @getSubParams
  }
  catch {
    if ($TenantId) {
      throw "Cannot retrieve subscriptions for tenant [$TenantId]. Credentials may be expired or missing. Please run: Connect-AzAccount -TenantId $TenantId"
    }
    throw "Cannot retrieve subscriptions. Please verify your Azure login with: Connect-AzAccount"
  }

  $targetSub = $availableSubs | Where-Object { $_.Id -eq $SubscriptionId }
  if (-not $targetSub) {
    $available = $availableSubs | Select-Object -Property Name, Id | Out-String
    $tenantMsg = if ($TenantId) { " in tenant [$TenantId]" } else { '' }
    throw "Subscription [$SubscriptionId] not found$tenantMsg. Available subscriptions:`n$available"
  }

  $azCtx = Get-AzContext
  if ($azCtx.Subscription.Id -eq $SubscriptionId -and (-not $TenantId -or $azCtx.Tenant.Id -eq $TenantId)) {
    Write-Verbose "Subscription [$SubscriptionId] is already selected."
  }
  else {
    Write-Verbose "Switching to subscription [$SubscriptionId]..."
    $setCtxParams = @{ SubscriptionId = $SubscriptionId; ErrorAction = 'Stop' }
    if ($TenantId) { $setCtxParams.Tenant = $TenantId }
    try {
      $azCtx = Set-AzContext @setCtxParams
    }
    catch {
      $targetTenant = if ($TenantId) { $TenantId } else { $targetSub.TenantId }
      throw "Failed to set Azure context for subscription [$SubscriptionId] in tenant [$targetTenant]. Credentials may be expired. Please run: Connect-AzAccount -TenantId $targetTenant"
    }
  }

  Write-Verbose "CDF Azure Context: Subscription '$($azCtx.Subscription.Name)' [$($azCtx.Subscription.Id)] in tenant '$($azCtx.Tenant.Id)'"
  return $azCtx
}
