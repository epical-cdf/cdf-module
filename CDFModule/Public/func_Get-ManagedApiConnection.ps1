Function Get-ManagedApiConnection {
    <#
        .SYNOPSIS
        Deploys managed api connection

        .DESCRIPTION
        Deploy Azure resources for managed api connections

        .PARAMETER CdfConfig
        The CDFConfig object that holds the current scope configurations (Platform, Application and Domain)

        .PARAMETER ConnectionKey
        The key name of the api connection configuration

        .PARAMETER TemplateDir
        Path to the connection templates module dir. Defaults to "./modules".

        .PARAMETER SourceDir
        Path to the connections config source directory. Defaults to "./connections".

        .INPUTS
        None.

        .OUTPUTS
        Connection configuration hashtable

        .EXAMPLE
        Get-ManagedApiConnection -ConnectionName "axia-tms"

        .EXAMPLE
        Get-ManagedApiConnection `
            -ConnectionName "External"
            -TemplateDir ../cdf-infra/connections/modules `
            -SourceDir ../cdf-infra/connections/config

        .LINK

        #>

    [CmdletBinding()]
    Param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [Object]$CdfConfig,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $true)]
        [string] $ConnectionKey,
        [Parameter(Mandatory = $false)]
        [string] $TemplateDir = './modules',
        [Parameter(Mandatory = $false)]
        [string] $SourceDir = './connections'
    )

    # This deployment name follows a standard that is also used by platform, application and domain templates
    $platformKey = "$($CdfConfig.Platform.Config.platformId)$($CdfConfig.Platform.Config.instanceId)"
    $applicationKey = "$($CdfConfig.Application.Config.applicationId)$($CdfConfig.Application.Config.instanceId)"
    $domainName = $CdfConfig.Domain.Config.domainName

    if ($ConnectionKey.ToLower().StartsWith('domain')) {
        $deploymentName = "$platformKey-$applicationKey-$domainName-connection-$ConnectionKey"
    }
    elseif ($ConnectionKey.ToLower().StartsWith('application')) {
        $deploymentName = "$platformKey-$applicationKey-connection-$ConnectionKey"
    }
    else {
        $deploymentName = "$platformKey-connection-$ConnectionKey"
    }

    Write-Verbose "Fetch deployment from resource group: $($CdfConfig.Platform.ResourceNames.apiConnResourceGroupName)"
    $azCtx = Get-AzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId

    Write-Verbose "Get deployment for '$deploymentName' at '$($CdfConfig.Platform.Env.region)' using subscription [$($AzCtx.Subscription.Name)]."
    $result = Get-AzResourceGroupDeployment `
        -DefaultProfile $azCtx `
        -Name $deploymentName `
        -ResourceGroupName $CdfConfig.Platform.ResourceNames.apiConnResourceGroupName `
        -WarningAction:SilentlyContinue

    $result | ConvertTo-Json -Depth 10 | Write-Verbose

    While ($result -and -not($result.ProvisioningState -eq 'Succeeded' -or $result.ProvisioningState -eq 'Failed')) {
        Write-Verbose 'Deployment still running...'
        Start-Sleep 30
        $result = Get-AzSubscriptionDeployment -DefaultProfile $azCtx -Name "$deploymentName"
        Write-Verbose $result
    }

    if ($result -and $result.ProvisioningState -eq 'Succeeded') {
        Write-Verbose "Successfully fetched deployment '$deploymentName' at '$($CdfConfig.Platform.Env.region)'."
        $ConnectionConfig = ($result.Outputs | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable)
        $ConnectionConfig | ConvertTo-Json -Depth 10 | Write-Verbose
        return $ConnectionConfig.connectionConfig.Value
    }
}
