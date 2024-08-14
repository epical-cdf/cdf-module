
Function Get-GitHubConfigPlatform {
    <#
    .SYNOPSIS
    Get platform deployment config artifact from GitHub.

    .DESCRIPTION
    Deployment workflow saves deployment configuration for each environment as an artifact.
    This cmdlet tries to download the configuration for all enabled envrionments and update application input file.
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
    Get-CdfGitHubConfigPlatform `
        -CdfConfig $config

    .EXAMPLE
    Get-CdfGitHubConfigPlatform `
        -CdfConfig $config `
        -OutputPath "./tmp/some-other-folder"

    .LINK
    Deploy-CdfTemplatePlatform
    Deploy-CdfTemplateApplication
    Get-CdfGitHubConfigApplication
    Get-CdfGitHubConfigDomain
    #>

    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [hashtable] $CdfConfig,
        [Parameter(Mandatory = $false)]
        [string] $SourceDir = "./src",
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = "./tmp/artifacts"
    )


    $sourcePath = "$SourceDir/$($CdfConfig.Platform.Config.platformId)/$($CdfConfig.Platform.Config.platformInstanceId)"
    $platformKey = "$($CdfConfig.Platform.Config.platformId)$($CdfConfig.Platform.Config.platformInstanceId)"
    $platformEnvKey = "$platformKey$($CdfConfig.Platform.Env.nameId)"
    $regionCode = $CdfConfig.Platform.Config.regionCode

    $downloadPath = "$OutputPath/$platformEnvKey-$regionCode"
    if (Test-Path $downloadPath) {
        # Remove previous download
        Remove-Item -Force -Recurse -Path $downloadPath | Out-Null
    }
    New-Item -Type Directory -Path "$downloadPath" | Out-Null

    # Depends on the artifact naming in the workflow (REF-ARTIFACT-02)
    $artifactName = "platform-config-$platformEnvKey-$regionCode"
    $output = gh run download -n $artifactName -D $downloadPath 2>&1
    if ($output -like "*no artifact*") {
        Write-Host "Artifact [$artifactName] not found, moving on."
    }
    else {
        Write-Host "Artifact [$artifactName] downloaded to $downloadPath"

        $configFile = "$downloadPath/platform/platform.$platformEnvKey-$regionCode.json"
        if (!(Test-Path $configFile)) {
            Write-Host "Could not find application config file path [$configFile] for $platformEnvKey-$regionCode"
        }
        else {
            Write-Host "Copy [$configFile] to [$sourcePath/platform/]"
            Copy-Item `
                -Path $configFile `
                -Destination $sourcePath/platform
        }
    }

}
