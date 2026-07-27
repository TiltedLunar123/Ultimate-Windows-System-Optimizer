# Services.psm1 - Bloat service detection and disabling

function Invoke-ServicesOptimization {
    param([hashtable]$Analysis)

    $DryRun = Get-DryRunMode

    Write-Host "`n    -- Disabling Unnecessary Services --" -ForegroundColor Cyan

    if ($Analysis.ServicesToDisable.Count -gt 0) {
        foreach ($svc in $Analysis.ServicesToDisable) {
            # Record the current startup type and running state first, the same
            # way Set-RegValue stages a registry write. Issue #2: without this
            # the undo file had no idea any service had ever been touched.
            Save-ServiceState -Name $svc.Name -NewStartupType 'Disabled'

            if ($DryRun) {
                Write-Dry "Would disable service: $($svc.Desc) ($($svc.Name))"
                continue
            }
            try {
                Stop-Service -Name $svc.Name -Force -ErrorAction Stop
                Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction Stop
                Write-Fix "Disabled: $($svc.Desc)"
            } catch {
                Write-Skip "Could not disable $($svc.Name): $($_.Exception.Message)"
            }
        }
    } else {
        Write-Good "No unnecessary services to disable"
    }
}

Export-ModuleMember -Function Invoke-ServicesOptimization
