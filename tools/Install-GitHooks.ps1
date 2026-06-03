<#
.SYNOPSIS
    Installs the repo git hooks by pointing core.hooksPath at .githooks.
.DESCRIPTION
    Run once after cloning. The pre-commit hook auto-formats staged PowerShell
    files with PSScriptAnalyzer using the repo settings.
.EXAMPLE
    ./build/Install-GitHooks.ps1
#>
[CmdletBinding()]
param()

$root = (git rev-parse --show-toplevel).Trim()
git -C $root config core.hooksPath .githooks
Write-Host "Git hooks installed: core.hooksPath = .githooks (repo: $root)"
