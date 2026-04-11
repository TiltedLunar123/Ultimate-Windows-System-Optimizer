# Performance.psm1 - Gaming tweaks, visual effects, memory, GPU scheduling, boot, scheduled tasks, background apps

function Invoke-PowerOptimization {
    param([hashtable]$Analysis)

    $DryRun = Get-DryRunMode

    Write-Host "`n    -- Power Plan Optimization --" -ForegroundColor Cyan

    try {
        if ($Analysis.IsLaptop) {
            Write-Host "      Laptop detected - using optimized balanced profile" -ForegroundColor DarkGray

            if ($DryRun) {
                Write-Dry "Would optimize laptop power profile (AC/battery)"
            } else {
                powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
                powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
                powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5
                powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
                powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
                powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 0
                powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 900
                powercfg /setactive SCHEME_CURRENT
                Write-Fix "Laptop power profile optimized (high perf on AC, balanced on battery)"
            }
        } else {
            if ($DryRun) {
                Write-Dry "Would activate Ultimate/High Performance power plan"
            } else {
                $ultPerf = powercfg /list | Select-String "Ultimate Performance"
                if (-not $ultPerf) {
                    powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
                }

                $schemes = powercfg /list
                $ultGuid = ($schemes | Select-String "Ultimate Performance" | ForEach-Object { if ($_ -match '([a-f0-9-]{36})') { $Matches[1] } }) | Select-Object -First 1
                $highGuid = ($schemes | Select-String "High performance" | ForEach-Object { if ($_ -match '([a-f0-9-]{36})') { $Matches[1] } }) | Select-Object -First 1

                if ($ultGuid) {
                    powercfg /setactive $ultGuid
                    Write-Fix "Activated Ultimate Performance power plan"
                } elseif ($highGuid) {
                    powercfg /setactive $highGuid
                    Write-Fix "Activated High Performance power plan"
                }
            }
        }

        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" 1
        Write-Fix "Disabled power throttling"
    } catch {
        Write-Skip "Power plan optimization encountered errors"
        Log "[ERROR] Power plan: $_"
    }
}

function Invoke-VisualEffectsOptimization {
    param([hashtable]$Analysis)

    Write-Host "`n    -- Visual Effects Optimization --" -ForegroundColor Cyan

    $vePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    $dwmPath = "HKCU:\Software\Microsoft\Windows\DWM"
    $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    if ($Analysis.SystemTier -eq "Low-End") {
        Set-RegValue $vePath "VisualFXSetting" 2
        Set-RegValue "HKCU:\Control Panel\Desktop" "UserPreferencesMask" ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) "Binary"
        Set-RegValue "HKCU:\Control Panel\Desktop" "FontSmoothing" "2" "String"
        Set-RegValue "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" "String"
        Set-RegValue $advPath "ListviewAlphaSelect" 0
        Set-RegValue $advPath "TaskbarAnimations" 0
        Set-RegValue $dwmPath "EnableAeroPeek" 0
        Set-RegValue "HKCU:\Control Panel\Desktop" "DragFullWindows" "0" "String"
        Write-Fix "Visual effects set to MAXIMUM PERFORMANCE (Low-End system)"
    } elseif ($Analysis.SystemTier -eq "Mid-Range") {
        Set-RegValue $vePath "VisualFXSetting" 3
        Set-RegValue "HKCU:\Control Panel\Desktop" "FontSmoothing" "2" "String"
        Set-RegValue "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" "String"
        Set-RegValue $advPath "ListviewAlphaSelect" 1
        Set-RegValue $advPath "TaskbarAnimations" 0
        Set-RegValue $dwmPath "EnableAeroPeek" 0
        Set-RegValue "HKCU:\Control Panel\Desktop" "DragFullWindows" "1" "String"
        Write-Fix "Visual effects optimized for balanced quality/performance"
    } else {
        Set-RegValue "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" "String"
        Set-RegValue $advPath "TaskbarAnimations" 0
        Write-Fix "Visual effects: minimal tweaks (High-End system - keeping quality)"
    }
}

function Invoke-PerformanceOptimization {
    param([hashtable]$Analysis)

    Write-Host "`n    -- Performance Tweaks --" -ForegroundColor Cyan

    Set-RegValue "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode" 1
    Set-RegValue "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" 1
    Write-Fix "Game Mode enabled"

    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0
    Set-RegValue "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" 0
    Write-Fix "Game Bar / DVR capture disabled (reduces overhead)"

    Set-RegValue "HKCU:\System\GameConfigStore" "GameDVR_FSEBehaviorMode" 2
    Set-RegValue "HKCU:\System\GameConfigStore" "GameDVR_HonorUserFSEBehaviorMode" 1
    Set-RegValue "HKCU:\System\GameConfigStore" "GameDVR_FSEBehavior" 2
    Write-Fix "Fullscreen optimizations configured"

    if ([int]$Analysis.OSBuild -ge 19041) {
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2
        Write-Fix "Hardware-accelerated GPU scheduling enabled"
    }

    Set-RegValue "HKCU:\Control Panel\Mouse" "MouseSpeed" "0" "String"
    Set-RegValue "HKCU:\Control Panel\Mouse" "MouseThreshold1" "0" "String"
    Set-RegValue "HKCU:\Control Panel\Mouse" "MouseThreshold2" "0" "String"
    Write-Fix "Mouse acceleration disabled (1:1 precision)"

    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "GPU Priority" 8
    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "Priority" 6
    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "Scheduling Category" "High" "String"
    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "SFIO Priority" "High" "String"
    Write-Fix "Multimedia scheduler optimized for games"
}

function Invoke-SSDOptimization {
    param([hashtable]$Analysis)

    if (-not $Analysis.HasSSD) { return }

    $DryRun = Get-DryRunMode

    Write-Host "`n    -- SSD Optimization --" -ForegroundColor Cyan

    Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnablePrefetcher" 0
    Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnableSuperfetch" 0
    Write-Fix "Prefetch/Superfetch disabled (SSD doesn't need it)"

    if ($DryRun) {
        Write-Dry "Would disable last access timestamps"
        Write-Dry "Would enable TRIM for SSD"
    } else {
        fsutil behavior set disablelastaccess 1 2>&1 | Out-Null
        Write-Fix "Last access timestamps disabled (reduces SSD writes)"

        fsutil behavior set disabledeletenotify 0 2>&1 | Out-Null
        Write-Fix "TRIM enabled for SSD"
    }

    Write-Good "SSD optimization complete"
}

function Invoke-MemoryOptimization {
    param([hashtable]$Analysis)

    $DryRun = Get-DryRunMode

    Write-Host "`n    -- Memory Optimization --" -ForegroundColor Cyan

    if ($Analysis.TotalRAMGB -ge 16) {
        $minMB = 2048
        $maxMB = 4096
    } elseif ($Analysis.TotalRAMGB -ge 8) {
        $minMB = 4096
        $maxMB = 8192
    } else {
        $minMB = [int]($Analysis.TotalRAMGB * 1024 * 1.5)
        $maxMB = [int]($Analysis.TotalRAMGB * 1024 * 3)
    }

    # Fixed: use Write-Info instead of Write-Fix since we don't actually set the page file
    Write-Info "Page file recommendation" "$minMB MB - $maxMB MB (current RAM: $($Analysis.TotalRAMGB) GB)"

    if ($Analysis.TotalRAMGB -ge 16) {
        if ($DryRun) {
            Write-Dry "Would disable memory compression (16GB+ RAM)"
        } else {
            try {
                $memComp = Get-MMAgent -ErrorAction Stop
                if ($memComp.MemoryCompression) {
                    Disable-MMAgent -MemoryCompression -ErrorAction Stop
                    Write-Fix "Memory compression disabled (16GB+ RAM - CPU savings)"
                }
            } catch {
                Write-Skip "Could not modify memory compression setting"
            }
        }
    }

    Set-RegValue "HKLM:\SYSTEM\ControlSet001\Services\Ndu" "Start" 4
    Write-Fix "NDU service disabled (prevents memory leak)"
}

function Invoke-ScheduledTasksOptimization {
    param([hashtable]$Analysis)

    $null = $Analysis  # Used for interface consistency
    $DryRun = Get-DryRunMode

    Write-Host "`n    -- Disabling Bloat Scheduled Tasks --" -ForegroundColor Cyan

    $tasksToDisable = Get-BloatScheduledTaskList

    foreach ($task in $tasksToDisable) {
        if ($DryRun) {
            $shortName = $task.Split('\')[-1]
            Write-Dry "Would disable task: $shortName"
            continue
        }
        try {
            $taskPath = (Split-Path $task -Parent).TrimEnd('\') + '\'
            $taskName = Split-Path $task -Leaf
            $t = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
            if ($t -and $t.State -ne 'Disabled') {
                Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null
                $shortName = $task.Split('\')[-1]
                Write-Fix "Disabled task: $shortName"
            }
        } catch {
            Log "[ERROR] Could not disable task $task : $_"
        }
    }
}

function Invoke-BootOptimization {
    param([hashtable]$Analysis)

    $null = $Analysis  # Used for interface consistency
    $DryRun = Get-DryRunMode

    Write-Host "`n    -- Boot Optimization --" -ForegroundColor Cyan

    Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 1
    Write-Fix "Fast Startup enabled"

    if ($DryRun) {
        Write-Dry "Would reduce boot menu timeout to 3 seconds"
    } else {
        bcdedit /timeout 3 2>&1 | Out-Null
        Write-Fix "Boot menu timeout reduced to 3 seconds"
    }

    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "VerboseStatus" 1
    Write-Fix "Verbose boot messages enabled"
}

function Invoke-BackgroundAppsOptimization {
    param([hashtable]$Analysis)

    $null = $Analysis  # Used for interface consistency
    Write-Host "`n    -- Background Apps --" -ForegroundColor Cyan

    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" 1
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BackgroundAppGlobalToggle" 0
    Write-Fix "Background apps disabled globally (saves CPU & RAM)"
}

function Invoke-NotificationsOptimization {
    param([hashtable]$Analysis)

    $null = $Analysis  # Used for interface consistency
    Write-Host "`n    -- Notification & Distraction Cleanup --" -ForegroundColor Cyan

    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "RotatingLockScreenOverlayEnabled" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "RotatingLockScreenEnabled" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-310093Enabled" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" "NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK" 0
    Write-Fix "Notifications and nag screens reduced"
}

function Invoke-DiskOptimization {
    param([hashtable]$Analysis)

    $DryRun = Get-DryRunMode

    Write-Host "`n    -- Disk Optimization --" -ForegroundColor Cyan

    if ($Analysis.HasSSD) {
        if ($DryRun) {
            Write-Dry "Would run TRIM on SSD"
        } else {
            Write-Host "      Running TRIM on SSDs..." -ForegroundColor DarkGray
            try {
                Optimize-Volume -DriveLetter C -ReTrim -ErrorAction Stop
                Write-Fix "TRIM executed on SSD"
            } catch {
                Write-Skip "Could not run TRIM on SSD"
            }
        }
    }
    if ($Analysis.HasHDD) {
        if ($DryRun) {
            Write-Dry "Would start HDD defragmentation"
        } else {
            Write-Host "      HDD defrag will run in background..." -ForegroundColor DarkGray
            try {
                Start-Process -FilePath "defrag.exe" -ArgumentList "C: /O /U" -WindowStyle Hidden -ErrorAction Stop
                Write-Fix "HDD defragmentation started in background"
            } catch {
                Write-Skip "Could not start HDD defragmentation"
            }
        }
    }
}

function Invoke-FeaturesOptimization {
    param([hashtable]$Analysis)

    $null = $Analysis  # Used for interface consistency
    $DryRun = Get-DryRunMode

    Write-Host "`n    -- Disabling Unused Windows Features --" -ForegroundColor Cyan

    $featuresToDisable = Get-FeaturesToDisable

    # Context-aware: don't disable printing features if printers are installed
    $hasPrinters = $false
    try {
        $printers = Get-Printer -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch 'Microsoft|Fax|OneNote|PDF|XPS' }
        $hasPrinters = ($null -ne $printers -and @($printers).Count -gt 0)
    } catch { $null = $_ }

    if ($hasPrinters) {
        $featuresToDisable = $featuresToDisable | Where-Object { $_ -ne "Printing-Foundation-Features" }
        Write-Info "Printers detected" "Keeping printing features"
    }

    foreach ($feat in $featuresToDisable) {
        if ($DryRun) {
            Write-Dry "Would disable feature: $feat"
            continue
        }
        try {
            $f = Get-WindowsOptionalFeature -Online -FeatureName $feat -ErrorAction SilentlyContinue
            if ($f -and $f.State -eq 'Enabled') {
                Disable-WindowsOptionalFeature -Online -FeatureName $feat -NoRestart -ErrorAction Stop | Out-Null
                Write-Fix "Disabled feature: $feat"
            }
        } catch {
            Write-Skip "Could not disable feature: $feat"
            Log "[ERROR] Feature disable failed for $feat : $_"
        }
    }
}

Export-ModuleMember -Function Invoke-PowerOptimization, Invoke-VisualEffectsOptimization,
    Invoke-PerformanceOptimization, Invoke-SSDOptimization, Invoke-MemoryOptimization,
    Invoke-ScheduledTasksOptimization, Invoke-BootOptimization, Invoke-BackgroundAppsOptimization,
    Invoke-NotificationsOptimization, Invoke-DiskOptimization, Invoke-FeaturesOptimization
