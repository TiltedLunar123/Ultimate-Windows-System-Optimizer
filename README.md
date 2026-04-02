# Ultimate Windows System Optimizer

[![CI](https://github.com/TiltedLunar123/Ultimate-Windows-System-Optimizer/actions/workflows/ci.yml/badge.svg)](https://github.com/TiltedLunar123/Ultimate-Windows-System-Optimizer/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A PowerShell script that analyzes Windows 10/11 systems and applies intelligent, hardware-aware optimizations to improve performance, reduce bloat, harden privacy, and tighten security.

## Screenshots

<!-- Screenshots coming soon -->

## Features

- **Deep system analysis** — detects CPU, RAM, GPU, SSD/HDD, laptop vs. desktop, and assigns a system tier (Low-End, Mid-Range, High-End)
- **Health scoring** — calculates a real 0-100 health score before and after optimization
- **Temp file cleanup** — removes user temp, Windows temp, internet cache, update cache, crash dumps, thumbnail cache, and empties the Recycle Bin
- **Service trimming** — disables telemetry, Xbox, fax, geolocation, and other commonly unnecessary services
- **Power plan tuning** — activates Ultimate/High Performance on desktops; optimizes AC vs. battery profiles on laptops
- **Visual effects optimization** — adjusts animations and effects based on system tier
- **Privacy hardening** — disables telemetry, Cortana, advertising ID, activity history, location tracking, feedback prompts, and silent app installs
- **Network latency reduction** — disables Nagle's algorithm, optimizes TCP settings, flushes DNS
- **Gaming tweaks** — enables Game Mode, disables Game DVR, configures GPU scheduling, disables mouse acceleration, and tunes the multimedia scheduler
- **Explorer improvements** — shows file extensions, disables Bing search in Start Menu, speeds up menus, opens to This PC
- **SSD-specific tuning** — disables Prefetch/Superfetch, enables TRIM, reduces unnecessary writes
- **Scheduled task cleanup** — disables compatibility appraiser, CEIP, disk diagnostics, maps updates, and error reporting tasks
- **Boot optimization** — enables Fast Startup, reduces boot timeout, enables verbose boot messages
- **Security hardening** — disables Remote Desktop, Remote Assistance, SMBv1, and AutoRun; verifies Windows Firewall is enabled
- **Context-aware safety** — skips changes that would break detected hardware or active sessions (Outlook, RDP, printers, touchscreens)
- **Undo/rollback** — exports all registry changes to a JSON file that can restore previous values
- **Dry run mode** — preview all changes without modifying anything
- **Selective optimization** — run only specific sections or skip sections you don't want
- **Restore point creation** — automatically creates a System Restore Point before making any changes
- **Detailed logging** — saves a timestamped log file to the desktop

## Requirements

- **Windows 10** (build 10240+) or **Windows 11**
- **PowerShell 5.1** or later
- **Administrator privileges** — the script must be run as admin
- System Restore enabled (recommended, for rollback protection)

## Quick Start (One Command)

Open **PowerShell** and paste this single command. It downloads, elevates to admin, and runs everything automatically:

```powershell
irm https://raw.githubusercontent.com/TiltedLunar123/Ultimate-Windows-System-Optimizer/main/run.ps1 | iex
```

That's it. The script will:
1. Request administrator privileges (UAC prompt)
2. Download the latest version
3. Analyze your system
4. Apply all optimizations
5. Show before/after health scores
6. Clean up temp files

## Manual Usage

If you prefer to clone and run manually:

1. Clone or download this repository
2. Open **PowerShell as Administrator**
3. Run:

   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process
   .\Ultimate-Windows-System-Optimizer.ps1
   ```

## Parameters

| Parameter | Type | Description |
|---|---|---|
| `-DryRun` | Switch | Preview all changes without modifying anything. Shows what WOULD happen. |
| `-Only` | String[] | Run only the specified sections. Example: `-Only "Privacy","Cleanup"` |
| `-Skip` | String[] | Run all sections except the specified ones. Example: `-Skip "Security","Network"` |
| `-Undo` | String | Path to a previously generated undo JSON file. Restores all registry values. |
| `-Force` | Switch | Skip per-section confirmation prompts. Runs all enabled sections without asking. |

### Valid Section Names

`Cleanup`, `Services`, `Power`, `VisualEffects`, `Privacy`, `Network`, `Performance`, `Explorer`, `SSD`, `Memory`, `ScheduledTasks`, `ContextMenu`, `Boot`, `Disk`, `Features`, `Notifications`, `BackgroundApps`, `Security`

### Examples

```powershell
# Run all optimizations (prompts before each section):
.\Ultimate-Windows-System-Optimizer.ps1

# Preview changes without modifying anything:
.\Ultimate-Windows-System-Optimizer.ps1 -DryRun

# Run only privacy and cleanup, skip prompts:
.\Ultimate-Windows-System-Optimizer.ps1 -Only "Privacy","Cleanup" -Force

# Run everything except security:
.\Ultimate-Windows-System-Optimizer.ps1 -Skip "Security"

# Restore from undo file:
.\Ultimate-Windows-System-Optimizer.ps1 -Undo "C:\Users\you\Desktop\undo_20260329_120000.json"
```

## Modules

The optimizer is split into a modular architecture for maintainability and testability:

```
Ultimate-Windows-System-Optimizer.ps1   # Entry point, orchestration, parameter handling
modules/
  Config.psm1          # Shared constants, tier definitions, Set-RegValue helper
  UI.psm1              # Banner, section headers, status output, colors, logging
  UndoManager.psm1     # Save registry state before changes, restore from JSON
  Analysis.psm1        # Phase 1 - hardware/disk/temp/startup/services/power analysis + scoring
  Cleanup.psm1         # Temp files, disk cleanup, recycle bin
  Services.psm1        # Bloat service detection and disabling
  Privacy.psm1         # Telemetry, ads, tracking, content delivery, feedback
  Network.psm1         # Nagle, TCP, DNS, network throttling
  Performance.psm1     # Gaming, visual effects, memory, GPU, boot, scheduled tasks, background apps
  Security.psm1        # RDP, SMB, firewall, autorun
  Explorer.psm1        # Shell tweaks, context menu, file extensions, search
tests/
  Analysis.Tests.ps1   # Tier classification and score calculation tests
  UndoManager.Tests.ps1 # Undo file generation and restore tests
  Optimizer.Tests.ps1  # Section filtering, DryRun mode, and integration tests
.github/workflows/
  ci.yml               # PSScriptAnalyzer lint + Pester tests on push/PR
```

Each optimization module exports a single `Invoke-*Optimization` function. The analysis module exports `Get-SystemAnalysis` (returns a results hashtable) and `Get-HealthScore` (computes score from results). The undo manager exports `Save-RegistryState`, `Export-UndoFile`, and `Restore-FromUndoFile`.

## What the Script Modifies

| Category | Examples |
|---|---|
| Windows services | Telemetry, Xbox, Fax, Geolocation, Search Indexer, etc. |
| Registry values | Privacy settings, visual effects, power throttling, network tuning |
| Power configuration | Power plan selection, CPU throttle limits, USB suspend settings |
| Scheduled tasks | Compatibility appraiser, CEIP, disk diagnostics, map updates |
| Explorer behavior | File extensions, Quick Access, menu delay, Bing search |
| Network settings | Nagle's algorithm, TCP acknowledgment, DNS cache, ECN |
| Gaming settings | Game Mode, Game DVR, GPU scheduling, mouse acceleration |
| Security settings | Remote Desktop, Remote Assistance, SMBv1, AutoRun, Firewall |
| Optional features | Windows Media Player, Work Folders, Fax client |
| Disk optimization | TRIM on SSDs, defrag on HDDs, temp file removal |

## Output

A log file is saved to the desktop:

```
Optimizer_Log_YYYYMMDD_HHMMSS.txt
```

This log contains timestamped entries for every action, warning, fix, and skip that occurred during the run.

An undo file is also saved to the desktop after optimization:

```
undo_YYYYMMDD_HHMMSS.json
```

This JSON file records the previous value of every registry key that was modified, allowing full rollback with the `-Undo` parameter.

## Disclaimer

**Use at your own risk.** This script modifies Windows settings, services, registry values, scheduled tasks, and system behavior. While it creates a restore point before making changes, there is no guarantee that every system can be restored cleanly or that every optimization is appropriate for every configuration.

Some things to keep in mind:

- Some disabled services may be needed for your specific workflow
- Privacy and telemetry changes may affect certain Microsoft features
- Gaming and network tweaks are not universally beneficial
- Disabling background apps and notifications changes convenience features
- Remote Desktop is disabled by default for security; re-enable it if you need it
- Use `-DryRun` to preview changes before applying them
- Use the generated undo file to roll back registry changes

**Always review the script before running it on a machine you depend on.**

## License

This project is licensed under the [MIT License](LICENSE).
