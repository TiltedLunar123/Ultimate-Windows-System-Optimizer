# Changelog

All notable changes to this project are documented here. This project adheres
to [Semantic Versioning](https://semver.org/).

## [4.0.0] - 2026-05-25

A correctness, safety, and feature release. Closes the open bug, security, and
enhancement issues and adds presets, a JSON report, and richer undo.

### Added
- **Optimization presets** via `-Preset`: `Balanced` (all sections), `Gaming`,
  `Privacy`, and `Minimal`. Composes with `-Skip`; `-Only` overrides.
- **Check-only mode** (`-CheckOnly`): analyze and score the system, then exit
  without making any changes, restore point, or undo file.
- **JSON report** (`report_YYYYMMDD_HHMMSS.json`) written next to the log with
  device profile, tier, preset, sections run, before/after scores, fix count,
  and duration.
- **Undo conveniences**: `-Undo Latest` restores the most recent run and
  `-ListUndo` lists available undo files.
- **Non-registry undo** (#2): service startup types, scheduled task states,
  optional feature states, the boot menu timeout, and optimizer-created
  registry keys are now captured and restorable.
- **Restore-point verification**: the run confirms a restore point actually
  exists and warns (rather than implying rollback) when System Protection is off.
- Pure, unit-tested helpers `Get-SystemTier`, `Get-PowerPlanName`, and
  `Get-OSBuildNumber`. Pester coverage expanded to 84 tests, including a
  DryRun no-mutation integration test and cleanup age-filter tests (#18).

### Fixed
- **Power plan name parsing**: modern `powercfg` prints the plan in
  parentheses, but the old regex expected quotes, so the active plan was always
  reported as "Unknown". This corrupted the analysis readout and the health
  score; both are now accurate.
- **Post-optimization score** is computed from a consistent schema (it no longer
  drops keys like `IsLaptop`), so before/after scores are comparable.
- **DryRun no longer inflates the fix counter** (#8): Privacy, Performance,
  Network, Security, Notifications, and BackgroundApps now gate their `[FIX]`
  output on DryRun.
- **Temp cleanup is safe** (#3, #28): only files older than 24h are removed, one
  file at a time (locked/in-use files are skipped instead of wedging Windows
  servicing), reparse points are skipped, freed-space totals are accurate, and
  the optimizer's own data directory is excluded.
- **Context-menu restoration is undoable** (#14): the Windows 11 classic
  context-menu key is recorded so rollback removes it.
- **NDU disable** targets `CurrentControlSet` instead of a hardcoded
  `ControlSet001` that could silently no-op.
- Undo entries are **de-duplicated**, preserving the genuine pre-run value when
  a key is written by more than one section; `Restore-FromUndoFile` validates
  JSON and fails gracefully instead of throwing.
- External tool failures (`fsutil`, `netsh`, `bcdedit`) are reported as skips
  rather than false successes.

### Changed
- **Windows Search Indexer (WSearch) is no longer disabled by default** (#20):
  Start Menu, File Explorer, Outlook, Teams, and OneNote all depend on it.
- **Fast Startup is skipped on dual-boot systems** and when hibernation is
  unavailable (#22), avoiding NTFS corruption and inert settings.
- `Set-RegValue` validates the registry value type before writing.
- Documentation corrected: log/report location, module map, and undo coverage.

### Security
- **run.ps1 no longer re-downloads on elevation** (#10): it downloads once and
  elevates the local copy, closing a time-of-check/time-of-use gap.
- **run.ps1 integrity** (#11): the installer prints the archive SHA256 and can
  fail closed against a pinned hash via `-ExpectedHash` or `$env:UWSO_SHA256`.

## [3.1] and earlier

See the Git history for the v3.x modular refactor, DryRun/Undo introduction,
and the initial release.
