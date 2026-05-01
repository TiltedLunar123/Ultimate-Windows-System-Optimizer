# Analysis.psm1 - Phase 1: System analysis and health scoring

function Get-SystemAnalysis {
    Write-Section "PHASE 1: DEEP SYSTEM ANALYSIS"

    $results = @{
        IsLaptop          = $false
        TotalRAMGB        = 0
        FreeRAMGB         = 0
        RAMUsedPct        = 0
        CPUCores          = 0
        CPULogical        = 0
        CPUName           = ""
        OSVersion         = ""
        OSBuild           = ""
        DeviceType        = ""
        SystemTier        = ""
        Disks             = @()
        HasSSD            = $false
        HasHDD            = $false
        TempSizeMB        = 0
        TempFiles         = 0
        StartupItems      = @()
        ServicesToDisable  = @()
        BloatServices     = @()
        CurrentPowerPlan   = ""
        VisualEffects      = ""
        MemoryHogs        = @()
        CurrentDNS        = ""
        TelemetryEnabled  = $true
        CortanaEnabled    = $true
        AdIDEnabled       = $true
    }

    # -- 1.1 HARDWARE DETECTION --
    Write-Host "`n    -- Hardware Profile --" -ForegroundColor Cyan

    try {
        $os   = Get-CimInstance Win32_OperatingSystem
        $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
        $gpu  = Get-CimInstance Win32_VideoController | Select-Object -First 1
        $cs   = Get-CimInstance Win32_ComputerSystem
        $bat  = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    } catch {
        Write-Bad "Failed to query system hardware via WMI/CIM."
        Log "[ERROR] Hardware detection failed: $_"
        return $results
    }

    $results.IsLaptop    = ($null -ne $bat) -or ($cs.PCSystemType -eq 2)
    $results.TotalRAMGB  = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $results.FreeRAMGB   = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $results.RAMUsedPct  = [math]::Round((1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100, 1)
    $results.CPUCores    = $cpu.NumberOfCores
    $results.CPULogical  = $cpu.NumberOfLogicalProcessors
    $results.CPUName     = $cpu.Name.Trim()
    $results.OSVersion   = $os.Caption
    $results.OSBuild     = $os.BuildNumber
    $results.DeviceType  = if ($results.IsLaptop) { "Laptop" } else { "Desktop" }

    Write-Info "Device Type"        $results.DeviceType
    Write-Info "OS"                 "$($results.OSVersion) (Build $($results.OSBuild))"
    Write-Info "CPU"                "$($results.CPUName)"
    Write-Info "Cores / Threads"    "$($results.CPUCores) / $($results.CPULogical)"
    Write-Info "GPU"                "$($gpu.Name)"
    Write-Info "Total RAM"          "$($results.TotalRAMGB) GB"
    Write-Info "Free RAM"           "$($results.FreeRAMGB) GB ($($results.RAMUsedPct)% used)"
    Write-Info "Uptime"             "$([math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1)) hours"

    # Categorize system tier
    if ($results.TotalRAMGB -ge 16 -and $results.CPUCores -ge 6) {
        $results.SystemTier = "High-End"
    } elseif ($results.TotalRAMGB -ge 8 -and $results.CPUCores -ge 4) {
        $results.SystemTier = "Mid-Range"
    } else {
        $results.SystemTier = "Low-End"
    }
    Write-Info "System Tier"  $results.SystemTier

    # -- 1.2 DISK ANALYSIS --
    Write-Host "`n    -- Storage Analysis --" -ForegroundColor Cyan

    $volumes = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
    foreach ($vol in $volumes) {
        if ($vol.Size -eq 0) { continue }
        $totalGB = [math]::Round($vol.Size / 1GB, 1)
        $freeGB  = [math]::Round($vol.FreeSpace / 1GB, 1)
        $usedPct = [math]::Round((1 - $vol.FreeSpace / $vol.Size) * 100, 1)

        $health = if ($freeGB -lt 10) { "CRITICAL" }
                  elseif ($freeGB -lt 30) { "WARNING" }
                  else { "HEALTHY" }

        $color = switch ($health) { "CRITICAL" { "Red" } "WARNING" { "Yellow" } default { "Green" } }
        Write-Status "Drive $($vol.DeviceID) - $freeGB GB free / $totalGB GB" $health $color

        $results.Disks += @{ Drive = $vol.DeviceID; FreeGB = $freeGB; TotalGB = $totalGB; UsedPct = $usedPct; Health = $health }
    }

    # Detect SSD vs HDD. Get-PhysicalDisk lives in the Storage module, which
    # is missing on early Windows 10 builds (1607/1703). A missing cmdlet
    # throws CommandNotFoundException, which is terminating and ignores
    # -ErrorAction, so probe with Get-Command first.
    $physDisks = $null
    if (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue) {
        $physDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
    }
    $results.HasSSD = ($physDisks | Where-Object MediaType -eq 'SSD').Count -gt 0
    $results.HasHDD = ($physDisks | Where-Object MediaType -eq 'HDD').Count -gt 0

    if ($physDisks) {
        foreach ($pd in $physDisks) {
            Write-Info "$($pd.FriendlyName)" "$($pd.MediaType) - $($pd.HealthStatus)"
        }
    } else {
        Write-Info "Physical disk detection" "skipped (Storage module unavailable)"
    }

    # -- 1.3 TEMP FILES ANALYSIS --
    Write-Host "`n    -- Junk / Temp Files --" -ForegroundColor Cyan

    $tempPaths = @(
        "$env:TEMP",
        "$env:WINDIR\Temp",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer",
        "$env:WINDIR\SoftwareDistribution\Download",
        "$env:WINDIR\Prefetch",
        "$env:LOCALAPPDATA\CrashDumps",
        "$env:LOCALAPPDATA\Temp"
    )

    $results.TempSizeMB = 0
    $results.TempFiles  = 0
    foreach ($tp in $tempPaths) {
        if (Test-Path $tp) {
            try {
                $items = Get-ChildItem -Path $tp -Recurse -Force -File -ErrorAction SilentlyContinue
                $sizeMB = ($items | Measure-Object -Property Length -Sum).Sum / 1MB
                $results.TempSizeMB += $sizeMB
                $results.TempFiles  += $items.Count
            } catch {
                Log "[ERROR] Could not scan $tp : $_"
            }
        }
    }
    $results.TempSizeMB = [math]::Round($results.TempSizeMB, 1)

    # Recycle Bin
    $rbCount = 0
    try {
        $recycleBin = (New-Object -ComObject Shell.Application).NameSpace(0xA)
        $rbCount = $recycleBin.Items().Count
    } catch {
        Log "[ERROR] Could not query Recycle Bin: $_"
    }

    if ($results.TempSizeMB -gt 500) {
        Write-Bad  "Temp/Junk files: $($results.TempSizeMB) MB ($($results.TempFiles) files) - BLOATED"
    } elseif ($results.TempSizeMB -gt 100) {
        Write-Warn "Temp/Junk files: $($results.TempSizeMB) MB ($($results.TempFiles) files)"
    } else {
        Write-Good "Temp/Junk files: $($results.TempSizeMB) MB ($($results.TempFiles) files)"
    }
    Write-Info "Recycle Bin" "$rbCount items"

    # Windows Update cleanup size
    $wuPath = "$env:WINDIR\SoftwareDistribution\Download"
    if (Test-Path $wuPath) {
        try {
            $wuSize = [math]::Round((Get-ChildItem $wuPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)
            Write-Info "WinUpdate Cache" "$wuSize MB"
        } catch { $null = $_ }
    }

    # -- 1.4 STARTUP PROGRAMS --
    Write-Host "`n    -- Startup Programs --" -ForegroundColor Cyan

    $results.StartupItems = @()

    $regPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    )
    foreach ($rp in $regPaths) {
        if (Test-Path $rp) {
            $props = Get-ItemProperty $rp -ErrorAction SilentlyContinue
            if ($props) {
                $props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
                    $results.StartupItems += @{ Name = $_.Name; Source = "Registry"; Path = $_.Value }
                }
            }
        }
    }

    $startupFolder = [System.IO.Path]::Combine($env:APPDATA, 'Microsoft\Windows\Start Menu\Programs\Startup')
    if (Test-Path $startupFolder) {
        Get-ChildItem $startupFolder -File -ErrorAction SilentlyContinue | ForEach-Object {
            $results.StartupItems += @{ Name = $_.BaseName; Source = "StartupFolder"; Path = $_.FullName }
        }
    }

    try {
        $logonTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
            $_.State -ne 'Disabled' -and
            ($_.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' })
        }
        foreach ($lt in $logonTasks) {
            $results.StartupItems += @{ Name = $lt.TaskName; Source = "ScheduledTask"; Path = $lt.TaskPath }
        }
    } catch {
        Log "[ERROR] Could not enumerate scheduled tasks: $_"
    }

    $startupCount = $results.StartupItems.Count
    if ($startupCount -gt 15) {
        Write-Bad  "$startupCount startup items - TOO MANY (slowing boot)"
    } elseif ($startupCount -gt 8) {
        Write-Warn "$startupCount startup items - could be trimmed"
    } else {
        Write-Good "$startupCount startup items"
    }
    foreach ($si in $results.StartupItems | Select-Object -First 12) {
        Write-Host "      - $($si.Name)" -ForegroundColor DarkGray
    }
    if ($startupCount -gt 12) { Write-Host "      ... and $($startupCount - 12) more" -ForegroundColor DarkGray }

    # -- 1.5 SERVICES ANALYSIS --
    Write-Host "`n    -- Unnecessary Services Running --" -ForegroundColor Cyan

    $bloatServices = Get-BloatServiceDefinition

    # Smart filtering: keep SysMain on HDD-only systems
    if ($results.HasHDD -and -not $results.HasSSD) {
        $bloatServices = $bloatServices | Where-Object { $_.Name -ne "SysMain" }
    }

    # Context-aware: don't flag WSearch if Outlook is installed.
    # Test-Path doesn't expand wildcards in registry providers, so we walk the
    # version subkeys (15.0, 16.0, ...) and look for an Outlook child explicitly.
    $outlookInstalled = $false
    foreach ($officeRoot in @("HKLM:\SOFTWARE\Microsoft\Office", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office")) {
        if (-not (Test-Path $officeRoot)) { continue }
        $versionKeys = Get-ChildItem $officeRoot -ErrorAction SilentlyContinue
        foreach ($vk in $versionKeys) {
            if (Test-Path (Join-Path $vk.PSPath "Outlook")) {
                $outlookInstalled = $true
                break
            }
        }
        if ($outlookInstalled) { break }
    }
    if ($outlookInstalled) {
        $bloatServices = $bloatServices | Where-Object { $_.Name -ne "WSearch" }
        Write-Info "Outlook detected" "Keeping Windows Search Indexer"
    }

    # Context-aware: don't flag TabletInputService if touchscreen detected
    $hasTouchscreen = $false
    try {
        $touchDevices = Get-PnpDevice -Class 'HIDClass' -ErrorAction SilentlyContinue |
            Where-Object { $_.FriendlyName -match 'touch screen|touch digitizer' -and $_.Status -eq 'OK' }
        $hasTouchscreen = ($null -ne $touchDevices -and @($touchDevices).Count -gt 0)
    } catch { $null = $_ }
    if ($hasTouchscreen) {
        $bloatServices = $bloatServices | Where-Object { $_.Name -ne "TabletInputService" }
        Write-Info "Touchscreen detected" "Keeping Touch Keyboard service"
    }

    $results.BloatServices = $bloatServices
    $results.ServicesToDisable = @()
    foreach ($svc in $bloatServices) {
        $s = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($s -and $s.Status -eq 'Running') {
            Write-Warn "Running: $($svc.Desc) ($($svc.Name))"
            $results.ServicesToDisable += $svc
        } elseif ($s -and $s.StartType -ne 'Disabled') {
            Write-Host "      o Enabled but stopped: $($svc.Desc)" -ForegroundColor DarkGray
            $results.ServicesToDisable += $svc
        }
    }
    if ($results.ServicesToDisable.Count -eq 0) { Write-Good "No unnecessary services detected" }

    # -- 1.6 POWER PLAN --
    Write-Host "`n    -- Power Configuration --" -ForegroundColor Cyan

    $activePlan = powercfg /getactivescheme
    $results.CurrentPowerPlan = if ($activePlan -match '"([^"]+)"') { $Matches[1] } else { "Unknown" }
    Write-Info "Active Power Plan" $results.CurrentPowerPlan

    if ($results.CurrentPowerPlan -match "Balanced|Power saver") {
        Write-Warn "Not using High Performance plan - CPU may be throttled"
    } else {
        Write-Good "Performance power plan active"
    }

    # -- 1.7 VISUAL EFFECTS --
    Write-Host "`n    -- Visual Effects --" -ForegroundColor Cyan

    $veKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    $veSetting = (Get-ItemProperty -Path $veKey -Name "VisualFXSetting" -ErrorAction SilentlyContinue).VisualFXSetting

    switch ($veSetting) {
        0 { Write-Warn "Visual Effects: Let Windows decide (not optimal)"; $results.VisualEffects = "Auto" }
        1 { Write-Good "Visual Effects: Best appearance"; $results.VisualEffects = "Appearance" }
        2 { Write-Good "Visual Effects: Best performance"; $results.VisualEffects = "Performance" }
        3 { Write-Info "Visual Effects" "Custom"; $results.VisualEffects = "Custom" }
        default { Write-Info "Visual Effects" "Unknown"; $results.VisualEffects = "Unknown" }
    }

    # -- 1.8 MEMORY & PROCESS ANALYSIS --
    Write-Host "`n    -- Top Memory Consumers --" -ForegroundColor Cyan

    $topProcs = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10
    $results.MemoryHogs = @()
    foreach ($p in $topProcs) {
        $memMB = [math]::Round($p.WorkingSet64 / 1MB, 0)
        Write-Host "      $($p.ProcessName.PadRight(30)) $($memMB.ToString().PadLeft(6)) MB" -ForegroundColor DarkGray
        $results.MemoryHogs += @{ Name = $p.ProcessName; MemMB = $memMB }
    }

    if ($results.RAMUsedPct -gt 85) {
        Write-Bad "RAM usage is at $($results.RAMUsedPct)% - system under memory pressure"
    } elseif ($results.RAMUsedPct -gt 70) {
        Write-Warn "RAM usage is at $($results.RAMUsedPct)%"
    } else {
        Write-Good "RAM usage is healthy at $($results.RAMUsedPct)%"
    }

    # -- 1.9 NETWORK ANALYSIS --
    Write-Host "`n    -- Network Configuration --" -ForegroundColor Cyan

    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up'
    foreach ($a in $adapters) {
        Write-Info "$($a.Name)" "$($a.LinkSpeed) - $($a.InterfaceDescription)"
    }

    $dnsServers = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object ServerAddresses).ServerAddresses | Select-Object -Unique
    $results.CurrentDNS = $dnsServers -join ", "
    Write-Info "DNS Servers" $results.CurrentDNS

    $nagle = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\*" -Name TcpNoDelay -ErrorAction SilentlyContinue
    if (-not $nagle) {
        Write-Warn "Nagle's algorithm is enabled (adds network latency)"
    } else {
        Write-Good "Nagle's algorithm optimized"
    }

    # -- 1.10 SECURITY & PRIVACY --
    Write-Host "`n    -- Privacy & Telemetry --" -ForegroundColor Cyan

    $telemetry = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name AllowTelemetry -ErrorAction SilentlyContinue).AllowTelemetry
    $results.TelemetryEnabled = ($telemetry -ne 0)
    if ($telemetry -eq 0) {
        Write-Good "Telemetry is disabled"
    } else {
        Write-Warn "Telemetry is sending data to Microsoft"
    }

    $cortana = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name AllowCortana -ErrorAction SilentlyContinue).AllowCortana
    $results.CortanaEnabled = ($cortana -ne 0)
    if ($cortana -eq 0) {
        Write-Good "Cortana is disabled"
    } else {
        Write-Warn "Cortana is enabled"
    }

    $adID = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name Enabled -ErrorAction SilentlyContinue).Enabled
    $results.AdIDEnabled = ($adID -ne 0)
    if ($adID -eq 0) {
        Write-Good "Advertising ID is disabled"
    } else {
        Write-Warn "Advertising ID is tracking you"
    }

    # -- 1.11 WINDOWS UPDATE --
    Write-Host "`n    -- Windows Update Status --" -ForegroundColor Cyan

    try {
        $lastUpdate = (Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1).InstalledOn
        $daysSince  = [math]::Round(((Get-Date) - $lastUpdate).TotalDays, 0)
        Write-Info "Last Update" "$lastUpdate ($daysSince days ago)"
        if ($daysSince -gt 30) { Write-Warn "System hasn't been updated in $daysSince days" }
    } catch {
        Write-Info "Last Update" "Unable to determine"
    }

    # -- SCORE DISPLAY --
    $score = Get-HealthScore -AnalysisResults $results
    $scoreColor = if ($score -ge 80) { "Green" } elseif ($score -ge 60) { "Yellow" } else { "Red" }
    $scoreBar = ("#" * [math]::Floor($score / 5)).PadRight(20, "-")

    Write-Host "`n    -- System Health Score --" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "       [$scoreBar] " -NoNewline -ForegroundColor $scoreColor
    Write-Host "$score/100" -ForegroundColor $scoreColor
    Write-Host ""

    Log "System Health Score: $score/100"

    return $results
}

function Get-HealthScore {
    param(
        [hashtable]$AnalysisResults
    )

    $score = 100

    if ($AnalysisResults.RAMUsedPct -gt 85)      { $score -= 15 }
    elseif ($AnalysisResults.RAMUsedPct -gt 70)  { $score -= 5 }

    $startupCount = $AnalysisResults.StartupItems.Count
    if ($startupCount -gt 15)           { $score -= 15 }
    elseif ($startupCount -gt 8)        { $score -= 8 }

    if ($AnalysisResults.TempSizeMB -gt 500)     { $score -= 10 }
    elseif ($AnalysisResults.TempSizeMB -gt 100) { $score -= 5 }

    if ($AnalysisResults.ServicesToDisable.Count -gt 5) { $score -= 10 }
    elseif ($AnalysisResults.ServicesToDisable.Count -gt 0) { $score -= 5 }

    if ($AnalysisResults.TelemetryEnabled)       { $score -= 5 }

    # Balanced is the recommended plan on laptops (battery life, thermals);
    # only penalise non-performance plans on desktops.
    if (-not $AnalysisResults.IsLaptop -and $AnalysisResults.CurrentPowerPlan -match "Balanced|Power saver") {
        $score -= 10
    }

    foreach ($d in $AnalysisResults.Disks) {
        if ($d.Health -eq "CRITICAL") { $score -= 15 }
        elseif ($d.Health -eq "WARNING") { $score -= 8 }
    }

    if ($AnalysisResults.VisualEffects -eq "Auto") { $score -= 5 }

    return [math]::Max(0, [math]::Min(100, $score))
}

Export-ModuleMember -Function Get-SystemAnalysis, Get-HealthScore
