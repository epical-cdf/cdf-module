#region Prompt
Write-Verbose "Loading CDF PowerShell prompt."
$Global:CdfPromptEnabled = $true
if (!$Global:CdfPromptBackup) {
    $Global:CdfPromptBackup = Get-Content Function:/Prompt
}

Function Format-ElapsedTime($ts) {
    $elapsedTime = ""

    if ( $ts.TotalMinutes -gt 0 ) {
        $elapsedTime = [string]::Format( "{0:0}.{1:00} min", $ts.TotalMinutes, $ts.Seconds );
    }
    else {
        $elapsedTime = [string]::Format( "{0:0}.{1:000} s", $ts.Seconds, $ts.Milliseconds);
    }

    if ($ts.Hours -eq 0 -and $ts.Minutes -eq 0 -and $ts.Seconds -eq 0) {
        $elapsedTime = [string]::Format("{0:0} ms", $ts.TotalMilliseconds);
    }

    return $elapsedTime
}
Function Global:Prompt {
    <#
        .SYNOPSIS
            Prompt Function for PowerShell CDF Sessions.
    #>

    # Powershell Version
    $PSVersion = $PSVersionTable.PSVersion.ToString()
    Write-Host "PowerShell " -ForegroundColor Blue -NoNewLine
    Write-Host "v$PSVersion" -ForegroundColor White -NoNewLine

    # CDF Version and Context
    $cdfModule = Get-Module -Name CDFModule
    if ($cdfModule) {
        $CdfConfig = Get-CdfConfigPlatform -ErrorAction:SilentlyContinue -WarningAction:SilentlyContinue
        $CdfConfig = $CdfConfig | Get-CdfConfigApplication -ErrorAction:SilentlyContinue -WarningAction:SilentlyContinue
        $envName = $CdfConfig.Application.Env.nameId
        if ($envName -ne $CdfConfig.Platform.Env.nameId ) {
            $envName = $CdfConfig.Platform.Env.nameId + "/" + $envName
        }
        Write-Host " | " -ForegroundColor Gray -NoNewline
        Write-Host "CDF" -ForegroundColor Blue -NoNewLine
        Write-Host (" v" + $($cdfModule.Version)) -ForegroundColor White -NoNewLine
        if ($cdfModule.PrivateData.PSData.Prerelease ) {
            Write-Host ("-" + $cdfModule.PrivateData.PSData.Prerelease) -ForegroundColor White -NoNewLine
        }
        if (Test-Path 'cdf-config.json') {
            $svcConfig = Get-Content -Raw "cdf-config.json" | ConvertFrom-Json -AsHashtable
            $ServiceName = $svcConfig.ServiceDefaults.ServiceName
            $ServiceGroup = $svcConfig.ServiceDefaults.ServiceGroup
            # $ServiceType = $svcConfig.ServiceDefaults.ServiceType
            # $ServiceTemplate = $svcConfig.ServiceDefaults.ServiceTemplate
            $SvcColor = 'Yellow'
        }
        else {
            $ServiceName = $env:CDF_SERVICE_NAME
            #$ServiceGroup = $env:CDF_SERVICE_GROUP
            #$ServiceType = $env:CDF_SERVICE_TYPE
            #$ServiceTemplate = $env:CDF_SERVICE_TEMPLATE
            $SvcColor = 'White'
        }
        Write-Host (" | " + $env:CDF_PLATFORM_ID + $env:CDF_PLATFORM_INSTANCE) -ForegroundColor White -NoNewLine
        Write-Host ("-" + $env:CDF_APPLICATION_ID + $env:CDF_APPLICATION_INSTANCE) -ForegroundColor White -NoNewLine
        Write-Host ("/" + $env:CDF_DOMAIN_NAME) -ForegroundColor White -NoNewLine
        Write-Host (":" + $ServiceName) -ForegroundColor $SvcColor -NoNewLine
        Write-Host (":" + $ServiceGroup) -ForegroundColor $SvcColor -NoNewLine
        Write-Host (" [" + $envName + "]") -ForegroundColor Gray -NoNewLine
    }

    # Output current working directory and git status
    Write-Host " | " -ForegroundColor Gray -NoNewline
    $cwd = $executionContext.SessionState.Path.CurrentLocation.ProviderPath
    if ($cwd.Length -gt 40 -and ($cwd.Split([IO.Path]::DirectorySeparatorChar)).Length -gt 5) {
        $elemCwd = $cwd.Split([IO.Path]::DirectorySeparatorChar)
        if ('Unix' -eq $PSVersionTable.Platform) {
            $elemCwd[0] = [IO.Path]::DirectorySeparatorChar
        }
        $Cwd = Join-Path -Path @($elemCwd[0], $elemCwd[1], '...', $elemCwd[-3], $elemCwd[-2], $elemCwd[-1])
    }
    Write-Host $Cwd -NoNewline -ForegroundColor Red
    if (Get-Module posh-git) {
        $vcsStatus = Write-VcsStatus
    }
    Write-Host $vcsStatus

    # VSCode, datetime and duration of last command
    Write-Host "PWSH: " -ForegroundColor Yellow -NoNewLine
    Write-Host (Get-Date -Format HH:mm:ss) -ForegroundColor Gray -NoNewLine
    if (Get-History) {
        Write-Host " [" -ForegroundColor Gray -NoNewLine
        Write-Host (Format-ElapsedTime ((Get-History)[-1].EndExecutionTime - (Get-History)[-1].StartExecutionTime)) -ForegroundColor Cyan -NoNewline
        Write-Host "]" -ForegroundColor Gray -NoNewLine
    }
    return " > "
}
$Global:CdfPrompt = Get-Content Function:/Prompt
Write-Verbose " Done."
#endregion
