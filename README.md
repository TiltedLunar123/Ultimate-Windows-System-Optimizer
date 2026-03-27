# Ultimate Windows System Optimizer

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A PowerShell script that analyzes Windows 10/11 systems and applies intelligent, hardware-aware optimizations to improve performance, reduce bloat, harden privacy, and tighten security.

## Features

- **Deep system analysis** — detects CPU, RAM, GPU, SSD/HDD, laptop vs. desktop, and assigns a system tier (Low-End, Mid-Range, High-End)
- **Health scoring** — calculates a 0-100 health score before and after optimization
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
- **Restore point creation** — automatically creates a System Restore Point before making any changes
- **Detailed logging** — saves a timestamped log file to the desktop

## Requirements

- **Windows 10** (build 10240+) or **Windows 11**
- **PowerShell 5.1** or later
- **Administrator privileges** — the script must be run as admin
- System Restore enabled (recommended, for rollback protection)

## Usage

1. Download `Ultimate-Windows-System-Optimizer.ps1`

2. Open **PowerShell as Administrator**

3. Allow script execution for the current session:

   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process
   ```

4. Navigate to the script directory and run it:

   ```powershell
   .\Ultimate-Windows-System-Optimizer.ps1
   ```

5. Follow the on-screen prompts:
   - Confirm to start analysis
   - Review the health score and analysis results
   - Confirm to proceed with optimization
   - Optionally restart when complete

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

## Disclaimer

**Use at your own risk.** This script modifies Windows settings, services, registry values, scheduled tasks, and system behavior. While it creates a restore point before making changes, there is no guarantee that every system can be restored cleanly or that every optimization is appropriate for every configuration.

Some things to keep in mind:

- Some disabled services may be needed for your specific workflow
- Privacy and telemetry changes may affect certain Microsoft features
- Gaming and network tweaks are not universally beneficial
- Disabling background apps and notifications changes convenience features
- Remote Desktop is disabled by default for security; re-enable it if you need it

**Always review the script before running it on a machine you depend on.**

## License

This project is licensed under the [MIT License](LICENSE).
