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

    # Use "cdf-config.json" if available, but if parameter is bound it overrides / takes precendens
    if (Test-Path "$ServiceSrcPath/cdf-config.json") {
        Write-Host "Loading service settings from cdf-config.json"
        $svcConfig = Get-Content -Raw "$ServiceSrcPath/cdf-config.json" | ConvertFrom-Json -AsHashtable
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
    if ($null -eq $CdfConfig) {
        Write-Host "Get Platform Config [$PlatformId$PlatformInstance]"
        $CdfConfig = Get-CdfConfigPlatform `
            -Region $Region `
            -PlatformId $PlatformId `
            -Instance $PlatformInstance `
            -EnvDefinitionId $PlatformEnvId  `
            -SourceDir $CdfInfraSourcePath `
            -Deployed -ErrorAction Continue

        if ($null -eq $CdfConfig.Platform -or $false -eq $CdfConfig.Platform.IsDeployed) {
            throw "Missing Platform configuration for deployed runtime instance."
        }
        
        Write-Host "Get Application Config [$ApplicationId$ApplicationInstance]"
        $CdfConfig = Get-CdfConfigApplication `
            -CdfConfig $CdfConfig `
            -Region $Region `
            -ApplicationId $ApplicationId  `
            -InstanceId $ApplicationInstance `
            -EnvDefinitionId $ApplicationEnvId  `
            -SourceDir $CdfInfraSourcePath `
            -Deployed -ErrorAction Continue

        if ($null -eq $CdfConfig.Application -or $false -eq $CdfConfig.Application.IsDeployed) {
            throw "Missing Application configuration for deployed runtime instance."
        }
  
        if ($false -eq $isApi) {
            Write-Host "Get Domain Config [$DomainName]"
            $CdfConfig = Get-CdfConfigDomain `
                -CdfConfig $CdfConfig `
                -DomainName $DomainName `
                -SourceDir $CdfInfraSourcePath `
                -Deployed -ErrorAction Continue
    
            if ($null -eq $CdfConfig.Domain -or $false -eq $CdfConfig.Domain.IsDeployed) {
                throw "Missing Domain configuration for deployed runtime instance."
            }
        }
    }

    # API Management does not have infrastructure configuration for service
    if ($false -eq $isApi) {
        try {
            Write-Host "Get Service Config [$ServiceName]"
            $CdfConfig = Get-ConfigService `
                -CdfConfig $CdfConfig `
                -ServiceName $ServiceName `
                -SourceDir $CdfInfraSourcePath `
                -Deployed -ErrorAction Stop

            if ($null -eq $CdfConfig.Service -or !$CdfConfig.Service.IsDeployed) {
                throw "Service infrastructure not deployed."
            }
        }
        catch {
            Write-Host "Deploying CDF Infrastructure for Logic App Standard service [$ServiceName]"
            $CdfConfig = Deploy-TemplateService `
                -CdfConfig $CdfConfig `
                -ServiceName $ServiceName `
                -ServiceType $ServiceType `
                -ServiceGroup $ServiceGroup `
                -ServiceTemplate $ServiceTemplate `
                -TemplateDir $CdfInfraTemplatePath `
                -SourceDir $CdfInfraSourcePath `
                -ErrorAction:Stop

            if ($null -eq $CdfConfig.Service -or $false -eq $CdfConfig.Service.IsDeployed) {
                throw "Deployment of Service runtime infrastructure template failed."
            }

        }
    }
    else {
        # Setup a dummy domain and service configuration for API
        $CdfConfig.Domain = @{
            IsDeployed = $false
            Config     = @{
                templateScope   = 'domain'
                templateName    = $CdfConfig.Application.Config.templateName
                templateVersion = $CdfConfig.Application.Config.templateVersion
                domainName      = $DomainName
            }
            Env        = $CdfConfig.Application.Env
        }
        $CdfConfig.Service = @{
            IsDeployed = $false
            Config     = @{
                templateScope   = 'service'
                templateName    = $CdfConfig.Application.Config.templateName
                templateVersion = $CdfConfig.Application.Config.templateVersion
                serviceName     = $ServiceName
                serviceGroup    = $ServiceGroup
                serviceType     = $ServiceType
                serviceTemplate = $ServiceTemplate
            }
            Env        = $CdfConfig.Application.Env
        }
    }

    if ($true -eq $isApi -and $null -ne $CdfConfig.Service) {
        # Ensure we are using any override values as we move on
        $CdfConfig.Service.Config.serviceName = $ServiceName
        $CdfConfig.Service.Config.serviceGroup = $ServiceGroup
        $CdfConfig.Service.Config.serviceType = $ServiceType
        $CdfConfig.Service.Config.serviceTemplate = $ServiceTemplate
    }

    if (!$ServiceOnly) {
        # TODO: Iterate multiple occurances "storageaccount*.config.json"
        if (Test-Path "$ServiceSrcPath/storageaccount.config.json" ) {
            Deploy-StorageAccountConfig `
                -CdfConfig $CdfConfig `
                -InputPath $ServiceSrcPath `
                -OutputPath $outputPath `
                -TemplateDir $CdfSharedPath/modules/storageaccount-config `
                -ErrorAction Stop
                    
        }
                
        # TODO: Iterate multiple occurances "servicebus*.config.json"
        if (Test-Path "$ServiceSrcPath/servicebus.config.json" ) {
            Deploy-ServiceBusConfig `
                -CdfConfig $CdfConfig `
                -InputPath $ServiceSrcPath  `
                -OutputPath $outputPath `
                -TemplateDir $CdfSharedPath/modules/servicebus-config `
                -ErrorAction Stop
        }
    }

    if ($ServiceTemplate -eq 'logicapp-standard') {
        Deploy-ServiceLogicAppStd `
            -CdfConfig $CdfConfig `
            -InputPath $ServiceSrcPath `
            -OutputPath $outputPath `
            -TemplateDir $CdfSharedPath/modules `
            -ErrorAction Stop
    }
    elseif ($ServiceTemplate -eq 'functionapp') {
        Deploy-ServiceFunctionApp `
            -CdfConfig $CdfConfig `
            -InputPath $ServiceSrcPath `
            -OutputPath $outputPath `
            -TemplateDir $CdfSharedPath/modules `
            -ErrorAction Stop
    }
    elseif ($ServiceTemplate.StartsWith('container-')) {
        Deploy-ServiceContainerAppService `
            -CdfConfig $CdfConfig `
            -InputPath $ServiceSrcPath `
            -OutputPath $outputPath `
            -TemplateDir $CdfSharedPath/modules `
            -ErrorAction Stop
    }
    elseif ($true -eq $isApi) {
        
        # Default is to deploy service dependencies (ServiceOnly = false)
        if (!$ServiceOnly) {
            $CdfConfig | Build-ApimDomainBackendTemplates `
                -DomainName $DomainName `
                -DomainPath (Resolve-Path "$ServiceSrcPath/..") `
                -SharedPath $CdfSharedPath `
                -BuildPath "$OutputPath/domain-backends" `
                -ErrorAction:Stop

            $CdfConfig | Build-ApimDomainProductTemplates `
                -DomainName $DomainName `
                -DomainPath (Resolve-Path "$ServiceSrcPath/..") `
                -SharedPath $CdfSharedPath `
                -BuildPath "$OutputPath/domain-products" `
                -ErrorAction:Stop

            $CdfConfig | Build-ApimDomainNamedValuesTemplate `
                -DomainName $DomainName `
                -DomainPath (Resolve-Path "$ServiceSrcPath/..") `
                -SharedPath $CdfSharedPath `
                -BuildPath "$OutputPath/domain-namedvalues" `
                -ErrorAction:Stop
                        
            # Deploy Domain Named Values to KeyVault
            $CdfConfig | Deploy-ApimKeyVaultDomainNamedValues `
                -DomainName $DomainName `
                -ConfigPath "$OutputPath/domain-namedvalues/"

            $azCtx = Get-AzureContext $CdfConfig.Platform.Env.subscriptionId

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
                        -ResourceGroupName $CdfConfig.Application.ResourceNames.appResourceGroupName `
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
                        -ResourceGroupName $CdfConfig.Application.ResourceNames.appResourceGroupName `
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
                    -ResourceGroupName $CdfConfig.Application.ResourceNames.appResourceGroupName `
                    -TemplateFile "$OutputPath/domain-namedvalues/namedvalues.domain.bicep" `
                    -TemplateParameterFile "$OutputPath/domain-namedvalues/namedvalues.domain.params.json" `
                    -ErrorAction:Stop `
                    -WarningAction:SilentlyContinue `
                | Out-Null
            }
        }


        # Build API templates
        $CdfConfig | Build-ApimServiceTemplates `
            -DomainName $DomainName `
            -ServiceName $ServiceName `
            -ServicePath $ServiceSrcPath `
            -SharedPath $CdfSharedPath `
            -BuildPath "$OutputPath/domain-api" `
            -ErrorAction Stop

        # Replace CDF tokens in policy xml
        $CdfTokens = $CdfConfig | Get-TokenValues
        Update-ConfigFileTokens `
            -InputFile "$OutputPath/domain-api/$ServiceName.params.json" `
            -OutputFile "$OutputPath/domain-api/$ServiceName.subst.params.json" `
            -Tokens $CdfTokens `
            -StartTokenPattern "#{" `
            -EndTokenPattern "}#" `
            -NoWarning `
            -WarningAction:SilentlyContinue 
             
        # Deploy Service Named Values to KeyVault
        $CdfConfig | Deploy-ApimKeyVaultServiceNamedValues `
            -DomainName $DomainName `
            -ServiceName $ServiceName `
            -ConfigPath "$OutputPath/domain-api"

        # Deploy API
        Write-Host "Deploying api template: $OutputPath/domain-api/$ServiceName.bicep" 
        New-AzResourceGroupDeployment `
            -DefaultProfile $azCtx `
            -Name "api-$DomainName-$ServiceName" `
            -ResourceGroupName $CdfConfig.Application.ResourceNames.appResourceGroupName `
            -TemplateFile "$OutputPath/domain-api/$ServiceName.bicep" `
            -TemplateParameterFile "$OutputPath/domain-api/$ServiceName.subst.params.json" `
            -ErrorAction:Stop `
        | Out-Null

        # Indicate is deployed...
        $CdfConfig.Domain.IsDeployed = $true
        $CdfConfig.Service.IsDeployed = $true
    }
    else {
        Write-Error "Unable to determine service implementation. Supported ServiceTemplate keywords include 'api-*', 'logicapp-standard', 'container-*'."
    }
    return $CdfConfig
}