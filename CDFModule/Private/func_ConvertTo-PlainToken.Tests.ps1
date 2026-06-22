BeforeAll {
    # Dot-source the function under test.
    $testFolder = Split-Path -Parent $PSCommandPath
    $sourceFile = (Split-Path -Leaf $PSCommandPath).Replace('.Tests.', '.')
    . (Join-Path $testFolder $sourceFile)
}

Describe 'ConvertTo-PlainToken' {

    It 'converts a SecureString token to plain text (Az 14+/16 behaviour)' {
        $secure = ConvertTo-SecureString 'my-token-value' -AsPlainText -Force
        ConvertTo-PlainToken -Token $secure | Should -BeExactly 'my-token-value'
    }

    It 'passes a plain string token through unchanged (older Az)' {
        ConvertTo-PlainToken -Token 'plain-token' | Should -BeExactly 'plain-token'
    }

    It 'returns null for a null token' {
        ConvertTo-PlainToken -Token $null | Should -BeNullOrEmpty
    }
}
