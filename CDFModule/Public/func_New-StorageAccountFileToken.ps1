Function New-StorageAccountFileToken {
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $true)]
    [Object] $AzCtx,
    [Parameter(Mandatory = $true)]
    [string] $StorageAccountRG,
    [Parameter(Mandatory = $true)]
    [string] $StorageAccountName,
    [Parameter(Mandatory = $false)]
    [int] $ValidityDays = 90
 
  )

  # Get storage account context
  $storageContext = (Get-AzStorageAccount `
      -DefaultProfile $AzCtx `
      -ResourceGroupName $StorageAccountRG `
      -Name $StorageAccountName).Context
  
  # Set the token time range
  $startTime = Get-Date -Hour 0 -Minute 00
  $endTime = $startTime.AddDays($ValidityDays)
  
  # Create new SAS token
  $sasToken = New-AzStorageAccountSASToken `
    -Context $storageContext `
    -ResourceType Service, Container, Object `
    -Service "File, Blob, Queue, Table"  `
    -StartTime $endTime `
    -ExpiryTime $endTime `
    -Permission "racwdlup"

  return $sasToken
}
