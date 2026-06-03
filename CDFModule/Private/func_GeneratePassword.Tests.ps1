BeforeAll {
    # Dot-source the function under test (private, not exported by the module).
    $testFolder = Split-Path -Parent $PSCommandPath
    $sourceFile = (Split-Path -Leaf $PSCommandPath).Replace('.Tests.', '.')
    . (Join-Path $testFolder $sourceFile)

    function Get-PlainPassword {
        param([System.Security.SecureString]$Secure)
        [System.Net.NetworkCredential]::new('', $Secure).Password
    }

    $script:UpperSet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $script:LowerSet = 'abcdefghijklmnopqrstuvwxyz'
    $script:NumberSet = '0123456789'
    $script:SpecialSet = '*-+,!=._'
}

Describe 'GeneratePassword' {

    It 'returns a SecureString' {
        GeneratePassword | Should -BeOfType [System.Security.SecureString]
    }

    It 'defaults to a length of 12' {
        $plain = Get-PlainPassword (GeneratePassword)
        $plain.Length | Should -Be 12
    }

    It 'generates a password of the requested length' {
        $plain = Get-PlainPassword (GeneratePassword -Length 14)
        $plain.Length | Should -Be 14
    }

    It 'satisfies the requested minimum for each character class' {
        $plain = Get-PlainPassword (GeneratePassword -Length 16 -Upper 2 -Lower 2 -Numeric 2 -Special 2)
        $chars = $plain.ToCharArray()

        @($chars | Where-Object { $script:UpperSet.Contains($_) }).Count | Should -BeGreaterOrEqual 2
        @($chars | Where-Object { $script:LowerSet.Contains($_) }).Count | Should -BeGreaterOrEqual 2
        @($chars | Where-Object { $script:NumberSet.Contains($_) }).Count | Should -BeGreaterOrEqual 2
        @($chars | Where-Object { $script:SpecialSet.Contains($_) }).Count | Should -BeGreaterOrEqual 2
    }

    It 'throws when class minimums exceed the length' {
        { GeneratePassword -Length 8 -Upper 3 -Lower 3 -Numeric 3 -Special 3 } |
            Should -Throw -ExpectedMessage '*less than or equal to length*'
    }

    It 'rejects a length outside the allowed range (8-16)' {
        { GeneratePassword -Length 4 } | Should -Throw
    }
}
