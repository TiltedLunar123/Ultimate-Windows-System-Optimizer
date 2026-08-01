# Ultimate Windows System Optimizer

[![CI](https://github.com/TiltedLunar123/Ultimate-Windows-System-Optimizer/actions/workflows/ci.yml/badge.svg)](https://github.com/TiltedLunar123/Ultimate-Windows-System-Optimizer/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A PowerShell script that analyzes Windows 10/11 systems and applies intelligent, hardware-aware optimizations to improve performance, reduce bloat, harden privacy, and tighten security.

## What it does

It looks at the machine first: CPU, RAM, GPU, whether the system disk is an SSD or a
spinning drive, laptop or desktop. From that it assigns a tier (Low-End, Mid-Range,
High-End) and scores overall health out of 100. It scores again at the end so you can
see what actually moved.

Then it works through the usual suspects. Telemetry, Cortana, the advertising ID,
activity history, location tracking, feedback prompts and silent app installs all get
switched off. So do the Xbox, fax and geolocation services, and the scheduled tasks
nobody misses: compatibility appraiser, CEIP, disk diagnostics, maps updates, error
reporting. On the security side it turns off Remote Desktop, Remote Assistance, SMBv1
and AutoRun, and checks the firewall is actually on.

Performance work is tier-aware rather than uniform. Visual effects get tuned to what the
machine can carry. Desktops get the Ultimate or High Performance power plan; laptops get
separate AC and battery profiles instead. SSDs get Prefetch and Superfetch off, TRIM on,
and fewer pointless writes. Network settings get Nagle's algorithm disabled, TCP tuned,
DNS flushed. For games there is Game Mode on, Game DVR off, hardware GPU scheduling,
mouse acceleration off, and a retuned multimedia scheduler. Explorer gets file
extensions shown, Bing search out of the Start menu, faster menus, and This PC as the
landing view.

Cleanup covers user and Windows temp, internet and update caches, crash dumps, the
thumbnail cache, and the Recycle Bin. Only files more than 24 hours old are touched, so
whatever the current session is holding onto stays put, and it deletes files rather than
removing whole directory trees out from under running applications.

Boot gets a shorter timeout and verbose messages. Fast Startup only gets enabled when
Windows is the only entry in the boot menu, because turning it on next to a Linux
install is how people lose filesystems.

## Not breaking your machine

This is the part I have spent the most time on. Before each change the script checks
whether anything on the system depends on what it is about to turn off, and skips it if
so. Detected printers, touchscreens, Outlook, Teams, OneNote, a live RDP session, a
dual-boot menu: all of these veto the changes that would break them.

Every registry write is recorded to a JSON file that can put the old values back, and a
System Restore Point is created before anything is modified. `-DryRun` shows the whole
plan without touching a thing, and you can run or skip individual sections. A timestamped
log lands on the desktop.

Run it with `-DryRun` first. I would.

## Requirements

- **Windows 10** (build 10240+) or **Windows 11**
- **PowerShell 5.1** or later
- **Administrator privileges** - the script must be run as admin
- System Restore enabled (recommended, for rollback protection)

## Quick Start (One Command)

Open **PowerShell** and paste this single command. It downloads, elevates to admin, and runs everything automatically:

```powershell
irm https://raw.githubusercontent.com/TiltedLunar123/Ultimate-Windows-System-Optimizer/main/run.ps1 | iex
```

That's it. The script will:
1. Request administrator privileges (UAC prompt)
2. Resolve the current commit on `main` and print it
3. Download that exact commit and print the archive's SHA-256
4. Create a System Restore Point so changes can be rolled back
5. Analyze your system
6. Apply all optimizations
7. Show before/after health scores
8. Clean up temp files

### About that one-liner

Piping a script off the internet straight into `iex` and letting it elevate
means you are handing full administrator access to whatever that URL serves at
the moment you run it. That is worth being uncomfortable about, here or
anywhere else. I cannot sign the script (no code-signing certificate), so
instead of pretending the risk away, the installer does what it actually can:

- It asks the GitHub API which commit `main` points at, then downloads that
  commit rather than the branch tip, so the code cannot change between the
  moment you read it and the moment it runs.
- It prints the commit SHA and a link to that commit before downloading.
- It prints the SHA-256 of the archive it fetched, so you can compare across
  machines or against your own download.

If you want to pin a revision you have already read, set `UWSO_COMMIT` to the
short SHA GitHub shows you. The installer stops before downloading anything if
`main` has moved on:

```powershell
$env:UWSO_COMMIT = 'a1b2c3d'; irm https://raw.githubusercontent.com/TiltedLunar123/Ultimate-Windows-System-Optimizer/main/run.ps1 | iex
```

None of this protects you if the repository or my account is compromised. If
that matters for the machine you are on, clone it, read it, and run it from the
clone. The manual instructions below do exactly that, and the optimizer is the
same either way.

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
.\Ultimate-Windows-System-Optimizer.ps1 -Undo "$env:LOCALAPPDATA\UWSO\undo_20260329_120000.json"
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
| Disk optimization | TRIM on SSDs, defrag on HDDs, temp file removal (files older than 24h only) |

## Output

A log file is saved under `%LOCALAPPDATA%\UWSO\` (with fallback to `%TEMP%`, then the user's Desktop if neither is writable):

```
Optimizer_Log_YYYYMMDD_HHMMSS.txt
```

This log contains timestamped entries for every action, warning, fix, and skip that occurred during the run.

An undo file is written to the same directory after optimization:

```
undo_YYYYMMDD_HHMMSS.json
```

This JSON file records the previous value of every registry key that was modified, plus the startup type and running state of every service that was disabled. `-Undo` puts both back. The file's ACL is tightened after write so only the current user can read it (the JSON contains enough configuration detail that it shouldn't be world-readable on a shared machine).

### What undo does not cover

The undo file is not a full system snapshot, and it is worth knowing where it stops before you rely on it:

| Change | Covered by `-Undo`? | How to reverse it |
|---|---|---|
| Registry values | Yes | `-Undo` |
| Disabled services | Yes | `-Undo` |
| Disabled scheduled tasks | No | `Enable-ScheduledTask` per task, or the restore point |
| Disabled optional features | No | `Enable-WindowsOptionalFeature -Online`, or the restore point |
| `bcdedit` boot timeout | No | `bcdedit /timeout 30` |
| `fsutil` NTFS settings | No | `fsutil behavior set disablelastaccess 0` |
| Memory compression | No | `Enable-MMAgent -MemoryCompression` |
| Deleted temp files and Recycle Bin | No | Not reversible |

The System Restore Point the script creates before it starts covers most of the rows marked no. That is the reason it is created, and the reason it is worth leaving System Restore turned on.

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
