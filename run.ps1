<#
.SYNOPSIS
    One-click installer and runner for Ultimate Windows System Optimizer.
    Downloads, extracts, and runs the optimizer automatically with admin privileges.

.PARAMETER Auto
    Skip every confirmation prompt in the optimizer (passes -Force to the
    main script). Off by default; opt in only for unattended runs.

.PARAMETER ExpectedCommit
    Full or short commit SHA you expect main to be at. When supplied, the
    installer resolves the current commit first and stops if it does not
    match, so you can pin a revision you have already read.

.DESCRIPTION
    Usage (paste into PowerShell):
        irm https://raw.githubusercontent.com/TiltedLunar123/Ultimate-Windows-System-Optimizer/main/run.ps1 | iex

    Hands-off run (no prompts):
        $env:UWSO_AUTO = '1'; irm .../run.ps1 | iex

    Pinned to a commit you have reviewed:
        $env:UWSO_COMMIT = 'a1b2c3d'; irm .../run.ps1 | iex

    This script downloads and runs code as administrator. Nothing about that
    is verifiable from inside the script itself, so it does the next best
    things: it resolves the exact commit main points at, downloads that
    commit rather than a moving branch tip, prints the commit SHA and the
    SHA-256 of the archive it fetched, and lets you refuse anything that is
    not the revision you expected. See the security section of the README.
#>

param(
    [switch]$Auto,
    [string]$ExpectedCommit
)

# Allow opt-in via env var too, since piping into iex strips parameters
if ($env:UWSO_AUTO -eq '1') { $Auto = $true }
if (-not $ExpectedCommit -and $env:UWSO_COMMIT) { $ExpectedCommit = $env:UWSO_COMMIT }

# Raw URL of this bootstrap script. Only used as a fallback for the case where
# run.ps1 was piped straight into the shell (irm ... | iex) and so has no
# on-disk copy to re-run when it elevates.
$RunScriptUrl = "https://raw.githubusercontent.com/TiltedLunar123/Ultimate-Windows-System-Optimizer/main/run.ps1"
$RepoSlug = "TiltedLunar123/Ultimate-Windows-System-Optimizer"

function Get-RepositoryArchiveUrl {
    # Pin the download to one commit when we know it. A branch tip can move
    # between the moment somebody reads the source and the moment the zip
    # lands, and the archive endpoint happily serves whatever is newest.
    param([string]$CommitSha)

    if ([string]::IsNullOrWhiteSpace($CommitSha)) {
        return "https://github.com/$RepoSlug/archive/refs/heads/main.zip"
    }
    return "https://github.com/$RepoSlug/archive/$CommitSha.zip"
}

function Get-CurrentCommitSha {
    # Ask the API what main points at right now. Returns $null if the call
    # fails; the caller falls back to the branch tip and says so out loud.
    param([string]$Branch = "main")

    try {
        $headers = @{ 'Accept' = 'application/vnd.github+json'; 'User-Agent' = 'UWSO-Installer' }
        $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$RepoSlug/commits/$Branch" `
            -Headers $headers -UseBasicParsing -ErrorAction Stop
        if ($response -and $response.sha) { return [string]$response.sha }
        return $null
    } catch {
        return $null
    }
}

function Test-CommitMatch {
    # Accept a short SHA so people can paste the seven characters GitHub shows
    # them. Comparison is prefix-based and case-insensitive, and an expectation
    # that cannot be checked (no resolved SHA) is a failure, not a pass.
    param(
        [string]$Expected,
        [string]$Actual
    )

    if ([string]::IsNullOrWhiteSpace($Expected)) { return $true }
    if ([string]::IsNullOrWhiteSpace($Actual)) { return $false }

    $e = $Expected.Trim()
    if ($e.Length -lt 7) { return $false }
    return $Actual.StartsWith($e, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-FileSha256 {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
    } catch {
        return $null
    }
}

function Get-ElevationArgumentString {
    # Build the powershell.exe argument string used to relaunch this installer
    # with admin rights. Issue #10: when run.ps1 already exists on disk, re-run
    # that exact file with -File so the elevated process runs the same code the
    # user looked at, with no second network fetch. Fall back to re-downloading
    # only when there is no local copy (the irm | iex one-liner).
    param(
        [string]$LocalScriptPath,
        [switch]$Auto,
        [string]$ExpectedCommit
    )

    if ($LocalScriptPath -and (Test-Path -LiteralPath $LocalScriptPath)) {
        $argString = "-NoProfile -ExecutionPolicy Bypass -File `"$LocalScriptPath`""
        if ($Auto) { $argString += " -Auto" }
        if ($ExpectedCommit) { $argString += " -ExpectedCommit `"$ExpectedCommit`"" }
        return $argString
    }

    $autoEnv = if ($Auto) { "`$env:UWSO_AUTO = '1'; " } else { "" }
    $commitEnv = if ($ExpectedCommit) { "`$env:UWSO_COMMIT = '$ExpectedCommit'; " } else { "" }
    $command = "Set-ExecutionPolicy Bypass -Scope Process -Force; ${autoEnv}${commitEnv}irm $RunScriptUrl | iex"
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
    $elevationArgs = Get-ElevationArgumentString -LocalScriptPath $PSCommandPath -Auto:$Auto -ExpectedCommit $ExpectedCommit
    Start-Process powershell.exe -ArgumentList $elevationArgs -Verb RunAs
    return
}

Set-ExecutionPolicy Bypass -Scope Process -Force
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$tempDir = Join-Path $env:TEMP "UWSO_$(Get-Random)"
$zipFile = "$tempDir.zip"

try {
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host "  |     ULTIMATE WINDOWS SYSTEM OPTIMIZER - INSTALLER        |" -ForegroundColor Cyan
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host ""

    # Resolve which commit we are about to run before fetching anything.
    $commitSha = Get-CurrentCommitSha -Branch 'main'

    if ($ExpectedCommit) {
        if (-not (Test-CommitMatch -Expected $ExpectedCommit -Actual $commitSha)) {
            $seen = if ($commitSha) { $commitSha } else { "unknown (could not reach the GitHub API)" }
            throw "Commit mismatch. You asked for '$ExpectedCommit' but main is at $seen. Nothing was downloaded."
        }
        Write-Host "  [OK]  Commit matches the one you pinned" -ForegroundColor Green
    }

    $repoUrl = Get-RepositoryArchiveUrl -CommitSha $commitSha
    if ($commitSha) {
        Write-Host "  Commit:  $commitSha" -ForegroundColor DarkGray
        Write-Host "  Review:  https://github.com/$RepoSlug/commit/$commitSha" -ForegroundColor DarkGray
    } else {
        Write-Host "  [WARN] Could not resolve the current commit, falling back to the branch tip." -ForegroundColor Yellow
    }
    Write-Host ""

    # Download
    Write-Host "  [1/3] Downloading optimizer..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $repoUrl -OutFile $zipFile -UseBasicParsing
    $zipHash = Get-FileSha256 -Path $zipFile
    Write-Host "  [OK]  Downloaded successfully" -ForegroundColor Green
    if ($zipHash) {
        Write-Host "  Archive SHA-256: $zipHash" -ForegroundColor DarkGray
    }

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
