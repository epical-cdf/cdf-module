Function New-ServiceLogicAppStd {
    <#
      .SYNOPSIS
      Create a new Logic App service

      .DESCRIPTION
      Setup the configuration for a new platform instance in output files stored at SourceDir using template.

      .PARAMETER ServiceName
      Design-time name of the service

      .PARAMETER ServiceGroup
      Design-time group name for service

      .PARAMETER ServiceType
      Type of service aka service design-time template

      .PARAMETER ServiceTemplate
      CDF infrastructure template of the service implementation

      .PARAMETER ServicePath
      Type of service aka service design-time template

      .PARAMETER CdfInfraSourcePath
      Path to the platform instance source directory. Defaults to "../../cdf-infra/src".

      .PARAMETER CdfSharedPath
      Path to the shared repository root dir. Defaults to "../../shared-infra".

      .PARAMETER SharedTemplatePath
      Path to the platform template root dir. Defaults to "$CdfSharedPath/templates".

      .INPUTS
      None.

      .OUTPUTS
      None.

      .EXAMPLE


      .LINK
      Get-CdfConfigPlatform
      Get-CdfConfigApplication
      Get-CdfConfigDomain
      Get-CdfConfigService

      #>

    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
        [Object]$CdfConfig,
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
        [string] $PlatformEnvId = $env:CDF_PLATFORM_ENV_ID,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ApplicationId = $env:CDF_APPLICATION_ID,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ApplicationInstance = $env:CDF_APPLICATION_INSTANCE,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ApplicationEnvId = $env:CDF_APPLICATION_ENV_ID,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $DomainName = $env:CDF_DOMAIN_NAME,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ServiceName = $env:CDF_SERVICE_NAME,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ServiceType = $env:CDF_SERVICE_TYPE,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ServiceGroup = $env:CDF_SERVICE_GROUP,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ServiceTemplate = $env:CDF_SERVICE_TEMPLATE,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ServicePath = ".",
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $CdfInfraSourcePath = $env:CDF_INFRA_SOURCE_PATH ?? "../../cdf-infra/src",
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $CdfSharedPath = $env:CDF_SHARED_SOURCE_PATH ?? "../../shared-infra",
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $SharedTemplatePath = $env:CDF_SHARED_TEMPLATES_PATH ?? "$CdfSharedPath/templates"
    )


    if (!(Test-Path $CdfSharedPath)) {
        Write-Error "Could not find the CDF Infra shared path [$CdfSharedPath]"
        Throw "Could not find the CDF Infra shared path [$CdfSharedPath]"
    }

    if (!(Test-Path $CdfInfraSourcePath)) {
        Write-Error "Could not find the CDF Infra source path [$CdfInfraSourcePath]"
        Throw "Could not find the CDF Infra source path [$CdfInfraSourcePath]"
    }

    if (!(Test-Path $SharedTemplatePath/$ServiceType)) {
        Write-Error "Could not find service type [$ServiceType] at the CDF service templates path [$SharedTemplatePath]"
        Write-Error "Please make sure you have the correct path to shared templates and have given a correct service type reference."
        Throw "Could not find service type [$ServiceType] at the CDF service templates path [$SharedTemplatePath]"
    }

    if (!(Test-Path $SharedTemplatePath/la-base)) {
        Write-Error "Could not find base service type [la-base] at the CDF service templates path [$SharedTemplatePath]"
        Write-Error "Please make sure you have the correct path to shared templates and using CDF version 1.1."
        Throw "Could not find base service type [la-base] at the CDF service templates path [$SharedTemplatePath]"
    }

    if (!$CdfConfig) {
        Write-Host "Get Platform Config [$PlatformId$PlatformInstance]"
        $CdfConfig = Get-CdfConfigPlatform `
            -Region $Region `
            -PlatformId $PlatformId `
            -Instance $PlatformInstance `
            -EnvDefinitionId $PlatformEnvId  `
            -SourceDir $CdfInfraSourcePath `
            -Deployed -ErrorAction Continue

        Write-Host "Get Application Config [$ApplicationId$ApplicationInstance]"
        $CdfConfig = Get-CdfConfigApplication `
            -CdfConfig $CdfConfig `
            -Region $Region `
            -ApplicationId $ApplicationId  `
            -InstanceId $ApplicationInstance `
            -EnvDefinitionId $ApplicationEnvId  `
            -SourceDir $CdfInfraSourcePath `
            -Deployed -ErrorAction Continue

        Write-Host "Get Domain Config [$DomainName]"
        $CdfConfig = Get-CdfConfigDomain `
            -CdfConfig $CdfConfig `
            -DomainName $DomainName `
            -SourceDir $CdfInfraSourcePath `
            -Deployed -ErrorAction Continue

    }

    #############################################################
    # Validate and get cdf config for template service
    ############################################################
    $cdfConfigFile = Join-Path -Path $SharedTemplatePath -ChildPath $ServiceType -AdditionalChildPath 'cdf-config.json'
    $cdfSchemaPath = Join-Path -Path $MyInvocation.MyCommand.Module.ModuleBase -ChildPath 'Resources/Schemas/cdf-service-config.schema.json'
    if (!(Test-Json -SchemaFile $cdfSchemaPath -Path $cdfConfigFile)) {
        Write-Error "Service configuration file did not validate. Please check errors above and correct."
        Write-Error "File path:  $cdfConfigFile"
        return
    }
    $serviceConfig = Get-Content -Raw $cdfConfigFile | ConvertFrom-Json -AsHashtable


    #############################################################
    # Copy template for service type
    #############################################################

    # Copy Logic App Standard base
    Copy-Item -Recurse `
        -Path "$SharedTemplatePath/la-base/*" `
        -Destination $ServicePath `
        -ErrorAction SilentlyContinue
    # Copy service type
    Copy-Item -Recurse `
        -Path "$SharedTemplatePath/$ServiceType/*" `
        -Destination $ServicePath `
        -ErrorAction SilentlyContinue

    # Prepare (local) app settings
    if (Test-Path "$ServicePath/local.settings.json") {
        Write-Host "Loading settings from local.settings.json"
        $appSettings = Get-Content -Raw "$ServicePath/local.settings.json" | ConvertFrom-Json -AsHashtable
    }
    else {
        $appSettings = [ordered] @{
            "IsEncrypted" = $false
            "Values"      = [ordered] @{
                "AzureWebJobsStorage" = "UseDevelopmentStorage=true"
            }
        }
    }
    if (Test-Path "$ServicePath/app.settings.json") {
        # Add default app settings if exists.
        Write-Host "Loading settings from app.settings.json"
        $updateSettings = Get-Content -Raw "$ServicePath/app.settings.json" | ConvertFrom-Json -AsHashtable
        foreach ($key in $updateSettings.Keys) {
            $appSettings.Values[$key] = $updateSettings[$key]
        }
    }

    if (Test-Path "$ServicePath/parameters.json") {
        $parameters = Get-Content -Path "$ServicePath/parameters.json" | ConvertFrom-Json -AsHashtable
    }
    else {
        $parameters = [ordered] @{}
    }
    if (Test-Path "$ServicePath/connections.json") {
        $connections = Get-Content -Raw "$ServicePath/connections.json" | ConvertFrom-Json -AsHashtable
    }
    else {
        $connections = [ordered] @{}
    }

    $CdfConfig.Service = [ordered] @{
        "Config" = @{
            ServiceName     = $ServiceName
            ServiceGroup    = $ServiceGroup
            ServiceType     = $ServiceType
            ServiceTemplate = $ServiceTemplate
        }
        "Tags"   = @{
            BuildRun         = "456123789"
            BuildRepo        = "local"
            BuildBranch      = "local"
            BuildCommit      = "c3b2a1"
            TemplateEnv      = $CdfConfig.Domain.Tags.TemplateEnv
            TemplateName     = $CdfConfig.Domain.Tags.TemplateName
            TemplateVersion  = $CdfConfig.Domain.Tags.TemplateVersion
            TemplateInstance = $CdfConfig.Domain.Tags.TemplateInstance
        }
    }

    #############################################################
    # Setup the service CDF Config file from template
    #############################################################
    $serviceConfig.ServiceDefaults.ServiceName = $ServiceName
    $serviceConfig.ServiceDefaults.ServiceGroup = $ServiceGroup
    $serviceConfig.ServiceDefaults.ServiceType = $ServiceType
    $serviceConfig.ServiceDefaults.ServiceTemplate = $ServiceTemplate

    $serviceConfig | ConvertTo-Json -Depth 5 | Set-Content -Path "$ServicePath/cdf-config.json"

    #############################################################
    # Update service parameter values
    #############################################################
    Write-Host "Setting service CDF parameters"

    # Initialize CDF parameter keys
    if ($null -eq $parameters.Platform) { $parameters.Platform = [ordered] @{ "type" = "object"; "value" = [ordered] @{} } }
    if ($null -eq $parameters.External) { $parameters.External = [ordered] @{ "type" = "object"; "value" = [ordered] @{} } }
    if ($null -eq $parameters.Service) { $parameters.Service = [ordered] @{ "type" = "object"; "value" = [ordered] @{} } }
    if ($null -eq $parameters.Domain) { $parameters.Domain = [ordered] @{ "type" = "object"; "value" = [ordered] @{} } }
    if ($null -eq $parameters.Application) { $parameters.Application = [ordered] @{ "type" = "object"; "value" = [ordered] @{} } }
    if ($null -eq $parameters.Environment) { $parameters.Environment = [ordered] @{ "type" = "object"; "value" = [ordered] @{} } }
    if ($null -eq $parameters.BuildContext) { $parameters.BuildContext = [ordered] @{ "type" = "object"; "value" = [ordered] @{} } }

    Set-LogicAppParameters `
        -CdfConfig $CdfConfig `
        -AppSettings $updateSettings `
        -Parameters $parameters | Out-Null

    $parameters.Environment.value = [ordered] @{
        definitionId   = $CdfConfig.Application.Env.definitionId
        nameId         = $CdfConfig.Application.Env.nameId
        name           = $CdfConfig.Application.Env.name
        shortName      = $CdfConfig.Application.Env.shortName
        description    = $CdfConfig.Application.Env.description
        purpose        = $CdfConfig.Application.Env.purpose
        quality        = $CdfConfig.Application.Env.quality
        region         = $CdfConfig.Application.Env.region
        regionCode     = $CdfConfig.Application.Env.regionCode
        regionName     = $CdfConfig.Application.Env.regionName
        tenantId       = $CdfConfig.Platform.Env.tenantId
        subscriptionId = $CdfConfig.Platform.Env.subscriptionId
    }
    $parameters | ConvertTo-Json -Depth 5 | Set-Content -Path "$ServicePath/parameters.template.json"


    # Substitute Tokens for the config file
    $tokenValues = $CdfConfig | Get-TokenValues
    Update-ConfigFileTokens `
        -InputFile "$ServicePath/parameters.template.json" `
        -OutputFile "$ServicePath/parameters.json" `
        -Tokens $tokenValues `
        -StartTokenPattern "{{" `
        -EndTokenPattern "}}" `
        -NoWarning `
        -WarningAction:SilentlyContinue


    Write-Debug "Parameters: $($parameters | ConvertTo-Json -Depth 5 | Out-String)"
    Write-Host "Wrote updated parameters.json"


    #############################################################
    # Update Service Provider Connections
    #############################################################
    Write-Host "Prepare connections.json"

    $connections | ConvertTo-Json -Depth 5 | Set-Content -Path "$ServicePath/connections.json"
    Write-Debug "Connections: $($connections | ConvertTo-Json -Depth 5 | Out-String)"
    Write-Host "Wrote updated connections.json"

    #############################################################
    # Update local.setting.json with connection uri parameters
    #############################################################
    Write-Host "Prepare local.setting.json"
    $connectionDefinitions = $CdfConfig | Get-ConnectionDefinitions
    $svcConns = $serviceConfig.Connections

    foreach ( $connectionName in $serviceConfig.Connections ) {
        $definition = $connectionDefinitions[$connectionName]
        if ($definition) {
            Write-Host "`t$connectionName"
            # Add Managed API Connections
            $config = $CdfConfig | Get-ManagedApiConnection -ConnectionKey $definition.ConnectionKey
            if ($true -eq $definition.IsApiConnection -and $null -ne $config) {
                $config.Identity = $CdfConfig.Domain.Config.domainIdentityResourceId
                Add-LogicAppManagedApiConnection `
                    -UseCS `
                    -Connections $connections `
                    -ConnectionName $connectionName `
                    -ConnectionConfig $config
            }
            else {
                # Add ServiceProviderConnection
                Add-LogicAppServiceProviderConnection `
                    -UseCS `
                    -Connections $connections `
                    -ConnectionName $connectionName `
                    -serviceProvider $definition.ServiceProvider `
                    -ManagedIdentityResourceId $CdfConfig.Domain.Config.domainIdentityResourceId
            }
        }
    }

    # Add app settings for Logic App Connections
    foreach ( $connectionName in $connectionDefinitions.Keys ) {
        $definition = $connectionDefinitions[$connectionName]
        if ($definition.IsEnabled -and $svcConns.Contains($connectionName)) {
            Write-Host "`tConnection setting for $connectionName"
            Add-LogicAppAppSettings `
                -SubscriptionId $CdfConfig.Platform.Env.subscriptionId `
                -Settings $appSettings.Values  `
                -ConnectionDefinition $definition `
                -ConnectionName $connectionName `
                -ParameterName $definition.ConnectionKey `
                -ServiceProvider $definition.ServiceProvider
        }
    }


    $appSettings.Values.WORKFLOWS_TENANT_ID = $CdfConfig.Platform.Env.tenantId
    $appSettings.Values.WORKFLOWS_SUBSCRIPTION_ID = $CdfConfig.Platform.Env.subscriptionId
    $appSettings.Values.WORKFLOWS_LOCATION_NAME = $CdfConfig.Platform.Config.region
    $appSettings.Values.WORKFLOWS_RESOURCE_GROUP_NAME = $CdfConfig.Platform.ResourceNames.apiConnResourceGroupName

    $appSettings | ConvertTo-Json -Depth 5 | Set-Content -Path "local.settings.json"
    Write-Debug "Settings: $($appSettings | ConvertTo-Json -Depth 5 | Out-String)"
    Write-Host "Wrote updated local.setttings.json"
}