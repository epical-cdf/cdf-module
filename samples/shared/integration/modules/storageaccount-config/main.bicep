targetScope = 'resourceGroup'

param domainName string
param serviceName string
param storageAccountName string
param storageAccountConfig object = loadJsonContent('storageaccount.sample.config.json')

module modSTContainers 'storage-containers.bicep' = {
  name: take('modSTContainers-${storageAccountName}-${domainName}-${serviceName}', 64)
  scope: resourceGroup()
  params: {
    storageAccountName: storageAccountName
    containerDefinitions: storageAccountConfig.containers
  }
}

module modSTFileShares 'storage-fileshares.bicep' = {
  name: take('modSTFileShares-${storageAccountName}-${domainName}-${serviceName}', 64)
  scope: resourceGroup()
  params: {
    storageAccountName: storageAccountName
    fileshareDefinitions: storageAccountConfig.fileShares
  }
}

module modSTQueues 'storage-queues.bicep' = {
  name: take('modSTQueues-${storageAccountName}-${domainName}-${serviceName}', 64)
  scope: resourceGroup()
  params: {
    storageAccountName: storageAccountName
    queueDefinitions: storageAccountConfig.queues
  }
}

module modSTTables 'storage-tables.bicep' = {
  name: take('modSTTables-${storageAccountName}-${domainName}-${serviceName}', 64)
  scope: resourceGroup()
  params: {
    storageAccountName: storageAccountName
    tableDefinitions: storageAccountConfig.tables
  }
}
