
Function Build-ApimDomainNamedValuesTemplate {
    <#
    .SYNOPSIS

    Build bicep template and parameters for domain named values

    .DESCRIPTION
    TBD

    .PARAMETER CdfConfig
    Instance config

    .PARAMETER DomainName
    Domain name of the service as provided in workflow inputs

    .PARAMETER SharedPath
    File system root path to the apim shared repository contents

    .PARAMETER DomainPath
    File system root path to the service's domain repository contents

    .PARAMETER OutputPath
    File system path where ARM template will be written

    .INPUTS
    None. You cannot pipe objects.

    .OUTPUTS
    None. Writes compiled policies.

    .EXAMPLE
    PS> $config | Build-ApimDomainNamedValuesTemplate `
        -DomainName "testdom1" `
        -DomainPath "." `
        -SharedPath "shared" `
        -BuildFolder "tmp"

    .LINK
    Deploy-ApimKeyVaultDomainNamedValues

    #>
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [hashtable] $CdfConfig,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $DomainName = $env:CDF_DOMAIN_NAME,
        [Parameter(Mandatory = $false)]
        [string] $SharedPath = $env:CDF_SHARED_SOURCE_PATH,
        [Parameter(Mandatory = $false)]
        [string] $DomainPath = '.',
        [Parameter(Mandatory = $false)]
        [string] $BuildPath = 'tmp/build'
    )


    if ($false -eq (Test-Path "$DomainPath/domain-namedvalues")) {
        Write-Verbose "No domain named values configuration - returning"
        return
    }

    # Setup named values "build" folder.
    New-Item -Force -Type Directory "$BuildPath" | Out-Null

    $ConstantsFile = Resolve-Path "$DomainPath/domain-namedvalues/constants.json"
    $VariablesFile = Resolve-Path "$DomainPath/domain-namedvalues/env-variables.json"
    $SecretsFile = Resolve-Path "$DomainPath/domain-namedvalues/env-secrets.json"

    $DomainNamedValuesParamJson = @"
    {
        "`$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
        "contentVersion": "1.0.0.0",
        "parameters": {
            "keyVaultName": {
                "value": "$($CdfConfig.Application.ResourceNames.keyVaultName)"
            },
            "apimServiceName": {
                "value": "$($CdfConfig.Application.ResourceNames.apimName)"
            },
            "apimClientId": {
                "value": "$($CdfConfig.Application.Config.appIdentityClientId)"
            },
            "domainName": {
                "value": "$DomainName"
            },
            "domainNamedValues": {
            }
        }
      }
"@
    $domainNamedValuesParams = ConvertFrom-Json $DomainNamedValuesParamJson -AsHashtable
    # Create a dynamic array using ArrayList
    $paramNamedValues = New-Object System.Collections.ArrayList

    if (!$null -eq $ConstantsFile) {
        $Constants = Get-Content -Path $ConstantsFile | ConvertFrom-Json -AsHashtable

        foreach ($NamedValue in $Constants) {
            Write-Host "Build named value constant with keyvault name: $($NamedValue.kvSecretName)"
            if (!$NamedValue.kvSecretName.StartsWith("$DomainName-", 'CurrentCultureIgnoreCase')) {
                Write-Error 'Domain constants must have keyvault secret names starting with domain name. <domain name>-<name>'
                return 1
            }
            $paramNamedValues.Add(@{
                    'name'       = $NamedValue.name
                    'secretName' = $NamedValue.kvSecretName
                }) | Out-Null
        }

    }

    if (!$null -eq $VariablesFile) {
        $Variables = Get-Content -Path $VariablesFile | ConvertFrom-Json -AsHashtable

        foreach ($NamedValue in $Variables) {
            Write-Host "Build named value variable with keyvault name: $($NamedValue.kvSecretName)"
            if (!$NamedValue.kvSecretName.StartsWith("$DomainName-", 'CurrentCultureIgnoreCase')) {
                Write-Error 'Domain env-variables must have keyvault secret names starting with domain name. <domain name>-<name>'
                return 1
            }
            $paramNamedValues.Add(@{
                    'name'       = $NamedValue.name
                    'secretName' = $NamedValue.kvSecretName
                }) | Out-Null
        }

    }

    if (!$null -eq $SecretsFile) {
        $Secrets = Get-Content -Path $SecretsFile | ConvertFrom-Json -AsHashtable

        foreach ($NamedValue in $Secrets) {
            Write-Host "Build named value secret with keyvault name: $($NamedValue.kvSecretName)"
            if (!$NamedValue.kvSecretName.StartsWith("$DomainName-", 'CurrentCultureIgnoreCase')) {
                Write-Error 'Domain env-secrets must have keyvault secret name starting with domain name. <domain name>-<name>'
                return 1
            }
            $paramNamedValues.Add(@{
                    'name'       = $NamedValue.name
                    'secretName' = $NamedValue.kvSecretName
                }) | Out-Null
        }
    }

    # Create template parameters json file
    $domainNamedValuesParams.parameters.domainNamedValues.Add('value', $paramNamedValues.ToArray())
    $domainNamedValuesParams | ConvertTo-Json -Depth 10 | Set-Content -Path "$BuildPath/namedvalues.domain.params.json"

    # Copy bicep template with type name
    Copy-Item -Force -Path "$SharedPath/resources/namedvalues.domain.bicep" -Destination "$BuildPath/namedvalues.domain.bicep" | Out-Null

    # Copy domain named values files
    Copy-Item -Force -Path "$ConstantsFile" -Destination "$BuildPath/constants.json" | Out-Null
    Copy-Item -Force -Path "$VariablesFile" -Destination "$BuildPath/env-variables.json" | Out-Null
    Copy-Item -Force -Path "$SecretsFile" -Destination "$BuildPath/env-secrets.json" | Out-Null
}
