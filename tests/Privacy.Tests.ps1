BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot "..\modules"
    Import-Module (Join-Path $modulesPath "UI.psm1")          -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "UndoManager.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Config.psm1")      -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Privacy.psm1")     -Force -DisableNameChecking
}

Describe "Invoke-PrivacyOptimization in DryRun" {
    # Issue #8: Privacy only writes registry values through Set-RegValue, which
    # already skips the write and prints a [DRY] line when DryRun is on. The
    # module must not also fire [FIX] lines, or a dry run claims fixes it never
    # made and the counter is wrong.
    BeforeEach {
        Reset-FixCounter
        Set-DryRunMode $true
    }

    AfterAll {
        Set-DryRunMode $false
        Reset-FixCounter
    }

    It "Should not increment the fix counter" {
        Invoke-PrivacyOptimization -Analysis @{} | Out-Null
        Get-FixCount | Should -Be 0
    }

    It "Should run without throwing" {
        { Invoke-PrivacyOptimization -Analysis @{} } | Should -Not -Throw
    }

    It "Should still record what it would do in the report log" {
        Invoke-PrivacyOptimization -Analysis @{} | Out-Null
        $report = Get-Report
        ($report -join "`n") | Should -Match '\[DRY\]  Would set .*AllowTelemetry'
    }
}
