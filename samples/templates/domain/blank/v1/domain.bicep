targetScope = 'subscription'

/////////////////////////////////
// Template variables
// This bicep script deploys a 'domain' for 'blank' version v1'
metadata template = 'domain-blank-v1'
var templateScope = 'domain'
var templateName = 'blank'
var templateVersion = 'v1'

/////////////////////////////////
// Parameters
param location string = deployment().location

@description('Environment settings of the Platform for which the Domain template is being deployed')
param platformEnv object

@description('Platform config for which the Domain template is being deployed')
param platformConfig object

@description('Features of the Platform for which the Domain template is being deployed')
param platformFeatures object

@description('Network config of the Platform for which the Domain template is being deployed')
param platformNetworkConfig object

@description('Resource names of the Platform for which the Domain template is being deployed')
param platformResourceNames object

@description('Environment settings of the Application for which the Domain template is being deployed')
param applicationEnv object

@description('Features of the Application for which the Domain template is being deployed')
param applicationFeatures object

@description('Application config of the Platform for which the Domain template is being deployed')
param applicationConfig object

@description('Network configuration of the Application for which the Domain template is being deployed')
param applicationNetworkConfig object

@description('Resource names of the Application for which the Domain template is being deployed')
param applicationResourceNames object

@description('Additional tags to be applied to all resources in this module. The module sets predefined common tags to resources')
param domainTags object = {}

@description('Domain configuration')
param domainConfig object

@description('Domain features')
param domainFeatures object

@description('Domain network configuration')
param domainNetworkConfig object

@description('Domain access control settings')
param domainAccessControl object

var varAccessControl = {}

/////////////////////////////////
// Variables
var varDomainName = domainConfig.domainName
var varPlatformKey = '${platformConfig.platformId}${platformConfig.instanceId}'
var varApplicationKey = '${applicationConfig.applicationId}${applicationConfig.instanceId}'
var varPlatformEnvKey = '${varPlatformKey}${platformEnv.nameId}'
var varApplicationEnvKey = '${varApplicationKey}${applicationEnv.nameId}'

var varRegionCode = platformEnv.regionCode
var varRegionName = platformEnv.regionName

// Resource tags for source and build
var varTags = union(
  // Platform configuration tags
  domainTags,
  // CDF template tags
  {
    TemplateName: templateName
    TemplateVersion: templateVersion
    TemplateScope: templateScope
    TemplateInstance: '${varPlatformKey}-${varApplicationKey}-${varDomainName}-${varRegionCode}'
    TemplateEnv: applicationEnv.definitionId
  }
)

// Resource Names
var baseStorageAccountName = 'st${varPlatformKey}${varDomainName}${applicationConfig.instanceId}${applicationEnv.nameId}${varRegionCode}'

var domainResourceNames = {
  // Resource Groups
  domainResourceGroupName: 'rg-${varPlatformKey}-${varApplicationKey}-${varDomainName}-${applicationEnv.nameId}-${varRegionCode}'

  // Storage Account (null when feature is disabled)
  storageAccountName: domainFeatures.enableStorageAccount == true
    ? take(replace(baseStorageAccountName, '-', ''), 24)
    : null
}

/////////////////////////////////
// Modules and Resources

resource domainResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: domainResourceNames.domainResourceGroupName
  location: location
  tags: varTags
}

// Storage Account - feature gated
module modDomainStorageAccount 'modules/domain-storageaccount.bicep' = if (domainFeatures.enableStorageAccount) {
  name: '${varPlatformKey}-${varApplicationKey}-${varDomainName}-domain-storageaccount'
  scope: domainResourceGroup
  params: {
    location: location
    tags: varTags
    storageAccountName: domainResourceNames.storageAccountName!
  }
}

/////////////////////////
// Deployment Config
var varDomainConfig = union(domainConfig, {
  domainStorageAccountName: domainFeatures.enableStorageAccount
    ? modDomainStorageAccount.outputs.storageAccountName
    : null
})

var deploymentConfig = {
  Tags: varTags
  Config: varDomainConfig
  Features: domainFeatures
  ResourceNames: domainResourceNames
  NetworkConfig: domainNetworkConfig
  AccessControl: varAccessControl
}

/////////////////////////
// Outputs
output domainEnv object = applicationEnv
output domainTags object = deploymentConfig.Tags
output domainConfig object = deploymentConfig.Config
output domainFeatures object = deploymentConfig.Features
output domainResourceNames object = deploymentConfig.ResourceNames
output domainNetworkConfig object = domainNetworkConfig
output domainAccessControl object = deploymentConfig.AccessControl
