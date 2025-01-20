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


    if ($null -eq $CdfConfig.Service -or $false -eq $CdfConfig.Service.IsDeployed) {
        Write-Error "Service configuration is not deployed. Please deploy the service infrastructure first."
        return
    }
    if (-not $CdfConfig.Config.serviceTemplate -match 'functionapp.*') {
        Write-Error "Service mismatch - does not match a FunctionApp implementation."
        return
    }

    Write-Host "Preparing Function App Service implementation deployment."

    $azCtx = Get-AzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId

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

    Copy-Item -Force -Recurse -Path $InputPath/* -Destination $OutputPath

    ## Adjust these if template changes regarding placement of appService runtime for the service
    $appServiceRG = $CdfConfig.Service.ResourceNames.appServiceResourceGroup ?? $CdfConfig.Service.ResourceNames.serviceResourceGroup
    $appServiceName = $CdfConfig.Service.ResourceNames.appServiceName ?? $CdfConfig.Service.ResourceNames.serviceResourceName

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

    $updateSettings = $CdfConfig | Get-ServiceConfigSettings `
        -UpdateSettings $updateSettings `
        -InputPath $InputPath `
        -ErrorAction:Stop

    # Configure service API URLs
    $updateSettings["SVC_API_BASEURL"] = "https://$($app.HostNames[0])"
    $BaseUrls = @()
    foreach ($hostName in $app.HostNames) { $BaseUrls += "https://$hostName" }
    $updateSettings["SVC_API_BASEURLS"] = $BaseUrls | Join-String -Separator ','

    # Run from package. Not to be used with .net functions app
    #$updateSettings["WEBSITE_RUN_FROM_PACKAGE"] = "0"
    #$updateSettings["SCM_DO_BUILD_DURING_DEPLOYMENT"] = "true"
    #$updateSettings["ENABLE_ORYX_BUILD"] = "true"

    #-------------------------------------------------------------
    # Update the app settings
    #-------------------------------------------------------------
    $updateSettings | ConvertTo-Json -Depth 10 | Set-Content -Path "$OutputPath/app.settings.gen.json"
    Remove-Item -Path "$OutputPath/local.settings.json" -ErrorAction SilentlyContinue

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
        -ZipPath "$OutputPath/deployment-package-$($CdfConfig.Service.Config.serviceName).zip" `
        -IncludeHidden

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
