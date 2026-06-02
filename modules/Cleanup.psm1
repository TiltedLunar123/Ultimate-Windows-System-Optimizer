# Cleanup.psm1 - Temp files, disk cleanup, recycle bin

function Get-CleanupMinAgeHour {
    # Files touched more recently than this are assumed to belong to an
    # active session (current temp files, in-progress downloads, open
    # handles) and are left alone. Issue #3 / #28: the cleanup used to
    # delete everything it could reach, which removed in-use files.
    return 24
}

function Select-AgedItem {
    # Pure age filter. Keeps only items whose LastWriteTime is older than
    # MinAgeHour before ReferenceTime. Pulled out of the cleanup loop so it
    # can be unit tested without touching the disk.
    param(
        [object[]]$Item,
        [int]$MinAgeHour = 24,
        [datetime]$ReferenceTime = (Get-Date)
    )
    if (-not $Item) { return @() }
    $cutoff = $ReferenceTime.AddHours(-[math]::Abs($MinAgeHour))
    @($Item | Where-Object { $_.LastWriteTime -lt $cutoff })
}

function Invoke-CleanupOptimization {
    param([hashtable]$Analysis)

    $null = $Analysis  # Used for interface consistency
    $DryRun = Get-DryRunMode

    Write-Host "`n    -- Cleaning Temporary Files --" -ForegroundColor Cyan

    $cleanPaths = @(
        @{ Path = "$env:TEMP";                                                     Desc = "User Temp" },
        @{ Path = "$env:WINDIR\Temp";                                              Desc = "Windows Temp" },
        @{ Path = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache";                 Desc = "Internet Cache" },
        @{ Path = "$env:WINDIR\SoftwareDistribution\Download";                     Desc = "Windows Update Cache" },
        @{ Path = "$env:LOCALAPPDATA\CrashDumps";                                  Desc = "Crash Dumps" },
        @{ Path = "$env:WINDIR\Logs\CBS";                                          Desc = "CBS Logs" },
        @{ Path = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer";                  Desc = "Thumbnail Cache" },
        @{ Path = "$env:WINDIR\Minidump";                                          Desc = "Minidump Files" }
    )

    $minAge = Get-CleanupMinAgeHour
    $now = Get-Date

    $totalCleaned = 0
    foreach ($cp in $cleanPaths) {
        if (Test-Path $cp.Path) {
            if ($DryRun) {
                Write-Dry "Would clean $($cp.Desc) at $($cp.Path) (files older than $minAge h)"
                continue
            }
            try {
                $before = (Get-ChildItem $cp.Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                # Files only, never a recursive directory delete: removing a
                # whole tree could take a file another process still has open
                # (issue #28). Age filter keeps anything from the last day so
                # in-use temp files survive (issue #3).
                $candidates = Get-ChildItem $cp.Path -Recurse -Force -File -ErrorAction SilentlyContinue
                $aged = Select-AgedItem -Item $candidates -MinAgeHour $minAge -ReferenceTime $now
                foreach ($f in $aged) {
                    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
                }
                $after = (Get-ChildItem $cp.Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                $freed = [math]::Round(($before - $after) / 1MB, 1)
                if ($freed -gt 0) {
                    Write-Fix "Cleaned $($cp.Desc): $freed MB freed"
                    $totalCleaned += $freed
                }
            } catch {
                Write-Skip "Could not clean $($cp.Desc)"
                Log "[ERROR] Cleanup failed for $($cp.Path): $_"
            }
        }
    }

    # Empty Recycle Bin
    if ($DryRun) {
        Write-Dry "Would empty Recycle Bin"
    } else {
        try {
            Clear-RecycleBin -Force -ErrorAction Stop
            Write-Fix "Recycle Bin emptied"
        } catch {
            Write-Skip "Could not empty Recycle Bin"
        }
    }

    # Windows Disk Cleanup (silent)
    if ($DryRun) {
        Write-Dry "Would run Disk Cleanup utility"
    } else {
        Write-Host "      Running Disk Cleanup utility..." -ForegroundColor DarkGray
        $cleanMgrFlags = @(
            "Active Setup Temp Folders",
            "Temporary Files",
            "Temporary Setup Files",
            "Old ChkDsk Files",
            "Setup Log Files",
            "Downloaded Program Files",
            "Delivery Optimization Files",
            "Thumbnail Cache",
            "Windows Error Reporting"
        )
        $volCachePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
        foreach ($flag in $cleanMgrFlags) {
            $p = Join-Path $volCachePath $flag
            if (Test-Path $p) {
                Set-ItemProperty -Path $p -Name "StateFlags0100" -Value 2 -Type DWord -ErrorAction SilentlyContinue
            }
        }
        try {
            # /sagerun:100 must complete before downstream phases reanalyze
            # disk state. Cap the wait at 10 minutes so a stuck cleanmgr
            # doesn't hang the whole run; on locked-down installs it has.
            $proc = Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:100" -WindowStyle Hidden -PassThru -ErrorAction Stop
            if (-not $proc.WaitForExit(600000)) {
                try { $proc.Kill() } catch { $null = $_ }
                Write-Skip "Disk Cleanup timed out after 10 minutes"
                Log "[WARN] cleanmgr.exe killed after 10-minute timeout"
            }
        } catch {
            Log "[ERROR] Disk Cleanup utility failed to start: $_"
        }
    }

    if (-not $DryRun) {
        Write-Good "Total space recovered: ~$([math]::Round($totalCleaned, 0)) MB"
    }
}

Export-ModuleMember -Function Invoke-CleanupOptimization, Get-CleanupMinAgeHour, Select-AgedItem
