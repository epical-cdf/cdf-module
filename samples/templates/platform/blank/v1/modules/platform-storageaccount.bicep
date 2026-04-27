@description('Azure region for the storage account')
param location string

@description('Tags to apply to the storage account')
param tags object

@description('Name of the storage account')
param storageAccountName string

resource platformStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  tags: tags
  properties: {
    publicNetworkAccess: 'Enabled'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
  }
}

output storageAccountName string = platformStorageAccount.name
output storageAccountId string = platformStorageAccount.id
output storageAccountHostnames object = {
  blob: '${platformStorageAccount.name}.blob.${environment().suffixes.storage}'
  file: '${platformStorageAccount.name}.file.${environment().suffixes.storage}'
  table: '${platformStorageAccount.name}.table.${environment().suffixes.storage}'
  queue: '${platformStorageAccount.name}.queue.${environment().suffixes.storage}'
}
