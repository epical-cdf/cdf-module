Function New-CdfPackageDeployView {
    <#
    .SYNOPSIS
    Materializes a classic-layout deploy view of installed packages and returns its paths.

    .DESCRIPTION
    Internal helper for Install-CdfPackage. The package cache stores
    {templates|configs}/<endpoint>/<path>/<release>/, which does not match what the
    Get-Cdf*Config* / Deploy-CdfTemplate* loaders expect. This builds a real-directory view
    (copy — NOT symlink: the loaders Resolve-Path-canonicalize, which would defeat a symlink)
    so the existing loaders work from the cache unchanged:

      <view>/templates/<scope>/<name>/<version>/   (contents of each template release dir)
      <view>/source/<platformId>/<instanceId>/      (contents of each config release dir;
                                                      ids read from the config's packed cdf-runtime.json)

    Callers set CDF_INFRA_TEMPLATES_PATH = .TemplatesPath and CDF_INFRA_SOURCE_PATH = .SourcePath.

    .PARAMETER Templates
    Installed template descriptors: @{ Endpoint; Path; Release } where Path = '<scope>/<name>/<version>'.

    .PARAMETER Configs
    Installed config descriptors: @{ Endpoint; Path; Release } where Path = '<configKey>'.

    .OUTPUTS
    [ordered] @{ TemplatesPath; SourcePath; ViewRoot }

    .NOTES
    Internal helper; not exported.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)]
        [array]$Templates = @(),
        [Parameter(Mandatory = $false)]
        [array]$Configs = @(),
        [Parameter(Mandatory = $false)]
        [string]$CacheRoot = (Get-CdfPackageCacheRoot)
    )

    # Deterministic per-resolution view: the same package set hashes to the same view root,
    # so a re-install of the same resolution reuses it and a different resolution gets its own.
    $refs = @(
        $Templates | ForEach-Object { "t:$($_.Endpoint)/$($_.Path)@$($_.Release)" }
        $Configs | ForEach-Object { "c:$($_.Endpoint)/$($_.Path)@$($_.Release)" }
    ) | Sort-Object
    $hashBytes = [System.Security.Cryptography.SHA1]::HashData([System.Text.Encoding]::UTF8.GetBytes(($refs -join ';')))
    $hash = (($hashBytes | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 12)

    $viewRoot = Join-Path -Path $CacheRoot -ChildPath ".views/$hash"
    $templatesView = Join-Path -Path $viewRoot -ChildPath 'templates'
    $sourceView = Join-Path -Path $viewRoot -ChildPath 'source'

    # Rebuild fresh — dirs are small and the path is content-addressed by the hash.
    if (Test-Path $viewRoot) { Remove-Item -Path $viewRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $templatesView -Force | Out-Null
    New-Item -ItemType Directory -Path $sourceView -Force | Out-Null

    foreach ($t in $Templates) {
        $src = Join-Path -Path $CacheRoot -ChildPath "templates/$($t.Endpoint)/$($t.Path)/$($t.Release)"
        if (-not (Test-Path $src)) { Write-Warning "Template package not cached, skipping view mapping: $src"; continue }
        $dst = Join-Path -Path $templatesView -ChildPath $t.Path   # <scope>/<name>/<version>
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
        Copy-Item -Path (Join-Path $src '*') -Destination $dst -Recurse -Force
    }

    foreach ($c in $Configs) {
        $src = Join-Path -Path $CacheRoot -ChildPath "configs/$($c.Endpoint)/$($c.Path)/$($c.Release)"
        if (-not (Test-Path $src)) { Write-Warning "Config package not cached, skipping view mapping: $src"; continue }
        $runtimePath = Join-Path -Path $src -ChildPath 'cdf-runtime.json'
        if (-not (Test-Path $runtimePath)) {
            Write-Warning "Config package '$($c.Path)' has no cdf-runtime.json; cannot place it in the deploy view."
            continue
        }
        $runtime = Get-Content -Raw $runtimePath | ConvertFrom-Json
        if (-not $runtime.platformId -or -not $runtime.instanceId) {
            Write-Warning "Config package '$($c.Path)' cdf-runtime.json lacks platformId/instanceId; cannot place it in the deploy view."
            continue
        }
        $dst = Join-Path -Path $sourceView -ChildPath "$($runtime.platformId)/$($runtime.instanceId)"
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
        Copy-Item -Path (Join-Path $src '*') -Destination $dst -Recurse -Force
    }

    return [ordered]@{
        TemplatesPath = $templatesView
        SourcePath    = $sourceView
        ViewRoot      = $viewRoot
    }
}
