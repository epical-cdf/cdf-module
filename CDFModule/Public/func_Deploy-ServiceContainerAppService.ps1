﻿Function Deploy-ServiceContainerAppService {
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
                $appSettingRef = "@Microsoft.KeyVault(VaultName=$($CdfConfig.Domain.ResourceNames.keyVaultName );SecretName=svc-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier))"
                $appSettingKey = "Param_$serviceSettingKey"
                $updateSettings[$appSettingKey] = $appSettingRef
                $Parameters.Service.value[$setting.Identifier] = "@appsetting('$appSettingKey')"
                Write-Verbose "Prepared KeyVault secret reference for Setting [$($setting.Identifier)] using app setting [$appSettingKey] KeyVault ref [$appSettingRef]"
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

    #-------------------------------------------------------------
    # Preparing the app settings
    #-------------------------------------------------------------

    # Service Identity
    $updateSettings["SERVICE_NAME"] = $CdfConfig.Service.Config.serviceName
    $updateSettings["SERVICE_TYPE"] = $CdfConfig.Service.Config.serviceType
    $updateSettings["SERVICE_GROUP"] = $CdfConfig.Service.Config.serviceGroup
    $updateSettings["SERVICE_TEMPLATE"] = $CdfConfig.Service.Config.serviceTemplate
    $updateSettings["DOMAIN_NAME"] = $CdfConfig.Domain.Config.domainName

    # Build information
    $updateSettings["BUILD_COMMIT"] = $env:GITHUB_SHA ?? $env:BUILD_SOURCEVERSION ?? $(git -C $TemplateDir rev-parse --short HEAD)
    $updateSettings["BUILD_RUN"] = $env:GITHUB_RUN_ID ?? $env:BUILD_BUILDNUMBER ?? "local"
    $updateSettings["BUILD_BRANCH"] = $env:GITHUB_REF_NAME ?? $env:BUILD_SOURCEBRANCH ?? $(git -C $TemplateDir branch --show-current)
    $updateSettings["BUILD_REPOSITORY"] = $env:GITHUB_REPOSITORY ?? $env:BUILD_REPOSITORY_NAME ?? $(Split-Path -Leaf (git -C $TemplateDir remote get-url origin))
    $updateSettings["BUILD_PIPELINE"] = $env:GITHUB_WORKFLOW_REF ?? $env:BUILD_DEFINITIONNAME ?? "local"

    $updateSettings | ConvertTo-Json -Depth 10 | Set-Content -Path "$OutputPath/app.settings.gen.json"

    # Substitute Tokens in the app.settings file
    $tokenValues = $CdfConfig | Get-TokenValues
    Update-ConfigFileTokens `
        -InputFile "$OutputPath/app.settings.gen.json" `
        -OutputFile "$OutputPath/app.settings.json" `
        -Tokens $tokenValues `
        -StartTokenPattern '{{' `
        -EndTokenPattern '}}' `
        -NoWarning `
        -WarningAction:SilentlyContinue

    # Read generated app.settings file with token substitutions
    $updateSettings = Get-Content -Path "$OutputPath/app.settings.json" | ConvertFrom-Json -Depth 10 -AsHashtable

    Set-AzWebApp `
        -Name $appServiceName `
        -ResourceGroupName $appServiceRG `
        -AppSettings $updateSettings `
        -WarningAction:SilentlyContinue | Out-Null

    #--------------------------------------
    # Deploy container app implementation
    #--------------------------------------

    Write-Host "Container App Service implementation deployment done."
}
