BeforeAll {
    $testFolder = Split-Path -Parent $PSCommandPath
    . (Join-Path $testFolder 'func_Get-Config.ps1')
    . (Join-Path $testFolder 'func_Get-ConfigService.ps1')   # real forward target (+ Get-InfraServiceConfig)

    # Stub the platform/application/domain loaders — not under test here. Return a *deployed* domain
    # so Get-Config reaches the Get-ConfigService forward (line: $ServiceName -and $config.Domain.IsDeployed).
    function Get-ConfigPlatform {
        [CmdletBinding()] param($Region, $PlatformId, $Instance, $EnvDefinitionId, $SourceDir, [switch]$Deployed)
        @{ Platform = @{ Config = @{ platformId = 'test'; instanceId = '01' }; Env = @{ nameId = 'lcl'; regionCode = 'we'; region = 'westeurope'; subscriptionId = '0' } } }
    }
    function Get-ConfigApplication {
        [CmdletBinding()] param($CdfConfig, $Region, $ApplicationId, $InstanceId, $EnvDefinitionId, $SourceDir, [switch]$Deployed)
        $CdfConfig.Application = @{ Config = @{ applicationId = 'app'; instanceId = '01' }; Env = @{ nameId = 'lcl'; name = 'Local' } }
        $CdfConfig
    }
    function Get-ConfigDomain {
        [CmdletBinding()] param($CdfConfig, $DomainName, $SourceDir, [switch]$Deployed)
        $CdfConfig.Domain = @{ Config = @{ domainName = 'dom1' }; IsDeployed = $true; ResourceNames = @{} }
        $CdfConfig
    }
}

Describe 'Get-Config -> Get-ConfigService chain — service name precedence (#76)' {

    BeforeEach {
        Remove-Item Env:/CDF_SERVICE_NAME -ErrorAction SilentlyContinue
        $script:src = Join-Path $TestDrive 'src'
        New-Item -ItemType Directory -Path (Join-Path $script:src 'test/01') -Force | Out-Null   # Get-Config source-path existence check
        $script:svcSrc = Join-Path $TestDrive 'svc'
        New-Item -ItemType Directory -Path $script:svcSrc -Force | Out-Null
        @{ ServiceDefaults = @{ ServiceName = 'umbraco-cms'; ServiceGroup = 'web'; ServiceType = 'dotnet'; ServiceTemplate = 'containerapp-api-v1' } } |
            ConvertTo-Json | Set-Content -Path (Join-Path $script:svcSrc 'cdf-config.json')
        Mock Test-Json { $true }
    }

    AfterEach { Remove-Item Env:/CDF_SERVICE_NAME -ErrorAction SilentlyContinue }

    It 'env CDF_SERVICE_NAME flows through Get-Config into the service config (the deploy path)' {
        $env:CDF_SERVICE_NAME = 'umbraco-web'
        $cfg = Get-Config -PlatformId test -PlatformInstance 01 -DomainName dom1 -CdfInfraSourcePath $script:src -ServiceSrcPath $script:svcSrc
        $cfg.Service.Config.serviceName | Should -BeExactly 'umbraco-web'
    }

    It 'explicit -ServiceName overrides env through the chain' {
        $env:CDF_SERVICE_NAME = 'umbraco-web'
        $cfg = Get-Config -ServiceName explicit-svc -PlatformId test -PlatformInstance 01 -DomainName dom1 -CdfInfraSourcePath $script:src -ServiceSrcPath $script:svcSrc
        $cfg.Service.Config.serviceName | Should -BeExactly 'explicit-svc'
    }

    It 'ServiceDefaults used when neither param nor env is set (regression guard)' {
        $cfg = Get-Config -PlatformId test -PlatformInstance 01 -DomainName dom1 -CdfInfraSourcePath $script:src -ServiceSrcPath $script:svcSrc
        $cfg.Service.Config.serviceName | Should -BeExactly 'umbraco-cms'
    }
}
