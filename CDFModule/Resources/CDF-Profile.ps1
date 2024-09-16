# File: CDF-Profile.ps1
# Microsoft PowerShell Profile

# Customize culture
$myCulture = Get-Culture
# $myCulture = Get-Culture -Name sv-SE
# $myCulture = Get-Culture -Name en-US
if ($null -ne (Get-Command Set-Culture -ErrorAction:SilentlyContinue)) {
    Set-Culture $myCulture
}
[System.Threading.Thread]::CurrentThread.CurrentUICulture = $myCulture
[System.Threading.Thread]::CurrentThread.CurrentCulture = $myCulture

# Customize output colors
# ANSI escape code are described here: 
# https://en.wikipedia.org/wiki/ANSI_escape_code#Colors

# $PSStyle.Formatting.FormatAccent = "`e[32;1m"
# $PSStyle.Formatting.ErrorAccent = "`e[36;1m"
# $PSStyle.Formatting.Error = "`e[31;1m"
# $PSStyle.Formatting.Warning = "`e[33;1m"

# Verbose as "Cyan+Bold".
# Warning and Verbose both Yellow as default in VSCode
$PSStyle.Formatting.Verbose = "`e[96;1m"

# $PSStyle.Formatting.Debug = "`e[33;1m"
# $PSStyle.Formatting.TableHeader = "`e[32;1m"
# $PSStyle.Formatting.CustomTableHeaderLabel = "`e[32;1;3m"
# $PSStyle.Formatting.FeedbackName = "`e[33m"
# $PSStyle.Formatting.FeedbackText = "`e[96m"
# $PSStyle.Formatting.FeedbackAction = "`e[97m"

#endregion

$usePrerelease = $true
$cdfModule = Get-Module -Name CDFModule -ListAvailable
if ($cdfModule.Count -gt 1) {
    Write-Verbose "More than one version of CDFModule installed, this is not recommended. Uninstalling."
    Uninstall-Module -Name CDFModule -AllVersions
    Install-Module -Name CDFModule -AllowPrerelease:$usePrerelease
}
elseif ($cdfModule.Count -eq 1) {
    Write-Verbose "Updating CDFModule to latest."
    Update-Module -Name CDFModule -AllowPrerelease:$usePrerelease
}
else {
    Write-Verbose "Installing lastest CDFModule."
    Install-Module -Name CDFModule -AllowPrerelease:$usePrerelease
}
Import-Module -Name CDFModule

# Import-Module posh-git

## Uncomment to enable the custom CDF prompt:
Set-Content -Path Function:/Prompt -Value (Get-Content -Path Function:/Show-CdfPrompt)

Write-Verbose " Done."
#endregion
