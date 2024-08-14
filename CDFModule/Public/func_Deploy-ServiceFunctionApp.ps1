Function Deploy-ServiceFunctionApp {
    <#
        .SYNOPSIS
        Deploys a Function App Service implementation and condfiguration

        .DESCRIPTION
        The cmdlet deploys a Function App Service implementation with configuration of app settings, parameters and connections.      
    
        .PARAMETER CdfConfig
        The CDFConfig object that holds the current scope configurations (Platform, Application and Domain)
        
        .PARAMETER InputPath
        Path to the Function implementation including cdf-config.json.
        Optional, defaults to "./build"
        
        .PARAMETER OutputPath
        Output path for the environment specific config with updated parameters.json and connections.json.
        Optional, defaults to "./build"

        .INPUTS
        None. You cannot pipe objects.

        .OUTPUTS
        None.

        .EXAMPLE
        PS> Deploy-ServiceFunctionAppService `
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
        [string] $InputPath = "./logicapp",
        [Parameter(Mandatory = $false)]
        [string] $OutputPath = "../tmp/$($CdfConfig.Service.Config.serviceName)",
        [Parameter(Mandatory = $false)]
        [string] $TemplateDir = $env:CDF_INFRA_TEMPLATES_PATH ?? "../../cdf-infra"
    )

    Write-Host "Preparing Function App Service implementation deployment."

    # Copy service/logicapp implementation

    # 'dist'
    # 'node_modules',
    [string[]]$functionFiles = @(
        'src'
        '.npmrc',
        'package.json',
        'package-lock.json',
        'app.settings.json',
        'host.json',
        'tsconfig.json'
        '.funcignore'
    )
   
    Copy-Item -Force -Recurse -Include $functionFiles -Path $InputPath/* -Destination $OutputPath
    
    # Write-Host "Build function..."
    # Push-Location $OutputPath
    # npm install
    # npm run build
    # Remove-Item -Force -Recurse node_modules
    # npm install --omit=dev
    # Pop-Location

    # Copy-Item -Force -Recurse -Exclude $exclude -Path $InputPath/* -Destination $OutputPath

    # Get-ChildItem -Path $InputPath/* -Recurse -Exclude $exclude | Copy-Item -Force -Destination {
    #     if ($_.GetType() -eq [System.IO.FileInfo]) {
    #         Join-Path $OutputPath $_.FullName.Substring($InputPath.length)
    #     }
    #     else {
    #         Join-Path $OutputPath $_.Parent.FullName.Substring($InputPath.length)
    #     }
    # }
      
    ## Adjust these if template changes regarding placement of appService for the service
    $appServiceRG = $CdfConfig.Service.ResourceNames.functionAppResourceGroup
    $appServiceName = $CdfConfig.Service.ResourceNames.functionAppName

    Write-Host "AppServiceRG: $appServiceRG"
    Write-Host "AppServiceName: $appServiceName"

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

    # Get service config from cdf-config.json
    $serviceConfig = Get-Content -Path "$InputPath/cdf-config.json" | ConvertFrom-Json -AsHashtable
 

    #--------------------------------------
    # Configure connections for target env
    #--------------------------------------
    Write-Host "Preparing connections."
    $connectionDefinitions = $CdfConfig | Get-ConnectionDefinitions 
    $svcConns = $serviceConfig.Connections ?? $connectionDefinitions.Keys

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

    # Run from package
    $updateSettings["WEBSITE_RUN_FROM_PACKAGE"] = "0"
    $updateSettings["SCM_DO_BUILD_DURING_DEPLOYMENT"] = "true"
    $updateSettings["ENABLE_ORYX_BUILD"] = "true"


    # Add default app settings if exists - override any generated app settings
    if (Test-Path "$OutputPath/app.settings.json") {
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

    #-------------------------------------------------------------
    # Preparing the app settings
    #-------------------------------------------------------------

    $updateSettings | ConvertTo-Json -Depth 10 | Set-Content -Path "$OutputPath/app.settings.raw.json"

    # Substitute Tokens in the app.settings file
    $tokenValues = $CdfConfig | Get-TokenValues
    Update-ConfigFileTokens `
        -InputFile "$OutputPath/app.settings.raw.json" `
        -OutputFile "$OutputPath/app.settings.json" `
        -Tokens $tokenValues `
        -StartTokenPattern '{{' `
        -EndTokenPattern '}}' `
        -NoWarning `
        -WarningAction:SilentlyContinue 

    Remove-Item -Path "$OutputPath/local.settings.json" -ErrorAction SilentlyContinue

    # Read generated app.settings file with token substitutions
    $updateSettings = Get-Content -Path "$OutputPath/app.settings.json" | ConvertFrom-Json -Depth 10 -AsHashtable

    Set-AzWebApp `
        -Name $appServiceName `
        -ResourceGroupName $appServiceRG `
        -AppSettings $updateSettings `
        -WarningAction:SilentlyContinue | Out-Null

    #--------------------------------------
    # Deploy function app implementation
    #--------------------------------------
    Write-Host "Deploying functions."


    # '*.ts'
    # '*/tsconfig.json'
    # '*/node_modules/@types/*'
    # '*/node_modules/azure-functions-core-tools/*'
    # '*/node_modules/typescript/*'
    [string[]]$exclude = @(
        'app.settings.*'
    ) 
    $OutputPath = Resolve-Path $OutputPath
    New-Zip `
        -Exclude $exclude `
        -FolderPath $OutputPath `
        -ZipPath "$OutputPath/deployment-package-$($CdfConfig.Service.Config.serviceName).zip" 

    # Compress-Archive -Force  `
    #     -Path "$OutputPath/*"  `
    #     -DestinationPath "$OutputPath/deployment-package-$($CdfConfig.Service.Config.serviceName).zip"

    Publish-AzWebApp -Force `
        -Name $appServiceName `
        -ResourceGroupName $appServiceRG `
        -ArchivePath "$OutputPath/deployment-package-$($CdfConfig.Service.Config.serviceName).zip" `
        -WarningAction:SilentlyContinue | Out-Null

    Write-Host "Function App Service implementation deployment done."
}
