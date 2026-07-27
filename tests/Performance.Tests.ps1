BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot "..\modules"
    Import-Module (Join-Path $modulesPath "UI.psm1")          -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "UndoManager.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Config.psm1")      -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Performance.psm1") -Force -DisableNameChecking

    # Analysis that steers each function into its registry-writing branch:
    # a low-end tier for visual effects, a modern build for throttling and
    # GPU scheduling, an SSD present, and enough RAM for the memory path.
    $script:Analysis = @{
        IsLaptop   = $false
        OSBuild    = 22631
        SystemTier = 'Low-End'
        HasSSD     = $true
        HasHDD     = $false
        TotalRAMGB = 16
    }
}

Describe "Performance module honors DryRun (issue #8)" {
    # The eight functions that write registry values through Set-RegValue.
    # Set-RegValue already stages the write and prints a [DRY] line when
    # DryRun is on, so none of these should also fire a [FIX] line or the
    # applied-fixes counter ends up higher than the work actually done.
    $dryCases = @(
        @{ Name = 'Invoke-PowerOptimization' }
        @{ Name = 'Invoke-VisualEffectsOptimization' }
        @{ Name = 'Invoke-PerformanceOptimization' }
        @{ Name = 'Invoke-SSDOptimization' }
        @{ Name = 'Invoke-MemoryOptimization' }
        @{ Name = 'Invoke-BootOptimization' }
        @{ Name = 'Invoke-BackgroundAppsOptimization' }
        @{ Name = 'Invoke-NotificationsOptimization' }
    )

    BeforeEach {
        Reset-FixCounter
        Set-DryRunMode $true
    }

    AfterAll {
        Set-DryRunMode $false
        Reset-FixCounter
    }

    It "<Name> leaves the fix counter at zero in dry run" -ForEach $dryCases {
        & $Name -Analysis $script:Analysis | Out-Null
        Get-FixCount | Should -Be 0
    }

    It "<Name> runs without throwing in dry run" -ForEach $dryCases {
        { & $Name -Analysis $script:Analysis } | Should -Not -Throw
    }

    It "still records the staged writes in the report log" {
        Invoke-BackgroundAppsOptimization -Analysis $script:Analysis | Out-Null
        $report = Get-Report
        ($report -join "`n") | Should -Match '\[DRY\]  Would set .*GlobalUserDisabled'
    }
}

Describe "Performance module still counts fixes in a real run" {
    # The dry-run guard must not suppress [FIX] when DryRun is off. Set-RegValue
    # is mocked here so the assertion stays on the counter and never touches the
    # real registry. Only functions whose counting path is Set-RegValue plus
    # Write-Fix are used, so no powercfg/fsutil/bcdedit call is involved.
    BeforeEach {
        Reset-FixCounter
        Set-DryRunMode $false
        Mock -ModuleName Performance Set-RegValue { $true }
    }

    AfterAll {
        Reset-FixCounter
    }

    It "Invoke-BackgroundAppsOptimization counts its fix when applied for real" {
        Invoke-BackgroundAppsOptimization -Analysis $script:Analysis | Out-Null
        Get-FixCount | Should -Be 1
    }

    It "Invoke-NotificationsOptimization counts its fix when applied for real" {
        Invoke-NotificationsOptimization -Analysis $script:Analysis | Out-Null
        Get-FixCount | Should -Be 1
    }
}

Describe "Dual-boot detection (issue #22)" {
    # Trimmed but structurally real bcdedit output. The Windows-only sample
    # matters as much as the dual-boot one: \Windows\system32\winload.efi and
    # \EFI\Microsoft\Boot\bootmgfw.efi must not trip the foreign-loader match.
    BeforeAll {
        $script:WindowsOnlyBcd = @"
Windows Boot Manager
--------------------
identifier              {bootmgr}
device                  partition=\Device\HarddiskVolume1
path                    \EFI\Microsoft\Boot\bootmgfw.efi
description             Windows Boot Manager

Windows Boot Loader
-------------------
identifier              {current}
device                  partition=C:
path                    \Windows\system32\winload.efi
description             Windows 11
"@

        $script:DualBootBcd = $script:WindowsOnlyBcd + @"

Firmware Application (101fffff)
-------------------------------
identifier              {7619dcc8-fafe-11d9-b411-000476eba25f}
device                  partition=\Device\HarddiskVolume1
path                    \EFI\ubuntu\shimx64.efi
description             ubuntu
"@
    }

    It "returns false when only Windows entries are present" {
        Mock -ModuleName Performance Get-BootConfigurationText { $script:WindowsOnlyBcd }
        Test-DualBootSystem | Should -BeFalse
    }

    It "returns true when a non-Windows loader is in the boot menu" {
        Mock -ModuleName Performance Get-BootConfigurationText { $script:DualBootBcd }
        Test-DualBootSystem | Should -BeTrue
    }

    It "returns null when bcdedit could not be read" {
        Mock -ModuleName Performance Get-BootConfigurationText { "Access is denied." }
        Test-DualBootSystem | Should -BeNullOrEmpty
    }

    It "returns null on empty output" {
        Mock -ModuleName Performance Get-BootConfigurationText { "" }
        Test-DualBootSystem | Should -BeNullOrEmpty
    }
}

Describe "Fast Startup respects the dual-boot check (issue #22)" {
    BeforeEach {
        Clear-UndoEntry
        Reset-FixCounter
        Set-DryRunMode $true
    }

    AfterAll {
        Set-DryRunMode $false
        Clear-UndoEntry
        Reset-FixCounter
    }

    It "stages HiberbootEnabled on a Windows-only machine" {
        Mock -ModuleName Performance Test-DualBootSystem { $false }
        Invoke-BootOptimization -Analysis $script:Analysis | Out-Null
        $entries = Get-UndoEntry
        @($entries | Where-Object { $_.Name -eq 'HiberbootEnabled' }).Count | Should -Be 1
    }

    It "does not touch HiberbootEnabled when a second OS is detected" {
        Mock -ModuleName Performance Test-DualBootSystem { $true }
        Invoke-BootOptimization -Analysis $script:Analysis | Out-Null
        $entries = Get-UndoEntry
        @($entries | Where-Object { $_.Name -eq 'HiberbootEnabled' }).Count | Should -Be 0
    }

    It "says why it skipped on a dual-boot machine" {
        Mock -ModuleName Performance Test-DualBootSystem { $true }
        Invoke-BootOptimization -Analysis $script:Analysis | Out-Null
        $report = Get-Report
        ($report -join "`n") | Should -Match '\[SKIP\] Fast Startup left off'
    }

    It "leaves the setting alone when the boot config is unreadable" {
        Mock -ModuleName Performance Test-DualBootSystem { $null }
        Invoke-BootOptimization -Analysis $script:Analysis | Out-Null
        $entries = Get-UndoEntry
        @($entries | Where-Object { $_.Name -eq 'HiberbootEnabled' }).Count | Should -Be 0
        $report = Get-Report
        ($report -join "`n") | Should -Match '\[SKIP\] Fast Startup left alone'
    }

    It "still applies the other boot tweaks either way" {
        Mock -ModuleName Performance Test-DualBootSystem { $true }
        Invoke-BootOptimization -Analysis $script:Analysis | Out-Null
        $entries = Get-UndoEntry
        @($entries | Where-Object { $_.Name -eq 'VerboseStatus' }).Count | Should -Be 1
    }
}
