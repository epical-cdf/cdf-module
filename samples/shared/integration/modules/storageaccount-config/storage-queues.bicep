targetScope = 'resourceGroup'

param storageAccountName string
param queueDefinitions array = []

resource storageQueues 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-01-01' = [
  for queueDefinition in queueDefinitions: {
    name: '${storageAccountName}/default/${queueDefinition.name}'
    properties: {
      metadata: contains(queueDefinition, 'metadata') ? queueDefinition.metadata : {}
    }
  }
]
