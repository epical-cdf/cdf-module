BeforeAll {
    # Dot-source the function under test.
    $testFolder = Split-Path -Parent $PSCommandPath
    $sourceFile = (Split-Path -Leaf $PSCommandPath).Replace('.Tests.', '.')
    . (Join-Path $testFolder $sourceFile)

    function New-HookTemplate {
        param([string]$Name, [string]$Hook, [string]$Body)
        $templatePath = Join-Path $TestDrive "domain/$Name/v1"
        if ($Body) {
            $hooksDir = Join-Path $templatePath 'hooks'
            New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
            $Body | Set-Content -Path (Join-Path $hooksDir "$Hook.ps1")
        }
        else {
            New-Item -ItemType Directory -Path $templatePath -Force | Out-Null
        }
        return $templatePath
    }
}

Describe 'Invoke-TemplateHook' {

    It 'no-ops when the hook script is absent' {
        $templatePath = New-HookTemplate -Name 't-absent'

        { Invoke-TemplateHook -CdfConfig @{} -TemplatePath $templatePath -Hook 'pre-deploy' -Scope 'Domain' } |
            Should -Not -Throw
    }

    It 'runs the hook, passing CdfConfig and Scope' {
        $resultFile = Join-Path $TestDrive 'result.txt'
        $body = @'
param([object] $CdfConfig, [string] $Scope)
"$Scope|$($CdfConfig.Name)" | Set-Content -Path $CdfConfig.ResultFile
'@
        $templatePath = New-HookTemplate -Name 't-runs' -Hook 'post-deploy' -Body $body
        $cfg = @{ Name = 'dom1'; ResultFile = $resultFile }

        Invoke-TemplateHook -CdfConfig $cfg -TemplatePath $templatePath -Hook 'post-deploy' -Scope 'Domain'

        Get-Content -Path $resultFile | Should -Be 'Domain|dom1'
    }

    It 'throws when the hook script throws' {
        $body = @'
param([object] $CdfConfig, [string] $Scope)
throw 'hook failure'
'@
        $templatePath = New-HookTemplate -Name 't-throws' -Hook 'pre-deploy' -Body $body

        { Invoke-TemplateHook -CdfConfig @{} -TemplatePath $templatePath -Hook 'pre-deploy' -Scope 'Domain' } |
            Should -Throw -ExpectedMessage '*hook failure*'
    }

    It 'rejects an invalid hook name' {
        { Invoke-TemplateHook -CdfConfig @{} -TemplatePath $TestDrive -Hook 'mid-deploy' -Scope 'Domain' } |
            Should -Throw
    }

    It 'rejects an invalid scope' {
        { Invoke-TemplateHook -CdfConfig @{} -TemplatePath $TestDrive -Hook 'pre-deploy' -Scope 'Galaxy' } |
            Should -Throw
    }
}
