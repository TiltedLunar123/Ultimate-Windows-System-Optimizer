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
