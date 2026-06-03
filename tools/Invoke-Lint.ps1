<#
.SYNOPSIS
    Runs PSScriptAnalyzer over the module using the repo settings.
.DESCRIPTION
    Default mode lints the whole module and reports issues. The -Changed mode
    lints only PowerShell files changed versus a base ref and fails (exit 1) on
    any issue — used as a ratcheting CI gate so new violations are blocked while
    the existing backlog does not wall off unrelated PRs.
.EXAMPLE
    ./build/Invoke-Lint.ps1
.EXAMPLE
    ./build/Invoke-Lint.ps1 -Changed -BaseRef origin/main
#>
[CmdletBinding()]
param(
    [string]$Path = './CDFModule',
    [switch]$Changed,
    [string]$BaseRef,
    [string]$SettingsPath = './PSScriptAnalyzerSettings.psd1'
)

Import-Module PSScriptAnalyzer -ErrorAction Stop

function Get-ChangedPowerShellFile {
    param([string]$BaseRef)

    if (-not $BaseRef) {
        if ($env:GITHUB_BASE_REF) { $BaseRef = "origin/$($env:GITHUB_BASE_REF)" }
        else { $BaseRef = 'HEAD~1' }
    }

    $diff = git diff --name-only --diff-filter=ACMR "$BaseRef...HEAD" -- '*.ps1'
    return @($diff | Where-Object { $_ -and (Test-Path $_) })
}

if ($Changed) {
    $files = Get-ChangedPowerShellFile -BaseRef $BaseRef
    if (-not $files) {
        Write-Host 'Lint: no changed PowerShell files.'
        exit 0
    }
    Write-Host "Lint: analyzing changed files:`n  $($files -join "`n  ")"
    $results = foreach ($file in $files) {
        Invoke-ScriptAnalyzer -Path $file -Settings $SettingsPath
    }
}
else {
    Write-Host "Lint: analyzing '$Path' (recursive)."
    $results = Invoke-ScriptAnalyzer -Path $Path -Settings $SettingsPath -Recurse
}

$results = @($results)
if ($results.Count -gt 0) {
    $results | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host "PSScriptAnalyzer found $($results.Count) issue(s)."
    exit 1
}

Write-Host 'PSScriptAnalyzer: no issues.'
exit 0
