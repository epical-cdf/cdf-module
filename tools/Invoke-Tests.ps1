<#
.SYNOPSIS
    Runs the CDFModule Pester test suite.
.DESCRIPTION
    Thin wrapper around Pester 5 used both locally and in CI. Discovers
    co-located *.Tests.ps1 files under the module path.
.EXAMPLE
    ./build/Invoke-Tests.ps1
.EXAMPLE
    ./build/Invoke-Tests.ps1 -CI   # emit NUnit results and fail the process on test failure
#>
[CmdletBinding()]
param(
    [string]$Path = './CDFModule',
    [switch]$CI
)

Import-Module Pester -MinimumVersion 5.5.0 -ErrorAction Stop

$config = New-PesterConfiguration
$config.Run.Path = $Path
$config.Output.Verbosity = 'Detailed'

if ($CI) {
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = './testResults.xml'
    $config.TestResult.OutputFormat = 'NUnitXml'
    # Throw (non-zero exit) when any test fails so the CI job is marked failed.
    $config.Run.Throw = $true
}

Invoke-Pester -Configuration $config
