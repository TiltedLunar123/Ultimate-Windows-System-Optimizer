BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot "..\modules"
    foreach ($m in @('UI','UndoManager','Config','Analysis','Cleanup','Services',
                     'Privacy','Network','Performance','Security','Explorer')) {
        Import-Module (Join-Path $modulesPath "$m.psm1") -Force -DisableNameChecking
    }
}

Describe "DryRun safety - no registry writes, no inflated fix counter" {
    # The single most important safety property for a destructive tool: when
    # DryRun is on, NOTHING should mutate the registry and the fix counter
    # must stay at zero (issue #8 - several modules used to emit [FIX] anyway).
    It "No section writes the registry or counts a fix in DryRun" {
        Mock -ModuleName Config Set-ItemProperty {}

        Set-DryRunMode $true
        Reset-FixCounter
        Clear-UndoEntry
        try {
            $a = @{
                IsLaptop = $false; TotalRAMGB = 8; SystemTier = "Mid-Range"
                OSBuild = "22000"; HasSSD = $true; HasHDD = $false
                ServicesToDisable = @(); Disks = @()
            }

            Invoke-CleanupOptimization        -Analysis $a | Out-Null
            Invoke-ServicesOptimization       -Analysis $a | Out-Null
            Invoke-PowerOptimization          -Analysis $a | Out-Null
            Invoke-VisualEffectsOptimization  -Analysis $a | Out-Null
            Invoke-PrivacyOptimization        -Analysis $a | Out-Null
            Invoke-NetworkOptimization        -Analysis $a | Out-Null
            Invoke-PerformanceOptimization    -Analysis $a | Out-Null
            Invoke-ExplorerOptimization       -Analysis $a | Out-Null
            Invoke-SSDOptimization            -Analysis $a | Out-Null
            Invoke-MemoryOptimization         -Analysis $a | Out-Null
            Invoke-ScheduledTasksOptimization -Analysis $a | Out-Null
            Invoke-ContextMenuOptimization    -Analysis $a | Out-Null
            Invoke-BootOptimization           -Analysis $a | Out-Null
            Invoke-DiskOptimization           -Analysis $a | Out-Null
            Invoke-FeaturesOptimization       -Analysis $a | Out-Null
            Invoke-NotificationsOptimization  -Analysis $a | Out-Null
            Invoke-BackgroundAppsOptimization -Analysis $a | Out-Null
            Invoke-SecurityOptimization       -Analysis $a | Out-Null

            Get-FixCount | Should -Be 0
            Should -Invoke -ModuleName Config Set-ItemProperty -Exactly -Times 0
        } finally {
            Set-DryRunMode $false
            Reset-FixCounter
            Clear-UndoEntry
        }
    }
}

Describe "Cleanup age filtering" {
    # Issue #3 / #28: only files older than the cutoff may be deleted, and the
    # delete is per-file so a locked/in-use file is skipped, not fatal.
    BeforeAll {
        $script:sandbox = Join-Path $env:TEMP "uwso_cleanup_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:sandbox -Force | Out-Null
    }
    AfterAll {
        Remove-Item -LiteralPath $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Deletes files older than the age threshold but keeps fresh ones" {
        $old = Join-Path $script:sandbox "old.tmp"
        $new = Join-Path $script:sandbox "new.tmp"
        "x" * 2048 | Out-File -LiteralPath $old -Encoding ascii
        "y" * 2048 | Out-File -LiteralPath $new -Encoding ascii
        # Backdate the "old" file two days.
        (Get-Item -LiteralPath $old).LastWriteTime = (Get-Date).AddDays(-2)

        $freed = Clear-OldFile -Path $script:sandbox -MinAgeHours 24

        Test-Path -LiteralPath $old | Should -Be $false
        Test-Path -LiteralPath $new | Should -Be $true
        $freed | Should -BeGreaterThan 0
    }

    It "Respects ExcludePaths" {
        $sub = Join-Path $script:sandbox "keep"
        New-Item -ItemType Directory -Path $sub -Force | Out-Null
        $protected = Join-Path $sub "protected.tmp"
        "z" * 2048 | Out-File -LiteralPath $protected -Encoding ascii
        (Get-Item -LiteralPath $protected).LastWriteTime = (Get-Date).AddDays(-5)

        Clear-OldFile -Path $script:sandbox -MinAgeHours 24 -ExcludePaths @($sub) | Out-Null

        Test-Path -LiteralPath $protected | Should -Be $true
    }
}
