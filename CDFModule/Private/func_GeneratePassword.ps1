Function GeneratePassword {
    [CmdletBinding()]
    Param(
        [ValidateRange(8,16)]
        [int] $Length = 12,
        [int] $Upper = 1,
        [int] $Lower = 1,
        [int] $Numeric = 1,
        [int] $Special = 1
    )

    if($Upper + $Lower + $Numeric + $Special -gt $Length) {
        throw "Total of Upper/Lower/Numeric/Special char must be less than or equal to length."
    }
    $uCharSet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    $lCharSet = "abcdefghijklmnopqrstuvwxyz"
    $nCharSet = "0123456789"
    $sCharSet = "*-+,!=._"
    $charSet = ""
    if($Upper -gt 0) { $charSet += $uCharSet }
    if($Lower -gt 0) { $charSet += $lCharSet }
    if($Numeric -gt 0) { $charSet += $nCharSet }
    if($Special -gt 0) { $charSet += $sCharSet }
    $charSet = $charSet.ToCharArray()
    $valid = $false

    while($valid -eq $false)
    {
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $bytes = New-Object byte[]($Length)
    $rng.GetBytes($bytes)
    $result = New-Object char[]($Length)
    for ($i = 0 ; $i -lt $Length ; $i++) {
        $result[$i] = $charSet[$bytes[$i] % $charSet.Length]
    }
    $password = (-join $result)
    $valid = $true
    if($Upper   -gt ($password.ToCharArray() | Where-Object {$_ -cin $uCharSet.ToCharArray() }).Count) { $valid = $false }
    if($Lower   -gt ($password.ToCharArray() | Where-Object {$_ -cin $lCharSet.ToCharArray() }).Count) { $valid = $false }
    if($Numeric -gt ($password.ToCharArray() | Where-Object {$_ -cin $nCharSet.ToCharArray() }).Count) { $valid = $false }
    if($Special -gt ($password.ToCharArray() | Where-Object {$_ -cin $sCharSet.ToCharArray() }).Count) { $valid = $false }
    if($valid) {
        return ConvertTo-SecureString $password -AsPlainText -Force
    }
}
}