$Params = @{
  "Path"                 = "$PSScriptRoot/CDFModule.psd1"
  "Author"               = 'Andreas Stenlund'
  "CompanyName"          = 'Epical Sweden AB'
  "Version    "          = '1.1.0'
  "RootModule"           = 'CDFModule.psm1'
  "GUID"                 = 'da47da88-920e-48c9-9ca6-d9b84d1b8c9d'
  "CompatiblePSEditions" = @('Core')
  "PowerShellVersion"    = '7.4'
  # "RequiredModules"      = @('Az')
  "DefaultCommandPrefix" = 'Cdf'
  # "CmdletsToExport"      = @(
  #   "Add-LogicAppAppSettings"
  #   "Add-CdfGitHubApplicationEnv"
  #   "Add-CdfGitHubPlatformEnv"
  #   "Add-LogicAppServiceProviderConnection"
  #   "Deploy-CdfServiceBusConfig"
  #   "Deploy-CdfServiceLogicAppStd"
  #   "Deploy-CdfStorageAccountConfig"
  #   "Deploy-CdfTemplateApplication"
  #   "Deploy-CdfTemplateDomain"
  #   "Deploy-CdfTemplatePlatform"
  #   "Deploy-CdfTemplateService"
  #   "Get-AzureContext"
  #   "Get-ConfigApplication"
  #   "Get-ConfigDomain"
  #   "Get-CdfConfigPlatform"
  #   "Get-CdfGitHubApplicationConfig"
  #   "Get-CdfGitHubDomainConfig"
  #   "Get-CdfGitHubPlatformConfig"
  #   "Get-ServiceConfig"
  #   "New-StorageAccountFileToken"
  #   "Remove-OrphanAccessPolicies"
  #   "Remove-OrphanRoleAssignments"
  #   "Remove-CdfTemplateApplication"
  #   "Set-LogicAppParameters"
  #   "Update-ConfigFileTokens"
  # )
  "VariablesToExport"    = ''
  "AliasesToExport"      = @()
  "Description"          = 'Azure CDF Module'
}
New-ModuleManifest @Params
