Function Deploy-GitHubKeyVaultSecrets {
    <#
    .SYNOPSIS

    Deploys GitHub secrets to Azure KeyVault

    .DESCRIPTION

    This cmdlet reads GitHub variables and secrets and stores them in the KeyVault as secrets.

    .PARAMETER CdfConfig
    Instance config

    .PARAMETER Scope
    Scope Platform, Application or Domain for the KeyVault

    .PARAMETER SecretsMapFile
    A JSON file with secrets mapping

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

    $ConstantsFile = Resolve-Path "$ConfigPath/constants.json"
    $VariablesFile = Resolve-Path "$ConfigPath/env-variables.json"
    $SecretsFile = Resolve-Path "$ConfigPath/env-secrets.json"

    if (!$null -eq $ConstantsFile) {
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

    if (!$null -eq $VariablesFile) {
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
                Write-Host ' - Existing, match, no change'
            }
            else {
                Write-Host ' - Existing, diff, update'
                $SecretValue = ConvertTo-SecureString $ghVariableValue -AsPlainText -Force
                $SetSecret = Set-AzKeyVaultSecret -VaultName $CdfConfig.Application.ResourceNames.keyVaultName -Name $NamedValue.kvSecretName -SecretValue $SecretValue
                #TODO: Handle error response
            }
        }

    }

    if (!$null -eq $SecretsFile) {
        $Secrets = Get-Content -Path $SecretsFile | ConvertFrom-Json -AsHashtable

        foreach ($NamedValue in $Secrets) {
            Write-Host "Processing secret with keyvault name: $($NamedValue.kvSecretName)"
            if (!$NamedValue.kvSecretName.StartsWith("$DomainName-", 'CurrentCultureIgnoreCase')) {
                Write-Error 'Domain env-secrets must have keyvault secret name starting with domain name. <domain name>-<name>'
                return 1
            }

            # Fetch the secret value from GitHub Workflow environment
            if (Test-Path "env:$($NamedValue.ghSecretName)") {
                $ghSecretName = (Get-Item "env:$($NamedValue.ghSecretName)").Value
            }
            else {
                Write-Warning "Environment variable [$($NamedValue.ghSecretName)] for GitHub Secret not set, assigning dummy value 'not-defined' for development test."
                $ghSecretName = 'not-defined'
            }

            $CurrentSecret = Get-AzKeyVaultSecret -VaultName $CdfConfig.Application.ResourceNames.keyVaultName -Name $NamedValue.kvSecretName -AsPlainText
            Write-Host " - Current: '$CurrentSecret' new '$ghSecretName'"
            if ($null -eq $CurrentSecret) {
                Write-Host ' - Adding secret'
                $SecretValue = ConvertTo-SecureString $ghSecretName -AsPlainText -Force
                $SetSecret = Set-AzKeyVaultSecret -VaultName $CdfConfig.Application.ResourceNames.keyVaultName -Name $NamedValue.kvSecretName -SecretValue $SecretValue
                #TODO: Handle error response
            }
            elseif ($ghSecretName -eq $CurrentSecret) {
                Write-Host ' - Existing, match, no change'
            }
            else {
                Write-Host ' - Existing, diff, update'
                $SecretValue = ConvertTo-SecureString $ghSecretName -AsPlainText -Force
                $SetSecret = Set-AzKeyVaultSecret -VaultName $CdfConfig.Application.ResourceNames.keyVaultName -Name $NamedValue.kvSecretName -SecretValue $SecretValue
                #TODO: Handle error response
            }
        }
    }
}
