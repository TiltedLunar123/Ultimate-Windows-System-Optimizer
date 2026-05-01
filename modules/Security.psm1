# Security.psm1 - RDP, SMB, firewall, autorun

function Invoke-SecurityOptimization {
    param([hashtable]$Analysis)

    $null = $Analysis  # Used for interface consistency
    $DryRun = Get-DryRunMode

    Write-Host "`n    -- Security Hardening --" -ForegroundColor Cyan

    # Context-aware: don't disable Remote Desktop if an active RDP session is
    # detected. qwinsta output is localized (Active/Aktiv/Activo/...), so
    # parsing it by string breaks on non-English Windows. Prefer a CIM query
    # against Win32_LogonSession joined to Win32_LoggedOnUser, which uses
    # numeric LogonType values (10 = RemoteInteractive). Fall back to qwinsta
    # only if CIM fails entirely.
    $hasActiveRDP = $false
    try {
        $rdpLogons = Get-CimInstance -ClassName Win32_LogonSession -ErrorAction Stop |
            Where-Object { $_.LogonType -eq 10 }
        $hasActiveRDP = ($null -ne $rdpLogons -and @($rdpLogons).Count -gt 0)
    } catch {
        try {
            $rdpSessions = qwinsta 2>$null | Where-Object { $_ -match '^\s*rdp-tcp\S*\s+\S+\s+\d+\s+\S+' }
            $hasActiveRDP = ($null -ne $rdpSessions -and @($rdpSessions).Count -gt 0)
        } catch { $null = $_ }
    }

    if ($hasActiveRDP) {
        Write-Warn "Active RDP session detected - skipping Remote Desktop disable"
    } else {
        Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" "fDenyTSConnections" 1
        Write-Fix "Remote Desktop disabled (security)"
    }

    Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" "fAllowToGetHelp" 0
    Write-Fix "Remote Assistance disabled"

    Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "SMB1" 0
    Write-Fix "SMBv1 disabled (security)"

    if ($DryRun) {
        Write-Dry "Would verify Windows Firewall is enabled"
    } else {
        try {
            Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction Stop
            Write-Fix "Windows Firewall verified enabled"
        } catch {
            Write-Skip "Could not verify firewall status"
        }
    }

    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoDriveTypeAutoRun" 255
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" "DisableAutoplay" 1
    Write-Fix "AutoRun/AutoPlay disabled (prevents USB malware)"
}

Export-ModuleMember -Function Invoke-SecurityOptimization
