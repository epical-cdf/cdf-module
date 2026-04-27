BeforeAll {
    $repoRoot = Split-Path -Parent (Resolve-Path $PSCommandPath/../..)
    $testFolder = Split-Path -Parent $PSCommandPath
    $testFileName = (Split-Path -Leaf $PSCommandPath).Replace(".Tests.", ".")

    . $testFolder/$testFileName
}

Describe 'Get-DotEnv' {
    BeforeEach {
    }

    It 'Should import env file to hashtable' {
        Mock Write-Verbose {}

        {
            $dotenv = Get-DotEnv -Path $repoRoot/tests/data/Get-DotEnv.env -Verbose
            $dotenv | Should -Not -BeNullOrEmpty
            $dotenv.Count | Should -BeExactly 8
            $dotenv["TEST_STRING1"] | Should -BeExactly 'Hello'
            $dotenv["TEST_STRING2"] | Should -BeExactly 'Hello World'
            $dotenv["TEST_STRING3"] | Should -BeExactly 'Hellü Wörld! èé^ô`´\'
            $dotenv["TEST_NUMBER1"] | Should -BeExactly '1'
            $dotenv["TEST_NUMBER2"] | Should -BeExactly '1234567890'
            $dotenv["TEST_BOOL1"] | Should -BeExactly 'true'
            $dotenv["TEST_BOOL2"] | Should -BeExactly 'false'
            $dotenv["TEST_TOKEN"] | Should -BeExactly "This {TOKEN} should be 'word'"
        } | Should -Not -Throw

        Assert-MockCalled Write-Verbose -Scope It -Exactly -Times 8 -ParameterFilter { $Message.StartsWith('Adding:') }
        Assert-MockCalled Write-Verbose -Scope It -Exactly -Times 1 -ParameterFilter { $Message.StartsWith('Skipping empty line:') }
        Assert-MockCalled Write-Verbose -Scope It -Exactly -Times 1 -ParameterFilter { $Message.StartsWith('Skipping line without assigmment:') }
        Assert-MockCalled Write-Verbose -Scope It -Exactly -Times 1 -ParameterFilter { $Message.StartsWith('Skipping line with comment:') }
    }
}
