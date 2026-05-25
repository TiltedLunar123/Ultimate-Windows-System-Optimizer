<#
.SYNOPSIS
    One-click installer and runner for Ultimate Windows System Optimizer.
    Downloads the optimizer ONCE to a local temp folder, optionally verifies
    its SHA256, then runs it - elevating to admin from the local copy rather
    than re-downloading.

.PARAMETER Auto
    Skip every confirmation prompt in the optimizer (passes -Force to the
    main script). Off by default; opt in only for unattended runs.

.PARAMETER ExpectedHash
    Expected SHA256 of the downloaded archive. When supplied, the run aborts
    if the download doesn't match. Can also be set via $env:UWSO_SHA256, since
    piping into iex strips parameters.

.DESCRIPTION
    Usage (paste into PowerShell):
        irm https://raw.githubusercontent.com/TiltedLunar123/Ultimate-Windows-System-Optimizer/main/run.ps1 | iex

    Hands-off run (no prompts):
        $env:UWSO_AUTO = '1'; irm .../run.ps1 | iex

    Pin a known-good build (recommended on shared/managed machines):
        $env:UWSO_SHA256 = '<hash printed on a trusted run>'; irm .../run.ps1 | iex

    SECURITY: this downloads code from the internet and elevates it to
    administrator. Review this script and the repository before running.
    The script prints the downloaded archive's SHA256 so you can record and
    pin it; supply that value via $env:UWSO_SHA256 to fail closed on tampering.
#>

param(
    [switch]$Auto,
    [string]$ExpectedHash
)

# Allow opt-in via env vars too, since piping into iex strips parameters.
if ($env:UWSO_AUTO -eq '1') { $Auto = $true }
if ([string]::IsNullOrWhiteSpace($ExpectedHash) -and $env:UWSO_SHA256) {
    $ExpectedHash = $env:UWSO_SHA256
}

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repoUrl = "https://github.com/TiltedLunar123/Ultimate-Windows-System-Optimizer/archive/refs/heads/main.zip"
$tempDir = Join-Path $env:TEMP "UWSO_$(Get-Random)"
$zipFile = "$tempDir.zip"

try {
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host "  |     ULTIMATE WINDOWS SYSTEM OPTIMIZER - INSTALLER        |" -ForegroundColor Cyan
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host ""

    # 1. Download once (no admin needed to fetch).
    Write-Host "  [1/4] Downloading optimizer..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $repoUrl -OutFile $zipFile -UseBasicParsing
    Write-Host "  [OK]  Downloaded successfully" -ForegroundColor Green

    # 2. Integrity check. Always print the hash; verify it if one was pinned.
    Write-Host "  [2/4] Verifying integrity..." -ForegroundColor Yellow
    $hash = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash
    Write-Host "  Archive SHA256: $hash" -ForegroundColor Gray
    if ($ExpectedHash) {
        if ($hash -ne $ExpectedHash.Trim()) {
            throw "SHA256 mismatch - expected '$ExpectedHash' but got '$hash'. Aborting."
        }
        Write-Host "  [OK]  Integrity verified against pinned hash" -ForegroundColor Green
    } else {
        Write-Host "  [..]  No pinned hash; set `$env:UWSO_SHA256 to fail closed on tampering" -ForegroundColor DarkGray
    }

    # 3. Extract.
    Write-Host "  [3/4] Extracting files..." -ForegroundColor Yellow
    Expand-Archive -Path $zipFile -DestinationPath $tempDir -Force
    $scriptDir = Get-ChildItem -Path $tempDir -Directory | Select-Object -First 1
    if (-not $scriptDir) { throw "Extraction produced no directory." }
    $mainScript = Join-Path $scriptDir.FullName "Ultimate-Windows-System-Optimizer.ps1"
    if (-not (Test-Path $mainScript)) { throw "Optimizer script not found after extraction." }
    Write-Host "  [OK]  Extracted to temp directory" -ForegroundColor Green

    # 4. Run the LOCAL copy, elevating if needed. We never re-download in the
    #    elevated shell - that re-fetch was a time-of-check/time-of-use gap
    #    where GitHub content could differ between the two downloads.
    Write-Host "  [4/4] Launching optimizer..." -ForegroundColor Yellow
    Write-Host ""

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $mainArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $mainScript)
    if ($Auto) { $mainArgs += "-Force" }

    if ($isAdmin) {
        powershell.exe @mainArgs
    } else {
        Write-Host "  Requesting administrator privileges (running the local copy)..." -ForegroundColor Yellow
        $proc = Start-Process powershell.exe -ArgumentList $mainArgs -Verb RunAs -PassThru
        # Wait so the temp copy isn't deleted out from under the elevated run.
        try { $proc.WaitForExit() } catch { $null = $_ }
    }

} catch {
    Write-Host ""
    Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Try downloading manually: https://github.com/TiltedLunar123/Ultimate-Windows-System-Optimizer" -ForegroundColor Yellow
    Write-Host ""
    pause
} finally {
    # Cleanup temp files
    Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
