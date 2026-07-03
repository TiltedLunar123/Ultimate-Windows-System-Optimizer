# Privacy.psm1 - Telemetry, ads, tracking, content delivery, feedback

function Invoke-PrivacyOptimization {
    param([hashtable]$Analysis)

    $null = $Analysis  # Used for interface consistency
    Write-Host "`n    -- Privacy & Telemetry Hardening --" -ForegroundColor Cyan

    # Issue #8: Set-RegValue already prints a [DRY] line per key when DryRun is
    # on, so every [FIX] line here has to be gated the same way Explorer does it.
    # Otherwise a dry run reports fixes it never applied and inflates the counter.
    $isDry = Get-DryRunMode

    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0
    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" 0
    if (-not $isDry) { Write-Fix "Telemetry disabled" }

    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana" 0
    if (-not $isDry) { Write-Fix "Cortana disabled" }

    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0
    if (-not $isDry) { Write-Fix "Advertising ID disabled" }

    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" 0
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 0
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities" 0
    if (-not $isDry) { Write-Fix "Activity History disabled" }

    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" "DisableLocation" 1
    if (-not $isDry) { Write-Fix "Location tracking disabled" }

    Set-RegValue "HKCU:\Software\Microsoft\Siuf\Rules" "NumberOfSIUFInPeriod" 0
    Set-RegValue "HKCU:\Software\Microsoft\Siuf\Rules" "PeriodInNanoSeconds" 0
    if (-not $isDry) { Write-Fix "Feedback requests disabled" }

    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_TrackProgs" 0
    if (-not $isDry) { Write-Fix "App launch tracking disabled" }

    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" 0
    if (-not $isDry) { Write-Fix "Tailored experiences disabled" }

    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338389Enabled" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-310093Enabled" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338388Enabled" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SilentInstalledAppsEnabled" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SystemPaneSuggestionsEnabled" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SoftLandingEnabled" 0
    if (-not $isDry) { Write-Fix "Tips, suggestions, and silent app installs disabled" }
}

Export-ModuleMember -Function Invoke-PrivacyOptimization
