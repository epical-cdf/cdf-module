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
        
        .PARAMETER InputPath
        Path to the Function implementation including cdf-config.json.
        Optional

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
        [Parameter(Mandatory = $true)]
        [string] $InputPath = ".",
        [Parameter(Mandatory = $false)]
        [string] $TemplateDir = $env:CDF_INFRA_TEMPLATES_PATH ?? "."       
            
    )
    
    if($null -eq $CdfConfig) {
        if($Deployed){
            $CdfConfig = Get-CdfConfig -Deployed
        }
        else {
            $CdfConfig = Get-CdfConfig
        }
        Write-Host (ConvertTo-Json $CdfConfig.Domain)
    }
    $cdfConfigFile = Join-Path -Path $InputPath  -ChildPath 'cdf-config.json'
    $serviceConfig = Get-Content -Raw $cdfConfigFile | ConvertFrom-Json -AsHashtable
    if ($null -eq $UpdateSettings) {
        $UpdateSettings = ConvertFrom-Json -InputObject "{}" -AsHashtable
    }
    foreach ($serviceSettingKey in $serviceConfig.ServiceSettings.Keys) {
        Write-Host "Adding service internal setting: $serviceSettingKey"
        $setting = $serviceConfig.ServiceSettings[$serviceSettingKey]
        switch ($setting.Type) {
            "Constant" {
                $UpdateSettings["SVC_$serviceSettingKey"] = ($setting.Value | Out-String -NoNewline)
            }
            "Setting" {
                $UpdateSettings["SVC_$serviceSettingKey"] = ($setting.Values[0].Value | Out-String -NoNewline)
    
            }
            "Secret" {
                $appSettingRef = "@Microsoft.KeyVault(VaultName=$($CdfConfig.Domain.ResourceNames.keyVaultName );SecretName=svc-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier))"
                $appSettingKey = "SVC_$serviceSettingKey"
                $UpdateSettings[$appSettingKey] = $appSettingRef
                Write-Verbose "Prepared KeyVault secret reference for Setting [$($setting.Identifier)] using app setting [$appSettingKey] KeyVault ref [$appSettingRef]"
            }
        }
    }

    foreach ($externalSettingKey in $serviceConfig.ExternalSettings.Keys) {
        Write-Host "Adding service external setting: $externalSettingKey"
        $setting = $serviceConfig.ExternalSettings[$externalSettingKey]
        switch ($setting.Type) {
            "Constant" {
                $UpdateSettings["EXT_$externalSettingKey"] = ($setting.Value | Out-String -NoNewline)
            }
            "Setting" {
                [string] $value = ($setting.Values  | Where-Object { $_.Purpose -eq $CdfConfig.Application.Env.purpose }).Value
                $UpdateSettings["EXT_$externalSettingKey"] = $value
    
            }
            "Secret" {
                $appSettingRef = "@Microsoft.KeyVault(VaultName=$($CdfConfig.Domain.ResourceNames.keyVaultName );SecretName=ext-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier))"
                $appSettingKey = "EXT_$serviceSettingKey"
                $UpdateSettings[$appSettingKey] = $appSettingRef
                Write-Verbose "Prepared KeyVault secret reference for Setting [$($setting.Identifier)] using app setting [$appSettingKey] KeyVault ref [$appSettingRef]"
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
    $UpdateSettings["CDF_BUILD_COMMIT"] = $env:GITHUB_SHA ?? $env:BUILD_SOURCEVERSION ?? $(git -C $TemplateDir rev-parse --short HEAD)
    $UpdateSettings["CDF_BUILD_RUN"] = $env:GITHUB_RUN_ID ?? $env:BUILD_BUILDNUMBER ?? "local"
    $UpdateSettings["CDF_BUILD_BRANCH"] = $env:GITHUB_REF_NAME ?? $env:BUILD_SOURCEBRANCH ?? $(git -C $TemplateDir branch --show-current)
    $UpdateSettings["CDF_BUILD_REPOSITORY"] = $env:GITHUB_REPOSITORY ?? $env:BUILD_REPOSITORY_NAME ?? $(Split-Path -Leaf (git -C $TemplateDir remote get-url origin))
    $UpdateSettings["CDF_BUILD_PIPELINE"] = $env:GITHUB_WORKFLOW_REF ?? $env:BUILD_DEFINITIONNAME ?? "local"
    $UpdateSettings["CDF_BUILD_BRANCH"] = $env:GITHUB_REF_NAME ?? $env:BUILD_SOURCEBRANCH ?? $(git -C $TemplateDir branch --show-current)

}