Function Publish-Config {
    <#
    .SYNOPSIS
    Publishes a CDF config package to an OCI registry.

    .DESCRIPTION
    Packs a config instance directory into an OCI artifact and pushes it to the configured registry.
    Requires a cdf-runtime.json manifest in the config instance directory.

    .PARAMETER ConfigPath
    Path to the config instance directory (e.g. ./src/tsdc/01). Must contain cdf-runtime.json.

    .PARAMETER Registry
    Registry endpoint (e.g. cdfcodex.azurecr.io). Overrides manifest/default.

    .PARAMETER Release
    Override the release version from the manifest. Useful for CI builds.

    .EXAMPLE
    Publish-CdfConfig -ConfigPath ./src/tsdc/01

    .EXAMPLE
    Publish-CdfConfig -ConfigPath ./src/tsdc/01 -Release 1.3.0-pre.1

    .LINK
    Install-CdfPackage
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        [Parameter(Mandatory = $false)]
        [string]$Registry,
        [Parameter(Mandatory = $false)]
        [string]$Release
    )

    $resolvedPath = Resolve-Path $ConfigPath -ErrorAction Stop
    $manifestPath = Join-Path $resolvedPath 'cdf-runtime.json'

    if (-not (Test-Path $manifestPath)) {
        throw "No cdf-runtime.json found in '$resolvedPath'. Cannot publish without a manifest."
    }

    $manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json -AsHashtable
    $platformId = $manifest.platformId
    $instanceId = $manifest.instanceId
    $releaseTag = $Release ? $Release : $manifest.release

    if (-not $releaseTag) {
        throw "No release version specified. Set 'release' in cdf-runtime.json or use -Release parameter."
    }

    $configKey = "$platformId$instanceId"

    # Resolve registry config (layered: project → user → inline manifest)
    $inlineRegistries = $null
    $pkgManifestPath = Join-Path (Get-Location) 'cdf-packages.json'
    if (Test-Path $pkgManifestPath) {
        $pkgManifest = Get-Content -Raw $pkgManifestPath | ConvertFrom-Json -AsHashtable
        $inlineRegistries = $pkgManifest.registries
    }
    if ($Registry -and $Registry -match '\.') {
        $regConfig = @{ type = 'acr'; endpoint = $Registry }
    }
    else {
        $regName = if ($Registry) { $Registry } else { 'default' }
        $regConfig = Resolve-CdfRegistryConfig -Name $regName -InlineRegistries $inlineRegistries
    }

    $packagePath = "cdf/configs/$configKey"
    $provider = New-CdfRegistryProvider $regConfig

    # Build OCI annotations from manifest metadata
    $annotations = @{
        'org.opencontainers.image.title'   = $configKey
        'org.opencontainers.image.version' = $releaseTag
        'cdf.config.platformId'            = $platformId
        'cdf.config.instanceId'            = $instanceId
    }
    if ($manifest.description) {
        $annotations['org.opencontainers.image.description'] = $manifest.description
    }

    Write-Host "Publishing config ${configKey}:$releaseTag to $($regConfig.endpoint)..."
    $provider.Login()
    $provider.Push($packagePath, $releaseTag, $resolvedPath.Path, $annotations)
    Write-Host "Successfully published ${configKey}:$releaseTag"
}
