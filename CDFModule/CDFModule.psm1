#Requires -Modules @{ ModuleName="Az.ResourceGraph"; ModuleVersion="1.0.0" }

Get-ChildItem (Split-Path $script:MyInvocation.MyCommand.Path) -Filter 'func_*.ps1' -Recurse | ForEach-Object {
  # Write-Host ($_.FullName)
  . $_.FullName
}
Get-ChildItem "$(Split-Path $script:MyInvocation.MyCommand.Path)\Public\*" -Filter 'func_*.ps1' -Recurse | ForEach-Object {
  # Write-Host """$(($_.BaseName -Split "_")[1])"""
  Export-ModuleMember -Function ($_.BaseName -Split "_")[1]
  Export-ModuleMember ($_.BaseName -Split "_")[1]
}

Set-Alias -Scope Global -Name cdf-profile -Value "Import-CdfProfile" -Description "Load the standard CDFModule profile which includes customized prompt."
Set-Alias -Scope Global -Name cdf-prompt-on -Value "Enable-CdfPrompt"
Set-Alias -Scope Global -Name cdf-prompt-off -Value "Disable-CdfPrompt"

Export-ModuleMember -Alias *
# Get-ChildItem "$(Split-Path $script:MyInvocation.MyCommand.Path)\Private\*" -Filter 'type_*.ps1' -Recurse | ForEach-Object {
#   Add-Type ($_.BaseName -Split "_")[1]
# }

# & ./CDFModule/Private/class_CdfConfig.ps1
# & ./CDFModule/Private/class_CdfEnvironment.ps1

# class CDFConfigParameter : Attribute {
#   [string]$ServiceName
#   [string]$ServiceType
#   [string]$ServiceGroup
#   [string]$ServiceTemplate

#   CDFConfigParameter() {
#   }
  
#   CDFConfigParameter([string]$Name) {
#     if (Test-Path 'cdf-config.json') {
#       $svcConfig = Get-Content -Raw "cdf-config.json" | ConvertFrom-Json -AsHashtable
#       $ServiceName = $svcConfig.ServiceDefaults.ServiceName
#       $ServiceGroup = $svcConfig.ServiceDefaults.ServiceGroup
#       $ServiceType = $svcConfig.ServiceDefaults.ServiceType
#       $ServiceTemplate = $svcConfig.ServiceDefaults.ServiceTemplate
#     }

#     switch ($Name) {
#       'ServiceName' {

#       }
#     }
#     $this.ServiceName = $Target
#   }
# }

# Force import of the CDF PowerShell Profile
Import-Profile
