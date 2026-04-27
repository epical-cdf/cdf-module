BeforeAll {
    $testFolder = Split-Path -Parent $PSCommandPath
    $testFileName = (Split-Path -Leaf $PSCommandPath).Replace(".Tests.", ".")
    . $testFolder/$testFileName
}

Describe 'ConvertTo-DotEnv' {
    BeforeAll {
        Mock Write-Verbose {}
    }

    It 'Should convert hashtable' {
        {
            $config = [ordered] @{
                TEST_STRING1 = "Hello"
                TEST_STRING2 = "Hello World"
                TEST_STRING3 = 'Hellü Wörld! èé^ô`´\'
                TEST_NUMBER1 = "1"
                TEST_NUMBER2 = "1234567890"
                TEST_BOOL1   = "true"
                TEST_BOOL2   = "false"
                TEST_TOKEN   = "This {TOKEN} should be 'word'"
            }
            ConvertTo-DotEnv -DotEnvSource $config -Verbose | Should -BeExactly @'
TEST_STRING1=Hello
TEST_STRING2=Hello World
TEST_STRING3=Hellü Wörld! èé^ô`´\
TEST_NUMBER1=1
TEST_NUMBER2=1234567890
TEST_BOOL1=true
TEST_BOOL2=false
TEST_TOKEN=This {TOKEN} should be 'word'

'@
        } | Should -Not -Throw

        Assert-MockCalled Write-Verbose -Scope It -Exactly -Times 0
    }

    It 'Should convert 2x2 name-value pair array' {
        {
            , @( @('Name1', 'Value1'), @('Name2', 'Value2') ) | ConvertTo-DotEnv -Verbose | Should -BeExactly @'
Name1=Value1
Name2=Value2

'@
        } | Should -Not -Throw

        Assert-MockCalled Write-Verbose -Scope It -Exactly -Times 1 -ParameterFilter { "Is array is determined to be key-value-pairs: YES" }
    }

    It 'Should convert separate name and value column array' {


        {
            , @( @('Name1', 'Name2', 'Name3', 'Name4'), @('Value1', 'Value2', 'Value3', 'Value4') ) | ConvertTo-DotEnv -Verbose | Should -BeExactly @'
Name1=Value1
Name2=Value2
Name3=Value3
Name4=Value4

'@
        } | Should -Not -Throw

        Assert-MockCalled Write-Verbose -Scope It -Exactly -Times 1 -ParameterFilter { "Is array is determined to be key-value-pairs: NO" }
    }
}
