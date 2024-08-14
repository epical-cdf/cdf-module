Function Get-ConnectionDefinitions {
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
        [hashtable]$CdfConfig
    )

    $connectionDefinitions = @{
        PlatformKeyVault             = @{
            ConnectionKey   = "platformKeyVault"
            ServiceProvider = "keyvault"
            Scope           = "Platform"
            IsEnabled       = $CdfConfig.Platform.Features.enableKeyVault
            IsApiConnection = $false
        }
        PlatformServiceBus           = @{
            ConnectionKey   = "platformServiceBus"
            ServiceProvider = "servicebus"
            Scope           = "Platform"
            IsEnabled       = $CdfConfig.Platform.Features.enableServiceBus
            IsApiConnection = $false
        }
        PlatformEventGridTopicApi    = @{
            ConnectionKey   = "platformEventGridTopic"
            ServiceProvider = "azureeventgridpublish"
            Scope           = "Platform"
            IsEnabled       = $CdfConfig.Platform.Features.enableEventGridTopic
            IsApiConnection = $true
        }
        PlatformEventGridTopic       = @{
            ConnectionKey   = "platformEventGridTopic"
            ServiceProvider = "eventGridPublisher"
            Scope           = "Platform"
            IsEnabled       = $CdfConfig.Platform.Features.enableEventGridTopic
            IsApiConnection = $false
        }
        PlatformStorageAccountBlob   = @{
            ConnectionKey   = "platformStorageAccount"
            ServiceProvider = "AzureBlob"
            Scope           = "Platform"
            IsEnabled       = $CdfConfig.Platform.Features.enableStorageAccount
            IsApiConnection = $false
        }
        PlatformStorageAccountFile   = @{
            ConnectionKey   = "platformStorageAccount"
            ServiceProvider = "azurefile"
            Scope           = "Platform"
            IsEnabled       = $CdfConfig.Platform.Features.enableStorageAccount
            IsApiConnection = $true
        }
        PlatformStorageAccountQueues = @{
            ConnectionKey   = "platformStorageAccount"
            ServiceProvider = "azurequeues"
            Scope           = "Platform"
            IsEnabled       = $CdfConfig.Platform.Features.enableStorageAccount
            IsApiConnection = $false
        }
        PlatformStorageAccountTables = @{
            ConnectionKey   = "platformStorageAccount"
            ServiceProvider = "azureTables"
            Scope           = "Platform"
            IsEnabled       = $CdfConfig.Platform.Features.enableStorageAccount
            IsApiConnection = $false
        }
        ApplicationKeyVault          = @{
            ConnectionKey   = "applicationKeyVault"
            ServiceProvider = "keyvault"
            Scope           = "Application"
            IsEnabled       = $CdfConfig.Application.Features.enableKeyVault
        }
        AppSftpStorageAccountBlob    = @{
            ConnectionKey   = "sftpStorageAccount"
            ServiceProvider = "AzureBlob"
            Scope           = "Application"
            IsEnabled       = $CdfConfig.Application.Features.enableSftpStorageAccount
            IsApiConnection = $false
        }
        DomainKeyVault               = @{
            ConnectionKey   = "domainKeyVault"
            ServiceProvider = "keyvault"
            Scope           = "Domain"
            IsEnabled       = $CdfConfig.Domain.Features.enableKeyVault
            IsApiConnection = $false
        }
        DomainStorageAccountBlob     = @{
            ConnectionKey   = "domainStorageAccount"
            ServiceProvider = "AzureBlob"
            Scope           = "Domain"
            IsEnabled       = $CdfConfig.Domain.Features.enableStorageAccount
            IsApiConnection = $false
        }
        DomainStorageAccountFile     = @{
            ConnectionKey   = "domainStorageAccount"
            ServiceProvider = "azurefile"
            Scope           = "Domain"
            IsEnabled       = $CdfConfig.Domain.Features.enableStorageAccount
            IsApiConnection = $true
        }
        DomainStorageAccountQueues   = @{
            ConnectionKey   = "domainStorageAccount"
            ServiceProvider = "azurequeues"
            Scope           = "Domain"
            IsEnabled       = $CdfConfig.Domain.Features.enableStorageAccount
            IsApiConnection = $false
        }
        DomainStorageAccountTables   = @{
            ConnectionKey   = "domainStorageAccount"
            ServiceProvider = "azureTables"
            Scope           = "Domain"
            IsEnabled       = $CdfConfig.Domain.Features.enableStorageAccount
            IsApiConnection = $false
        }
    }

    return $connectionDefinitions
}