Function ConvertTo-PlainToken {
    <#
    .SYNOPSIS
    Normalizes an access-token value to plain text, tolerating both [String] and [SecureString].

    .DESCRIPTION
    Internal helper. Since Az.Accounts 5.x (Az PowerShell 14.0; always in 16.0),
    Get-AzAccessToken returns its Token as a [SecureString]; older Az returned a
    [string]. Callers that need the raw bearer token (Authorization headers, container
    registry login passwords) use this to obtain a plain-text string regardless of the
    installed Az version. Unlike Get-AzKeyVaultSecret there is no -AsPlainText switch on
    Get-AzAccessToken, so the conversion is done here.

    .PARAMETER Token
    The value of (Get-AzAccessToken).Token — a [SecureString] or [string].

    .OUTPUTS
    [string] plain-text token, or $null when the input is $null.

    .NOTES
    Internal helper; not exported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    Param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object] $Token
    )

    if ($null -eq $Token) { return $null }
    if ($Token -is [System.Security.SecureString]) {
        return [System.Net.NetworkCredential]::new('', $Token).Password
    }
    return [string]$Token
}
