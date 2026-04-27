targetScope = 'subscription'

/////////////////////////////////
// Template variables
// This bicep script deploys a 'application' for 'blank' version v1'
metadata template = 'application-blank-v1'
var templateScope = 'application'
var templateName = 'blank'
var templateVersion = 'v1'

/////////////////////////////////
// Parameters

param location string = deployment().location

@description('Environment settings of the Platform for which the Application template is being deployed')
param platformEnv object

@description('The platform for which the application deployment is being executed')
param platformConfig object

@description('Features of the Platform for which the Application template is being deployed')
param platformFeatures object

@description('Network config of the Platform for which the Application template is being deployed')
param platformNetworkConfig object

@description('Resource names of the Platform for which the Application template is being deployed')
param platformResourceNames object

@description('Additional tags you would like to be applied to all resources in this module. The module sets predefined common tags to resources')
param applicationTags object

@description('Application environment')
param applicationEnv object

@description('Application features')
param applicationFeatures object

@description('Application config')
param applicationConfig object

@description('Application network configuration')
param applicationNetworkConfig object

@description('Application access control configuration')
param applicationAccessControl object

/////////////////////////////////
// Variables
var varAccessControl = {}

var varPlatformKey = '${platformConfig.platformId}${platformConfig.instanceId}'
var varApplicationKey = '${templateName}${applicationConfig.instanceId}'
var varPlatformEnvKey = '${varPlatformKey}${platformEnv.nameId}'
var varApplicationEnvKey = '${varApplicationKey}${applicationEnv.nameId}'

var varRegionCode = platformEnv.regionCode
var varRegionName = platformEnv.regionName

// Resource tags for source and build
var varTags = union(
  // Platform configuration tags
  applicationTags,
  // CDF template tags
  {
    TemplateName: templateName
    TemplateVersion: templateVersion
    TemplateScope: templateScope
    TemplateInstance: '${varPlatformKey}-${varApplicationKey}-${varRegionCode}'
    TemplateEnv: applicationEnv.definitionId
  }
)

var applicationResourceNames = {
  // Resource Groups
  appResourceGroupName: 'rg-${varPlatformKey}-${varApplicationKey}-application-${applicationEnv.nameId}-${varRegionCode}'

  // TODO: Add resource names here
}

/////////////////////////////////
// Modules and Resources

resource appResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: applicationResourceNames.appResourceGroupName
  location: location
  tags: varTags
}

// TODO: Add resources and modules here

/////////////////////////
// Deployment Config
var varApplicationConfig = union(applicationConfig, {
  // TODO: Add output config here
})

var deploymentConfig = {
  Tags: varTags
  Env: applicationEnv
  Features: applicationFeatures
  Config: varApplicationConfig
  ResourceNames: applicationResourceNames
  NetworkConfig: applicationNetworkConfig
  AccessControl: varAccessControl
}

/////////////////////////
// Outputs
output applicationTags object = deploymentConfig.Tags
output applicationEnv object = deploymentConfig.Env
output applicationFeatures object = deploymentConfig.Features
output applicationConfig object = deploymentConfig.Config
output applicationResourceNames object = deploymentConfig.ResourceNames
output applicationNetworkConfig object = deploymentConfig.NetworkConfig
output applicationAccessControl object = deploymentConfig.AccessControl
