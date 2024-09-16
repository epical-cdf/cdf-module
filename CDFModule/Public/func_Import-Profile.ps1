Function Import-Profile {
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $false)]
    [switch] $Force
  )

  Write-Verbose "Setting up PowerShell profile for CDF"
  $CDF_USER_HOME = $env:APPDATA ?? $env:HOME

  if ($Force -or ((Test-Path -Path $CDF_USER_HOME) -and -not (Test-Path -Path $CDF_USER_HOME/.local/cdf))) {
    Write-Verbose "Setting up .local/cdf config folder in user home"
    Write-Verbose "Path:"
    Write-Verbose $MyInvocation.MyCommand.Module.ModuleBase

    New-Item -Force -ItemType Directory -Path $CDF_USER_HOME/.local/cdf | Out-Null
    $CdfDefaultProfileLocation = Join-Path -Path $MyInvocation.MyCommand.Module.ModuleBase -ChildPath 'Resources/CDF-Profile.ps1'
    Copy-Item -Path $CdfDefaultProfileLocation `
      -Destination $CDF_USER_HOME/.local/cdf/CDF-Profile.ps1 | Out-Null
  }
}
