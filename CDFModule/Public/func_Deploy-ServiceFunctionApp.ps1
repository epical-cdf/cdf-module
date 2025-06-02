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
    if (-not $CdfConfig.Service.Config.serviceTemplate -match 'functionapp.*') {
        Write-Error "Service mismatch - does not match a FunctionApp implementation."
        return
    }

    Write-Host "Preparing Function App Service implementation deployment."

    $azCtx = Get-AzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId

    ## Adjust these if template changes regarding placement of appService runtime for the service
    $appServiceRG = $CdfConfig.Service.ResourceNames.appServiceResourceGroup ?? $CdfConfig.Service.ResourceNames.functionAppResourceGroup ?? $CdfConfig.Service.ResourceNames.serviceResourceGroup
    $appServiceName = $CdfConfig.Service.ResourceNames.appServiceName ?? $CdfConfig.Service.ResourceNames.functionAppName ?? $CdfConfig.Service.ResourceNames.serviceResourceName

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
    $updateSettings["SVC_API_BASEURLS"] = [string] ($BaseUrls | Join-String -Separator ',')

    #-------------------------------------------------------------
    # Update the app settings
    #-------------------------------------------------------------
    
    Set-AzWebApp `
        -Name $appServiceName `
        -ResourceGroupName $appServiceRG `
        -AppSettings $updateSettings `
        -WarningAction:SilentlyContinue | Out-Null
    
    #--------------------------------------
    # Deploy function app implementation
    #--------------------------------------
    Write-Host "Deploying functions."

    # Copy service/logicapp implementation

    [string[]]$exclude = @(
        '.vscode',
        '.gitignore',
        '.funcignore',
        '.dockerignore',
        'Dockerfile',
        'app.settings.*',
        'local.settings.json',
        'cdf-config.json',
        'cdf-secrets.json'
    )

    if ($CdfConfig.Service.Config.serviceType -match '.*dotnet.*') {
        if ($false -eq (Test-Path -Path "$InputPath/publish" -PathType Container)) {
            Write-Verbose "Missing functionapp 'publish' folder. Running default dotnet publish."
            dotnet publish --verbosity q -c "Debug" --output "$InputPath/publish"
        }

        Copy-Item -Force -Recurse -Path $InputPath/cdf-*.json -Destination $OutputPath
        if (Test-Path app.settings.json) {
            Copy-Item -Force -Path $InputPath/app.settings.json -Destination $OutputPath
        }
        $OutputPath = Resolve-Path $OutputPath
        Push-Location -Path $InputPath/publish
        New-Zip `
            -Exclude $exclude `
            -ZipPath "$OutputPath/deployment-package-$($CdfConfig.Service.Config.serviceName).zip" `
            -IncludeHidden
        Pop-Location
    }
    else {
        if ($false -eq (Test-Path -Path './dist' -PathType Container)) {
            Write-Verbose "Missing functionapp 'dist' folder. Running default npm build."
            npm install
            npm run build
        }

        Copy-Item -Force -Recurse -Path $InputPath/cdf-*.json -Destination $OutputPath
        if (Test-Path app.settings.json) {
            Copy-Item -Force -Path $InputPath/app.settings.json -Destination $OutputPath
        }
        $OutputPath = Resolve-Path $OutputPath
        $exclude += @(
            'src',
            'package-lock.json',
            'tsconfig*.json'
        )
        New-Zip `
            -Exclude $exclude `
            -ZipPath "$OutputPath/deployment-package-$($CdfConfig.Service.Config.serviceName).zip" `
            -IncludeHidden
    }
    Remove-Item -Path "$OutputPath/local.settings.json" -ErrorAction SilentlyContinue

    Publish-AzWebApp -Force `
        -Name $appServiceName `
        -ResourceGroupName $appServiceRG `
        -ArchivePath "$OutputPath/deployment-package-$($CdfConfig.Service.Config.serviceName).zip" `
        -WarningAction:SilentlyContinue | Out-Null

    Write-Host "Function App Service implementation deployment done."
}
