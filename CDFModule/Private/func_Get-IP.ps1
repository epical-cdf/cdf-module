Function Get-IP {
    return Invoke-RestMethod -Uri "https://api.ipify.org/"
}