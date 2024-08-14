Function Update-ConfigPlatform {
  <#
    .SYNOPSIS
    Create a new configuration for a platform instance

    .DESCRIPTION
    Setup the configuration for a new platform instance in output files stored at SourceDir using template.

    .PARAMETER CdfConfig
    Instance configuration

    .PARAMETER TemplateName
    Platform template name to be used for deployment

    .PARAMETER TemplatVersion
    Platform template version to be used for deployment

    .PARAMETER Region
    The target Azure Region/region for the deployment

    .PARAMETER PlatformId
    Name of the platform instance

    .PARAMETER InstanceId
    Specific id of the platform instance

    .PARAMETER TemplateDir
    Path to the platform template root dir. Defaults to ".".

    .PARAMETER SourceDir
    Path to the platform instance source directory. Defaults to "./src".

    .INPUTS
    None.

    .OUTPUTS
    CdfConfig

    .EXAMPLE
    Update-ConfigPlatform `
      -Region "swedencentral" `
      -TemplateName "intg" `
      -TemplateVersion "v1net" `
      -PlatformId "capim" `
      -InstanceId "01"

    .EXAMPLE
    Update-ConfigPlatform `
        -Region "northeurope" `
        -TemplateName "apim" `
        -TemplateVersion "v2" `
        -PlatformId "capim" `
        -InstanceId "01" `
        -TemplateDir ../cdf-infra/templates `
        -SourceDir ../cdf-infra/instances

    .LINK
    Get-CdfConfigPlatform
    .LINK
    Deploy-CdfTemplatePlatform

    #>

  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $true)]
    [string] $Region,
    [Parameter(Mandatory = $true)]
    [string] $TemplateName,
    [Parameter(Mandatory = $true)]
    [string] $TemplateVersion,
    [Parameter(Mandatory = $true)]
    [string] $PlatformId,
    [Parameter(Mandatory = $true)]
    [string] $InstanceId,
    [Parameter(Mandatory = $false)]
    [string] $TemplateDir = $env:CDF_INFRA_TEMPLATES_PATH ?? '.',
    [Parameter(Mandatory = $false)]
    [string] $SourceDir = $env:CDF_INFRA_SOURCE_PATH ?? './src'
  )

  Begin {
  }

  Process {

    # Fetch definitions
    $templatePath = "$TemplateDir/platform/$TemplateName/$TemplateVersion"
    $sourcePath = "$SourceDir/$PlatformId/$InstanceId"
    $platformEnvs = Get-Content -Raw "$sourcePath/platform/environments.json" | ConvertFrom-Json -AsHashtable
    $regionCodes = Get-Content -Raw "$sourcePath/platform/regioncodes.json" | ConvertFrom-Json -AsHashtable
    $regionNames = Get-Content -Raw "$sourcePath/platform/regionnames.json" | ConvertFrom-Json -AsHashtable
    $regionCode = $regionCodes[$region]
    $regionName = $regionNames[$regionCode]

    foreach ($envDefinionId in $platformEnvs.Keys) {
      $platformEnv = $platformEnvs[$envDefinionId]

      if ($platformEnv.isEnabled) {
        Write-Information "Preparing configuration for environment $($platformEnv.nameId)"
        $platformEnvKey = "$PlatformId$InstanceId$($platformEnv.nameId)"

        # Re-use existing configuration file if it exists. Keep any addtional configurations if possible.
        if (Test-Path "$sourcePath/platform/platform.$platformEnvKey-$regionCode.json") {
          $CdfPlatform = Get-Content "$sourcePath/platform/platform.$platformEnvKey-$regionCode.json" | ConvertFrom-Json -AsHashtable
        }
        else {
          $CdfPlatform = Get-Content "$templatePath/templates/template.platform.json" | ConvertFrom-Json -AsHashtable
        }
        $CdfPlatform.IsDeployed = $false
        $CdfPlatform.Env = $platformEnv
        $CdfPlatform.Config.templateName = $TemplateName
        $CdfPlatform.Config.templateVersion = $TemplateVersion
        $CdfPlatform.Config.platformId = $PlatformId
        $CdfPlatform.Config.platformInstanceId = $InstanceId
        $CdfPlatform.Config.platformEnvDefinitionId = $envDefinionId
        $CdfPlatform.Config.region = $Region
        $CdfPlatform.Config.regionName = $regionName
        $CdfPlatform.Config.regionCode = $regionCode

        # Save new config
        $CdfPlatform | ConvertTo-Json -Depth 10 | Out-File "$sourcePath/platform/platform.$platformEnvKey-$regionCode.json"
        $CdfPlatform | ConvertTo-Json -Depth 10 | Write-Verbose
        Write-Information "Instance configuration for intance [$platformEnvKey] complete."
      }
    }
  }

  End {
  }
}
