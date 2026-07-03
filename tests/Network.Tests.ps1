BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot "..\modules"
    Import-Module (Join-Path $modulesPath "UI.psm1")          -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "UndoManager.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Config.psm1")      -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Network.psm1")     -Force -DisableNameChecking
}

Describe "Invoke-NetworkOptimization in DryRun" {
    # Issue #8: the Nagle summary and the throttling line both called Write-Fix
    # even though every write is staged, not applied, under DryRun. The adapter
    # and interface reads are mocked so a physical adapter is always "found"
    # (that path is what fired the bogus Nagle fix) and the run never depends on
    # the host's real network stack. DNS flush and netsh only run outside DryRun,
    # so they are never reached here.
    BeforeEach {
        Reset-FixCounter
        Set-DryRunMode $true

        Mock -ModuleName Network Get-NetAdapter {
            [pscustomobject]@{
                InterfaceGuid = '{ABCD1234-5678-90AB-CDEF-1234567890AB}'
                Status        = 'Up'
                Virtual       = $false
            }
        }
        Mock -ModuleName Network Get-ChildItem {
            [pscustomobject]@{
                PSChildName = '{abcd1234-5678-90ab-cdef-1234567890ab}'
                PSPath      = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{abcd1234-5678-90ab-cdef-1234567890ab}'
            }
        }
    }

    AfterAll {
        Set-DryRunMode $false
        Reset-FixCounter
    }

    It "Should not increment the fix counter even when an adapter matches" {
        Invoke-NetworkOptimization -Analysis @{} | Out-Null
        Get-FixCount | Should -Be 0
    }

    It "Should run without throwing" {
        { Invoke-NetworkOptimization -Analysis @{} } | Should -Not -Throw
    }

    It "Should stage the throttling and Nagle keys" {
        Invoke-NetworkOptimization -Analysis @{} | Out-Null
        $joined = (Get-Report) -join "`n"
        $joined | Should -Match '\[DRY\]  Would set .*SystemResponsiveness'
        $joined | Should -Match '\[DRY\]  Would set .*TcpNoDelay'
    }
}
