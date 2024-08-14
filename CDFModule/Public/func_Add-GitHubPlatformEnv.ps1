
Function Add-GitHubPlatformEnv {
    <#
    .SYNOPSIS
    Add or update GitHub Platform Repository environment settings.

    .DESCRIPTION
    Configures GitHub platform Repository with environment secrets and variables.
    
    .PARAMETER PlatformEnv
    Name of the environment configuration.
    
    .PARAMETER PlatformId
    Name of the platform instance
    
    .PARAMETER PlatformInstanceId
    Specific id of the platform instance

    .PARAMETER Repository
    The GitHub Repository <account/org>/<Repository name>
    
    .INPUTS
    None. You cannot pipe objects.

    .OUTPUTS
    CdfPlatform

    .EXAMPLE
    PS> Add-CdfGitHubPlatformEnv `
        -PlatformId "capim" `
        -PlatformInstanceId "01" `
        -PlatformEnvDefinitionId "intg-dev" `
        -Repository "Epical-Integration/apim-infra" `

    .LINK
    Deploy-CdfTemplatePlatform
    Deploy-CdfTemplateApplication
    Deploy-CdfTemplateDomain

    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Region,
        [Parameter(Mandatory = $true)]
        [string] $PlatformEnvDefinitionId,
        [Parameter(Mandatory = $true)]
        [string] $PlatformId,
        [Parameter(Mandatory = $true)]
        [string] $PlatformInstanceId,
        [Parameter(Mandatory = $true)]
        [string] $Repository,
        [Parameter(Mandatory = $false)]
        [string] $InfraRootDir = "."
    )

    Begin {
        $CdfPlatform = Get-CdfConfigPlatform `
            -Region $Region `
            -PlatformId $PlatformId `
            -PlatformInstanceId $PlatformInstanceId `
            -PlatformEnvDefinitionId $PlatformEnvDefinitionId `
            -Region $Region `
            -InfraRoot $InfraRootDir
    }
    Process {
        gh api --method PUT -H "Accept: application/vnd.github+json" repos/$Repository/environments/$PlatformEnvDefinitionId
        gh variable set PLATFORM_ENV_ID --repo $Repository --env $PlatformEnvDefinitionId --body $CdfPlatform.Env.nameId
        gh variable set PLATFORM_ENV_NAME --repo $Repository --env $PlatformEnvDefinitionId --body $CdfPlatform.Env.name
        gh variable set PLATFORM_ENV_PURPOSE --repo $Repository --env $PlatformEnvDefinitionId --body $CdfPlatform.Env.purpose
        gh variable set PLATFORM_ENV_QUALITY --repo $Repository --env $PlatformEnvDefinitionId --body $CdfPlatform.Env.quality
        gh variable set PLATFORM_TENANT_ID --repo $Repository --env $PlatformEnvDefinitionId --body $CdfPlatform.Env.tenantId

        gh variable set PLATFORM_SUBSCRIPTION_ID --repo $Repository --env $PlatformEnvDefinitionId --body $CdfPlatform.Env.subscriptionId
        gh variable set PLATFORM_DEPLOY_TENANT_ID --repo $Repository --env $PlatformEnvDefinitionId --body $CdfPlatform.Env.deployAppTenantId
        gh variable set PLATFORM_DEPLOY_CLIENT_ID --repo $Repository --env $PlatformEnvDefinitionId --body $CdfPlatform.Env.deployAppClientId
    }
    End {
        $CdfPlatform
    }
}


