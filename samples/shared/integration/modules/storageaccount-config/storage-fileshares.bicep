targetScope = 'resourceGroup'

param storageAccountName string
param fileshareDefinitions array = []

resource storageFileShares 'Microsoft.Storage/storageAccounts/fileServices/shares@2021-09-01' = [
  for fileshareDefinition in fileshareDefinitions: {
    name: '${storageAccountName}/default/${fileshareDefinition.name}'
    properties: {
      metadata: contains(fileshareDefinition, 'metadata') ? fileshareDefinition.metadata : {}
      shareQuota: contains(fileshareDefinition, 'shareQuota') ? fileshareDefinition.shareQuota : 5120
    }
  }
]
