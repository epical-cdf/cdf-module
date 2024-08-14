<#
MIT License

Copyright (c) 2020 Janne Mattila

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>
Function Export-APIMDeveloperPortal {
    <#
    .SYNOPSIS
    Export developer portal configuration

    .DESCRIPTION
    This creates `Export` folder and exports developer portal content and media files from `contosoapi` APIM Developer portal.

    .PARAMETER ResourceGroupName
    Resource group name for API Management

    .PARAMETER APIMName
    Name of API Manamgement instance

    .PARAMETER ExportFolder
    Path to folder where configuration export will be stored

    .PARAMETER APIVersion
    Version of management API to be used

    .EXAMPLE
    Export-APIMDeveloperPortal.ps1 -ResourceGroupName rg-apim -APIMName contosoapi -ExportFolder Export
    #>

    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Resource group of API MAnagement')]
        [string] $ResourceGroupName,

        [Parameter(Mandatory = $true, HelpMessage = 'API Management Name')]
        [string] $APIMName,

        [Parameter(HelpMessage = 'Export folder', Mandatory = $false)]
        [string] $ExportFolder = 'Export',

        [Parameter(HelpMessage = 'API Version')]
        [string] $APIVersion = '2023-03-01-preview'
    )

    $ErrorActionPreference = 'Stop'

    "Exporting Azure API Management Developer portal content to: $ExportFolder"
    $mediaFolder = Join-Path -Path $ExportFolder -ChildPath 'Media'

    New-Item -ItemType 'Directory' -Path $ExportFolder -Force
    New-Item -ItemType 'Directory' -Path $mediaFolder -Force

    $ctx = Get-AzContext
    $ctx.Subscription.Id
    $baseUri = "subscriptions/$($ctx.Subscription.Id)/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiManagement/service/$APIMName"
    $baseUri

    $contentItems = @{ }
    $contentTypes = (Invoke-AzRestMethod -Path "$baseUri/contentTypes?api-version=$APIVersion" -Method GET).Content | ConvertFrom-Json

    foreach ($contentTypeItem in $contentTypes.value) {
        $contentTypeItem.id
        $contentType = (Invoke-AzRestMethod -Path "$baseUri/$($contentTypeItem.id)/contentItems?api-version=$APIVersion" -Method GET).Content | ConvertFrom-Json

        foreach ($contentItem in $contentType.value) {
            $contentItem.id
            $contentItems.Add($contentItem.id, $contentItem)
        }
    }

    $contentItems
    $contentItems | ConvertTo-Json -Depth 100 | Out-File -FilePath "$ExportFolder\data.json"

    $storage = (Invoke-AzRestMethod -Path "$baseUri/portalSettings/mediaContent/listSecrets?api-version=$APIVersion" -Method POST).Content | ConvertFrom-Json
    $containerSasUrl = [System.Uri] $storage.containerSasUrl
    $storageAccountName = $containerSasUrl.Host.Split('.')[0]
    $sasToken = $containerSasUrl.Query
    $contentContainer = $containerSasUrl.GetComponents([UriComponents]::Path, [UriFormat]::SafeUnescaped)

    $storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $sasToken
    Set-AzCurrentStorageAccount -Context $storageContext

    $totalFiles = 0
    $continuationToken = $null
    do {
        $blobs = Get-AzStorageBlob -Container $contentContainer -MaxCount 1000 -ContinuationToken $continuationToken
        "Found $($blobs.Count) files in current batch."
        $blobs
        $totalFiles += $blobs.Count
        if (0 -eq $blobs.Length) {
            break
        }

        foreach ($blob in $blobs) {
            $targetFile = Join-Path -Path $mediaFolder -ChildPath $blob.Name
            $targetFolder = Split-Path -Path $targetFile -Parent
            if (-not (Test-Path -Path $targetFolder)) {
                New-Item -ItemType 'Directory' -Path $targetFolder -Force
            }
            Get-AzStorageBlobContent -Blob $blob.Name -Container $contentContainer -Destination $targetFile
        }

        $continuationToken = $blobs[$blobs.Count - 1].ContinuationToken
    }
    while ($null -ne $continuationToken)

    "Downloaded $totalFiles files from container $contentContainer"
    'Export completed'

}


Function Export-ApimPortalConfig {
    <#
    .SYNOPSIS

    Configures the platform Application Gateway ingress for an APIM portal.

    .DESCRIPTION
    Setup Azure Application Gateway for APIM application developer portal.

    .PARAMETER CdfConfig
    APIM Application configuration

    .PARAMETER PortalConfig
    Name of the APIM portal config template. Defaults to 'portal-config'

    .PARAMETER TemplateDir
    Path to the platform template root dir. Defaults to ".".


    .INPUTS
    None. You cannot pipe objects.

    .OUTPUTS
    None.

    .EXAMPLE
    Set-CdfApimPortalWafConfig `
        -CdfConfig $config `
        -TemplateName "portal-epical"

    .LINK
    Set-CdfApimWafConfig

    #>

    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [Object]$CdfConfig,
        [Parameter(Mandatory = $false)]
        [string] $PortalConfig = 'portal-config',
        [Parameter(Mandatory = $false)]
        [string] $TemplateDir = ".",
        [Parameter(Mandatory = $false)]
        [string] $SourceDir = "./src"
    )

    $portalConfigPath = "$TemplateDir/application/$($CdfConfig.Platform.Config.templateName)/$($CdfConfig.Platform.Config.templateVersion)/templates"
    if (!(Test-Path $portalConfigPath) ) {
        throw "Could not find portal config path at [$portalConfigPath]"
    }

    $currAzCtx = Get-AzContext
    Set-AzContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId

    Export-APIMDeveloperPortal `
        -ResourceGroupName $CdfConfig.Application.ResourceNames.appResourceGroupName `
        -APIMName $CdfConfig.Application.ResourceNames.apimName `
        -ExportFolder "$portalConfigPath/$PortalConfig"

    Set-AzContext $currAzCtx
}