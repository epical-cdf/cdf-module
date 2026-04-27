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
    [string] $TemplateName,
    [Parameter(Mandatory = $true)]
    [string] $TemplateVersion,
    [Parameter(Mandatory = $false)]
    [string] $Region = $env:CDF_REGION,
    [Parameter(Mandatory = $false)]
    [string] $PlatformId = $env:CDF_PLATFORM_ID,
    [Parameter(Mandatory = $false)]
    [string] $InstanceId = $env:CDF_PLATFORM_INSTANCE,
    [Parameter(Mandatory = $false)]
    [string] $TemplateDir = $env:CDF_INFRA_TEMPLATES_PATH ?? '.',
    [Parameter(Mandatory = $false)]
    [string] $SourceDir = $env:CDF_INFRA_SOURCE_PATH ?? './src',
    [Parameter(Mandatory = $false)]
    [switch] $Force
  )

  Begin {
  }

  Process {

    # Fetch definitions
    $templatePath = "$TemplateDir/platform/$TemplateName/$TemplateVersion"
    $sourcePath = "$SourceDir/$PlatformId/$InstanceId"

    if ($true -eq (Test-Path $sourcePath) -and -not $Force) {
      throw "Please make sure this is a new instance. A platform instance folder already exists at [$sourcePath]"
    }

    Write-Information "Preparing platform instance at [$sourcePath]"

    # Setup platform instance folder and definitions
    New-Item -ItemType Directory -Path $sourcePath -Force | Out-Null
    New-Item -ItemType Directory -Path "$sourcePath/platform" -Force | Out-Null
    Copy-Item -Path "$templatePath/samples/environments.json" "$sourcePath/platform/environments.json" -ErrorAction Stop
    Copy-Item -Path "$templatePath/samples/regionnames.json" "$sourcePath/platform/regionnames.json" -ErrorAction Stop
    Copy-Item -Path "$templatePath/samples/regioncodes.json" "$sourcePath/platform/regioncodes.json" -ErrorAction Stop

    # Load the newly setup definition files
    $platformEnvs = Get-Content -Raw "$sourcePath/platform/environments.json"  -ErrorAction Stop | ConvertFrom-Json -AsHashtable
    $regionNames = Get-Content -Raw "$sourcePath/platform/regionnames.json"  -ErrorAction Stop | ConvertFrom-Json -AsHashtable
    $regionCodes = Get-Content -Raw "$sourcePath/platform/regioncodes.json"  -ErrorAction Stop | ConvertFrom-Json -AsHashtable

    # Setup region mappings
    $regionCode = $regionCodes[$Region.ToLower()]
    $regionName = $regionNames[$regionCode]

    foreach ($envDefinionId in $platformEnvs.Keys) {
      $platformEnv = $platformEnvs[$envDefinionId]

      if ($platformEnv.isEnabled) {
        Write-Information "Preparing configuration for environment $($platformEnv.nameId)"
        $platformEnvKey = "$PlatformId$InstanceId$($platformEnv.nameId)"

        $CdfPlatform = Get-Content "$templatePath/samples/template.platform.json" -ErrorAction Stop | ConvertFrom-Json -AsHashtable
        $CdfPlatform.IsDeployed = $false
        $CdfPlatform.Config.templateName = $TemplateName
        $CdfPlatform.Config.templateVersion = $TemplateVersion
        $CdfPlatform.Config.platformId = $PlatformId
        $CdfPlatform.Config.instanceId = $InstanceId
        $CdfPlatform.Env = $platformEnv
        $CdfPlatform.Env['region'] = $Region
        $CdfPlatform.Env['regionName'] = $regionName
        $CdfPlatform.Env['regionCode'] = $regionCode

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
