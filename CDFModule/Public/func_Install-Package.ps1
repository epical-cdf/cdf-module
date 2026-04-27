Function Install-Package {
    <#
    .SYNOPSIS
    Installs CDF template and config packages from a registry to the local cache.

    .DESCRIPTION
    Reads cdf-packages.json from the current directory (or explicit path), resolves semver ranges
    against the registry, downloads packages to the local cache, and sets CDF_INFRA_TEMPLATES_PATH
    and CDF_INFRA_SOURCE_PATH environment variables.

    Can also install individual packages when -TemplateRef or -ConfigRef is specified.

    .PARAMETER ManifestPath
    Path to cdf-packages.json. Defaults to ./cdf-packages.json.

    .PARAMETER TemplateRef
    Install a single template by reference (e.g. 'platform/cas/v2pub:2.1.0' or 'platform/cas/v2pub:^2.0.0').

    .PARAMETER ConfigRef
    Install a single config by reference (e.g. 'tsdc01:1.3.0' or 'tsdc01:^1.0.0').

    .PARAMETER Registry
    Registry endpoint override. Required when using -TemplateRef or -ConfigRef without a manifest.

    .PARAMETER Force
    Re-download packages even if already cached.

    .EXAMPLE
    Install-CdfPackage
    # Reads ./cdf-packages.json and installs all declared packages

    .EXAMPLE
    Install-CdfPackage -TemplateRef 'platform/cas/v2pub:^2.1.0' -Registry cdfcodex.azurecr.io

    .LINK
    Publish-CdfTemplate
    .LINK
    Get-CdfPackage
    .LINK
    Test-CdfDependency
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)]
        [string]$ManifestPath = './cdf-packages.json',
        [Parameter(Mandatory = $false)]
        [string]$TemplateRef,
        [Parameter(Mandatory = $false)]
        [string]$ConfigRef,
        [Parameter(Mandatory = $false)]
        [string]$Registry,
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    # Single package install mode
    if ($TemplateRef -or $ConfigRef) {
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
        $endpoint = $regConfig.endpoint

        if ($TemplateRef) {
            Install-CdfSinglePackage -Ref $TemplateRef -PackageType 'templates' -Provider $provider -Endpoint $endpoint -Force:$Force
        }
        if ($ConfigRef) {
            Install-CdfSinglePackage -Ref $ConfigRef -PackageType 'configs' -Provider $provider -Endpoint $endpoint -Force:$Force
        }
        return
    }

    # Manifest-based install
    if (-not (Test-Path $ManifestPath)) {
        throw "No cdf-packages.json found at '$ManifestPath'. Use -ManifestPath or create one."
    }

    $manifest = Get-Content -Raw $ManifestPath | ConvertFrom-Json -AsHashtable
    $inlineRegistries = $manifest.registries
    $providers = @{}
    $defaultEndpoint = $null

    # Collect all registry names referenced by packages
    $referencedRegistries = @('default')
    if ($manifest.templates) {
        foreach ($key in $manifest.templates.Keys) {
            $parsed = Split-CdfPackageRef $key
            if ($parsed.Registry) { $referencedRegistries += $parsed.Registry }
        }
    }
    if ($manifest.configs) {
        foreach ($key in $manifest.configs.Keys) {
            $parsed = Split-CdfPackageRef $key
            if ($parsed.Registry) { $referencedRegistries += $parsed.Registry }
        }
    }
    $referencedRegistries = $referencedRegistries | Select-Object -Unique

    # Initialize registry providers via layered resolution
    foreach ($regName in $referencedRegistries) {
        $regConfig = Resolve-CdfRegistryConfig -Name $regName -InlineRegistries $inlineRegistries
        $providers[$regName] = New-CdfRegistryProvider $regConfig
        if ($regName -eq 'default') {
            $defaultEndpoint = $regConfig.endpoint
        }
    }

    # Login to all registries
    foreach ($provider in $providers.Values) {
        $provider.Login()
    }

    $installedTemplates = @()
    $installedConfigs = @()

    # Install templates
    if ($manifest.templates) {
        foreach ($templateKey in $manifest.templates.Keys) {
            $range = $manifest.templates[$templateKey]

            # Parse registry from key (e.g. 'platform/cas/v2pub@custx')
            $parsed = Split-CdfPackageRef $templateKey
            $packagePath = $parsed.Path
            $regName = $parsed.Registry ?? 'default'
            $provider = $providers[$regName]
            $endpoint = $provider.Endpoint

            $registryPath = "cdf/templates/$packagePath"
            $availableReleases = $provider.ListReleases($registryPath)

            if (-not $availableReleases) {
                Write-Warning "No releases found for template '$packagePath' in registry '$endpoint'"
                continue
            }

            $bestRelease = Resolve-CdfBestRelease -AvailableReleases $availableReleases -Range $range
            if (-not $bestRelease) {
                Write-Warning "No release matching '$range' found for template '$packagePath'. Available: $($availableReleases -join ', ')"
                continue
            }

            $cached = Get-CdfCachedPackage -PackageType 'templates' -Endpoint $endpoint -PackagePath $packagePath -Release $bestRelease
            if ($cached.Cached -and -not $Force) {
                Write-Host "Template ${packagePath}:$bestRelease already cached."
            }
            else {
                if ($Force -and $cached.Cached) {
                    Remove-Item -Recurse -Force $cached.Path
                }
                Save-CdfPackageToCache -PackageType 'templates' -Endpoint $endpoint -PackagePath $packagePath -Release $bestRelease -Provider $provider
            }
            $installedTemplates += @{ Path = $packagePath; Release = $bestRelease; Endpoint = $endpoint }
        }
    }

    # Install configs
    if ($manifest.configs) {
        foreach ($configKey in $manifest.configs.Keys) {
            $range = $manifest.configs[$configKey]

            $parsed = Split-CdfPackageRef $configKey
            $packagePath = $parsed.Path
            $regName = $parsed.Registry ?? 'default'
            $provider = $providers[$regName]
            $endpoint = $provider.Endpoint

            $registryPath = "cdf/configs/$packagePath"
            $availableReleases = $provider.ListReleases($registryPath)

            if (-not $availableReleases) {
                Write-Warning "No releases found for config '$packagePath' in registry '$endpoint'"
                continue
            }

            $bestRelease = Resolve-CdfBestRelease -AvailableReleases $availableReleases -Range $range
            if (-not $bestRelease) {
                Write-Warning "No release matching '$range' found for config '$packagePath'. Available: $($availableReleases -join ', ')"
                continue
            }

            $cached = Get-CdfCachedPackage -PackageType 'configs' -Endpoint $endpoint -PackagePath $packagePath -Release $bestRelease
            if ($cached.Cached -and -not $Force) {
                Write-Host "Config ${packagePath}:$bestRelease already cached."
            }
            else {
                if ($Force -and $cached.Cached) {
                    Remove-Item -Recurse -Force $cached.Path
                }
                Save-CdfPackageToCache -PackageType 'configs' -Endpoint $endpoint -PackagePath $packagePath -Release $bestRelease -Provider $provider
            }
            $installedConfigs += @{ Path = $packagePath; Release = $bestRelease; Endpoint = $endpoint }
        }
    }

    # Set environment variables for backwards compatibility
    if ($installedTemplates.Count -gt 0 -and $defaultEndpoint) {
        $cacheRoot = Get-CdfPackageCacheRoot
        $templatesPath = Join-Path $cacheRoot "templates/$defaultEndpoint"
        $env:CDF_INFRA_TEMPLATES_PATH = $templatesPath
        Write-Host "Set CDF_INFRA_TEMPLATES_PATH=$templatesPath"
    }

    if ($installedConfigs.Count -gt 0) {
        $firstConfig = $installedConfigs[0]
        $cacheRoot = Get-CdfPackageCacheRoot
        $configPath = Join-Path $cacheRoot "configs/$($firstConfig.Endpoint)/$($firstConfig.Path)/$($firstConfig.Release)"
        $env:CDF_INFRA_SOURCE_PATH = $configPath
        Write-Host "Set CDF_INFRA_SOURCE_PATH=$configPath"
    }

    # Summary
    Write-Host "`nInstalled $($installedTemplates.Count) template(s) and $($installedConfigs.Count) config(s)."

    # Run dependency check
    if ($installedTemplates.Count -gt 0) {
        Test-Dependency -Silent:$false
    }
}

# Helper: Parse package ref with optional @registry suffix
Function Split-CdfPackageRef {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Ref
    )

    if ($Ref -match '^(.+)@([^@]+)$') {
        return @{
            Path     = $Matches[1]
            Registry = $Matches[2]
        }
    }
    return @{
        Path     = $Ref
        Registry = $null
    }
}

# Helper: Install a single package from a ref like 'platform/cas/v2pub:^2.1.0'
Function Install-CdfSinglePackage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Ref,
        [Parameter(Mandatory = $true)]
        [ValidateSet('templates', 'configs')]
        [string]$PackageType,
        [Parameter(Mandatory = $true)]
        [CdfRegistryProvider]$Provider,
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    if ($Ref -notmatch '^(.+):(.+)$') {
        throw "Invalid package reference '$Ref'. Expected format: '<path>:<release-or-range>'"
    }
    $packagePath = $Matches[1]
    $releaseOrRange = $Matches[2]

    $registryPath = "cdf/$PackageType/$packagePath"

    # If exact version, use directly; otherwise resolve from registry
    if ($releaseOrRange -match '^\d+\.\d+\.\d+') {
        $release = $releaseOrRange
    }
    else {
        $availableReleases = $Provider.ListReleases($registryPath)
        $release = Resolve-CdfBestRelease -AvailableReleases $availableReleases -Range $releaseOrRange
        if (-not $release) {
            throw "No release matching '$releaseOrRange' for '$packagePath'"
        }
    }

    $cached = Get-CdfCachedPackage -PackageType $PackageType -Endpoint $Endpoint -PackagePath $packagePath -Release $release
    if ($cached.Cached -and -not $Force) {
        Write-Host "$PackageType/${packagePath}:$release already cached at $($cached.Path)"
        return
    }
    if ($Force -and $cached.Cached) {
        Remove-Item -Recurse -Force $cached.Path
    }

    Save-CdfPackageToCache -PackageType $PackageType -Endpoint $Endpoint -PackagePath $packagePath -Release $release -Provider $Provider
    Write-Host "Installed $PackageType/${packagePath}:$release"
}
