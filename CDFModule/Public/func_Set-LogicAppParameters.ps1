Function Set-LogicAppParameters {
    <#
    .SYNOPSIS
    Update logic app parameters for domain and environment
    .DESCRIPTION
    Update logic app parameters for domain and environment ...
    .PARAMETER CdfConfig
    The CdfConfig object that holds the current scope configurations (Platform, Application and Domain)
    .PARAMETER ServiceConfig
    The service configuration from cdf-config.json.
    .PARAMETER Parameters
    Hashtable with contents of logic app standard parameters.json. See examples.

    .OUTPUTS
    Hashtable with required app settings.

    .EXAMPLE
    parameters.json:
    {

    }

    $parameters = Get-Content "parameters.json" | ConvertFrom-Json -AsHashtable
    $serviceConfig = Get-Content "cdf-config.json" | ConvertFrom-Json -AsHashtable
    Set-CdfLogicAppParameters `
        -CdfConfig $CdfConfig `
        -ServiceConfig $serviceConfig `
        -Parameters $arameters

    $parameters | ConvertTo-Json -Depth 10 | Set-Content -Path "parameters.json"

    appsettings.json (result):
    {
        "AzureWebJobsStorage": "",
        "WORKFLOWS_SUBSCRIPTION_ID": "",
        "PlatformKeyVaultUri": "<KeyVaultName>.vault.azure.net"
        "DomainStorageAccountUri": "<StorageAccountName>.vault.azure.net"
    }
    #>

    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [hashtable]$CdfConfig,
        [Parameter(Mandatory = $true)]
        [hashtable]$ServiceConfig,
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters
    )


    #############################################################
    # Update service parameter values
    #############################################################
    Write-Verbose "Setting service CDF parameters"

    $platformId = $CdfConfig.Platform.Config.platformId
    $platformInstance = $CdfConfig.Platform.Config.instanceId
    $appId = $CdfConfig.Application.Config.applicationId
    $appInstance = $CdfConfig.Application.Config.instanceId

    # Set framework parameters
    $Parameters.Environment.value = $CdfConfig.Application.Env
    $Parameters.Platform.value.Key = "$platformId$platformInstance"
    $Parameters.Platform.value.TemplateName = $CdfConfig.Platform.Config.templateName
    $Parameters.Platform.value.TemplateVersion = $CdfConfig.Platform.Config.templateVersion
    $Parameters.Application.value.Key = "$appId$appInstance"
    $Parameters.Application.value.TemplateName = $CdfConfig.Application.Config.templateName
    $Parameters.Application.value.TemplateVersion = $CdfConfig.Application.Config.templateVersion
    $Parameters.Domain.value.Name = $CdfConfig.Domain.Config.domainName
    $Parameters.Service.value.Name = $CdfConfig.Service.Config.serviceName
    $Parameters.Service.value.Group = $CdfConfig.Service.Config.serviceGroup
    $Parameters.Service.value.Type = $CdfConfig.Service.Config.serviceType
    $Parameters.Service.value.Template = $CdfConfig.Service.Config.serviceTemplate
    $Parameters.BuildContext.value.BuildTimestamp = Get-Date -Format o
    $Parameters.BuildContext.value.BuildRun = $CdfConfig.Service.Tags.BuildRun
    $Parameters.BuildContext.value.BuildRepo = $CdfConfig.Service.Tags.BuildRepo
    $Parameters.BuildContext.value.BuildBranch = $CdfConfig.Service.Tags.BuildBranch
    $Parameters.BuildContext.value.BuildCommit = $CdfConfig.Service.Tags.BuildCommit
    $Parameters.BuildContext.value.TemplateEnv = $CdfConfig.Service.Tags.TemplateEnv
    $Parameters.BuildContext.value.TemplateName = $CdfConfig.Service.Tags.TemplateName
    $Parameters.BuildContext.value.TemplateVersion = $CdfConfig.Service.Tags.TemplateVersion
    $Parameters.BuildContext.value.TemplateInstance = $CdfConfig.Service.Tags.TemplateInstance

    $azCtx = Get-AzureContext -SubscriptionId $CdfConfig.Platform.Env["subscriptionId"]

    $appsettings = @{}

    # Service internal settings
    foreach ($serviceSettingKey in $ServiceConfig.ServiceSettings.Keys) {
        Write-Verbose "Adding service internal setting: $serviceSettingKey"
        $setting = $ServiceConfig.ServiceSettings[$serviceSettingKey]
        switch ($setting.Type) {
            "Constant" {
                if ($setting.IsAppSetting) {
                    $appSettingKey = "Internal_$serviceSettingKey"
                    $appsettings[$appSettingKey] = $setting.Values[0].Value
                    $Parameters.Service.value[$serviceSettingKey] = "@appsetting('$appSettingKey')"
                }
                else {
                    $Parameters.Service.value[$serviceSettingKey] = $setting.Value
                }

            }
            "Setting" {
                if ($setting.IsAppSetting) {
                    $appSettingKey = "Internal_$serviceSettingKey"
                    $appsettings[$appSettingKey] = $setting.Values[0].Value
                    $Parameters.Service.value[$serviceSettingKey] = "@appsetting('$appSettingKey')"
                }
                else {
                    $Parameters.Service.value[$serviceSettingKey] = $setting.Values[0].Value
                }

            }
            "Secret" {
                $secretName = "Internal-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier)"
                $keyVault = Get-AzKeyVault `
                    -DefaultProfile $azCtx `
                    -VaultName $CdfConfig.Domain.ResourceNames.keyVaultName `
                    -ErrorAction SilentlyContinue
                $appSettingRef = "@Microsoft.KeyVault(SecretUri=$($keyVault.VaultUri)secrets/$secretName)"
                $appSettingKey = "Internal_$serviceSettingKey"
                $appsettings[$appSettingKey] = $appSettingRef
                $Parameters.Service.value[$serviceSettingKey] = "@appsetting('$appSettingKey')"
                Write-Verbose "Prepared KeyVault secret reference for Setting [$serviceSettingKey] using app setting [$appSettingKey] KeyVault ref [$appSettingRef]"
            }
        }
    }

    # Service external settings
    foreach ($externalSettingKey in $ServiceConfig.ExternalSettings.Keys) {
        Write-Verbose "Adding service external setting: $externalSettingKey"
        $setting = $ServiceConfig.ExternalSettings[$externalSettingKey]
        switch ($setting.Type) {
            "Constant" {
                if ($setting.IsAppSetting) {
                    $appSettingKey = "EXT_$externalSettingKey"
                    $appsettings[$appSettingKey] = $setting.Values[0].Value
                    $Parameters.External.value[$externalSettingKey] = "@appsetting('$appSettingKey')"
                }
                else {
                    $Parameters.External.value[$externalSettingKey] = $setting.Value
                }
            }
            "Setting" {
                [string] $value = ($setting.Values  | Where-Object { $_.Purpose -eq $CdfConfig.Application.Env.purpose }).Value

                if ($setting.IsAppSetting) {
                    $appSettingKey = "EXT_$externalSettingKey"
                    $appsettings[$appSettingKey] = $value
                    $Parameters.External.value[$externalSettingKey] = "@appsetting('$appSettingKey')"
                }
                else {
                    $Parameters.External.value[$externalSettingKey] = $value
                }
            }
            "Secret" {
                $secretName = "External-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier)"
                $keyVault = Get-AzKeyVault `
                    -DefaultProfile $azCtx `
                    -VaultName $CdfConfig.Domain.ResourceNames.keyVaultName `
                    -ErrorAction SilentlyContinue
                $appSettingRef = "@Microsoft.KeyVault(SecretUri=$($keyVault.VaultUri)secrets/$secretName)"
                $appSettingKey = "EXT_$externalSettingKey"
                $appsettings[$appSettingKey] = $appSettingRef
                $Parameters.External.value[$externalSettingKey] = "@appsetting('$appSettingKey')"
                Write-Verbose "Prepared KeyVault secret reference for Setting [$externalSettingKey] using app setting [$appSettingKey] KeyVault ref [$appSettingRef]"
            }
        }
    }
    return $appsettings
}