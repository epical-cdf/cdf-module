targetScope = 'resourceGroup'

param storageAccountName string
param containerDefinitions array = []

resource storageContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-09-01' = [
  for containerDefinition in containerDefinitions: {
    name: toLower('${storageAccountName}/default/${containerDefinition.name}')
    properties: {
      metadata: contains(containerDefinition, 'metadata') ? containerDefinition.metadata : {}
      publicAccess: contains(containerDefinition, 'publicAccess') ? containerDefinition.publicAccess : 'None'
      immutableStorageWithVersioning: {
        enabled: contains(containerDefinition, 'immutableVersioning') ? containerDefinition.immutableVersioning : false
      }
    }
  }
]
