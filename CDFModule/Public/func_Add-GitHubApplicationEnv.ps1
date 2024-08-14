Function Add-GitHubApplicationEnv {
    <#
    .SYNOPSIS
    Add or update GitHub Domain Repository environment settings.

    .DESCRIPTION
    Configures GitHub domain repository with environment secrets and variables.

    .PARAMETER Repository
    The GitHub Repository <account/org>/<Repository name>

    .PARAMETER PlatformEnv
    Name of the platfornm environment configuration.
    
    .PARAMETER PlatformId
    Name of the platform instance
    
    .PARAMETER PlatformInstanceId
    Specific id of the appliction instance

    .PARAMETER ApplicationEnv
    Name of the application environment configuration.
    
    .PARAMETER ApplicationInstanceId
    Specific id of the application instance

    .INPUTS
    None. You cannot pipe objects.

    .OUTPUTS
    None.

    .EXAMPLE
    PS> Add-CdfGitHubDomainEnv `
        -Repository "Epical-Integration/apim-domain-sales"  `
        -PlatformEnv "dev" -PlatformId "capim" -PlatformInstanceId "01"  `
        -ApplicationEnv "dev"  `
        -ApplicationInstanceId "01"

    .EXAMPLE
    PS> Add-CdfGitHubDomainEnv  `
        -Repository "Epical-Integration/apim-domain-ops"  `
        -PlatformEnv "dev" -PlatformId "capim"  `
        -PlatformInstanceId "01"  `
        -ApplicationEnv "dev"  `
        -ApplicationInstanceId "01"

    .LINK
    Deploy-CdfTemplatePlatform
    Deploy-CdfTemplateApplication
    Deploy-CdfTemplateDomain

    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Repository,
        [Parameter(Mandatory = $true)]
        [string] $PlatformEnv,
        [Parameter(Mandatory = $true)]
        [string] $PlatformId,
        [Parameter(Mandatory = $true)]
        [string] $PlatformInstanceId,
        [Parameter(Mandatory = $true)]
        [string] $ApplicationEnv,
        [Parameter(Mandatory = $true)]
        [string] $ApplicationInstanceId
    )

    # Fetch application definitions
    $sourcePath = "src/$PlatformId/$PlatformInstanceId"
    $envFile = "$sourcePath/application/environments.json"
    Write-Host "Load environment from '$envFile'"
    $appEnvs = Get-Content -Raw "$envFile" | ConvertFrom-Json -AsHashtable

    # Setup environment
    $appEnv = $appEnvs[$ApplicationEnv]
    gh api --method PUT -H "Accept: application/vnd.github+json" repos/$Repository/environments/$ApplicationEnv
    gh variable set APPLICATION_ENV_ID --repo $Repository --env $ApplicationEnv --body $appEnv.nameId
    gh variable set APPLICATION_ENV_NAME --repo $Repository --env $ApplicationEnv --body $appEnv.name
    gh variable set APPLICATION_ENV_PURPOSE --repo $Repository --env $ApplicationEnv --body $appEnv.purpose
    gh variable set APPLICATION_ENV_QUALITY --repo $Repository --env $ApplicationEnv --body $appEnv.quality
    gh variable set APPLICATION_TENANT_ID --repo $Repository --env $ApplicationEnv --body $appEnv.tenantId

    # gh variable set APPLICATION_SUBSCRIPTION_ID --repo $Repository --env $ApplicationEnv --body $appEnv.subscriptionId
    gh variable set APPLICATION_DEPLOY_TENANT_ID --repo $Repository --env $ApplicationEnv --body $appEnv.deployAppTenantId
    gh variable set APPLICATION_DEPLOY_CLIENT_ID --repo $Repository --env $ApplicationEnv --body $appEnv.deployAppClientId

}
