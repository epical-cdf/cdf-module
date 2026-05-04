@description('Azure region for the storage account')
param location string

@description('Tags to apply to the storage account')
param tags object

@description('Name of the storage account')
param storageAccountName string

resource applicationStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
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
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
  }
}

output storageAccountName string = applicationStorageAccount.name
output storageAccountId string = applicationStorageAccount.id
output storageAccountHostnames object = {
  blob: '${applicationStorageAccount.name}.blob.${environment().suffixes.storage}'
  file: '${applicationStorageAccount.name}.file.${environment().suffixes.storage}'
  table: '${applicationStorageAccount.name}.table.${environment().suffixes.storage}'
  queue: '${applicationStorageAccount.name}.queue.${environment().suffixes.storage}'
}
