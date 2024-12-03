Function Get-ServiceConfigSettings {
    <#
        .SYNOPSIS
        Get service configuration settings

        .DESCRIPTION
        Get service configuration settings

        .PARAMETER CdfConfig
        The CDFConfig object that holds the current scope configurations (Platform, Application and Domain)
        Optional, if not provided then config will be generated based on env variables

        .PARAMETER UpdateSettings
        Existing settings. New settings will be attched to it.
        Optional

        .PARAMETER SecretValue
        When this paramter/switch is enabled the command will fetch the actual secret value from KeyVault instead of a reference.

        .PARAMETER ConfigFileName
        This optional parameter allows to reference a different config file name than the default 'cdf-config.json'.

        .PARAMETER InputPath
        Path to the service implementation where CDF config file resides. Defaults to current working directory.

        .PARAMETER TemplateDir
        Path to templates
        Optional, defaults to "./build"

        .INPUTS
        None. You cannot pipe objects.

        .OUTPUTS
        None.

        .EXAMPLE
        PS> Get-ServiceConfigSettings `
            -CdfConfig $CdfConfig `
            -UpdateSettings $UpdateSettings `
            -InputPath "./<service-name>" `
            -TemplateDir "."

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
        [hashtable]$UpdateSettings,
        [Parameter(Mandatory = $false)]
        [switch] $Deployed,
        [Parameter(Mandatory = $false)]
        [switch] $SecretValue,
        [Parameter(Mandatory = $false)]
        [string] $ConfigFileName = 'cdf-config.json',
        [Parameter(Mandatory = $true)]
        [string] $InputPath = ".",
        [Parameter(Mandatory = $false)]
        [string] $TemplateDir = $env:CDF_INFRA_TEMPLATES_PATH ?? "."

    )

    if ($null -eq $CdfConfig) {
        if ($Deployed) {
            $CdfConfig = Get-CdfConfig -Deployed
        }
        else {
            $CdfConfig = Get-CdfConfig
        }
        Write-Verbose (ConvertTo-Json $CdfConfig.Domain)
    }

    if ($null -eq $UpdateSettings) {
        $UpdateSettings = @{}
    }

    $cdfConfigFile = Join-Path -Path $InputPath  -ChildPath $ConfigFileName
    $serviceConfig = Get-Content -Raw $cdfConfigFile | Update-ConfigToken -NoWarning -Tokens ($CdfConfig | Get-TokenValues) | ConvertFrom-Json -AsHashtable

    foreach ($serviceSettingKey in $serviceConfig.ServiceSettings.Keys) {
        Write-Verbose "Adding service internal setting: $serviceSettingKey"
        $setting = $serviceConfig.ServiceSettings[$serviceSettingKey]
        $appSettingKey = "SVC_$serviceSettingKey"
        switch ($setting.Type) {
            "Constant" {
                $UpdateSettings[$appSettingKey] = [string] $setting.Value
            }
            "Setting" {
                [string] $value = ($setting.Values | Where-Object { $_.Purpose -eq $CdfConfig.Application.Env.purpose }).Value
                $UpdateSettings[$appSettingKey] = $value
            }
            "Secret" {
                $kvSecretName = "Internal-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier)"
                if ($SecretValue) {
                    $secret = Get-AzKeyVaultSecret `
                        -DefaultProfile $azCtx `
                        -VaultName $CdfConfig.Domain.ResourceNames.keyVaultName `
                        -Name $kvSecretName `
                        -ErrorAction SilentlyContinue

                    if ($null -eq $secret) {
                        Write-Warning " KeyVault secret not found in Domain KeyVault."
                        Write-Warning " Expecting secret by name [$kvSecretName] in KeyVault [$($CdfConfig.Domain.ResourceNames.keyVaultName)]"
                    }
                    else {
                        $UpdateSettings[$appSettingKey] = [System.Net.NetworkCredential]::new("", $secret.SecretValue).Password
                        Write-Verbose "Prepared KeyVault secret [$kvSecretName] for Setting [$appSettingKey]"
                    }
                }
                else {
                    $appSettingRef = "@Microsoft.KeyVault(VaultName=$($CdfConfig.Domain.ResourceNames.keyVaultName );SecretName=$kvSecretName)"
                    $UpdateSettings[$appSettingKey] = $appSettingRef
                    Write-Verbose "Prepared KeyVault secret reference for Setting [$kvSecretName] using app setting [$appSettingKey] KeyVault ref [$appSettingRef]"
                }
            }
        }
    }

    foreach ($externalSettingKey in $serviceConfig.ExternalSettings.Keys) {
        Write-Verbose "Adding service external setting: $externalSettingKey"
        $setting = $serviceConfig.ExternalSettings[$externalSettingKey]
        $appSettingKey = "EXT_$externalSettingKey"
        switch ($setting.Type) {
            "Constant" {
                $UpdateSettings[$appSettingKey] = [string] $setting.Value
            }
            "Setting" {
                [string] $value = ($setting.Values  | Where-Object { $_.Purpose -eq $CdfConfig.Application.Env.purpose }).Value
                $UpdateSettings[$appSettingKey] = $value
            }
            "Secret" {
                $kvSecretName = "External-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier)"
                if ($SecretValue) {
                    $secret = Get-AzKeyVaultSecret `
                        -DefaultProfile $azCtx `
                        -VaultName $CdfConfig.Domain.ResourceNames.keyVaultName `
                        -Name $kvSecretName `
                        -ErrorAction SilentlyContinue

                    if ($null -eq $secret) {
                        Write-Warning " KeyVault secret not found in Domain KeyVault."
                        Write-Warning " Expecting secret by name [$kvSecretName] in KeyVault [$($CdfConfig.Domain.ResourceNames.keyVaultName)]"
                    }
                    else {
                        $UpdateSettings[$appSettingKey] = [System.Net.NetworkCredential]::new("", $secret.SecretValue).Password
                        Write-Verbose "Prepared KeyVault secret [$kvSecretName] for Setting [$appSettingKey]"
                    }
                }
                else {
                    $appSettingRef = "@Microsoft.KeyVault(VaultName=$($CdfConfig.Domain.ResourceNames.keyVaultName );SecretName=$kvSecretName)"
                    $UpdateSettings[$appSettingKey] = $appSettingRef
                    Write-Verbose "Prepared KeyVault secret reference for Setting [$kvSecretName] using app setting [$appSettingKey] KeyVault ref [$appSettingRef]"
                }
            }
        }
    }

    # CDF Env details
    $UpdateSettings["CDF_ENV_DEFINITION_ID"] = $CdfConfig.Application.Env.definitionId
    $UpdateSettings["CDF_ENV_NAME_ID"] = $CdfConfig.Application.Env.nameId
    $UpdateSettings["CDF_ENV_NAME"] = $CdfConfig.Application.Env.name
    $UpdateSettings["CDF_ENV_SHORT_NAME"] = $CdfConfig.Application.Env.shortName
    $UpdateSettings["CDF_ENV_DESCRIPTION"] = $CdfConfig.Application.Env.description
    $UpdateSettings["CDF_ENV_PURPOSE"] = $CdfConfig.Application.Env.purpose
    $UpdateSettings["CDF_ENV_QUALITY"] = $CdfConfig.Application.Env.quality
    $UpdateSettings["CDF_ENV_REGION_CODE"] = $CdfConfig.Application.Env.regionCode
    $UpdateSettings["CDF_ENV_REGION_NAME"] = $CdfConfig.Application.Env.regionName

    # Service Identity
    $UpdateSettings["CDF_SERVICE_NAME"] = $CdfConfig.Service.Config.serviceName
    $UpdateSettings["CDF_SERVICE_TYPE"] = $CdfConfig.Service.Config.serviceType
    $UpdateSettings["CDF_SERVICE_GROUP"] = $CdfConfig.Service.Config.serviceGroup
    $UpdateSettings["CDF_SERVICE_TEMPLATE"] = $CdfConfig.Service.Config.serviceTemplate
    $UpdateSettings["CDF_DOMAIN_NAME"] = $CdfConfig.Domain.Config.domainName

    # Build information
    $UpdateSettings["CDF_BUILD_TIME"] = (Get-Date -Format 'o' -AsUTC).ToString()
    $UpdateSettings["CDF_BUILD_COMMIT"] = ($env:GITHUB_SHA ?? $env:BUILD_SOURCEVERSION ?? $(git -C $TemplateDir rev-parse --short HEAD)).ToString()
    $UpdateSettings["CDF_BUILD_RUN"] = ($env:GITHUB_RUN_ID ?? $env:BUILD_BUILDNUMBER ?? "local").ToString()
    $UpdateSettings["CDF_BUILD_BRANCH"] = ($env:GITHUB_REF_NAME ?? $env:BUILD_SOURCEBRANCH ?? $(git -C $TemplateDir branch --show-current)).ToString()
    $UpdateSettings["CDF_BUILD_REPOSITORY"] = ($env:GITHUB_REPOSITORY ?? $env:BUILD_REPOSITORY_NAME ?? $(Split-Path -Leaf (git -C $TemplateDir remote get-url origin))).ToString()
    $UpdateSettings["CDF_BUILD_PIPELINE"] = ($env:GITHUB_WORKFLOW_REF ?? $env:BUILD_DEFINITIONNAME ?? "local").ToString()
    $UpdateSettings["CDF_BUILD_BRANCH"] = ($env:GITHUB_REF_NAME ?? $env:BUILD_SOURCEBRANCH ?? $(git -C $TemplateDir branch --show-current)).ToString()


    # Add default/override app settings if exists - override any generated app settings
    if (Test-Path "$OutputPath/app.settings.json") {
        Write-Host "Loading settings from app.settings.json"
        $defaultSettings = (`
                Get-Content "$OutputPath/app.settings.json" `
            | ConvertFrom-Json -AsHashtable `
            | Update-ConfigToken -NoWarning -Tokens ($CdfConfig | Get-TokenValues) `
        )
        foreach ($key in $defaultSettings.Keys) {
            Write-Verbose "Adding/overriding parameter appsetting for [$key] value [$($defaultSettings[$key])]"
            $UpdateSettings[$key] = [string] $defaultSettings[$key]
        }
    }


    Write-Output -InputObject $UpdateSettings
}