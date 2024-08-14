
Function Build-ApimDomainProductTemplates {
    <#
    .SYNOPSIS

    Builds ARM templates for domain products

    .DESCRIPTION
    This cmdlet builds ARM templates for domain product specifications found in the <DomainPath>/domain-products.

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
    PS> Build-ApimDomainProductTemplates `
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

    if ($false -eq (Test-Path "$DomainPath/domain-products")) {
        Write-Verbose "No domain products configuration - returning"
        return
    }

    # Setup products "build" folder.
    New-Item -Force -Type Directory "$BuildPath" | Out-Null

    $DomainProducts = Get-ChildItem -Path "$DomainPath/domain-products" -Include '*.json' -File -Name
    foreach ($DomainProduct in $DomainProducts) {

        $ProductConfigFile = Resolve-Path "$DomainPath/domain-products/$DomainProduct"
        $Product = Get-Content -Path $ProductConfigFile | ConvertFrom-Json

        Write-Host "Build product: $($Product.name)"
        if (-not ($Product.name.StartsWith("$DomainName-"))) {
            Write-Error 'Domain products must have name starting with domain name. <domain name>-<product name>'
            return 1
        }

        $productParamJson = @"
            {
                "`$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
                "contentVersion": "1.0.0.0",
                "parameters": {
                    "apimServiceName": {
                        "value": "$($CdfConfig.Application.ResourceNames.apimName)"
                    },
                    "productName": {
                        "value": "$($Product.name)"
                    },
                    "productDescription": {
                        "value": "$($Product.description)"
                    },
                    "productDisplayName": {
                        "value": "$($Product.name)"
                    },
                    "productTerms": {
                        "value": "$($Product.terms)"
                    },
                    "productApprovalRequired": {
                        "value": $($Product.approvalRequired ? 'true' : 'false')
                    },
                    "productSubscriptionRequired": {
                        "value": $($Product.subscriptionRequired ? 'true' : 'false')
                    },
                    "productSubscriptionLimit": {
                        "value": $($Product.subscriptionLimit)
                    }
                }
            }
"@

        $BicepParams = ConvertFrom-Json $productParamJson -AsHashtable
        $BicepParams.parameters.Add('productGroups', @{ 'value' = @( $Product.groups ) })

        # From here are api type specific parameters for the bicep template in use
        switch ($Product.type) {
            'policy' {
                $PolicyXML = Get-Content -Path "$DomainPath/domain-products/$($Product.name)-policy.xml" | Join-String -Separator "`r`n"
                $BicepParams.parameters.Add('productPolicy', @{ 'value' = $PolicyXML })
            }
            Default { }
        }
        # Create template parameters json file
        $BicepParams | ConvertTo-Json -Depth 5 | Set-Content -Path "$BuildPath/product.$($Product.type).$($Product.name).params.json"

        # Copy bicep template with type name
        Copy-Item -Force -Path "$SharedPath/resources/product.$($Product.type).bicep" -Destination "$BuildPath/product.$($Product.type).$($Product.name).bicep" | Out-Null
    }
}