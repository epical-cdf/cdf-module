@description('Azure region for the storage account')
param location string

@description('Tags to apply to the storage account')
param tags object

@description('Name of the storage account')
param storageAccountName string

resource domainStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  tags: tags
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

output storageAccountName string = domainStorageAccount.name
output storageAccountId string = domainStorageAccount.id
output storageAccountHostnames object = {
  blob: '${domainStorageAccount.name}.blob.${environment().suffixes.storage}'
  file: '${domainStorageAccount.name}.file.${environment().suffixes.storage}'
  table: '${domainStorageAccount.name}.table.${environment().suffixes.storage}'
  queue: '${domainStorageAccount.name}.queue.${environment().suffixes.storage}'
}
