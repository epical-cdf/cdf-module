Function Deploy-ServiceBusConfig {
    <#
    .SYNOPSIS
    Deploy service bus queues, topics and subscriptions
    
    .DESCRIPTION
    The cmdlet makes token substitution for the Platform config environment.
    Then deploys the service bus queues, topics and subscriptions for the service bus resource.
    
    .PARAMETER CdfConfig
    The CDFConfig object that holds the current scope configurations (Platform, Application and Domain)

    .PARAMETER InputPath
    The deployment package path, where servicebus.config.json is located.
    Optional, defaults to "./build"
    
    .PARAMETER OutputPath
    Output path for the environment specific config file servicebus.config.<env nameId>.json
    Optional, defaults to "./build"

    .PARAMETER TemplateDir
    Path to the bicep template folder where main.bicep is found. Defaults to ".".

    .INPUTS
    None. You cannot pipe objects.

    .OUTPUTS
    None.

    .EXAMPLE
    Deploy-CdfServiceBusConfig `
        -CdfConfig $config `
        -ServiceName "svcdemo01" `
        -ServiceType "la-sample" `
        -ServiceGroup "demo" `
        -ServiceTemplate "logicapp-standard" `
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
        [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
        [Object]$CdfConfig,
        [Parameter(Mandatory = $false)]
        [string] $InputPath = ".",
        [Parameter(Mandatory = $false)]
        [string] $OutputPath,
        [Parameter(Mandatory = $false)]
        [string] $SharedDir = $env:CDF_SHARED_SOURCE_PATH ?? '.',
        [Parameter(Mandatory = $false)]
        [string] $TemplateDir = "$SharedDir/modules/servicebus-config"
    )

    Begin {
        if (!$OutputPath) {
            $OutputPath = "../tmp/$($CdfConfig.Service.Config.serviceName)"
        }
    }
    Process {
        Write-Host "Preparing Service Bus configuration deployment."
  
        # Substitute Tokens for the config file
        $tokenValues = $CdfConfig | Get-TokenValues
        Update-ConfigFileTokens `
            -InputFile $InputPath/servicebus.config.json `
            -OutputFile $OutputPath/servicebus.config.$($CdfConfig.Application.Env.nameId).json `
            -Tokens $tokenValues `
            -StartTokenPattern '{{' `
            -EndTokenPattern '}}' `
            -NoWarning `
            -WarningAction:SilentlyContinue 

        # TODO: Validate/normalize names e.g. queus and topic names to make sure naming conventions are followed


        # TODO: add named instance in scope e.g. option to have more than one service bus in scope
        #  {
        #     "scope": "platform",
        #     "instance": "platformServiceBusExternal",
        #     ...
        #  }
        #  $serviceBusRG = $CdfConfig.Platform.Config[$serviceBusConfig.instance].resourceGroup
        #  $serviceBusName = $CdfConfig.Platform.Config[$serviceBusConfig.instance].name

        if (Test-Path "$OutputPath/servicebus.config.$($CdfConfig.Application.Env.nameId).json") {
            $serviceBusConfig = Get-Content -Path "$OutputPath/servicebus.config.$($CdfConfig.Application.Env.nameId).json" | ConvertFrom-Json -AsHashtable
        }
        else {
            $serviceBusConfig = Get-Content -Path "$OutputPath/servicebus.config.json" | ConvertFrom-Json -AsHashtable
        }
        switch ($serviceBusConfig.scope) {
           
            'platform' {
                $serviceBusRG = $CdfConfig.Platform.Config.platformServiceBus.resourceGroup
                $serviceBusName = $CdfConfig.Platform.Config.platformServiceBus.name
            }
            'application' {
                $serviceBusRG = $CdfConfig.Application.Config.platformServiceBus.resourceGroup
                $serviceBusName = $CdfConfig.Application.Config.platformServiceBus.name
            }
            'domain' {
                $serviceBusRG = $CdfConfig.Domain.Config.platformServiceBus.resourceGroup
                $serviceBusName = $CdfConfig.Domain.Config.platformServiceBus.name
            }
        }

        # $serviceBusRG = $CdfConfig.Platform.ResourceNames.infraResourceGroupName
        # $serviceBusName = $CdfConfig.Platform.ResourceNames.serviceBusName

        Write-Verbose "serviceBusRG: $serviceBusRG"
        Write-Verbose "serviceBusName: $serviceBusName"
        Write-Debug "serviceBusConfig: $($serviceBusConfig | ConvertTo-Json -Depth 10)"

        # Setup template parameter values
        $templateParams = [ordered] @{}
        $templateParams.domainName = $CdfConfig.Domain.Config.domainName
        $templateParams.serviceName = $CdfConfig.Service.Config.serviceName
        $templateParams.serviceBusName = $serviceBusName
        # Could use default parameter in bicep template, but this construct allows for programatic configuration changes.
        $templateParams.serviceBusConfig = $serviceBusConfig 

        $applicationEnvKey = "$($CdfConfig.Application.Config.templateName)$($CdfConfig.Application.Config.applicationInstanceId)$($CdfConfig.Application.Env.nameId)"
        $deploymentName = "sb-cfg-$($CdfConfig.Service.Config.serviceName)-$($CdfConfig.Domain.Config.domainName)-$serviceBusName-$applicationEnvKey-$($CdfConfig.Application.Env.regionCode)"
        $azCtx = Get-AzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId

        Write-Host "Starting deployment of '$deploymentName' using subscription [$($azCtx.Subscription.Name)]."

        $result = New-AzResourceGroupDeployment `
            -DefaultProfile $azCtx `
            -Name $deploymentName `
            -ResourceGroupName $serviceBusRG `
            -TemplateFile "$TemplateDir/main.bicep" `
            -TemplateParameterObject $templateParams `
            -WarningAction:SilentlyContinue

        if ( -not $? ) {
            $msg = $Error[0].Exception.Message
            throw "Encountered error during deployment. Error Message is $msg."
        }

        if ($result.ProvisioningState = 'Succeeded') {
            Write-Host "Successfully deployed '$deploymentName' at resource group '$serviceBusRG'."
        }
        else {
            Write-Error $result.OutputsString
            Throw "Deployment failed for '$deploymentName' resource group '$serviceBusRG'. Please check the deployment status on azure portal for details."
        }
    }
    End {
    }
}
