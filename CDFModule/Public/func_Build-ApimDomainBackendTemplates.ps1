Function Build-ApimDomainBackendTemplates {
    <#
    .SYNOPSIS

    Builds ARM templates for domain backend

    .DESCRIPTION
    This cmdlet builds ARM templates for domain backend specifications found in the <DomainPath>/domain-backends.

    .PARAMETER CdfConfig
    Instance config

    .PARAMETER DomainName
    Domain name of the service as provided in workflow inputs

    .PARAMETER SharedPath
    File system root path to the apim shared repository contents

    .PARAMETER DomainPath
    File system root path to the domain repository contents

    .PARAMETER OutputPath
    File system path where ARM template will be written

    .INPUTS
    None. You cannot pipe objects.

    .OUTPUTS
    None. Writes compiled policies.

    .EXAMPLE
    PS> Build-ApimDomainBackendTemplates `
        -DomainName "testdom1" `
        -DomainPath "." `
        -SharedPath "shared" `
        -BuildFolder "tmp"


    .LINK
    Build-ApimServiceTemplates

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

    if ($false -eq (Test-Path "$DomainPath/domain-backends")) {
        Write-Verbose "No domain backend configuration - returning"
        return
    }

    # Setup backends "build" folder.
    New-Item -Force -Type Directory "$BuildPath" | Out-Null

    $DomainBackends = Get-ChildItem -Path "$DomainPath/domain-backends" -Include '*.json' -File -Name
    foreach ($DomainBackend in $DomainBackends) {

        $BackendConfigFile = Resolve-Path "$DomainPath/domain-backends/$DomainBackend"
        $Backend = Get-Content -Path $BackendConfigFile | ConvertFrom-Json -AsHashtable

        Write-Host "Build backend: $($Backend.title)"
        if (-not ($Backend.title.StartsWith("$DomainName-"))) {
            Write-Error 'Domain backends must have titles starting with domain name. <domain name>-<backend name>'
            return 1
        }

        # This is the "simple" type which is extended by other types below.
        $backendParams = @"
            {
                "`$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
                "contentVersion": "1.0.0.0",
                "parameters": {
                    "backendTitle": {
                        "value": "$($Backend.title)"
                    },
                    "backendDescription": {
                        "value": "$($Backend.description)"
                    },
                    "backendProtocol": {
                        "value": "$($Backend.protocol)"
                    },
                    "validateCertificateChain": {
                        "value": $($Backend.validateCertificateChain ? 'true' : 'false')
                    },
                    "validateCertificateName": {
                        "value": $($Backend.validateCertificateName ? 'true' : 'false')
                    }
                }
              }
"@


        $BicepParams = ConvertFrom-Json $backendParams -AsHashtable

        $urlKey = "url:" + $CdfConfig.Application.Env.definitionId
        $backendUrl = $Backend[$urlKey] ?? $Backend.url
        $BicepParams.parameters.Add('backendUrl', @{ 'value' = $backendUrl })

        $BicepParams.parameters.Add('platformResourceNames', @{ 'value' = $CdfConfig.Platform.ResourceNames })
        $BicepParams.parameters.Add('applicationResourceNames', @{ 'value' = $CdfConfig.Application.ResourceNames })

        if ('proxy' -eq $Backend.type) {
            $BicepParams.parameters.Add('proxyUrl', @{ })
            $BicepParams.parameters.proxyUrl.Add('reference', @{ 'secretName' = "APIM-Backend-$($Backend.title)-ProxyUrl" })
            $BicepParams.parameters.proxyUrl.reference.Add('keyVault', @{ 'id' = '#{{apim-keyvault-id}}' })

            $BicepParams.parameters.Add('proxyUserName', @{ })
            $BicepParams.parameters.proxyUserName.Add('reference', @{ 'secretName' = "APIM-Backend-$($Backend.title)-ProxyUserName" })
            $BicepParams.parameters.proxyUserName.reference.Add('keyVault', @{ 'id' = '#{{apim-keyvault-id}}' })

            $BicepParams.parameters.Add('proxyPassword', @{ })
            $BicepParams.parameters.proxyPassword.Add('reference', @{ 'secretName' = "APIM-Backend-$($Backend.title)-ProxyPassword" })
            $BicepParams.parameters.proxyPassword.reference.Add('keyVault', @{ 'id' = '#{{apim-keyvault-id}}' })
        }
        elseif ('certificate' -eq $Backend.type) {
            $azCtx = Get-AzureContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId
            $keyVault = Get-AzKeyVault `
                -DefaultProfile $azCtx `
                -Name $CdfConfig.Application.ResourceNames.keyVaultName `
                -ResourceGroupName $CdfConfig.Application.ResourceNames.appResourceGroupName

            $BicepParams.parameters.Add('certPassword', @{})
            $BicepParams.parameters.certPassword.Add('reference', @{ 'secretName' = "$($Backend.certPwdSecretName)" })
            $BicepParams.parameters.certPassword.reference.Add('keyVault', @{ 'id' = $keyVault.ResourceId })


            # Copy certificate file
            $BackendCertFile = Resolve-Path "$DomainPath/domain-backends/$($Backend.certFileName).$($CdfConfig.Application.Env.definitionId)"
            if (Test-Path $BackendCertFile) {
                # Load certificate file as base64 string parameter
                $base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($BackendCertFile))
                $BicepParams.parameters.Add('certData', @{ 'value' = "$base64" })
            }
        }

        # Create template parameters json file
        $BicepParams | ConvertTo-Json -Depth 5 | Set-Content -Path "$BuildPath/backend.$($Backend.type).$($Backend.title).params.json"

        # Copy bicep template with type name
        Copy-Item -Force -Path "$SharedPath/resources/backend.$($Backend.type).bicep" -Destination "$BuildPath/backend.$($Backend.type).$($Backend.title).bicep" | Out-Null
    }
}
