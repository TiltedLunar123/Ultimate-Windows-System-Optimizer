# Network.psm1 - Nagle, TCP, DNS, network throttling

function Invoke-NetworkOptimization {
    param([hashtable]$Analysis)

    $null = $Analysis  # Used for interface consistency
    $DryRun = Get-DryRunMode

    Write-Host "`n    -- Network Optimization --" -ForegroundColor Cyan

    # Build the set of NetCfgInstanceId GUIDs that belong to physical,
    # non-virtual adapters. Without this filter we also write the keys
    # under loopback, Hyper-V switches, and VPN adapters, where toggling
    # Nagle is at best pointless and at worst harmful (loopback latency
    # regressions, broken VPN MTU behavior).
    $physicalGuids = @{}
    try {
        Get-NetAdapter -Physical -ErrorAction Stop |
            Where-Object { $_.Status -ne 'Disabled' -and $_.Virtual -ne $true } |
            ForEach-Object {
                if ($_.InterfaceGuid) { $physicalGuids[$_.InterfaceGuid.ToLower()] = $true }
            }
    } catch {
        Log "[WARN] Get-NetAdapter unavailable; skipping Nagle tweaks: $_"
    }

    $applied = 0
    if ($physicalGuids.Count -gt 0) {
        $interfaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction SilentlyContinue
        foreach ($iface in $interfaces) {
            $guid = ($iface.PSChildName).ToLower()
            if (-not $physicalGuids.ContainsKey($guid)) { continue }
            Set-RegValue $iface.PSPath "TcpNoDelay" 1
            Set-RegValue $iface.PSPath "TcpAckFrequency" 1
            $applied++
        }
    }

    if ($applied -gt 0) {
        Write-Fix "Nagle's algorithm disabled on $applied physical adapter(s)"
    } else {
        Write-Skip "No eligible physical adapters; skipped Nagle tuning"
    }

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
