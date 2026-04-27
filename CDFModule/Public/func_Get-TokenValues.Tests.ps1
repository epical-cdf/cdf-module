BeforeAll {
    $repoRoot = Split-Path -Parent (Resolve-Path $PSCommandPath/../..)
    $testFolder = Split-Path -Parent $PSCommandPath
    $testFileName = (Split-Path -Leaf $PSCommandPath).Replace(".Tests.", ".")
    . $testFolder/$($testFileName.Replace("Get-TokenValues", "Get-ConfigPlatform"))
    . $testFolder/$($testFileName.Replace("Get-TokenValues", "Get-ConfigApplication"))
    . $testFolder/$($testFileName.Replace("Get-TokenValues", "Get-ConfigDomain"))
    . $testFolder/$($testFileName.Replace("Get-TokenValues", "Get-Config"))
    . $testFolder/$testFileName

    $env:CDF_INFRA_SOURCE_PATH = Join-Path -Path $repoRoot -ChildPath "tests/samples/sources"
    $env:CDF_INFRA_TEMPLATES_PATH = Join-Path -Path $repoRoot -ChildPath "tests/samples/templates"
}

Describe 'Get-TokenValues' {
    BeforeAll {
        $env:CDF_REGION = 'westeurope'
        $env:CDF_PLATFORM_ID = 'test'
        $env:CDF_PLATFORM_INSTANCE = '01'
        $env:CDF_PLATFORM_ENV_ID = 'local'
        $env:CDF_APPLICATION_ID = 'app'
        $env:CDF_APPLICATION_INSTANCE = '01'
        $env:CDF_APPLICATION_ENV_ID = 'local'
        $env:CDF_DOMAIN_NAME = 'dom1'

        Remove-Item -Path Env:/GITHUB_REPOSITORY -Force -ErrorAction SilentlyContinue
        Remove-Item -Path Env:/GITHUB_REF_NAME -Force -ErrorAction SilentlyContinue
        Remove-Item -Path Env:/GITHUB_SHA -Force -ErrorAction SilentlyContinue
        Remove-Item -Path Env:/GITHUB_WORKFLOW -Force -ErrorAction SilentlyContinue
        Remove-Item -Path Env:/GITHUB_RUN_ID -Force -ErrorAction SilentlyContinue

        Mock Get-AzContext {}
    }
    Context 'General test01' {

        It 'Should generate tokens for file config' {
            {
                $cdfConfig = Get-Config
                $tokens = $cdfConfig | Get-TokenValues -NoAlias -NoOldAPIM

                $tokens['Platform.Config.TemplateScope'] | Should -BeExactly  $cdfConfig.Platform.Config.templateScope
                $tokens['Platform.Config.TemplateVersion'] | Should -BeExactly  $cdfConfig.Platform.Config.templateVersion
                $tokens['Platform.Config.PlatformId'] | Should -BeExactly  $cdfConfig.Platform.Config.platformId
                $tokens['Platform.Config.InstanceId'] | Should -BeExactly  $cdfConfig.Platform.Config.instanceId
                $tokens['Platform.Env.TenantId'] | Should -BeExactly  $cdfConfig.Platform.Env.tenantId
                $tokens['Platform.Env.SubscriptionId'] | Should -BeExactly  $cdfConfig.Platform.Env.subscriptionId
                $tokens['Platform.Env.Region'] | Should -BeExactly  $cdfConfig.Platform.Env.region
                $tokens['Platform.Env.RegionCode'] | Should -BeExactly  $cdfConfig.Platform.Env.regionCode
                $tokens['Platform.Env.RegionName'] | Should -BeExactly  $cdfConfig.Platform.Env.regionName
                $tokens['Platform.Env.DefinitionId'] | Should -BeExactly  $cdfConfig.Platform.Env.definitionId
                $tokens['Platform.Env.NameId'] | Should -BeExactly  $cdfConfig.Platform.Env.nameId
                $tokens['Platform.Env.ShortName'] | Should -BeExactly  $cdfConfig.Platform.Env.shortName

                # Application Config
                $tokens['Application.Config.TemplateScope'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Config.TemplateScope'] | Should -BeExactly  $cdfConfig.Platform.Config.templateScope
                $tokens['Application.Config.TemplateName'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Config.TemplateName'] | Should -BeExactly  $cdfConfig.Platform.Config.templateName
                $tokens['Application.Config.TemplateVersion'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Config.TemplateVersion'] | Should -BeExactly  $cdfConfig.Platform.Config.templateVersion
                $tokens['Application.Config.PlatformId'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Config.PlatformId'] | Should -BeExactly  $cdfConfig.Platform.Config.platformId
                $tokens['Application.Config.InstanceId'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Config.InstanceId'] | Should -BeExactly  $cdfConfig.Platform.Config.instanceId
                $tokens['Application.Env.TenantId'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Env.TenantId'] | Should -BeExactly  $cdfConfig.Application.Env.tenantId
                $tokens['Application.Env.SubscriptionId'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Env.SubscriptionId'] | Should -BeExactly  $cdfConfig.Application.Env.subscriptionId
                $tokens['Application.Env.DefinitionId'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Env.DefinitionId'] | Should -BeExactly  $cdfConfig.Application.Env.definitionId
                $tokens['Application.Env.NameId'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Env.NameId'] | Should -BeExactly  $cdfConfig.Application.Env.nameId
                $tokens['Application.Env.ShortName'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Env.ShortName'] | Should -BeExactly  $cdfConfig.Application.Env.shortName
                $tokens['Application.ResourceNames.AppResourceGroupName'] | Should -BeNullOrEmpty
                $tokens['Application.ResourceNames.ApimName'] | Should -BeNullOrEmpty

                # Dmoain Config
                $tokens['Domain.Config.DomainName'] | Should -Not -BeNullOrEmpty
                $tokens['Domain.Config.DomainName'] | Should -BeExactly $cdfConfig.Domain.Config.domainName

            } | Should -Not -Throw
            Assert-MockCalled Get-AzContext -Scope It -Exactly -Times 1
        }

        It 'Should generate tokens for deployment config' {
            {
                $cdfConfig = Get-Config
                $cdfConfig.Application.ResourceNames = @{
                    appResourceGroupName = 'rg-test01-app01-apim-local-we'
                    apimName             = 'apim-test01-lcl-we'
                }
                $cdfConfig.Service = @{
                    Config = @{
                        serviceName     = 'service1'
                        serviceGroup    = 'backend'
                        serviceType     = 'node'
                        serviceTemplate = 'functionapp'
                    }
                }

                $tokens = $cdfConfig | Get-TokenValues -NoAlias -NoOldAPIM

                $tokens['Platform.Config.TemplateScope'] | Should -BeExactly  $cdfConfig.Platform.Config.templateScope
                $tokens['Platform.Config.TemplateVersion'] | Should -BeExactly  $cdfConfig.Platform.Config.templateVersion
                $tokens['Platform.Config.PlatformId'] | Should -BeExactly  $cdfConfig.Platform.Config.platformId
                $tokens['Platform.Config.InstanceId'] | Should -BeExactly  $cdfConfig.Platform.Config.instanceId
                $tokens['Platform.Env.TenantId'] | Should -BeExactly  $cdfConfig.Platform.Env.tenantId
                $tokens['Platform.Env.SubscriptionId'] | Should -BeExactly  $cdfConfig.Platform.Env.subscriptionId
                $tokens['Platform.Env.Region'] | Should -BeExactly  $cdfConfig.Platform.Env.region
                $tokens['Platform.Env.RegionCode'] | Should -BeExactly  $cdfConfig.Platform.Env.regionCode
                $tokens['Platform.Env.RegionName'] | Should -BeExactly  $cdfConfig.Platform.Env.regionName
                $tokens['Platform.Env.DefinitionId'] | Should -BeExactly  $cdfConfig.Platform.Env.definitionId
                $tokens['Platform.Env.NameId'] | Should -BeExactly  $cdfConfig.Platform.Env.nameId
                $tokens['Platform.Env.ShortName'] | Should -BeExactly  $cdfConfig.Platform.Env.shortName

                # Application Config
                $tokens['Application.Config.TemplateScope'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Config.TemplateScope'] | Should -BeExactly  $cdfConfig.Platform.Config.templateScope
                $tokens['Application.Config.TemplateName'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Config.TemplateName'] | Should -BeExactly  $cdfConfig.Platform.Config.templateName
                $tokens['Application.Config.TemplateVersion'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Config.TemplateVersion'] | Should -BeExactly  $cdfConfig.Platform.Config.templateVersion
                $tokens['Application.Config.PlatformId'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Config.PlatformId'] | Should -BeExactly  $cdfConfig.Platform.Config.platformId
                $tokens['Application.Config.InstanceId'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Config.InstanceId'] | Should -BeExactly  $cdfConfig.Platform.Config.instanceId
                $tokens['Application.Env.TenantId'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Env.TenantId'] | Should -BeExactly  $cdfConfig.Application.Env.tenantId
                $tokens['Application.Env.SubscriptionId'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Env.SubscriptionId'] | Should -BeExactly  $cdfConfig.Application.Env.subscriptionId
                $tokens['Application.Env.DefinitionId'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Env.DefinitionId'] | Should -BeExactly  $cdfConfig.Application.Env.definitionId
                $tokens['Application.Env.NameId'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Env.NameId'] | Should -BeExactly  $cdfConfig.Application.Env.nameId
                $tokens['Application.Env.ShortName'] | Should -Not -BeNullOrEmpty
                $tokens['Application.Env.ShortName'] | Should -BeExactly  $cdfConfig.Application.Env.shortName
                $tokens['Application.ResourceNames.AppResourceGroupName'] | Should -Not -BeNullOrEmpty
                $tokens['Application.ResourceNames.AppResourceGroupName'] | Should -BeExactly  $cdfConfig.Application.ResourceNames.appResourceGroupName
                $tokens['Application.ResourceNames.ApimName'] | Should -Not -BeNullOrEmpty
                $tokens['Application.ResourceNames.ApimName'] | Should -BeExactly  $cdfConfig.Application.ResourceNames.apimName

                # Dmoain Config
                $tokens['Domain.Config.DomainName'] | Should -Not -BeNullOrEmpty
                $tokens['Domain.Config.DomainName'] | Should -BeExactly $cdfConfig.Domain.Config.domainName

                # Service Config
                $tokens['Service.Config.ServiceName'] | Should -Not -BeNullOrEmpty
                $tokens['Service.Config.ServiceName'] | Should -BeExactly  $cdfConfig.Service.Config.serviceName
                $tokens['Service.Config.ServiceGroup'] | Should -Not -BeNullOrEmpty
                $tokens['Service.Config.ServiceGroup'] | Should -BeExactly $cdfConfig.Service.Config.serviceGroup
                $tokens['Service.Config.ServiceType'] | Should -Not -BeNullOrEmpty
                $tokens['Service.Config.ServiceType'] | Should -BeExactly -ExpectedValue $cdfConfig.Service.Config.serviceType
                $tokens['Service.Config.ServiceTemplate'] | Should -Not -BeNullOrEmpty
                $tokens['Service.Config.ServiceTemplate'] | Should -Be -ExpectedValue  $cdfConfig.Service.Config.serviceTemplate
            } | Should -Not -Throw
            Assert-MockCalled Get-AzContext -Scope It -Exactly -Times 1
        }

        It 'Should generate tokens for Old Apim ' {
            {
                $cdfConfig = Get-Config
                $cdfConfig.Application.ResourceNames = @{
                    appResourceGroupName = 'rg-test01-app01-apim-local-we'
                    apimName             = 'apim-test01-lcl-we'
                }
                $cdfConfig.Application.Config.appIdentityClientId = New-Guid
                $cdfConfig.Application.Config.appIdentityPrincipalId = New-Guid

                $cdfConfig.Service = @{
                    Config = @{
                        serviceName     = 'service1'
                        serviceGroup    = 'backend'
                        serviceType     = 'node'
                        serviceTemplate = 'functionapp'
                    }
                }
                $tokens = $cdfConfig | Get-TokenValues -NoAlias

                $tokens['APIM_IDENTITY_CLIENT_ID']  | Should -Not -BeNullOrEmpty
                $tokens['APIM_IDENTITY_CLIENT_ID'] | Should -BeExactly $CdfConfig.Application.Config.appIdentityClientId
                $tokens['APIM_IDENTITY_PRINCIPAL_ID'] | Should -Not -BeNullOrEmpty
                $tokens['APIM_IDENTITY_PRINCIPAL_ID'] | Should -BeExactly $CdfConfig.Application.Config.appIdentityPrincipalId
                $tokens['ENV_REGION']  | Should -Not -BeNullOrEmpty
                $tokens['ENV_REGION'] | Should -BeExactly $CdfConfig.Application.Env.region
                $tokens['ENV_REGION_CODE']  | Should -Not -BeNullOrEmpty
                $tokens['ENV_REGION_CODE'] | Should -BeExactly $CdfConfig.Application.Env.regionCode
                $tokens['ENV_REGION_NAME']  | Should -Not -BeNullOrEmpty
                $tokens['ENV_REGION_NAME'] | Should -BeExactly $CdfConfig.Application.Env.regionName
                $tokens['ENV_ID']  | Should -Not -BeNullOrEmpty
                $tokens['ENV_ID'] | Should -BeExactly $CdfConfig.Application.Env.definitionId
                $tokens['ENV_NAME_ID']  | Should -Not -BeNullOrEmpty
                $tokens['ENV_NAME_ID'] | Should -BeExactly $CdfConfig.Application.Env.nameId
                $tokens['ENV_SHORT_NAME']  | Should -Not -BeNullOrEmpty
                $tokens['ENV_SHORT_NAME'] | Should -BeExactly $CdfConfig.Application.Env.shortName
                $tokens['ENV_PURPOSE'] | Should -Not -BeNullOrEmpty
                $tokens['ENV_PURPOSE'] | Should -BeExactly $CdfConfig.Application.Env.purpose
                $tokens['ENV_QUALITY']  | Should -Not -BeNullOrEmpty
                $tokens['ENV_QUALITY'] | Should -BeExactly $CdfConfig.Application.Env.quality
                $tokens['PLATFORM_ID']  | Should -Not -BeNullOrEmpty
                $tokens['PLATFORM_ID'] | Should -BeExactly $CdfConfig.Platform.Config.platformId
                $tokens['PLATFORM_INSTANCE']  | Should -Not -BeNullOrEmpty
                $tokens['PLATFORM_INSTANCE'] | Should -BeExactly $CdfConfig.Platform.Config.instanceId
                $tokens['APPLICATION_ID']  | Should -Not -BeNullOrEmpty
                $tokens['APPLICATION_ID'] | Should -BeExactly $CdfConfig.Application.Config.applicationId
                $tokens['APPLICATION_INSTANCE'] | Should -Not -BeNullOrEmpty
                $tokens['APPLICATION_INSTANCE'] | Should -BeExactly $CdfConfig.Application.Config.instanceId
                $tokens['DOMAIN_NAME']  | Should -Not -BeNullOrEmpty
                $tokens['DOMAIN_NAME'] | Should -BeExactly $CdfConfig.Domain.Config.domainName
                $tokens['SERVICE_NAME']  | Should -Not -BeNullOrEmpty
                $tokens['SERVICE_NAME'] | Should -BeExactly $CdfConfig.Service.Config.serviceName
                $tokens['SERVICE_GROUP'] | Should -Not -BeNullOrEmpty
                $tokens['SERVICE_GROUP'] | Should -BeExactly $CdfConfig.Service.Config.serviceGroup
                $tokens['SERVICE_TYPE']  | Should -Not -BeNullOrEmpty
                $tokens['SERVICE_TYPE'] | Should -BeExactly $CdfConfig.Service.Config.serviceType
                $tokens['SERVICE_TEMPLATE'] | Should -Not -BeNullOrEmpty
                $tokens['SERVICE_TEMPLATE'] | Should -BeExactly $CdfConfig.Service.Config.serviceTemplate
                $tokens['GITHUB_REPOSITORY']  | Should -Not -BeNullOrEmpty
                $tokens['GITHUB_REF_NAME'] | Should -BeExactly 'local'
                $tokens['GITHUB_SHA'] | Should -BeExactly  'local'
                $tokens['GITHUB_WORKFLOW']  | Should -Not -BeNullOrEmpty
                $tokens['GITHUB_WORKFLOW'] | Should -BeExactly  'local'
                $tokens['GITHUB_RUN_NUMBER']  | Should -Not -BeNullOrEmpty
                $tokens['GITHUB_RUN_NUMBER'] | Should -BeExactly  'local'

            } | Should -Not -Throw
            Assert-MockCalled Get-AzContext -Scope It -Exactly -Times 1
        }

        It 'Should generate tokens for aliases ' {
            {
                $cdfConfig = Get-Config
                $cdfConfig.Application.ResourceNames = @{
                    appResourceGroupName = 'rg-test01-app01-apim-local-we'
                    apimName             = 'apim-test01-lcl-we'
                }
                $cdfConfig.Service = @{
                    Config = @{
                        serviceName     = 'service1'
                        serviceGroup    = 'backend'
                        serviceType     = 'node'
                        serviceTemplate = 'functionapp'
                    }
                }
                $tokens = $cdfConfig | Get-TokenValues -NoOldAPIM
                $tokens | ConvertTo-Json -Depth 10 | Set-Content -Path $repoRoot/output/token.json


                $tokens['EnvRegion'] | Should -Not -BeNullOrEmpty
                $tokens['EnvRegion'] | Should -BeExactly $CdfConfig.Application.Env.region
                $tokens['EnvRegionCode'] | Should -Not -BeNullOrEmpty
                $tokens['EnvRegionCode'] | Should -BeExactly $CdfConfig.Application.Env.regionCode
                $tokens['EnvRegionName'] | Should -Not -BeNullOrEmpty
                $tokens['EnvRegionName'] | Should -BeExactly $CdfConfig.Application.Env.regionName
                $tokens['EnvDefinitionId'] | Should -Not -BeNullOrEmpty
                $tokens['EnvDefinitionId'] | Should -BeExactly $CdfConfig.Application.Env.definitionId
                $tokens['EnvNameId'] | Should -Not -BeNullOrEmpty
                $tokens['EnvNameId'] | Should -BeExactly $CdfConfig.Application.Env.nameId
                $tokens['EnvShortName'] | Should -Not -BeNullOrEmpty
                $tokens['EnvShortName'] | Should -BeExactly $CdfConfig.Application.Env.shortName
                $tokens['PlatformKey'] | Should -Not -BeNullOrEmpty
                $tokens['PlatformKey'] | Should -BeExactly ($CdfConfig.Platform.Config.platformId + $CdfConfig.Platform.Config.instanceId)
                $tokens['PlatformEnvKey'] | Should -Not -BeNullOrEmpty
                $tokens['PlatformEnvKey'] | Should -BeExactly ($CdfConfig.Platform.Config.platformId + $CdfConfig.Platform.Config.instanceId + $CdfConfig.Platform.Env.nameId)
                $tokens['ApplicationKey'] | Should -Not -BeNullOrEmpty
                $tokens['ApplicationKey'] | Should -BeExactly ($CdfConfig.Application.Config.applicationId + $CdfConfig.Application.Config.instanceId)
                $tokens['ApplicationEnvKey'] | Should -Not -BeNullOrEmpty
                $tokens['ApplicationEnvKey'] | Should -BeExactly ($CdfConfig.Application.Config.applicationId + $CdfConfig.Application.Config.instanceId + $CdfConfig.Application.Env.nameId)
                $tokens['DomainName'] | Should -Not -BeNullOrEmpty
                $tokens['DomainName'] | Should -BeExactly $CdfConfig.Domain.Config.domainName
                $tokens['ServiceName'] | Should -Not -BeNullOrEmpty
                $tokens['ServiceName'] | Should -BeExactly $CdfConfig.Service.Config.serviceName
                $tokens['ServiceGroup'] | Should -Not -BeNullOrEmpty
                $tokens['ServiceGroup'] | Should -BeExactly $CdfConfig.Service.Config.serviceGroup
                $tokens['ServiceType'] | Should -Not -BeNullOrEmpty
                $tokens['ServiceType'] | Should -BeExactly $CdfConfig.Service.Config.serviceType
                $tokens['ServiceTemplate'] | Should -Not -BeNullOrEmpty
                $tokens['ServiceTemplate'] | Should -BeExactly $CdfConfig.Service.Config.serviceTemplate
                $tokens['BuildRepo'] | Should -Not -BeNullOrEmpty
                $tokens['BuildBranch'] | Should -Not -BeNullOrEmpty
                $tokens['BuildCommit'] | Should -Not -BeNullOrEmpty
                $tokens['BuildPipeline'] | Should -Not -BeNullOrEmpty
                $tokens['BuildPipeline'] | Should -BeExactly  'local'
                $tokens['BuildRun'] | Should -Not -BeNullOrEmpty
                $tokens['BuildRun'] | Should -BeExactly  'local'
            } | Should -Not -Throw
        }
    }
    Context 'GitHub Workflow test01' {
        BeforeAll {
            $env:GITHUB_REPOSITORY = 'cdf-module'
            $env:GITHUB_REF_NAME = 'refs/remotes/pull/1/merge'
            $env:GITHUB_SHA = 'a12bc3'
            $env:GITHUB_WORKFLOW = '123'
            $env:GITHUB_RUN_ID = '123'
        }

        AfterAll {
            Remove-Item -Path Env:/GITHUB_REPOSITORY
            Remove-Item -Path Env:/GITHUB_REF_NAME
            Remove-Item -Path Env:/GITHUB_SHA
            Remove-Item -Path Env:/GITHUB_WORKFLOW
            Remove-Item -Path Env:/GITHUB_RUN_ID
        }

        It 'Should generate tokens' {
            #{
            $cdfConfig = Get-Config
            $cdfConfig.Application.ResourceNames = @{
                appResourceGroupName = 'rg-test01-app01-apim-local-we'
                apimName             = 'apim-test01-lcl-we'
            }
            $cdfConfig.Service = @{
                Config = @{
                    serviceName     = 'service1'
                    serviceGroup    = 'backend'
                    serviceType     = 'node'
                    serviceTemplate = 'functionapp'
                }
            }
            $tokens = $cdfConfig | Get-TokenValues
            $tokens | ConvertTo-Json -Depth 10 | Set-Content -Path $repoRoot/output/token.json
            $tokens['BuildRepo'] | Should -BeExactly $env:GITHUB_REPOSITORY
            $tokens['BuildBranch'] | Should -BeExactly $env:GITHUB_REF_NAME
            $tokens['BuildCommit'] | Should -BeExactly $env:GITHUB_SHA
            $tokens['BuildPipeline'] | Should -BeExactly $env:GITHUB_WORKFLOW
            $tokens['BuildRun'] | Should -BeExactly $env:GITHUB_RUN_ID
            #} | Should -Not -Throw

            Assert-MockCalled Get-AzContext -Scope It -Exactly -Times 0
        }
    }

    Context 'Azure DevOps Pipelines test01' {
        BeforeAll {
            $env:BUILD_REPOSITORY_NAME = 'cdf-module'
            $env:BUILD_SOURCEBRANCH = 'refs/heads/main'
            $env:BUILD_SOURCEVERSION = 'a12bc3'
            $env:BUILD_DEFINITIONNAME = 'release-pipeline'
            $env:BUILD_BUILDNUMBER = '20250101.2'
        }
        AfterAll {
            Remove-Item Env:/BUILD_REPOSITORY_NAME
            Remove-Item Env:/BUILD_SOURCEBRANCH
            Remove-Item Env:/BUILD_SOURCEVERSION
            Remove-Item Env:/BUILD_DEFINITIONNAME
            Remove-Item Env:/BUILD_BUILDNUMBER
        }
        It 'Should generate tokens' {
            {
                $tokens = $cdfConfig | Get-TokenValues
                $tokens['BuildRepo'] | Should -BeExactly $env:BUILD_REPOSITORY_NAME
                $tokens['BuildBranch'] | Should -BeExactly $env:BUILD_SOURCEBRANCH
                $tokens['BuildCommit'] | Should -BeExactly $env:BUILD_SOURCEVERSION
                $tokens['BuildPipeline'] | Should -BeExactly $env:BUILD_DEFINITIONNAME
                $tokens['BuildRun'] | Should -BeExactly $env:BUILD_BUILDNUMBER
            } | Should -Not -Throw

            Assert-MockCalled Get-AzContext -Scope It -Exactly -Times 0
        }

    }
}

