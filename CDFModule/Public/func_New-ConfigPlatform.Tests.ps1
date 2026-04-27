BeforeAll {
    $repoRoot = Split-Path -Parent (Resolve-Path $PSCommandPath/../..)
    $testFolder = Split-Path -Parent $PSCommandPath
    $testFileName = (Split-Path -Leaf $PSCommandPath).Replace(".Tests.", ".")

    . $testFolder/$($testFileName.Replace("New-ConfigPlatform", "Get-ConfigPlatform"))
    . $testFolder/$testFileName

    $env:CDF_INFRA_SOURCE_PATH = Join-Path -Path $repoRoot -ChildPath "output/sources"
    $env:CDF_INFRA_TEMPLATES_PATH = Join-Path -Path $repoRoot -ChildPath "tests/samples/templates"

    Remove-Item -Path $env:CDF_INFRA_SOURCE_PATH -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path $env:CDF_INFRA_SOURCE_PATH -ItemType Directory -Force
}

AfterAll {
    Remove-Item -Path $env:CDF_INFRA_SOURCE_PATH -Recurse -Force
}

Describe 'New-ConfigPlatform' {
    Context 'Platform test03 local/westus' {
        BeforeEach {
            $env:CDF_REGION = 'westus'
            $env:CDF_PLATFORM_ID = 'test'
            $env:CDF_PLATFORM_INSTANCE = '03'
            $env:CDF_PLATFORM_ENV_ID = 'local'
        }

        It 'Should create new runtime config' {
            Mock Write-Error {}
            { New-ConfigPlatform -TemplateName blank -TemplateVersion v1 } | Should -Not -Throw
            Assert-MockCalled Write-Error -Scope It -Exactly -Times 0
        }
        It 'Should return config' {
            Mock Write-Error {}
            $config = Get-ConfigPlatform
            $config | Should -Not -BeNullOrEmpty
            $config.Platform | Should -Not -BeNullOrEmpty
            Assert-MockCalled Write-Error -Scope It -Exactly -Times 0
        }
    }

    #     Context 'Validate configuration test01' {
    #         It 'Should return correct config from files' {
    #             Mock Write-Error {}
    #             $config = Get-ConfigPlatform -Region westeurope -PlatformId test -InstanceId 01 -EnvDefinitionId local
    #             $config | Should -Not -BeNullOrEmpty
    #             $config.Platform | Should -Not -BeNullOrEmpty
    #             $config.Platform.IsDeployed | Should -BeFalse
    #             $config.Platform.Env | Should -Not -BeNullOrEmpty
    #             $config.Platform.Env.Count | Should -BeExactly 13
    #             $config.Platform.Env.definitionId | Should -Be -ExpectedValue "local"
    #             $config.Platform.Env.nameId | Should -Be -ExpectedValue "lcl"
    #             $config.Platform.Env.shortName | Should -Be -ExpectedValue "Local"
    #             $config.Platform.Env.name | Should -Be -ExpectedValue "Local development and testing"
    #             $config.Platform.Env.description | Should -Be -ExpectedValue "This environment is used to run regression testing "
    #             $config.Platform.Env.purpose | Should -Be -ExpectedValue "development"
    #             $config.Platform.Env.quality | Should -Be -ExpectedValue "development"
    #             $config.Platform.Env.tenantId | Should -Be -ExpectedValue "00000000-1111-2222-3333-444444444444"
    #             $config.Platform.Env.subscriptionId | Should -Be -ExpectedValue "11111111-2222-3333-4444-555555555555"
    #             $config.Platform.Env.isEnabled | Should -BeTrue
    #             $config.Platform.Env.region | Should -Be -ExpectedValue "westeurope"
    #             $config.Platform.Env.regionName | Should -Be -ExpectedValue "emea"
    #             $config.Platform.Env.regionCode | Should -Be -ExpectedValue "we"
    #             $config.Platform.Tags | Should -BeNullOrEmpty
    #             $config.Platform.Config | Should -Not -BeNullOrEmpty
    #             $config.Platform.Config.Count | Should -BeExactly 5
    #             $config.Platform.Config.templateName | Should -Be -ExpectedValue "blank"
    #             $config.Platform.Config.templateScope | Should -Be -ExpectedValue "platform"
    #             $config.Platform.Config.templateVersion | Should -Be -ExpectedValue "v1"
    #             $config.Platform.Config.platformId | Should -Be -ExpectedValue "test"
    #             $config.Platform.Config.instanceId | Should -Be -ExpectedValue "01"
    #             $config.Platform.Features | Should -BeNullOrEmpty
    #             $config.Platform.ResourceNames | Should -BeNullOrEmpty
    #             $config.Platform.NetworkConfig | Should -BeNullOrEmpty
    #             $config.Platform.AccessControl | Should -BeNullOrEmpty
    #             Assert-MockCalled Write-Error -Scope It -Exactly -Times 0
    #         }
    #         It 'Should return correct config from deployment' {
    #             Mock Write-Error {}
    #             Mock Get-AzureContext { return (Get-Content -Raw -Path $repoRoot/tests/data/AzureContext.json | ConvertFrom-Json -AsHashtable) }
    #             Mock Get-AzSubscriptionDeployment -RemoveParameterType DefaultProfile { return Get-Content -Raw -Path $repoRoot/tests/data/Deployment-Platform-test01.json | ConvertFrom-Json -AsHashtable }

    #             $config = Get-ConfigPlatform -Deployed -Region westeurope -PlatformId test -InstanceId 01 -EnvDefinitionId local
    #             $config | Should -Not -BeNullOrEmpty
    #             $config.Platform | Should -Not -BeNullOrEmpty
    #             $config.Platform.IsDeployed | Should -BeTrue
    #             $config.Platform.Env | Should -Not -BeNullOrEmpty
    #             $config.Platform.Tags | Should -Not -BeNullOrEmpty
    #             $config.Platform.Config | Should -Not -BeNullOrEmpty
    #             $config.Platform.Features | Should -BeNullOrEmpty
    #             $config.Platform.ResourceNames | Should -Not -BeNullOrEmpty
    #             $config.Platform.NetworkConfig | Should -BeNullOrEmpty
    #             $config.Platform.AccessControl | Should -BeNullOrEmpty

    #             Assert-MockCalled Write-Error -Scope It -Exactly -Times 0
    #             Assert-MockCalled Get-AzureContext -Scope It -Exactly -Times 1
    #             Assert-MockCalled Get-AzSubscriptionDeployment -Scope It -Exactly -Times 1
    #         }

    #         It 'Should write error configuration not complete' {
    #             Mock Write-Error {}
    #             Mock Get-AzureContext { return (Get-Content -Raw -Path $repoRoot/tests/data/AzureContext.json | ConvertFrom-Json -AsHashtable) }
    #             Mock Get-AzSubscriptionDeployment -RemoveParameterType DefaultProfile {
    #                 $deploymentResult = Get-Content -Raw -Path $repoRoot/tests/data/Deployment-Platform-test01.json | ConvertFrom-Json -AsHashtable
    #                 $deploymentResult.Outputs.platformEnv.Value = $null
    #                 return $deploymentResult
    #             }

    #             {
    #                 Get-ConfigPlatform -Deployed -Region westeurope -PlatformId test -InstanceId 01 -EnvDefinitionId local
    #             } | Should -Not -Throw
    #             Assert-MockCalled Write-Error -Scope It -Exactly -Times 1
    #         }

    #         It 'Should return from file with warning on unsuccessful deployment status' {
    #             Mock Write-Error {}
    #             Mock Write-Warning {}
    #             Mock Get-AzureContext { return (Get-Content -Raw -Path $repoRoot/tests/data/AzureContext.json | ConvertFrom-Json -AsHashtable) }
    #             Mock Get-AzSubscriptionDeployment -RemoveParameterType DefaultProfile {
    #                 $deploymentResult = Get-Content -Raw -Path $repoRoot/tests/data/Deployment-Platform-test01.json | ConvertFrom-Json -AsHashtable
    #                 $deploymentResult.ProvisioningState = 'Running'
    #                 return $deploymentResult
    #             }

    #             {
    #                 Get-ConfigPlatform -Deployed -Region westeurope -PlatformId test -InstanceId 01 -EnvDefinitionId local
    #             } | Should -Not -Throw
    #             Assert-MockCalled Write-Error -Scope It -Exactly -Times 0
    #             Assert-MockCalled Write-Warning -Scope It -Exactly -Times 2
    #         }
    #     }

    #     Context 'Validate configuration test02' {
    #         It 'Should return correct config from files for local/swedencentral' {
    #             Mock Write-Error {}
    #             $config = Get-ConfigPlatform -Region 'swedencentral' -PlatformId 'test' -InstanceId '02' -EnvDefinitionId 'local'
    #             $config | Should -Not -BeNullOrEmpty
    #             $config.Platform | Should -Not -BeNullOrEmpty
    #             $config.Platform.IsDeployed | Should -BeFalse
    #             $config.Platform.Env | Should -Not -BeNullOrEmpty
    #             $config.Platform.Env.Count | Should -BeExactly 20
    #             $config.Platform.Env.definitionId | Should -Be -ExpectedValue "local"
    #             $config.Platform.Env.nameId | Should -Be -ExpectedValue "lcl"
    #             $config.Platform.Env.shortName | Should -Be -ExpectedValue "Local"
    #             $config.Platform.Env.name | Should -Be -ExpectedValue "Local development and testing"
    #             $config.Platform.Env.description | Should -Be -ExpectedValue "This environment is used to run regression testing"
    #             $config.Platform.Env.purpose | Should -Be -ExpectedValue "development"
    #             $config.Platform.Env.quality | Should -Be -ExpectedValue "development"
    #             $config.Platform.Env.tenantId | Should -Be -ExpectedValue "00000000-1111-2222-3333-444444444444"
    #             $config.Platform.Env.subscriptionId | Should -Be -ExpectedValue "11111111-2222-3333-4444-555555555555"
    #             $config.Platform.Env.isEnabled | Should -BeTrue
    #             $config.Platform.Env.region | Should -Be -ExpectedValue "swedencentral"
    #             $config.Platform.Env.regionName | Should -Be -ExpectedValue "emea"
    #             $config.Platform.Env.regionCode | Should -Be -ExpectedValue "sdc"
    #             $config.Platform.Env.cdfInfraDeployerName | Should -Be -ExpectedValue  "sp-xyz"
    #             $config.Platform.Env.cdfInfraDeployerAppId | Should -Be -ExpectedValue "11111111-SSSS-PPPP-4444-555555555555"
    #             $config.Platform.Env.cdfInfraDeployerSPObjectId | Should -Be -ExpectedValue  "11111111-SSSS-PPPP-4444-555555555555"
    #             $config.Platform.Env.cdfSolutionDeployerName | Should -Be -ExpectedValue  "sp-xyz"
    #             $config.Platform.Env.cdfSolutionDeployerAppId | Should -Be -ExpectedValue  "11111111-SSSS-PPPP-4444-555555555555"
    #             $config.Platform.Env.cdfSolutionDeployerSPObjectId | Should -Be -ExpectedValue  "11111111-SSSS-PPPP-4444-555555555555"
    #             $config.Platform.Env.releaseApproval | Should -BeFalse
    #             $config.Platform.Tags | Should -BeNullOrEmpty
    #             $config.Platform.Config | Should -Not -BeNullOrEmpty
    #             $config.Platform.Config.Count | Should -BeExactly 5
    #             $config.Platform.Config.templateName | Should -Be -ExpectedValue "blank"
    #             $config.Platform.Config.templateScope | Should -Be -ExpectedValue "platform"
    #             $config.Platform.Config.templateVersion | Should -Be -ExpectedValue "v1"
    #             $config.Platform.Config.platformId | Should -Be -ExpectedValue "test"
    #             $config.Platform.Config.instanceId | Should -Be -ExpectedValue "02"
    #             $config.Platform.Features | Should -Not -BeNullOrEmpty
    #             $config.Platform.Features.Count | Should -BeExactly 5
    #             $config.Platform.Features.useKeyVault | Should -BeFalse
    #             $config.Platform.Features.useStorageAccount | Should -BeFalse
    #             $config.Platform.Features.useFeatureX | Should -BeTrue
    #             $config.Platform.Features.useFeatureY | Should -BeTrue
    #             $config.Platform.Features.useFeatureZ | Should -BeTrue
    #             $config.Platform.ResourceNames | Should -BeNullOrEmpty
    #             $config.Platform.NetworkConfig | Should -BeNullOrEmpty
    #             $config.Platform.AccessControl | Should -Not -BeNullOrEmpty
    #             $config.Platform.AccessControl.Count | Should -BeExactly 4
    #             $config.Platform.AccessControl.keyVaultRBAC  | Should -Not -BeNullOrEmpty
    #             $config.Platform.AccessControl.storageAccountRBAC  | Should -Not -BeNullOrEmpty
    #             $config.Platform.AccessControl.serviceBusRBAC | Should -BeNullOrEmpty
    #             $config.Platform.AccessControl.containerRegistryRBAC  | Should -BeNullOrEmpty

    #             Assert-MockCalled Write-Error -Scope It -Exactly -Times 0
    #         }

    #         It 'Should return correct config from files for uat/westeurope' {
    #             Mock Write-Error {}
    #             $config = Get-ConfigPlatform -Region 'westeurope' -PlatformId 'test' -InstanceId '02' -EnvDefinitionId 'uat'
    #             $config | Should -Not -BeNullOrEmpty
    #             $config.Platform | Should -Not -BeNullOrEmpty
    #             $config.Platform.IsDeployed | Should -BeFalse
    #             $config.Platform.Env | Should -Not -BeNullOrEmpty
    #             $config.Platform.Env.Count | Should -BeExactly 14
    #             $config.Platform.Env.definitionId | Should -Be -ExpectedValue "uat"
    #             $config.Platform.Env.nameId | Should -Be -ExpectedValue "uat"
    #             $config.Platform.Env.shortName | Should -Be -ExpectedValue "UAT"
    #             $config.Platform.Env.name | Should -Be -ExpectedValue "User acceptance"
    #             $config.Platform.Env.description | Should -Be -ExpectedValue "This is a sample user acceptance test environment configuration"
    #             $config.Platform.Env.purpose | Should -Be -ExpectedValue "validation"
    #             $config.Platform.Env.quality | Should -Be -ExpectedValue "production"
    #             $config.Platform.Env.tenantId | Should -Be -ExpectedValue "00000000-1111-2222-3333-444444444444"
    #             $config.Platform.Env.subscriptionId | Should -Be -ExpectedValue "11111111-2222-3333-4444-555555555555"
    #             $config.Platform.Env.isEnabled | Should -BeTrue
    #             $config.Platform.Env.region | Should -Be -ExpectedValue "westeurope"
    #             $config.Platform.Env.regionName | Should -Be -ExpectedValue "emea"
    #             $config.Platform.Env.regionCode | Should -Be -ExpectedValue "we"
    #             $config.Platform.Env.releaseApproval | Should -BeTrue
    #             $config.Platform.Tags | Should -BeNullOrEmpty
    #             $config.Platform.Config | Should -Not -BeNullOrEmpty
    #             $config.Platform.Config.Count | Should -BeExactly 5
    #             $config.Platform.Config.templateName | Should -Be -ExpectedValue "blank"
    #             $config.Platform.Config.templateScope | Should -Be -ExpectedValue "platform"
    #             $config.Platform.Config.templateVersion | Should -Be -ExpectedValue "v1"
    #             $config.Platform.Config.platformId | Should -Be -ExpectedValue "test"
    #             $config.Platform.Config.instanceId | Should -Be -ExpectedValue "02"
    #             $config.Platform.Features | Should -Not -BeNullOrEmpty
    #             $config.Platform.Features.Count | Should -BeExactly 5
    #             $config.Platform.Features.useKeyVault | Should -BeFalse
    #             $config.Platform.Features.useStorageAccount | Should -BeFalse
    #             $config.Platform.Features.useFeatureX | Should -BeTrue
    #             $config.Platform.Features.useFeatureY | Should -BeTrue
    #             $config.Platform.Features.useFeatureZ | Should -BeTrue
    #             $config.Platform.ResourceNames | Should -BeNullOrEmpty
    #             $config.Platform.NetworkConfig | Should -Not -BeNullOrEmpty
    #             $config.Platform.AccessControl | Should -Not -BeNullOrEmpty
    #             $config.Platform.AccessControl.Count | Should -BeExactly 4
    #             $config.Platform.AccessControl.keyVaultRBAC  | Should -Not -BeNullOrEmpty
    #             $config.Platform.AccessControl.storageAccountRBAC  | Should -Not -BeNullOrEmpty
    #             $config.Platform.AccessControl.serviceBusRBAC | Should -BeNullOrEmpty
    #             $config.Platform.AccessControl.containerRegistryRBAC  | Should -BeNullOrEmpty

    #             Assert-MockCalled Write-Error -Scope It -Exactly -Times 0
    #         }

    #         It 'Should return correct config from deployment' {
    #             Mock Write-Error {}
    #             Mock Write-Verbose {}
    #             Mock Get-AzureContext { return (Get-Content -Raw -Path $repoRoot/tests/data/AzureContext.json | ConvertFrom-Json -AsHashtable) }
    #             Mock Get-AzSubscriptionDeployment -RemoveParameterType DefaultProfile { return Get-Content -Raw -Path $repoRoot/tests/data/Deployment-Platform-test02uat-we.json | ConvertFrom-Json -AsHashtable }

    #             $config = Get-ConfigPlatform -Deployed -Region westeurope -PlatformId test -InstanceId 02 -EnvDefinitionId uat -Verbose
    #             $config | Should -Not -BeNullOrEmpty
    #             $config.Platform | Should -Not -BeNullOrEmpty
    #             $config.Platform.IsDeployed | Should -BeTrue
    #             $config.Platform.Env | Should -Not -BeNullOrEmpty
    #             $config.Platform.Tags | Should -Not -BeNullOrEmpty
    #             $config.Platform.Config | Should -Not -BeNullOrEmpty
    #             $config.Platform.Features | Should -Not -BeNullOrEmpty
    #             $config.Platform.ResourceNames | Should -Not -BeNullOrEmpty
    #             $config.Platform.NetworkConfig | Should -Not -BeNullOrEmpty
    #             $config.Platform.SpokeNetworkConfig | Should -Not -BeNullOrEmpty
    #             $config.Platform.AccessControl | Should -Not -BeNullOrEmpty

    #             # Write-Verbose "Loading enterprise spoke network configuration"

    #             Assert-MockCalled Write-Verbose -Scope It -Exactly -Times 4
    #             Assert-MockCalled Write-Error -Scope It -Exactly -Times 0
    #             Assert-MockCalled Get-AzureContext -Scope It -Exactly -Times 1
    #             Assert-MockCalled Get-AzSubscriptionDeployment -Scope It -Exactly -Times 1
    #         }
    #     }
}
