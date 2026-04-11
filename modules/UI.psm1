# UI.psm1 - Visual output helpers, logging, and user interaction

$script:Report = [System.Collections.Generic.List[string]]::new()

function Write-Banner {
    Clear-Host
    $banner = @"

    ============================================================
    |     ULTIMATE WINDOWS SYSTEM OPTIMIZER                    |
    |         Smart Analysis & Tuning Engine v3.1              |
    ============================================================

"@
    Write-Host $banner -ForegroundColor Cyan
}

function Write-Section ([string]$Title) {
    $line = "=" * 60
    Write-Host "`n  +${line}+" -ForegroundColor DarkCyan
    Write-Host "  |  $($Title.PadRight(58))|" -ForegroundColor DarkCyan
    Write-Host "  +${line}+" -ForegroundColor DarkCyan
    Log "=== $Title ==="
}

function Write-Status ([string]$Message, [string]$Status, [string]$Color = "White") {
    $pad = 50 - $Message.Length
    if ($pad -lt 1) { $pad = 1 }
    Write-Host "    $Message$(' ' * $pad)" -NoNewline
    Write-Host "[$Status]" -ForegroundColor $Color
}

function Write-Info ([string]$Label, [string]$Value) {
    Write-Host "    $($Label.PadRight(28))" -NoNewline -ForegroundColor Gray
    Write-Host "$Value" -ForegroundColor White
}

function Write-Good ([string]$Msg) {
    Write-Host "    [OK]   $Msg" -ForegroundColor Green
    Log "[OK]   $Msg"
}

function Write-Warn ([string]$Msg) {
    Write-Host "    [WARN] $Msg" -ForegroundColor Yellow
    Log "[WARN] $Msg"
}

function Write-Bad ([string]$Msg) {
    Write-Host "    [FAIL] $Msg" -ForegroundColor Red
    Log "[BAD]  $Msg"
}

function Write-Fix ([string]$Msg) {
    Write-Host "    [FIX]  $Msg" -ForegroundColor Magenta
    Log "[FIX]  $Msg"
    $script:TotalFixesApplied++
}

function Write-Skip ([string]$Msg) {
    Write-Host "    [SKIP] $Msg" -ForegroundColor DarkGray
    Log "[SKIP] $Msg"
}

function Write-Dry ([string]$Msg) {
    Write-Host "    [DRY]  $Msg" -ForegroundColor DarkYellow
    Log "[DRY]  $Msg"
}

function Log ([string]$Msg) {
    $script:Report.Add("$(Get-Date -Format 'HH:mm:ss') $Msg")
}

function Confirm-Action ([string]$Prompt) {
    Write-Host ""
    Write-Host "    $Prompt" -ForegroundColor Yellow -NoNewline
    Write-Host " (Y/N): " -NoNewline
    $r = Read-Host
    return ($r -match '^[Yy]')
}

function Get-Report {
    return $script:Report
}

function Reset-FixCounter {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (-not $PSCmdlet.ShouldProcess("FixCounter", "Reset")) { return }
    $script:TotalFixesApplied = 0
}

function Get-FixCount {
    return $script:TotalFixesApplied
}

# Initialize counter
$script:TotalFixesApplied = 0

Export-ModuleMember -Function Write-Banner, Write-Section, Write-Status, Write-Info,
    Write-Good, Write-Warn, Write-Bad, Write-Fix, Write-Skip, Write-Dry,
    Log, Confirm-Action, Get-Report, Reset-FixCounter, Get-FixCount
