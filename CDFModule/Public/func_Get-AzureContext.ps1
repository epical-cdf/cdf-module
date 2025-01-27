Function Get-AzureContext {
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $true)]
    [string] $SubscriptionId
  )

  # Epical CDF Module CUA/PID for tracking usage
  if ($null -eq $env:CDF_TELEMETRY_OPT_OUT -or $env:CDF_TELEMETRY_OPT_OUT -ne 'true') {
    $env:AZURE_HTTP_USER_AGENT = 'pid-af839e51-6ff3-40ff-89d9-8b1afdb8adeb'
  }

  if ((Get-AzContext).Subscription.Id -eq $SubscriptionId) {
    Write-Verbose "Subscription [$SubscriptionId] is already selected."
    return (Get-AzContext)
  }

  try {
    Set-AzContext -SubscriptionId $SubscriptionId -WarningAction:SilentlyContinue | Out-Null
  }
  catch {
    Get-AzSubscription -WarningAction:SilentlyContinue | Format-Table
    Get-AzContext -WarningAction:SilentlyContinue -ListAvailable | Format-Table
    throw "Could not find subscription [$SubscriptionId] in available azure subscriptions."
  }

  # The following code is a workaround for sync/propagation issue where client credentials for app registrations/service principals are not immediately available after creation.
  # When the Select-AzSubscription is called for a new AzureContext it may warn for bad ClientCredentials until credentials propagation is completed.
  Write-Verbose 'Selecting subscription...'
  $warnClientSecretCredentialAuthFailed = $true; $attempt = 0; $maxAttempts = 15
  while ($warnClientSecretCredentialAuthFailed) {
    try {
      Select-AzSubscription -SubscriptionId $SubscriptionId -WarningAction Stop | Out-Null
      Write-Verbose "...done."
      $warnClientSecretCredentialAuthFailed = $false
    }
    catch {
      if ($_.Exception.Message.indexOf('ClientSecretCredential authentication failed') -gt 0) {
        Write-Verbose "...client credentials not yet synced, waiting for propagation attempt $attempt/$maxAttempts."
        $warnClientSecretCredentialAuthFailed = $true
      }
      Start-Sleep -Seconds 15
    }

    if ($attempt -gt $maxAttempts) {
      Write-Verbose "Giving up on exception: $($_.Exception.Message)"
      $warnClientSecretCredentialAuthFailed = $false
    }
  }
  $azCtx = Get-AzContext -WarningAction:SilentlyContinue

  return $azCtx
}
