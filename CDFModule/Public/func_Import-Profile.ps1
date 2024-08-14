Function Import-Profile {
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $false)]
    [switch] $Force
  )

  Write-Verbose "Setting up PowerShell profile for CDF"
  $CDF_USER_HOME = $env:APPDATA ?? $env:HOME

  if ($Force -or ((Test-Path -Path $CDF_USER_HOME) -and -not (Test-Path -Path $CDF_USER_HOME/.cdf))) {
    Write-Verbose "Setting up .cdf config folder in user home"
    Write-Verbose "Path:"
    Write-Verbose $MyInvocation.MyCommand.Module.ModuleBase

    New-Item -Force -ItemType Directory -Path $CDF_USER_HOME/.cdf | Out-Null
    Copy-Item -Path (Join-Path -Path $MyInvocation.MyCommand.Module.ModuleBase -ChildPath 'Resources/Microsoft.Profile.cdf.ps1') -Destination $CDF_USER_HOME/.cdf/Microsoft.PowerShell_profile.ps1 | Out-Null
  }

  if ((Test-Path -Path $CDF_USER_HOME) -and (Test-Path -Path $CDF_USER_HOME/.cdf)) {
    . "$CDF_USER_HOME/.cdf/Microsoft.PowerShell_profile.ps1"
  }
}
