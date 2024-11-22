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

    Copy-Item -Force -Recurse -Path $InputPath/* -Destination $OutputPath    

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

    Get-ServiceConfigSettings -CdfConfig $CdfConfig -UpdateSettings $updateSettings -InputPath $InputPath -Deployed
    # Configure service API URLs
    $updateSettings["SERVICE_API_BASEURL"] = "https://$($app.HostNames[0])"
    $BaseUrls = @()
    foreach ($hostName in $app.HostNames) { $BaseUrls += "https://$hostName" }
    $updateSettings["SERVICE_API_BASEURLS"] = $BaseUrls | Join-String -Separator ','

    # Run from package. Not to be used with .net functions app
    #$updateSettings["WEBSITE_RUN_FROM_PACKAGE"] = "0"
    #$updateSettings["SCM_DO_BUILD_DURING_DEPLOYMENT"] = "true"
    #$updateSettings["ENABLE_ORYX_BUILD"] = "true"


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
