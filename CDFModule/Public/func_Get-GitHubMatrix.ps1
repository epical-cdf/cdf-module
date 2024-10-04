Function Get-GitHubMatrix {
    <#
    .SYNOPSIS
    Get GitHub actions matrix for environment.

    .DESCRIPTION
    GitHub deployment workflows can make use of matrix for deployment to target environments. This cmdlet provides a hashtable object that can be used as matrix json.
    It contains the dependant environments. For instance if CdfConfig parameter has Domain config with environment,
    then it will provide the Domain env settings with dependent Application env and dependent Platform Env for the Application.

    .PARAMETER PlatformId
    Name of the platform instance

    .PARAMETER PlatformInstance
    Instance id for the platform

    .PARAMETER ApplicationId
    Name of the application instance

    .PARAMETER ApplicationInstance
    Instance id for the application

    .PARAMETER SourceDir
    Path to the platform instance source directory. Defaults to "./src".

    .INPUTS
    No piped input processed

    .OUTPUTS
    Matrix hashtable

    .EXAMPLE
    Get-CdfGitHubMatrix `
        -PlatformId api `
        -PlatformInstance 01 `
        -ApplicationId capim `
        -ApplicationInstance 01

    .EXAMPLE
    Get-CdfGitHubMatrix `
        -PlatformId api `
        -PlatformInstance 02 `
        -SourceDir "cdf-infra/src"

    .LINK

    #>

    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $Region = $env:CDF_REGION,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $PlatformId = $env:CDF_PLATFORM_ID,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $PlatformInstance = $env:CDF_PLATFORM_INSTANCE,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ApplicationId = $env:CDF_APPLICATION_ID,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ApplicationInstance = $env:CDF_APPLICATION_INSTANCE,
        [Parameter(Mandatory = $false)]
        [string] $SourceDir = $env:CDF_INFRA_SOURCE_PATH ?? './src'
    )
    $sourcePath = "$SourceDir/$PlatformId/$PlatformInstance"
    $platformEnvs = Get-Content -Raw "$sourcePath/platform/environments.json" | ConvertFrom-Json -AsHashtable
    $platformKey = "$PlatformId$PlatformInstance"
    $applicationKey = "$ApplicationId$ApplicationInstance"
    $matrix = @()

    if (Test-Path "$sourcePath/application/environments.$applicationKey.json" ) {
        $applicationEnvs = Get-Content -Raw "$sourcePath/application/environments.$applicationKey.json" | ConvertFrom-Json -AsHashtable
    }

    if ($ApplicationId -and $ApplicationInstance -and $applicationEnvs ) {
        Write-Verbose "Processing platform [$platformKey] application [$applicationKey]"
        foreach ($envKey in  $applicationEnvs.Keys) {
            $applicationEnv = $applicationEnvs[$envKey]
            $platformEnv = $platformEnvs[$applicationEnv.platformDefinitionId]
            Write-Verbose "Processing application definition [$envKey] for platform definition [$($platformEnv.definitionId)]"
            if ($platformEnv.isEnabled -and $applicationEnv.isEnabled) {

                $env = [ordered] @{
                    tenantId                      = $platformEnv.tenantId
                    subscriptionId                = $platformEnv.subscriptionId
                    cdfInfraDeployerName          = $platformEnv.cdfInfraDeployerName
                    cdfInfraDeployerAppId         = $platformEnv.cdfInfraDeployerAppId
                    cdfSolutionDeployerName       = $platformEnv.cdfSolutionDeployerName
                    cdfSolutionDeployerAppId      = $platformEnv.cdfSolutionDeployerAppId

                    platformEnvKey                = "$platformKey$($platformEnv.nameId)"
                    platformEnvDefinitionId       = $platformEnv.definitionId
                    platformEnvNameId             = $platformEnv.nameId
                    platformEnvName               = $platformEnv.name
                    platformEnvShortName          = $platformEnv.shortName
                    platformEnvDescription        = $platformEnv.description
                    platformEnvQuality            = $platformEnv.quality
                    platformEnvPurpose            = $platformEnv.purpose
                    platformEnvReleaseApproval    = $platformEnv.releaseApproval

                    applicationEnvKey             = "$applicationKey$($applicationEnv.nameId)"
                    applicationEnvDefinitionId    = $applicationEnv.definitionId
                    applicationEnvNameId          = $applicationEnv.nameId
                    applicationEnvName            = $applicationEnv.name
                    applicationEnvShortName       = $applicationEnv.shortName
                    applicationEnvDescription     = $applicationEnv.description
                    applicationEnvQuality         = $applicationEnv.quality
                    applicationEnvPurpose         = $applicationEnv.purpose
                    applicationEnvReleaseApproval = $applicationEnv.releaseApproval
                }
                $matrix += $env
            }

        }
    }
    else {
        foreach ($envKey in $platformEnvs.Keys) {
            $platformEnv = $platformEnvs[$envKey]
            Write-Verbose "Processing platform definition [$($platformEnv.definitionId)]"
            if ($platformEnv.isEnabled) {
                $env = [ordered] @{
                    tenantId                   = $platformEnv.tenantId
                    subscriptionId             = $platformEnv.subscriptionId
                    cdfInfraDeployerName       = $platformEnv.cdfInfraDeployerName
                    cdfInfraDeployerAppId      = $platformEnv.cdfInfraDeployerAppId
                    cdfSolutionDeployerName    = $platformEnv.cdfSolutionDeployerName
                    cdfSolutionDeployerAppId   = $platformEnv.cdfSolutionDeployerAppId

                    platformEnvKey             = "$platformKey$($platformEnv.nameId)"
                    platformEnvDefinitionId    = $platformEnv.definitionId
                    platformEnvNameId          = $platformEnv.nameId
                    platformEnvName            = $platformEnv.Name
                    platformEnvShortName       = $platformEnv.shortName
                    platformEnvDescription     = $platformEnv.description
                    platformEnvQuality         = $platformEnv.quality
                    platformEnvPurpose         = $platformEnv.purpose
                    platformEnvReleaseApproval = $platformEnv.releaseApproval

                }
                $matrix += $env
            }
            else {
                Write-Verbose "`tSkipping env is [$($platformEnv.isEnabled)]"
            }

        }

    }
    return $matrix
}