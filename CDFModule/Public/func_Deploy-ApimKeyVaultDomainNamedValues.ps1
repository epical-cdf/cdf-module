Function Deploy-ApimKeyVaultDomainNamedValues {
    <#
    .SYNOPSIS

    Deploys named values to the the Apim domain keyvault

    .DESCRIPTION

    This cmdlet reads GitHub variables and secrets in the domain repository and stores them in the APIM domain keyvault as secrets.
    These keyvault secrets are referenced from the domain named values bicep templates.

    .PARAMETER CdfConfig
    Instance config

    .PARAMETER DomainName
    Domain name of the service as provided in workflow inputs

    .PARAMETER ConfigPath
    File system root path to the service's artifact build contents

    .INPUTS
    None. You cannot pipe objects.

    .OUTPUTS
    None. Writes compiled policies.

    .EXAMPLE
    PS> $config | Deploy-ApimKeyVaultDomainNamedValues `
        -DomainName "testdom1" `
        -ConfigPath "."

    .LINK
    Build-ApimDomainNamedValuesTemplate

    #>

    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [hashtable] $CdfConfig,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $DomainName = $env:CDF_DOMAIN_NAME,
        [Parameter(Mandatory = $true)]
        [string] $ConfigPath
    )

    if ($false -eq (Test-Path "$ConfigPath")) {
        Write-Verbose "No domain named values configuration - returning"
        return
    }


    #######################################
    # Constants
    ######################################
    $ConstantsFile = Resolve-Path "$ConfigPath/constants.json"
    if (!$null -eq $ConstantsFile) {
        $cdfSchemaPath = Join-Path -Path $MyInvocation.MyCommand.Module.ModuleBase -ChildPath 'Resources/Schemas/cdf-apim-nv-constants.schema.json'
        if (!(Test-Json -SchemaFile "$cdfSchemaPath" -Path $ConstantsFile)) {
            Write-Error "APIM Constant Named Values configuration file did not validate. Please check errors above and correct."
            Write-Error "File path:  $ConstantsFile"
        }
        else {
            $Constants = Get-Content -Path $ConstantsFile | ConvertFrom-Json -AsHashtable

            foreach ($NamedValue in $Constants) {
                Write-Host "Processing constant with keyvault name: $($NamedValue.kvSecretName)"
                if (!$NamedValue.kvSecretName.StartsWith("$DomainName-", 'CurrentCultureIgnoreCase')) {
                    Write-Error 'Domain constants must have keyvault secret names starting with domain name. <domain name>-<name>'
                    return 1
                }
                $CurrentSecret = Get-AzKeyVaultSecret -VaultName $CdfConfig.Application.ResourceNames.keyVaultName -Name $NamedValue.kvSecretName -AsPlainText
                Write-Host " - Current: '$CurrentSecret' new '$($NamedValue.value)'"
                if ($null -eq $CurrentSecret) {
                    Write-Host ' - Adding secret'
                    $SecretValue = ConvertTo-SecureString $NamedValue.value -AsPlainText -Force
                    $SetSecret = Set-AzKeyVaultSecret -VaultName $CdfConfig.Application.ResourceNames.keyVaultName -Name $NamedValue.kvSecretName -SecretValue $SecretValue
                    #TODO: Handle error response
                }
                elseif ($NamedValue.value -eq $CurrentSecret) {
                    Write-Host ' - Existing, match, no change'
                }
                else {
                    Write-Host ' - Existing, diff, update'
                    $SecretValue = ConvertTo-SecureString $NamedValue.value -AsPlainText -Force
                    $SetSecret = Set-AzKeyVaultSecret -VaultName $CdfConfig.Application.ResourceNames.keyVaultName -Name $NamedValue.kvSecretName -SecretValue $SecretValue
                    #TODO: Handle error response
                }
            }
        }

    }

    #######################################
    # Variables
    ######################################
    $VariablesFile = Resolve-Path "$ConfigPath/env-variables.json"
    if (!$null -eq $VariablesFile) {
        $cdfSchemaPath = Join-Path -Path $MyInvocation.MyCommand.Module.ModuleBase -ChildPath 'Resources/Schemas/cdf-apim-nv-gh-variables.schema.json'
        if (!(Test-Json -SchemaFile "$cdfSchemaPath" -Path $VariablesFile)) {
            Write-Error "APIM variable named values configuration file did not validate. Please check errors above and correct."
            Write-Error "File path:  $VariablesFile"
        }
        else {
            $Variables = Get-Content -Path $VariablesFile | ConvertFrom-Json -AsHashtable

            foreach ($NamedValue in $Variables) {
                Write-Host "Processing variable with keyvault name: $($NamedValue.kvSecretName)"
                if (!$NamedValue.kvSecretName.StartsWith("$DomainName-", 'CurrentCultureIgnoreCase')) {
                    Write-Error 'Domain env-variables must have keyvault secret names starting with domain name. <domain name>-<name>'
                    return 1
                }
                # Fetch the secret value from GitHub Workflow environment
                if (Test-Path "env:$($NamedValue.ghVariableName)") {
                    $ghVariableValue = (Get-Item "env:$($NamedValue.ghVariableName)").Value
                }
                else {
                    Write-Warning "Environment variable [$($NamedValue.ghVariableName)] for GitHub Secret not set, assigning dummy value 'not-defined' for development test."
                    $ghVariableValue = 'not-defined'
                }

                $CurrentSecret = Get-AzKeyVaultSecret -VaultName $CdfConfig.Application.ResourceNames.keyVaultName -Name $NamedValue.kvSecretName -AsPlainText
                Write-Host " - Current: '$CurrentSecret' new '$ghVariableValue'"
                if ($null -eq $CurrentSecret) {
                    Write-Host ' - Adding secret'
                    $SecretValue = ConvertTo-SecureString $ghVariableValue -AsPlainText -Force
                    $SetSecret = Set-AzKeyVaultSecret -VaultName $CdfConfig.Application.ResourceNames.keyVaultName -Name $NamedValue.kvSecretName -SecretValue $SecretValue
                    #TODO: Handle error response
                }
                elseif ($ghVariableValue -eq $CurrentSecret) {
                    Write-Host ' - Match, no change'
                }
                elseif ($ghSecretValue -ne 'not-defined') {
                    Write-Host ' - Existing, diff, update'
                    $SecretValue = ConvertTo-SecureString $ghVariableValue -AsPlainText -Force
                    $SetSecret = Set-AzKeyVaultSecret -VaultName $CdfConfig.Application.ResourceNames.keyVaultName -Name $NamedValue.kvSecretName -SecretValue $SecretValue
                    #TODO: Handle error response
                }
                else {
                    Write-Host ' - Existing, no change'
                }
            }
        }

    }

    $SecretsFile = Resolve-Path "$ConfigPath/env-secrets.json"
    if (!$null -eq $SecretsFile) {
        $cdfSchemaPath = Join-Path -Path $MyInvocation.MyCommand.Module.ModuleBase -ChildPath 'Resources/Schemas/cdf-apim-nv-gh-secrets.schema.json'
        if (!(Test-Json -SchemaFile "$cdfSchemaPath" -Path $SecretsFile)) {
            Write-Error "APIM secret named values configuration file did not validate. Please check errors above and correct."
            Write-Error "File path:  $SecretsFile"
        }
        else {
            $Secrets = Get-Content -Path $SecretsFile | ConvertFrom-Json -AsHashtable

            foreach ($NamedValue in $Secrets) {
                Write-Host "Processing secret with keyvault name: $($NamedValue.kvSecretName)"
                if (!$NamedValue.kvSecretName.StartsWith("$DomainName-", 'CurrentCultureIgnoreCase')) {
                    Write-Error 'Domain env-secrets must have keyvault secret name starting with domain name. <domain name>-<name>'
                    return 1
                }

                # Fetch the secret value from GitHub Workflow environment
                if (Test-Path "env:$($NamedValue.ghSecretName)") {
                    $ghSecretValue = (Get-Item "env:$($NamedValue.ghSecretName)").Value
                }
                else {
                    Write-Warning "Environment variable [$($NamedValue.ghSecretName)] for GitHub Secret not set, assigning dummy value 'not-defined' for development test."
                    $ghSecretValue = 'not-defined'
                }

                $CurrentSecret = Get-AzKeyVaultSecret -VaultName $CdfConfig.Application.ResourceNames.keyVaultName -Name $NamedValue.kvSecretName -AsPlainText
                if ($null -eq $CurrentSecret) {
                    Write-Host ' - Adding secret'
                    $SecretValue = ConvertTo-SecureString $ghSecretValue -AsPlainText -Force
                    $SetSecret = Set-AzKeyVaultSecret -VaultName $CdfConfig.Application.ResourceNames.keyVaultName -Name $NamedValue.kvSecretName -SecretValue $SecretValue
                    #TODO: Handle error response
                }
                elseif ($ghSecretValue -eq $CurrentSecret) {
                    Write-Host ' - Existing, match, no change'
                }
                elseif ($ghSecretValue -ne 'not-defined') {
                    Write-Host ' - Existing, diff, update'
                    $SecretValue = ConvertTo-SecureString $ghSecretValue -AsPlainText -Force
                    $SetSecret = Set-AzKeyVaultSecret -VaultName $CdfConfig.Application.ResourceNames.keyVaultName -Name $NamedValue.kvSecretName -SecretValue $SecretValue
                    #TODO: Handle error response
                }
                else {
                    Write-Host ' - Existing, no change'
                }
            }
        }
    }
}
