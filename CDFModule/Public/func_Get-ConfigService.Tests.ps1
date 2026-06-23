BeforeAll {
    $testFolder = Split-Path -Parent $PSCommandPath
    . (Join-Path $testFolder 'func_Get-ConfigService.ps1')   # also defines Get-InfraServiceConfig

    function New-TestCdfConfig {
        @{
            Platform    = @{
                Config = @{ platformId = 'test'; instanceId = '01' }
                Env    = @{ nameId = 'lcl'; regionCode = 'we'; region = 'westeurope'; subscriptionId = '00000000-0000-0000-0000-000000000000' }
            }
            Application = @{
                Config = @{ applicationId = 'app'; instanceId = '01' }
                Env    = @{ nameId = 'lcl'; name = 'Local' }
            }
            Domain      = @{ Config = @{ domainName = 'dom1' }; IsDeployed = $true; ResourceNames = @{} }
        }
    }
}

Describe 'Get-ConfigService — service name precedence (explicit > env > ServiceDefaults)' {

    BeforeEach {
        Remove-Item Env:/CDF_SERVICE_NAME -ErrorAction SilentlyContinue
        # cdf-config.json with ServiceDefaults at the service source path
        $script:svcSrc = Join-Path $TestDrive 'svc'
        New-Item -ItemType Directory -Path $script:svcSrc -Force | Out-Null
        @{ ServiceDefaults = @{ ServiceName = 'umbraco-cms'; ServiceGroup = 'web'; ServiceType = 'dotnet'; ServiceTemplate = 'containerapp-api-v1' } } |
            ConvertTo-Json | Set-Content -Path (Join-Path $script:svcSrc 'cdf-config.json')
        # No infra service.*.json -> Get-InfraServiceConfig returns Config.serviceName = the resolved value
        $script:noSrc = Join-Path $TestDrive 'no-infra-src'
        Mock Test-Json { $true }   # bypass JSON-schema validation for the unit test
    }

    AfterEach { Remove-Item Env:/CDF_SERVICE_NAME -ErrorAction SilentlyContinue }

    It 'explicit -ServiceName wins over env and ServiceDefaults' {
        $env:CDF_SERVICE_NAME = 'umbraco-web'
        $cfg = New-TestCdfConfig | Get-ConfigService -ServiceName 'explicit-svc' -ServiceSrcPath $script:svcSrc -SourceDir $script:noSrc
        $cfg.Service.Config.serviceName | Should -BeExactly 'explicit-svc'
    }

    It 'env CDF_SERVICE_NAME wins over ServiceDefaults when -ServiceName is not passed' {
        $env:CDF_SERVICE_NAME = 'umbraco-web'
        $cfg = New-TestCdfConfig | Get-ConfigService -ServiceSrcPath $script:svcSrc -SourceDir $script:noSrc
        $cfg.Service.Config.serviceName | Should -BeExactly 'umbraco-web'
    }

    It 'falls back to cdf-config ServiceDefaults when neither param nor env is set' {
        $cfg = New-TestCdfConfig | Get-ConfigService -ServiceSrcPath $script:svcSrc -SourceDir $script:noSrc
        $cfg.Service.Config.serviceName | Should -BeExactly 'umbraco-cms'
    }

    It 'env override of ServiceName does not bleed into the other fields' {
        $env:CDF_SERVICE_NAME = 'umbraco-web'
        $cfg = New-TestCdfConfig | Get-ConfigService -ServiceSrcPath $script:svcSrc -SourceDir $script:noSrc
        $cfg.Service.Config.serviceName | Should -BeExactly 'umbraco-web'
        $cfg.Service.Config.serviceGroup | Should -BeExactly 'web'           # from ServiceDefaults
        $cfg.Service.Config.serviceTemplate | Should -BeExactly 'containerapp-api-v1'
    }

    It 'emits a Verbose note when the CDF_SERVICE_NAME env override is in effect' {
        $env:CDF_SERVICE_NAME = 'umbraco-web'
        $verbose = New-TestCdfConfig | Get-ConfigService -ServiceSrcPath $script:svcSrc -SourceDir $script:noSrc -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match 'CDF_SERVICE_NAME override' }
        $verbose | Should -Not -BeNullOrEmpty
    }

    It 'does not emit the override note when -ServiceName is explicit' {
        $env:CDF_SERVICE_NAME = 'umbraco-web'
        $verbose = New-TestCdfConfig | Get-ConfigService -ServiceName 'explicit-svc' -ServiceSrcPath $script:svcSrc -SourceDir $script:noSrc -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match 'CDF_SERVICE_NAME override' }
        $verbose | Should -BeNullOrEmpty
    }
}
