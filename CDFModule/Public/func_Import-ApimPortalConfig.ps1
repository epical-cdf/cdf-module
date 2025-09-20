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
Function Import-APIMDeveloperPortal {
    <#
    .SYNOPSIS
    Import developer portal configuration into an API managment instance

    .DESCRIPTION
    This load content and media files from `Import` folder and imports them to `contosoapi` APIM Developer portal.

    .PARAMETER CdfConfig
    APIM Application configuration

    .PARAMETER ResourceGroupName
    Resource group name for API Management

    .PARAMETER APIMName
    Name of API Manamgement instance

    .PARAMETER ImportFolder
    Path to folder where import configuration is located

    .PARAMETER APIVersion
    Version of management API to be used

    .EXAMPLE
    Import-APIMDeveloperPortal.ps1 -ResourceGroupName rg-apim -APIMName contosoapi -ImportFolder Import
    #>

    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Resource group of API MAnagement')]
        [string] $ResourceGroupName,

        [Parameter(Mandatory = $true, HelpMessage = 'API Management Name')]
        [string] $APIMName,

        [Parameter(Mandatory = $false, HelpMessage = 'Import folder')]
        [string] $ImportFolder = "$PSScriptRoot\Import",

        [Parameter(Mandatory = $false, HelpMessage = 'Version used in description')]
        [string] $BuildVersion = $null,

        [Parameter(Mandatory = $false, HelpMessage = 'API Version')]
        [string] $APIVersion = '2023-03-01-preview'
    )

    $ErrorActionPreference = 'Stop'

    "Importing Azure API Management Developer portal content from: $ImportFolder"
    $ImportFolder = (Resolve-Path $ImportFolder).Path
    $mediaFolder = Join-Path -Path $ImportFolder -ChildPath 'Media'
    $dataFile = Join-Path -Path $ImportFolder -ChildPath 'data.json'

    if ($false -eq (Test-Path $ImportFolder)) {
        throw "Import folder path was not found: $ImportFolder"
    }

    if ($false -eq (Test-Path $dataFile)) {
        throw "Data file was not found: $dataFile"
    }

    if (-not (Test-Path -Path $mediaFolder)) {
        New-Item -ItemType 'Directory' -Path $mediaFolder -Force
        Write-Warning "Media folder $mediaFolder was not found but it was created."
    }

    "Reading $dataFile"
    $contentItems = Get-Content -Encoding utf8  -Raw -Path $dataFile | ConvertFrom-Json -AsHashtable
    $contentItems | Format-Table -AutoSize

    $apiManagement = Get-AzApiManagement -ResourceGroupName $ResourceGroupName -Name $APIMName
    $developerPortalEndpoint = "https://$APIMName.developer.azure-api.net"

    if ($null -ne $apiManagement.DeveloperPortalHostnameConfiguration) {
        # Custom domain name defined
        $developerPortalEndpoint = 'https://' + $apiManagement.DeveloperPortalHostnameConfiguration.Hostname
        $developerPortalEndpoint
    }

    $ctx = Get-AzContext
    $ctx.Subscription.Id

    $baseUri = "subscriptions/$($ctx.Subscription.Id)/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiManagement/service/$APIMName"
    $baseUri

    'Processing clean up of the target content'
    $contentTypes = (Invoke-AzRestMethod -Path "$baseUri/contentTypes?api-version=$APIVersion" -Method GET).Content | ConvertFrom-Json
    foreach ($contentTypeItem in $contentTypes.value) {
        $contentTypeItem.id
        $contentType = (Invoke-AzRestMethod -Path "$baseUri/$($contentTypeItem.id)/contentItems?api-version=$APIVersion" -Method GET).Content | ConvertFrom-Json

        foreach ($contentItem in $contentType.value) {
            $contentItem.id
            Invoke-AzRestMethod -Path "$baseUri/$($contentTypeItem.id)?api-version=$APIVersion" -Method DELETE
        }
        Invoke-AzRestMethod -Path "$baseUri/$($contentTypeItem.id)/contentItems?api-version=$APIVersion" -Method DELETE
    }

    'Processing clean up of the target storage'
    $storage = (Invoke-AzRestMethod -Path "$baseUri/portalSettings/mediaContent/listSecrets?api-version=$APIVersion" -Method POST).Content | ConvertFrom-Json
    $containerSasUrl = [System.Uri] $storage.containerSasUrl
    $storageAccountName = $containerSasUrl.Host.Split('.')[0]
    $sasToken = $containerSasUrl.Query
    $contentContainer = $containerSasUrl.GetComponents([UriComponents]::Path, [UriFormat]::SafeUnescaped)

    $storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $sasToken
    Set-AzCurrentStorageAccount -Context $storageContext

    $totalFiles = 0
    $continuationToken = $null

    $allBlobs = New-Object Collections.Generic.List[string]
    do {
        $blobs = Get-AzStorageBlob -Container $contentContainer -MaxCount 1000 -ContinuationToken $continuationToken
        "Found $($blobs.Count) files in current batch."
        $blobs
        $totalFiles += $blobs.Count
        if (0 -eq $blobs.Length) {
            break
        }

        foreach ($blob in $blobs) {
            $allBlobs.Add($blob.Name)
        }

        $continuationToken = $blobs[$blobs.Count - 1].ContinuationToken
    }
    while ($null -ne $continuationToken)

    foreach ($blobName in $allBlobs) {
        "Removing $blobName"
        Remove-AzStorageBlob -Blob $blobName -Container $contentContainer -Force
    }

    "Removed $totalFiles files from container $contentContainer"
    'Clean up completed'

    'Uploading content'
    foreach ($key in $contentItems.Keys) {
        $key
        $contentItem = $contentItems[$key]
        $body = $contentItem | ConvertTo-Json -Depth 100

        Invoke-AzRestMethod -Path "$baseUri/$key`?api-version=$APIVersion" -Method PUT -Payload $body
    }

    'Uploading files'
    $stringIndex = ($mediaFolder + '\').Length
    Get-ChildItem -File -Recurse $mediaFolder `
    | ForEach-Object {
        $name = $_.FullName.Substring($stringIndex)
        Write-Host "Uploading file: $name"
        Set-AzStorageBlobContent -File $_.FullName -Blob $name -Container $contentContainer
    }

    'Publishing developer portal'
    $revision = $BuildVersion ?? [DateTime]::UtcNow.ToString('yyyyMMddHHmm')
    $data = @{
        properties = @{
            description = "CDF Import $revision"
            isCurrent   = $true
        }
    }
    $body = ConvertTo-Json $data
    $publishResponse = Invoke-AzRestMethod -Path "$baseUri/portalRevisions/$($revision)?api-version=$APIVersion" -Method PUT -Payload $body
    $publishResponse

    if ($publishResponse.StatusCode -le 299) {
        'Import completed'
        return
    }
    else {
        Write-Host "Invoke-AzRestMethod -Path "$baseUri/portalRevisions/$($revision)?api-version=$APIVersion" -Method PUT -Payload $body"
        Write-Host $publishResponse
        throw 'Could not publish developer portal'
    }

}

Function Import-ApimPortalConfig {
    <#
    .SYNOPSIS

    Configures the platform Application Gateway ingress for an APIM portal.

    .DESCRIPTION
    Setup Azure Application Gateway for APIM application developer portal.

    .PARAMETER CdfConfig
    APIM Application configuration

    .PARAMETER PortalConfig
    Name of the APIM portal config template. Defaults to 'portal-config'

    .PARAMETER BuildVersion
    Version used in description

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

        [Parameter(Mandatory = $false, HelpMessage = 'Version used in description')]
        [string] $BuildVersion = $null,

        [Parameter(Mandatory = $false)]
        [string] $TemplateDir = "."
    )

    $portalConfigPath = "$TemplateDir/application/$($CdfConfig.Application.Config.templateName)/$($CdfConfig.Application.Config.templateVersion)/templates/$PortalConfig"
    if (!(Test-Path $portalConfigPath) ) {
        throw "Could not find portal config '$PortalConfig' at [$portalConfigPath]"
    }

    $currAzCtx = Get-AzContext
    Set-AzContext -SubscriptionId $CdfConfig.Platform.Env.subscriptionId

    Import-APIMDeveloperPortal `
        -ResourceGroupName $CdfConfig.Application.ResourceNames.appResourceGroupName `
        -APIMName $CdfConfig.Application.ResourceNames.apimName `
        -BuildVersion $BuildVersion `
        -ImportFolder $portalConfigPath

    Set-AzContext $currAzCtx
}
