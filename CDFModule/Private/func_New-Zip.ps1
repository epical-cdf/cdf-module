﻿# Based on Gist by "Araxeus", https://gist.github.com/Araxeus/a09797e84b0ef4b99f1efcc642d1da78
# TODO: Refactor, simplify
Function New-Zip {

    #  Specifying no parameter will result in current working directory ($pwd) being archived into $pwd\$pwd.zip
    param (
        # The following paths can be relative or absolute:
        # path to folder/s containing the files to be archived
        [Alias("i", "input", "from")]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string[]]
        $FolderPaths = @($PWD),
        # path to zipfile / zipFolder if $ZipNameFromJson is specified (will be created if it doesn't exist)
        [Alias("t", "to", "output")][string]
        $ZipPath = "", # defaults to $PWD.zip
        # set $ZipPath to end with .zip or set this to an empty string to disable this feature
        [Alias("j", "json")]
        [ValidatePattern('.json$')]
        [string]
        $ZipNameFromJson = "", # set to a json file containing name and version, output will be $name_v$version.zip
        # ie "*.*" to only include files that have a .extension
        [Alias("f")][string]
        $Filter = "",
        # filterScript has more options than eclude
        [Alias("e")][string[]]
        $Exclude = @(),
        # { ($_.FullName -notlike "*\node_modules\*") -and ($_.Name -notlike "*.scss")}, # ignore .scss and nodeModules folder
        [Alias("fs", "script")][ScriptBlock]
        $FilterScript = { $_ },
        # overwrite zip (if there is a zip with the same name, delete it creating a new one)
        [Alias("o", "overwrite")][switch]
        $OverwriteZip,
        # keep sync between folder and zip (doesn"t do anything if OverwriteZip=true) - delete surplus files from zip
        [Alias("s")][switch]
        $Sync,
        [Alias("ih")][switch]
        $IncludeHidden,
        # verbose output
        [Alias("v")][switch]
        $Verbose
    )

    $VerbosePreference = $Verbose ? "Continue" : "SilentlyContinue"

    if ($ZipNameFromJson -and !$ZipPath.EndsWith('.zip')) {
        $jsonFile = Get-Content $ZipNameFromJson
        $jsonObj = $jsonFile | ConvertFrom-Json
        $ZipName = "$($jsonObj.name.Trim().Replace(' ', '-'))_v$($jsonObj.version.Trim()).zip"
        if ($ZipPath) {
            try {
                [System.IO.Directory]::CreateDirectory($ZipPath) | Out-Null
                $ZipPath = [IO.Path]::Combine($ZipPath, $ZipName)
            }
            catch {
                Write-Error("`n Error creating ZipPath:`n $($_.Exception.Message)")
                $ZipPath = $ZipName
            }
        }
        else {
            $ZipPath = $ZipName
        }
    }
    elseif (!$ZipPath) {
        $ZipPath = [IO.Path]::Combine($PWD, "$(Split-Path -Path $PWD -Leaf).zip")
    }

    if ($OverwriteZip) {
        Remove-item -literalpath $ZipPath -force -ErrorAction SilentlyContinue
    }

    $AllFiles = New-Object System.Collections.Generic.List[System.Object]

    $ChangesCount = 0;

    try {
        $ZipArchive = [IO.Compression.ZipFile]::Open( $ZipPath, 2 )
        foreach ($FolderPath in $FolderPaths) {
            if ($IncludeHidden) {
                $FileList = (Get-ChildItem -LiteralPath $FolderPath -Filter $Filter -Exclude $Exclude -File -Recurse -Force | Where-Object $FilterScript) #use the -File argument because empty folders can"t be stored
            }
            else {
                $FileList = (Get-ChildItem -LiteralPath $FolderPath -Filter $Filter -Exclude $Exclude -File -Recurse | Where-Object $FilterScript) #use the -File argument because empty folders can"t be stored
            }
            foreach ($File in $FileList) {
                if ($File.FullName.endsWith($ZipPath)) { continue }
                # get relative path and trim leading .\ from it
                $File | Add-Member RelativePath ([System.IO.Path]::GetRelativePath($FolderPath, $File.FullName) -replace "^.\\")
                $AllFiles.Add($File)
                try {
                    # zip will store multiple copies of the exact same file - prevent this by checking if already archived.
                    if (!$OverwriteZip) {
                        $AlreadyArchivedFile = $ZipArchive.GetEntry($File.RelativePath)
                        # $AlreadyArchivedFile = ($ZipArchive.Entries | Where-Object { $_.FullName -eq $File.RelativePath })
                        if ($AlreadyArchivedFile) {
                            if (($AlreadyArchivedFile.Length -eq $File.Length) -and
                                #ZipFileExtensions timestamps are only precise within 2 seconds.
                            ([math]::Abs(($AlreadyArchivedFile.LastWriteTime.UtcDateTime - $File.LastWriteTimeUtc).Seconds) -le 2)) {
                                continue
                            }
                            $AlreadyArchivedFile.Delete()
                        }
                    }
                    $ZipArchiveEntry = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($ZipArchive, $File.FullName, $File.RelativePath, 'Optimal')
                    $ChangesCount++
                    Write-Verbose "Archived \$($ZipArchiveEntry.FullName)"
                }
                catch {
                    # single file failed - usually inaccessible or in use
                    Write-Warning  "`n $($File.FullName) could not be archived.`n $($_.Exception.Message)"
                }
            }
        }
        if ($Sync -and !$OverwriteZip) {
            $UnsyncedFiles = $ZipArchive.Entries | Where-Object -Property FullName -NotIn ($AllFiles | ForEach-Object { $_.RelativePath })
            foreach ($File in $UnsyncedFiles) {
                try {
                    $File.Delete()
                    $ChangesCount++
                    Write-Verbose "Deleted $($ZipPath)\$($File.FullName)"
                }
                catch {
                    Write-Warning "$($ZipPath)\$($File.FullName) is not in sync but couldn't be deleted"
                }
            }
        }
    }
    catch {
        # failure to open the zip file
        Write-Error $_.Exception
    }
    finally {
        # always close the zip file so it can be read later
        $ZipArchive.Dispose()
        Write-Host "$(Resolve-Path $ZipPath) was succesfully updated ($($ChangesCount) files changed)" -ForegroundColor Green
    }
}