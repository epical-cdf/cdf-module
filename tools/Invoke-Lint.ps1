<#
.SYNOPSIS
    Runs PSScriptAnalyzer over the module using the repo settings.
.DESCRIPTION
    Default mode lints the whole module and reports issues. The -Changed mode is a
    diff-aware ratcheting CI gate: it analyzes changed PowerShell files but only
    fails on findings located on lines the change actually added/modified, so a PR
    cannot introduce new violations while pre-existing ones in touched files do not
    wall off the change.
.EXAMPLE
    ./tools/Invoke-Lint.ps1
.EXAMPLE
    ./tools/Invoke-Lint.ps1 -Changed -BaseRef origin/main
#>
[CmdletBinding()]
param(
    [string]$Path = './CDFModule',
    [switch]$Changed,
    [string]$BaseRef,
    [string]$SettingsPath = './PSScriptAnalyzerSettings.psd1'
)

Import-Module PSScriptAnalyzer -ErrorAction Stop

function Resolve-BaseRef {
    param([string]$BaseRef)
    if ($BaseRef) { return $BaseRef }
    if ($env:GITHUB_BASE_REF) { return "origin/$($env:GITHUB_BASE_REF)" }
    return 'HEAD~1'
}

function Get-ChangedPowerShellFile {
    param([string]$BaseRef)
    $diff = git diff --name-only --diff-filter=ACMR "$BaseRef...HEAD" -- '*.ps1'
    return @($diff | Where-Object { $_ -and (Test-Path $_) })
}

# Line numbers added/modified in $File versus $BaseRef (new-file side of each hunk).
function Get-ChangedLine {
    param([string]$File, [string]$BaseRef)
    $changed = [System.Collections.Generic.HashSet[int]]::new()
    $diff = git diff -U0 "$BaseRef...HEAD" -- $File
    foreach ($line in $diff) {
        if ($line -match '^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@') {
            $start = [int]$Matches[1]
            $count = if ($Matches[2]) { [int]$Matches[2] } else { 1 }
            for ($i = 0; $i -lt $count; $i++) { [void]$changed.Add($start + $i) }
        }
    }
    return $changed
}

if ($Changed) {
    $base = Resolve-BaseRef -BaseRef $BaseRef
    $files = Get-ChangedPowerShellFile -BaseRef $base
    if (-not $files) {
        Write-Host 'Lint: no changed PowerShell files.'
        exit 0
    }
    Write-Host "Lint: analyzing changed lines in:`n  $($files -join "`n  ")"
    $results = foreach ($file in $files) {
        $changedLines = Get-ChangedLine -File $file -BaseRef $base
        Invoke-ScriptAnalyzer -Path $file -Settings $SettingsPath |
            Where-Object { $changedLines.Contains([int]$_.Line) }
    }
}
else {
    Write-Host "Lint: analyzing '$Path' (recursive)."
    $results = Invoke-ScriptAnalyzer -Path $Path -Settings $SettingsPath -Recurse
}

$results = @($results)
if ($results.Count -gt 0) {
    $results | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host "PSScriptAnalyzer found $($results.Count) issue(s) on changed lines."
    exit 1
}

Write-Host 'PSScriptAnalyzer: no issues on changed lines.'
exit 0
