BeforeAll {
    $repoRoot = Split-Path -Parent (Resolve-Path $PSCommandPath/../..)
    $testFolder = Split-Path -Parent $PSCommandPath
    $testFileName = (Split-Path -Leaf $PSCommandPath).Replace(".Tests.", ".")

    . $testFolder/$($testFileName.Replace("Export-DotEnv", "Get-DotEnv") | Out-String)
    . $testFolder/$($testFileName.Replace("Export-DotEnv", "ConvertTo-DotEnv") | Out-String)
    . $testFolder/$($testFileName.Replace("Export-DotEnv", "Get-ServiceConfigSettings") | Out-String)
    . $testFolder/$testFileName
}

Describe 'Export-DotEnv' {
    BeforeAll {
        New-Item -Path $repoRoot/output/ -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }

    AfterAll {
        Remove-Item -Path $repoRoot/output/Get-DotEnv.env -Recurse -Force
    }

    It 'Should import env file to hashtable' {
        Mock Write-Verbose {}
        Mock Get-DotEnv { return @{ UNITTEST = 'RESULT' } }
        Mock Get-ServiceConfigSettings { return @{ UNITTEST = 'RESULT' } }
        Mock ConvertTo-DotEnv { return "UNITTEST=RESULT" }
        $config = @{}

        {
            $config | Export-DotEnv -InputEnv $repoRoot/tests/data/Get-DotEnv.env -OutputEnv $repoRoot/output/Get-DotEnv.env -Verbose
            Test-Path -Path $repoRoot/output/Get-DotEnv.env -PathType Leaf | Should -BeTrue
            Get-Content $repoRoot/output/Get-DotEnv.env | Should -Be "UNITTEST=RESULT"
        } | Should -Not -Throw

        Assert-MockCalled Write-Verbose -Scope It -Exactly -Times 1 -ParameterFilter { $Message.StartsWith('Reading:') }
        Assert-MockCalled Write-Verbose -Scope It -Exactly -Times 1 -ParameterFilter { $Message.StartsWith('Writing:') }
    }
}
