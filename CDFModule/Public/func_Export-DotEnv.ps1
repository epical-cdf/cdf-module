<#
.SYNOPSIS
Export a CDF environment to a .env file.

.DESCRIPTION
The command reads a default .env file as template, default is './cfg/defaults.env'.
It then adds the CDF environment variables and finally writes the final .env file.

.PARAMETER CdfConfig
CDF Runtime Instance config

.PARAMETER InputEnv
Default/template .env file

.PARAMETER OutputEnv
Resulting/final .env file

#>

Function Export-DotEnv {
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        $CdfConfig,
        [Parameter(Mandatory = $false)]
        [string]$InputEnv = './cfg/defaults.env',
        [Parameter(Mandatory = $false)]
        [string]$OutputEnv = '.env'
    )

    Write-Verbose "Reading: $InputEnv"
    $defaultSettings = Get-CdfDotEnv $InputEnv
    $updatedSettings = $CdfConfig | Get-CdfServiceConfigSettings -UpdateSettings $defaultSettings -SecretValue
    Write-Verbose "Writing: $InputEnv"
    $updatedSettings | ConvertTo-CdfDotEnv | Set-Content -Path $OutputEnv
}
