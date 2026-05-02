# Network.psm1 - Nagle, TCP, DNS, network throttling

function Invoke-NetworkOptimization {
    param([hashtable]$Analysis)

    $null = $Analysis  # Used for interface consistency
    $DryRun = Get-DryRunMode

    Write-Host "`n    -- Network Optimization --" -ForegroundColor Cyan

    $interfaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction SilentlyContinue
    foreach ($iface in $interfaces) {
        Set-RegValue $iface.PSPath "TcpNoDelay" 1
        Set-RegValue $iface.PSPath "TcpAckFrequency" 1
    }
    Write-Fix "Nagle's algorithm disabled (lower latency)"

    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" 0xFFFFFFFF
    # SystemResponsiveness is the % CPU MMCSS reserves for background system
    # tasks. 0 starves audio scheduling and timer interrupts; Microsoft's
    # guidance is 10-20%. 10 keeps gaming/network priority high without
    # crippling background work.
    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness" 10
    Write-Fix "Network throttling disabled (SystemResponsiveness=10)"

    Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" "MaxCacheTtl" 86400
    Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" "MaxNegativeCacheTtl" 5

    if ($DryRun) {
        Write-Dry "Would flush DNS cache"
        Write-Dry "Would set TCP auto-tuning and ECN"
    } else {
        try {
            Clear-DnsClientCache -ErrorAction Stop
            Write-Fix "DNS cache flushed and optimized"
        } catch {
            Write-Skip "Could not flush DNS cache"
        }

        netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
        netsh int tcp set global ecncapability=enabled 2>&1 | Out-Null
        Write-Fix "TCP auto-tuning and ECN optimized"
    }
}

Export-ModuleMember -Function Invoke-NetworkOptimization
