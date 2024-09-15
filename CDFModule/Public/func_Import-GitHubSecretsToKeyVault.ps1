Function Import-GitHubSecretsToKeyVault {
    <#
    .SYNOPSIS

    Imports a set of secrets from GitHub into a target key vault.

    .DESCRIPTION
    The command takes 3 inputs:
    - JSON (As Hashtable) of all configured GitHub secrets.
      Format must have the following format:
      {
        "Key1": "Value1",
        "Key2": "Value2"
      }
    - path of the file having list of GitHub secrets to be imported and respective key name to be used in KV.
      The file must have the following JSON format:
      [
        {
          "kvSecretName": "Test-Cert-Password-wildcard-axesslogistics-com",
          "ghSecretName": "AXL_CERT_PASSWORD"
        },
        {
          "kvSecretName": "Test-ODGW-ServiceAccount-Username",
          "ghSecretName": "AXL_ODGW_USERNAME"
        },
        {
          "kvSecretName": "Test-ODGW-ServiceAccount-Password",
          "ghSecretName": "AXL_ODGW_PASSWORD"
        }
      ]
    - KeyVault where secrets has to be imported.    

    .PARAMETER GithubSecrets
    GitHub Secrets as HashTable

    .PARAMETER GithubKeyVaultMappingFilePath
    File Path

    .PARAMETER KeyVaultName
    The name of the target key vault.

    .INPUTS
    None. You cannot pipe objects.

    .OUTPUTS
    None.

    .EXAMPLE
    PS> Import-CdfGitHubSecretsToKeyVault -GithubSecrets "Github secrets json as hashtable" `
        -GithubKeyVaultMappingFilePath "FilePath" -KeyVaultName "KeyVaultName"

    .LINK
    
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $GithubSecrets,    
        [Parameter(Mandatory = $true)]
        [string] $GithubKeyVaultMappingFilePath,
        [Parameter(Mandatory = $true)]
        [string] $KeyVaultName        
    )    
            if (Test-Path $GithubKeyVaultMappingFilePath) {
              $ghKvList = Get-Content  $GithubKeyVaultMappingFilePath | ConvertFrom-Json -AsHashtable
              $secretsList = @()
              foreach($ghKvItem in $ghKvList) {
                foreach($ghSecret in $GithubSecrets.Keys) {
                  if($ghKvItem.ghSecretName -eq $ghSecret){
                    $keyValue = @{
                      kvSecretName = $ghKvItem.kvSecretName
                      kvValue = $GithubSecrets[$ghSecret]}   
                    $secretsList += $keyValue
                  }
                }
              }              
              $secretsList | Import-KeyVaultSecrets -Name $KeyVaultName
            }
            else {
                Write-Host "No secrets needed to be imported from GitHub to KeyVault"
            }

}