# Local cache management for CDF packages
# Cache layout: ~/.cdf/packages/{templates|configs}/<endpoint>/<path>/<release>/

Function Get-CdfPackageCacheRoot {
    [CmdletBinding()]
    Param()

    $CDF_USER_HOME = $env:APPDATA ?? $env:HOME
    $cachePath = Join-Path -Path $CDF_USER_HOME -ChildPath '.cdf/packages'
    return $cachePath
}

Function Get-CdfPackageCachePath {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('templates', 'configs')]
        [string]$PackageType,
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        [Parameter(Mandatory = $true)]
        [string]$PackagePath,
        [Parameter(Mandatory = $true)]
        [string]$Release
    )

    $cacheRoot = Get-CdfPackageCacheRoot
    return Join-Path -Path $cacheRoot -ChildPath "$PackageType/$Endpoint/$PackagePath/$Release"
}

Function Get-CdfCachedPackage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('templates', 'configs')]
        [string]$PackageType,
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        [Parameter(Mandatory = $true)]
        [string]$PackagePath,
        [Parameter(Mandatory = $true)]
        [string]$Release
    )

    $cachePath = Get-CdfPackageCachePath -PackageType $PackageType -Endpoint $Endpoint -PackagePath $PackagePath -Release $Release
    if (Test-Path $cachePath) {
        return @{
            Path    = $cachePath
            Cached  = $true
            Release = $Release
        }
    }
    return @{
        Path    = $cachePath
        Cached  = $false
        Release = $Release
    }
}

Function Save-CdfPackageToCache {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('templates', 'configs')]
        [string]$PackageType,
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        [Parameter(Mandatory = $true)]
        [string]$PackagePath,
        [Parameter(Mandatory = $true)]
        [string]$Release,
        [Parameter(Mandatory = $true)]
        [CdfRegistryProvider]$Provider
    )

    $cachePath = Get-CdfPackageCachePath -PackageType $PackageType -Endpoint $Endpoint -PackagePath $PackagePath -Release $Release

    if (Test-Path $cachePath) {
        Write-Verbose "Package already cached at $cachePath"
        return $cachePath
    }

    Write-Host "Downloading $PackageType/${PackagePath}:$Release from $Endpoint..."
    $registryPath = "cdf/$PackageType/$PackagePath"
    $Provider.Pull($registryPath, $Release, $cachePath)

    # Update cache index
    Update-CdfCacheIndex -PackageType $PackageType -Endpoint $Endpoint -PackagePath $PackagePath -Release $Release -CachePath $cachePath

    return $cachePath
}

Function Get-CdfCacheIndex {
    [CmdletBinding()]
    Param()

    $cacheRoot = Get-CdfPackageCacheRoot
    $indexPath = Join-Path -Path $cacheRoot -ChildPath 'index.json'

    if (Test-Path $indexPath) {
        return Get-Content -Raw $indexPath | ConvertFrom-Json -AsHashtable
    }
    return @{
        packages = @()
    }
}

Function Update-CdfCacheIndex {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$PackageType,
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        [Parameter(Mandatory = $true)]
        [string]$PackagePath,
        [Parameter(Mandatory = $true)]
        [string]$Release,
        [Parameter(Mandatory = $true)]
        [string]$CachePath
    )

    $cacheRoot = Get-CdfPackageCacheRoot
    $indexPath = Join-Path -Path $cacheRoot -ChildPath 'index.json'

    $index = Get-CdfCacheIndex

    # Remove existing entry for same package+release if present
    $index.packages = @($index.packages | Where-Object {
            -not ($_.type -eq $PackageType -and $_.endpoint -eq $Endpoint -and $_.path -eq $PackagePath -and $_.release -eq $Release)
        })

    $index.packages += @{
        type      = $PackageType
        endpoint  = $Endpoint
        path      = $PackagePath
        release   = $Release
        cachePath = $CachePath
        installed = (Get-Date -Format 'o')
    }

    if (!(Test-Path (Split-Path $indexPath))) {
        New-Item -ItemType Directory -Path (Split-Path $indexPath) -Force | Out-Null
    }
    $index | ConvertTo-Json -Depth 5 | Out-File -FilePath $indexPath -Force
}

# Semver comparison utilities

Function Test-CdfSemverMatch {
    <#
    .SYNOPSIS
    Tests if a release version satisfies a semver range expression.
    Supports: >=x.y.z, ^x.y.z, ~x.y.z, x.y.z (exact)
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Release,
        [Parameter(Mandatory = $true)]
        [string]$Range
    )

    $releaseVersion = ConvertTo-CdfSemver $Release
    if ($null -eq $releaseVersion) { return $false }

    # Exact match
    if ($Range -match '^\d+\.\d+\.\d+') {
        if ($Range -notmatch '^[~^><=]') {
            $rangeVersion = ConvertTo-CdfSemver $Range
            return ($null -ne $rangeVersion) -and ($releaseVersion -eq $rangeVersion)
        }
    }

    # >=x.y.z
    if ($Range -match '^>=(.+)$') {
        $minVersion = ConvertTo-CdfSemver $Matches[1]
        return ($null -ne $minVersion) -and ($releaseVersion -ge $minVersion)
    }

    # ^x.y.z (compatible: same major, >= minor.patch)
    if ($Range -match '^\^(.+)$') {
        $baseVersion = ConvertTo-CdfSemver $Matches[1]
        if ($null -eq $baseVersion) { return $false }
        return ($releaseVersion.Major -eq $baseVersion.Major) -and ($releaseVersion -ge $baseVersion)
    }

    # ~x.y.z (reasonably close: same major.minor, >= patch)
    if ($Range -match '^~(.+)$') {
        $baseVersion = ConvertTo-CdfSemver $Matches[1]
        if ($null -eq $baseVersion) { return $false }
        return ($releaseVersion.Major -eq $baseVersion.Major) -and ($releaseVersion.Minor -eq $baseVersion.Minor) -and ($releaseVersion -ge $baseVersion)
    }

    Write-Warning "Unsupported semver range format: '$Range'"
    return $false
}

Function ConvertTo-CdfSemver {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$VersionString
    )

    # Strip prerelease/build metadata for comparison
    $cleanVersion = $VersionString -replace '-.*$', '' -replace '\+.*$', ''
    try {
        return [version]$cleanVersion
    }
    catch {
        Write-Warning "Invalid semver: '$VersionString'"
        return $null
    }
}

Function Resolve-CdfBestRelease {
    <#
    .SYNOPSIS
    Given a list of available releases and a semver range, returns the highest matching release.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string[]]$AvailableReleases,
        [Parameter(Mandatory = $true)]
        [string]$Range
    )

    $matching = $AvailableReleases | Where-Object { Test-CdfSemverMatch -Release $_ -Range $Range }
    if (-not $matching) { return $null }

    # Sort descending by version and pick the highest
    $sorted = $matching | Sort-Object { ConvertTo-CdfSemver $_ } -Descending
    return $sorted | Select-Object -First 1
}
