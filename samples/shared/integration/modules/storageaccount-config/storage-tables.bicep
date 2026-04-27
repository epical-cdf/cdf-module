targetScope = 'resourceGroup'

param storageAccountName string
param tableDefinitions array = []

resource storageTables 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-01-01' = [
  for tableDefinition in tableDefinitions: {
    name: '${storageAccountName}/default/${tableDefinition.name}'
    properties: {}
  }
]
