BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot "..\modules"
    Import-Module (Join-Path $modulesPath "UI.psm1")          -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "UndoManager.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Config.psm1")      -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Security.psm1")    -Force -DisableNameChecking
}

Describe "Invoke-SecurityOptimization in DryRun" {
    # Issue #8: every registry change routes through Set-RegValue, which stages
    # the write and prints [DRY] when DryRun is on. The [FIX] lines have to be
    # gated the same way or a dry run reports fixes it never made. The RDP check
    # queries Win32_LogonSession, so it is mocked to return no remote session,
    # which keeps the run identical on any host (CI included).
    BeforeEach {
        Reset-FixCounter
        Set-DryRunMode $true
        Mock -ModuleName Security Get-CimInstance { @() }
    }

    AfterAll {
        Set-DryRunMode $false
        Reset-FixCounter
    }

    It "Should not increment the fix counter" {
        Invoke-SecurityOptimization -Analysis @{} | Out-Null
        Get-FixCount | Should -Be 0
    }

    It "Should run without throwing" {
        { Invoke-SecurityOptimization -Analysis @{} } | Should -Not -Throw
    }

    It "Should stage the Remote Desktop disable when no RDP session is active" {
        Invoke-SecurityOptimization -Analysis @{} | Out-Null
        $report = Get-Report
        ($report -join "`n") | Should -Match '\[DRY\]  Would set .*fDenyTSConnections'
    }
}
