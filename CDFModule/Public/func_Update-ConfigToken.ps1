Function Update-ConfigToken {
    <#
    .SYNOPSIS
    Replace tokens in a string with values.

    .DESCRIPTION
    Finds tokens in a given string and replace them with values. It is best used to replace configuration values in a release pipeline.

    .PARAMETER Tokens
    A hashtable containing the tokens and the value that should replace them.

    .PARAMETER InputString
    The string containing the tokens.

    .PARAMETER StartTokenPattern
    The start of the token, e.g. "{{".

    .PARAMETER EndTokenPattern
    The end of the token, e.g. "}}".

    .PARAMETER NullPattern
    The pattern that is used to signify $null. The reason for using this is that
    you cannot set an environment variable to null, so instead, set the environment
    variable to this pattern, and this script will replace the token with an the <NullPattern> string.

    .PARAMETER NoWarning
    If this is used, the script will not warn about tokens that cannot be found in the
    input file. This is useful when using environment variables to replace tokens since
    there will be a lot of warnings that aren't really warnings.

    .OUTPUTS
    The input string with substituted tokens

    .EXAMPLE
    $myConfig = '''
    {
        "url": "{{URL}}",
        "username": "{{USERNAME}}",
        "password": "{{PASSWORD}}"
    }
    '''
    Update-CdfConfigTokens `
        -InputString $myConfig `
        -Tokens @{URL="http://localhost:8080";USERNAME="admin";PASSWORD="Test123"} `
        -StartTokenPattern "{{" `
        -EndTokenPattern "}}"


    config.json (result):
        {
        "url": "http://localhost:8080",
        "username": "admin",
        "password": "Test123"
        }
#>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string]$InputString,

        [Parameter(Mandatory = $true)]
        [Hashtable]$Tokens,

        [Parameter(Mandatory = $false)]
        [string]$StartTokenPattern = '{{',

        [Parameter(Mandatory = $false)]
        [string]$EndTokenPattern = '}}',

        [Parameter(Mandatory = $false)]
        [string]$NullPattern = ":::NULL:::",

        [Parameter(Mandatory = $false)]
        [switch]$NoWarning
    )

    function GetTokenCount($line) {
		($line | Select-String -Pattern "$($StartTokenPattern).+?$($EndTokenPattern)" -AllMatches).Matches.Count
    }

    $TokensReplaced = [System.Text.StringBuilder]""

    # Go through each line of the InputFile and replace the tokens with their values
    $totalTokens = 0
    $missedTokens = 0
    $usedTokens = New-Object -TypeName "System.Collections.ArrayList"
    $InputString | ForEach-Object {
        $line = $_
        $totalTokens += GetTokenCount($line)
        foreach ($key in $Tokens.Keys) {
            $token = "$($StartTokenPattern)$($key)$($EndTokenPattern)"
            $value = $Tokens.$key
            if ($line -match $token) {
                $usedTokens.Add($key) | Out-Null
                if ($value -eq $NullPattern) {
                    $value = ""
                }
                Write-Verbose "Replacing $token with $value"
                $line = $line -replace "$token", "$value"
            }
        }
        $missedTokens += GetTokenCount($line)
        $TokensReplaced.Append($line) | Out-Null
    }

    # Write warning if there were tokens given in the Token parameter which were not replaced
    if (!$NoWarning -and $usedTokens.Count -ne $Tokens.Count) {
        $unusedTokens = New-Object -TypeName "System.Collections.ArrayList"
        foreach ($token in $Tokens.Keys) {
            if (!$usedTokens.Contains($token)) {
                $unusedTokens.Add($token) | Out-Null
            }
        }
        Write-Warning "The following tokens were not used: $($unusedTokens)"
    }

    # Write status message -- warn if there were tokens in the file that were not replaced
    $message = "Processed: $($InputFile) ($($totalTokens - $missedTokens) out of $totalTokens tokens replaced)"
    if ($missedTokens -gt 0) {
        Write-Warning $message
    }
    else {
        Write-Verbose $message
    }
    return $TokensReplaced.ToString()
}