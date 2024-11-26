Function Deploy-ServiceContainerApp {
    <#
        .SYNOPSIS
        Deploys a Container service to an App Service implementation and configuration

        .DESCRIPTION
        The cmdlet deploys a Container service to an App Service implementation with configuration of app settings, parameters and connections.

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
        PS> Deploy-ServiceContainerApp `
            -Platform $CdfConfig.Platform `
            -Application $CdfConfig.Application `
            -Domain $CdfConfig.Domain `
            -Service $CdfConfig.Service `
            -InputPath "./cs-<name>" `
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
        [string] $InputPath = ".",
        [Parameter(Mandatory = $false)]
        [string] $OutputPath = "../tmp/$($CdfConfig.Service.Config.serviceName)",
        [Parameter(Mandatory = $false)]
        [string] $TemplateDir = "."
    )

    Write-Host "Preparing Container App Service implementation deployment."

    $azCtx = Get-AzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId

    # Copy service implementation
    $containerFiles = @(
        'cdf-config.json',
        'cdf-secrets.json',
        'app.settings.json'
    )
    Copy-Item -Force -Recurse -Include $containerFiles -Path $InputPath/* -Destination $OutputPath

    ## Adjust these if template changes regarding placement of appService for the service
    $containerAppRG = $CdfConfig.Service.ResourceNames.appServiceResourceGroup
    $containerAppName = $CdfConfig.Service.ResourceNames.appServiceName

    Write-Host "containerAppRG: $containerAppRG"
    Write-Host "containerAppName: $containerAppName"

    #--------------------------------------
    # Preparing servicesettings for target env
    #--------------------------------------
    Write-Host "Preparing service settings."

    # Get container app env
    $app = Get-AzContainerApp `
        -DefaultProfile $azCtx `
        -Name $CdfConfig.Service.ResourceNames.appServiceName `
        -ResourceGroupName $CdfConfig.Service.ResourceNames.appServiceResourceGroup `
        -WarningAction:SilentlyContinue

    if (  $app.TemplateContainer.Count -gt 0) {
        $updateSettings = $app.TemplateContainer[0].Env
    }
    else {
        $updateSettings = @( New-AzContainerAppEnvironmentVarObject -Name 'CDF_SERVICE_NAME' -Value $CdfConfig.Service.Config.serviceName)
    }

    # Substitute Tokens in the cdf-config json file
    $tokenValues = $CdfConfig | Get-TokenValues
    Update-ConfigFileTokens `
        -InputFile "$OutputPath/cdf-config.json" `
        -OutputFile "$OutputPath/cdf-config.gen.json" `
        -Tokens $tokenValues `
        -StartTokenPattern '{{' `
        -EndTokenPattern '}}' `
        -NoWarning `
        -WarningAction:SilentlyContinue

    # Get service config from cdf-config.json with token substitutions
    $serviceConfig = Get-Content -Path "$OutputPath/cdf-config.gen.json" | ConvertFrom-Json -AsHashtable
    
    #-------------------------------------------------------------
    # Set the CDF parameters
    #-------------------------------------------------------------
    
    # CDF Env details
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_ENV_DEFINITION_ID' -VarValue $CdfConfig.Application.Env.definitionId
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_ENV_NAME_ID' -VarValue  $CdfConfig.Application.Env.nameId
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_ENV_NAME' -VarValue $CdfConfig.Application.Env.name
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_ENV_SHORT_NAME' -VarValue $CdfConfig.Application.Env.shortName
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_ENV_DESCRIPTION' -VarValue $CdfConfig.Application.Env.description
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_ENV_PURPOSE' -VarValue $CdfConfig.Application.Env.purpose
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_ENV_QUALITY' -VarValue $CdfConfig.Application.Env.quality
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_ENV_REGION_CODE' -VarValue $CdfConfig.Application.Env.regionCode
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_ENV_REGION_NAME' -VarValue $CdfConfig.Application.Env.regionName
        
    # Service Identity
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_SERVICE_NAME' -VarValue $CdfConfig.Service.Config.serviceName
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_SERVICE_TYPE' -VarValue $CdfConfig.Service.Config.serviceType
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_SERVICE_GROUP' -VarValue $CdfConfig.Service.Config.serviceGroup
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_SERVICE_TEMPLATE' -VarValue $CdfConfig.Service.Config.serviceTemplate
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_DOMAIN_NAME' -VarValue $CdfConfig.Domain.Config.domainName
    
    # Build information
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_BUILD_TIME' -VarValue (Get-Date -Format 'o' -AsUTC)
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_BUILD_COMMIT' -VarValue ($env:GITHUB_SHA ?? $env:BUILD_SOURCEVERSION ?? $(git -C $TemplateDir rev-parse --short HEAD))
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_BUILD_RUN' -VarValue ($env:GITHUB_RUN_ID ?? $env:BUILD_BUILDNUMBER ?? "local")
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_BUILD_BRANCH' -VarValue ($env:GITHUB_REF_NAME ?? $env:BUILD_SOURCEBRANCH ?? $(git -C $TemplateDir branch --show-current))
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_BUILD_REPOSITORY' -VarValue ($env:GITHUB_REPOSITORY ?? $env:BUILD_REPOSITORY_NAME ?? $(Split-Path -Leaf (git -C $TemplateDir remote get-url origin)))
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_BUILD_PIPELINE' -VarValue ($env:GITHUB_WORKFLOW_REF ?? $env:BUILD_DEFINITIONNAME ?? "local")
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_BUILD_BRANCH' -VarValue ($env:GITHUB_REF_NAME ?? $env:BUILD_SOURCEBRANCH ?? $(git -C $TemplateDir branch --show-current))

    #-------------------------------------------------------------
    # Set the CDF service settings
    #-------------------------------------------------------------
    
    # Service internal settings
    foreach ($serviceSettingKey in $serviceConfig.ServiceSettings.Keys) {
        $setting = $serviceConfig.ServiceSettings[$serviceSettingKey]
        switch ($setting.Type) {
            "Constant" {
                $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName "SVC_$serviceSettingKey"-VarValue ($setting.Value | Out-String -NoNewline)
            }
            "Setting" {
                $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName "SVC_$serviceSettingKey"-VarValue ($svcEnvSetting.Value | Out-String -NoNewline)
            }
            "Secret" {
                Write-Host "Adding service internal secret: $serviceSettingKey"
                $secret = Get-AzKeyVaultSecret `
                    -DefaultProfile $azCtx `
                    -VaultName $CdfConfig.Domain.ResourceNames.keyVaultName `
                    -Name "svc-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier)" `
                    -ErrorAction SilentlyContinue

                if ($null -eq $secret) {
                    Write-Warning " KeyVault secret for Identifier [$($setting.Identifier)] not found in KeyVault"
                    Write-Warning " Expecting secret name [svc-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier)] in Domain KeyVault"
                }
                else {

                    $envVar = $updateSettings | Where-Object { $_.Name -eq "SVC_$serviceSettingKey" }
                    $secretRef = "@Microsoft.KeyVault(VaultName=$($CdfConfig.Domain.ResourceNames.keyVaultName );SecretName=svc-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier))"
                    if ($null -eq $envVar) {
                        $app.Configuration.Secret.Add(@{
                                name        = $serviceSettingKey
                                keyVaultUrl = $secretRef
                                identity    = $app.IdentityUserAssignedIdentity.Keys[0]
                            })

                        $updateSettings += New-AzContainerAppEnvironmentVarObject `
                            -Name "SVC_$serviceSettingKey" `
                            -SecretRef $serviceSettingKey
                    }
                    else {
                        $secretRef = $envVar.SecretRef
                        $secretConfig = $app.Configuration.Secret | Where-Object { $_.Name -eq $secretRef }
                        $secretConfig.KeyVaultUrl = $secretRef
                    }
                    Write-Verbose "Prepared KeyVault secret reference for Setting [$($setting.Identifier)] using app setting [$appSettingKey] KeyVault ref [$appSettingRef]"
                }
            }
        }
    }

    # Service external settings
    foreach ($externalSettingKey in $serviceConfig.ExternalSettings.Keys) {
        $setting = $serviceConfig.ExternalSettings[$externalSettingKey]
        switch ($setting.Type) {
            "Constant" {
                $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName "EXT_$externalSettingKey"-VarValue ($setting.Value | Out-String -NoNewline)
            }
            "Setting" {
                $svcEnvSetting = $setting.Values | Where-Object { $_.Purpose -eq $CdfConfig.Application.Env.purpose }
                $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName "EXT_$externalSettingKey"-VarValue ($svcEnvSetting.Value | Out-String -NoNewline)
            }
            "Secret" {
                Write-Host "Adding service external secret: $externalSettingKey"
                $secret = Get-AzKeyVaultSecret `
                    -DefaultProfile $azCtx `
                    -VaultName $CdfConfig.Domain.ResourceNames.keyVaultName `
                    -Name "svc-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier)" `
                    -ErrorAction SilentlyContinue

                if ($null -eq $secret) {
                    Write-Warning " KeyVault secret for Identifier [$($setting.Identifier)] not found in KeyVault"
                    Write-Warning " Expecting secret name [svc-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier)] in Domain KeyVault"
                }
                else {
                    $envVar = $updateSettings | Where-Object { $_.Name -eq "EXT_$externalSettingKey" }
                    $secretRef = "@Microsoft.KeyVault(VaultName=$($CdfConfig.Domain.ResourceNames.keyVaultName );SecretName=svc-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier))"
                    if ($null -eq $envVar) {
                        $updateSettings += New-AzContainerAppEnvironmentVarObject `
                            -Name "EXT_$externalSettingKey" `
                            -SecretRef $secretRef
                    }
                    else {
                        $envVar.SecretRef = $secretRef
                    }
                    Write-Verbose "Prepared KeyVault secret reference for Setting [$($setting.Identifier)] using app setting [$appSettingKey] KeyVault ref [$appSettingRef]"
                }
            }
        }
    }

    # Configure service API URLs for the App Service
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'SVC_API_BASEURL' -VarValue "https://$($app.Configuration.IngressFqdn)"
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'SVC_API_BASEURLS' -VarValue "https://$($app.Configuration.IngressFqdn)"
    
    # Add custom env settings:
    # Substitute Tokens in the app.settings file
    $tokenValues = $CdfConfig | Get-TokenValues
    Update-ConfigFileTokens `
        -InputFile "$OutputPath/app.settings.json" `
        -OutputFile "$OutputPath/app.settings.gen.json" `
        -Tokens $tokenValues `
        -StartTokenPattern '{{' `
        -EndTokenPattern '}}' `
        -NoWarning `
        -WarningAction:SilentlyContinue


    $appSettings = (Get-Content "$OutputPath/app.settings.gen.json" | ConvertFrom-Json -AsHashtable)

    foreach ($appSettingKey in $appSettings.Keys) {
        $appSetting = $appSettings[$appSettingKey]
        if ($appSetting.Type -eq "System.Management.Automation.OrderedHashtable") {
            $appSetting = $appSettings[$appSettingKey] | ConvertTo-Json -Depth 20
        }
        $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName $appSettingKey -VarValue $appSetting    
    }
    #-------------------------------------------------------------
    # Set container image config
    #-------------------------------------------------------------
    
    $acrName = $cdfConfig.Application.ResourceNames.containerRegistryName
    $cdfEnvId = $cdfConfig.Application.Env.definitionId
    $cdfDomainName = $cdfConfig.Domain.Config.domainName
    $cdfServiceName = $CdfConfig.Service.Config.serviceName
    $imageName = "$acrName.azurecr.io/$cdfEnvId/$cdfDomainName/$cdfServiceName"
    $imageTag = 'v1'

    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_IMAGE_NAME' -VarValue $imageName
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_IMAGE_TAG' -VarValue $imageTag

    if ($CdfConfig.Service.Config.serviceType -eq 'javascript' ) {
        $containerPort = 8080
    }
    else {
        $containerPort = 8080
    }
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'PORT' -VarValue "$containerPort"

    # $app.Configuration = New-AzContainerAppConfigurationObject
    $app.Configuration.IngressExposedPort = $containerPort
  
    $containerProbe = New-AzContainerAppProbeObject `
        -Type Liveness `
        -HttpGetPort $containerPort `
        -HttpGetPath '/healthz/Liveness' `
        -HttpGetScheme HTTP `
        -InitialDelaySecond 30 `
        -PeriodSecond 15 `
        -FailureThreshold 3 `
        -TimeoutSecond 1

    $container = New-AzContainerAppTemplateObject `
        -Name $CdfConfig.Service.Config.serviceName `
        -Image "${imageName}:${imageTag}" `
        -Env $updateSettings `
        -Probe $containerProbe

    $app.TemplateContainer[0] = $container

    # $app.TemplateContainer[0].Env = $updateSettings

    #--------------------------------------
    # Deploy container app implementation
    #--------------------------------------
    Update-AzContainerApp `
        -DefaultProfile $azCtx `
        -Name $CdfConfig.Service.ResourceNames.appServiceName `
        -ResourceGroupName $CdfConfig.Service.ResourceNames.appServiceResourceGroup `
        -TemplateContainer  $app.TemplateContainer[0] `
        -WarningAction:SilentlyContinue

    Write-Host "Container App Service implementation deployment done."
}

Function Set-EnvVarValue {

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, Position = 0)]
        [array] $Settings,
        [Parameter(Mandatory = $true, Position = 1)]
        [string] $VarName,
        [Parameter(Mandatory = $true, Position = 2)]
        [string] $VarValue
    )

    Write-Host "Adding service env setting: $VarName"
    $envVar = $Settings | Where-Object { $_.Name -eq $VarName }
    if ($null -eq $envVar) {
        $Settings += New-AzContainerAppEnvironmentVarObject -Name $VarName -Value $VarValue
    }
    else {
        $envVar.Value = $VarValue
    }
    return $Settings
}
