Function Deploy-ServiceContainerAppService {
    <#
        .SYNOPSIS
        Deploys a Container App Service implementation and condfiguration

        .SYNOPSIS
        Deploys a Container service to an App Service implementation and configuration

        .DESCRIPTION
        The cmdlet deploys a Container service to an App Service implementation with configuration of app settings, parameters and connections.

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

    if ($null -eq $CdfConfig.Service -or $false -eq $CdfConfig.Service.IsDeployed) {
        Write-Error "Service configuration is not deployed. Please deploy the service infrastructure first."
        return
    }
    if (-not $CdfConfig.Config.serviceTemplate -match 'container-.*') {
        Write-Error "Service mismatch - does not match a Container AppService implementation."
        return
    }

    ## Adjust these if template changes regarding placement of logicapp for the service
    $appServiceRG = $CdfConfig.Service.ResourceNames.appServiceResourceGroup ?? $CdfConfig.Service.ResourceNames.serviceResourceGroup
    $appServiceName = $CdfConfig.Service.ResourceNames.appServiceName ?? $CdfConfig.Service.ResourceNames.serviceResourceName


    Write-Host "appServiceRG: $appServiceRG"
    Write-Host "appServiceName: $appServiceName"

    if ($null -eq $appServiceRG -or $null -eq $appServiceName) {
        Write-Error "Service configuration is missing AppService resource group or name. Please check the service configuration."
        return
    }

    Write-Host "Preparing Container App Service implementation deployment."

    $azCtx = Get-AzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId

    # Copy service config
    $containerFiles = @(
        'cdf-config.json',
        'cdf-secrets.json',
        'app.settings.json'
    )
    Copy-Item -Force -Recurse -Include $containerFiles -Path $InputPath/* -Destination $OutputPath

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

    $updateSettings = $CdfConfig | Get-ServiceConfigSettings `
        -UpdateSettings $updateSettings `
        -InputPath $InputPath `
        -ErrorAction:Stop

    # Configure service API URLs
    $updateSettings["SVC_API_BASEURL"] = "https://$($app.HostNames[0])"
    $BaseUrls = @()
    foreach ($hostName in $app.HostNames) { $BaseUrls += "https://$hostName" }
    $updateSettings["SVC_API_BASEURLS"] = [string]($BaseUrls | Join-String -Separator ',')

    $acrName = $cdfConfig.Application.ResourceNames.containerRegistryName
    $cdfEnvId = $cdfConfig.Application.Env.definitionId
    $cdfDomainName = $cdfConfig.Domain.Config.domainName
    $cdfServiceName = $CdfConfig.Service.Config.serviceName
    $imageTag = $CdfConfig.Service.Config.imageTag ?? 'latest'
    $imageName = "$acrName.azurecr.io/$cdfEnvId/$cdfDomainName/$cdfServiceName"

    $updateSettings["CDF_IMAGE_NAME"] = $imageName
    $updateSettings["CDF_IMAGE_TAG"] = $imageTag

    #--------------------------------------
    # Deploy app configuration
    #--------------------------------------
    Set-AzWebApp `
        -Name $appServiceName `
        -ResourceGroupName $appServiceRG `
        -AppSettings $updateSettings `
        -WarningAction:SilentlyContinue | Out-Null

    $webConfig = Get-AzResource  -DefaultProfile $azCtx -Id "$($app.Id)/config" -ExpandProperties
    $webConfig.Properties.linuxFxVersion = "DOCKER|${imageName}:${imageTag}"
    $webConfig.Properties.numberOfWorkers = $CdfConfig.Service.Config.numberOfWorkers ?? 1
    $webConfig | Set-AzResource -DefaultProfile $azCtx -Force | Out-Null

    Restart-AzWebApp `
        -SoftRestart `
        -Name $appServiceName `
        -ResourceGroupName $appServiceRG `
        -WarningAction:SilentlyContinue | Out-Null

    Write-Host "Container App Service deployment done."
}
