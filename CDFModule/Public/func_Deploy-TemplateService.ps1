Function Deploy-TemplateService {
    <#
        .SYNOPSIS
        Deploys Integration service template. The service requires the platform, application and domain to be in place.

        .DESCRIPTION
        Deploy Azure resources for Integration domain.

        .PARAMETER CdfConfig
        The CDFConfig object that holds the current scope configurations (Platform, Application and Domain)

        .PARAMETER TemplateDir
        Path to the platform template root dir. Defaults to ".".

        .PARAMETER SourceDir
        Path to the platform instance source directory. Defaults to "./src".

        .INPUTS
        CdfConfig

        .OUTPUTS
        Updated CdfConfig and json config files at SourceDir

        .EXAMPLE
        Deploy-CdfTemplateService `
            -CdfConfig $config `
            -ServiceName "my-service" `
            -ServiceType "logicapp-standard" `
            -ServiceGroup "demo" `
            -ServiceTemplate "la-sample"

        .EXAMPLE
        $config | Deploy-CdfTemplateService `
            -ServiceName "my-service" `
            -ServiceType "logicapp-standard" `
            -ServiceGroup "demo" `
            -ServiceTemplate "la-sample"
            -TemplateDir ../cdf-infra/templates `
            -SourceDir ../cdf-infra/instances

        .LINK
        Deploy-CdfTemplatePlatform
        Deploy-CdfTemplateApplication
        Deploy-CdfTemplateDomain
        Remove-CdfTemplatePlatform
        Remove-CdfTemplateApplication
        Remove-CdfTemplateDomain
        Remove-TemplateService
        #>

    [CmdletBinding()]
    Param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
        [Object]$CdfConfig,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ServiceName = $env:CDF_SERVICE_NAME,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ServiceType = $env:CDF_SERVICE_TYPE,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ServiceGroup = $env:CDF_SERVICE_GROUP,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ServiceTemplate = $env:CDF_SERVICE_TEMPLATE,
        [Parameter(Mandatory = $false)]
        [string] $TemplateDir = $env:CDF_INFRA_TEMPLATES_PATH ?? '.',
        [Parameter(Mandatory = $false)]
        [string] $SourceDir = $env:CDF_INFRA_SOURCE_PATH ?? './src'

    )

    # Fetch service definitions
    $templatePath = "$TemplateDir/service/$($CdfConfig.Domain.Config.templateName)/$($CdfConfig.Domain.Config.templateVersion)"
    $sourcePath = "$SourceDir/$($CdfConfig.Platform.Config.platformId)/$($CdfConfig.Platform.Config.instanceId)"

    # Setup deployment variables from configuration
    # Service uses application config for region
    $region = $CdfConfig.Platform.Env.region.toLower()
    $regionCode = $CdfConfig.Platform.Env.regionCode
    $regionName = $CdfConfig.Platform.Env.regionName


    # If provided parameters are not set, use the default values from the CDF Config object
    $ServiceName = $ServiceName ? $ServiceName : $CdfConfig.Service.Config.serviceName
    $ServiceType = $ServiceType ? $ServiceType : $CdfConfig.Service.Config.serviceType
    $ServiceGroup = $ServiceGroup ? $ServiceGroup : $CdfConfig.Service.Config.serviceGroup
    $ServiceTemplate = $ServiceTemplate ? $ServiceTemplate : $CdfConfig.Service.Config.serviceTemplate

    $templateFile = "$templatePath/$ServiceTemplate.bicep"
    $platformEnvKey = "$($CdfConfig.Platform.Config.platformId)$($CdfConfig.Platform.Config.instanceId)$($CdfConfig.Platform.Env.nameId)"
    $applicationEnvKey = "$($CdfConfig.Application.Config.applicationId ?? $CdfConfig.Application.Config.templateName)$($CdfConfig.Application.Config.instanceId)$($CdfConfig.Application.Env.nameId)"

    $deploymentName = "service-$platformEnvKey-$applicationEnvKey-$($CdfConfig.Domain.Config.domainName)-$ServiceName-$regionCode"


    # Setup platform parameters from envrionment and params file
    $templateParams = [ordered] @{}

    $templateParams.platformEnv = $CdfConfig.Platform.Env
    $templateParams.platformConfig = $CdfConfig.Platform.Config
    $templateParams.platformFeatures = $CdfConfig.Platform.Features
    $templateParams.platformNetworkConfig = $CdfConfig.Platform.NetworkConfig
    $templateParams.platformResourceNames = $CdfConfig.Platform.ResourceNames

    $templateParams.applicationEnv = $CdfConfig.Application.Env
    $templateParams.applicationConfig = $CdfConfig.Application.Config
    $templateParams.applicationFeatures = $CdfConfig.Application.Features
    $templateParams.applicationNetworkConfig = $CdfConfig.Application.NetworkConfig
    $templateParams.applicationResourceNames = $CdfConfig.Application.ResourceNames

    $templateParams.domainConfig = $CdfConfig.Domain.Config
    $templateParams.domainFeatures = $CdfConfig.Domain.Features
    $templateParams.domainNetworkConfig = $CdfConfig.Domain.NetworkConfig
    $templateParams.domainAccessControl = $CdfConfig.Domain.AccessControl
    $templateParams.domainResourceNames = $CdfConfig.Domain.ResourceNames

    $templateParams.serviceConfig = $CdfConfig.Service -and $CdfConfig.Service.Config ? $CdfConfig.Service.Config ?? @{} : @{}
    $templateParams.serviceConfig.serviceName = $ServiceName ? $ServiceName : $CdfConfig.Service.Config.serviceName
    $templateParams.serviceConfig.serviceType = $ServiceType ? $ServiceType : $CdfConfig.Service.Config.serviceType
    $templateParams.serviceConfig.serviceGroup = $ServiceGroup ? $ServiceGroup : $CdfConfig.Service.Config.serviceGroup
    $templateParams.serviceConfig.serviceTemplate = $ServiceTemplate ? $ServiceTemplate : $CdfConfig.Service.Config.serviceTemplate

    $templateParams.serviceFeatures = $CdfConfig.Service -and $CdfConfig.Service.serviceFeatures ? $CdfConfig.Service.serviceFeatures ?? @{} : @{}
    $templateParams.serviceNetworkConfig = $CdfConfig.Service -and $CdfConfig.Service.serviceNetworkConfig ? $CdfConfig.Service.serviceNetworkConfig ?? @{} : @{}
    $templateParams.serviceAccessControl = $CdfConfig.Service -and $CdfConfig.Service.serviceAccessControl ? $CdfConfig.Service.serviceAccessControl ?? @{} : @{}

    $templateParams.serviceTags = @{} # TODO: Implement default configurable service tags or inherit domain default tags??
    $templateParams.serviceTags.BuildCommit = $env:GITHUB_SHA ?? $env:BUILD_SOURCEVERSION ?? $(git -C $TemplateDir rev-parse --short HEAD)
    $templateParams.serviceTags.BuildRun = $env:GITHUB_RUN_ID ?? $env:BUILD_BUILDNUMBER ?? "local"
    $templateParams.serviceTags.BuildBranch = $env:GITHUB_REF_NAME ?? $env:BUILD_SOURCEBRANCH ?? $(git -C $TemplateDir branch --show-current)
    $templateParams.serviceTags.BuildRepo = $env:GITHUB_REPOSITORY ?? $env:BUILD_REPOSITORY_NAME ?? $(Split-Path -Leaf (git -C $TemplateDir remote get-url origin))

    # TODO: Remove these - deprecated. Kept for now not to break compatbility with old templates.
    $templateParams.serviceName = $ServiceName
    $templateParams.serviceType = $ServiceType
    $templateParams.serviceGroup = $ServiceGroup
    $templateParams.serviceTemplate = $ServiceTemplate

    Write-Debug "Template parameters: $($templateParams | ConvertTo-Json -Depth 10 | Out-String)"

    $azCtx = Get-AzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId

    Write-Host "Starting deployment of '$deploymentName' at '$Region' using subscription [$($AzCtx.Subscription.Name)]."
    $result = New-AzResourceGroupDeployment `
        -DefaultProfile $azCtx `
        -Name $deploymentName `
        -ResourceGroupName $CdfConfig.Domain.ResourceNames.domainResourceGroupName `
        -TemplateFile $templateFile `
        -TemplateParameterObject $templateParams `
        -WarningAction:SilentlyContinue `
        -ErrorAction:Continue

    $result | ConvertTo-Json -Depth 10 | Write-Verbose

    While ($result -and -not($result.ProvisioningState -eq 'Succeeded' -or $result.ProvisioningState -eq 'Failed')) {
        Write-Host 'Deployment still running...'
        Start-Sleep 30
        $result = Get-AzSubscriptionDeployment -DefaultProfile $azCtx -Name "$deploymentName"
        Write-Verbose $result
    }

    if ( -not $? -or ($null -eq $result.Outputs) ) {
        Write-Error 'Deployment failed.'
        if (($null -ne $Error) -and ($null -ne $Error)) {
            Write-Error 'Error messages are:'
            $Error
            foreach ($errorDetail in $Error) {
                if (($null -ne $errorDetail)) {
                    Write-Error $errorDetail.Exception.Message
                }
            }
        }
        Write-Error 'Operation error messages are:'
        $errors = Get-AzDeploymentOperation `
            -DefaultProfile $azCtx `
            -DeploymentName $deploymentName `
        | Where-Object -FilterScript { $_.ProvisioningState -eq 'Failed' }
        foreach ($error in $errors) {
            Write-Error "Error [$( $error.StatusCode)] Message [$( $error.StatusMessage)]"
        }
        throw "Deployment failed, see error output or deployment status on Azure Portal"
    }

    if ($result.ProvisioningState = 'Succeeded') {
        Write-Host "Successfully deployed '$deploymentName' at '$Region'."

        # Save deployment configuration for service
        $CdfService = [ordered] @{
            IsDeployed    = $true
            Env           = $result.Outputs.serviceEnv.Value
            Tags          = $result.Outputs.serviceTags.Value
            Config        = $result.Outputs.serviceConfig.Value
            Features      = $result.Outputs.serviceFeatures.Value
            ResourceNames = $result.Outputs.serviceResourceNames.Value
            NetworkConfig = $result.Outputs.serviceNetworkConfig.Value
            AccessControl = $result.Outputs.serviceAccessControl.Value
        }

        $CdfService.Config.serviceName = $ServiceName
        $CdfService.Config.serviceType = $ServiceType
        $CdfService.Config.serviceGroup = $ServiceGroup
        $CdfService.Config.serviceTemplate = $ServiceTemplate

        # Save config file and load as resulting JSON

        $configPath = $OutputDir ? $OutputDir : "$sourcePath/output"
        $configFileName = "service.$platformEnvKey-$applicationEnvKey-$($CdfConfig.Domain.Config.domainName)-$ServiceName-$regionCode.json"
        $configOutput = Join-Path -Path $configPath -ChildPath $configFileName

        if (!(Test-Path -Path $configPath)) {
            New-Item -Type Directory -Path  $configPath | Out-Null
        }

        $CdfService | ConvertTo-Json -Depth 10 | Out-File $configOutput
        $CdfService = Get-Content -Path $configOutput | ConvertFrom-Json -AsHashtable
        $CdfService | ConvertTo-Json -Depth 10 | Write-Verbose

        if ($CdfConfig.Platform.Config.configStoreType.ToUpper() -ne 'DEPLOYMENTOUTPUT') {
            $regionDetails = [ordered] @{
                region = $region
                code   = $regionCode
                name   = $regionName
            }
            Save-ConfigToStore `
                -CdfConfig $CdfConfig `
                -ScopeConfig $CdfService `
                -Scope 'Service' `
                -OutputConfigFilePath $configOutput `
                -EnvKey $platformEnvKey-$applicationEnvKey-$($CdfConfig.Domain.Config.domainName)-$ServiceName `
                -RegionDetails $regionDetails `
                -ErrorAction Continue
        }
        $CdfConfig.Service = $CdfService
        return $CdfConfig
    }
    else {
        Write-Error $result.OutputsString
        Throw "Deployment failed for '$deploymentName' at '$Region'. Please check the deployment status on azure portal for details."
    }
}
