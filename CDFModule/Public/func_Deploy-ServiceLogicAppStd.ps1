Function Deploy-ServiceLogicAppStd {
    <#
        .SYNOPSIS
        Deploys a Logic App standard implementation and condfiguration

        .DESCRIPTION
        The cmdlet deploys a Logic App standard implementation with configuration of app settings, parameters and connections.

        .PARAMETER CdfConfig
        The CDFConfig object that holds the current scope configurations (Platform, Application and Domain)

        .PARAMETER InputPath
        Path to the logic app implementation including cdf-config.json.
        Optional, defaults to "./build"

        .PARAMETER OutputPath
        Output path for the environment specific config with updated parameters.json and connections.json.
        Optional, defaults to "./build"

        .INPUTS
        None. You cannot pipe objects.

        .OUTPUTS
        None.

        .EXAMPLE
        PS> Deploy-CdfServiceLogicAppStd `
            -Platform $CdfConfig.Platform `
            -Application $CdfConfig.Application `
            -Domain $CdfConfig.Domain `
            -Service $CdfConfig.Service `
            -InputPath "./la-<name>" `
            -OutputPath "./build"

        .LINK
        Deploy-CdfTemplatePlatform
        Deploy-CdfTemplateApplication
        Deploy-CdfTemplateDomain
        Deploy-CdfTemplateService
        Get-CdfGitHubPlatformConfig
        Get-CdfGitHubApplicationConfig
        Get-CdfGitHubDomainConfig
        Get-CdfGitHubServiceConfig
        Deploy-CdfStorageAccountConfig

    #>

    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [hashtable]$CdfConfig,
        [Parameter(Mandatory = $false)]
        [string] $InputPath = ".",
        [Parameter(Mandatory = $false)]
        [string] $OutputPath = "../tmp/$($CdfConfig.Service.Config.serviceName)",
        [Parameter(Mandatory = $false)]
        [string] $TemplateDir = $env:CDF_INFRA_TEMPLATES_PATH ?? "../../cdf-infra"
    )

    Write-Host "Preparing Logic App Standard implementation deployment."

    if (!$OutputPath) {
        $OutputPath = "../tmp/$($CdfConfig.Service.Config.serviceName)"
    }

    # Copy service/logicapp implementation
    New-Item -Force -ItemType Directory -Path $OutputPath -ErrorAction:SilentlyContinue | Out-Null

    $laFiles = @(
        'wf-*',
        'cdf-config.json',
        'host.json',
        'parameters.json',
        'connections.json',
        'app.settings.json',
        'Artifacts',
        'lib'
    )
    Copy-Item -Force -Recurse -Include $laFiles -Path (Resolve-Path -Path $InputPath/*) -Destination (Resolve-Path -Path $OutputPath)

    ## Adjust these if template changes regarding placement of logicapp for the service
    $logicAppRG = $CdfConfig.Service.ResourceNames.logicAppResourceGroup
    $logicAppName = $CdfConfig.Service.ResourceNames.logicAppName

    Write-Verbose "logicAppRG: $logicAppRG"
    Write-Verbose "logicAppName: $logicAppName"

    $azCtx = Get-CdfAzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId

    #--------------------------------------
    # Configure parameters for target env
    #--------------------------------------
    Write-Host "Preparing parameters."

    $serviceConfig = Get-Content -Path "$InputPath/cdf-config.json" | ConvertFrom-Json -AsHashtable
    $parameters = Get-Content -Path "$InputPath/parameters.json" | ConvertFrom-Json -AsHashtable

    # TODO: Fix this workaround with override of the logic app infra build tags to set the logic app implementation build context parameters
    $CdfConfig.Service.Tags.BuildCommit = $env:GITHUB_SHA ?? $env:BUILD_SOURCEVERSION ?? $(git -C $InputPath rev-parse --short HEAD)
    $CdfConfig.Service.Tags.BuildRun = $env:GITHUB_RUN_ID ?? $env:BUILD_BUILDNUMBER ?? "local"
    $CdfConfig.Service.Tags.BuildBranch = $env:GITHUB_REF_NAME ?? $env:BUILD_SOURCEBRANCH ?? $(git -C $InputPath branch --show-current)
    $CdfConfig.Service.Tags.BuildRepo = $env:GITHUB_REPOSITORY ?? $env:BUILD_REPOSITORY_NAME ?? $(Split-Path -Leaf (git -C $InputPath remote get-url origin))

    $paramAppSettings = Set-LogicAppParameters `
        -CdfConfig $CdfConfig `
        -ServiceConfig $serviceConfig `
        -Parameters $parameters

    $parameters | ConvertTo-Json -Depth 10 | Set-Content -Path "$OutputPath/parameters.raw.json"

    # Substitute Tokens in the parameters file
    $tokenValues = $CdfConfig | Get-TokenValues
    Update-ConfigFileTokens `
        -InputFile  "$OutputPath/parameters.raw.json" `
        -OutputFile  "$OutputPath/parameters.json" `
        -Tokens $tokenValues `
        -StartTokenPattern '{{' `
        -EndTokenPattern '}}' `
        -NoWarning `
        -WarningAction:SilentlyContinue

    #--------------------------------------
    # Configure connections for target env
    #--------------------------------------
    Write-Host "Preparing connections."
    $connections = Get-Content -Raw "$InputPath/connections.json" | ConvertFrom-Json -AsHashtable
    $connectionDefinitions = $CdfConfig | Get-ConnectionDefinitions
    $svcConns = $serviceConfig.Connections ?? $connectionDefinitions.Keys

    # Loop through all Platform, Application and Domain connections
    foreach ( $connectionName in $connectionDefinitions.Keys ) {
        $definition = $connectionDefinitions[$connectionName]
        if ($definition.IsEnabled -and $svcConns.Contains($connectionName)) {
            Write-Host "`t$connectionName"

            # Add ServiceProviderConnection
            Add-LogicAppServiceProviderConnection `
                -Connections $connections `
                -ConnectionName $connectionName `
                -serviceProvider $definition.ServiceProvider `
                -ManagedIdentityResourceId $CdfConfig.Domain.Config.domainIdentityResourceId

            # Add duplicate connection config for API Connections
            $config = $CdfConfig | Get-ManagedApiConnection -ConnectionKey $definition.ConnectionKey
            if ($definition.IsEnabled -and $definition.IsApiConnection -and $null -ne $config) {
                $config.Identity = $CdfConfig.Domain.Config.domainIdentityResourceId
                Add-LogicAppManagedApiConnection `
                    -Connections $connections `
                    -ConnectionName $connectionName `
                    -ConnectionConfig $config
            }
        }
    }

    # Loop through any Custom connections referenced
    foreach ( $connectionName in $svcConns ) {
        if ($connectionName.StartsWith('Enterprise') -or $connectionName.StartsWith('External') -or $connectionName.StartsWith('Internal') ) {
            $config = $CdfConfig | Get-ManagedApiConnection -ConnectionKey $connectionName
            if ($null -ne $config) {
                $config.Identity = $CdfConfig.Domain.Config.domainIdentityResourceId
                Write-Host "`t$connectionName"
                Add-LogicAppManagedApiConnection `
                    -Connections $connections `
                    -ConnectionName $connectionName `
                    -ConnectionConfig $config

                # Add access policy for logic app domain identity
                $CdfConfig | Add-ManagedApiConnectionAccess `
                    -ConnectionName $connectionName `
                    -ManagedIdentityResourceId $CdfConfig.Domain.Config.domainIdentityResourceId
            }
            else {
                Write-Host "`t$connectionName - missing connection configuration" -ForegroundColor Yellow
            }
        }
    }

    Write-Debug "Connections: $($connections | ConvertTo-Json -Depth 10 | Out-String)"
    $connections | ConvertTo-Json -Depth 10 | Set-Content -Path "$OutputPath/connections.json"

    #--------------------------------------
    # Preparing appsettings for target env
    #--------------------------------------
    Write-Host "Preparing app settings."

    # Get app service settings
    $app = Get-AzWebApp `
        -DefaultProfile $azCtx `
        -Name $logicAppName `
        -ResourceGroupName $logicAppRG `
        -WarningAction:SilentlyContinue `
        -ErrorAction:Stop

    $appSettings = $app.SiteConfig.AppSettings

    # Preparing hashtable with exsting config
    $updateSettings = ConvertFrom-Json -InputObject "{}" -AsHashtable
    foreach ($setting in $appSettings) {
        $updateSettings[$setting.Name] = $setting.Value
    }

    # Add app settings for parameter references
    foreach ($settingKey in $paramAppSettings.Keys) {
        Write-Verbose "Adding parameter appsetting for [$settingKey] value [$($paramAppSettings[$settingKey])]"
        $updateSettings[$settingKey] = $paramAppSettings[$settingKey]
    }

    # TODO: Make these configurable using a "platform services" definition file
    foreach ( $connectionName in $connectionDefinitions.Keys ) {
        $definition = $connectionDefinitions[$connectionName]
        if ($definition.IsEnabled -and $svcConns.Contains($connectionName)) {
            Write-Host "`tConnection setting for $connectionName"
            Add-LogicAppAppSettings `
                -SubscriptionId $CdfConfig.Platform.Env.subscriptionId `
                -Settings $updateSettings `
                -Config $CdfConfig[$definition.Scope] `
                -ConnectionName $connectionName `
                -ParameterName $definition.ConnectionKey `
                -ServiceProvider $definition.ServiceProvider
        }
    }

    # # Platform Connections Uri Settings
    # ($CdfConfig.Platform.Features.enableKeyVault && Add-LogicAppAppSettings `
    #     -SubscriptionId $CdfConfig.Platform.Env.subscriptionId `
    #     -Config $CdfConfig.Platform `
    #     -Settings $updateSettings `
    #     -ConnectionName "PlatformKeyVault" `
    #     -ParameterName "platformKeyVault" `
    #     -ServiceProvider "keyvault" `
    # ) | Out-Null

    # ($CdfConfig.Platform.Features.enableServiceBus && Add-LogicAppAppSettings `
    #     -SubscriptionId $CdfConfig.Platform.Env.subscriptionId `
    #     -Config $CdfConfig.Platform -Settings $updateSettings `
    #     -ConnectionName "PlatformServiceBus" `
    #     -ParameterName "platformServiceBus" `
    #     -ServiceProvider "servicebus" `
    # ) | Out-Null

    # if ( $CdfConfig.Platform.Features.enableStorageAccount) {
    #     Add-LogicAppAppSettings `
    #         -SubscriptionId $CdfConfig.Platform.Env.subscriptionId `
    #         -Config $CdfConfig.Platform -Settings $updateSettings `
    #         -ConnectionName "PlatformStorageAccountBlob" `
    #         -ParameterName "platformStorageAccount" `
    #         -ServiceProvider "AzureBlob"
    #     Add-LogicAppAppSettings `
    #         -SubscriptionId $CdfConfig.Platform.Env.subscriptionId `
    #         -Config $CdfConfig.Platform -Settings $updateSettings `
    #         -ConnectionName "PlatformStorageAccountFile" `
    #         -ParameterName "platformStorageAccount" `
    #         -ServiceProvider "azurefile"
    #     Add-LogicAppAppSettings `
    #         -SubscriptionId $CdfConfig.Platform.Env.subscriptionId `
    #         -Config $CdfConfig.Platform -Settings $updateSettings `
    #         -ConnectionName "PlatformStorageAccountQueues" `
    #         -ParameterName "platformStorageAccount" `
    #         -ServiceProvider "azurequeues"
    #     Add-LogicAppAppSettings `
    #         -SubscriptionId $CdfConfig.Platform.Env.subscriptionId `
    #         -Config $CdfConfig.Platform -Settings $updateSettings `
    #         -ConnectionName "PlatformStorageAccountTables" `
    #         -ParameterName "platformStorageAccount" `
    #         -ServiceProvider "azureTables"
    # }

    # # Application Connections Uri Settings
    # ($CdfConfig.Application.Features.enableStorageAccount && Add-LogicAppAppSettings `
    #     -SubscriptionId $CdfConfig.Platform.Env.subscriptionId `
    #     -Config $CdfConfig.Application  -Settings $updateSettings `
    #     -ConnectionName "ApplicationKeyVault" `
    #     -ParameterName "applicationKeyVault"`
    #     -ServiceProvider "keyvault" `
    # ) | Out-Null
    # ($CdfConfig.Application.Features.enableSftpStorageAccount && Add-LogicAppAppSettings `
    #     -SubscriptionId $CdfConfig.Platform.Env.subscriptionId `
    #     -Config $CdfConfig.Application  -Settings $updateSettings `
    #     -ConnectionName "AppSftpStorageAccountBlob" `
    #     -ParameterName "appSftpStorageAccount" `
    #     -ServiceProvider "AzureBlob" `
    # ) | Out-Null

    # # Domain Connections Uri Settings
    # ($CdfConfig.Domain.Features.enableKeyVault && Add-LogicAppAppSettings  `
    #     -SubscriptionId $CdfConfig.Platform.Env.subscriptionId  `
    #     -Config $CdfConfig.Domain -Settings $updateSettings  `
    #     -ConnectionName "DomainKeyVault"  `
    #     -ParameterName "domainKeyVault"  `
    #     -ServiceProvider "keyvault" `
    # ) | Out-Null
    # if ( $CdfConfig.Domain.Features.enableStorageAccount) {
    #     Add-LogicAppAppSettings  `
    #         -SubscriptionId $CdfConfig.Platform.Env.subscriptionId  `
    #         -Config $CdfConfig.Domain  `
    #         -Settings $updateSettings  `
    #         -ConnectionName "DomainStorageAccountBlob"  `
    #         -ParameterName "domainStorageAccount"  `
    #         -ServiceProvider "AzureBlob"
    #     Add-LogicAppAppSettings  `
    #         -SubscriptionId $CdfConfig.Platform.Env.subscriptionId  `
    #         -Config $CdfConfig.Domain -Settings $updateSettings  `
    #         -ConnectionName "DomainStorageAccountFile"  `
    #         -ParameterName "domainStorageAccount"  `
    #         -ServiceProvider "azurefile"
    #     Add-LogicAppAppSettings  `
    #         -SubscriptionId $CdfConfig.Platform.Env.subscriptionId  `
    #         -Config $CdfConfig.Domain `
    #         -Settings $updateSettings  `
    #         -ConnectionName "DomainStorageAccountQueues"  `
    #         -ParameterName "domainStorageAccount"  `
    #         -ServiceProvider "azurequeues"
    #     Add-LogicAppAppSettings  `
    #         -SubscriptionId $CdfConfig.Platform.Env.subscriptionId  `
    #         -Config $CdfConfig.Domain  `
    #         -Settings $updateSettings  `
    #         -ConnectionName "DomainStorageAccountTables"  `
    #         -ParameterName "domainStorageAccount"  `
    #         -ServiceProvider "azureTables"
    # }

    if ($CdfConfig.Application.Env.purpose -eq 'production') {
        $updateSettings["WEBSITE_RUN_FROM_PACKAGE"] = "1"
        Write-Host "PRODUCTION: Using 'WEBSITE_RUN_FROM_PACKAGE=1' which prevents editing in Azure Portal." -ForegroundColor Yellow
    }
    else {
        $updateSettings["WEBSITE_RUN_FROM_PACKAGE"] = "0"
        Write-Host "NON-PRODUCTION: Using 'WEBSITE_RUN_FROM_PACKAGE=0' which allows editing in Azure Portal." -ForegroundColor Gray
    }

    if (Test-Path "$OutputPath/app.settings.json") {
        # Add default app settings if exists - override any generated app settings
        Write-Host "Loading settings from app.settings.json"
        $defaultSettings = Get-Content -Raw "$OutputPath/app.settings.json" | ConvertFrom-Json -AsHashtable
        foreach ($key in $defaultSettings.Keys) {
            Write-Verbose "Adding parameter appsetting for [$key] value [$($defaultSettings[$key])]"
            $updateSettings[$key] = $defaultSettings[$key]
        }
    }
    #-------------------------------------------------------------
    # Update the app settings
    #-------------------------------------------------------------
    $updateSettings | ConvertTo-Json -Depth 10 | Set-Content -Path "$OutputPath/app.settings.gen.json"
    Remove-Item -Path "$OutputPath/local.settings.json" -ErrorAction SilentlyContinue

    Set-AzWebApp `
        -DefaultProfile $azCtx `
        -Name $logicAppName `
        -ResourceGroupName $logicAppRG `
        -AppSettings $updateSettings `
        -WarningAction:SilentlyContinue | Out-Null

    #-----------------------------------------------------------
    # Deploy logic app implementation using 'run-from-package'
    #-----------------------------------------------------------
    Write-Host "Deploying workflows using zip-file."

    # $inputPath = Resolve-Path -Path "$OutputPath/."
    # $outputPath = Resolve-Path -Path "$OutputPath/deployment-package-$($CdfConfig.Service.Config.serviceName).zip"
    # Get-ChildItem -Path $inputPath  -Filter *.* | Compress-Archive -DestinationPath $outputPath
    # Get-ChildItem -Path $inputPath  -Force | Compress-Archive -DestinationPath $outputPath
    Compress-Archive -Force `
        -Path "$OutputPath/*" `
        -DestinationPath "$OutputPath/deployment-package-$($CdfConfig.Service.Config.serviceName).zip"

    $tries = 0
    do {
        try {
            Publish-AzWebApp -Force `
                -DefaultProfile $azCtx `
                -Name $logicAppName `
                -ResourceGroupName $logicAppRG `
                -ArchivePath "$OutputPath/deployment-package-$($CdfConfig.Service.Config.serviceName).zip" `
                -WarningAction:SilentlyContinue | Out-Null
            break
        }
        catch {
            $tries++
            Write-Warning "Deployment failed:"$_.Exception
            if ($tries++ -le 3) {
                Write-Host "Retrying in 10 seconds..."
                Start-Sleep 10
            }
        }
    } until ($tries -gt 3)


    Write-Host "Logic App Standard implementation deployment done."
}
