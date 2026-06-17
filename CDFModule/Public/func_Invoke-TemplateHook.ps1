Function Invoke-TemplateHook {
    <#
    .SYNOPSIS
    Runs a template-bundled deployment hook script if present.

    .DESCRIPTION
    Generic CDF extension point: after resolving a template directory, Deploy-CdfTemplate{Platform,
    Application,Domain,Service} can invoke optional pre-/post-deploy PowerShell scripts bundled with
    the template at "<templatePath>/hooks/<pre-deploy|post-deploy>.ps1".

    The hook runs in the CURRENT deployment context (the pipeline runner or the developer's session),
    which for VNet-integrated runners / VPN-connected developers already has private network access
    and the deploy identity's Entra token. This is the lightweight alternative to provisioning
    Azure deploymentScript/ACI resources for post-deployment scripted setup (e.g. SQL grants,
    certificate issuance). The same code path runs identically locally and in CI.

    The hook script receives the resolved CdfConfig (with deployment outputs for post-deploy) and the
    scope, and should declare:  param([object] $CdfConfig, [string] $Scope)
    Hooks must be idempotent and should no-op gracefully when their preconditions aren't met
    (e.g. no private access / not an admin), so local infra-iteration runs don't fail.

    .PARAMETER CdfConfig
    The CDFConfig object for the current scope (Platform/Application/Domain[/Service]).

    .PARAMETER TemplatePath
    The resolved template directory, e.g. "<TemplateDir>/domain/mssql/v1net".

    .PARAMETER Hook
    Which hook to run: 'pre-deploy' (before the ARM deployment) or 'post-deploy' (after success).

    .PARAMETER Scope
    The template scope: Platform | Application | Domain | Service.

    .OUTPUTS
    None. Throws if the hook script exits non-zero or throws.

    .EXAMPLE
    Invoke-CdfTemplateHook -CdfConfig $config -TemplatePath $templatePath -Hook 'post-deploy' -Scope 'Domain'
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [Object] $CdfConfig,
        [Parameter(Mandatory = $true)]
        [string] $TemplatePath,
        [Parameter(Mandatory = $true)]
        [ValidateSet('pre-deploy', 'post-deploy')]
        [string] $Hook,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Platform', 'Application', 'Domain', 'Service')]
        [string] $Scope
    )

    $hookScript = Join-Path -Path $TemplatePath -ChildPath "hooks/$Hook.ps1"
    if (Test-Path -Path $hookScript) {
        Write-Host "CDF: running $Scope $Hook hook -> $hookScript"
        & $hookScript -CdfConfig $CdfConfig -Scope $Scope
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            throw "CDF $Scope $Hook hook failed (exit code $LASTEXITCODE): $hookScript"
        }
    }
    else {
        Write-Verbose "CDF: no $Hook hook found at $hookScript"
    }
}
