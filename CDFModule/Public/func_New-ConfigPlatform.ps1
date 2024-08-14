Function New-ConfigPlatform {
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
    New-CdfConfigPlatform `
      -Region "swedencentral" `
      -TemplateName "intg" `
      -TemplateVersion "v1net" `
      -PlatformId "capim" `
      -InstanceId "01"

    .EXAMPLE
    New-CdfConfigPlatform `
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

    if (Test-Path $sourcePath) {
      throw "Please make sure this is a new instance. A platform instance folder already exists at [$sourcePath]"
    }

    Write-Information "Preparing platform instance at [$sourcePath]"

    # Setup platform instance folder and definitions
    New-Item -ItemType Directory -Path $sourcePath | Out-Null
    New-Item -ItemType Directory -Path "$sourcePath/platform" | Out-Null
    Copy-Item -Path "$templatePath/templates/environments.json" "$sourcePath/platform/environments.json"
    Copy-Item -Path "$templatePath/templates/regionnames.json" "$sourcePath/platform/regionnames.json"
    Copy-Item -Path "$templatePath/templates/regioncodes.json" "$sourcePath/platform/regioncodes.json"

    # Load the newly setup definition files
    $platformEnvs = Get-Content -Raw "$sourcePath/platform/environments.json" | ConvertFrom-Json -AsHashtable
    $regionNames = Get-Content -Raw "$sourcePath/platform/regionnames.json" | ConvertFrom-Json -AsHashtable
    $regionCodes = Get-Content -Raw "$sourcePath/platform/regioncodes.json" | ConvertFrom-Json -AsHashtable

    # Setup region mappings
    $regionCode = $regionCodes[$Region.ToLower()]
    $regionName = $regionNames[$regionCode]

    foreach ($envDefinionId in $platformEnvs.Keys) {
      $platformEnv = $platformEnvs[$envDefinionId]

      if ($platformEnv.isEnabled) {
        Write-Information "Preparing configuration for environment $($platformEnv.nameId)"
        $platformEnvKey = "$PlatformId$InstanceId$($platformEnv.nameId)"

        $CdfPlatform = Get-Content "$templatePath/templates/template.platform.json" | ConvertFrom-Json -AsHashtable
        $CdfPlatform.IsDeployed = $false
        $CdfPlatform.Config.templateName = $TemplateName
        $CdfPlatform.Config.templateVersion = $TemplateVersion
        $CdfPlatform.Config.platformId = $PlatformId
        $CdfPlatform.Config.instanceId = $InstanceId
        # $CdfPlatform.Config.platformEnvDefinitionId = $envDefinionId
        # $CdfPlatform.Env = $platformEnv
        $CdfPlatform.Env.region = $Region
        $CdfPlatform.Env.regionName = $regionName
        $CdfPlatform.Env.regionCode = $regionCode

        # Save new config
        $CdfPlatform | ConvertTo-Json -depth 10 | Out-File "$sourcePath/platform/platform.$platformEnvKey-$regionCode.json"
        $CdfPlatform | ConvertTo-Json -Depth 10 | Write-Verbose
        Write-Information "Instance configuration for intance [$platformEnvKey] complete."
      }
    }
  }

  End {
  }
}
