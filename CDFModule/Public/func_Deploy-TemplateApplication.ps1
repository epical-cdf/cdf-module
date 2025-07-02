Function Deploy-TemplateApplication {
    <#
        .SYNOPSIS
        Deploys Integration application template. The application requires the foundational parts of the platform to be in place.

        .DESCRIPTION
        Deploy Azure resources for Integration application.

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
        ($config | Get-CdfConfigApplication ...) `
            | Deploy-CdfTemplateApplication

        .EXAMPLE
        $config = Get-CdfConfigApplication ...; $config `
            | Deploy-CdfTemplateApplication `
            -TemplateDir ../cdf-infra/templates `
            -SourceDir ../cdf-infra/instances

        .LINK
        Get-CdfConfigPlatform
        .LINK
        Remove-CdfTemplateApplication
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
        if ($CdfConfig.Application.IsDeployed -eq $true -and !$Deployed) {
            $errMsg = 'Provided application configuration is a deployed version. If this is intended, use parameter switch -Deployed to override this check. Using deployed version for deployments may impact negatively on template functionality.'
            Write-Error -Message $errMsg
            throw $errMsg
        }

        # Fetch platform definitions
        $templatePath = "$TemplateDir/application/$($CdfConfig.Application.Config.templateName)/$($CdfConfig.Application.Config.templateVersion)"
        $sourcePath = "$SourceDir/$($CdfConfig.Platform.Config.platformId)/$($CdfConfig.Platform.Config.instanceId)"

        # Setup deployment variables from configuration
        # Application uses platform config for region
        $region = $CdfConfig.Platform.Env.region.toLower()
        $regionCode = $CdfConfig.Platform.Env.regionCode
        $regionName = $CdfConfig.Platform.Env.regionName

        $CdfConfig.Application.Env.region = $region
        $CdfConfig.Application.Env.regionCode = $regionCode
        $CdfConfig.Application.Env.regionName = $regionName

        $templateFile = "$templatePath/application.bicep"
        $platformEnvKey = "$($CdfConfig.Platform.Config.platformId)$($CdfConfig.Platform.Config.instanceId)$($CdfConfig.Platform.Env.nameId)"
        $applicationEnvKey = "$($CdfConfig.Application.Config.applicationId ?? $CdfConfig.Application.Config.templateName)$($CdfConfig.Application.Config.instanceId)$($CdfConfig.Application.Env.nameId)"
        $deploymentName = "application-$platformEnvKey-$applicationEnvKey-$regionCode"

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
        $templateParams.applicationNetworkConfig = $CdfConfig.Application.NetworkConfig ?? @{}
        $templateParams.applicationAccessControl = $CdfConfig.Application.AccessControl ?? @{}

        $templateParams.applicationTags = $CdfConfig.Application.Tags ?? @{}
        $templateParams.applicationTags.BuildCommit = $env:GITHUB_SHA ?? $env:BUILD_SOURCEVERSION ?? $(git -C $TemplateDir rev-parse --short HEAD)
        $templateParams.applicationTags.BuildRun = $env:GITHUB_RUN_ID ?? $env:BUILD_BUILDNUMBER ?? "local"
        $templateParams.applicationTags.BuildBranch = $env:GITHUB_REF_NAME ?? $env:BUILD_SOURCEBRANCH ?? $(git -C $TemplateDir branch --show-current)
        $templateParams.applicationTags.BuildRepo = $env:GITHUB_REPOSITORY ?? $env:BUILD_REPOSITORY_NAME ?? $(Split-Path -Leaf (git -C $TemplateDir remote get-url origin))

        Write-Debug "Template parameters: $($templateParams | ConvertTo-Json -Depth 10 | Out-String)"

        $azCtx = Get-AzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId

        Write-Host "Starting deployment of '$deploymentName' at '$region' using subscription [$($AzCtx.Subscription.Name)]."
        $result = New-AzSubscriptionDeployment `
            -DefaultProfile $azCtx `
            -Name $deploymentName `
            -Location $region  `
            -TemplateFile $templateFile `
            -TemplateParameterObject $templateParams `
            -WarningAction:SilentlyContinue `
            -ErrorAction:Continue

        While ($result -and -not($result.ProvisioningState -eq 'Succeeded' -or $result.ProvisioningState -eq 'Failed')) {
            Write-Host 'Deployment still running...'
            Start-Sleep 30
            $result = Get-AzSubscriptionDeployment -DefaultProfile $azCtx -Name "$deploymentName"
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
            Write-Host "Successfully deployed '$deploymentName' at '$region '."

            # Save deployment configuration output to file
            if (!(Test-Path -Path "$sourcePath/output")) {
                New-Item -Type Directory -Path  "$sourcePath/output" | Out-Null
            }
            $CdfApplication = [ordered] @{
                IsDeployed    = $true
                Env           = $result.Outputs.applicationEnv.Value
                Tags          = $result.Outputs.applicationTags.Value
                Config        = $result.Outputs.applicationConfig.Value
                Features      = $result.Outputs.applicationFeatures.Value
                ResourceNames = $result.Outputs.applicationResourceNames.Value
                NetworkConfig = $result.Outputs.applicationNetworkConfig.Value
                AccessControl = $result.Outputs.applicationAccessControl.Value
            }

            # Save config file and load as resulting JSON
            $configPath = $OutputDir ? $OutputDir : "$sourcePath/output"
            $configFileName = "application.$platformEnvKey-$applicationEnvKey-$regionCode.json"
            $configOutput = Join-Path -Path $configPath -ChildPath $configFileName

            if (!(Test-Path -Path $configPath)) {
                New-Item -Type Directory -Path  $configPath | Out-Null
            }

            $CdfApplication | ConvertTo-Json -Depth 10 | Out-File $configOutput
            $CdfApplication = Get-Content -Path $configOutput | ConvertFrom-Json -AsHashtable
            $CdfApplication | ConvertTo-Json -Depth 10 | Write-Verbose

            #Save to external config store
            if ($CdfConfig.Platform.Config.configStoreType.ToUpper() -ne 'DEPLOYMENTOUTPUT') {
                $regionDetails = [ordered] @{
                    region = $region
                    code   = $regionCode
                    name   = $regionName
                }
                Save-ConfigToStore `
                    -CdfConfig $CdfConfig `
                    -ScopeConfig $CdfApplication `
                    -Scope 'Application' `
                    -OutputConfigFilePath $configOutput `
                    -EnvKey "$($platformEnvKey)-$($applicationEnvKey)" `
                    -RegionDetails $regionDetails `
                    -ErrorAction Continue
            }

            $CdfConfig.Application = $CdfApplication
            return $CdfConfig
        }
        else {
            Write-Error $result.OutputsString
            Throw "Deployment failed for '$deploymentName' at '$region '. Please check the deployment status on azure portal for details."
        }
    }
    End {
    }
}

