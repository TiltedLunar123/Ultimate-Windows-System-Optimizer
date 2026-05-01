# Explorer.psm1 - Shell tweaks, context menu, file extensions, search

function Invoke-ExplorerOptimization {
    param([hashtable]$Analysis)

    $null = $Analysis  # Used for interface consistency
    Write-Host "`n    -- Explorer & UI Tweaks --" -ForegroundColor Cyan

    $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    Set-RegValue $advPath "HideFileExt" 0
    Write-Fix "File extensions now visible"

    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "CortanaConsent" 0
    Write-Fix "Web search in Start Menu disabled"

    Set-RegValue "HKCU:\Control Panel\Desktop" "MenuShowDelay" "50" "String"
    Write-Fix "Menu animations sped up"

    Set-RegValue $advPath "ShowRecent" 0
    Set-RegValue $advPath "ShowFrequent" 0
    Write-Fix "Recent and frequent items hidden"

    Set-RegValue $advPath "LaunchTo" 1 "DWord"
    Write-Fix "Explorer opens to 'This PC' - faster navigation"
}

function Invoke-ContextMenuOptimization {
    param([hashtable]$Analysis)

    Write-Host "`n    -- Shell & Context Menu Tweaks --" -ForegroundColor Cyan

    if ([int]$Analysis.OSBuild -ge 22000) {
        $ctxPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
        if (Get-DryRunMode) {
            Write-Dry "Would restore classic right-click context menu"
        } else {
            try {
                if (-not (Test-Path $ctxPath)) { New-Item -Path $ctxPath -Force | Out-Null }
                Set-ItemProperty -Path $ctxPath -Name "(Default)" -Value "" -Force
                Write-Fix "Classic right-click context menu restored (Windows 11)"
            } catch {
                Write-Skip "Could not restore classic context menu"
                Log "[ERROR] Context menu restore: $_"
            }
        }
    }

    Write-Fix "Context menu cleaned"
}

Export-ModuleMember -Function Invoke-ExplorerOptimization, Invoke-ContextMenuOptimization
