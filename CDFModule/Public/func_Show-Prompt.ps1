Function Show-Prompt {
    <#
        .SYNOPSIS
            Prompt Function for PowerShell CDF Sessions.
    #>

    # NOTE: We disable strict mode for the scope of this function because it unhelpfully throws an
    # error when $LastHistoryEntry is null, and is not otherwise useful.
    Set-StrictMode -Off
    $LastHistoryEntry = Get-History -Count 1
    $Result = ''

    # Skip finishing the command if the first command has not yet started
    if ($Global:__LastHistoryId -ne -1) {
        if ($LastHistoryEntry.Id -eq $Global:__LastHistoryId) {
            # Don't provide a command line or exit code if there was no history entry (eg. ctrl+c, enter on no command)
            $Result += "$([char]0x1b)]633;D`a"
        }
        else {
            # Command finished exit code
            # OSC 633 ; D [; <ExitCode>] ST
            $Result += "$([char]0x1b)]633;D;$FakeCode`a"
        }
    }
    # Prompt started
    # OSC 633 ; A ST
    $Result += "$([char]0x1b)]633;A`a"

    # Powershell Version
    $PSVersion = $PSVersionTable.PSVersion.ToString() 
    $Result += "`e[34mPowerShell `e[37mv$PSVersion" 

    # CDF Version and Context
    $cdfModule = Get-Module -Name CDFModule
    if ($null -ne $cdfModule) {
        $CdfConfig = Get-CdfConfigPlatform -ErrorAction:SilentlyContinue -WarningAction:SilentlyContinue
        $CdfConfig = $CdfConfig | Get-CdfConfigApplication -ErrorAction:SilentlyContinue -WarningAction:SilentlyContinue

        $Result += " | `e[34mCDF`e[37m v$($cdfModule.Version)" 
        if ($cdfModule.PrivateData.PSData.Prerelease ) {
            $Result += "-$($cdfModule.PrivateData.PSData.Prerelease)" 
        }

        $Result += $env:CDF_PLATFORM_ID ? " | ${env:CDF_PLATFORM_ID}${env:CDF_PLATFORM_INSTANCE}" : ''
        $Result += $env:CDF_APPLICATION_ID ? "-${env:CDF_APPLICATION_ID}${env:CDF_APPLICATION_INSTANCE}" : ''
        $Result += $env:CDF_DOMAIN_NAME ? "-${env:CDF_DOMAIN_NAME}" : ''
        
        if (Test-Path 'cdf-config.json') {
            $svcConfig = Get-Content -Raw "cdf-config.json" | ConvertFrom-Json -AsHashtable
            $ServiceName = $svcConfig.ServiceDefaults.ServiceName
            $ServiceGroup = $svcConfig.ServiceDefaults.ServiceGroup
            # $ServiceType = $svcConfig.ServiceDefaults.ServiceType
            # $ServiceTemplate = $svcConfig.ServiceDefaults.ServiceTemplate
            $Result += "`e[33m:${ServiceName}:${ServiceGroup}`e[37m"
        }
        elseif ($env:CDF_SERVICE_NAME) {
            $ServiceName = $env:CDF_SERVICE_NAME
            $ServiceGroup = $env:CDF_SERVICE_GROUP
            #$ServiceType = $env:CDF_SERVICE_TYPE
            #$ServiceTemplate = $env:CDF_SERVICE_TEMPLATE
            $Result += "${ServiceName}:${ServiceGroup}"
        }

        # Add application environment to the prompt if different from platform environment
        switch ($CdfConfig.Platform.Env.purpose) {
            'production' { $envColor = "`e[91m" }
            'validation' { $envColor = "`e[32m" }
            Default { $envColor = "`e[34m" }
        } 
        
        $envName = $CdfConfig.Application.Env.nameId
        if ($envName -ne $CdfConfig.Platform.Env.nameId ) {
            $envName = $CdfConfig.Platform.Env.nameId + "/" + $envName
        }
        $Result += " [${envColor}${envName}`e[37m]"
    }

    # Output current working directory and git status
    $cwd = $executionContext.SessionState.Path.CurrentLocation.ProviderPath
    if ($cwd.Length -gt 40 -and ($cwd.Split([IO.Path]::DirectorySeparatorChar)).Length -gt 5) {
        $elemCwd = $cwd.Split([IO.Path]::DirectorySeparatorChar)
        if ('Unix' -eq $PSVersionTable.Platform) {
            $elemCwd[0] = [IO.Path]::DirectorySeparatorChar
        }
        $Cwd = Join-Path $elemCwd[0] $elemCwd[1] '...' $elemCwd[-3] $elemCwd[-2] $elemCwd[-1]
    }
    if (Get-Module posh-git) {
        $Result += Write-VcsStatus
        $Result += "`n"
        # $Result += " `e[36m$Cwd`e[37m`n"
    }
    else {
        # Current working directory in short form
        $Result += " | `e[36m$Cwd`e[37m`n"
    }

    # VSCode, datetime and duration of last command
    $Result += "PWSH: " 
    $Result += (Get-Date -Format HH:mm:ss)
    if (Get-History) {
        $Result += " [`e[36m"
        $Result += (Format-ElapsedTime ((Get-History)[-1].EndExecutionTime - (Get-History)[-1].StartExecutionTime))
        $Result += "`e[37m]"
    }

    # Run the original prompt
    # $OriginalPrompt += $Global:__VSCodeOriginalPrompt.Invoke()
    # $Result += $OriginalPrompt

    # Prompt
    # OSC 633 ; <Property>=<Value> ST
    if ($isStable -eq "0") {
        $Result += "$([char]0x1b)]633;P;Prompt=$(__VSCode-Escape-Value $OriginalPrompt)`a"
    }

    # Write command started
    $Result += "$([char]0x1b)]633;B`a > "
    $Global:__LastHistoryId = $LastHistoryEntry.Id
    return $Result
    # return " > "
}