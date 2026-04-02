<#
.SYNOPSIS
    One-click installer and runner for Ultimate Windows System Optimizer.
    Downloads, extracts, and runs the optimizer automatically with admin privileges.

.DESCRIPTION
    Usage (paste into PowerShell):
        irm https://raw.githubusercontent.com/TiltedLunar123/Ultimate-Windows-System-Optimizer/main/run.ps1 | iex
#>

# Self-elevate to admin if not already
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "`n  Requesting administrator privileges..." -ForegroundColor Yellow
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(
        "Set-ExecutionPolicy Bypass -Scope Process -Force; irm https://raw.githubusercontent.com/TiltedLunar123/Ultimate-Windows-System-Optimizer/main/run.ps1 | iex"
    ))
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" -Verb RunAs
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
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mainScript -Force

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
