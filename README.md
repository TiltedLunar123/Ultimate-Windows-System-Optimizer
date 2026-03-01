# Ultimate Windows System Optimizer v3.0

Smart Windows analysis and optimization script for improving performance, reducing background bloat, tightening privacy settings, and applying system-specific tweaks based on the hardware detected.

## Overview

**Ultimate Windows System Optimizer v3.0** is a PowerShell script that scans a Windows system, identifies common performance and clutter issues, and applies a large set of automated optimizations.

It is designed to:

* analyze hardware, storage, memory, startup items, services, network settings, and privacy settings
* score overall system health
* apply targeted optimizations based on whether the machine is low-end, mid-range, high-end, laptop, desktop, SSD, or HDD
* create a restore point before making changes
* generate a detailed log on the desktop

This script is meant for **advanced users, power users, and PC enthusiasts** who want a fast all-in-one Windows tuning tool.

---

## Features

### Deep system analysis

The script checks:

* device type: laptop or desktop
* Windows version and build
* CPU, GPU, RAM, uptime
* disk free space and drive health status
* SSD vs HDD detection
* junk and temp file size
* recycle bin contents
* startup programs from registry, startup folder, and scheduled tasks
* potentially unnecessary services
* active power plan
* visual effects settings
* top memory-consuming processes
* DNS and network configuration
* telemetry, Cortana, advertising ID, and update status

### Intelligent optimization

Based on the analysis, the script can:

* create a system restore point
* clean temp files, update cache, crash dumps, thumbnails, and recycle bin
* disable selected unnecessary services
* optimize power settings for laptops and desktops
* tune visual effects based on system tier
* harden privacy settings
* reduce tracking and suggestions in Windows
* tweak network settings for lower latency
* enable gaming and performance-related options
* improve File Explorer behavior
* apply SSD-specific tuning like TRIM and reduced write overhead
* recommend memory/page file settings
* disable selected scheduled tasks
* reduce notification and background app clutter
* apply basic security hardening

### Final summary

At the end, the script shows:

* total fixes applied
* estimated before/after health score
* recommended next steps
* path to a full log file saved on the desktop

---

## What it changes

This script makes changes to:

* Windows services
* registry values
* power configuration
* privacy and telemetry settings
* scheduled tasks
* Explorer behavior
* gaming and network settings
* optional Windows features
* security-related system settings

Because of that, this is **not** a harmless cosmetic script. It changes real system behavior.

---

## Requirements

* **Windows 10 or Windows 11**
* **PowerShell**
* **Administrator privileges**
* restore point support enabled if you want rollback protection

The script includes:

```powershell
#Requires -RunAsAdministrator
```

So it must be launched as admin.

---

## How to run

1. Save the script as something like:
   `Ultimate-Windows-System-Optimizer.ps1`

2. Open **PowerShell as Administrator**

3. If needed, allow script execution for the session:

```powershell
Set-ExecutionPolicy Bypass -Scope Process
```

4. Run the script:

```powershell
.\Ultimate-Windows-System-Optimizer.ps1
```

5. Confirm the prompts:

   * start analysis
   * proceed with optimization
   * restart after changes

---

## Safety notes

This script tries to create a **System Restore Point** before making changes, but that may fail if restore points are disabled, unavailable, or recently created.

You should still treat this as a script that can significantly alter system behavior.

### Read this before using it

* some tweaks may disable features you actually use
* some services marked as unnecessary may matter for your workflow
* some gaming/network tweaks are preference-dependent, not universal miracles
* privacy and telemetry changes may affect Microsoft features
* disabling background apps, search behavior, or notifications can change convenience features
* Remote Desktop, Remote Assistance, SMBv1, and other settings are modified for security reasons

If you are not comfortable troubleshooting Windows, do **not** run this blindly.

---

## Best use case

This script makes the most sense for:

* old or bloated Windows installs
* gaming PCs that need cleanup and latency-focused tuning
* laptops with too many startup/background items
* systems with junk buildup and poor default settings
* users who want a faster, leaner Windows setup without manually doing every tweak

---

## Probably not ideal for

This script may be a bad fit for:

* production/work machines where every feature matters
* managed school or company devices
* systems that rely on Remote Desktop or specific Windows services
* users who want full control over every single tweak before it happens
* people expecting a guaranteed speed boost from every setting

Some tweaks help a lot. Some are minor. Some are situational. That is the truth.

---

## Output

A log file is saved to the desktop with a name like:

```text
Optimizer_Log_YYYYMMDD_HHMMSS.txt
```

This log contains a timestamped summary of actions, warnings, fixes, and the health score.

---

## Example optimizations included

* temp file cleanup
* Windows Update cache cleanup
* recycle bin cleanup
* startup and service trimming
* telemetry disablement
* Cortana disablement
* advertising ID disablement
* Game Mode enablement
* Game DVR disablement
* DNS cache flush
* Nagle-related latency tweaks
* power throttling disablement
* SSD TRIM support
* file extension visibility
* faster Explorer/menu behavior
* notification reduction
* background app disablement
* firewall verification
* AutoRun/AutoPlay disablement

---

## Important caveats

A few tweaks in scripts like this are debated in the PC tuning world. That does **not** mean the script is useless. It means you should understand that:

* not every registry tweak gives a measurable performance gain
* some network and gaming tweaks help only in certain setups
* disabling services can be helpful or pointless depending on your machine
* estimated “after” health score is not a benchmark, it is just a rough internal score

Use this as a **practical tuning tool**, not a magic button.

---

## Disclaimer

Use at your own risk.

This script modifies Windows settings, services, registry values, scheduled tasks, and system behavior. While it attempts to create a restore point first, there is no guarantee every system can be restored cleanly or that every tweak is ideal for every user.

Always review the code before running it on a machine you care about.

---

## License

Use, modify, and share at your own discretion.

If you publish or distribute this project, it is smart to add a proper license file such as **MIT**.

---

## Author note

This script is built for people who want a faster, cleaner Windows setup with less manual digging through settings, services, and registry paths.

It is aggressive enough to matter, but still tries to stay practical by adapting to the system it detects.
