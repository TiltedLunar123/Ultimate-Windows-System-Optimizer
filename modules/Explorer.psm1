# Explorer.psm1 - Shell tweaks, context menu, file extensions, search

function Invoke-ExplorerOptimization {
    param([hashtable]$Analysis)

    $null = $Analysis  # Used for interface consistency
    Write-Host "`n    -- Explorer & UI Tweaks --" -ForegroundColor Cyan

    $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $isDry = Get-DryRunMode

    Set-RegValue $advPath "HideFileExt" 0
    if (-not $isDry) { Write-Fix "File extensions now visible" }

    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "CortanaConsent" 0
    if (-not $isDry) { Write-Fix "Web search in Start Menu disabled" }

    Set-RegValue "HKCU:\Control Panel\Desktop" "MenuShowDelay" "50" "String"
    if (-not $isDry) { Write-Fix "Menu animations sped up" }

    Set-RegValue $advPath "ShowRecent" 0
    Set-RegValue $advPath "ShowFrequent" 0
    if (-not $isDry) { Write-Fix "Recent and frequent items hidden" }

    Set-RegValue $advPath "LaunchTo" 1 "DWord"
    if (-not $isDry) { Write-Fix "Explorer opens to 'This PC' - faster navigation" }
}

function Invoke-ContextMenuOptimization {
    param([hashtable]$Analysis)

    Write-Host "`n    -- Shell & Context Menu Tweaks --" -ForegroundColor Cyan

    $isDry = Get-DryRunMode

    if ([int]$Analysis.OSBuild -ge 22000) {
        $ctxPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"

        # This used to call New-Item and Set-ItemProperty directly, which meant
        # the classic-menu key was the one change a run made that undo could not
        # reverse. Set-RegValue records the prior state first and owns the
        # dry-run branch, so the write now behaves like every other one here.
        if (Set-RegValue $ctxPath "(Default)" "" "String") {
            if (-not $isDry) { Write-Fix "Classic right-click context menu restored (Windows 11)" }
        } else {
            Write-Skip "Could not restore classic context menu"
        }
    }

    if (-not $isDry) { Write-Fix "Context menu cleaned" }
}

Export-ModuleMember -Function Invoke-ExplorerOptimization, Invoke-ContextMenuOptimization
