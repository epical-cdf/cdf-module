Function Set-LogicAppParameters {
    <#
    .SYNOPSIS
    Update logic app parameters for domain and environment
    .DESCRIPTION
    Update logic app parameters for domain and environment ...
    .PARAMETER CdfConfig
    The CdfConfig object that holds the current scope configurations (Platform, Application and Domain)
    .PARAMETER AppSettings
    The service configuration from cdf-config.json.
    .PARAMETER Parameters
    Hashtable with contents of logic app standard parameters.json. See examples.

    .OUTPUTS
    Hashtable with updated app settings.

    .EXAMPLE

    $appsettings = @{
        "AzureWebJobsStorage"= "",
        "WORKFLOWS_SUBSCRIPTION_ID"= "",
        "PlatformKeyVaultUri"= "<KeyVaultName>.vault.azure.net",
        "DomainStorageAccountUri"= "<StorageAccountName>.vault.azure.net",
        "SVC_SETTING_02" = "VAL02"
        "EXT_SETTING_04" = "VAL04"
    }
    $parameters = @{
        "OtherParam": { ... },
        "SVC_SETTING_01": {
            type: "string"
            value = "VAL01"
        }
        "SVC_SETTING_02": {
            type: "string"
            value = "VAL02"
        }
        "EXT_SETTING_03": {
            type: "string"
            value = "VAL03"
        }
    }

    Set-CdfLogicAppParameters `
        -CdfConfig $CdfConfig `
        -AppSettings $appsettings `
        -Parameters $parameters

    $parameters (json):
    {
        "OtherParam": { ... },
        "Platform": { ... },
        "Application": { ... },
        "Domain": { ... },
        "Service": {
          "type": "object",
          "value" {
            ...
            "SETTING_02": "@appsetting('SVC_SETTING_02')"
          }
        },
        "External": {
         "type": "object",
          "value" {
            ...
            "SETTING_04": "@appsetting('EXT_SETTING_04')"
          }
        },
        "SVC_SETTING_01": {
            type: "string"
            value = "VAL01"
        },
        "SVC_SETTING_02": {
            type: "string"
            value = "@appsetting('SVC_SETTING_02')"
        },
        "EXT_SETTING_03": {
            type: "string"
            value = "VAL03"
        },
        "EXT_SETTING_04": {
            type: "string"
            value = "@appsetting('EXT_SETTING_04')"
        }
    }
    #>

    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [hashtable]$CdfConfig,
        [Parameter(Mandatory = $true)]
        [hashtable]$AppSettings,
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


    foreach ($AppSettingKey in $AppSettings.Keys) {
        $ParameterName = $AppSettingKey.Substring(4)
        if ($AppSettingKey.StartsWith('SVC_')) {
            $Parameters.Service.value[$ParameterName] = "@appsetting('$AppSettingKey')"
        }

        if ($AppSettingKey.StartsWith('EXT_')) {
            $Parameters.External.value[$ParameterName] = "@appsetting('$AppSettingKey')"
        }

        # For future use add app settings as individual parameters too
        $Parameters[$appSettingKey] = @{
            type  = 'string'
            value = "@appsetting('$appSettingKey')"
        }
    }

    return $AppSettings
}