# Known Bugs

## [Severity: High] Outlook detection uses wildcard in Test-Path (never matches)
- **File:** modules/Analysis.psm1:231-233
- **Issue:** `Test-Path` doesn't support wildcards in registry paths, so the Outlook check always returns false and WSearch is proposed for disable even when Outlook is installed.
- **Repro:** Run analysis on a system with Outlook installed; WSearch still shows up as a disable candidate.
- **Fix:** Use `Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Office" -ErrorAction SilentlyContinue` and test each subkey for an Outlook value.

## [Severity: High] defrag hardcodes C: drive
- **File:** modules/Performance.psm1:301
- **Issue:** `defrag.exe "C: /O /U"` (note: quoted as a single argument) only ever targets C:, and mis-quotes the arguments.
- **Repro:** Run on a system where Windows is on D:, or where the user wants other fixed drives optimized — nothing useful happens.
- **Fix:** Iterate `Get-Volume -DriveType Fixed` and call `defrag.exe "$($_.DriveLetter):" /O /U` (as separate args).

## [Severity: High] Unbounded recursive cleanup can delete in-use system files
- **File:** modules/Cleanup.psm1:31
- **Issue:** `Get-ChildItem -Recurse -Force | Remove-Item -Recurse` on `$env:WINDIR\Temp` or `Logs\CBS` will try to delete files Windows is actively using (during updates).
- **Repro:** Run during Windows Update — deletes installer/CBS files and can wedge servicing.
- **Fix:** Iterate files, skip locked ones, and scope to known-safe subpaths (`-ErrorAction SilentlyContinue` per file instead of recursive removal).

## [Severity: Medium] MenuShowDelay written as String instead of DWord
- **File:** modules/Explorer.psm1:18
- **Issue:** Sets `MenuShowDelay` to string `"50"` (Explorer expects the canonical string "50" but the codebase helper defaults to DWord; double-check cast mismatch).
- **Repro:** After running, menus respond at default speed.
- **Fix:** Use `Set-RegValue ... "MenuShowDelay" "50" "String"` explicitly (the value is documented as REG_SZ).

## [Severity: Medium] qwinsta parsing fails on non-English Windows
- **File:** modules/Security.psm1:14-15
- **Issue:** Regex `'rdp-tcp.*Active'` depends on English output; localized Windows reports a translated state string and the active-session check silently fails.
- **Repro:** Run on German/French/Spanish Windows with an active RDP session — script disables RDP anyway.
- **Fix:** Use `Get-CimInstance Win32_TerminalServiceSetting`/`Get-SmbSession` or query by session ID, not localized text.

## [Severity: Medium] Get-PhysicalDisk crash on older Windows 10 builds
- **File:** modules/Analysis.psm1:101
- **Issue:** The cmdlet is missing on builds without the Storage module; analysis aborts instead of degrading.
- **Repro:** Run on a 1607/1703 image without the Storage module.
- **Fix:** `Get-PhysicalDisk -ErrorAction SilentlyContinue` and fall back to `Get-Disk` or WMI `Win32_DiskDrive`.

## [Severity: Low] LaunchTo registry value type ambiguity
- **File:** modules/Explorer.psm1:25
- **Issue:** Comment says "open to This PC" but the helper defaults to DWord; the canonical value is DWord `1` — acceptable, but inconsistent with sibling settings that use explicit types.
- **Repro:** Not a runtime failure; file Explorer should still open to "This PC", but callers maintaining the module get confused.
- **Fix:** Pass an explicit type token to match the rest of the file.

## [Severity: Low] PowerThrottling key is a no-op on older Windows 10
- **File:** modules/Performance.psm1:50
- **Issue:** The registry path was added in 1903; on earlier builds a key is created that Windows ignores while the module reports success.
- **Repro:** Run on build <18362 — key appears under HKLM but no behavior changes.
- **Fix:** Gate the write on `[int]$Analysis.OSBuild -ge 18362`.

## [Severity: Low] Missing guard around power-scheme GUIDs
- **File:** modules/Performance.psm1:37-38
- **Issue:** If `powercfg /list` output doesn't yield a match, `$ultGuid`/`$highGuid` are `$null` and `powercfg /setactive $null` silently fails inside the catch.
- **Repro:** Run on a stripped image where only Balanced is present.
- **Fix:** `if (-not $ultGuid -and -not $highGuid) { Write-Warning 'No high-performance scheme found'; return }`.
