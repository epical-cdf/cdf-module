Import-Module PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path ./CDFModule/ -Settings ./PSScriptAnalyzerSettings.psd1 -Recurse -Fix
