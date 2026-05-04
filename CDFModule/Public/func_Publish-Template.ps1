Function Publish-Template {
    <#
    .SYNOPSIS
    Publishes a CDF template package to an OCI registry.

    .DESCRIPTION
    Packs a template directory into an OCI artifact and pushes it to the configured registry.
    Requires a cdf-template.json manifest in the template directory.

    .PARAMETER TemplatePath
    Path to the template directory (e.g. ./platform/cas/v2pub). Must contain cdf-template.json.

    .PARAMETER Registry
    Registry endpoint (e.g. cdfcodex.azurecr.io). Overrides manifest/default.

    .PARAMETER Release
    Override the release version from the manifest. Useful for CI builds.

    .EXAMPLE
    Publish-CdfTemplate -TemplatePath ./platform/cas/v2pub

    .EXAMPLE
    Publish-CdfTemplate -TemplatePath ./platform/cas/v2pub -Release 2.1.0-pre.1

    .LINK
    Install-CdfPackage
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$TemplatePath,
        [Parameter(Mandatory = $false)]
        [string]$Registry,
        [Parameter(Mandatory = $false)]
        [string]$Release
    )

    $resolvedPath = Resolve-Path $TemplatePath -ErrorAction Stop
    $manifestPath = Join-Path $resolvedPath 'cdf-template.json'

    if (-not (Test-Path $manifestPath)) {
        throw "No cdf-template.json found in '$resolvedPath'. Cannot publish without a manifest."
    }

    $manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json -AsHashtable
    $scope = $manifest.scope
    $name = $manifest.name
    $version = $manifest.version
    $releaseTag = $Release ? $Release : $manifest.release

    if (-not $releaseTag) {
        throw "No release version specified. Set 'release' in cdf-template.json or use -Release parameter."
    }

    # Resolve registry config (layered: project → user → inline manifest)
    $inlineRegistries = $null
    $pkgManifestPath = Join-Path (Get-Location) 'cdf-packages.json'
    if (Test-Path $pkgManifestPath) {
        $pkgManifest = Get-Content -Raw $pkgManifestPath | ConvertFrom-Json -AsHashtable
        $inlineRegistries = $pkgManifest.registries
    }
    if ($Registry -and $Registry -match '\.') {
        # Literal endpoint (e.g. ghcr.io/org or myacr.azurecr.io) — assume ACR for backwards compat
        $regConfig = @{ type = 'acr'; endpoint = $Registry }
    }
    else {
        $regName = if ($Registry) { $Registry } else { 'default' }
        $regConfig = Resolve-CdfRegistryConfig -Name $regName -InlineRegistries $inlineRegistries
    }

    $packagePath = "cdf/templates/$scope/$name/$version"
    $provider = New-CdfRegistryProvider $regConfig

    # Build OCI annotations from manifest metadata
    $annotations = @{
        'org.opencontainers.image.title'   = "$scope/$name/$version"
        'org.opencontainers.image.version' = $releaseTag
        'cdf.template.scope'               = $scope
        'cdf.template.name'                = $name
        'cdf.template.variant'             = $version
    }
    if ($manifest.description) {
        $annotations['org.opencontainers.image.description'] = $manifest.description
    }

    Write-Host "Publishing template $scope/$name/${version}:$releaseTag to $($regConfig.endpoint)..."
    $provider.Login()
    $provider.Push($packagePath, $releaseTag, $resolvedPath.Path, $annotations)
    Write-Host "Successfully published $scope/$name/${version}:$releaseTag"
}
