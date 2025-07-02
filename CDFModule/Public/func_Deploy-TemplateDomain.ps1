
Function Deploy-TemplateDomain {
    <#
        .SYNOPSIS
        Deploys Integration domain template. The domain requires the foundational parts of the platform and application to be in place.

        .DESCRIPTION
        Deploy Azure resources for Integration domain.

        .PARAMETER CdfConfig
        The CDFConfig object that holds the current scope configurations (Platform, Application and Domain)

        .PARAMETER Deployed
        Override check on configuration 'IsDeployed' to force deployment of deployed configuration

        .PARAMETER TemplateDir
        Path to the platform template root dir. Defaults to ".".

        .PARAMETER SourceDir
        Path to the platform instance source directory. Defaults to "./src".

        .INPUTS
        CdfConfig

        .OUTPUTS
        Updated CdfConfig and json config files at SourceDir

        .EXAMPLE
        Deploy-CdfTemplateDomain -CdfConfig $config

        .EXAMPLE
        $config | Deploy-CdfTemplateDomain `
            -TemplateDir ../cdf-infra/templates `
            -SourceDir ../cdf-infra/instances

        .LINK
        Deploy-CdfTemplateService
        .LINK
        Remove-CdfTemplateDomain
        #>


    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
        [Object]$CdfConfig,
        [Parameter(Mandatory = $false)]
        [switch] $Deployed,
        [Parameter(Mandatory = $false)]
        [string] $TemplateDir = $env:CDF_INFRA_TEMPLATES_PATH ?? '.',
        [Parameter(Mandatory = $false)]
        [string] $SourceDir = $env:CDF_INFRA_SOURCE_PATH ?? './src',
        [Parameter(Mandatory = $false)]
        [string] $OutputDir = ''

    )

    Begin {
    }
    Process {
        if ($CdfConfig.Domain.IsDeployed -eq $true -and !$Deployed) {
            $errMsg = 'Provided domain configuration is a deployed version. If this is intended, use parameter switch -Deployed to override this check. Using deployed version for deployments may impact negatively on template functionality.'
            Write-Error -Message $errMsg
            throw $errMsg
        }
        # Fetch application definitions
        $templatePath = "$TemplateDir/domain/$($CdfConfig.Domain.Config.templateName)/$($CdfConfig.Domain.Config.templateVersion)"
        $sourcePath = "$SourceDir/$($CdfConfig.Platform.Config.platformId)/$($CdfConfig.Platform.Config.instanceId)"

        # Setup deployment variables from configuration
        # Domain uses platform config for region
        $region = $CdfConfig.Platform.Env.region.toLower()
        $regionCode = $CdfConfig.Platform.Env.regionCode
        $regionName = $CdfConfig.Platform.Env.regionName

        $templateFile = "$templatePath/domain.bicep"
        $platformEnvKey = "$($CdfConfig.Platform.Config.platformId)$($CdfConfig.Platform.Config.instanceId)$($CdfConfig.Platform.Env.nameId)"
        $applicationEnvKey = "$($CdfConfig.Application.Config.applicationId ?? $CdfConfig.Application.Config.templateName)$($CdfConfig.Application.Config.instanceId)$($CdfConfig.Application.Env.nameId)"
        $deploymentName = "domain-$platformEnvKey-$applicationEnvKey-$($CdfConfig.Domain.Config.domainName)-$regionCode"
        $postgresConfigOutput = $CdfConfig | Deploy-PostgresConfig
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
        if ($postgresConfigOutput.Count -ne 0) {
            if ($templateParams.domainConfig.ContainsKey("postgresDatabaseName")) {
                $templateParams.domainConfig["postgresDatabaseName"] = $postgresConfigOutput["Postgres-Database"]
                $templateParams.domainConfig["postgresUserSecretName"] = $postgresConfigOutput["Postgres-UserSecretName"]
                $templateParams.domainConfig["postgresPasswordSecretName"] = $postgresConfigOutput["Postgres-PasswordSecretName"]
            }
            else {
                $templateParams.domainConfig.Add("postgresDatabaseName", $postgresConfigOutput["Postgres-Database"])
                $templateParams.domainConfig.Add("postgresUserSecretName", $postgresConfigOutput["Postgres-UserSecretName"])
                $templateParams.domainConfig.Add("postgresPasswordSecretName", $postgresConfigOutput["Postgres-PasswordSecretName"])
            }
        }
        $templateParams.domainNetworkConfig = $CdfConfig.Domain.NetworkConfig ?? @{}
        $templateParams.domainAccessControl = $CdfConfig.Domain.AccessControl ?? @{}

        $templateParams.domainTags = $CdfConfig.Domain.Tags ?? @{}
        $templateParams.domainTags.BuildCommit = $env:GITHUB_SHA ?? $env:BUILD_SOURCEVERSION ?? $(git -C $TemplateDir rev-parse --short HEAD)
        $templateParams.domainTags.BuildRun = $env:GITHUB_RUN_ID ?? $env:BUILD_BUILDNUMBER ?? "local"
        $templateParams.domainTags.BuildBranch = $env:GITHUB_REF_NAME ?? $env:BUILD_SOURCEBRANCH ?? $(git -C $TemplateDir branch --show-current)
        $templateParams.domainTags.BuildRepo = $env:GITHUB_REPOSITORY ?? $env:BUILD_REPOSITORY_NAME ?? $(Split-Path -Leaf (git -C $TemplateDir remote get-url origin))

        Write-Debug "Template parameters: $($templateParams | ConvertTo-Json -Depth 10 | Out-String)"

        $azCtx = Get-AzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId

        Write-Host "Starting deployment of '$deploymentName' at '$region' using subscription [$($AzCtx.Subscription.Name)]."
        $result = New-AzSubscriptionDeployment `
            -DefaultProfile $azCtx `
            -Name $deploymentName `
            -Location $region `
            -TemplateFile $templateFile `
            -TemplateParameterObject $templateParams `
            -WarningAction:SilentlyContinue `
            -ErrorAction:Continue

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

        if ($result.ProvisioningState -eq 'Succeeded') {
            Write-Host "Successfully deployed '$deploymentName' at '$region'."

            # Save deployment configuration for domain
            $CdfDomain = [ordered] @{
                IsDeployed    = $true
                Env           = $result.Outputs.domainEnv.Value
                Tags          = $result.Outputs.domainTags.Value
                Config        = $result.Outputs.domainConfig.Value
                Features      = $result.Outputs.domainFeatures.Value
                ResourceNames = $result.Outputs.domainResourceNames.Value
                NetworkConfig = $result.Outputs.domainNetworkConfig.Value
                AccessControl = $result.Outputs.domainAccessControl.Value
            }

            # Save config file and load as resulting JSON
            $configPath = $OutputDir ? $OutputDir : "$sourcePath/output"
            $configFileName = "domain.$platformEnvKey-$applicationEnvKey-$($CdfConfig.Domain.Config.domainName)-$regionCode.json"
            $configOutput = Join-Path -Path $configPath -ChildPath $configFileName

            if (!(Test-Path -Path $configPath)) {
                New-Item -Type Directory -Path  $configPath | Out-Null
            }

            $CdfDomain | ConvertTo-Json -Depth 10 | Out-File $configOutput
            $CdfDomain = Get-Content -Path $configOutput | ConvertFrom-Json -AsHashtable
            $CdfDomain | ConvertTo-Json -Depth 10 | Write-Verbose

            if ($CdfConfig.Platform.Config.configStoreType) {
                $regionDetails = [ordered] @{
                    region = $region
                    code   = $regionCode
                    name   = $regionName
                }
                Save-ConfigToStore `
                    -CdfConfig $CdfConfig `
                    -ScopeConfig $CdfDomain `
                    -Scope 'Domain' `
                    -OutputConfigFilePath $configOutput `
                    -EnvKey $platformEnvKey-$applicationEnvKey-$($CdfConfig.Domain.Config.domainName) `
                    -RegionDetails $regionDetails `
                    -ErrorAction Continue
            }

            $CdfConfig.Domain = $CdfDomain
            return $CdfConfig
        }
        else {
            Write-Error $result.OutputsString
            Throw "Deployment failed for '$deploymentName' at '$region'. Please check the deployment status on azure portal for additional details."
        }
    }
    End {
    }
}
