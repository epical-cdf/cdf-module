BeforeAll {
    # Dot-source the function under test (private, not exported by the module).
    $testFolder = Split-Path -Parent $PSCommandPath
    $sourceFile = (Split-Path -Leaf $PSCommandPath).Replace('.Tests.', '.')
    . (Join-Path $testFolder $sourceFile)
}

Describe 'New-CdfRegistryProvider' {

    Context 'OCI registry' {
        It 'creates an OCI provider whose PasswordEnvVar is the env-var NAME ([string])' {
            $provider = New-CdfRegistryProvider -RegistryConfig @{
                type     = 'oci'
                endpoint = 'reg.example.com/cdf'
            }

            $provider.Type | Should -Be 'oci'
            $provider.Endpoint | Should -Be 'reg.example.com/cdf'
            $provider.Username | Should -Be 'cdf'

            # Regression guard: PasswordEnvVar holds the NAME of an environment
            # variable (a plain string), not a SecureString. Retyping the
            # constructor parameter to [SecureString] breaks construction because
            # the factory passes a [string] default ('CDF_REGISTRY_TOKEN').
            $provider.PasswordEnvVar | Should -BeOfType [string]
            $provider.PasswordEnvVar | Should -Be 'CDF_REGISTRY_TOKEN'
        }

        It 'honours an explicit username and passwordEnvVar' {
            $provider = New-CdfRegistryProvider -RegistryConfig @{
                type           = 'oci'
                endpoint       = 'reg.example.com/cdf'
                username       = 'svc-cdf'
                passwordEnvVar = 'MY_TOKEN'
            }

            $provider.Username | Should -Be 'svc-cdf'
            $provider.PasswordEnvVar | Should -Be 'MY_TOKEN'
        }
    }

    Context 'ACR registry' {
        It 'creates an ACR provider' {
            $provider = New-CdfRegistryProvider -RegistryConfig @{
                type     = 'acr'
                endpoint = 'myreg.azurecr.io'
            }

            $provider.Type | Should -Be 'acr'
            $provider.Endpoint | Should -Be 'myreg.azurecr.io'
        }
    }

    Context 'Unsupported registry' {
        It 'throws for an unknown registry type' {
            { New-CdfRegistryProvider -RegistryConfig @{ type = 'nope'; endpoint = 'x' } } |
                Should -Throw -ExpectedMessage '*Unsupported registry type*'
        }
    }
}

Describe 'Resolve-CdfRegistryConfig' {

    It 'resolves a project-level registry file first' {
        $projectDir = Join-Path $TestDrive 'proj'
        $registriesDir = Join-Path $projectDir '.cdf/registries'
        New-Item -ItemType Directory -Path $registriesDir -Force | Out-Null
        @{ type = 'acr'; endpoint = 'proj.azurecr.io' } | ConvertTo-Json |
            Set-Content -Path (Join-Path $registriesDir 'default.json')

        $config = Resolve-CdfRegistryConfig -Name 'default' -ProjectDir $projectDir

        $config.type | Should -Be 'acr'
        $config.endpoint | Should -Be 'proj.azurecr.io'
    }

    It 'falls back to inline registries from the manifest' {
        $projectDir = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
        $inline = @{ 'cdf-pkgs' = @{ type = 'oci'; endpoint = 'ghcr.io/epical' } }

        $config = Resolve-CdfRegistryConfig -Name 'cdf-pkgs' -InlineRegistries $inline -ProjectDir $projectDir

        $config.endpoint | Should -Be 'ghcr.io/epical'
    }

    It 'throws when the registry cannot be resolved' {
        $projectDir = Join-Path $TestDrive 'unresolved'
        New-Item -ItemType Directory -Path $projectDir -Force | Out-Null

        { Resolve-CdfRegistryConfig -Name 'cdf-no-such-registry-xyz' -ProjectDir $projectDir } |
            Should -Throw -ExpectedMessage '*not found*'
    }
}
