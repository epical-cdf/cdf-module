Function Get-GitHubConfigService {
    <#
    .SYNOPSIS
    Get service deployment config artifact from GitHub.

    .DESCRIPTION
    Deployment workflow saves deployment configuration for each environment as an artifact.
    This cmdlet tries to download the configuration for all enabled envrionments and update service input file.
    The updated input file configration can then be compared with application configuration files and optionally have them updated.

    .PARAMETER CdfConfig
    Instance config

    .PARAMETER SourceDir
    Path to the platform instance source directory. Defaults to "./src".

    .PARAMETER OutputPath
    Optional output path for artifact download. Defaults to "./tmp/artifacts"

    .INPUTS
    CdfConfig

    .OUTPUTS
    None.

    .EXAMPLE
    Get-CdfGitHubConfigDomain `
        -CdfConfig $config

    .EXAMPLE
    Get-CdfGitHubConfigDomain `
        -CdfConfig $config `
        -OutputPath "./tmp/some-other-folder"

    .LINK
    Deploy-CdfTemplatePlatform
    Deploy-CdfTemplateApplication
    Deploy-CdfTemplateDomain
    Get-CdfGitHubConfigPlatform
    Get-CdfGitHubConfigApplication

    #>

    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [hashtable] $CdfConfig,
        [Parameter(Mandatory = $true)]
        [string] $ServiceName,
        [Parameter(Mandatory = $false)]
        [string] $SourceDir = "./src",
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = "./tmp/artifacts"
    )

    $sourcePath = "$SourceDir/$($CdfConfig.Platform.Config.platformId)/$($CdfConfig.Platform.Config.platformInstanceId)"
    $platformKey = "$($CdfConfig.Platform.Config.platformId)$($CdfConfig.Platform.Config.platformInstanceId)"
    $applicationKey = "$($CdfConfig.Application.Config.applicationId ?? $CdfConfig.Application.Config.templateName)$($CdfConfig.Application.Config.applicationInstanceId)"
    $platformEnvKey = "$platformKey$($CdfConfig.Platform.Env.nameId)"
    $applicationEnvKey = "$applicationKey$($CdfConfig.Application.Env.nameId)"
    $regionCode = $CdfConfig.Application.Config.regionCode

    $downloadPath = "$OutputPath/$platformEnvKey-$applicationEnvKey-$regionCode"
    if (Test-Path $downloadPath) {
        # Remove previous download
        Remove-Item -Force -Recurse -Path $downloadPath | Out-Null
    }
    New-Item -Type Directory -Path "$downloadPath" | Out-Null

    # Depends on the artifact naming in the workflow (REF-ARTIFACT-05)
    $artifactName = "service-config-$platformEnvKey-$applicationEnvKey-$($CdfConfig.Domain.Config.domainName)-$ServiceName-$regionCode"
    $output = gh run download -R Epical-Integration/integration-domain-$($CdfConfig.Domain.Config.domainName) -n $artifactName -D $downloadPath 2>&1
    if ($output -like "*no artifact*") {
        Write-Host "Artifact [$artifactName] not found, moving on."
    }
    else {
        Write-Host "Artifact [$artifactName] downloaded to $downloadPath"

        $configFile = "$downloadPath/service/service.$platformEnvKey-$applicationEnvKey-$($CdfConfig.Domain.Config.domainName)-$ServiceName-$regionCode.json"
        if (!(Test-Path $configFile)) {
            Write-Host "Could not find service config file path [$configFile] for $platformEnvKey-$applicationEnvKey-$regionCode"
        }
        else {
            Write-Host "Copy [$configFile] to [$sourcePath/service/]"
            Copy-Item `
                -Path $configFile `
                -Destination $sourcePath/service
        }
    }

}
