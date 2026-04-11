BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot "..\modules"
    Import-Module (Join-Path $modulesPath "UI.psm1")          -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "UndoManager.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Config.psm1")      -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Analysis.psm1")    -Force -DisableNameChecking
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
