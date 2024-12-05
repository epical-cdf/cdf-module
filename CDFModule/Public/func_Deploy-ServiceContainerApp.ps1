﻿Function Deploy-ServiceContainerApp {
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

    # Copy service config
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

    #-------------------------------------------------------------
    # Set the CDF parameters
    #-------------------------------------------------------------
    $envSettings = $CdfConfig | Get-CdfServiceConfigSettings -InputPath $OutputPath

    foreach ($envKey in $envSettings.Keys) {
        $envValue = $envSettings[$envKey]

        $updateSettings = Set-EnvVarValue `
            -Settings $updateSettings `
            -VarName $envKey `
            -VarValue $envValue

        if ($envValue -match '@Microsoft.KeyVault.+SecretName=([External|Internal].+)[)|;].*') {
            $kvSecretName = $Matches[1]
            $envVar = $updateSettings | Where-Object { $_.Name -eq $envKey }
            $isInternal = $envValue -match 'Internal'
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
                $secretUrl = "https://$($CdfConfig.Domain.ResourceNames.keyVaultName).vault.azure.net/secrets/$($secret.Name)"
                $containerAppSecret = $app.Configuration.Secret | Where-Object { $_.Name -eq $secret.Name }

                if ($null -eq $containerAppSecret) {
                    $containerAppSecret = New-AzContainerAppSecretObject `
                        -Name $secret.Name.ToLower() `
                        -Identity $app.IdentityUserAssignedIdentity.Keys[0] `
                        -KeyVaultUrl $secretUrl
                    $app.Configuration.Secret += $containerAppSecret
                }
                else {
                    $containerAppSecret.KeyVaultUrl = $secretUrl
                }
            }

            if ($null -eq $envVar) {
                $updateSettings += New-AzContainerAppEnvironmentVarObject `
                    -Name "$($isInternal ? 'SVC_' : 'EXT_')_$externalSettingKey" `
                    -SecretRef $secret.Name.ToLower()
            }
            else {
                $envVar.SecretRef = $secret.Name.ToLower()
            }
        }
    }

    # Configure service API URLs for the App Service
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'SVC_API_BASEURL' -VarValue "https://$($app.Configuration.IngressFqdn)"
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'SVC_API_BASEURLS' -VarValue "https://$($app.Configuration.IngressFqdn)"

    #-------------------------------------------------------------
    # Set default container image and port config if missing
    #-------------------------------------------------------------
    $acrName = $cdfConfig.Application.ResourceNames.containerRegistryName
    $cdfEnvId = $cdfConfig.Application.Env.definitionId
    $cdfDomainName = $cdfConfig.Domain.Config.domainName
    $cdfServiceName = $CdfConfig.Service.Config.serviceName
    $imageTag = $CdfConfig.Service.Config.imageTag ?? 'latest'
    $imageName = "$acrName.azurecr.io/$cdfEnvId/$cdfDomainName/$cdfServiceName"

    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_IMAGE_NAME' -VarValue  $imageName
    $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'CDF_IMAGE_TAG' -VarValue  $imageTag

    $containerPort = $updateSettings['PORT']
    if ($null -eq $containerPort) {
        $containerPort = 8080
        $updateSettings = Set-EnvVarValue -Settings $updateSettings -VarName 'PORT' -VarValue "$containerPort"

        # # For publicly exposed container apps... ??
        # $app.Configuration = New-AzContainerAppConfigurationObject
        # $app.Configuration.IngressExposedPort = $containerPort
    }

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

    #--------------------------------------
    # Deploy container app implementation
    #--------------------------------------
    Update-AzContainerApp `
        -DefaultProfile $azCtx `
        -Name $CdfConfig.Service.ResourceNames.appServiceName `
        -ResourceGroupName $CdfConfig.Service.ResourceNames.appServiceResourceGroup `
        -Configuration $app.Configuration `
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

    Write-Host "Adding container app env setting: $VarName"
    $envVar = $Settings | Where-Object { $_.Name -eq $VarName }
    if ($null -eq $envVar) {
        $Settings += New-AzContainerAppEnvironmentVarObject -Name $VarName -Value $VarValue
    }
    else {
        $envVar.Value = $VarValue
    }
    return $Settings
}