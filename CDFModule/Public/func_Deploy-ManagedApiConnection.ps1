Function Deploy-ManagedApiConnection {
    <#
        .SYNOPSIS
        Deploys managed api connection

        .DESCRIPTION
        Deploy Azure resources for managed api connections

        .PARAMETER PlatformId
        Name of the platform instance

        .PARAMETER InstanceId
        Specific id of the platform instance

        .PARAMETER EnvDefinitionId
        Name of the environment configuration.

        .PARAMETER ConnectionId
        The identity of the api connection configuration

        .PARAMETER TemplateDir
        Path to the connection templates module dir. Defaults to "./modules".

        .PARAMETER SourceDir
        Path to the connections config source directory. Defaults to "./connections".

        .INPUTS
        None.

        .OUTPUTS
        Connection configuration hashtable

        .EXAMPLE
        Deploy-ManagedApiConnection -ConnectionName "axia-tms"

        .EXAMPLE
        Deploy-ManagedApiConnection `
            -ConnectionName "axia-tms"
            -TemplateDir ../cdf-infra/connections/modules `
            -SourceDir ../cdf-infra/connections/config

        .LINK

        #>

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [string] $Region = $env:CDF_REGION,
        [Parameter(Mandatory = $false)]
        [string] $PlatformId = $env:CDF_PLATFORM_ID,
        [Parameter(Mandatory = $false)]
        [string] $InstanceId = $env:CDF_PLATFORM_INSTANCE,
        [Parameter(Mandatory = $false)]
        [string] $EnvDefinitionId = $env:CDF_PLATFORM_ENV_ID,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $true)]
        [string] $ConnectionId,
        [Parameter(Mandatory = $false)]
        [string] $TemplateDir = './modules',
        [Parameter(Mandatory = $false)]
        [string] $SourceDir = './connections'
    )
    $haveCdfParameters = $true
    if ([String]::IsNullOrWhiteSpace($Region)) { Write-Error "Missing required CDF Parameter 'Region' or environment variable 'CDF_REGION'"; $haveCdfParameters = $false }
    if ([String]::IsNullOrWhiteSpace($PlatformId)) { Write-Error "Missing required CDF Parameter 'PlatformId' or environment variable 'CDF_PLATFORM_ID'"; $haveCdfParameters = $false }
    if ([String]::IsNullOrWhiteSpace($InstanceId)) { Write-Error "Missing required CDF Parameter 'InstanceId' or environment variable 'CDF_PLATFORM_INSTANCE'"; $haveCdfParameters = $false }
    if ([String]::IsNullOrWhiteSpace($EnvDefinitionId)) { Write-Error "Missing required CDF Parameter 'EnvDefinitionId' or environment variable 'CDF_PLATFORM_ENV_ID'"; $haveCdfParameters = $false }
    if (!$haveCdfParameters) {
        throw("Missing required CDF parameters")
    }

    $cdfPlatform = (Get-CdfConfigPlatform `
            -PlatformId $PlatformId `
            -InstanceId $InstanceId `
            -EnvDefinitionId $EnvDefinitionId `
            -Region $Region `
            -Deployed `
    ).Platform

    # Load configuration
    $apiConfigFile = "$SourceDir/$ConnectionId.$($cdfPlatform.Config.platformId)$($cdfPlatform.Config.instanceId).$EnvDefinitionId.json"
    Write-Verbose "Loading connection configuration file: $apiConfigFile"
    if (Test-Path $apiConfigFile) {
        Write-Verbose "Loading configuration for connection"
        $apiConfig = Get-Content  $apiConfigFile | ConvertFrom-Json -AsHashtable
    }
    else {
        throw "Could not find connection configuration file: $apiConfigFile"
    }

    if ($null -ne $apiConfig.gatewayPlatformId) {
        $dgwPlatform = (Get-CdfConfigPlatform `
                -PlatformId $apiConfig.gatewayPlatformId `
                -InstanceId $apiConfig.gatewayPlatformInstance `
                -EnvDefinitionId $apiConfig.gatewayPlatformEnvDefinitionId `
                -Region $apiConfig.gatewayPlatformRegion `
                -Deployed `
        ).Platform
    }

    # This deployment name follows a standard that is also used by platform, application and domain templates
    $platformKey = "$($cdfPlatform.Config.platformId)$($cdfPlatform.Config.instanceId)"
    $deploymentName = "$platformKey-connection-$($apiConfig.name)"

    $templateFile = "$TemplateDir/dgw-connections/$($apiConfig.type).bicep"

    # Setup platform parameters from envrionment and params file
    $templateParams = [ordered] @{}

    $templateParams.platformEnv = $cdfPlatform.Env
    $templateParams.platformConfig = $cdfPlatform.Config
    $templateParams.platformFeatures = $cdfPlatform.Features
    $templateParams.platformAccessControl = $cdfPlatform.AccessControl
    $templateParams.platformNetworkConfig = $cdfPlatform.NetworkConfig
    $templateParams.platformResourceNames = $cdfPlatform.ResourceNames

    $templateParams.connectionTags = @{} # TODO: Implement default configurable service tags or inherit domain default tags??
    $templateParams.connectionTags.BuildCommit = $env:GITHUB_SHA ?? $env:BUILD_SOURCEVERSION ?? $(git -C $TemplateDir rev-parse --short HEAD)
    $templateParams.connectionTags.BuildRun = $env:GITHUB_RUN_ID ?? $env:BUILD_BUILDNUMBER ?? "local"
    $templateParams.connectionTags.BuildBranch = $env:GITHUB_REF_NAME ?? $env:BUILD_SOURCEBRANCH ?? $(git -C $TemplateDir branch --show-current)
    $templateParams.connectionTags.BuildRepo = $env:GITHUB_REPOSITORY ?? $env:BUILD_REPOSITORY_NAME ?? $(Split-Path -Leaf (git -C $TemplateDir remote get-url origin))

    $templateParams.connectionId = $apiConfig.id
    $templateParams.connectionName = $apiConfig.name
    $templateParams.connectionDisplayName = $apiConfig.displayName

    if ($null -ne $dgwPlatform ) {
        $templateParams.dataGatewayId = $dgwPlatform.Config.platformDataGateway.dataGatewayResourceId
        $templateParams.dataGatewayName = $dgwPlatform.Config.platformDataGateway.dataGatewayName
        $templateParams.dataGatewayRGName = $dgwPlatform.ResourceNames.platformResourceGroupName
    }

    # Add connection template specific settings
    $templateParams.templateSettings = $apiConfig.templateSettings

    if ($apiConfig.templateSettings.openApiSpecJsonFile) {
        $openApiSpecDoc = Get-Content -Path  "$SourceDir/$($apiConfig.templateSettings.openApiSpecJsonFile)" | ConvertFrom-Json -AsHashtable
        $templateParams.templateSettings.openApiSpec = $openApiSpecDoc
    }

    Write-Verbose "Template parameters: $($templateParams | ConvertTo-Json -Depth 10 | Out-String)"
    Write-Verbose "Deploying to resource group: $($cdfPlatform.ResourceNames.apiConnResourceGroupName)"

    $azCtx = Get-CdfAzureContext -SubscriptionId $cdfPlatform.Env.subscriptionId

    Write-Host "Starting deployment of '$deploymentName' at '$Region' using subscription [$($AzCtx.Subscription.Name)]."
    $result = New-AzResourceGroupDeployment `
        -DefaultProfile $azCtx `
        -Name $deploymentName `
        -ResourceGroupName $cdfPlatform.ResourceNames.apiConnResourceGroupName `
        -TemplateFile $templateFile `
        -TemplateParameterObject $templateParams `
        -WarningAction:SilentlyContinue

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
        $ConnectionConfig = ($result.Outputs | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable)
        $ConnectionConfig | ConvertTo-Json -Depth 10 | Write-Verbose
        return $ConnectionConfig.connectionConfig.Value
    }
    else {
        Write-Error $result.OutputsString
        Throw "Deployment failed for '$deploymentName' at '$Region'. Please check the deployment status on azure portal for details."
    }
}
