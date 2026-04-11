#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Ultimate Windows System Optimizer v3.1 — automated performance tuning for Windows 10/11.

.DESCRIPTION
    Performs deep system analysis and applies intelligent optimizations based on detected
    hardware (CPU, RAM, SSD/HDD, laptop/desktop). Covers temp file cleanup, service
    trimming, privacy hardening, power plan tuning, network latency reduction, gaming
    tweaks, Explorer improvements, SSD-specific tuning, and security hardening.

    The script creates a System Restore Point before making any changes and generates
    a timestamped log file on the desktop.

.PARAMETER Only
    Run only the specified optimization sections. Valid values: Cleanup, Services, Power,
    VisualEffects, Privacy, Network, Performance, Explorer, SSD, Memory, ScheduledTasks,
    ContextMenu, Boot, Disk, Features, Notifications, BackgroundApps, Security

.PARAMETER Skip
    Skip the specified optimization sections. Same valid values as -Only.

.PARAMETER DryRun
    Show what changes WOULD be made without actually modifying anything.

.PARAMETER Undo
    Path to a previously generated undo JSON file. Restores all registry values.

.PARAMETER Force
    Skip per-section confirmation prompts.

.NOTES
    Version      : 3.1
    Author       : TiltedLunar123
    Requires     : Windows 10 or 11, PowerShell 5.1+, Administrator privileges
    Restore Point: Created automatically before optimization begins
    Log File     : Saved to Desktop as Optimizer_Log_YYYYMMDD_HHMMSS.txt

.EXAMPLE
    # Run all optimizations:
    .\Ultimate-Windows-System-Optimizer.ps1

.EXAMPLE
    # Preview changes without modifying anything:
    .\Ultimate-Windows-System-Optimizer.ps1 -DryRun

.EXAMPLE
    # Run only privacy and cleanup:
    .\Ultimate-Windows-System-Optimizer.ps1 -Only "Privacy","Cleanup"

.EXAMPLE
    # Run all except security, skip prompts:
    .\Ultimate-Windows-System-Optimizer.ps1 -Skip "Security" -Force

.EXAMPLE
    # Restore from undo file:
    .\Ultimate-Windows-System-Optimizer.ps1 -Undo "C:\Users\you\Desktop\undo_20260329_120000.json"
#>

param(
    [string[]]$Only,
    [string[]]$Skip,
    [switch]$DryRun,
    [string]$Undo,
    [switch]$Force
)

# ── CONFIG ──────────────────────────────────────────────────────
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
$LogFile = "$env:USERPROFILE\Desktop\Optimizer_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$RestorePoint = $true

# ── IMPORT MODULES ──────────────────────────────────────────────
$modulesPath = Join-Path $PSScriptRoot "modules"
Import-Module (Join-Path $modulesPath "UI.psm1")        -Force -DisableNameChecking
Import-Module (Join-Path $modulesPath "UndoManager.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $modulesPath "Config.psm1")     -Force -DisableNameChecking
Import-Module (Join-Path $modulesPath "Analysis.psm1")   -Force -DisableNameChecking
Import-Module (Join-Path $modulesPath "Cleanup.psm1")    -Force -DisableNameChecking
Import-Module (Join-Path $modulesPath "Services.psm1")   -Force -DisableNameChecking
Import-Module (Join-Path $modulesPath "Privacy.psm1")    -Force -DisableNameChecking
Import-Module (Join-Path $modulesPath "Network.psm1")    -Force -DisableNameChecking
Import-Module (Join-Path $modulesPath "Performance.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $modulesPath "Security.psm1")   -Force -DisableNameChecking
Import-Module (Join-Path $modulesPath "Explorer.psm1")   -Force -DisableNameChecking

# ── UNDO MODE ───────────────────────────────────────────────────
if ($Undo) {
    Write-Banner
    Write-Section "UNDO / ROLLBACK"
    Write-Host "    Restoring from: $Undo" -ForegroundColor Cyan
    $success = Restore-FromUndoFile -FilePath $Undo
    if ($success) {
        Write-Host "    All registry values restored successfully." -ForegroundColor Green
    } else {
        Write-Host "    Some values could not be restored. Check warnings above." -ForegroundColor Yellow
    }
    Write-Host ""
    return
}

# ── VALIDATE SECTION NAMES ──────────────────────────────────────
$validSections = Get-ValidSectionList
if ($Only) {
    foreach ($s in $Only) {
        if ($s -notin $validSections) {
            Write-Host "  ERROR: Invalid section name '$s'. Valid sections: $($validSections -join ', ')" -ForegroundColor Red
            return
        }
    }
}
if ($Skip) {
    foreach ($s in $Skip) {
        if ($s -notin $validSections) {
            Write-Host "  ERROR: Invalid section name '$s'. Valid sections: $($validSections -join ', ')" -ForegroundColor Red
            return
        }
    }
}

# ── DRY RUN MODE ────────────────────────────────────────────────
if ($DryRun) {
    Set-DryRunMode $true
}

# ── SECTION HELPER ──────────────────────────────────────────────
# Maps section names to their optimization functions
$sectionMap = [ordered]@{
    "Cleanup"        = { param($a) Invoke-CleanupOptimization -Analysis $a }
    "Services"       = { param($a) Invoke-ServicesOptimization -Analysis $a }
    "Power"          = { param($a) Invoke-PowerOptimization -Analysis $a }
    "VisualEffects"  = { param($a) Invoke-VisualEffectsOptimization -Analysis $a }
    "Privacy"        = { param($a) Invoke-PrivacyOptimization -Analysis $a }
    "Network"        = { param($a) Invoke-NetworkOptimization -Analysis $a }
    "Performance"    = { param($a) Invoke-PerformanceOptimization -Analysis $a }
    "Explorer"       = { param($a) Invoke-ExplorerOptimization -Analysis $a }
    "SSD"            = { param($a) Invoke-SSDOptimization -Analysis $a }
    "Memory"         = { param($a) Invoke-MemoryOptimization -Analysis $a }
    "ScheduledTasks" = { param($a) Invoke-ScheduledTasksOptimization -Analysis $a }
    "ContextMenu"    = { param($a) Invoke-ContextMenuOptimization -Analysis $a }
    "Boot"           = { param($a) Invoke-BootOptimization -Analysis $a }
    "Disk"           = { param($a) Invoke-DiskOptimization -Analysis $a }
    "Features"       = { param($a) Invoke-FeaturesOptimization -Analysis $a }
    "Notifications"  = { param($a) Invoke-NotificationsOptimization -Analysis $a }
    "BackgroundApps" = { param($a) Invoke-BackgroundAppsOptimization -Analysis $a }
    "Security"       = { param($a) Invoke-SecurityOptimization -Analysis $a }
}

# ── MAIN EXECUTION ──────────────────────────────────────────────
Write-Banner

# Admin check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  ERROR: This script MUST be run as Administrator!" -ForegroundColor Red
    Write-Host "     Right-click PowerShell -> Run as Administrator" -ForegroundColor Yellow
    Write-Host ""
    pause
    return
}

# Verify supported OS
$osBuild = [System.Environment]::OSVersion.Version.Build
if ($osBuild -lt 10240) {
    Write-Host "  ERROR: This script requires Windows 10 or later (detected build $osBuild)." -ForegroundColor Red
    Write-Host ""
    pause
    return
}

if ($DryRun) {
    Write-Host "  *** DRY RUN MODE - No changes will be made ***" -ForegroundColor DarkYellow
    Write-Host ""
}

Write-Host "  This script will:" -ForegroundColor White
Write-Host "    1. Analyze your system hardware & software" -ForegroundColor Gray
Write-Host "    2. Identify performance bottlenecks" -ForegroundColor Gray
Write-Host "    3. Apply smart optimizations based on your hardware" -ForegroundColor Gray
Write-Host "    4. Create a restore point before making changes" -ForegroundColor Gray
Write-Host ""
Write-Host "  IMPORTANT: This script modifies system settings, services," -ForegroundColor Yellow
Write-Host "  registry values, and scheduled tasks. Review the README" -ForegroundColor Yellow
Write-Host "  before proceeding." -ForegroundColor Yellow
Write-Host ""

if (-not $Force) {
    if (-not (Confirm-Action "Ready to begin analysis and optimization?")) {
        Write-Host "`n  Cancelled. No changes made." -ForegroundColor Red
        return
    }
}

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Phase 1 - Analysis
$analysisResults = Get-SystemAnalysis
$beforeScore = Get-HealthScore -AnalysisResults $analysisResults

if (-not $Force) {
    Write-Host ""
    if (-not (Confirm-Action "Proceed with optimization? (A restore point will be created first)")) {
        Write-Host "`n  Cancelled after analysis. No changes made." -ForegroundColor Red
        return
    }
}

# Phase 2 - Optimization
Write-Section "PHASE 2: INTELLIGENT OPTIMIZATION"

# Create restore point
if ($RestorePoint -and -not $DryRun) {
    Write-Host "`n    Creating System Restore Point..." -ForegroundColor Cyan
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "Pre-Optimizer Backup $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Good "Restore point created successfully"
    } catch {
        Write-Warn "Could not create restore point (may have been created recently)"
        Log "[ERROR] Restore point creation failed: $_"
    }
} elseif ($DryRun) {
    Write-Dry "Would create System Restore Point"
}

# Run each enabled section
foreach ($sectionName in $sectionMap.Keys) {
    if (-not (Test-SectionEnabled -SectionName $sectionName -Only $Only -Skip $Skip)) {
        continue
    }

    if (-not $Force -and -not $DryRun) {
        if (-not (Confirm-Action "Run $sectionName optimization?")) {
            Write-Skip "Skipped $sectionName (user declined)"
            continue
        }
    }

    & $sectionMap[$sectionName] $analysisResults
}

$stopwatch.Stop()

# Export undo file
if (-not $DryRun) {
    $undoFile = Export-UndoFile
    if ($undoFile) {
        Write-Host ""
        Write-Good "Undo file saved: $undoFile"
        Write-Host "    Use -Undo `"$undoFile`" to restore all registry changes" -ForegroundColor Gray
    }
}

# Phase 3 - Re-run analysis for real after-score
Write-Section "PHASE 3: OPTIMIZATION COMPLETE"

# Re-analyze to get actual post-optimization score
$postResults = @{
    RAMUsedPct        = $analysisResults.RAMUsedPct
    StartupItems      = $analysisResults.StartupItems
    TempSizeMB        = 0  # temp files cleaned
    ServicesToDisable  = @()
    TelemetryEnabled  = $false
    CurrentPowerPlan   = ""
    Disks             = $analysisResults.Disks
    VisualEffects      = ""
}

# Re-check actual system state for accurate score
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        $postResults.RAMUsedPct = [math]::Round((1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100, 1)
    }
} catch { $null = $_ }

# Re-check temp file size
$tempPaths = @("$env:TEMP", "$env:WINDIR\Temp", "$env:LOCALAPPDATA\Microsoft\Windows\INetCache")
$postTempMB = 0
foreach ($tp in $tempPaths) {
    if (Test-Path $tp) {
        try {
            $postTempMB += (Get-ChildItem -Path $tp -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
        } catch { $null = $_ }
    }
}
$postResults.TempSizeMB = [math]::Round($postTempMB, 1)

# Re-check services
$bloatSvcs = Get-BloatServiceDefinition
$postResults.ServicesToDisable = @()
foreach ($svc in $bloatSvcs) {
    $s = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($s -and $s.Status -eq 'Running') {
        $postResults.ServicesToDisable += $svc
    } elseif ($s -and $s.StartType -ne 'Disabled') {
        $postResults.ServicesToDisable += $svc
    }
}

# Re-check telemetry
$telVal = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name AllowTelemetry -ErrorAction SilentlyContinue).AllowTelemetry
$postResults.TelemetryEnabled = ($telVal -ne 0)

# Re-check power plan
$activePlan = powercfg /getactivescheme 2>$null
$postResults.CurrentPowerPlan = if ($activePlan -match '"([^"]+)"') { $Matches[1] } else { "Unknown" }

# Re-check visual effects
$veSetting = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -ErrorAction SilentlyContinue).VisualFXSetting
$postResults.VisualEffects = switch ($veSetting) { 0 { "Auto" } 1 { "Appearance" } 2 { "Performance" } 3 { "Custom" } default { "Unknown" } }

$newScore = Get-HealthScore -AnalysisResults $postResults
$fixCount = Get-FixCount

Write-Host ""
Write-Host "    +-----------------------------------------------------+" -ForegroundColor Green
Write-Host "    |                 OPTIMIZATION SUMMARY                 |" -ForegroundColor Green
Write-Host "    +-----------------------------------------------------+" -ForegroundColor Green
Write-Host "    |                                                      |" -ForegroundColor Green
Write-Host "    |  Device Type:    $($analysisResults.DeviceType.PadRight(34))|" -ForegroundColor Green
Write-Host "    |  System Tier:    $("$($analysisResults.SystemTier)".PadRight(34))|" -ForegroundColor Green
Write-Host "    |  Fixes Applied:  $("$fixCount optimizations".PadRight(34))|" -ForegroundColor Green
Write-Host "    |                                                      |" -ForegroundColor Green

$oldBar = ("#" * [math]::Floor($beforeScore / 5)).PadRight(20, "-")
$newBar = ("#" * [math]::Floor($newScore / 5)).PadRight(20, "-")

Write-Host "    |  Before: [$oldBar] $($beforeScore.ToString().PadLeft(3))/100    |" -ForegroundColor Green
Write-Host "    |  After:  [$newBar] $($newScore.ToString().PadLeft(3))/100    |" -ForegroundColor Green
Write-Host "    |                                                      |" -ForegroundColor Green
Write-Host "    +-----------------------------------------------------+" -ForegroundColor Green

Write-Host ""
Write-Host "    Recommendations:" -ForegroundColor Cyan
Write-Host ""

if ($analysisResults.RAMUsedPct -gt 80) {
    Write-Host "    * Consider adding more RAM (currently $($analysisResults.TotalRAMGB) GB)" -ForegroundColor Yellow
}
if ($analysisResults.HasHDD -and -not $analysisResults.HasSSD) {
    Write-Host "    * Upgrade to an SSD for MASSIVE speed improvement" -ForegroundColor Yellow
}
foreach ($d in $analysisResults.Disks) {
    if ($d.Health -eq "CRITICAL") {
        Write-Host "    * URGENT: Drive $($d.Drive) is almost full - free up space!" -ForegroundColor Red
    }
}
if ($analysisResults.StartupItems.Count -gt 10) {
    Write-Host "    * Manually review startup programs in Task Manager" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "    WARNING: A RESTART is recommended to apply all changes." -ForegroundColor Yellow
Write-Host ""

# Save log
try {
    Get-Report | Out-File -FilePath $LogFile -Encoding UTF8 -Force
    Write-Host "    Full log saved to:" -ForegroundColor Gray
    Write-Host "       $LogFile" -ForegroundColor White
} catch {
    Write-Host "    Could not save log file to $LogFile" -ForegroundColor Red
}

Write-Host ""
Write-Host "    Completed in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1)) seconds" -ForegroundColor Gray
Write-Host ""

if (-not $DryRun) {
    if (Confirm-Action "Restart your computer now to apply all changes?") {
        Write-Host "`n    Restarting in 10 seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    } else {
        Write-Host "`n    Remember to restart when convenient!" -ForegroundColor Cyan
        Write-Host ""
    }
}
