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

        if ($true -eq $line.StartsWith('#')) {
            Write-Verbose "Skipping line with comment: [$line]"
            continue
        }

        $ePos = $line.IndexOf('=')
        $name = $line.Substring(0, $ePos)
        $value = $line.Substring($ePos + 1)

        Write-Verbose "Adding: '$name' = '$value'"
        $EnvHash[$name] = $value
    }
    Write-Output -InputObject $EnvHash
}