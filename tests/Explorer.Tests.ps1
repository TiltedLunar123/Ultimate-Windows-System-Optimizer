BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot "..\modules"
    Import-Module (Join-Path $modulesPath "UI.psm1")          -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "UndoManager.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Config.psm1")      -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Explorer.psm1")    -Force -DisableNameChecking

    $script:ClassicMenuKey = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
}

Describe "Context menu restore is undoable (issue #14)" {
    # The classic-menu key used to be written with New-Item and Set-ItemProperty,
    # which skipped Save-RegistryState entirely. A user who ran the optimizer and
    # then ran the undo got everything back except their context menu. Dry run is
    # on throughout so nothing here touches the real registry.
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

    It "records the classic menu key in the undo list on Windows 11" {
        Invoke-ContextMenuOptimization -Analysis @{ OSBuild = 22621 } | Out-Null
        $entries = @(Get-UndoEntry)
        $match = $entries | Where-Object { $_.Path -eq $script:ClassicMenuKey -and $_.Name -eq '(Default)' }
        @($match).Count | Should -Be 1
    }

    It "saves it as a String so restore writes the right value type" {
        Invoke-ContextMenuOptimization -Analysis @{ OSBuild = 22621 } | Out-Null
        $entry = @(Get-UndoEntry) | Where-Object { $_.Path -eq $script:ClassicMenuKey } | Select-Object -First 1
        $entry.Type | Should -Be 'String'
    }

    It "leaves the key alone on Windows 10, where the tweak does not apply" {
        Invoke-ContextMenuOptimization -Analysis @{ OSBuild = 19045 } | Out-Null
        $entries = @(Get-UndoEntry)
        ($entries | Where-Object { $_.Path -eq $script:ClassicMenuKey }) | Should -BeNullOrEmpty
    }

    It "does not count a fix in dry run" {
        Invoke-ContextMenuOptimization -Analysis @{ OSBuild = 22621 } | Out-Null
        Get-FixCount | Should -Be 0
    }
}

Describe "Context menu restore in a real run" {
    BeforeEach {
        Clear-UndoEntry
        Reset-FixCounter
        Set-DryRunMode $false
        Mock -ModuleName Explorer Set-RegValue { $true }
    }

    AfterAll {
        Clear-UndoEntry
        Reset-FixCounter
    }

    It "reports the restore when the write succeeds" {
        Invoke-ContextMenuOptimization -Analysis @{ OSBuild = 22621 } | Out-Null
        $report = Get-Report
        ($report -join "`n") | Should -Match 'Classic right-click context menu restored'
    }

    It "reports a skip instead when the write fails" {
        Mock -ModuleName Explorer Set-RegValue { $false }
        Invoke-ContextMenuOptimization -Analysis @{ OSBuild = 22621 } | Out-Null
        $report = Get-Report
        ($report -join "`n") | Should -Match '\[SKIP\] Could not restore classic context menu'
    }
}
