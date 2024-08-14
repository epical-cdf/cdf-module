Function New-ConfigDomain {
  <#
    .SYNOPSIS
    Create a new configuration for a domain within an application

    .DESCRIPTION
    Setup the configuration for a domain within an application instance. Output files stored at SourceDir using template.

    .PARAMETER CdfConfig
    Instance configuration

    .PARAMETER Region
    The target Azure Region/region for the deployment

    .PARAMETER TemplateName
    Domain template name to be used for deployment

    .PARAMETER TemplatVersion
    Domain template version to be used for deployment

    .PARAMETER DomainName
    Name of the domain

    .PARAMETER TemplateDir
    Path to the platform template root dir. Defaults to ".".

    .PARAMETER SourceDir
    Path to the platform instance source directory. Defaults to "./src".

    .INPUTS
    None.

    .OUTPUTS
    CdfConfig

    .EXAMPLE
    New-CdfConfigDomain `
      -CdfConfig $config `
      -Region "swedencentral" `
      -TemplateName "intg" `
      -TemplateVersion "v1net" `
      -DomainName "ops"

    .EXAMPLE
    New-CdfConfigDomain `
      -CdfConfig $config `
      -Region "swedencentral" `
      -TemplateName "intg" `
      -TemplateVersion "v1pub" `
      -DomainName "hr" `
      -TemplateDir ../cdf-infra/templates `
      -SourceDir ../cdf-infra/instances

    .LINK
    Get-CdfConfigApplication
    .LINK
    Deploy-CdfTemplateDomain

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
    [string] $DomainName,
    [Parameter(Mandatory = $false)]
    [string] $TemplateDir = $env:CDF_INFRA_TEMPLATES_PATH ?? '.',
    [Parameter(Mandatory = $false)]
    [string] $SourceDir = $env:CDF_INFRA_SOURCE_PATH ?? './src'
  )

  Begin {
  }

  Process {
    if (($null -eq $CdfConfig.Platform) -or ($null -eq $CdfConfig.Application) ) {
      throw "Missing platform and/or application configuration. Make sure you have provided CDF platform and application configuration for the domain"
    }

    # Setup paths
    $templatePath = "$TemplateDir/domain/$TemplateName/$TemplateVersion"
    $sourcePath = "$SourceDir/$($CdfConfig.Platform.Config.platformId)/$($CdfConfig.Platform.Config.instanceId)"

    if (!(Test-Path $templatePath)) {
      throw "Bad template specification. Domain template path not found [$templatePath]"
    }

    $platformKey = $CdfConfig.Platform.Config.platformId + $CdfConfig.Platform.Config.instanceId
    $applicationKey = $CdfConfig.Application.Config.templateName + $CdfConfig.Application.Config.instanceId

    Write-Information "Preparing application configuration for platform instance at [$sourcePath]"

    # Setup application instance folder and definitions
    if (!(Test-Path -Path "$sourcePath/domain")) {
      New-Item -ItemType Directory -Path "$sourcePath/domain" | Out-Null
    }

    # # Domain environments currently not implemented - using application environments
    # if (Test-Path -Path "$sourcePath/application/environments.$applicationKey.json") {
    #   Write-Warning "Environment for [$applicationKey] already exists for platform [$platformKey], skipping setup"

    # }
    # else {
    #   Copy-Item -Path "$templatePath/templates/environments.json" "$sourcePath/application/environments.$applicationKey.json"
    # }

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
        if (Test-Path -Path "$sourcePath/domain/application.$platformEnvKey-$applicationEnvKey-$DomainName-$regionCode.json") {
          Write-Warning "Configuration for domain $DomainName already exists for platform-application [$platformEnvKey-$applicationEnv], skipping setup"
        }
        else {
          Write-Output "Preparing domain configuration for environment $envDefinionId"
          $CdfDomain = Get-Content "$templatePath/templates/template.domain.json" | ConvertFrom-Json -AsHashtable
          $CdfDomain.IsDeployed = $false
          $CdfDomain.Config.templateName = $TemplateName
          $CdfDomain.Config.templateVersion = $TemplateVersion
          $CdfDomain.Config.domainName = $DomainName

          # Save new config
          $CdfDomain | ConvertTo-Json -depth 10 | Out-File "$sourcePath/domain/domain.$platformEnvKey-$applicationEnvKey-$DomainName-$regionCode.json"
          # $CdfDomain | ConvertTo-Json -Depth 10 | Write-Verbose
          Write-Output "Domain configuration for instance [$platformEnvKey-$applicationEnvKey] complete."
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
