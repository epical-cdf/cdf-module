$AzModule = Get-InstalledModule -Name Az -MinimumVersion 9.0.0 -ErrorAction SilentlyContinue
if ( -Not ( $AzModule )) {
    Write-Host "Missing Az module, installing..." -ForegroundColor Red
    Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
    $AzModule = Get-InstalledModule -Name Az -MinimumVersion 3.7.0 -ErrorAction SilentlyContinue
    Write-Host "Az module version:" $AzModule.Version -NoNewline -ForegroundColor Yellow
}
else {
    Write-Host "Using Az module version:" $AzModule.Version -NoNewline -ForegroundColor Yellow
}

