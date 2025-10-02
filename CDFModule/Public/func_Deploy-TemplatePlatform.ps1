Function Deploy-TemplatePlatform {
    <#
    .SYNOPSIS
    Deploys a platform template for given instance configuration

    .DESCRIPTION
    Deploy Azure resources for a platform template and configuration.

    .PARAMETER CdfConfig
    Instance configuration

    .PARAMETER Deployed
    Override check on configuration 'IsDeployed' to force deployment of deployed configuration

    .PARAMETER TemplateDir
    Path to the platform template root dir. Defaults to ".".

    .PARAMETER SourceDir
    Path to the platform instance source directory. Defaults to "./src".

    .INPUTS
    CdfConfig

    .OUTPUTS
    Updated CDFConfig and json config files at SourceDir


    .EXAMPLE
    New-CdfConfigPlatform ... | Deploy-CdfTemplatePlatform `
        -CdfConfig $CdfConfig

    .EXAMPLE
    $CdfConfig = Get-CdfConfigPlatform ...
    $UpdatedCdfConfig = Deploy-CdfTemplatePlatform `
        -CdfConfig $CdfConfig `
        -TemplateDir ../cdf-infra/templates `
        -SourceDir ../cdf-infra/instances

    .LINK
    Deploy-CdfTemplateApplication
    .LINK
    Remove-CdfTemplatePlatform

    #>

    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [Object]$CdfConfig,
        [Parameter(Mandatory = $false)]
        [switch] $Deployed,
        [Parameter(Mandatory = $false)]
        [string] $ExportParametersPath,
        [Parameter(Mandatory = $false)]
        [bool] $DryRun = $false,
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
        if ($CdfConfig.Platform.IsDeployed -eq $true -and !$Deployed) {
            $errMsg = 'Provided platform configuration is a deployed version. If this is intended, use parameter switch -Deployed to override this check. Using deployed version for deployments may impact negatively on template functionality.'
            Write-Error -Message $errMsg
            throw $errMsg
        }
        # Fetch platform definitions
        $templatePath = "$TemplateDir/platform/$($CdfConfig.Platform.Config.templateName)/$($CdfConfig.Platform.Config.templateVersion)"
        $sourcePath = "$SourceDir/$($CdfConfig.Platform.Config.platformId)/$($CdfConfig.Platform.Config.instanceId)"

        # TODO: replace with regionCode/regionName parameters, see below
        $regionNames = Get-Content -Raw "$sourcePath/platform/regionnames.json" | ConvertFrom-Json -AsHashtable
        $regionCodes = Get-Content -Raw "$sourcePath/platform/regioncodes.json" | ConvertFrom-Json -AsHashtable

        # Setup deployment variables from configuration
        # TODO: Verify validitity of environment/EnvDefinitionId
        $region = $CdfConfig.Platform.Env.region.toLower()
        $regionCode = $regionCodes[$region]
        $regionName = $regionNames[$regionCode]

        $platformEnvKey = "$($CdfConfig.Platform.Config.platformId)$($CdfConfig.Platform.Config.instanceId)$($CdfConfig.Platform.Env.nameId)"
        $templateFile = "$templatePath/platform.bicep"
        $deploymentName = "platform-$platformEnvKey-$regionCode"

        # Setup CDF template parameters for the Platform deployment
        $templateParams = [ordered] @{}
        $templateParams.platformEnv = $CdfConfig.Platform.Env
        $templateParams.platformConfig = $CdfConfig.Platform.Config
        $templateParams.platformFeatures = $CdfConfig.Platform.Features
        $templateParams.platformNetworkConfig = $CdfConfig.Platform.NetworkConfig ?? @{}
        $templateParams.platformAccessControl = $CdfConfig.Platform.AccessControl ?? @{}

        $templateParams.platformTags = $CdfConfig.Platform.Tags ?? @{}
        $templateParams.platformTags.BuildCommit = $env:GITHUB_SHA ?? $env:BUILD_SOURCEVERSION ?? $(git -C $TemplateDir rev-parse --short HEAD)
        $templateParams.platformTags.BuildRun = $env:GITHUB_RUN_ID ?? $env:BUILD_BUILDNUMBER ?? "local"
        $templateParams.platformTags.BuildBranch = $env:GITHUB_REF_NAME ?? $env:BUILD_SOURCEBRANCH ?? $(git -C $TemplateDir branch --show-current)
        $templateParams.platformTags.BuildRepo = $env:GITHUB_REPOSITORY ?? $env:BUILD_REPOSITORY_NAME ?? $(Split-Path -Leaf (git -C $TemplateDir remote get-url origin))

        # Add settings from the enterprise configuration for the spoke network / landing zone
        if ( $CdfConfig.Platform.SpokeNetworkConfig ) { $templateParams.enterpriseSpokeConfig = $CdfConfig.Platform.SpokeNetworkConfig }

        # Add Public IP of Host for Postgres
        #if ( $CdfConfig.Platform.Features.enablePostgres ) {$templateParams.buildAgentIP = (Invoke-WebRequest ifconfig.me/ip).Content } else {$templateParams.buildAgentIP = ''}
        # TODO: Standardize this ugly workaround to provide DevOps Build Env Token
        if ( $env:PLATFORM_BUILDAGENT_PAT ) {
            $templateParams.platformEnv.platformDeploymentAccessToken = $env:PLATFORM_BUILDAGENT_PAT
        }

        if ($ExportParametersPath) {
            $deploymentParams = [ordered] @{
                'schema'        = "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#"
                'contenVersion' = "1.0.0.0"
                'parameters' = [ordered] @{
                }
            }
            $templateParams.Keys | ForEach-Object {
                $deploymentParams.parameters[$_] = @{
                        value = $templateParams[$_]
                }
            }
            $deploymentParams | ConvertTo-Json -Depth 10 | Out-File -FilePath $ExportParametersPath -Force
            Write-Host "Exported platform parameters to $ExportParametersPath"
            return;
        }
        else {
            Write-Debug "Template parameters: $($templateParams | ConvertTo-Json -Depth 10 | Out-String)"
        }

        $azCtx = Get-AzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId

        # Deploy bicep template using parameters object
        Write-Host "Starting deployment of '$deploymentName' at '$region' using subscription [$($azCtx.Subscription.Name)] for runtime environment '$($CdfConfig.Platform.Env.name)'."
        $result = New-AzSubscriptionDeployment `
            -DefaultProfile $azCtx `
            -Name $deploymentName `
            -Location $region `
            -TemplateFile $templateFile `
            -TemplateParameterObject $templateParams `
            -WarningAction:SilentlyContinue `
            -ErrorAction:Continue

        While ($result -and -not ($result.ProvisioningState -eq 'Succeeded' -or $result.ProvisioningState -eq 'Failed')) {
            Write-Host "Deployment still running..."
            Start-Sleep 30
            $result = Get-AzSubscriptionDeployment -DefaultProfile $azCtx -Name "$deploymentName"
            if ($result.ProvisioningState -eq 'Succeeded' -or $result.ProvisioningState -eq 'Failed') {
                break;
            }
        }

        if ( -not $? -or ($null -eq $result.Outputs) ) {
            Write-Error "Deployment failed."
            if (($null -ne $Error) -and ($null -ne $Error)) {
                Write-Error "Error messages are:"
                $Error
                foreach ($errorDetail in $Error) {
                    if (($null -ne $errorDetail)) {
                        Write-Error $errorDetail.Exception.Message
                    }
                }
            }
            Write-Error "Operation error messages are:"
            $errors = Get-AzDeploymentOperation `
                -DefaultProfile $azCtx `
                -DeploymentName $deploymentName `
            | Where-Object -FilterScript { $_.ProvisioningState -eq 'Failed' }
            foreach ($err in $errors) {
                Write-Error "Error [$( $err.StatusCode)] Message [$( $err.StatusMessage)]"
            }
            throw "Deployment failed, see error output or deployment status on Azure Portal"
        }

        if ($result.ProvisioningState -eq 'Succeeded') {
            Write-Host "Successfully deployed '$deploymentName' at '$region '."

            # Save deployment configuration output to file
            if (!(Test-Path -Path "$sourcePath/output")) {
                New-Item -Type Directory -Path  "$sourcePath/output" | Out-Null
            }
            $CdfPlatform = [ordered] @{
                IsDeployed    = $true
                Env           = $result.Outputs.platformEnv.Value
                Tags          = $result.Outputs.platformTags.Value
                Config        = $result.Outputs.platformConfig.Value
                Features      = $result.Outputs.platformFeatures.Value
                ResourceNames = $result.Outputs.platformResourceNames.Value
                NetworkConfig = $result.Outputs.platformNetworkConfig.Value
                AccessControl = $result.Outputs.platformAccessControl.Value
            }

            # Save config file and load as resulting JSON
            $configPath = $OutputDir ? $OutputDir : "$sourcePath/output"
            $configFileName = "platform.$platformEnvKey-$regionCode.json"
            $configOutput = Join-Path -Path $configPath -ChildPath $configFileName

            if (!(Test-Path -Path $configPath)) {
                New-Item -Type Directory -Path  $configPath | Out-Null
            }

            $CdfPlatform | ConvertTo-Json -depth 10 | Out-File $configOutput
            $CdfPlatform | ConvertTo-Json -Depth 10 | Write-Verbose
            $CdfPlatform = Get-Content -Path $configOutput | ConvertFrom-Json -AsHashtable

            #Save to external config store
            if ($CdfConfig.Platform.Config.configStoreType) {
                $regionDetails = [ordered] @{
                    region = $region
                    code   = $regionCode
                    name   = $regionName
                }
                Save-ConfigToStore `
                    -CdfConfig $CdfConfig `
                    -ScopeConfig $CdfPlatform `
                    -Scope 'Platform' `
                    -OutputConfigFilePath $configOutput `
                    -EnvKey $platformEnvKey `
                    -RegionDetails $regionDetails `
                    -ErrorAction Continue
            }
            $CdfConfig = [ordered] @{
                Platform = $CdfPlatform
            }
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
