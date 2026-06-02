BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot "..\modules"
    Import-Module (Join-Path $modulesPath "UI.psm1")      -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Config.psm1")  -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Cleanup.psm1") -Force -DisableNameChecking
}

Describe "Get-CleanupMinAgeHour" {
    # Issue #3: temp cleanup needs a floor so files from the active session
    # are not deleted out from under it.
    It "Should return a positive whole number of hours" {
        $h = Get-CleanupMinAgeHour
        $h | Should -BeOfType [int]
        $h | Should -BeGreaterThan 0
    }
}

Describe "Select-AgedItem" {
    # Issue #3 / #28: only files older than the window are eligible for
    # deletion. These run against synthetic objects so nothing touches disk.
    BeforeEach {
        $script:ref = Get-Date "2026-06-02T12:00:00"
    }

    It "Should keep an item older than the window" {
        $old = [pscustomobject]@{ FullName = 'old.tmp'; LastWriteTime = $script:ref.AddHours(-48) }
        $result = Select-AgedItem -Item @($old) -MinAgeHour 24 -ReferenceTime $script:ref
        $result.Count | Should -Be 1
        $result[0].FullName | Should -Be 'old.tmp'
    }

    It "Should drop an item newer than the window" {
        $fresh = [pscustomobject]@{ FullName = 'fresh.tmp'; LastWriteTime = $script:ref.AddHours(-1) }
        $result = Select-AgedItem -Item @($fresh) -MinAgeHour 24 -ReferenceTime $script:ref
        $result.Count | Should -Be 0
    }

    It "Should split a mixed set, keeping only the aged files" {
        $items = @(
            [pscustomobject]@{ FullName = 'a'; LastWriteTime = $script:ref.AddHours(-72) }
            [pscustomobject]@{ FullName = 'b'; LastWriteTime = $script:ref.AddHours(-2)  }
            [pscustomobject]@{ FullName = 'c'; LastWriteTime = $script:ref.AddHours(-25) }
        )
        $result = Select-AgedItem -Item $items -MinAgeHour 24 -ReferenceTime $script:ref
        ($result | ForEach-Object FullName) | Should -Be @('a', 'c')
    }

    It "Should treat an item exactly at the cutoff as still in use (not deleted)" {
        # cutoff is strict (<), so a file at precisely 24h is kept.
        $edge = [pscustomobject]@{ FullName = 'edge'; LastWriteTime = $script:ref.AddHours(-24) }
        $result = Select-AgedItem -Item @($edge) -MinAgeHour 24 -ReferenceTime $script:ref
        $result.Count | Should -Be 0
    }

    It "Should return an empty array for empty input" {
        $result = Select-AgedItem -Item @() -MinAgeHour 24 -ReferenceTime $script:ref
        $result.Count | Should -Be 0
    }

    It "Should return an empty array for null input" {
        $result = Select-AgedItem -Item $null -MinAgeHour 24 -ReferenceTime $script:ref
        $result.Count | Should -Be 0
    }

    It "Should tolerate a negative age window the same as its absolute value" {
        $old = [pscustomobject]@{ FullName = 'old'; LastWriteTime = $script:ref.AddHours(-48) }
        $result = Select-AgedItem -Item @($old) -MinAgeHour -24 -ReferenceTime $script:ref
        $result.Count | Should -Be 1
    }
}
