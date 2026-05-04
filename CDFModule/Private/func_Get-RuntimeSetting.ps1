Function Get-RuntimeSetting {
    <#
    .SYNOPSIS
    Load CDF runtime settings from file or package source.

    .DESCRIPTION
    Reads CDF template input settings (definitions and configuration) from the local file system or
    an installed setting package. Returns a hashtable with the scope-specific settings, definitions,
    ConfigSource (FILE or PACKAGE), and ConfigVersion (from cdf-runtime.json release if available).

    This is a private helper used by the Get-Config* public functions to separate
    "settings" (static input, no Azure needed) from "config" (deployed output from Azure).

    .PARAMETER Scope
    The CDF scope to load settings for: Platform, Application, Domain, or Service.

    .PARAMETER SourceDir
    Path to the CDF infrastructure source directory containing config instance directories.

    .PARAMETER PlatformId
    Platform identifier.

    .PARAMETER InstanceId
    Platform instance identifier.

    .PARAMETER EnvDefinitionId
    Environment definition key used to look up the environment in definitions files.

    .PARAMETER Region
    Azure region name.

    .PARAMETER ApplicationId
    Application identifier. Required for Application, Domain, and Service scopes.

    .PARAMETER ApplicationInstance
    Application instance identifier. Required for Application, Domain, and Service scopes.

    .PARAMETER ApplicationEnvId
    Application environment definition key. Required for Application scope.

    .PARAMETER DomainName
    Domain name. Required for Domain and Service scopes.

    .PARAMETER ServiceName
    Service name. Required for Service scope.

    .PARAMETER ServiceSrcPath
    Path to the service source directory (for cdf-config.json). Required for Service scope.

    .PARAMETER CdfConfig
    Existing CdfConfig hashtable from prior scope. Required for Application, Domain, and Service scopes.
  #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Platform', 'Application', 'Domain', 'Service')]
        [string] $Scope,
        [Parameter(Mandatory = $true)]
        [string] $SourceDir,
        [Parameter(Mandatory = $false)]
        [string] $PlatformId,
        [Parameter(Mandatory = $false)]
        [string] $InstanceId,
        [Parameter(Mandatory = $false)]
        [string] $EnvDefinitionId,
        [Parameter(Mandatory = $false)]
        [string] $Region,
        [Parameter(Mandatory = $false)]
        [string] $ApplicationId,
        [Parameter(Mandatory = $false)]
        [string] $ApplicationInstance,
        [Parameter(Mandatory = $false)]
        [string] $ApplicationEnvId,
        [Parameter(Mandatory = $false)]
        [string] $DomainName,
        [Parameter(Mandatory = $false)]
        [string] $ServiceName,
        [Parameter(Mandatory = $false)]
        [string] $ServiceSrcPath,
        [Parameter(Mandatory = $false)]
        [hashtable] $CdfConfig
    )

    # Determine source path and detect config source type
    if ($Scope -eq 'Platform') {
        $sourcePath = "$SourceDir/$PlatformId/$InstanceId"
    }
    else {
        $sourcePath = "$SourceDir/$($CdfConfig.Platform.Config.platformId)/$($CdfConfig.Platform.Config.instanceId)"
    }

    $configVersion = $null
    $configSource = 'FILE'

    $runtimeManifestPath = Join-Path $sourcePath 'cdf-runtime.json'
    if (Test-Path $runtimeManifestPath) {
        $runtimeManifest = Get-Content -Raw $runtimeManifestPath | ConvertFrom-Json -AsHashtable
        $configVersion = $runtimeManifest.release

        # Detect PACKAGE source: path is under the CDF package cache
        $cacheRoot = Get-CdfPackageCacheRoot
        if ($sourcePath.StartsWith($cacheRoot)) {
            $configSource = 'PACKAGE'

            # Check staleness from cache index
            $staleDays = [int]($env:CDF_PACKAGE_STALE_DAYS ?? '30')
            $cacheIndex = Get-CdfCacheIndex
            $settingKey = "$($runtimeManifest.platformId)$($runtimeManifest.instanceId)"
            $indexEntry = $cacheIndex.packages | Where-Object {
                $_.type -eq 'settings' -and $_.path -eq $settingKey -and $_.release -eq $configVersion
            } | Select-Object -First 1

            if ($indexEntry -and $indexEntry.installed) {
                $installedDate = [DateTime]::Parse($indexEntry.installed)
                $age = (Get-Date) - $installedDate
                if ($age.TotalDays -gt $staleDays) {
                    Write-Warning "Setting package '${settingKey}:${configVersion}' was installed $([int]$age.TotalDays) days ago. Run Install-CdfPackage to check for updates."
                }
            }
        }
    }

    $result = @{
        ConfigSource  = $configSource
        ConfigVersion = $configVersion
    }

    switch ($Scope) {
        'Platform' {
            # Load platform definitions
            $platformEnvs = Get-Content -Raw "$sourcePath/platform/environments.json" | ConvertFrom-Json -AsHashtable
            $regionCodes = Get-Content -Raw "$sourcePath/platform/regioncodes.json" | ConvertFrom-Json -AsHashtable
            $regionNames = Get-Content -Raw "$sourcePath/platform/regionnames.json" | ConvertFrom-Json -AsHashtable

            $platformEnv = $platformEnvs[$EnvDefinitionId]
            $regionCode = $regionCodes[$Region.ToLower()]
            $regionName = $regionNames[$regionCode]
            $platformEnvKey = "$PlatformId$InstanceId$($platformEnv.nameId)"

            $result.Definitions = @{
                PlatformEnv    = $platformEnv
                RegionCode     = $regionCode
                RegionName     = $regionName
                PlatformEnvKey = $platformEnvKey
            }

            # Load platform config from file/package
            $platformConfigFile = "$sourcePath/platform/platform.$platformEnvKey-$regionCode.json"
            if (Test-Path $platformConfigFile) {
                Write-Verbose "Loading platform settings from $configSource"
                $CdfPlatform = Get-Content $platformConfigFile | ConvertFrom-Json -AsHashtable
                $CdfPlatform.Env = $platformEnv
                $CdfPlatform.ConfigSource = $configSource
                $CdfPlatform.ConfigVersion = $configVersion
            }
            else {
                throw "Platform configuration file not found. Path: $platformConfigFile"
            }

            $result.ScopeConfig = $CdfPlatform
        }

        'Application' {
            $platformKey = "$($CdfConfig.Platform.Config.platformId)$($CdfConfig.Platform.Config.instanceId)"
            $applicationKey = "$ApplicationId$ApplicationInstance"

            # Load application definitions
            $applicationEnvs = Get-Content -Raw "$sourcePath/application/environments.$applicationKey.json" | ConvertFrom-Json -AsHashtable
            $applicationEnv = $applicationEnvs[$ApplicationEnvId]

            $region = $CdfConfig.Platform.Env.region
            $regionCode = $CdfConfig.Platform.Env.regionCode
            $regionName = $CdfConfig.Platform.Env.regionName

            $platformEnvKey = "$platformKey$($CdfConfig.Platform.Env.nameId)"
            $applicationEnvKey = "$applicationKey$($applicationEnv.nameId)"

            $result.Definitions = @{
                ApplicationEnv    = $applicationEnv
                PlatformEnvKey    = $platformEnvKey
                ApplicationEnvKey = $applicationEnvKey
                RegionCode        = $regionCode
                RegionName        = $regionName
            }

            # Load application config from file/package
            $applicationConfigFile = "$sourcePath/application/application.$platformEnvKey-$applicationEnvKey-$regionCode.json"
            if (Test-Path $applicationConfigFile) {
                Write-Verbose "Loading application settings from $configSource"
                $CdfApplication = Get-Content $applicationConfigFile | ConvertFrom-Json -AsHashtable
                $CdfApplication.Env = $applicationEnv
                $CdfApplication.ConfigSource = $configSource
                $CdfApplication.ConfigVersion = $configVersion
            }
            else {
                throw "No application configuration file found for platform key '$platformEnvKey', application key '$applicationEnvKey' and region code '$regionCode'."
            }

            $result.ScopeConfig = $CdfApplication
        }

        'Domain' {
            $platformEnvKey = "$($CdfConfig.Platform.Config.platformId)$($CdfConfig.Platform.Config.instanceId)$($CdfConfig.Platform.Env.nameId)"
            $applicationEnvKey = "$($CdfConfig.Application.Config.applicationId ?? $CdfConfig.Application.Config.templateName)$($CdfConfig.Application.Config.instanceId)$($CdfConfig.Application.Env.nameId)"
            $regionCode = $CdfConfig.Platform.Env.regionCode

            $result.Definitions = @{
                PlatformEnvKey    = $platformEnvKey
                ApplicationEnvKey = $applicationEnvKey
                RegionCode        = $regionCode
            }

            # Load domain config from file/package
            $domainConfigFile = "$sourcePath/domain/domain.$platformEnvKey-$applicationEnvKey-$DomainName-$regionCode.json"
            if (Test-Path $domainConfigFile) {
                Write-Verbose "Loading domain settings from $configSource"
                $CdfDomain = Get-Content $domainConfigFile | ConvertFrom-Json -AsHashtable
                $CdfDomain.ConfigSource = $configSource
                $CdfDomain.ConfigVersion = $configVersion
            }
            else {
                Write-Warning "No domain configuration file found '$DomainName' with platform key '$platformEnvKey', application key '$applicationEnvKey' and region code '$regionCode'."
                $CdfDomain = [ordered] @{
                    IsDeployed    = $false
                    Env           = [ordered] @{}
                    Config        = [ordered] @{}
                    Features      = [ordered] @{}
                    ConfigSource  = 'NO-SOURCE'
                    ConfigVersion = $configVersion
                }
            }

            $result.ScopeConfig = $CdfDomain
        }

        'Service' {
            $platformEnvKey = "$($CdfConfig.Platform.Config.platformId)$($CdfConfig.Platform.Config.instanceId)$($CdfConfig.Platform.Env.nameId)"
            $applicationEnvKey = "$($CdfConfig.Application.Config.applicationId ?? $CdfConfig.Application.Config.templateName)$($CdfConfig.Application.Config.instanceId)$($CdfConfig.Application.Env.nameId)"
            $regionCode = $CdfConfig.Platform.Env.regionCode
            $domainNameVal = $CdfConfig.Domain.Config.domainName

            $result.Definitions = @{
                PlatformEnvKey    = $platformEnvKey
                ApplicationEnvKey = $applicationEnvKey
                RegionCode        = $regionCode
                DomainName        = $domainNameVal
            }

            # Load service config from infra config file
            $serviceConfigPath = "$sourcePath/service/service.$platformEnvKey-$applicationEnvKey-$domainNameVal-$ServiceName-$regionCode.json"

            $CdfService = Get-InfraServiceConfig `
                -ServiceName $ServiceName `
                -ServiceType ($CdfConfig.Service.Config.serviceType ?? '') `
                -ServiceGroup ($CdfConfig.Service.Config.serviceGroup ?? '') `
                -ServiceTemplate ($CdfConfig.Service.Config.serviceTemplate ?? '') `
                -ServiceConfigPath $serviceConfigPath

            $CdfService.ConfigSource = $configSource
            $CdfService.ConfigVersion = $configVersion

            $result.ScopeConfig = $CdfService
        }
    }

    $result.SourcePath = $sourcePath
    return $result
}
