Function Get-Package {
    <#
    .SYNOPSIS
    Lists available and installed CDF packages from a registry.

    .DESCRIPTION
    Queries the configured registry for available releases of a template or config package.
    Shows installed versions alongside available versions.

    .PARAMETER PackageRef
    Package reference (e.g. 'platform/cas/v2pub' for templates, 'tsdc01' for configs).

    .PARAMETER PackageType
    Type of package: 'templates' or 'configs'.

    .PARAMETER Registry
    Registry endpoint override.

    .PARAMETER ManifestPath
    Path to cdf-packages.json for registry resolution.

    .PARAMETER Installed
    Show only locally installed/cached packages.

    .EXAMPLE
    Get-CdfPackage -PackageRef 'platform/cas/v2pub' -PackageType templates

    .EXAMPLE
    Get-CdfPackage -Installed

    .LINK
    Install-CdfPackage
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)]
        [string]$PackageRef,
        [Parameter(Mandatory = $false)]
        [ValidateSet('templates', 'configs')]
        [string]$PackageType = 'templates',
        [Parameter(Mandatory = $false)]
        [string]$Registry,
        [Parameter(Mandatory = $false)]
        [string]$ManifestPath = './cdf-packages.json',
        [Parameter(Mandatory = $false)]
        [switch]$Installed
    )

    # Show installed packages from cache index
    if ($Installed -or -not $PackageRef) {
        $index = Get-CdfCacheIndex
        if ($index.packages.Count -eq 0) {
            Write-Host "No packages installed in cache."
            return
        }

        $packages = $index.packages
        if ($PackageRef) {
            $packages = $packages | Where-Object { $_.path -like "*$PackageRef*" }
        }
        if ($PackageType) {
            $packages = $packages | Where-Object { $_.type -eq $PackageType }
        }

        $packages | ForEach-Object {
            [PSCustomObject]@{
                Type      = $_.type
                Package   = $_.path
                Release   = $_.release
                Registry  = $_.endpoint
                Installed = $_.installed
                CachePath = $_.cachePath
            }
        } | Format-Table -AutoSize

        return
    }

    # Query registry for available releases
    $inlineRegistries = $null
    if (Test-Path $ManifestPath) {
        $manifest = Get-Content -Raw $ManifestPath | ConvertFrom-Json -AsHashtable
        $inlineRegistries = $manifest.registries
    }
    if ($Registry -and $Registry -match '\.') {
        $regConfig = @{ type = 'acr'; endpoint = $Registry }
    }
    else {
        $regName = if ($Registry) { $Registry } else { 'default' }
        $regConfig = Resolve-CdfRegistryConfig -Name $regName -InlineRegistries $inlineRegistries
    }
    $provider = New-CdfRegistryProvider $regConfig
    $provider.Login()
    $endpoint = $provider.Endpoint

    $registryPath = "cdf/$PackageType/$PackageRef"
    $releases = $provider.ListReleases($registryPath)

    if (-not $releases) {
        Write-Host "No releases found for $PackageType/$PackageRef in $endpoint"
        return
    }

    # Check which are cached locally
    $results = $releases | Sort-Object { ConvertTo-CdfSemver $_ } -Descending | ForEach-Object {
        $cached = Get-CdfCachedPackage -PackageType $PackageType -Endpoint $endpoint -PackagePath $PackageRef -Release $_
        [PSCustomObject]@{
            Package  = $PackageRef
            Release  = $_
            Cached   = $cached.Cached
            Registry = $endpoint
        }
    }

    $results | Format-Table -AutoSize
}
