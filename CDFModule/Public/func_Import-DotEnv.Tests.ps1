BeforeAll {
    $repoRoot = Split-Path -Parent (Resolve-Path $PSCommandPath/../..)
    $testFolder = Split-Path -Parent $PSCommandPath
    $testFileName = (Split-Path -Leaf $PSCommandPath).Replace(".Tests.", ".")
    . $testFolder/$($testFileName.Replace("Import-DotEnv", "Get-DotEnv"))
    . $testFolder/$testFileName
}

Describe 'Import-DotEnv' {

    It 'Should import .env file to environment' {
        {
            Import-DotEnv -Path $repoRoot/tests/data/Import-DotEnv-OK.env
        } | Should -Not -Throw

        (Get-Item Env:/TEST_STRING1).Value | Should -BeExactly 'Hello'
        (Get-Item Env:/TEST_STRING2).Value | Should -BeExactly 'Hello World'
        (Get-Item Env:/TEST_STRING3).Value | Should -BeExactly 'Hellü Wörld! èé^ô`´\'
        (Get-Item Env:/TEST_NUMBER1).Value | Should -BeExactly '1'
        (Get-Item Env:/TEST_NUMBER2).Value | Should -BeExactly '1234567890'
        (Get-Item Env:/TEST_BOOL1).Value | Should -BeExactly 'true'
        (Get-Item Env:/TEST_BOOL2).Value  | Should -BeExactly 'false'
        (Get-Item Env:/TEST_TOKEN).Value | Should -BeExactly "This {TOKEN} should be 'word'"
    }

    It 'Should import .env file to variables' {
        {
            Import-DotEnv -Path $repoRoot/tests/data/Import-DotEnv-OK.env -Type Regular
        } | Should -Not -Throw

        (Get-Variable TEST_STRING1).Value | Should -BeExactly 'Hello'
        (Get-Variable TEST_STRING2).Value | Should -BeExactly 'Hello World'
        (Get-Variable TEST_STRING3).Value | Should -BeExactly 'Hellü Wörld! èé^ô`´\'
        (Get-Variable TEST_NUMBER1).Value | Should -BeExactly '1'
        (Get-Variable TEST_NUMBER2).Value | Should -BeExactly '1234567890'
        (Get-Variable TEST_BOOL1).Value | Should -BeExactly 'true'
        (Get-Variable TEST_BOOL2).Value  | Should -BeExactly 'false'
        (Get-Variable TEST_TOKEN).Value | Should -BeExactly "This {TOKEN} should be 'word'"
    }

    It 'Should throw on right quote missing' {
        {
            Import-DotEnv -Path $repoRoot/tests/data/Import-DotEnv-MR.env
        } | Should -Throw -ExpectedMessage 'Missing terminating quote " in ''NOT_OK'': "Missing right quote'

    }

    It 'Should throw on left quote missing' {
        {
            Import-DotEnv -Path $repoRoot/tests/data/Import-DotEnv-ML.env
        } | Should -Throw -ExpectedMessage "Missing starting quote ' in 'NOT_OK': Missing left quote'"

    }

    It 'Should throw quote mismatch' {
        {
            Import-DotEnv -Path $repoRoot/tests/data/Import-DotEnv-LR.env
        } | Should -Throw -ExpectedMessage "Mismatched quotes in 'NOT_OK': ""Mismatch quotes'"

    }
}
