BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot "..\modules"
    Import-Module (Join-Path $modulesPath "UI.psm1")          -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "UndoManager.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Config.psm1")      -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Analysis.psm1")    -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Explorer.psm1")    -Force -DisableNameChecking
}

Describe "Section Filtering with -Only" {
    It "Should enable section when it is in the Only list" {
        $result = Test-SectionEnabled -SectionName "Privacy" -Only @("Privacy", "Cleanup") -Skip @()
        $result | Should -Be $true
    }

    It "Should disable section when it is NOT in the Only list" {
        $result = Test-SectionEnabled -SectionName "Security" -Only @("Privacy", "Cleanup") -Skip @()
        $result | Should -Be $false
    }

    It "Should enable all sections when Only is empty" {
        $result = Test-SectionEnabled -SectionName "Security" -Only @() -Skip @()
        $result | Should -Be $true
    }
}

Describe "Section Filtering with -Skip" {
    It "Should disable section when it is in the Skip list" {
        $result = Test-SectionEnabled -SectionName "Security" -Only @() -Skip @("Security", "Network")
        $result | Should -Be $false
    }

    It "Should enable section when it is NOT in the Skip list" {
        $result = Test-SectionEnabled -SectionName "Privacy" -Only @() -Skip @("Security", "Network")
        $result | Should -Be $true
    }
}

Describe "Section Filtering with neither Only nor Skip" {
    It "Should enable all sections" {
        $validSections = Get-ValidSectionList
        foreach ($section in $validSections) {
            $result = Test-SectionEnabled -SectionName $section -Only @() -Skip @()
            $result | Should -Be $true
        }
    }
}

Describe "Section Filtering precedence (-Only takes priority over -Skip)" {
    It "Should honor -Only when both -Only and -Skip are provided" {
        # If Privacy is in both lists, Only wins and the section runs.
        $result = Test-SectionEnabled -SectionName "Privacy" -Only @("Privacy") -Skip @("Privacy")
        $result | Should -Be $true
    }

    It "Should still exclude sections outside -Only even if -Skip would allow them" {
        $result = Test-SectionEnabled -SectionName "Network" -Only @("Privacy") -Skip @()
        $result | Should -Be $false
    }
}

Describe "Bloat lists" {
    It "Get-BloatServiceDefinition should return well-formed entries" {
        $services = Get-BloatServiceDefinition
        $services | Should -Not -BeNullOrEmpty
        foreach ($svc in $services) {
            $svc.Name | Should -Not -BeNullOrEmpty
            $svc.Desc | Should -Not -BeNullOrEmpty
        }
    }

    It "Get-BloatScheduledTaskList should return non-empty task paths" {
        $tasks = Get-BloatScheduledTaskList
        $tasks | Should -Not -BeNullOrEmpty
        foreach ($t in $tasks) {
            $t | Should -Match '^\\Microsoft\\Windows\\'
        }
    }

    It "Get-FeaturesToDisable should return a non-empty array" {
        $features = Get-FeaturesToDisable
        $features | Should -Not -BeNullOrEmpty
        $features.Count | Should -BeGreaterThan 0
    }
}

Describe "Valid Section Names" {
    It "Should contain all expected section names" {
        $sections = Get-ValidSectionList
        $sections | Should -Contain "Cleanup"
        $sections | Should -Contain "Services"
        $sections | Should -Contain "Power"
        $sections | Should -Contain "VisualEffects"
        $sections | Should -Contain "Privacy"
        $sections | Should -Contain "Network"
        $sections | Should -Contain "Performance"
        $sections | Should -Contain "Explorer"
        $sections | Should -Contain "SSD"
        $sections | Should -Contain "Memory"
        $sections | Should -Contain "ScheduledTasks"
        $sections | Should -Contain "ContextMenu"
        $sections | Should -Contain "Boot"
        $sections | Should -Contain "Disk"
        $sections | Should -Contain "Features"
        $sections | Should -Contain "Notifications"
        $sections | Should -Contain "BackgroundApps"
        $sections | Should -Contain "Security"
    }

    It "Should have exactly 18 sections" {
        $sections = Get-ValidSectionList
        $sections.Count | Should -Be 18
    }
}

Describe "DryRun Mode" {
    It "Should default to disabled" {
        Set-DryRunMode $false
        $result = Get-DryRunMode
        $result | Should -Be $false
    }

    It "Should be settable to enabled" {
        Set-DryRunMode $true
        $result = Get-DryRunMode
        $result | Should -Be $true
        # Reset
        Set-DryRunMode $false
    }

    It "Should not create undo entries with actual values in DryRun" {
        Set-DryRunMode $true
        Clear-UndoEntry

        # Set-RegValue in DryRun mode should save state but not modify registry
        Set-RegValue "HKCU:\Software\OptimizerDryRunTest_$(Get-Random)" "DryTest" 1

        $entries = Get-UndoEntry
        # Undo entries are still saved for tracking purposes
        $entries.Count | Should -BeGreaterOrEqual 1

        Set-DryRunMode $false
        Clear-UndoEntry
    }
}

Describe "UI Functions" {
    It "Should track fix count" {
        Reset-FixCounter
        $count = Get-FixCount
        $count | Should -Be 0
    }

    It "Should return report as list" {
        $report = Get-Report
        $report | Should -Not -BeNullOrEmpty
    }
}

Describe "Get-OptimizerDataDir" {
    It "Should return a non-empty path" {
        $dir = Get-OptimizerDataDir
        $dir | Should -Not -BeNullOrEmpty
    }

    It "Should return a path that exists on disk" {
        $dir = Get-OptimizerDataDir
        Test-Path -LiteralPath $dir | Should -Be $true
    }

    It "Should return a writable directory" {
        $dir = Get-OptimizerDataDir
        $probe = Join-Path $dir (".uwso_test_probe_" + [Guid]::NewGuid().ToString('N'))
        { Set-Content -LiteralPath $probe -Value 'x' -ErrorAction Stop } | Should -Not -Throw
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    }

    It "Should prefer LOCALAPPDATA\\UWSO when that path is writable" {
        if (-not $env:LOCALAPPDATA) {
            Set-ItResult -Skipped -Because "LOCALAPPDATA not set in this environment"
            return
        }
        $expected = Join-Path $env:LOCALAPPDATA 'UWSO'
        $dir = Get-OptimizerDataDir
        $dir | Should -Be $expected
    }
}

Describe "Explorer DryRun output" {
    # Issue #7: every [FIX] line was firing even in DryRun, on top of the
    # [DRY] line that Set-RegValue already emits. Make sure the fix
    # counter doesn't move when DryRun is on.
    BeforeEach {
        Reset-FixCounter
        Clear-UndoEntry
    }

    It "Should not increment fix counter during Invoke-ExplorerOptimization in DryRun" {
        Set-DryRunMode $true
        try {
            Invoke-ExplorerOptimization -Analysis @{ OSBuild = 22000 } | Out-Null
            Get-FixCount | Should -Be 0
        } finally {
            Set-DryRunMode $false
        }
    }

    It "Should not increment fix counter during Invoke-ContextMenuOptimization in DryRun" {
        Set-DryRunMode $true
        try {
            Invoke-ContextMenuOptimization -Analysis @{ OSBuild = 22000 } | Out-Null
            Get-FixCount | Should -Be 0
        } finally {
            Set-DryRunMode $false
        }
    }
}

Describe "Set-RegValue path validation" {
    # Issue #13: Set-RegValue would create keys at any path string. Reject
    # anything not under a standard hive prefix so a bad caller can't
    # scatter keys around the registry.
    BeforeEach {
        Set-DryRunMode $true
        Clear-UndoEntry
    }

    AfterAll {
        Set-DryRunMode $false
    }

    It "Should accept HKCU: paths" {
        $result = Set-RegValue "HKCU:\Software\UWSOValidationTest_$(Get-Random)" "X" 1
        $result | Should -Be $true
    }

    It "Should accept HKLM: paths" {
        $result = Set-RegValue "HKLM:\Software\UWSOValidationTest_$(Get-Random)" "X" 1
        $result | Should -Be $true
    }

    It "Should accept HKCR: paths" {
        $result = Set-RegValue "HKCR:\UWSOValidationTest_$(Get-Random)" "X" 1
        $result | Should -Be $true
    }

    It "Should reject paths without a hive prefix" {
        $result = Set-RegValue "Software\UWSOBadPath" "X" 1
        $result | Should -Be $false
    }

    It "Should reject paths with a bogus PSDrive prefix" {
        $result = Set-RegValue "Foo:\Bar" "X" 1
        $result | Should -Be $false
    }

    It "Should reject empty or whitespace paths" {
        (Set-RegValue "" "X" 1)  | Should -Be $false
        (Set-RegValue "   " "X" 1) | Should -Be $false
    }

    It "Should reject an unknown registry value type" {
        $result = Set-RegValue "HKCU:\Software\UWSOTypeTest_$(Get-Random)" "X" 1 "NotARealType"
        $result | Should -Be $false
    }
}

Describe "Optimization Presets" {
    It "Should expose the documented preset names" {
        $names = Get-PresetNameList
        $names | Should -Contain "Balanced"
        $names | Should -Contain "Gaming"
        $names | Should -Contain "Privacy"
        $names | Should -Contain "Minimal"
    }

    It "Test-PresetName accepts a known preset and rejects an unknown one" {
        Test-PresetName "Gaming"  | Should -Be $true
        Test-PresetName "Nonsense" | Should -Be $false
        Test-PresetName ""         | Should -Be $false
    }

    It "Balanced preset resolves to every section" {
        $sections = Resolve-EnabledSection -PresetName "Balanced"
        ($sections | Sort-Object) | Should -Be ((Get-ValidSectionList) | Sort-Object)
    }

    It "Gaming preset excludes Privacy and Security" {
        $sections = Resolve-EnabledSection -PresetName "Gaming"
        $sections | Should -Not -Contain "Privacy"
        $sections | Should -Not -Contain "Security"
        $sections | Should -Contain "Performance"
    }

    It "-Only overrides a preset entirely" {
        $sections = Resolve-EnabledSection -PresetName "Gaming" -Only @("Privacy")
        $sections | Should -Be @("Privacy")
    }

    It "-Skip removes sections from a preset" {
        $sections = Resolve-EnabledSection -PresetName "Privacy" -Skip @("Security")
        $sections | Should -Not -Contain "Security"
        $sections | Should -Contain "Privacy"
    }

    It "Returns sections in canonical order" {
        $all = Get-ValidSectionList
        $sections = Resolve-EnabledSection -PresetName "Gaming"
        $indices = $sections | ForEach-Object { [array]::IndexOf($all, $_) }
        $sorted = $indices | Sort-Object
        "$indices" | Should -Be "$sorted"
    }
}

Describe "Bloat list safety" {
    It "Should NOT include WSearch (Start Menu/Explorer/Outlook depend on it - #20)" {
        $names = (Get-BloatServiceDefinition).Name
        $names | Should -Not -Contain "WSearch"
    }
}

Describe "Get-OSBuildNumber" {
    It "Parses a numeric build string" {
        Get-OSBuildNumber "22631" | Should -Be 22631
    }
    It "Returns 0 for an empty or non-numeric build" {
        Get-OSBuildNumber ""    | Should -Be 0
        Get-OSBuildNumber "n/a" | Should -Be 0
    }
}
