Function Deploy-StorageAccountConfig {
    <#
        .SYNOPSIS
        Deploy storage account containers, file shares, queues and tables

        .DESCRIPTION
        The cmdlet makes token substitution for the config scope environment.
        Then deploys the containers, file shares, queues and tables for the storage account resource.

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
        Deploy-CdfStorageAccountConfig `
            -CdfConfig $config `
            -ServiceName "myservice" `
            -ServiceType "logicapp-standard" `
            -ServiceGroup "demo}" `
            -ServiceTemplate "la-sample" `
            -InputPath "./la-<name>" `
            -OutputPath "./build"

        .LINK
        Deploy-CdfTemplateService
        .LINK
        Get-CdfGitHubServiceConfig
        .LINK
        Deploy-CdfServiceBusConfig

    #>

    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
        [Object]$CdfConfig,
        [Parameter(Mandatory = $false)]
        [string] $InputPath = ".",
        [Parameter(Mandatory = $false)]
        [string] $OutputPath = "../tmp/$($CdfConfig.Service.Config.serviceName)",
        [Parameter(Mandatory = $false)]
        [string] $SharedDir = $env:CDF_SHARED_SOURCE_PATH ?? '.',
        [Parameter(Mandatory = $false)]
        [string] $TemplateDir = "$SharedDir/modules/storageaccount-config"

    )

    Begin {
    }
    Process {
        Write-Host "Preparing Storage Account configuration deployment."

        # Substitute Tokens for the config file
        $tokenValues = $CdfConfig | Get-TokenValues
        Update-ConfigFileTokens `
            -InputFile $InputPath/storageaccount.config.json `
            -OutputFile $OutputPath/storageaccount.config.$($CdfConfig.Application.Env.nameId).json `
            -Tokens $tokenValues `
            -StartTokenPattern '{{' `
            -EndTokenPattern '}}' `
            -NoWarning `
            -WarningAction:SilentlyContinue

        $storageAccountConfig = Get-Content -Path "$OutputPath/storageaccount.config.$($CdfConfig.Application.Env.nameId).json" | ConvertFrom-Json -AsHashtable

        # TODO: Standardize names e.g. table names to make sure naming conventions are followed by removing dashes and underscores.


        # TODO: add named instance in scope e.g. option to have more than one storage account in scope
        #  {
        #     "scope": "application",
        #     "instance": "ServiceBusExternal",
        #     ...
        #  }
        #  $serviceBusRG = $CdfConfig.Platform.Config[$serviceBusConfig.instance].resourceGroup
        #  $serviceBusName = $CdfConfig.Platform.Config[$serviceBusConfig.instance].name

        switch ($storageAccountConfig.scope) {
            'platform' {
                $storageAccountRG = $CdfConfig.Platform.Config.platformStorageAccount.resourceGroup
                $storageAccountName = $CdfConfig.Platform.Config.platformStorageAccount.name
            }
            'application' {
                $storageAccountRG = $CdfConfig.Application.Config.applicationStorageAccount.resourceGroup
                $storageAccountName = $CdfConfig.Application.Config.applicationStorageAccount.name
            }
            'domain' {
                $storageAccountRG = $CdfConfig.Domain.Config.domainStorageAccount.resourceGroup
                $storageAccountName = $CdfConfig.Domain.Config.domainStorageAccount.name
            }
        }

        Write-Verbose "storageAccountRG: $storageAccountRG"
        Write-Verbose "storageAccountName: $storageAccountName"
        Write-Debug "storageAccountConfig: $($storageAccountConfig | ConvertTo-Json -Depth 10)"

        # Setup template parameter values
        $templateParams = [ordered] @{}
        $templateParams.domainName = $CdfConfig.Domain.Config.domainName
        $templateParams.serviceName = $CdfConfig.Service.Config.serviceName
        $templateParams.storageAccountName = $storageAccountName
        # Could use default parameter in bicep template, but this construct allows for programatic configuration changes.
        $templateParams.storageAccountConfig = $storageAccountConfig

        $applicationEnvKey = "$($CdfConfig.Application.Config.applicationId ?? $CdfConfig.Application.Config.templateName)$($CdfConfig.Application.Config.applicationInstanceId)$($CdfConfig.Application.Env.nameId)"
        $deploymentName = "st-cfg-$($CdfConfig.Service.Config.serviceName)-$($CdfConfig.Domain.Config.domainName)-$storageAccountName-$applicationEnvKey-$($CdfConfig.Application.Env.regionCode)"
        $azCtx = Get-AzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId

        Write-Host "Starting deployment of '$deploymentName' using subscription [$($azCtx.Subscription.Name)]."

        $result = New-AzResourceGroupDeployment `
            -DefaultProfile $azCtx `
            -Name $deploymentName `
            -ResourceGroupName $storageAccountRG `
            -TemplateFile "$TemplateDir/main.bicep" `
            -TemplateParameterObject $templateParams `
            -WarningAction:SilentlyContinue

        if ( -not $? ) {
            $msg = $Error[0].Exception.Message
            throw "Encountered error during deployment. Error Message is $msg."
        }

        if ($result.ProvisioningState = 'Succeeded') {
            Write-Host "Successfully deployed '$deploymentName' at resource group '$storageAccountRG'."
        }
        else {
            Write-Error $result.OutputsString
            Throw "Deployment failed for '$deploymentName' resource group '$storageAccountRG'. Please check the deployment status on azure portal for details."
        }
    }
    End {
    }
}
