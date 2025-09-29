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
    - CdfConfig config object.

    .PARAMETER GithubSecrets
    GitHub Secrets as HashTable

    .PARAMETER GithubKeyVaultMappingFilePath
    File Path

    .PARAMETER KeyVaultName
    The name of the target key vault.

    .PARAMETER CdfConfig
    The CDFConfig object that holds the current scope configurations (Platform, Application and Domain)

    .INPUTS
    None. You cannot pipe objects.

    .OUTPUTS
    None.

    .EXAMPLE
    PS> Import-CdfGitHubSecretsToKeyVault -GithubSecrets "Github secrets json as hashtable" `
        -GithubKeyVaultMappingFilePath "FilePath" -KeyVaultName "KeyVaultName"

    PS> $cdfConfig | Import-CdfGitHubSecretsToKeyVault -GithubSecrets "Github secrets json as hashtable" `
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
    [string] $KeyVaultName,
    [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
    [hashtable]$CdfConfig
  )
  if (Test-Path $GithubKeyVaultMappingFilePath) {
    if ($null -ne $CdfConfig) {
      $CdfTokens = $CdfConfig | Get-TokenValues
      $ghKvList = Get-Content  $GithubKeyVaultMappingFilePath -Raw | Update-ConfigToken `
        -Tokens $CdfTokens `
        -StartTokenPattern "{{" `
        -EndTokenPattern "}}" `
        -NoWarning `
        -WarningAction:SilentlyContinue | ConvertFrom-Json -AsHashtable
    }
    else {
      $ghKvList = Get-Content  $GithubKeyVaultMappingFilePath | ConvertFrom-Json -AsHashtable
    }

    $secretsList = @()
    foreach ($ghKvItem in $ghKvList) {
      if ($null -ne $CdfConfig -and $null -ne $CdfConfig.Service) {
        $pattern = "^(External|Internal)-$([Regex]::Escape($CdfConfig.Service.Config.serviceName))-.+$"
        if ($ghKvItem.kvSecretName -notmatch $pattern) {
          Write-Warning "Detected possible misconfiguration in GitHub to Key Vault mapping file for service [$($CdfConfig.Service.Config.serviceName)]."
          Write-Warning "$($ghKvItem.kvSecretName) - Key Vault identitifier does not follow the expected naming convention service secrets."
          Write-Warning "The format should be: 'Internal|External-{{SERVICE_NAME}}-somevalue'."
          Write-Warning "If these are not service secrets, you can ignore this warning."
        }
      }
      foreach ($ghSecret in $GithubSecrets.Keys) {
        if ($ghKvItem.ghSecretName -eq $ghSecret) {
          Write-Verbose "Include GitHub Secret $($ghKvItem.ghSecretName)"
          $secretsList += @{
            kvSecretName = $ghKvItem.kvSecretName
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