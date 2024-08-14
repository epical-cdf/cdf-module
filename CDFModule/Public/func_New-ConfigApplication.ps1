Function New-ConfigApplication {
  <#
    .SYNOPSIS
    Create a new configuration for a platform instance

    .DESCRIPTION
    Setup the configuration for a new application instance within a platform. Output files stored at SourceDir using template.

    .PARAMETER CdfConfig
    Instance configuration

    .PARAMETER TemplateName
    Application template name to be used for deployment

    .PARAMETER TemplatVersion
    Application template version to be used for deployment

    .PARAMETER Region
    The target Azure Region/region for the deployment

    .PARAMETER InstanceId
    Specific id of the application instance

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
    [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
    [Object]$CdfConfig,
    [Parameter(Mandatory = $true)]
    [string] $Region,
    [Parameter(Mandatory = $true)]
    [string] $TemplateName,
    [Parameter(Mandatory = $true)]
    [string] $TemplateVersion,
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
    if ($null -eq $CdfConfig.Platform) {
      throw "Missing platform configuration. Make sure you have provided CDF platform configuration for the application"
    }

    # Setup paths
    $templatePath = "$TemplateDir/application/$TemplateName/$TemplateVersion"
    $sourcePath = "$SourceDir/$($CdfConfig.Platform.Config.platformId)/$($CdfConfig.Platform.Config.instanceId)"

    if (!(Test-Path $templatePath)) {
      throw "Bad template specification. Application template path not found [$templatePath]"
    }

    $platformKey = "$($CdfConfig.Platform.Config.platformId)$($CdfConfig.Platform.Config.instanceId)"
    $applicationKey = "$TemplateName$InstanceId"

    Write-Information "Preparing application configuration for platform instance at [$sourcePath]"

    # Setup application instance folder and definitions
    if (!(Test-Path -Path "$sourcePath/application")) {
      New-Item -ItemType Directory -Path "$sourcePath/application" | Out-Null
    }

    if (Test-Path -Path "$sourcePath/application/environments.$applicationKey.json") {
      Write-Warning "Environment for [$applicationKey] already exists for platform [$platformKey], skipping setup"

    }
    else {
      Copy-Item -Path "$templatePath/templates/environments.json" "$sourcePath/application/environments.$applicationKey.json"
    }

    # Load the definition files
    $applicationEnvs = Get-Content -Raw "$sourcePath/application/environments.$applicationKey.json" | ConvertFrom-Json -AsHashtable
    $regionNames = Get-Content -Raw "$sourcePath/platform/regionnames.json" | ConvertFrom-Json -AsHashtable
    $regionCodes = Get-Content -Raw "$sourcePath/platform/regioncodes.json" | ConvertFrom-Json -AsHashtable
    $platformEnvs = Get-Content -Raw "$sourcePath/platform/environments.json" | ConvertFrom-Json -AsHashtable

    # Setup region mappings
    $regionCode = $regionCodes[$Region.ToLower()]
    $regionName = $regionNames[$regionCode]

    foreach ($envDefinionId in $applicationEnvs.Keys) {
      Write-Verbose "Processing environment $envDefinionId"

      $applicationEnv = $applicationEnvs[$envDefinionId]
      $platformEnv = $platformEnvs[$applicationEnv.platformDefinitionId]

      $platformEnvKey = "$platformKey$($platformEnv.nameId)"
      $applicationEnvKey = "$applicationKey$($applicationEnv.nameId)"

      if ($applicationEnv.isEnabled -and $platformEnv.isEnabled) {
        if (Test-Path -Path "$sourcePath/application/application.$platformEnvKey-$applicationEnvKey-$regionCode.json") {
          Write-Warning "Configuration for [$applicationEnv] already exists for platform [$platformEnvKey], skipping setup"
        }
        else {
          Write-Output "Preparing configuration for environment $envDefinionId"
          $CdfApplication = Get-Content "$templatePath/templates/template.application.json" | ConvertFrom-Json -AsHashtable
          $CdfApplication.IsDeployed = $false
          $CdfApplication.Config.templateName = $TemplateName
          $CdfApplication.Config.templateVersion = $TemplateVersion
          $CdfApplication.Config.applicationId = $TemplateName
          $CdfApplication.Config.instanceId = $InstanceId
          # $CdfApplication.Env = $platformEnv
          # $CdfApplication.Env.region = $Region
          # $CdfApplication.Env.regionCode = $regionCode
          # $CdfApplication.Env.regionName = $regionName

          # Save new config
          $CdfApplication | ConvertTo-Json -depth 10 | Out-File "$sourcePath/application/application.$platformEnvKey-$applicationEnvKey-$regionCode.json"
          # $CdfApplication | ConvertTo-Json -Depth 10 | Write-Verbose
          Write-Output "Instance configuration for instance [$platformEnvKey-$applicationEnvKey] complete."
        }
      }
      else {
        Write-Output "Skipping environment $envDefinionId - not enabled"
      }
    }
  }

  End {
  }
}
