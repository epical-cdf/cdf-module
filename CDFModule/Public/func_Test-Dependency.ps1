Function Test-Dependency {
    <#
    .SYNOPSIS
    Validates CDF template dependency compatibility across installed packages.

    .DESCRIPTION
    Reads cdf-template.json manifests from all cached templates and validates:
    (a) All declared dependency release ranges are satisfied by installed packages
    (b) All requiredFeatures exist in the dependency's providedFeatures

    .PARAMETER CachePath
    Override the cache root for testing. Defaults to ~/.cdf/packages.

    .PARAMETER Silent
    Suppress output for use as a sub-call. Returns $true if all checks pass.

    .EXAMPLE
    Test-CdfDependency

    .EXAMPLE
    $valid = Test-CdfDependency -Silent

    .LINK
    Install-CdfPackage
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)]
        [string]$CachePath,
        [Parameter(Mandatory = $false)]
        [switch]$Silent
    )

    $cacheRoot = $CachePath ? $CachePath : (Get-CdfPackageCacheRoot)
    $templatesRoot = Join-Path $cacheRoot 'templates'

    if (-not (Test-Path $templatesRoot)) {
        if (-not $Silent) { Write-Host "No templates installed. Nothing to validate." }
        return $true
    }

    # Discover all installed template manifests
    $manifests = @{}
    $manifestFiles = Get-ChildItem -Path $templatesRoot -Filter 'cdf-template.json' -Recurse
    foreach ($file in $manifestFiles) {
        $manifest = Get-Content -Raw $file.FullName | ConvertFrom-Json -AsHashtable
        $key = "$($manifest.scope)/$($manifest.name)/$($manifest.version)"
        if (-not $manifests[$key]) {
            $manifests[$key] = @()
        }
        $manifests[$key] += $manifest
    }

    $warnings = @()
    $errors = @()

    foreach ($key in $manifests.Keys) {
        foreach ($manifest in $manifests[$key]) {
            $source = "${key}:$($manifest.release)"

            if (-not $manifest.dependencies) { continue }

            foreach ($depKey in $manifest.dependencies.Keys) {
                $dep = $manifest.dependencies[$depKey]
                $depRange = $dep.release
                $depRequiredFeatures = $dep.requiredFeatures ?? @()

                # Check if dependency is installed
                if (-not $manifests[$depKey]) {
                    $warnings += "[$source] Dependency '$depKey' ($depRange) is not installed."
                    continue
                }

                # Check release compatibility
                $depManifests = $manifests[$depKey]
                $matchingRelease = $depManifests | Where-Object {
                    Test-CdfSemverMatch -Release $_.release -Range $depRange
                }
                if (-not $matchingRelease) {
                    $installedReleases = ($depManifests | ForEach-Object { $_.release }) -join ', '
                    $warnings += "[$source] Dependency '$depKey' requires release '$depRange' but installed: $installedReleases"
                }

                # Check feature compatibility
                foreach ($depManifest in $depManifests) {
                    $providedFeatures = $depManifest.providedFeatures ?? @()
                    foreach ($requiredFeature in $depRequiredFeatures) {
                        if ($requiredFeature -notin $providedFeatures) {
                            $warnings += "[$source] Requires feature '$requiredFeature' from '$depKey' but it is not in providedFeatures."
                        }
                    }
                }
            }
        }
    }

    # Report results
    $allPassed = ($warnings.Count -eq 0) -and ($errors.Count -eq 0)

    if (-not $Silent) {
        if ($allPassed) {
            Write-Host "All dependency checks passed. ($($manifests.Count) template(s) validated)"
        }
        else {
            Write-Host "`nDependency validation results:"
            foreach ($w in $warnings) {
                Write-Warning $w
            }
            foreach ($e in $errors) {
                Write-Error $e
            }
            Write-Host "$($warnings.Count) warning(s), $($errors.Count) error(s)"
        }
    }

    return $allPassed
}
