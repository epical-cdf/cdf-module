/////////////////////////////////
// Template: api-sample-v1
// A minimal APIM API deployment template for the 'sample' service type.
// Real implementations should use api-openapi-yaml-v1 or similar.
metadata cdfTemplate = {
  template: 'api-sample-v1'
  templateScope: 'service'
  templateName: 'api-sample'
  templateVersion: 'v1'
}
/////////////////////////////////
targetScope = 'resourceGroup'

/////////////////////////////////
// CDF standard params
param parTags object = {}
param parCdfApplication object = {}
param domainName string
param serviceName string
param serviceGroup string
param serviceType string = ''
param serviceTemplate string = ''

/////////////////////////////////
// API params
param apiName string
param apiPath string
param apiProtocols array
param apiDisplayName string
param apiPolicy string
param apiSpecDoc string
param apiOperations array
param apiProductNames array = []
param apiNamedValues array = []

/////////////////////////////////
// Resolve APIM instance from application config
var varApimServiceName = parCdfApplication.ResourceNames.apimName

/////////////////////////////////
// APIM service reference
resource resApimService 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: varApimServiceName
}

/////////////////////////////////
// API definition
resource resApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  name: apiName
  parent: resApimService
  properties: {
    protocols: apiProtocols
    displayName: apiDisplayName
    apiRevision: '1'
    apiRevisionDescription: '${parTags.BuildRun}/${parTags.BuildRepo}/${parTags.BuildBranch}/${parTags.BuildCommit}'
    path: apiPath
    format: 'openapi'
    value: apiSpecDoc
    subscriptionRequired: false
  }
}

/////////////////////////////////
// Global API policy
resource resApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  name: 'policy'
  parent: resApi
  properties: {
    format: 'rawxml'
    value: apiPolicy
  }
}

/////////////////////////////////
// Operation policies
resource resOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = [
  for operation in apiOperations: {
    name: '${apiName}/${operation.name}/policy'
    dependsOn: [resApi]
    properties: {
      format: 'rawxml'
      value: operation.policy
    }
  }
]

/////////////////////////////////
// Tags
resource resApiTag 'Microsoft.ApiManagement/service/apis/tags@2024-05-01' = {
  name: 'cdf-${domainName}-${serviceName}'
  parent: resApi
  properties: {}
}
