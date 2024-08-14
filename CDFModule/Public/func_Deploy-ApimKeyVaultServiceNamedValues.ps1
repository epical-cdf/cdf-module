Function Deploy-ApimKeyVaultServiceNamedValues {
    <#
    .SYNOPSIS

    Deploys named values to the the Apim application keyvault

    .DESCRIPTION

    This cmdlet reads GitHub variables and secrets in the domain repository and stores them in the APIM domain keyvault as secrets.
    These keyvault secrets are referenced from the domain named values bicep templates.
    
    .PARAMETER CdfConfig
    Instance config
    
    .PARAMETER DomainName
    The domain name of the service as provided in workflow inputs
    
    .PARAMETER ServiceName
    Name of the service as provided in workflow inputs

    .PARAMETER ConfigPath
    File system root path to the service's artifact build contents

    .INPUTS
    None. You cannot pipe objects.

    .OUTPUTS
    None. Writes compiled policies.

    .EXAMPLE
    PS> Deploy-ApimKeyVaultServiceNamedValues `
        -KeyVaultName "kv-apim01-dev-we" `
        -EnvDefinitionId "apim-dev" `
        -DomainName "hr" `
        -ServiceName "api-expenses" `
        -ConfigPath "."

    .LINK

    #>

    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [hashtable] $CdfConfig,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $DomainName = $env:CDF_DOMAIN_NAME,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ServiceName = $env:CDF_SERVICE_NAME,
        [Parameter(Mandatory = $true)]
        [string] $ConfigPath
    )

    if ($false -eq (Test-Path "$ConfigPath")) {
        Write-Verbose "No domain named values configuration - returning"
        return
    }
    
    $cdfConfigFile = Resolve-Path "$ConfigPath/cdf-config.json"

    if (!$null -eq $cdfConfigFile) {
        $svcConfig = Get-Content -Path $cdfConfigFile | ConvertFrom-Json -AsHashtable

        foreach ($NamedValue in $svcConfig.ServiceSettings.namedValues) {        
            Write-Host "Processing constant with keyvault name: $($NamedValue.secretName)"
            if (!$NamedValue.secretName.StartsWith("$DomainName-", 'CurrentCultureIgnoreCase')) {
                Write-Error 'Domain constants must have keyvault secret names starting with domain name. [<DomainName>-<Some-Other-Names>]'
                return 1
            }
            $CurrentSecret = Get-AzKeyVaultSecret -VaultName $CdfConfig.Application.ResourceNames.keyVaultName -Name $NamedValue.secretName -AsPlainText
            Write-Host " - Current: '$CurrentSecret' new '$($NamedValue.value)'"
            if ($null -eq $CurrentSecret) {
                Write-Host ' - Adding secret'
                $SecretValue = ConvertTo-SecureString -String $NamedValue.value -AsPlainText -Force 
                $SetSecret = Set-AzKeyVaultSecret -VaultName $CdfConfig.Application.ResourceNames.keyVaultName -Name $NamedValue.secretName -SecretValue $SecretValue
                #TODO: Handle error response
            }
            elseif ($NamedValue.value -eq $CurrentSecret) {
                Write-Host ' - Existing, match, no change'
            }
            else {
                Write-Host ' - Existing, diff, update'
                $SecretValue = ConvertTo-SecureString $NamedValue.value -AsPlainText -Force 
                $SetSecret = Set-AzKeyVaultSecret -VaultName $CdfConfig.Application.ResourceNames.keyVaultName -Name $NamedValue.secretName -SecretValue $SecretValue
                #TODO: Handle error response
            }
        }

    }

}
