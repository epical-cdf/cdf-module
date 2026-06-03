#!/usr/bin/env pwsh
# Auto-format staged PowerShell files using the repo PSScriptAnalyzer settings,
# then re-stage anything that changed. Never blocks the commit — the CI lint gate
# is the enforcement point; this hook just keeps formatting consistent.
$ErrorActionPreference = 'Stop'

$staged = git diff --cached --name-only --diff-filter=ACMR -- '*.ps1' |
    Where-Object { $_ -and (Test-Path $_) }
if (-not $staged) { exit 0 }

if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
    Write-Warning 'pre-commit: PSScriptAnalyzer not installed; skipping auto-format. (Install-Module PSScriptAnalyzer)'
    exit 0
}
Import-Module PSScriptAnalyzer

$root = (git rev-parse --show-toplevel).Trim()
$settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
$fixed = @()

foreach ($file in $staged) {
    $before = Get-Content -Raw -- $file
    Invoke-ScriptAnalyzer -Path $file -Settings $settings -Fix | Out-Null
    $after = Get-Content -Raw -- $file
    if ($before -ne $after) {
        git add -- $file
        $fixed += $file
    }
}

if ($fixed) {
    Write-Host "pre-commit: auto-formatted and re-staged:`n  $($fixed -join "`n  ")"
}
exit 0
