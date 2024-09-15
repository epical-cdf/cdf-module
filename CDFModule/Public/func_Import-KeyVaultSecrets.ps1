Function Import-KeyVaultSecrets {
    <#
    .SYNOPSIS

    Imports a set of secrets from JSON file input into a target key vault

    .DESCRIPTION

    The command takesan array of secrets to import. 
    The secrets JSON must have the following format.

    [
        {
            "kvSecretName": "System-AppA-Secret",
            "kvValue": "app-a-secret"
        },
        {
            "kvSecretName": "System-AppB-Dev-Secret",
            "kvValue": "app-b-dev-secret"
        },
        {
            "kvSecretName": "System-AppB-Test-Secret",
            "kvValue": "app-b-tst-secret"
        }
    ]

    .PARAMETER Name
    The name of the target key vault.

    .INPUTS
    Secrets

    .OUTPUTS
    None.

    .EXAMPLE
    PS> Import-CdfGitHubSecretsToKeyVault ... | Import-CdfKeyVaultSecrets `
            -Name "KeyVault Name"
            

    PS> (Get-Content  "secrets json file path" | ConvertFrom-Json -AsHashtable) `
            | Import-CdfKeyVaultSecrets `
            -Name "KeyVault Name" 

    .LINK
    Import-CdfGitHubSecretsToKeyVault

    #>

    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [hashtable] $Secrets,    
        [Parameter(Mandatory = $true)]
        [string] $Name        
    )
    
    foreach ($Secret in $Secrets) {
        Write-Verbose "Processing $($Secret.kvSecretName)"
        $CurrentSecret = Get-AzKeyVaultSecret -VaultName $Name -Name $Secret.kvSecretName -AsPlainText 
        if($Secret.kvValue  -eq $CurrentSecret) {
            Write-Verbose " - Existing, match, no change"
        } else {
            Write-Verbose " - Add/Update"
            $SecretValue = ConvertTo-SecureString $Secret.kvValue -AsPlainText -Force 
            Set-AzKeyVaultSecret -VaultName $Name -Name $Secret.kvSecretName -SecretValue $SecretValue
        }
    }

}