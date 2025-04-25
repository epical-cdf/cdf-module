Function Restore-Config {
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = 'The name used to store and restore the CDF confguration')]
    [string]$Name
  )
  # Save the CDF configuration to a file
  $CDF_USER_HOME = $env:APPDATA ?? $env:HOME
  $configFilePath = Join-Path -Path  $CDF_USER_HOME -ChildPath ".cdf/$Name-config.json"
  $envFilePath = Join-Path -Path  $CDF_USER_HOME -ChildPath ".cdf/$Name-env.json"
  $CdfConfig = Get-Content -Path $configFilePath -Raw | ConvertFrom-Json -AsHashtable
  $cdfEnv = Get-Content -Path $envFilePath -Raw | ConvertFrom-Json -AsHashtable
  $cdfEnv.Keys | ForEach-Object {
    New-Item -Path "env:$_" -Value $cdfEnv[$_] -Force
  }
  Write-Host "CDF configuration loaded from $(Split-Path -Parent $configFilePath)"
  return $CdfConfig
}