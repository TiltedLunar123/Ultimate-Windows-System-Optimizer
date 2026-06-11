<#
.SYNOPSIS
    One-click installer and runner for Ultimate Windows System Optimizer.
    Downloads, extracts, and runs the optimizer automatically with admin privileges.

.PARAMETER Auto
    Skip every confirmation prompt in the optimizer (passes -Force to the
    main script). Off by default; opt in only for unattended runs.

.DESCRIPTION
    Usage (paste into PowerShell):
        irm https://raw.githubusercontent.com/TiltedLunar123/Ultimate-Windows-System-Optimizer/main/run.ps1 | iex

    Hands-off run (no prompts):
        $env:UWSO_AUTO = '1'; irm .../run.ps1 | iex
#>

param(
    [switch]$Auto
)

# Allow opt-in via env var too, since piping into iex strips parameters
if ($env:UWSO_AUTO -eq '1') { $Auto = $true }

# Raw URL of this bootstrap script. Only used as a fallback for the case where
# run.ps1 was piped straight into the shell (irm ... | iex) and so has no
# on-disk copy to re-run when it elevates.
$RunScriptUrl = "https://raw.githubusercontent.com/TiltedLunar123/Ultimate-Windows-System-Optimizer/main/run.ps1"

function Get-ElevationArgumentString {
    # Build the powershell.exe argument string used to relaunch this installer
    # with admin rights. Issue #10: when run.ps1 already exists on disk, re-run
    # that exact file with -File so the elevated process runs the same code the
    # user looked at, with no second network fetch. Fall back to re-downloading
    # only when there is no local copy (the irm | iex one-liner).
    param(
        [string]$LocalScriptPath,
        [switch]$Auto
    )

    if ($LocalScriptPath -and (Test-Path -LiteralPath $LocalScriptPath)) {
        $argString = "-NoProfile -ExecutionPolicy Bypass -File `"$LocalScriptPath`""
        if ($Auto) { $argString += " -Auto" }
        return $argString
    }

    $autoEnv = if ($Auto) { "`$env:UWSO_AUTO = '1'; " } else { "" }
    $command = "Set-ExecutionPolicy Bypass -Scope Process -Force; ${autoEnv}irm $RunScriptUrl | iex"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    return "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
}

# Tests dot-source this file to exercise Get-ElevationArgumentString without kicking
# off a real install (which self-elevates and downloads). Real entry points -
# irm | iex, -File, & ./run.ps1 - never set InvocationName to '.'.
if ($MyInvocation.InvocationName -eq '.') { return }

# Self-elevate to admin if not already
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "`n  Requesting administrator privileges..." -ForegroundColor Yellow
    $elevationArgs = Get-ElevationArgumentString -LocalScriptPath $PSCommandPath -Auto:$Auto
    Start-Process powershell.exe -ArgumentList $elevationArgs -Verb RunAs
    return
}

Set-ExecutionPolicy Bypass -Scope Process -Force
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

    # Download
    Write-Host "  [1/3] Downloading optimizer..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $repoUrl -OutFile $zipFile -UseBasicParsing
    Write-Host "  [OK]  Downloaded successfully" -ForegroundColor Green

    # Extract
    Write-Host "  [2/3] Extracting files..." -ForegroundColor Yellow
    Expand-Archive -Path $zipFile -DestinationPath $tempDir -Force
    $scriptDir = Get-ChildItem -Path $tempDir -Directory | Select-Object -First 1
    Write-Host "  [OK]  Extracted to temp directory" -ForegroundColor Green

    # Run
    Write-Host "  [3/3] Launching optimizer..." -ForegroundColor Yellow
    Write-Host ""

    $mainScript = Join-Path $scriptDir.FullName "Ultimate-Windows-System-Optimizer.ps1"
    $mainArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $mainScript)
    if ($Auto) { $mainArgs += "-Force" }
    powershell.exe @mainArgs

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
