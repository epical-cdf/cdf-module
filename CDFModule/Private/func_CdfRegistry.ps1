# Registry provider abstraction for CDF package management
# Supports pluggable backends (ACR, GitHub Packages, etc.)

class CdfRegistryProvider {
    [string]$Type
    [string]$Endpoint

    CdfRegistryProvider([string]$Type, [string]$Endpoint) {
        $this.Type = $Type
        $this.Endpoint = $Endpoint
    }

    # List available tags/releases for a package in the registry
    [string[]] ListReleases([string]$PackagePath) {
        throw "ListReleases must be implemented by subclass"
    }

    # Pull a package from the registry to a local directory
    [void] Pull([string]$PackagePath, [string]$Tag, [string]$OutputDir) {
        throw "Pull must be implemented by subclass"
    }

    # Push a local directory as a package to the registry
    [void] Push([string]$PackagePath, [string]$Tag, [string]$SourceDir) {
        throw "Push must be implemented by subclass"
    }

    [void] Push([string]$PackagePath, [string]$Tag, [string]$SourceDir, [hashtable]$Annotations) {
        throw "Push must be implemented by subclass"
    }
}

class CdfAcrRegistryProvider : CdfRegistryProvider {

    CdfAcrRegistryProvider([string]$Endpoint) : base('acr', $Endpoint) {}

    [string] GetOrasRef([string]$PackagePath, [string]$Tag) {
        return "$($this.Endpoint)/${PackagePath}:${Tag}"
    }

    # Ensure oras CLI is available and user is logged in
    [void] EnsureOras() {
        if (-not (Get-Command 'oras' -ErrorAction SilentlyContinue)) {
            throw "The 'oras' CLI is required for ACR registry operations. Install from https://oras.land/docs/installation"
        }
    }

    # Login to ACR using Azure CLI token
    [void] Login() {
        $this.EnsureOras()
        $token = (Get-AzAccessToken -ResourceUrl "https://$($this.Endpoint)" -ErrorAction Stop).Token
        oras login $this.Endpoint --username '00000000-0000-0000-0000-000000000000' --password $token 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to login to ACR '$($this.Endpoint)'"
        }
    }

    [string[]] ListReleases([string]$PackagePath) {
        $this.EnsureOras()
        $ref = "$($this.Endpoint)/${PackagePath}"
        $output = oras repo tags $ref 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to list tags for '$ref': $output"
            return @()
        }
        return ($output -split "`n" | Where-Object { $_ -match '^\d+\.\d+\.\d+' })
    }

    [void] Pull([string]$PackagePath, [string]$Tag, [string]$OutputDir) {
        $this.EnsureOras()
        $ref = $this.GetOrasRef($PackagePath, $Tag)
        if (!(Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }
        Push-Location $OutputDir
        try {
            $output = oras pull $ref 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to pull '$ref': $output"
            }
        }
        finally {
            Pop-Location
        }
    }

    [void] Push([string]$PackagePath, [string]$Tag, [string]$SourceDir) {
        $this.Push($PackagePath, $Tag, $SourceDir, @{})
    }

    [void] Push([string]$PackagePath, [string]$Tag, [string]$SourceDir, [hashtable]$Annotations) {
        $this.EnsureOras()
        $ref = $this.GetOrasRef($PackagePath, $Tag)
        Push-Location $SourceDir
        try {
            $files = Get-ChildItem -Recurse -File | ForEach-Object {
                $_.FullName.Substring($SourceDir.Length + 1)
            }
            $annotationArgs = @()
            foreach ($key in $Annotations.Keys) {
                $annotationArgs += '--annotation'
                $annotationArgs += "${key}=$($Annotations[$key])"
            }
            $output = oras push $ref @files @annotationArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to push '$ref': $output"
            }
        }
        finally {
            Pop-Location
        }
    }
}

class CdfOciRegistryProvider : CdfRegistryProvider {
    [string]$Username
    [string]$PasswordEnvVar

    CdfOciRegistryProvider([string]$Endpoint, [string]$Username, [string]$PasswordEnvVar) : base('oci', $Endpoint) {
        $this.Username = $Username
        $this.PasswordEnvVar = $PasswordEnvVar
    }

    [string] GetOrasRef([string]$PackagePath, [string]$Tag) {
        return "$($this.Endpoint)/${PackagePath}:${Tag}"
    }

    [void] EnsureOras() {
        if (-not (Get-Command 'oras' -ErrorAction SilentlyContinue)) {
            throw "The 'oras' CLI is required for OCI registry operations. Install from https://oras.land/docs/installation"
        }
    }

    # Login using username + password from environment variable
    [void] Login() {
        $this.EnsureOras()
        $password = [System.Environment]::GetEnvironmentVariable($this.PasswordEnvVar)
        if ([string]::IsNullOrEmpty($password)) {
            throw "Environment variable '$($this.PasswordEnvVar)' is not set. Set it to your registry token/password."
        }
        # oras login requires just the registry host, not the full path
        $registryHost = ($this.Endpoint -split '/')[0]
        $output = oras login $registryHost --username $this.Username --password $password 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to login to OCI registry '$registryHost': $output"
        }
    }

    [string[]] ListReleases([string]$PackagePath) {
        $this.EnsureOras()
        $ref = "$($this.Endpoint)/${PackagePath}"
        $output = oras repo tags $ref 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to list tags for '$ref': $output"
            return @()
        }
        return ($output -split "`n" | Where-Object { $_ -match '^\d+\.\d+\.\d+' })
    }

    [void] Pull([string]$PackagePath, [string]$Tag, [string]$OutputDir) {
        $this.EnsureOras()
        $ref = $this.GetOrasRef($PackagePath, $Tag)
        if (!(Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }
        Push-Location $OutputDir
        try {
            $output = oras pull $ref 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to pull '$ref': $output"
            }
        }
        finally {
            Pop-Location
        }
    }

    [void] Push([string]$PackagePath, [string]$Tag, [string]$SourceDir) {
        $this.Push($PackagePath, $Tag, $SourceDir, @{})
    }

    [void] Push([string]$PackagePath, [string]$Tag, [string]$SourceDir, [hashtable]$Annotations) {
        $this.EnsureOras()
        $ref = $this.GetOrasRef($PackagePath, $Tag)
        Push-Location $SourceDir
        try {
            $files = Get-ChildItem -Recurse -File | ForEach-Object {
                $_.FullName.Substring($SourceDir.Length + 1)
            }
            $annotationArgs = @()
            foreach ($key in $Annotations.Keys) {
                $annotationArgs += '--annotation'
                $annotationArgs += "${key}=$($Annotations[$key])"
            }
            $output = oras push $ref @files @annotationArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to push '$ref': $output"
            }
        }
        finally {
            Pop-Location
        }
    }
}

# Factory function to create a registry provider from a registry config entry
Function New-CdfRegistryProvider {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable]$RegistryConfig
    )

    switch ($RegistryConfig.type) {
        'acr' {
            return [CdfAcrRegistryProvider]::new($RegistryConfig.endpoint)
        }
        'oci' {
            $username = $RegistryConfig.username ?? 'cdf'
            $passwordEnvVar = $RegistryConfig.passwordEnvVar ?? 'CDF_REGISTRY_TOKEN'
            return [CdfOciRegistryProvider]::new($RegistryConfig.endpoint, $username, $passwordEnvVar)
        }
        default {
            throw "Unsupported registry type: '$($RegistryConfig.type)'. Supported types: acr, oci"
        }
    }
}

# Resolve a named registry config using layered lookup:
#  1. <project>/.cdf/registries/<name>.json
#  2. $HOME/.cdf/registries/<name>.json
#  3. Inline registries from cdf-packages.json manifest (optional hashtable)
Function Resolve-CdfRegistryConfig {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)]
        [string]$Name = 'default',
        [Parameter(Mandatory = $false)]
        [hashtable]$InlineRegistries,
        [Parameter(Mandatory = $false)]
        [string]$ProjectDir = (Get-Location).Path
    )

    # 1. Project-level
    $projectFile = Join-Path $ProjectDir ".cdf/registries/$Name.json"
    if (Test-Path $projectFile) {
        Write-Verbose "Resolved registry '$Name' from project: $projectFile"
        return Get-Content -Raw $projectFile | ConvertFrom-Json -AsHashtable
    }

    # 2. User-level
    $userFile = Join-Path $HOME ".cdf/registries/$Name.json"
    if (Test-Path $userFile) {
        Write-Verbose "Resolved registry '$Name' from user: $userFile"
        return Get-Content -Raw $userFile | ConvertFrom-Json -AsHashtable
    }

    # 3. Inline from manifest
    if ($InlineRegistries -and $InlineRegistries.ContainsKey($Name)) {
        Write-Verbose "Resolved registry '$Name' from inline manifest"
        return $InlineRegistries[$Name]
    }

    throw "Registry '$Name' not found. Create '$userFile' or define it in cdf-packages.json registries."
}
