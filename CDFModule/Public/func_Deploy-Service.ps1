Function Deploy-Service {

    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
        [hashtable]$CdfConfig,
        [Parameter(Mandatory = $false)]
        [string] $Region = $env:CDF_REGION,
        [Parameter(Mandatory = $false)]
        [string] $PlatformId = $env:CDF_PLATFORM_ID,
        [Parameter(Mandatory = $false)]
        [string] $PlatformInstance = $env:CDF_PLATFORM_INSTANCE,
        [Parameter(Mandatory = $false)]
        [string] $PlatformEnvId = $env:CDF_PLATFORM_ENV_ID,
        [Parameter(Mandatory = $false)]
        [string] $ApplicationId = $env:CDF_APPLICATION_ID,
        [Parameter(Mandatory = $false)]
        [string] $ApplicationInstance = $env:CDF_APPLICATION_INSTANCE,
        [Parameter(Mandatory = $false)]
        [string] $ApplicationEnvId = $env:CDF_APPLICATION_ENV_ID,
        [Parameter(Mandatory = $false)]
        [string] $DomainName = $env:CDF_DOMAIN_NAME,
        [Parameter(Mandatory = $false)]
        [string] $ServiceName = $env:CDF_SERVICE_NAME,
        [Parameter(Mandatory = $false)]
        [string] $ServiceType = $env:CDF_SERVICE_TYPE,
        [Parameter(Mandatory = $false)]
        [string] $ServiceGroup = $env:CDF_SERVICE_GROUP,
        [Parameter(Mandatory = $false)]
        [string] $ServiceTemplate = $env:CDF_SERVICE_TEMPLATE,
        [Parameter(Mandatory = $false)]
        [string] $ServiceSrcPath = ".",
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $CdfInfraTemplatePath = $env:CDF_INFRA_TEMPLATES_PATH ?? "../../cdf-infra",
        [Parameter(Mandatory = $false)]
        [string] $CdfInfraSourcePath = $env:CDF_INFRA_SOURCE_PATH ?? "../../cdf-infra/src",
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $CdfSharedPath = $env:CDF_SHARED_SOURCE_PATH ?? "../../shared-infra",
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $SharedTemplatePath = $env:CDF_SHARED_TEMPLATES_PATH ?? "$CdfSharedPath/templates",
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $BuildPath = "../tmp/build",
        [Parameter(Mandatory = $false)]
        [switch] $ServiceOnly = $false

    )

    # Initiate Service Deployment CDF Config
    if ($null -ne $CdfConfig) {
        $SvcCdfConfig = $CdfConfig.Clone()
    }

    # Use "cdf-config.json" if available, but if parameter is bound it overrides / takes precedence
    $cdfConfigFile = Join-Path -Path $ServiceSrcPath  -ChildPath 'cdf-config.json'
    if (Test-Path $cdfConfigFile) {
        Write-Host "Loading service settings from cdf-config.json"

        $cdfSchemaPath = Join-Path -Path $MyInvocation.MyCommand.Module.ModuleBase -ChildPath 'Resources/Schemas/cdf-service-config.schema.json'
        if (!(Test-Json -SchemaFile $cdfSchemaPath -Path $cdfConfigFile)) {
            Write-Error "Service configuration file did not validate. Please check errors above and correct."
            Write-Error "File path:  $cdfConfigFile"
            return
        }
        $svcConfig = Get-Content -Raw $cdfConfigFile | ConvertFrom-Json -AsHashtable

        $ServiceName = $MyInvocation.BoundParameters.Keys.Contains("ServiceName") ? $ServiceName : $svcConfig.ServiceDefaults.ServiceName
        $ServiceGroup = $MyInvocation.BoundParameters.Keys.Contains("ServiceGroup") ? $ServiceGroup : $svcConfig.ServiceDefaults.ServiceGroup
        $ServiceType = $MyInvocation.BoundParameters.Keys.Contains("ServiceType") ? $ServiceType : $svcConfig.ServiceDefaults.ServiceType
        $ServiceTemplate = $MyInvocation.BoundParameters.Keys.Contains("ServiceTemplate") ? $ServiceTemplate : $svcConfig.ServiceDefaults.ServiceTemplate
    }

    # Make sure build folder exists
    if (!(Test-Path -Path $BuildPath)) {
        New-Item -Force  -Type Directory $BuildPath -ErrorAction SilentlyContinue | Out-Null
    }

    # Clear output from previos build
    $outputPath = "$BuildPath/$ServiceName"
    if (!(Test-Path -Path $outputPath)) {
        New-Item -Force  -Type Directory $outputPath -ErrorAction SilentlyContinue | Out-Null
    }
    else {
        Remove-Item -Recurse -Force $outputPath -ErrorAction SilentlyContinue | Out-Null
    }
    New-Item -Force -Type Directory $outputPath -ErrorAction SilentlyContinue | Out-Null

    $isApi = $ServiceTemplate.StartsWith('api-') # API Management has a slightly difference handling and currently does not require domain infra deployment config.
    if ($null -eq $SvcCdfConfig) {
        Write-Host "Get Platform Config [$PlatformId$PlatformInstance]"
        $SvcCdfConfig = Get-CdfConfigPlatform `
            -Region $Region `
            -PlatformId $PlatformId `
            -Instance $PlatformInstance `
            -EnvDefinitionId $PlatformEnvId  `
            -SourceDir $CdfInfraSourcePath `
            -Deployed -ErrorAction Continue

        if ($null -eq $SvcCdfConfig.Platform -or $false -eq $SvcCdfConfig.Platform.IsDeployed) {
            throw "Missing Platform configuration for deployed runtime instance."
        }

        Write-Host "Get Application Config [$ApplicationId$ApplicationInstance]"
        $SvcCdfConfig = Get-CdfConfigApplication `
            -CdfConfig $SvcCdfConfig `
            -Region $Region `
            -ApplicationId $ApplicationId  `
            -InstanceId $ApplicationInstance `
            -EnvDefinitionId $ApplicationEnvId  `
            -SourceDir $CdfInfraSourcePath `
            -Deployed -ErrorAction Continue

        if ($null -eq $SvcCdfConfig.Application -or $false -eq $SvcCdfConfig.Application.IsDeployed) {
            throw "Missing Application configuration for deployed runtime instance."
        }

        if ($false -eq $isApi) {
            Write-Host "Get Domain Config [$DomainName]"
            $SvcCdfConfig = Get-CdfConfigDomain `
                -CdfConfig $SvcCdfConfig `
                -DomainName $DomainName `
                -SourceDir $CdfInfraSourcePath `
                -Deployed -ErrorAction Continue

            if ($null -eq $SvcCdfConfig.Domain -or $false -eq $SvcCdfConfig.Domain.IsDeployed) {
                throw "Missing Domain configuration for deployed runtime instance."
            }
        }
    }

    # API Management does not have infrastructure configuration for service
    if ($true -eq $isApi) {
        # Setup a dummy domain and service configuration for API
        $SvcCdfConfig.Domain = @{
            IsDeployed = $false
            Config     = @{
                templateScope   = 'domain'
                templateName    = $SvcCdfConfig.Application.Config.templateName
                templateVersion = $SvcCdfConfig.Application.Config.templateVersion
                domainName      = $DomainName
            }
            Env        = $SvcCdfConfig.Application.Env
        }
        $SvcCdfConfig.Service = @{
            IsDeployed = $false
            Config     = @{
                templateScope   = 'service'
                templateName    = $SvcCdfConfig.Application.Config.templateName
                templateVersion = $SvcCdfConfig.Application.Config.templateVersion
                serviceName     = $ServiceName
                serviceGroup    = $ServiceGroup
                serviceType     = $ServiceType
                serviceTemplate = $ServiceTemplate
            }
            Env        = $SvcCdfConfig.Application.Env
        }
    }
    elseif ($false -eq $isApi -and ($null -eq $SvcCdfConfig.Service -or $false -eq $SvcCdfConfig.Service.IsDeployed )) {
        # We're missing Deployed Service configuration in CdfConfig. Try fetching or deploy infra.
        try {
            Write-Host "Get Service Config [$ServiceName]"
            $SvcCdfConfig = Get-ConfigService `
                -CdfConfig $SvcCdfConfig `
                -ServiceName $ServiceName `
                -SourceDir $CdfInfraSourcePath `
                -Deployed -ErrorAction Stop

            if ($null -eq $SvcCdfConfig.Service -or !$SvcCdfConfig.Service.IsDeployed) {
                throw "Service infrastructure not deployed."
            }
        }
        catch {
            Write-Host "Deploying CDF Infrastructure for [$ServiceTemplate] service [$ServiceName]"
            $SvcCdfConfig = Deploy-TemplateService `
                -CdfConfig $SvcCdfConfig `
                -ServiceName $ServiceName `
                -ServiceType $ServiceType `
                -ServiceGroup $ServiceGroup `
                -ServiceTemplate $ServiceTemplate `
                -TemplateDir $CdfInfraTemplatePath `
                -SourceDir $CdfInfraSourcePath `
                -ErrorAction:Stop

            if ($null -eq $SvcCdfConfig.Service -or $false -eq $SvcCdfConfig.Service.IsDeployed) {
                throw "Deployment of Service runtime infrastructure template failed."
            }

        }
        # Set current ServiceGroup
        $SvcCdfConfig.Service.Config.serviceGroup = $ServiceGroup
    }


    if ($true -eq $isApi -and $null -ne $SvcCdfConfig.Service) {
        # Ensure we are using any override values as we move on
        $SvcCdfConfig.Service.Config.serviceName = $ServiceName
        $SvcCdfConfig.Service.Config.serviceGroup = $ServiceGroup
        $SvcCdfConfig.Service.Config.serviceType = $ServiceType
        $SvcCdfConfig.Service.Config.serviceTemplate = $ServiceTemplate
    }

    if (!$ServiceOnly) {
        # TODO: Iterate multiple occurances "storageaccount*.config.json"
        if (Test-Path "$ServiceSrcPath/storageaccount.config.json" ) {
            Deploy-StorageAccountConfig `
                -CdfConfig $SvcCdfConfig `
                -InputPath $ServiceSrcPath `
                -OutputPath $outputPath `
                -TemplateDir $CdfSharedPath/modules/storageaccount-config `
                -ErrorAction Stop

        }

        # TODO: Iterate multiple occurances "servicebus*.config.json"
        if (Test-Path "$ServiceSrcPath/servicebus.config.json" ) {
            Deploy-ServiceBusConfig `
                -CdfConfig $SvcCdfConfig `
                -InputPath $ServiceSrcPath  `
                -OutputPath $outputPath `
                -TemplateDir $CdfSharedPath/modules/servicebus-config `
                -ErrorAction Stop
        }
    }

    if ($ServiceTemplate -eq 'logicapp-standard') {
        Deploy-ServiceLogicAppStd `
            -CdfConfig $SvcCdfConfig `
            -InputPath $ServiceSrcPath `
            -OutputPath $outputPath `
            -TemplateDir $CdfSharedPath/modules `
            -ErrorAction Stop
    }
    elseif ($ServiceTemplate -eq 'functionapp') {
        Deploy-ServiceFunctionApp `
            -CdfConfig $SvcCdfConfig `
            -InputPath $ServiceSrcPath `
            -OutputPath $outputPath `
            -TemplateDir $CdfSharedPath/modules `
            -ErrorAction Stop
    }
    elseif ($ServiceTemplate.StartsWith('containerapp-')) {
        Deploy-ServiceContainerApp `
            -CdfConfig $SvcCdfConfig `
            -InputPath $ServiceSrcPath `
            -OutputPath $outputPath `
            -TemplateDir $CdfSharedPath/modules `
            -ErrorAction Stop
    }
    elseif ($ServiceTemplate.StartsWith('container-')) {
        Deploy-ServiceContainerAppService `
            -CdfConfig $SvcCdfConfig `
            -InputPath $ServiceSrcPath `
            -OutputPath $outputPath `
            -TemplateDir $CdfSharedPath/modules `
            -ErrorAction Stop
    }
    elseif ($true -eq $isApi) {
        # Default is to deploy service dependencies (ServiceOnly = false)
        if (!$ServiceOnly) {
            $SvcCdfConfig | Build-ApimDomainBackendTemplates `
                -DomainName $DomainName `
                -DomainPath (Resolve-Path "$ServiceSrcPath/..") `
                -SharedPath $CdfSharedPath `
                -BuildPath "$OutputPath/domain-backends" `
                -ErrorAction:Stop

            $SvcCdfConfig | Build-ApimDomainProductTemplates `
                -DomainName $DomainName `
                -DomainPath (Resolve-Path "$ServiceSrcPath/..") `
                -SharedPath $CdfSharedPath `
                -BuildPath "$OutputPath/domain-products" `
                -ErrorAction:Stop

            $SvcCdfConfig | Build-ApimDomainNamedValuesTemplate `
                -DomainName $DomainName `
                -DomainPath (Resolve-Path "$ServiceSrcPath/..") `
                -SharedPath $CdfSharedPath `
                -BuildPath "$OutputPath/domain-namedvalues" `
                -ErrorAction:Stop

            # Deploy Domain Named Values to KeyVault
            $SvcCdfConfig | Deploy-ApimKeyVaultDomainNamedValues `
                -DomainName $DomainName `
                -ConfigPath "$OutputPath/domain-namedvalues/"

            $azCtx = Get-AzureContext $SvcCdfConfig.Platform.Env.subscriptionId

            # Deploy Products
            if (Test-Path "$OutputPath/domain-products") {
                $Templates = Get-ChildItem -Path "$OutputPath/domain-products" -Include "product.*.$DomainName-*.bicep" -File -Name
                foreach ($Template in $Templates) {
                    $Params = $Template.replace('.bicep', '.params.json')
                    Write-Host "Deploying product template: $Template"
                    $ProductName = $Template.Replace('.bicep', '')
                    New-AzResourceGroupDeployment `
                        -DefaultProfile $azCtx `
                        -Name "domain-$DomainName-product-$ProductName" `
                        -ResourceGroupName $SvcCdfConfig.Application.ResourceNames.appResourceGroupName `
                        -TemplateFile "$OutputPath/domain-products/$Template" `
                        -TemplateParameterFile "$OutputPath/domain-products/$Params" `
                        -ErrorAction:Stop `
                        -WarningAction:SilentlyContinue `
                    | Out-Null
                }
            }

            # Deploy Backends
            if (Test-Path "$OutputPath/domain-backends") {
                $Templates = Get-ChildItem -Path "$OutputPath/domain-backends" -Include "backend.*.$DomainName-*.bicep" -File -Name
                foreach ($Template in $Templates) {
                    $Params = $Template.replace('.bicep', '.params.json')
                    Write-Host "Deploying backend template: $Template"
                    $BackendName = $Template.Replace('.bicep', '')
                    New-AzResourceGroupDeployment `
                        -DefaultProfile $azCtx `
                        -Name "domain-$DomainName-backend-$BackendName" `
                        -ResourceGroupName $SvcCdfConfig.Application.ResourceNames.appResourceGroupName `
                        -TemplateFile "$OutputPath/domain-backends/$Template" `
                        -TemplateParameterFile "$OutputPath/domain-backends/$Params" `
                        -ErrorAction:Stop `
                        -WarningAction:SilentlyContinue `
                    | Out-Null
                }
            }

            # Deploy APIM Domain Named Values
            if (Test-Path "$OutputPath/domain-namedvalues") {
                New-AzResourceGroupDeployment `
                    -DefaultProfile $azCtx `
                    -Name "domain-$DomainName-namedvalues" `
                    -ResourceGroupName $SvcCdfConfig.Application.ResourceNames.appResourceGroupName `
                    -TemplateFile "$OutputPath/domain-namedvalues/namedvalues.domain.bicep" `
                    -TemplateParameterFile "$OutputPath/domain-namedvalues/namedvalues.domain.params.json" `
                    -ErrorAction:Stop `
                    -WarningAction:SilentlyContinue `
                | Out-Null
            }
        }


        # Build API templates
        $SvcCdfConfig | Build-ApimServiceTemplates `
            -DomainName $DomainName `
            -ServiceName $ServiceName `
            -ServicePath $ServiceSrcPath `
            -SharedPath $CdfSharedPath `
            -BuildPath "$OutputPath/domain-api" `
            -ErrorAction Stop

        # Replace CDF tokens in policy xml
        $CdfTokens = $SvcCdfConfig | Get-TokenValues
        Update-ConfigFileTokens `
            -InputFile "$OutputPath/domain-api/$ServiceName.params.json" `
            -OutputFile "$OutputPath/domain-api/$ServiceName.subst.params.json" `
            -Tokens $CdfTokens `
            -StartTokenPattern "#{" `
            -EndTokenPattern "}#" `
            -NoWarning `
            -WarningAction:SilentlyContinue

        # Deploy Service Named Values to KeyVault
        $SvcCdfConfig | Deploy-ApimKeyVaultServiceNamedValues `
            -DomainName $DomainName `
            -ServiceName $ServiceName `
            -ConfigPath "$OutputPath/domain-api"

        # Deploy API
        Write-Host "Deploying api template: $OutputPath/domain-api/$ServiceName.bicep"
        New-AzResourceGroupDeployment `
            -DefaultProfile $azCtx `
            -Name "api-$DomainName-$ServiceName" `
            -ResourceGroupName $SvcCdfConfig.Application.ResourceNames.appResourceGroupName `
            -TemplateFile "$OutputPath/domain-api/$ServiceName.bicep" `
            -TemplateParameterFile "$OutputPath/domain-api/$ServiceName.subst.params.json" `
            -ErrorAction:Stop `
        | Out-Null

        # Indicate is deployed...
        $SvcCdfConfig.Domain.IsDeployed = $true
        $SvcCdfConfig.Service.IsDeployed = $true
    }
    else {
        Write-Error "Unable to determine service implementation. Supported ServiceTemplate keywords include 'api-*', 'logicapp-standard', 'container-*'."
    }
    return $SvcCdfConfig
}