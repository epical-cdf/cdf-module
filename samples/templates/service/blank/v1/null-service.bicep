targetScope = 'resourceGroup'

/////////////////////////////////
// Template variables
// This bicep script deploys a 'service' template 'blank' version 'v1'
metadata template = 'service-blank-v1'
var templateScope = 'service'
var templateName = 'blank'
var templateVersion = 'v1'

/////////////////////////////////
// Parameters
param location string = resourceGroup().location

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

@description('Domain configuration')
param domainConfig object

@description('Domain features')
param domainFeatures object

@description('Domain network configuration')
param domainNetworkConfig object

@description('Domain access control settings')
param domainAccessControl object

@description('Domain resource names')
param domainResourceNames object

@description('Additional tags to be applied to all resources in this module. The module sets predefined common tags to resources')
param serviceTags object = {}

@description('Service access control settings')
param serviceNetworkConfig object = {}
param serviceAccessControl object = {
  keyVaultRBAC: []
  storageAccountRBAC: []
}

param serviceName string
param serviceGroup string
param serviceType string
param serviceTemplate string

/////////////////////////////////
// Variables
var varAccessControl = {}

var domainName = domainConfig.domainName
var platformKey = '${platformConfig.platformId}${platformConfig.instanceId}'
var applicationKey = '${applicationConfig.applicationId}${applicationConfig.instanceId}'
var platformEnvKey = '${platformKey}${platformEnv.nameId}'
var applicationEnvKey = '${applicationKey}${applicationEnv.nameId}'

var regionCode = platformEnv.regionCode
var regionName = platformEnv.regionName

// Resource tags for source and build
var varTags = union(
  // Platform configuration tags
  serviceTags,
  // CDF template tags
  {
    TemplateName: templateName
    TemplateVersion: templateVersion
    TemplateScope: templateScope
    TemplateInstance: '${platformKey}-${applicationKey}-${domainName}-${serviceName}-${regionCode}'
    TemplateEnv: applicationEnv.definitionId
  }
)

// Resource Names
var serviceResourceNames = {
  serviceResourceGroup: resourceGroup().name
  serviceName: 'nsg-${platformKey}-${applicationKey}-${domainName}-${serviceName}-${applicationEnv.nameId}-${regionCode}'
}

/////////////////////////////////
// Modules and Resources

// Reference the domain storage account (deployed by the domain template)
resource domainStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = if (domainFeatures.enableStorageAccount) {
  name: domainResourceNames.storageAccountName
}

// Dummy service: network security group
resource service 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: serviceResourceNames.serviceName
  location: location
  tags: varTags
  properties: {
    securityRules: []
  }
}

/////////////////////////
// Deployment Config
var varServiceConfig = {
  templateScope: templateScope
  templateName: templateName
  templateVersion: templateVersion
  serviceName: serviceName
  serviceType: serviceType
  serviceGroup: serviceGroup
  serviceTemplate: serviceTemplate
  domainStorageAccountName: domainFeatures.enableStorageAccount ? domainStorageAccount.name : null
}

var deploymentConfig = {
  Tags: varTags
  Config: varServiceConfig
  Features: {}
  ResourceNames: serviceResourceNames
  NetworkConfig: serviceNetworkConfig
  AccessControl: varAccessControl
}

// TODO: Store config in keyvault?
// module modStoreCdfConfig 'modules/store-keyvault-secret/store-keyvault-secret.bicep' = if (domainFeatures.enableKeyVault) {
//   name: '${varPlatformKey}-${varApplicationKey}-${varDomainName}-modStoreCdfConfig'
//   scope: domainResourceGroup
//   params: {
//     vaultName: modShared.outputs.domainKeyVaultName
//     secretName: 'CdfConfig'
//     secretValue: string(deploymentConfig)
//     contentType: 'application/json'
//   }
// }

/////////////////////////
// Outputs
output serviceEnv object = applicationEnv
output serviceTags object = deploymentConfig.Tags
output serviceConfig object = deploymentConfig.Config
output serviceFeatures object = deploymentConfig.Features
output serviceResourceNames object = deploymentConfig.ResourceNames
output serviceNetworkConfig object = serviceNetworkConfig
output serviceAccessControl object = deploymentConfig.AccessControl
