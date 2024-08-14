Function Build-ApimServiceTemplates {
  <#
    .SYNOPSIS

    Build bicep ARM templates for an API

    .DESCRIPTION

    This cmdlet builds bicep template and parameter file for an api and expects an "config.json" file to be found in the <SpecFolder>.

    .PARAMETER CdfConfig
    Instance config

    .PARAMETER DomainName
    Domain name of the service as provided in workflow inputs

    .PARAMETER ServiceName
    Name of the service as provided in workflow inputs

    .PARAMETER SharedPath
    File system root path to the apim shared repository contents

    .PARAMETER ServicePath
    File system root path to the service's implementation folder, defaults to CWD.

    .PARAMETER BuildPath
    File system path where ARM template will be written

    .INPUTS
    None. You cannot pipe objects.

    .OUTPUTS
    None. Writes compiled policies.

    .EXAMPLE
    PS> Build-ApimServiceTemplates `
        -ConfigFile "api-shaman/api.yaml"

    PS> Build-ApimServiceTemplates `
        -ConfigFile "api-shaman/api.yaml"
        -Output "./api-arm-templates"

    .LINK
    Build-ApimTemplates
    Build-ApimGlobalPolicies
    Build-ApimOperationPolicies

    #>

  [CmdletBinding()]
  Param(
    [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
    [hashtable] $CdfConfig,
    [Parameter(Mandatory = $false)]
    [string] $DomainName = $env:CDF_DOMAIN_NAME,
    [Parameter(Mandatory = $false)]
    [string] $ServiceName = $env:CDF_SERVICE_NAME,
    [Parameter(Mandatory = $false)]
    [string] $ServiceType = $env:CDF_SERVICE_TYPE,
    [Parameter(Mandatory = $false)]
    [string] $ServiceGroup = $env:CDF_SERVICE_GROUP,
    [Parameter(Mandatory = $false)]
    [string] $ServiceTemplate = $env:CDF_SERVICE_TEMPLATE,
    [Parameter(Mandatory = $false)]
    [string] $SharedPath = $env:CDF_SHARED_SOURCE_PATH,
    [Parameter(Mandatory = $false)]
    [string] $ServicePath = '.',
    [Parameter(Mandatory = $false)]
    [string] $BuildPath = "../tmp/build"
  )

  # Use "cdf-config.json" if available, but if parameter is bound it overrides / takes precendens
  if (Test-Path "$ServicePath/cdf-config.json") {
    Write-Host "Loading service settings from cdf-config.json"
    $svcConfig = Get-Content -Raw "$ServicePath/cdf-config.json" | ConvertFrom-Json -AsHashtable
    $ServiceName = $MyInvocation.BoundParameters.Keys.Contains("ServiceName") ? $ServiceName : $svcConfig.ServiceDefaults.ServiceName
    $ServiceGroup = $MyInvocation.BoundParameters.Keys.Contains("ServiceGroup") ? $ServiceGroup : $svcConfig.ServiceDefaults.ServiceGroup
    $ServiceType = $MyInvocation.BoundParameters.Keys.Contains("ServiceType") ? $ServiceType : $svcConfig.ServiceDefaults.ServiceType
    $ServiceTemplate = $MyInvocation.BoundParameters.Keys.Contains("ServiceTemplate") ? $ServiceTemplate : $svcConfig.ServiceDefaults.ServiceTemplate
  }
  else {
    Write-Error "No service configuration file [$ServicePath/cdf-config.json] found."
    return 1
  }

  # Clear the build path
  if (!(Test-Path -Path $BuildPath)) {
    New-Item -Force  -Type Directory $BuildPath -ErrorAction SilentlyContinue | Out-Null
  }
  # else {
  #   Remove-Item -Recurse -Force $BuildPath/$ServiceName -ErrorAction SilentlyContinue | Out-Null
  # }
  # New-Item -Force -Type Directory $BuildPath/$ServiceName -ErrorAction SilentlyContinue | Out-Null
  # $outputPath = (Resolve-Path -Path $BuildPath/$ServiceName).Path
  $outputPath = (Resolve-Path -Path $BuildPath).Path

  # Setup api "build" folder. Excluding the policies as these will be generated from <SpecFolder> below
  New-Item -Force -Type Directory "$outputPath/policies" | Out-Null
  Copy-Item -Force -Path "$ServicePath/*" -Destination "$outputPath" -Recurse -Exclude 'policies' | Out-Null

  # Build policies
  Build-ApimGlobalPolicies `
    -DomainName $DomainName `
    -ServiceName $ServiceName `
    -ServiceType $ServiceType `
    -ServiceTemplate $ServiceTemplate `
    -ServicePath $ServicePath `
    -SharedPath $SharedPath `
    -OutputPath $outputPath

  Build-ApimOperationPolicies `
    -DomainName $DomainName `
    -ServiceName $ServiceName `
    -ServiceType $ServiceType `
    -ServiceTemplate $ServiceTemplate `
    -ServicePath $ServicePath `
    -SharedPath $SharedPath `
    -OutputPath $outputPath

  #############################################################################
  # This section uses new bicep templates to generate API deployment package
  #############################################################################

  $CdfConfigFile = Resolve-Path "$outputPath/cdf-config.json"
  Write-Host '---------------------------------------'
  Write-Host "Build API       : $ServiceName"
  Write-Host "API type        : $ServiceType"
  Write-Host "API template    : $ServiceTemplate"
  Write-Host "API displayName : $($svcConfig.ServiceSettings.displayName)"

  Write-Host "API Config Path : $CdfConfigFile"
  if (-not ($svcConfig.ServiceSettings.displayName.StartsWith("$DomainName", 'CurrentCultureIgnoreCase'))) {
    Write-Error 'API display names must start with domain name. (<domain name><api display name>)'
    return 1
  }

  # These are the standard API template parameters
  $apiPath = $DomainName + '/' + $ServiceName.Replace('api-', '')
  $apiBaseParams = @"
            {
                "`$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
                "contentVersion": "1.0.0.0",
                "parameters": {
                  "appInsightsName": {
                    "value": "$($CdfConfig.Application.ResourceNames.appInsightsName)"
                  },
                  "appInsightsRG": {
                    "value": "$($CdfConfig.Application.ResourceNames.appResourceGroupName)"
                  },
                  "keyVaultName": {
                    "value": "$($CdfConfig.Application.ResourceNames.keyVaultName)"
                  },
                  "apimServiceName": {
                    "value": "$($CdfConfig.Application.ResourceNames.apimName)"
                  },
                  "apimClientId": {
                    "value": "$($CdfConfig.Application.Config.appIdentityClientId)"
                  },
                  "domainName": {
                    "value": "$DomainName"
                  },
                  "serviceGroup": {
                    "value": "$ServiceGroup"
                  },
                  "apiName": {
                    "value": "$DomainName-$ServiceName"
                  },
                  "apiDisplayName": {
                    "value": "$($svcConfig.ServiceSettings.displayName)"
                  },
                  "apiPath": {
                    "value": "$apiPath"
                  }
                }
              }
"@
  $apiParams = ConvertFrom-Json $apiBaseParams -AsHashtable
  $apiParams.parameters.Add('apiProtocols', @{ 'value' = @( $($svcConfig.ServiceSettings.protocols ?? @()) ) })
  $apiParams.parameters.Add('apiProductNames', @{ 'value' = @( $($svcConfig.ServiceSettings.products ?? @()) ) })
  $apiParams.parameters.Add('apiNamedValues', @{ 'value' = @( $($svcConfig.ServiceSettings.namedValues ?? @()) ) })

  $parTags = @{}
  $parTags.BuildCommit = $env:GITHUB_SHA ?? $env:BUILD_SOURCEVERSION ?? $(git rev-parse --short HEAD)
  $parTags.BuildRun = $env:GITHUB_RUN_ID ?? $env:BUILD_BUILDNUMBER ?? "local"
  $parTags.BuildBranch = $env:GITHUB_REF_NAME ?? $env:BUILD_SOURCEBRANCH ?? $(git branch --show-current)
  $parTags.BuildRepo = $env:GITHUB_REPOSITORY ?? $env:BUILD_REPOSITORY_NAME ?? $(Split-Path -Leaf (git remote get-url origin))
  $apiParams.parameters.Add('parTags', @{ 'value' = $parTags })

  $PolicyXML = Get-Content -Path "$outputPath/$($svcConfig.ServiceSettings.policy)"
  $apiParams.parameters.Add('apiPolicy', @{ 'value' = $PolicyXML | Join-String })

  # From here are api type specific parameters for the bicep template in use
  switch ($ServiceTemplate) {
    'api-internal-passthrough-wsdl' {
      $OpenAPISpecDoc = Get-Content -Path "$outputPath/$($svcConfig.ServiceSettings.openApiSpec)"
      $apiParams.parameters.Add('apiSpecDoc', @{ 'value' = $OpenAPISpecDoc | Join-String -Separator "`r`n" })

      foreach ($operations in $svcConfig.ServiceSettings.operations) {
        $PolicyXML = Get-Content -Path "$outputPath/$($operations.policy)"
        $operations.policy = $PolicyXML | Join-String
      }
      if ($svcConfig.ServiceSettings.operations.GetType().BaseType -eq 'System.Array') {
        # Add array
        Write-Verbose "Adding ApiOperations value as array"
        $apiParams.parameters.Add('apiOperations', @{ 'value' = $($svcConfig.ServiceSettings.operations) })
      }
      else {
        # Add object to array
        Write-Verbose "Adding ApiOperations value as object to array"
        $apiParams.parameters.Add('apiOperations', @{ 'value' = @( $svcConfig.ServiceSettings.operations ) })
      }
    }
    'api-internal-passthrough-v1' {
      $OpenAPISpecDoc = Get-Content -Path "$outputPath/$($svcConfig.ServiceSettings.openApiSpec)"
      $apiParams.parameters.Add('apiSpecDoc', @{ 'value' = $OpenAPISpecDoc | Join-String -Separator "`r`n" })

      foreach ($operations in $svcConfig.ServiceSettings.operations) {
        $PolicyXML = Get-Content -Path "$outputPath/$($operations.policy)"
        $operations.policy = $PolicyXML | Join-String
      }
      if ($svcConfig.ServiceSettings.operations.GetType().BaseType -eq 'System.Array') {
        # Add array
        Write-Verbose "Adding ApiOperations value as array"
        $apiParams.parameters.Add('apiOperations', @{ 'value' = $($svcConfig.ServiceSettings.operations) })
      }
      else {
        # Add object to array
        Write-Verbose "Adding ApiOperations value as object to array"
        $apiParams.parameters.Add('apiOperations', @{ 'value' = @( $svcConfig.ServiceSettings.operations ) })
      }
    }
    'api-internal-openapi-yaml' {
      Write-Host "OpenAPI YAML spec   : $($svcConfig.ServiceSettings.openApiSpec)"
      $OpenAPISpecDoc = Get-Content -Path "$outputPath/$($svcConfig.ServiceSettings.openApiSpec)"


      $apiParams.parameters.Add('apiSpecDoc', @{ 'value' = $OpenAPISpecDoc | Join-String -Separator "`r`n" })

      foreach ($operations in $svcConfig.ServiceSettings.operations) {
        $PolicyXML = Get-Content -Path "$outputPath/$($operations.policy)"
        $operations.policy = $PolicyXML | Join-String
      }
      if ($svcConfig.ServiceSettings.operations.GetType().BaseType -eq 'System.Array') {
        # Add array
        Write-Verbose "Adding ApiOperations value as array"
        $apiParams.parameters.Add('apiOperations', @{ 'value' = $($svcConfig.ServiceSettings.operations) })
      }
      else {
        # Add object to array
        Write-Verbose "Adding ApiOperations value as object to array"
        $apiParams.parameters.Add('apiOperations', @{ 'value' = @( $svcConfig.ServiceSettings.operations ) })
      }

    }
    'api-internal-openapi-json' {
      Write-Host "OpenAPI JSON spec   : $($svcConfig.ServiceSettings.openApiSpec)"
      $OpenAPISpecDoc = Get-Content -Path  "$outputPath/$($svcConfig.ServiceSettings.openApiSpec)"

      $apiParams.parameters.Add('apiSpecDoc', @{ 'value' = $OpenAPISpecDoc | Join-String -Separator "`r`n" })

      foreach ($operations in $svcConfig.ServiceSettings.operations) {
        $PolicyXML = Get-Content -Path "$outputPath/$($operations.policy)"
        $operations.policy = $PolicyXML | Join-String
      }
      if ($svcConfig.ServiceSettings.operations.GetType().BaseType -eq 'System.Array') {
        # Add array
        Write-Verbose "Adding ApiOperations value as array"
        $apiParams.parameters.Add('apiOperations', @{ 'value' = $($svcConfig.ServiceSettings.operations) })
      }
      else {
        # Add object to array
        Write-Verbose "Adding ApiOperations value as object to array"
        $apiParams.parameters.Add('apiOperations', @{ 'value' = @( $svcConfig.ServiceSettings.operations ) })
      }
    }
    Default {
      Write-Error "Unknown API service template [$($svcConfig.ServiceSettings.ServiceDefaults.ServiceTemplate)]."
      throw "Unknown API service template [$($svcConfig.ServiceSettings.ServiceDefaults.ServiceTemplate)]."
    }
  }

  # Create template parameters json file
  $apiParams | ConvertTo-Json -Depth 50 | Set-Content -Path "$outputPath/$ServiceName.params.json"

  # Copy bicep template with type name
  Copy-Item -Force -Path "$SharedPath/resources/$($svcConfig.ServiceDefaults.ServiceTemplate).bicep" -Destination "$outputPath/$ServiceName.bicep" | Out-Null
}
