Function Save-Config {
  [CmdletBinding()]
  Param(
    [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
    [Object]$CdfConfig,
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = 'The name used to store and restore the CDF confguration')]
    [string]$Name
  )
  # Save the CDF configuration to a file
  $CDF_USER_HOME = $env:APPDATA ?? $env:HOME
  $configFilePath = Join-Path -Path  $CDF_USER_HOME -ChildPath ".cdf/$Name-config.json"
  $envFilePath = Join-Path -Path  $CDF_USER_HOME -ChildPath ".cdf/$Name-env.json"
  $cdfEnv = @{}
  Get-ChildItem env:CDF_* | ForEach-Object {
    $cdfEnv[$_.Name] = $_.Value
  }
  $CdfConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $configFilePath -Force
  $cdfEnv | ConvertTo-Json -Depth 10 | Out-File -FilePath $envFilePath -Force
  Write-Host "CDF configuration saved to folder $(Split-Path -Parent $configFilePath)"
}