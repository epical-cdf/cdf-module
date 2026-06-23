BeforeAll {
    $testFolder = Split-Path -Parent $PSCommandPath
    . (Join-Path $testFolder 'func_New-CdfPackageDeployView.ps1')
}

Describe 'New-CdfPackageDeployView' {

    BeforeEach {
        $script:cacheRoot = Join-Path $TestDrive 'cache'
        # Template package: templates/<endpoint>/<scope>/<name>/<version>/<release>/...
        $tDir = Join-Path $script:cacheRoot 'templates/ghcr.io/org/platform/blank/v1/0.1.0'
        New-Item -ItemType Directory -Path $tDir -Force | Out-Null
        'targetScope = ''subscription''' | Set-Content -Path (Join-Path $tDir 'platform.bicep')
        # Config package: configs/<endpoint>/<configKey>/<release>/{cdf-runtime.json, platform/...}
        $cDir = Join-Path $script:cacheRoot 'configs/ghcr.io/org/axldb01/0.1.0'
        New-Item -ItemType Directory -Path (Join-Path $cDir 'platform') -Force | Out-Null
        @{ platformId = 'axldb'; instanceId = '01'; release = '0.1.0' } | ConvertTo-Json | Set-Content -Path (Join-Path $cDir 'cdf-runtime.json')
        '{}' | Set-Content -Path (Join-Path $cDir 'platform/environments.json')
    }

    It 'maps templates to <scope>/<name>/<version> and configs to <platformId>/<instanceId>' {
        $view = New-CdfPackageDeployView -CacheRoot $script:cacheRoot `
            -Templates @(@{ Endpoint = 'ghcr.io/org'; Path = 'platform/blank/v1'; Release = '0.1.0' }) `
            -Configs @(@{ Endpoint = 'ghcr.io/org'; Path = 'axldb01'; Release = '0.1.0' })

        # Template resolves at $CDF_INFRA_TEMPLATES_PATH/<scope>/<name>/<version>/...
        Test-Path (Join-Path $view.TemplatesPath 'platform/blank/v1/platform.bicep') | Should -BeTrue
        # Config resolves at $CDF_INFRA_SOURCE_PATH/<platformId>/<instanceId>/... (the loader shape)
        Test-Path (Join-Path $view.SourcePath 'axldb/01/platform/environments.json') | Should -BeTrue
        $view.TemplatesPath | Should -Match 'templates$'
        $view.SourcePath | Should -Match 'source$'
    }

    It 'derives <platformId>/<instanceId> from the packed cdf-runtime.json, not the configKey' {
        # configKey 'axldb01' is ambiguous to split; the runtime manifest is authoritative.
        $view = New-CdfPackageDeployView -CacheRoot $script:cacheRoot `
            -Configs @(@{ Endpoint = 'ghcr.io/org'; Path = 'axldb01'; Release = '0.1.0' })
        Test-Path (Join-Path $view.SourcePath 'axldb/01') | Should -BeTrue
    }

    It 'includes all configs (not just the first)' {
        $c2 = Join-Path $script:cacheRoot 'configs/ghcr.io/org/axcdb01/0.1.0'
        New-Item -ItemType Directory -Path $c2 -Force | Out-Null
        @{ platformId = 'axcdb'; instanceId = '01' } | ConvertTo-Json | Set-Content -Path (Join-Path $c2 'cdf-runtime.json')
        $view = New-CdfPackageDeployView -CacheRoot $script:cacheRoot -Configs @(
            @{ Endpoint = 'ghcr.io/org'; Path = 'axldb01'; Release = '0.1.0' },
            @{ Endpoint = 'ghcr.io/org'; Path = 'axcdb01'; Release = '0.1.0' }
        )
        Test-Path (Join-Path $view.SourcePath 'axldb/01') | Should -BeTrue
        Test-Path (Join-Path $view.SourcePath 'axcdb/01') | Should -BeTrue
    }

    It 'is deterministic for the same package set' {
        $a = New-CdfPackageDeployView -CacheRoot $script:cacheRoot -Configs @(@{ Endpoint = 'ghcr.io/org'; Path = 'axldb01'; Release = '0.1.0' })
        $b = New-CdfPackageDeployView -CacheRoot $script:cacheRoot -Configs @(@{ Endpoint = 'ghcr.io/org'; Path = 'axldb01'; Release = '0.1.0' })
        $a.ViewRoot | Should -BeExactly $b.ViewRoot
    }

    It 'warns and skips a config with no cdf-runtime.json' {
        $bad = Join-Path $script:cacheRoot 'configs/ghcr.io/org/noruntime01/0.1.0'
        New-Item -ItemType Directory -Path $bad -Force | Out-Null
        '{}' | Set-Content -Path (Join-Path $bad 'platform.json')
        $view = New-CdfPackageDeployView -CacheRoot $script:cacheRoot `
            -Configs @(@{ Endpoint = 'ghcr.io/org'; Path = 'noruntime01'; Release = '0.1.0' }) -WarningAction SilentlyContinue
        @(Get-ChildItem -Path $view.SourcePath -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
}
