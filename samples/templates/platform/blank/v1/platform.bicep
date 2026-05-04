targetScope = 'subscription'
/////////////////////////////////
// Template variables
// This bicep script deploys a 'platform' for 'blank' version 'v1'
metadata template = 'platform-blank-v1'
var templateScope = 'platform'
var templateName = 'blank'
var templateVersion = 'v1'
/////////////////////////////////

param location string = deployment().location

@description('Additional tags you would like to be applied to all resources in this module. The module sets predefined common tags to resources')
param platformTags object = {}

@description('Platform environment settings')
param platformEnv object

@description('Platform configuration settings')
param platformConfig object

@description('Platform features')
// param platformFeatures PlatformFeatures
param platformFeatures object

@description('Network configuration for the landing zone spoke')
// param platformNetworkConfig PlatformNetworkConfig
param platformNetworkConfig object

@description('Access control configuration for the landing zone spoke')
// param platformAccessControl PlatformAccessControl
param platformAccessControl object

///////////////////////////////////////
// Variables
var varAccessControl = {}

var varRegionCode = toLower(platformEnv.regionCode)
var varRegionName = toLower(platformEnv.regionName)

var varPlatformKey = '${platformConfig.platformId}${platformConfig.instanceId}'
var varPlatformEnvKey = '${varPlatformKey}${toLower(platformEnv.nameId)}'

var varTags = union(
  // Platform configuration tags
  platformTags,
  // CDF template tags
  {
    TemplateName: templateName
    TemplateVersion: templateVersion
    TemplateScope: templateScope
    TemplateInstance: '${varPlatformKey}-${varRegionCode}'
    TemplateEnv: platformEnv.definitionId
  }
)

var baseStorageAccountName = 'st${varPlatformKey}${toLower(platformEnv.nameId)}${varRegionCode}'

var platformResourceNames = {
  // Resource Groups
  platformResourceGroupName: 'rg-${varPlatformKey}-platform-${toLower(platformEnv.nameId)}-${varRegionName}'

  // Storage Account (null when feature is disabled)
  storageAccountName: platformFeatures.enableStorageAccount == true
    ? take(replace(baseStorageAccountName, '-', ''), 24)
    : null
}

/////////////////////////
// Resources and modules

// Resource Groups
resource platformRG 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: platformResourceNames.platformResourceGroupName
  location: location
  tags: varTags
}

// Storage Account - feature gated
module modPlatformStorageAccount 'modules/platform-storageaccount.bicep' = if (platformFeatures.enableStorageAccount) {
  name: '${varPlatformEnvKey}-platform-storageaccount'
  scope: platformRG
  params: {
    location: location
    tags: varTags
    storageAccountName: platformResourceNames.storageAccountName!
  }
}

/////////////////////////
// Deployment Config
var varPlatformConfig = union(platformConfig, {
  platformStorageAccountName: platformFeatures.enableStorageAccount
    ? modPlatformStorageAccount.outputs.storageAccountName
    : null
})

var deploymentConfig = {
  Env: platformEnv
  Tags: varTags
  Features: platformFeatures
  Config: varPlatformConfig
  NetworkConfig: platformNetworkConfig
  ResourceNames: platformResourceNames
  AccessControl: varAccessControl
}

///////////////////////////////
// Outputs
output platformEnv object = deploymentConfig.Env
output platformTags object = deploymentConfig.Tags
output platformFeatures object = deploymentConfig.Features
output platformConfig object = deploymentConfig.Config
output platformNetworkConfig object = deploymentConfig.NetworkConfig
output platformResourceNames object = deploymentConfig.ResourceNames
output platformAccessControl object = deploymentConfig.AccessControl
