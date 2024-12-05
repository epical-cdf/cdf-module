<#
.SYNOPSIS
Get .env variables as hashtable
#>

function Get-DotEnv {
    [Alias('dotenv')]
    param(
        [ValidateNotNullOrEmpty()]
        [Parameter(Position = 0)]
        [String] $Path = '.env'
    )

    $EnvHash = [ordered] @{}
    $lines = Get-Content -Path $Path
    foreach ($line in $lines) {
        $line = $line.Trim()

        if ($line.Length -eq 0) {
            Write-Verbose "Skipping empty line: [$line]"
            continue
        }
        if (-not $line.Contains('=')) {
            Write-Verbose "Skipping line without assigmment: [$line]"
            continue
        }

        $ePos = $line.IndexOf('=')
        $Name = $line.Substring(0, $ePos)
        $Value = $line.Substring($ePos + 1)

        if ([string]::IsNullOrWhiteSpace($name) || $name.Contains('#')) {
            continue
        }

        Write-Verbose "Adding '$Name' = '$Value'"
        $EnvHash[$Name] = $Value
    }
    return $EnvHash
}