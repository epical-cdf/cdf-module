Function Get-TokenValues {
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
        [hashtable]$CdfConfig,
        [Parameter(Mandatory = $false)]
        [switch] $NoAlias,
        [Parameter(Mandatory = $false)]
        [switch] $NoOldAPIM
    )

    $tokenValues = [ordered] @{}

    if ($false -eq $NoAlias -and $null -ne $CdfConfig.Service) {
        # These Aliases are short names for Commonly used attributes
        $tokenValues = [ordered] @{
            PlatformKey       = ($CdfConfig.Platform.Config.platformId + $CdfConfig.Platform.Config.instanceId)
            PlatformEnvKey    = ($CdfConfig.Platform.Config.platformId + $CdfConfig.Platform.Config.instanceId + $CdfConfig.Platform.Env.nameId)
            ApplicationKey    = ($CdfConfig.Application.Config.applicationId + $CdfConfig.Platform.Config.instanceId)
            ApplicationEnvKey = ($CdfConfig.Application.Config.applicationId + $CdfConfig.Platform.Config.instanceId + $CdfConfig.Application.Env.nameId)
            EnvRegion         = $CdfConfig.Platform.Env.region
            EnvRegionCode     = $CdfConfig.Platform.Env.regionCode
            EnvRegionName     = $CdfConfig.Platform.Env.regionName
            EnvDefinitionId   = $CdfConfig.Application.Env.definitionId
            EnvNameId         = $CdfConfig.Application.Env.nameId
            EnvShortName      = $CdfConfig.Application.Env.shortName
            DomainName        = $CdfConfig.Domain.Config.domainName
            DomainStorageName = $CdfConfig.Domain.ResourceNames.storageAccountName
            ServiceName       = $CdfConfig.Service.Config.serviceName
            ServiceGroup      = $CdfConfig.Service.Config.serviceGroup
            ServiceType       = $CdfConfig.Service.Config.serviceType
            ServiceTemplate   = $CdfConfig.Service.Config.serviceTemplate
        }
    }

    if ($null -ne $env:GITHUB_RUN_ID) {
        $tokenValues += [ordered] @{
            BuildRepo     = $env:GITHUB_REPOSITORY
            BuildBranch   = $env:GITHUB_REF_NAME
            BuildCommit   = $env:GITHUB_SHA
            BuildPipeline = $env:GITHUB_WORKFLOW
            BuildRun      = $env:GITHUB_RUN_ID
        }
    }
    elseif ($null -ne $env:BUILD_BUILDNUMBER) {
        $tokenValues += [ordered] @{
            BuildRepo     = $env:BUILD_REPOSITORY_NAME
            BuildBranch   = $env:BUILD_SOURCEBRANCH
            BuildCommit   = $env:BUILD_SOURCEVERSION
            BuildPipeline = $env:BUILD_DEFINITIONNAME
            BuildRun      = $env:BUILD_BUILDNUMBER
        }
    }
    else {
        $azCtx = Get-AzContext -ErrorAction:SilentlyContinue -WarningAction:SilentlyContinue
        $tokenValues += [ordered] @{
            BuildRepo     = $(Split-Path -Leaf (git remote get-url origin))
            BuildBranch   = $(git branch --show-current)
            BuildCommit   = $(git rev-parse --short HEAD)
            BuildPipeline = $azCtx ? $azCtx.Account.Id : 'local'
            BuildRun      = "local"
        }
    }

    if ($false -eq $NoOldAPIM -and $null -ne $CdfConfig.Service) {
        # These Aliases are short names for Commonly used attributes
        $tokenValues += [ordered] @{
            APIM_IDENTITY_CLIENT_ID    = $CdfConfig.Application.Config.appIdentityClientId
            APIM_IDENTITY_PRINCIPAL_ID = $CdfConfig.Application.Config.appIdentityPrincipalId
            ENV_REGION                 = $CdfConfig.Application.Env.region
            ENV_REGION_CODE            = $CdfConfig.Application.Env.regionCode
            ENV_REGION_NAME            = $CdfConfig.Application.Env.regionName
            ENV_ID                     = $CdfConfig.Application.Env.definitionId
            ENV_NAME_ID                = $CdfConfig.Application.Env.nameId
            ENV_SHORT_NAME             = $CdfConfig.Application.Env.shortName
            ENV_PURPOSE                = $CdfConfig.Application.Env.purpose
            ENV_QUALITY                = $CdfConfig.Application.Env.quality
            PLATFORM_ID                = $CdfConfig.Platform.Config.platformId
            PLATFORM_INSTANCE          = $CdfConfig.Platform.Config.instanceId
            APPLICATION_ID             = $CdfConfig.Application.Config.applicationId
            APPLICATION_INSTANCE       = $CdfConfig.Application.Config.instanceId
            DOMAIN_NAME                = $CdfConfig.Domain.Config.domainName
            SERVICE_NAME               = $CdfConfig.Service.Config.serviceName
            SERVICE_GROUP              = $CdfConfig.Service.Config.serviceGroup
            SERVICE_TYPE               = $CdfConfig.Service.Config.serviceType
            SERVICE_TEMPLATE           = $CdfConfig.Service.Config.serviceTemplate
            GITHUB_REPOSITORY          = 'local'
            GITHUB_REF_NAME            = 'local'
            GITHUB_SHA                 = 'local'
            GITHUB_WORKFLOW            = 'local'
            GITHUB_RUN_NUMBER          = 'local'

        }
    }

    if ($null -ne $CdfConfig.Platform) {
        $tokenValues += [ordered] @{
            'Platform.Config.TemplateScope'   = $CdfConfig.Platform.Config.templateScope
            'Platform.Config.TemplateVersion' = $CdfConfig.Platform.Config.templateVersion
            'Platform.Config.PlatformId'      = $CdfConfig.Platform.Config.platformId
            'Platform.Config.InstanceId'      = $CdfConfig.Platform.Config.instanceId
            'Platform.Env.TenantId'           = $CdfConfig.Platform.Env.tenantId
            'Platform.Env.SubscriptionId'     = $CdfConfig.Platform.Env.subscriptionId
            'Platform.Env.Region'             = $CdfConfig.Platform.Env.region
            'Platform.Env.RegionCode'         = $CdfConfig.Platform.Env.regionCode
            'Platform.Env.RegionName'         = $CdfConfig.Platform.Env.regionName
            'Platform.Env.DefinitionId'       = $CdfConfig.Platform.Env.definitionId
            'Platform.Env.NameId'             = $CdfConfig.Platform.Env.nameId
            'Platform.Env.ShortName'          = $CdfConfig.Platform.Env.shortName
        }
    }

    if ($null -ne $CdfConfig.Application) {
        $tokenValues += [ordered] @{
            'Application.Config.TemplateScope'               = $CdfConfig.Platform.Config.templateScope
            'Application.Config.TemplateName'                = $CdfConfig.Platform.Config.templateName
            'Application.Config.TemplateVersion'             = $CdfConfig.Platform.Config.templateVersion
            'Application.Config.PlatformId'                  = $CdfConfig.Platform.Config.platformId
            'Application.Config.InstanceId'                  = $CdfConfig.Platform.Config.instanceId
            'Application.Env.TenantId'                       = $CdfConfig.Application.Env.tenantId
            'Application.Env.SubscriptionId'                 = $CdfConfig.Application.Env.subscriptionId
            'Application.Env.DefinitionId'                   = $CdfConfig.Application.Env.definitionId
            'Application.Env.NameId'                         = $CdfConfig.Application.Env.nameId
            'Application.Env.ShortName'                      = $CdfConfig.Application.Env.shortName
            'Application.ResourceNames.AppResourceGroupName' = $CdfConfig.Application.ResourceNames.appResourceGroupName
            'Application.ResourceNames.ApimName'             = $CdfConfig.Application.ResourceNames.apimName
        }

        if ($CdfConfig.Application.Config.appIdentityClientId) { $tokenValues['Application.Config.AppIdentityClientId'] = $CdfConfig.Application.Config.appIdentityClientId }
        if ($CdfConfig.Application.Config.appIdentityPrincipalId) { $tokenValues['Application.Config.AppIdentityPrincipalId'] = $CdfConfig.Application.Config.appIdentityPrincipalId }
    }

    if ($null -ne $CdfConfig.Domain) {
        $tokenValues += [ordered] @{
            'Domain.Config.DomainName' = $CdfConfig.Domain.Config.domainName
        }
    }

    if ($null -ne $CdfConfig.Service) {
        $tokenValues += [ordered] @{
            'Service.Config.ServiceName'     = $CdfConfig.Service.Config.serviceName
            'Service.Config.ServiceGroup'    = $CdfConfig.Service.Config.serviceGroup
            'Service.Config.ServiceType'     = $CdfConfig.Service.Config.serviceType
            'Service.Config.ServiceTemplate' = $CdfConfig.Service.Config.serviceTemplate
        }
    }
    return $tokenValues
}