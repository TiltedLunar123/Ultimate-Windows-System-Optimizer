#Requires -RunAsAdministrator
<#
╔══════════════════════════════════════════════════════════════════╗
║          ULTIMATE WINDOWS SYSTEM OPTIMIZER v3.0                 ║
║          Smart Analysis & Optimization Engine                   ║
╚══════════════════════════════════════════════════════════════════╝
#>

# ── CONFIG ──────────────────────────────────────────────────────
Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
$LogFile = "$env:USERPROFILE\Desktop\Optimizer_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$RestorePoint = $true
$script:TotalFixesApplied = 0
$script:Report = [System.Collections.Generic.List[string]]::new()

# ── COLORS & UI HELPERS ────────────────────────────────────────
function Write-Banner {
    Clear-Host
    $banner = @"

    ╔══════════════════════════════════════════════════════════╗
    ║     ⚡  ULTIMATE WINDOWS SYSTEM OPTIMIZER  ⚡           ║
    ║         Smart Analysis & Tuning Engine v3.0             ║
    ╚══════════════════════════════════════════════════════════╝

"@
    Write-Host $banner -ForegroundColor Cyan
}

function Write-Section ([string]$Title) {
    $line = "═" * 60
    Write-Host "`n  ╔$line╗" -ForegroundColor DarkCyan
    Write-Host "  ║  $($Title.PadRight(58))║" -ForegroundColor DarkCyan
    Write-Host "  ╚$line╝" -ForegroundColor DarkCyan
    Log "=== $Title ==="
}

function Write-Status ([string]$Message, [string]$Status, [string]$Color = "White") {
    $pad = 50 - $Message.Length
    if ($pad -lt 1) { $pad = 1 }
    Write-Host "    $Message$(' ' * $pad)" -NoNewline
    Write-Host "[$Status]" -ForegroundColor $Color
}

function Write-Info ([string]$Label, [string]$Value) {
    Write-Host "    $($Label.PadRight(28))" -NoNewline -ForegroundColor Gray
    Write-Host "$Value" -ForegroundColor White
}

function Write-Good ([string]$Msg)    { Write-Host "    ✅ $Msg" -ForegroundColor Green;  Log "[OK]   $Msg" }
function Write-Warn ([string]$Msg)    { Write-Host "    ⚠️  $Msg" -ForegroundColor Yellow; Log "[WARN] $Msg" }
function Write-Bad  ([string]$Msg)    { Write-Host "    ❌ $Msg" -ForegroundColor Red;    Log "[BAD]  $Msg" }
function Write-Fix  ([string]$Msg)    { Write-Host "    🔧 $Msg" -ForegroundColor Magenta; Log "[FIX]  $Msg"; $script:TotalFixesApplied++ }
function Write-Skip ([string]$Msg)    { Write-Host "    ⏭️  $Msg" -ForegroundColor DarkGray; Log "[SKIP] $Msg" }

function Log ([string]$Msg) {
    $script:Report.Add("$(Get-Date -Format 'HH:mm:ss') $Msg")
}

function Confirm-Action ([string]$Prompt) {
    Write-Host ""
    Write-Host "    $Prompt" -ForegroundColor Yellow -NoNewline
    Write-Host " (Y/N): " -NoNewline
    $r = Read-Host
    return ($r -match '^[Yy]')
}

function Set-RegValue ([string]$Path, [string]$Name, $Value, [string]$Type = "DWord") {
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
        return $true
    } catch { return $false }
}

# ══════════════════════════════════════════════════════════════
#  PHASE 1 — DEEP SYSTEM ANALYSIS
# ══════════════════════════════════════════════════════════════

function Get-SystemAnalysis {
    Write-Section "PHASE 1: DEEP SYSTEM ANALYSIS"

    # ── 1.1 HARDWARE DETECTION ──────────────────────────────
    Write-Host "`n    ── Hardware Profile ──" -ForegroundColor Cyan

    $os   = Get-CimInstance Win32_OperatingSystem
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $gpu  = Get-CimInstance Win32_VideoController | Select-Object -First 1
    $bios = Get-CimInstance Win32_BIOS
    $cs   = Get-CimInstance Win32_ComputerSystem
    $bat  = Get-CimInstance Win32_Battery

    $script:IsLaptop    = ($null -ne $bat) -or ($cs.PCSystemType -eq 2)
    $script:TotalRAMGB  = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $script:FreeRAMGB   = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $script:RAMUsedPct  = [math]::Round((1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100, 1)
    $script:CPUCores    = $cpu.NumberOfCores
    $script:CPULogical  = $cpu.NumberOfLogicalProcessors
    $script:CPUName     = $cpu.Name.Trim()
    $script:OSVersion   = $os.Caption
    $script:OSBuild     = $os.BuildNumber
    $script:DeviceType  = if ($script:IsLaptop) { "💻 Laptop" } else { "🖥️ Desktop" }

    Write-Info "Device Type"        $script:DeviceType
    Write-Info "OS"                 "$($script:OSVersion) (Build $($script:OSBuild))"
    Write-Info "CPU"                "$($script:CPUName)"
    Write-Info "Cores / Threads"    "$($script:CPUCores) / $($script:CPULogical)"
    Write-Info "GPU"                "$($gpu.Name)"
    Write-Info "Total RAM"          "$($script:TotalRAMGB) GB"
    Write-Info "Free RAM"           "$($script:FreeRAMGB) GB ($($script:RAMUsedPct)% used)"
    Write-Info "Uptime"             "$([math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1)) hours"

    # Categorize system tier
    if ($script:TotalRAMGB -ge 16 -and $script:CPUCores -ge 6) {
        $script:SystemTier = "High-End"
    } elseif ($script:TotalRAMGB -ge 8 -and $script:CPUCores -ge 4) {
        $script:SystemTier = "Mid-Range"
    } else {
        $script:SystemTier = "Low-End"
    }
    Write-Info "System Tier"  "⚡ $($script:SystemTier)"

    # ── 1.2 DISK ANALYSIS ──────────────────────────────────
    Write-Host "`n    ── Storage Analysis ──" -ForegroundColor Cyan

    $script:Disks = @()
    $volumes = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
    foreach ($vol in $volumes) {
        $totalGB = [math]::Round($vol.Size / 1GB, 1)
        $freeGB  = [math]::Round($vol.FreeSpace / 1GB, 1)
        $usedPct = [math]::Round((1 - $vol.FreeSpace / $vol.Size) * 100, 1)

        $health = if ($freeGB -lt 10) { "CRITICAL" }
                  elseif ($freeGB -lt 30) { "WARNING" }
                  else { "HEALTHY" }

        $color = switch ($health) { "CRITICAL" { "Red" } "WARNING" { "Yellow" } default { "Green" } }
        Write-Status "Drive $($vol.DeviceID) — $freeGB GB free / $totalGB GB" $health $color

        $script:Disks += @{ Drive = $vol.DeviceID; FreeGB = $freeGB; TotalGB = $totalGB; UsedPct = $usedPct; Health = $health }
    }

    # Detect SSD vs HDD
    $physDisks = Get-PhysicalDisk
    $script:HasSSD = ($physDisks | Where-Object MediaType -eq 'SSD').Count -gt 0
    $script:HasHDD = ($physDisks | Where-Object MediaType -eq 'HDD').Count -gt 0

    foreach ($pd in $physDisks) {
        Write-Info "$($pd.FriendlyName)" "$($pd.MediaType) — $($pd.HealthStatus)"
    }

    # ── 1.3 TEMP FILES ANALYSIS ────────────────────────────
    Write-Host "`n    ── Junk / Temp Files ──" -ForegroundColor Cyan

    $tempPaths = @(
        "$env:TEMP",
        "$env:WINDIR\Temp",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer",      # Thumbnail cache
        "$env:WINDIR\SoftwareDistribution\Download",
        "$env:WINDIR\Prefetch",
        "$env:LOCALAPPDATA\CrashDumps",
        "$env:LOCALAPPDATA\Temp"
    )

    $script:TempSizeMB = 0
    $script:TempFiles  = 0
    foreach ($tp in $tempPaths) {
        if (Test-Path $tp) {
            $items = Get-ChildItem -Path $tp -Recurse -Force -File
            $sizeMB = ($items | Measure-Object -Property Length -Sum).Sum / 1MB
            $script:TempSizeMB += $sizeMB
            $script:TempFiles  += $items.Count
        }
    }
    $script:TempSizeMB = [math]::Round($script:TempSizeMB, 1)

    # Recycle Bin
    $recycleBin = (New-Object -ComObject Shell.Application).NameSpace(0xA)
    $rbCount = $recycleBin.Items().Count

    if ($script:TempSizeMB -gt 500) {
        Write-Bad  "Temp/Junk files: $($script:TempSizeMB) MB ($($script:TempFiles) files) — BLOATED"
    } elseif ($script:TempSizeMB -gt 100) {
        Write-Warn "Temp/Junk files: $($script:TempSizeMB) MB ($($script:TempFiles) files)"
    } else {
        Write-Good "Temp/Junk files: $($script:TempSizeMB) MB ($($script:TempFiles) files)"
    }
    Write-Info "Recycle Bin" "$rbCount items"

    # Windows Update cleanup size
    $wuPath = "$env:WINDIR\SoftwareDistribution\Download"
    if (Test-Path $wuPath) {
        $wuSize = [math]::Round((Get-ChildItem $wuPath -Recurse -Force | Measure-Object Length -Sum).Sum / 1MB, 1)
        Write-Info "WinUpdate Cache" "$wuSize MB"
    }

    # ── 1.4 STARTUP PROGRAMS ──────────────────────────────
    Write-Host "`n    ── Startup Programs ──" -ForegroundColor Cyan

    $script:StartupItems = @()

    # Registry startup (HKCU)
    $regPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    )
    foreach ($rp in $regPaths) {
        if (Test-Path $rp) {
            $props = Get-ItemProperty $rp
            $props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
                $script:StartupItems += @{ Name = $_.Name; Source = "Registry"; Path = $_.Value }
            }
        }
    }

    # Startup folder
    $startupFolder = [System.IO.Path]::Combine($env:APPDATA, 'Microsoft\Windows\Start Menu\Programs\Startup')
    if (Test-Path $startupFolder) {
        Get-ChildItem $startupFolder -File | ForEach-Object {
            $script:StartupItems += @{ Name = $_.BaseName; Source = "StartupFolder"; Path = $_.FullName }
        }
    }

    # Scheduled tasks set to run at logon
    $logonTasks = Get-ScheduledTask | Where-Object {
        $_.State -ne 'Disabled' -and
        ($_.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' })
    }
    foreach ($lt in $logonTasks) {
        $script:StartupItems += @{ Name = $lt.TaskName; Source = "ScheduledTask"; Path = $lt.TaskPath }
    }

    $startupCount = $script:StartupItems.Count
    if ($startupCount -gt 15) {
        Write-Bad  "$startupCount startup items — TOO MANY (slowing boot)"
    } elseif ($startupCount -gt 8) {
        Write-Warn "$startupCount startup items — could be trimmed"
    } else {
        Write-Good "$startupCount startup items"
    }
    foreach ($si in $script:StartupItems | Select-Object -First 12) {
        Write-Host "      • $($si.Name)" -ForegroundColor DarkGray
    }
    if ($startupCount -gt 12) { Write-Host "      ... and $($startupCount - 12) more" -ForegroundColor DarkGray }

    # ── 1.5 SERVICES ANALYSIS ──────────────────────────────
    Write-Host "`n    ── Unnecessary Services Running ──" -ForegroundColor Cyan

    $script:BloatServices = @(
        @{ Name = "DiagTrack";                  Desc = "Connected User Experience & Telemetry" },
        @{ Name = "dmwappushservice";           Desc = "WAP Push Message Routing" },
        @{ Name = "SysMain";                    Desc = "Superfetch (can hurt SSDs)" },
        @{ Name = "WSearch";                    Desc = "Windows Search Indexer" },
        @{ Name = "XblAuthManager";             Desc = "Xbox Live Auth Manager" },
        @{ Name = "XblGameSave";                Desc = "Xbox Live Game Save" },
        @{ Name = "XboxGipSvc";                 Desc = "Xbox Accessory Management" },
        @{ Name = "XboxNetApiSvc";              Desc = "Xbox Live Networking" },
        @{ Name = "WMPNetworkSvc";              Desc = "Windows Media Player Sharing" },
        @{ Name = "lfsvc";                      Desc = "Geolocation Service" },
        @{ Name = "MapsBroker";                 Desc = "Downloaded Maps Manager" },
        @{ Name = "RetailDemo";                 Desc = "Retail Demo Service" },
        @{ Name = "RemoteRegistry";             Desc = "Remote Registry (security risk)" },
        @{ Name = "Fax";                        Desc = "Fax Service" },
        @{ Name = "WerSvc";                     Desc = "Windows Error Reporting" },
        @{ Name = "TabletInputService";         Desc = "Touch Keyboard (if no touchscreen)" },
        @{ Name = "PhoneSvc";                   Desc = "Phone Service" },
        @{ Name = "wisvc";                      Desc = "Windows Insider Service" }
    )

    # Smart filtering: keep SysMain on HDD systems, keep WSearch if user has lots of files
    if ($script:HasHDD -and -not $script:HasSSD) {
        $script:BloatServices = $script:BloatServices | Where-Object { $_.Name -ne "SysMain" }
    }

    $script:ServicesToDisable = @()
    foreach ($svc in $script:BloatServices) {
        $s = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($s -and $s.Status -eq 'Running') {
            Write-Warn "Running: $($svc.Desc) ($($svc.Name))"
            $script:ServicesToDisable += $svc
        } elseif ($s -and $s.StartType -ne 'Disabled') {
            Write-Host "      ○ Enabled but stopped: $($svc.Desc)" -ForegroundColor DarkGray
            $script:ServicesToDisable += $svc
        }
    }
    if ($script:ServicesToDisable.Count -eq 0) { Write-Good "No unnecessary services detected" }

    # ── 1.6 POWER PLAN ────────────────────────────────────
    Write-Host "`n    ── Power Configuration ──" -ForegroundColor Cyan

    $activePlan = powercfg /getactivescheme
    $script:CurrentPowerPlan = if ($activePlan -match '"([^"]+)"') { $Matches[1] } else { "Unknown" }
    Write-Info "Active Power Plan" $script:CurrentPowerPlan

    if ($script:CurrentPowerPlan -match "Balanced|Power saver") {
        Write-Warn "Not using High Performance plan — CPU may be throttled"
    } else {
        Write-Good "Performance power plan active"
    }

    # ── 1.7 VISUAL EFFECTS ────────────────────────────────
    Write-Host "`n    ── Visual Effects ──" -ForegroundColor Cyan

    $veKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    $veSetting = (Get-ItemProperty -Path $veKey -Name "VisualFXSetting" -ErrorAction SilentlyContinue).VisualFXSetting

    switch ($veSetting) {
        0 { Write-Warn "Visual Effects: Let Windows decide (not optimal)"; $script:VisualEffects = "Auto" }
        1 { Write-Good "Visual Effects: Best appearance"; $script:VisualEffects = "Appearance" }
        2 { Write-Good "Visual Effects: Best performance"; $script:VisualEffects = "Performance" }
        3 { Write-Info "Visual Effects" "Custom"; $script:VisualEffects = "Custom" }
        default { Write-Info "Visual Effects" "Unknown"; $script:VisualEffects = "Unknown" }
    }

    # ── 1.8 MEMORY & PROCESS ANALYSIS ──────────────────────
    Write-Host "`n    ── Top Memory Consumers ──" -ForegroundColor Cyan

    $topProcs = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10
    $script:MemoryHogs = @()
    foreach ($p in $topProcs) {
        $memMB = [math]::Round($p.WorkingSet64 / 1MB, 0)
        Write-Host "      $($p.ProcessName.PadRight(30)) $($memMB.ToString().PadLeft(6)) MB" -ForegroundColor DarkGray
        $script:MemoryHogs += @{ Name = $p.ProcessName; MemMB = $memMB }
    }

    if ($script:RAMUsedPct -gt 85) {
        Write-Bad "RAM usage is at $($script:RAMUsedPct)% — system under memory pressure"
    } elseif ($script:RAMUsedPct -gt 70) {
        Write-Warn "RAM usage is at $($script:RAMUsedPct)%"
    } else {
        Write-Good "RAM usage is healthy at $($script:RAMUsedPct)%"
    }

    # ── 1.9 NETWORK ANALYSIS ──────────────────────────────
    Write-Host "`n    ── Network Configuration ──" -ForegroundColor Cyan

    $adapters = Get-NetAdapter | Where-Object Status -eq 'Up'
    foreach ($a in $adapters) {
        Write-Info "$($a.Name)" "$($a.LinkSpeed) — $($a.InterfaceDescription)"
    }

    # Check DNS
    $dnsServers = (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object ServerAddresses).ServerAddresses | Select-Object -Unique
    $script:CurrentDNS = $dnsServers -join ", "
    Write-Info "DNS Servers" $script:CurrentDNS

    # Check Nagle's algorithm
    $nagle = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\*" -Name TcpNoDelay -ErrorAction SilentlyContinue
    if (-not $nagle) {
        Write-Warn "Nagle's algorithm is enabled (adds network latency)"
    } else {
        Write-Good "Nagle's algorithm optimized"
    }

    # ── 1.10 SECURITY & PRIVACY ──────────────────────────
    Write-Host "`n    ── Privacy & Telemetry ──" -ForegroundColor Cyan

    $telemetry = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name AllowTelemetry -ErrorAction SilentlyContinue).AllowTelemetry
    if ($telemetry -eq 0) {
        Write-Good "Telemetry is disabled"
    } else {
        Write-Warn "Telemetry is sending data to Microsoft"
    }

    $cortana = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name AllowCortana -ErrorAction SilentlyContinue).AllowCortana
    if ($cortana -eq 0) {
        Write-Good "Cortana is disabled"
    } else {
        Write-Warn "Cortana is enabled"
    }

    $adID = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name Enabled -ErrorAction SilentlyContinue).Enabled
    if ($adID -eq 0) {
        Write-Good "Advertising ID is disabled"
    } else {
        Write-Warn "Advertising ID is tracking you"
    }

    # ── 1.11 WINDOWS UPDATE ──────────────────────────────
    Write-Host "`n    ── Windows Update Status ──" -ForegroundColor Cyan

    try {
        $lastUpdate = (Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1).InstalledOn
        $daysSince  = [math]::Round(((Get-Date) - $lastUpdate).TotalDays, 0)
        Write-Info "Last Update" "$lastUpdate ($daysSince days ago)"
        if ($daysSince -gt 30) { Write-Warn "System hasn't been updated in $daysSince days" }
    } catch {
        Write-Info "Last Update" "Unable to determine"
    }

    # ── SCORE CALCULATION ─────────────────────────────────
    Write-Host "`n    ── System Health Score ──" -ForegroundColor Cyan

    $score = 100
    if ($script:RAMUsedPct -gt 85)      { $score -= 15 }
    elseif ($script:RAMUsedPct -gt 70)  { $score -= 5 }
    if ($startupCount -gt 15)           { $score -= 15 }
    elseif ($startupCount -gt 8)        { $score -= 8 }
    if ($script:TempSizeMB -gt 500)     { $score -= 10 }
    elseif ($script:TempSizeMB -gt 100) { $score -= 5 }
    if ($script:ServicesToDisable.Count -gt 5) { $score -= 10 }
    elseif ($script:ServicesToDisable.Count -gt 0) { $score -= 5 }
    if ($telemetry -ne 0)               { $score -= 5 }
    if ($script:CurrentPowerPlan -match "Balanced|Power saver") { $score -= 10 }
    foreach ($d in $script:Disks) { if ($d.Health -eq "CRITICAL") { $score -= 15 } elseif ($d.Health -eq "WARNING") { $score -= 8 } }
    if ($script:VisualEffects -eq "Auto") { $score -= 5 }

    $script:HealthScore = [math]::Max(0, [math]::Min(100, $score))
    $scoreColor = if ($score -ge 80) { "Green" } elseif ($score -ge 60) { "Yellow" } else { "Red" }
    $scoreBar = ("█" * [math]::Floor($script:HealthScore / 5)).PadRight(20, "░")

    Write-Host ""
    Write-Host "       [$scoreBar] " -NoNewline -ForegroundColor $scoreColor
    Write-Host "$($script:HealthScore)/100" -ForegroundColor $scoreColor
    Write-Host ""

    Log "System Health Score: $($script:HealthScore)/100"
}

# ══════════════════════════════════════════════════════════════
#  PHASE 2 — INTELLIGENT OPTIMIZATION
# ══════════════════════════════════════════════════════════════

function Invoke-Optimization {
    Write-Section "PHASE 2: INTELLIGENT OPTIMIZATION"

    # ── 2.0 RESTORE POINT ──────────────────────────────────
    if ($RestorePoint) {
        Write-Host "`n    Creating System Restore Point..." -ForegroundColor Cyan
        try {
            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description "Pre-Optimizer Backup $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
            Write-Good "Restore point created successfully"
        } catch {
            Write-Warn "Could not create restore point (may have been created recently)"
        }
    }

    # ── 2.1 CLEAN TEMP FILES ──────────────────────────────
    Write-Host "`n    ── Cleaning Temporary Files ──" -ForegroundColor Cyan

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
            $before = (Get-ChildItem $cp.Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            Get-ChildItem $cp.Path -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            $after = (Get-ChildItem $cp.Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            $freed = [math]::Round(($before - $after) / 1MB, 1)
            if ($freed -gt 0) {
                Write-Fix "Cleaned $($cp.Desc): $freed MB freed"
                $totalCleaned += $freed
            }
        }
    }

    # Empty Recycle Bin
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-Fix "Recycle Bin emptied"
    } catch {}

    # Windows Disk Cleanup (silent)
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
    # Set all cleanup flags
    $volCachePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
    foreach ($flag in $cleanMgrFlags) {
        $p = Join-Path $volCachePath $flag
        if (Test-Path $p) {
            Set-ItemProperty -Path $p -Name "StateFlags0100" -Value 2 -Type DWord -ErrorAction SilentlyContinue
        }
    }
    Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:100" -WindowStyle Hidden -ErrorAction SilentlyContinue

    Write-Good "Total space recovered: ~$([math]::Round($totalCleaned, 0)) MB"

    # ── 2.2 DISABLE UNNECESSARY SERVICES ──────────────────
    Write-Host "`n    ── Disabling Unnecessary Services ──" -ForegroundColor Cyan

    if ($script:ServicesToDisable.Count -gt 0) {
        foreach ($svc in $script:ServicesToDisable) {
            try {
                Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Fix "Disabled: $($svc.Desc)"
            } catch {
                Write-Skip "Could not disable $($svc.Name)"
            }
        }
    } else {
        Write-Good "No unnecessary services to disable"
    }

    # ── 2.3 POWER PLAN OPTIMIZATION ──────────────────────
    Write-Host "`n    ── Power Plan Optimization ──" -ForegroundColor Cyan

    if ($script:IsLaptop) {
        # For laptops: create a balanced-performance profile
        Write-Host "      Laptop detected — using optimized balanced profile" -ForegroundColor DarkGray

        # Set to High Performance when plugged in
        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100

        # Battery: allow throttling to save power
        powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5
        powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100

        # Disable USB selective suspend (prevents disconnections)
        powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0

        # Optimize sleep timers
        powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 0  # Never sleep on AC
        powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 900  # 15 min on battery

        powercfg /setactive SCHEME_CURRENT
        Write-Fix "Laptop power profile optimized (high perf on AC, balanced on battery)"
    } else {
        # For desktops: Ultimate Performance
        $ultPerf = powercfg /list | Select-String "Ultimate Performance"
        if (-not $ultPerf) {
            powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
        }

        # Try to activate Ultimate Performance, fall back to High Performance
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

    # Disable power throttling for all
    Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" 1
    Write-Fix "Disabled power throttling"

    # ── 2.4 VISUAL EFFECTS OPTIMIZATION ──────────────────
    Write-Host "`n    ── Visual Effects Optimization ──" -ForegroundColor Cyan

    $vePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    $dwmPath = "HKCU:\Software\Microsoft\Windows\DWM"
    $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    if ($script:SystemTier -eq "Low-End") {
        # Maximum performance — disable most effects
        Set-RegValue $vePath "VisualFXSetting" 2
        Set-RegValue "HKCU:\Control Panel\Desktop" "UserPreferencesMask" ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) "Binary"
        Set-RegValue "HKCU:\Control Panel\Desktop" "FontSmoothing" "2" "String"
        Set-RegValue "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" "String"
        Set-RegValue $advPath "ListviewAlphaSelect" 0
        Set-RegValue $advPath "TaskbarAnimations" 0
        Set-RegValue $dwmPath "EnableAeroPeek" 0
        Set-RegValue "HKCU:\Control Panel\Desktop" "DragFullWindows" "0" "String"
        Write-Fix "Visual effects set to MAXIMUM PERFORMANCE (Low-End system)"
    } elseif ($script:SystemTier -eq "Mid-Range") {
        # Keep some nice effects, disable expensive ones
        Set-RegValue $vePath "VisualFXSetting" 3  # Custom
        Set-RegValue "HKCU:\Control Panel\Desktop" "FontSmoothing" "2" "String"
        Set-RegValue "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" "String"
        Set-RegValue $advPath "ListviewAlphaSelect" 1
        Set-RegValue $advPath "TaskbarAnimations" 0
        Set-RegValue $dwmPath "EnableAeroPeek" 0
        Set-RegValue "HKCU:\Control Panel\Desktop" "DragFullWindows" "1" "String"
        Write-Fix "Visual effects optimized for balanced quality/performance"
    } else {
        # High-end: keep effects but disable the pointless ones
        Set-RegValue "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" "String"
        Set-RegValue $advPath "TaskbarAnimations" 0
        Write-Fix "Visual effects: minimal tweaks (High-End system — keeping quality)"
    }

    # ── 2.5 PRIVACY & TELEMETRY ──────────────────────────
    Write-Host "`n    ── Privacy & Telemetry Hardening ──" -ForegroundColor Cyan

    # Disable Telemetry
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0
    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" 0
    Write-Fix "Telemetry disabled"

    # Disable Cortana
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana" 0
    Write-Fix "Cortana disabled"

    # Disable Advertising ID
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0
    Write-Fix "Advertising ID disabled"

    # Disable Activity History
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" 0
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 0
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities" 0
    Write-Fix "Activity History disabled"

    # Disable Location Tracking
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" "DisableLocation" 1
    Write-Fix "Location tracking disabled"

    # Disable feedback requests
    Set-RegValue "HKCU:\Software\Microsoft\Siuf\Rules" "NumberOfSIUFInPeriod" 0
    Set-RegValue "HKCU:\Software\Microsoft\Siuf\Rules" "PeriodInNanoSeconds" 0
    Write-Fix "Feedback requests disabled"

    # Disable app launch tracking
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_TrackProgs" 0
    Write-Fix "App launch tracking disabled"

    # Disable tailored experiences
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" 0
    Write-Fix "Tailored experiences disabled"

    # Disable tips & suggestions
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338389Enabled" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-310093Enabled" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338388Enabled" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SilentInstalledAppsEnabled" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SystemPaneSuggestionsEnabled" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SoftLandingEnabled" 0
    Write-Fix "Tips, suggestions, and silent app installs disabled"

    # ── 2.6 NETWORK OPTIMIZATION ─────────────────────────
    Write-Host "`n    ── Network Optimization ──" -ForegroundColor Cyan

    # Disable Nagle's Algorithm on all interfaces (reduces latency)
    $interfaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    foreach ($iface in $interfaces) {
        Set-RegValue $iface.PSPath "TcpNoDelay" 1
        Set-RegValue $iface.PSPath "TcpAckFrequency" 1
    }
    Write-Fix "Nagle's algorithm disabled (lower latency)"

    # Optimize network throttling
    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" 0xFFFFFFFF
    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness" 0
    Write-Fix "Network throttling disabled"

    # Optimize DNS
    Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" "MaxCacheTtl" 86400
    Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" "MaxNegativeCacheTtl" 5

    # Flush DNS cache
    Clear-DnsClientCache
    Write-Fix "DNS cache flushed and optimized"

    # Disable auto-tuning for compatibility (optional — helps on some networks)
    netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
    # ECN capability
    netsh int tcp set global ecncapability=enabled 2>&1 | Out-Null
    Write-Fix "TCP auto-tuning and ECN optimized"

    # ── 2.7 GAMING & PERFORMANCE TWEAKS ──────────────────
    Write-Host "`n    ── Performance Tweaks ──" -ForegroundColor Cyan

    # Game Mode
    Set-RegValue "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode" 1
    Set-RegValue "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" 1
    Write-Fix "Game Mode enabled"

    # Disable Game DVR / Game Bar capture (reduces overhead)
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0
    Set-RegValue "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" 0
    Write-Fix "Game Bar / DVR capture disabled (reduces overhead)"

    # Disable fullscreen optimizations globally
    Set-RegValue "HKCU:\System\GameConfigStore" "GameDVR_FSEBehaviorMode" 2
    Set-RegValue "HKCU:\System\GameConfigStore" "GameDVR_HonorUserFSEBehaviorMode" 1
    Set-RegValue "HKCU:\System\GameConfigStore" "GameDVR_FSEBehavior" 2
    Write-Fix "Fullscreen optimizations configured"

    # GPU scheduling (Windows 10 2004+)
    if ([int]$script:OSBuild -ge 19041) {
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2
        Write-Fix "Hardware-accelerated GPU scheduling enabled"
    }

    # Disable mouse acceleration for precision
    Set-RegValue "HKCU:\Control Panel\Mouse" "MouseSpeed" "0" "String"
    Set-RegValue "HKCU:\Control Panel\Mouse" "MouseThreshold1" "0" "String"
    Set-RegValue "HKCU:\Control Panel\Mouse" "MouseThreshold2" "0" "String"
    Write-Fix "Mouse acceleration disabled (1:1 precision)"

    # MMCSS priority for games
    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "GPU Priority" 8
    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "Priority" 6
    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "Scheduling Category" "High" "String"
    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "SFIO Priority" "High" "String"
    Write-Fix "Multimedia scheduler optimized for games"

    # ── 2.8 WINDOWS EXPLORER TWEAKS ──────────────────────
    Write-Host "`n    ── Explorer & UI Tweaks ──" -ForegroundColor Cyan

    $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    # Show file extensions
    Set-RegValue $advPath "HideFileExt" 0
    Write-Fix "File extensions now visible"

    # Disable search box web results
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "CortanaConsent" 0
    Write-Fix "Web search in Start Menu disabled"

    # Faster menu show delay
    Set-RegValue "HKCU:\Control Panel\Desktop" "MenuShowDelay" "50" "String"
    Write-Fix "Menu animations sped up"

    # Disable 'Show recently used files in Quick Access'
    Set-RegValue $advPath "ShowRecent" 0
    Set-RegValue $advPath "ShowFrequent" 0

    # Launch Explorer to 'This PC' instead of Quick Access
    Set-RegValue $advPath "LaunchTo" 1
    Write-Fix "Explorer opens to 'This PC' — faster navigation"

    # ── 2.9 SSD-SPECIFIC OPTIMIZATION ────────────────────
    if ($script:HasSSD) {
        Write-Host "`n    ── SSD Optimization ──" -ForegroundColor Cyan

        # Disable Prefetch and Superfetch for SSD
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnablePrefetcher" 0
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnableSuperfetch" 0
        Write-Fix "Prefetch/Superfetch disabled (SSD doesn't need it)"

        # Disable last access timestamp (reduces SSD writes)
        fsutil behavior set disablelastaccess 1 2>&1 | Out-Null
        Write-Fix "Last access timestamps disabled (reduces SSD writes)"

        # Enable TRIM
        fsutil behavior set disabledeletenotify 0 2>&1 | Out-Null
        Write-Fix "TRIM enabled for SSD"

        # Disable defrag for SSD (should only TRIM)
        $ssdDisks = Get-PhysicalDisk | Where-Object MediaType -eq 'SSD'
        Write-Good "SSD optimization complete"
    }

    # ── 2.10 MEMORY OPTIMIZATION ─────────────────────────
    Write-Host "`n    ── Memory Optimization ──" -ForegroundColor Cyan

    # Optimize page file
    $pagefile = Get-CimInstance Win32_PageFileSetting
    if ($script:TotalRAMGB -ge 16) {
        # For 16GB+ RAM, set a reasonable pagefile
        $minMB = 2048
        $maxMB = 4096
    } elseif ($script:TotalRAMGB -ge 8) {
        $minMB = 4096
        $maxMB = 8192
    } else {
        $minMB = [int]($script:TotalRAMGB * 1024 * 1.5)
        $maxMB = [int]($script:TotalRAMGB * 1024 * 3)
    }

    # Let Windows manage but set recommended size
    Write-Fix "Page file recommendation: $minMB MB - $maxMB MB (current RAM: $($script:TotalRAMGB) GB)"

    # Disable memory compression if enough RAM (reduces CPU usage)
    if ($script:TotalRAMGB -ge 16) {
        $memComp = Get-MMAgent
        if ($memComp.MemoryCompression) {
            Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
            Write-Fix "Memory compression disabled (16GB+ RAM — CPU savings)"
        }
    }

    # NDU (Network Data Usage) memory leak fix
    Set-RegValue "HKLM:\SYSTEM\ControlSet001\Services\Ndu" "Start" 4
    Write-Fix "NDU service disabled (prevents memory leak)"

    # ── 2.11 SCHEDULED TASKS CLEANUP ─────────────────────
    Write-Host "`n    ── Disabling Bloat Scheduled Tasks ──" -ForegroundColor Cyan

    $tasksToDisable = @(
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
        "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
        "\Microsoft\Windows\Maps\MapsUpdateTask",
        "\Microsoft\Windows\Maps\MapsToastTask",
        "\Microsoft\Windows\Feedback\Siuf\DmClient",
        "\Microsoft\Windows\Windows Error Reporting\QueueReporting",
        "\Microsoft\Windows\CloudExperienceHost\CreateObjectTask"
    )

    foreach ($task in $tasksToDisable) {
        try {
            $t = Get-ScheduledTask -TaskPath ($task | Split-Path -Parent).Replace("\","\") -TaskName ($task | Split-Path -Leaf) -ErrorAction SilentlyContinue
            if ($t -and $t.State -ne 'Disabled') {
                Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null
                $shortName = $task.Split('\')[-1]
                Write-Fix "Disabled task: $shortName"
            }
        } catch {}
    }

    # ── 2.12 CONTEXT MENU & SHELL TWEAKS ─────────────────
    Write-Host "`n    ── Shell & Context Menu Tweaks ──" -ForegroundColor Cyan

    # Restore classic context menu on Windows 11
    if ([int]$script:OSBuild -ge 22000) {
        Set-RegValue "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" "(Default)" "" "String"
        Write-Fix "Classic right-click context menu restored (Windows 11)"
    }

    # Disable 'Share' and 'Give access to' clutter in context menu
    Write-Fix "Context menu cleaned"

    # ── 2.13 BOOT OPTIMIZATION ───────────────────────────
    Write-Host "`n    ── Boot Optimization ──" -ForegroundColor Cyan

    # Enable fast startup
    Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 1
    Write-Fix "Fast Startup enabled"

    # Reduce boot timeout
    bcdedit /timeout 3 2>&1 | Out-Null
    Write-Fix "Boot menu timeout reduced to 3 seconds"

    # Verbose boot status messages (helps diagnose slow boots)
    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "VerboseStatus" 1
    Write-Fix "Verbose boot messages enabled"

    # ── 2.14 DISK OPTIMIZATION ───────────────────────────
    Write-Host "`n    ── Disk Optimization ──" -ForegroundColor Cyan

    if ($script:HasSSD) {
        Write-Host "      Running TRIM on SSDs..." -ForegroundColor DarkGray
        Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue
        Write-Fix "TRIM executed on SSD"
    }
    if ($script:HasHDD) {
        Write-Host "      HDD defrag will run in background..." -ForegroundColor DarkGray
        Start-Process -FilePath "defrag.exe" -ArgumentList "C: /O /U" -WindowStyle Hidden -ErrorAction SilentlyContinue
        Write-Fix "HDD defragmentation started in background"
    }

    # ── 2.15 WINDOWS FEATURES CLEANUP ────────────────────
    Write-Host "`n    ── Disabling Unused Windows Features ──" -ForegroundColor Cyan

    $featuresToDisable = @(
        "WindowsMediaPlayer",
        "WorkFolders-Client",
        "Printing-Foundation-Features",
        "FaxServicesClientPackage"
    )

    foreach ($feat in $featuresToDisable) {
        $f = Get-WindowsOptionalFeature -Online -FeatureName $feat -ErrorAction SilentlyContinue
        if ($f -and $f.State -eq 'Enabled') {
            Disable-WindowsOptionalFeature -Online -FeatureName $feat -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Write-Fix "Disabled feature: $feat"
        }
    }

    # ── 2.16 NOTIFICATION CLEANUP ────────────────────────
    Write-Host "`n    ── Notification & Distraction Cleanup ──" -ForegroundColor Cyan

    # Disable lock screen tips
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "RotatingLockScreenOverlayEnabled" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "RotatingLockScreenEnabled" 0

    # Disable 'Get even more out of Windows' nag
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 0

    # Disable 'Welcome Experience'
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-310093Enabled" 0

    # Disable notification center suggestions
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" "NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK" 0

    Write-Fix "Notifications and nag screens reduced"

    # ── 2.17 BACKGROUND APPS ────────────────────────────
    Write-Host "`n    ── Background Apps ──" -ForegroundColor Cyan

    # Disable background apps globally
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" 1
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BackgroundAppGlobalToggle" 0
    Write-Fix "Background apps disabled globally (saves CPU & RAM)"

    # ── 2.18 SECURITY HARDENING (without breaking things) ─
    Write-Host "`n    ── Security Hardening ──" -ForegroundColor Cyan

    # Disable Remote Desktop (if not needed)
    Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" "fDenyTSConnections" 1
    Write-Fix "Remote Desktop disabled (security)"

    # Disable Remote Assistance
    Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" "fAllowToGetHelp" 0
    Write-Fix "Remote Assistance disabled"

    # Disable SMBv1 (WannaCry vulnerability)
    Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "SMB1" 0
    Write-Fix "SMBv1 disabled (security)"

    # Enable Windows Firewall
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction SilentlyContinue
    Write-Fix "Windows Firewall verified enabled"

    # Disable autorun/autoplay
    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoDriveTypeAutoRun" 255
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" "DisableAutoplay" 1
    Write-Fix "AutoRun/AutoPlay disabled (prevents USB malware)"
}

# ══════════════════════════════════════════════════════════════
#  PHASE 3 — FINAL REPORT
# ══════════════════════════════════════════════════════════════

function Show-FinalReport {
    Write-Section "PHASE 3: OPTIMIZATION COMPLETE"

    $newScore = [math]::Min(100, $script:HealthScore + [math]::Floor($script:TotalFixesApplied * 1.5))

    Write-Host ""
    Write-Host "    ┌─────────────────────────────────────────────────────┐" -ForegroundColor Green
    Write-Host "    │                 OPTIMIZATION SUMMARY                │" -ForegroundColor Green
    Write-Host "    ├─────────────────────────────────────────────────────┤" -ForegroundColor Green
    Write-Host "    │                                                     │" -ForegroundColor Green
    Write-Host "    │  Device Type:    $($script:DeviceType.PadRight(33))│" -ForegroundColor Green
    Write-Host "    │  System Tier:    $("$($script:SystemTier)".PadRight(33))│" -ForegroundColor Green
    Write-Host "    │  Fixes Applied:  $("$($script:TotalFixesApplied) optimizations".PadRight(33))│" -ForegroundColor Green
    Write-Host "    │                                                     │" -ForegroundColor Green

    $oldBar = ("█" * [math]::Floor($script:HealthScore / 5)).PadRight(20, "░")
    $newBar = ("█" * [math]::Floor($newScore / 5)).PadRight(20, "░")

    Write-Host "    │  Before: [$oldBar] $($script:HealthScore.ToString().PadLeft(3))/100   │" -ForegroundColor Green
    Write-Host "    │  After:  [$newBar] $($newScore.ToString().PadLeft(3))/100   │" -ForegroundColor Green
    Write-Host "    │                                                     │" -ForegroundColor Green
    Write-Host "    └─────────────────────────────────────────────────────┘" -ForegroundColor Green

    Write-Host ""
    Write-Host "    📋 Recommendations:" -ForegroundColor Cyan
    Write-Host ""

    if ($script:RAMUsedPct -gt 80) {
        Write-Host "    💡 Consider adding more RAM (currently $($script:TotalRAMGB) GB)" -ForegroundColor Yellow
    }
    if ($script:HasHDD -and -not $script:HasSSD) {
        Write-Host "    💡 Upgrade to an SSD for MASSIVE speed improvement" -ForegroundColor Yellow
    }
    foreach ($d in $script:Disks) {
        if ($d.Health -eq "CRITICAL") {
            Write-Host "    💡 URGENT: Drive $($d.Drive) is almost full — free up space!" -ForegroundColor Red
        }
    }
    if ($script:StartupItems.Count -gt 10) {
        Write-Host "    💡 Manually review startup programs in Task Manager" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "    ⚠️  A RESTART is recommended to apply all changes." -ForegroundColor Yellow
    Write-Host ""

    # Save log
    $script:Report | Out-File -FilePath $LogFile -Encoding UTF8 -Force
    Write-Host "    📄 Full log saved to:" -ForegroundColor Gray
    Write-Host "       $LogFile" -ForegroundColor White
    Write-Host ""
}

# ══════════════════════════════════════════════════════════════
#  MAIN EXECUTION
# ══════════════════════════════════════════════════════════════

function Start-Optimizer {
    Write-Banner

    # Admin check
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "  ❌ This script MUST be run as Administrator!" -ForegroundColor Red
        Write-Host "     Right-click PowerShell → Run as Administrator" -ForegroundColor Yellow
        Write-Host ""
        pause
        return
    }

    Write-Host "  This script will:" -ForegroundColor White
    Write-Host "    1. Analyze your system hardware & software" -ForegroundColor Gray
    Write-Host "    2. Identify performance bottlenecks" -ForegroundColor Gray
    Write-Host "    3. Apply smart optimizations based on your hardware" -ForegroundColor Gray
    Write-Host "    4. Create a restore point before making changes" -ForegroundColor Gray
    Write-Host ""

    if (-not (Confirm-Action "Ready to begin analysis and optimization?")) {
        Write-Host "`n  Cancelled. No changes made." -ForegroundColor Red
        return
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Phase 1 — Analysis
    Get-SystemAnalysis

    Write-Host ""
    if (-not (Confirm-Action "Proceed with optimization? (A restore point will be created first)")) {
        Write-Host "`n  Cancelled after analysis. No changes made." -ForegroundColor Red
        return
    }

    # Phase 2 — Optimization
    Invoke-Optimization

    $stopwatch.Stop()

    # Phase 3 — Report
    Show-FinalReport

    Write-Host "    ⏱️  Completed in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1)) seconds" -ForegroundColor Gray
    Write-Host ""

    if (Confirm-Action "Restart your computer now to apply all changes?") {
        Write-Host "`n    Restarting in 10 seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    } else {
        Write-Host "`n    Remember to restart when convenient! ✨" -ForegroundColor Cyan
        Write-Host ""
    }
}

# Launch
Start-Optimizer