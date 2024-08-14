Function Deploy-ServiceContainerAppService {
    <#
        .SYNOPSIS
        Deploys a Container App Service implementation and condfiguration

        .DESCRIPTION
        The cmdlet deploys a Container App Service implementation with configuration of app settings, parameters and connections.

        .PARAMETER CdfConfig
        The CDFConfig object that holds the current scope configurations (Platform, Application and Domain)

        .PARAMETER InputPath
        Path to the Container implementation including cdf-config.json.
        Optional, defaults to "./build"

        .PARAMETER OutputPath
        Output path for the environment specific config with updated parameters.json and connections.json.
        Optional, defaults to "./build"

        .INPUTS
        None. You cannot pipe objects.

        .OUTPUTS
        None.

        .EXAMPLE
        PS> Deploy-ServiceContainerAppService `
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
        [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
        [hashtable]$CdfConfig,
        [Parameter(Mandatory = $false)]
        [string] $InputPath = "./logicapp",
        [Parameter(Mandatory = $false)]
        [string] $OutputPath = "../tmp/$($CdfConfig.Service.Config.serviceName)",
        [Parameter(Mandatory = $false)]
        [string] $TemplateDir = "."
    )

    Write-Host "Preparing Container App Service implementation deployment."

    # Copy service/logicapp implementation
    $containerFiles = @(
        'cdf-config.json',
        '*'
    )
    Copy-Item -Force -Recurse -Include $containerFiles -Path $InputPath/* -Destination $OutputPath

    ## Adjust these if template changes regarding placement of appService for the service
    $appServiceRG = $CdfConfig.Service.ResourceNames.appServiceResourceGroup
    $appServiceName = $CdfConfig.Service.ResourceNames.appServiceName

    Write-Host "appServiceRG: $appServiceRG"
    Write-Host "appServiceName: $appServiceName"

    # #--------------------------------------
    # # Configure connections for target env
    # #--------------------------------------
    # Write-Host "Preparing connections."
    # $connections = Get-Content -Raw "$InputPath/connections.json" | ConvertFrom-Json -AsHashtable

    # # TODO: Make these configurable using a "platform services" definition file
    # # Proposal for definition.json:
    # #   {
    # #     ServiceBus: [
    # #       {
    # #         "Name": "PlatformServiceBus",
    # #         "ServiceProvider": "servicebus",
    # #         "Scope": "Platform
    # #       }
    # #     ],
    # #     KeyVault: [
    # #       {
    # #         "Name": "PlatformKeyVault",
    # #         "ServiceProvider": "keyvault",
    # #         "Scope": "Platform
    # #       },
    # #       {
    # #         "Name": "ApplicationKeyVault",
    # #         "ServiceProvider": "keyvault",
    # #         "Scope": "Application
    # #       },
    # #       {
    # #         "Name": "DomainKeyVault",
    # #         "ServiceProvider": "keyvault",
    # #         "Scope": "Domain
    # #       }
    # #     ]
    # #   }


    # # Platform
    # ($CdfConfig.Platform.Features.enableKeyVault && Add-LogicAppServiceProviderConnection `
    #     -connections $connections -ConnectionName "PlatformKeyVault" `
    #     -serviceProvider "keyvault"`
    # ) | Out-Null

    # ($CdfConfig.Platform.Features.enableServiceBus && Add-LogicAppServiceProviderConnection `
    #     -connections $connections `
    #     -ConnectionName "PlatformServiceBus" `
    #     -serviceProvider "servicebus" `
    # ) | Out-Null

    # if ( $CdfConfig.Platform.Features.enableStorageAccount) {
    #     Add-LogicAppServiceProviderConnection `
    #         -connections $connections -ConnectionName "PlatformStorageAccountBlob" `
    #         -serviceProvider "AzureBlob"
    #     Add-LogicAppServiceProviderConnection `
    #         -connections $connections -ConnectionName "PlatformStorageAccountFile" `
    #         -serviceProvider "azurefile"
    #     Add-LogicAppServiceProviderConnection `
    #         -connections $connections -ConnectionName "PlatformStorageAccountQueues" `
    #         -serviceProvider "azurequeues"
    #     Add-LogicAppServiceProviderConnection `
    #         -connections $connections -ConnectionName "PlatformStorageAccountTables" `
    #         -serviceProvider "azureTables"
    # }

    # # Application
    # ($CdfConfig.Application.Features.enableKeyVault && Add-LogicAppServiceProviderConnection `
    #     -connections $connections `
    #     -ConnectionName "ApplicationKeyVault" `
    #     -serviceProvider "keyvault" `
    # ) | Out-Null
    # ($CdfConfig.Application.Features.enableSftpStorageAccount && Add-LogicAppServiceProviderConnection `
    #     -connections $connections `
    #     -ConnectionName "AppSftpStorageAccountBlob" `
    #     -serviceProvider "AzureBlob" `
    # ) | Out-Null

    # # Domain
    # ($CdfConfig.Domain.Features.enableKeyVault && Add-LogicAppServiceProviderConnection `
    #     -connections $connections `
    #     -ConnectionName "DomainKeyVault" `
    #     -serviceProvider "keyvault" `
    # ) | Out-Null

    # if ( $CdfConfig.Domain.Features.enableStorageAccount) {
    #     Add-LogicAppServiceProviderConnection `
    #         -connections $connections `
    #         -ConnectionName "DomainStorageAccountBlob" `
    #         -serviceProvider "AzureBlob"
    #     Add-LogicAppServiceProviderConnection `
    #         -connections $connections `
    #         -ConnectionName "DomainStorageAccountFile"`
    #         -serviceProvider "azurefile"
    #     Add-LogicAppServiceProviderConnection `
    #         -connections $connections `
    #         -ConnectionName "DomainStorageAccountQueues" `
    #         -serviceProvider "azurequeues"
    #     Add-LogicAppServiceProviderConnection `
    #         -connections $connections `
    #         -ConnectionName "DomainStorageAccountTables" `
    #         -serviceProvider "azureTables"
    # }

    # Write-Debug "Connections: $($connections | ConvertTo-Json -Depth 10 | Out-String)"
    # $connections | ConvertTo-Json -Depth 10 | Set-Content -Path "$OutputPath/$($CdfConfig.Service.Config.serviceName)/connections.json"

    #--------------------------------------
    # Preparing appsettings for target env
    #--------------------------------------
    Write-Host "Preparing app settings."

    # Get app service settings
    $app = Get-AzWebApp `
        -DefaultProfile $azCtx `
        -Name $appServiceName `
        -ResourceGroupName $appServiceRG `
        -WarningAction:SilentlyContinue

    $appSettings = $app.SiteConfig.AppSettings

    # Preparing hashtable with exsting config
    $updateSettings = ConvertFrom-Json -InputObject "{}" -AsHashtable
    foreach ($setting in $appSettings) {
        $updateSettings[$setting.Name] = $setting.Value
    }

    # # TODO: Make these configurable using a "platform services" definition file

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


    # Get service config from cdf-config.json
    $serviceConfig = Get-Content -Path "$InputPath/cdf-config.json" | ConvertFrom-Json -AsHashtable

    # Service internal settings
    foreach ($serviceSettingKey in $serviceConfig.ServiceSettings.Keys) {
        Write-Host "Adding service internal setting: $serviceSettingKey"
        $setting = $serviceConfig.ServiceSettings[$serviceSettingKey]
        switch ($setting.Type) {
            "Constant" {
                #  $Parameters.Service.value[$serviceSettingKey] = $setting.Value
                $updateSettings["SERVICE_$serviceSettingKey"] = ($setting.Value | Out-String -NoNewline)
            }
            "Setting" {
                # $Parameters.Service.value[$serviceSettingKey] = $setting.Values[0].Value
                $updateSettings["SERVICE_$serviceSettingKey"] = ($setting.Values[0].Value | Out-String -NoNewline)

            }
            "Secret" {
                # $secret = Get-AzKeyVaultSecret `
                #     -DefaultProfile $azCtx `
                #     -VaultName $CdfConfig.Domain.ResourceNames.keyVaultName `
                #     -Name "svc-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier)" `
                #     -AsPlainText `
                #     -ErrorAction SilentlyContinue

                # if ($null -eq $secret) {
                #     Write-Warning " KeyVault secret for Identifier [$($setting.Identifier)] not found"
                #     Write-Warning " Expecting secret name [svc-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier)] in Domain KeyVault"
                # }
                # else {
                $appSettingRef = "@Microsoft.KeyVault(VaultName=$($CdfConfig.Domain.ResourceNames.keyVaultName );SecretName=svc-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier))"
                $appSettingKey = "Param_$serviceSettingKey"
                $updateSettings[$appSettingKey] = $appSettingRef
                $Parameters.Service.value[$setting.Identifier] = "@appsetting('$appSettingKey')"
                Write-Verbose "Prepared KeyVault secret reference for Setting [$($setting.Identifier)] using app setting [$appSettingKey] KeyVault ref [$appSettingRef]"
                # }
            }
        }
    }

    # Service external settings
    foreach ($externalSettingKey in $serviceConfig.ExternalSettings.Keys) {
        Write-Host "Adding service external setting: $externalSettingKey"
        $setting = $serviceConfig.ExternalSettings[$externalSettingKey]
        switch ($setting.Type) {
            "Constant" {
                # $Parameters.External.value[$externalSettingKey] = $setting.Value
                $updateSettings["EXTERNAL_$serviceSettingKey"] = ($setting.Value | Out-String -NoNewline)

            }
            "Setting" {
                [string] $value = ($setting.Values  | Where-Object { $_.Purpose -eq $CdfConfig.Application.Env.purpose }).Value
                # $Parameters.External.value[$externalSettingKey] = $setting.Values[0].Value
                $updateSettings["EXTERNAL_$serviceSettingKey"] = $value
            }
            "Secret" {
                $secret = Get-AzKeyVaultSecret `
                    -DefaultProfile $azCtx `
                    -VaultName $CdfConfig.Domain.ResourceNames.keyVaultName `
                    -Name "svc-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier)" `
                    -AsPlainText `
                    -ErrorAction SilentlyContinue

                if ($null -eq $secret) {
                    Write-Warning " KeyVault secret for Identifier [$($setting.Identifier)] not found"
                    Write-Warning " Expecting secret name [svc-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier)] in Domain KeyVault"
                }
                else {
                    # $Parameters.External.value[$externalSettingKey] = $secret
                    $updateSettings["EXTERNAL_$serviceSettingKey"] = ($secret | Out-String -NoNewline)

                    $appSettingRef = "@Microsoft.KeyVault(VaultName=$($CdfConfig.Domain.ResourceNames.keyVaultName );SecretName=svc-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier))"
                    $appSettingKey = "EXT_$serviceSettingKey"
                    $updateSettings[$appSettingKey] = $appSettingRef
                    $Parameters.Service.value[$setting.Identifier] = "@appsetting('$appSettingKey')"
                    Write-Verbose "Prepared KeyVault secret reference for Setting [$($setting.Identifier)] using app setting [$appSettingKey] KeyVault ref [$appSettingRef]"

                }

            }
        }
    }

    # Configure service API URLs
    $updateSettings["SERVICE_API_BASEURL"] = "https://$($app.HostNames[0])"
    $BaseUrls = @()
    foreach ($hostName in $app.HostNames) { $BaseUrls += "https://$hostName" }
    $updateSettings["SERVICE_API_BASEURLS"] = $BaseUrls | Join-String -Separator ','

    if ($CdfConfig.Application.Env.purpose -eq 'production') {
        $updateSettings["WEBSITE_RUN_FROM_PACKAGE"] = "1"
        Write-Host "PRODUCTION: Enable 'WEBSITE_RUN_FROM_PACKAGE' which prevents editing in Azure Portal." -ForegroundColor Yellow
    }
    else {
        $updateSettings["WEBSITE_RUN_FROM_PACKAGE"] = "0"
        Write-Host "NON-PRODUCTION: Disabling 'WEBSITE_RUN_FROM_PACKAGE' which allows editing in Azure Portal." -ForegroundColor Blue
    }
    #-------------------------------------------------------------
    # Preparing the app settings
    #-------------------------------------------------------------

    $updateSettings | ConvertTo-Json -Depth 10 | Set-Content -Path "$OutputPath/$($CdfConfig.Service.Config.serviceName)/app.settings.raw.json"

    # Substitute Tokens in the app.settings file
    $tokenValues = $CdfConfig | Get-TokenValues
    Update-ConfigFileTokens `
        -InputFile "$OutputPath/$($CdfConfig.Service.Config.serviceName)/app.settings.raw.json" `
        -OutputFile "$OutputPath/$($CdfConfig.Service.Config.serviceName)/app.settings.json" `
        -Tokens $tokenValues `
        -StartTokenPattern '{{' `
        -EndTokenPattern '}}' `
        -NoWarning `
        -WarningAction:SilentlyContinue

    Remove-Item -Path "$OutputPath/$($CdfConfig.Service.Config.serviceName)/local.settings.json" -ErrorAction SilentlyContinue

    # Read generated app.settings file with token substitutions
    $updateSettings = Get-Content -Path "$OutputPath/$($CdfConfig.Service.Config.serviceName)/app.settings.json" | ConvertFrom-Json -Depth 10 -AsHashtable

    Set-AzWebApp `
        -Name $appServiceName `
        -ResourceGroupName $appServiceRG `
        -AppSettings $updateSettings `
        -WarningAction:SilentlyContinue | Out-Null

    #--------------------------------------
    # Deploy container app implementation
    #--------------------------------------
    Write-Host "Deploying workflows."

    Compress-Archive -Force  `
        -Path "$OutputPath/$($CdfConfig.Service.Config.serviceName)/*"  `
        -DestinationPath "$OutputPath/deployment-package-$($CdfConfig.Service.Config.serviceName).zip"

    Publish-AzWebApp -Force `
        -Name $appServiceName `
        -ResourceGroupName $appServiceRG `
        -ArchivePath "$OutputPath/deployment-package-$($CdfConfig.Service.Config.serviceName).zip" `
        -WarningAction:SilentlyContinue | Out-Null

    Write-Host "Container App Service implementation deployment done."
}
