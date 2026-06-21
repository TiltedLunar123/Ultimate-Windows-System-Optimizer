BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot "..\modules"
    Import-Module (Join-Path $modulesPath "UI.psm1") -Force -DisableNameChecking
}

Describe "Fix counter" {
    # Issue #8 was about this counter getting inflated by dry-run output. The
    # contract is simple: reset clears it, an applied fix bumps it, and a
    # second reset clears it again. Guard all three so a regression shows up.
    BeforeEach {
        Reset-FixCounter
    }

    It "Should start at zero after a reset" {
        Get-FixCount | Should -Be 0
    }

    It "Should count each applied fix once" {
        Write-Fix 'first change'  | Out-Null
        Write-Fix 'second change' | Out-Null
        Write-Fix 'third change'  | Out-Null
        Get-FixCount | Should -Be 3
    }

    It "Should return to zero on a fresh reset" {
        Write-Fix 'a change' | Out-Null
        Get-FixCount | Should -Be 1
        Reset-FixCounter
        Get-FixCount | Should -Be 0
    }
}

Describe "Report log" {
    # Log appends a timestamped line to the running report, and Get-Report
    # hands the whole thing back. The report accumulates across the suite, so
    # these assertions work off the delta rather than an absolute count.
    It "Should append a timestamped line for each Log call" {
        $before = (Get-Report).Count
        Log 'UWSO-UI-TEST-MARKER'
        $after = Get-Report
        $after.Count | Should -Be ($before + 1)
        $after[-1]   | Should -Match 'UWSO-UI-TEST-MARKER'
    }

    It "Should prefix log entries with an HH:mm:ss stamp" {
        Log 'stamp check'
        (Get-Report)[-1] | Should -Match '^\d{2}:\d{2}:\d{2} '
    }
}
