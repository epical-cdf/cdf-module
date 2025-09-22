Function Import-GitHubSecretsToKeyVault {
  <#
    .SYNOPSIS

    Imports a set of secrets from GitHub into a target key vault.

    .DESCRIPTION
    The command takes 3 mandatory inputs and 1 optional input:
    - JSON (As Hashtable) of all configured GitHub secrets.
      Must have the following format:
      {
        "Secret1": "somevalue",
        "Secret2": "somevalue",
        "Secret3": "somevalue"
      }
    - path of the file having list of GitHub secrets to be imported and respective key name to be used in KV.
      The file must have the following JSON format:
      [
        {
          "kvSecretName": "Secret-1",
          "ghSecretName": "Secret1"
        },
        {
          "kvSecretName": "Secret-3",
          "ghSecretName": "Secret3"
        }
      ]
    - KeyVault where secrets has to be imported.
    - ServiceName where secrets are referenced.

    .PARAMETER GithubSecrets
    GitHub Secrets as HashTable

    .PARAMETER GithubKeyVaultMappingFilePath
    File Path

    .PARAMETER KeyVaultName
    The name of the target key vault.

    .PARAMETER ServiceName
    Name of the service that references the secrets.

    .INPUTS
    None. You cannot pipe objects.

    .OUTPUTS
    None.

    .EXAMPLE
    PS> Import-CdfGitHubSecretsToKeyVault -GithubSecrets "Github secrets json as hashtable" `
        -GithubKeyVaultMappingFilePath "FilePath" -KeyVaultName "KeyVaultName"

    PS> Import-CdfGitHubSecretsToKeyVault -GithubSecrets "Github secrets json as hashtable" `
        -GithubKeyVaultMappingFilePath "FilePath" -KeyVaultName "KeyVaultName" -ServiceName "outbound"

    .LINK

    #>

  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $true)]
    [hashtable] $GithubSecrets,
    [Parameter(Mandatory = $true)]
    [string] $GithubKeyVaultMappingFilePath,
    [Parameter(Mandatory = $true)]
    [string] $KeyVaultName,
    [Parameter(Mandatory = $false)]
    [string] $ServiceName
  )
  if (Test-Path $GithubKeyVaultMappingFilePath) {

    $ghKvList = Get-Content  $GithubKeyVaultMappingFilePath | ConvertFrom-Json -AsHashtable
    $secretsList = @()
    foreach ($ghKvItem in $ghKvList) {
      foreach ($ghSecret in $GithubSecrets.Keys) {
        if ($ghKvItem.ghSecretName -eq $ghSecret) {
          Write-Verbose "Include GitHub Secret $($ghKvItem.ghSecretName)"
          if ($ServiceName) {
            if ($ghKvItem.configType) {
              $kvSecretName = $ghKvItem.configType + '-' + $ServiceName + '-' + $ghKvItem.kvSecretName
            }
            else {
              $kvSecretName = 'External-' + $ServiceName + '-' + $ghKvItem.kvSecretName
            }
          }
          else {
            $kvSecretName = $ghKvItem.kvSecretName
          }
          $secretsList += @{
            kvSecretName = $kvSecretName
            kvValue      = $GithubSecrets[$ghSecret]
          }
        }
      }
    }
    $secretsList | Import-KeyVaultSecrets -Name $KeyVaultName
  }
  else {
    Write-Host "No secrets needed to be imported from GitHub to KeyVault"
  }

}