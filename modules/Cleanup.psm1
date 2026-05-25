# Cleanup.psm1 - Temp files, disk cleanup, recycle bin

function Clear-OldFile {
    # Delete files under $Path that are older than $MinAgeHours, one file at a
    # time. Per-file deletion (instead of a recursive Remove-Item) means a
    # locked or in-use file - e.g. an installer/CBS file Windows is actively
    # writing during an update - is skipped rather than aborting the whole
    # sweep or wedging servicing. Skips reparse points (junctions/symlinks) so
    # we never follow a link out of the intended directory. Returns the number
    # of bytes actually freed, so the caller's total is accurate.
    param(
        [string]$Path,
        [int]$MinAgeHours = 24,
        [string[]]$ExcludePaths = @()
    )

    [long]$freed = 0
    $cutoff = (Get-Date).AddHours(-$MinAgeHours)

    # Resolve the base path and excludes to canonical (long) form. Enumerated
    # file paths come back long, but $Path/$ExcludePaths may be passed in 8.3
    # short form (e.g. C:\Users\RUNNER~1\...); without this the StartsWith
    # exclusion silently misses and a protected file gets deleted.
    try { $Path = (Get-Item -LiteralPath $Path -ErrorAction Stop).FullName } catch { $null = $_ }
    $resolvedExcludes = @()
    foreach ($ex in $ExcludePaths) {
        if ([string]::IsNullOrWhiteSpace($ex)) { continue }
        try { $resolvedExcludes += (Get-Item -LiteralPath $ex -ErrorAction Stop).FullName }
        catch { $resolvedExcludes += $ex }
    }

    $files = @()
    try {
        $files = Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.LastWriteTime -lt $cutoff -and
                -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
            }
    } catch {
        return [long]0
    }

    foreach ($f in $files) {
        $skip = $false
        foreach ($ex in $resolvedExcludes) {
            if ($f.FullName.StartsWith($ex, [System.StringComparison]::OrdinalIgnoreCase)) {
                $skip = $true
                break
            }
        }
        if ($skip) { continue }

        $size = $f.Length
        try {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            $freed += $size
        } catch {
            $null = $_  # locked / in use - leave it in place
        }
    }
    return $freed
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

    # Never delete the optimizer's own log/undo files if its data dir happens
    # to live under one of the temp paths (e.g. the %TEMP% fallback).
    $excludes = @()
    if (Get-Command Get-OptimizerDataDir -ErrorAction SilentlyContinue) {
        $excludes += (Get-OptimizerDataDir)
    }

    # Only touch files older than this. Disk Cleanup uses the same idea:
    # freshly written temp files are likely still in use by a running app.
    $minAgeHours = 24

    $totalCleaned = 0
    foreach ($cp in $cleanPaths) {
        if (Test-Path $cp.Path) {
            if ($DryRun) {
                Write-Dry "Would clean files older than ${minAgeHours}h in $($cp.Desc) at $($cp.Path)"
                continue
            }
            $freedBytes = Clear-OldFile -Path $cp.Path -MinAgeHours $minAgeHours -ExcludePaths $excludes
            $freed = [math]::Round($freedBytes / 1MB, 1)
            if ($freed -gt 0) {
                Write-Fix "Cleaned $($cp.Desc): $freed MB freed"
                $totalCleaned += $freed
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

Export-ModuleMember -Function Invoke-CleanupOptimization, Clear-OldFile
