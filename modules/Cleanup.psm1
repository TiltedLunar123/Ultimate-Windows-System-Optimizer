# Cleanup.psm1 - Temp files, disk cleanup, recycle bin

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

    $totalCleaned = 0
    foreach ($cp in $cleanPaths) {
        if (Test-Path $cp.Path) {
            if ($DryRun) {
                Write-Dry "Would clean $($cp.Desc) at $($cp.Path)"
                continue
            }
            try {
                $before = (Get-ChildItem $cp.Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                Get-ChildItem $cp.Path -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
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
            Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:100" -WindowStyle Hidden -ErrorAction SilentlyContinue
        } catch {
            Log "[ERROR] Disk Cleanup utility failed to start: $_"
        }
    }

    if (-not $DryRun) {
        Write-Good "Total space recovered: ~$([math]::Round($totalCleaned, 0)) MB"
    }
}

Export-ModuleMember -Function Invoke-CleanupOptimization
