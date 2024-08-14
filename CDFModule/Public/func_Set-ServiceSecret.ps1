Function Set-ServiceSecret {
    <#
    .SYNOPSIS
    Set parameter values for service in domain keyvault

    .DESCRIPTION
    Set parameter values for service in domain keyvault

    .PARAMETER CdfConfig
    The CdfConfig object that holds the current scope configurations (Platform, Application and Domain)

    .PARAMETER ParameterName
    Name of the parameter in cdf-config.json

    .PARAMETER ParameterValue
    Value to store in KeyVault

    .PARAMETER Internal
    Selects the scope of the parameter, cannot be used with External
    
    .PARAMETER External
    Selects the scope of the parameter, cannot be used with Internal
    

    .EXAMPLE
    $config | Set-CdfServiceSecret -External -ParameterName MySecret -ParameterValue my-secret-value `

    #>

    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [hashtable]$CdfConfig,
        [Parameter(Mandatory = $true)]
        [string]$ParameterName,
        [Parameter(Mandatory = $true)]
        [string]$ParameterValue,
        [Parameter(Mandatory = $false)]
        [switch]$Internal,
        [Parameter(Mandatory = $false)]
        [switch]$External
    )


    #############################################################
    # Get current service configurations
    #############################################################

    $configJson = Get-Content -Raw "cdf-config.json" 
    $svcConfig = ConvertFrom-Json -InputObject $configJson -AsHashtable 
    $azCtx = Get-AzureContext -Subscription $CdfConfig.Platform.Env.subscriptionId
    if ($Internal) {
        # Service internal settings
        $setting = $svcConfig.ServiceSettings[$ParameterName]
        if ($setting -and ($setting.Type -eq "Secret")) {
            $secretName = "Internal-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier)"
            $secretValue = ConvertTo-SecureString -String $ParameterValue -AsPlainText -Force
            Set-AzKeyVaultSecret `
                -DefaultProfile $azCtx `
                -VaultName $CdfConfig.Domain.ResourceNames.keyVaultName `
                -Name $secretName `
                -SecretValue $secretValue
        }
        else {
            if ($null -eq $setting) {
                Write-Warning "Could not find ServiceSettings with name [$ParameterName]"
            }
            else {
                Write-Warning "Parameter [$setting] is of type [$($setting.Type)]"
            }
        }
    }
    elseif ($External) {
        # Service internal settings
        $setting = $svcConfig.ExternalSettings[$ParameterName]
        if ($setting -and ($setting.Type -eq "Secret")) {
            $secretName = "External-$($CdfConfig.Service.Config.serviceName)-$($setting.Identifier)"
            $secretValue = ConvertTo-SecureString -String $ParameterValue -AsPlainText -Force
            Set-AzKeyVaultSecret `
                -DefaultProfile $azCtx `
                -VaultName $CdfConfig.Domain.ResourceNames.keyVaultName `
                -Name $secretName `
                -SecretValue $secretValue
        }
        else {
            if ($null -eq $setting) {
                Write-Warning "Could not find ExternalSettings with name [$ParameterName]"
            }
            else {
                Write-Warning "Parameter [$setting] is of type [$($setting.Type)]"
            }
        }
    }
    else {
        Write-Error "Missing -Internal or -External switch."
    }
}