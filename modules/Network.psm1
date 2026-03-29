# Network.psm1 - Nagle, TCP, DNS, network throttling

function Invoke-NetworkOptimization {
    param([hashtable]$Analysis)

    $DryRun = Get-DryRunMode

    Write-Host "`n    -- Network Optimization --" -ForegroundColor Cyan

    $interfaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction SilentlyContinue
    foreach ($iface in $interfaces) {
        Set-RegValue $iface.PSPath "TcpNoDelay" 1
        Set-RegValue $iface.PSPath "TcpAckFrequency" 1
    }
    Write-Fix "Nagle's algorithm disabled (lower latency)"

    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" 0xFFFFFFFF
    Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness" 0
    Write-Fix "Network throttling disabled"

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
