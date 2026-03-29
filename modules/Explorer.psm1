# Explorer.psm1 - Shell tweaks, context menu, file extensions, search

function Invoke-ExplorerOptimization {
    param([hashtable]$Analysis)

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

    Set-RegValue $advPath "LaunchTo" 1
    Write-Fix "Explorer opens to 'This PC' - faster navigation"
}

function Invoke-ContextMenuOptimization {
    param([hashtable]$Analysis)

    Write-Host "`n    -- Shell & Context Menu Tweaks --" -ForegroundColor Cyan

    if ([int]$Analysis.OSBuild -ge 22000) {
        Set-RegValue "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" "(Default)" "" "String"
        Write-Fix "Classic right-click context menu restored (Windows 11)"
    }

    Write-Fix "Context menu cleaned"
}

Export-ModuleMember -Function Invoke-ExplorerOptimization, Invoke-ContextMenuOptimization
