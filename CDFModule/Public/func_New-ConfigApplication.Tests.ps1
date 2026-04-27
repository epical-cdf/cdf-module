BeforeAll {
    $repoRoot = Split-Path -Parent (Resolve-Path $PSCommandPath/../..)
    $testFolder = Split-Path -Parent $PSCommandPath
    $testFileName = (Split-Path -Leaf $PSCommandPath).Replace(".Tests.", ".")

    . $testFolder/$($testFileName.Replace("New-ConfigApplication", "Get-ConfigApplication"))
    . $testFolder/$($testFileName.Replace("New-ConfigApplication", "Get-ConfigPlatform"))
    . $testFolder/$($testFileName.Replace("New-ConfigApplication", "New-ConfigPlatform"))
    . $testFolder/$testFileName

    $env:CDF_INFRA_SOURCE_PATH = Join-Path -Path $repoRoot -ChildPath "output/sources"
    $env:CDF_INFRA_TEMPLATES_PATH = Join-Path -Path $repoRoot -ChildPath "tests/samples/templates"

    Remove-Item -Path $env:CDF_INFRA_SOURCE_PATH -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path $env:CDF_INFRA_SOURCE_PATH -ItemType Directory -Force
}

AfterAll {
    Remove-Item -Path $env:CDF_INFRA_SOURCE_PATH -Recurse -Force
}

Describe 'New-ConfigApplication' {
    Context 'Application test03-app01 local/westus' {
        BeforeEach {
            $env:CDF_REGION = 'westus'
            $env:CDF_PLATFORM_ID = 'test'
            $env:CDF_PLATFORM_INSTANCE = '03'
            $env:CDF_PLATFORM_ENV_ID = 'local'
            $env:CDF_APPLICATION_ID = 'app'
            $env:CDF_APPLICATION_INSTANCE = '01'
            $env:CDF_APPLICATION_ENV_ID = 'local'
        }

        It 'Should create new runtime config' {
            Mock Write-Error {}
            {
                New-ConfigPlatform -TemplateName blank -TemplateVersion v1
                Get-ConfigPlatform | New-ConfigApplication -TemplateName blank -TemplateVersion v1
            } | Should -Not -Throw
            Assert-MockCalled Write-Error -Scope It -Exactly -Times 0
        }
        It 'Should return config' {
            Mock Write-Error {}
            $config = Get-ConfigPlatform | Get-ConfigApplication
            $config | Should -Not -BeNullOrEmpty
            $config.Platform | Should -Not -BeNullOrEmpty
            $config.Application | Should -Not -BeNullOrEmpty
            Assert-MockCalled Write-Error -Scope It -Exactly -Times 0
        }
    }

}
