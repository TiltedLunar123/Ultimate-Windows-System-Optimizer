BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot "..\modules"
    Import-Module (Join-Path $modulesPath "UI.psm1")          -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "UndoManager.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Config.psm1")      -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Analysis.psm1")    -Force -DisableNameChecking
}

Describe "System Tier Classification" {
    # These call the real Get-SystemTier so the test fails if the product
    # logic changes - the previous version re-implemented the if/else inline.
    It "Should classify High-End system (16GB+ RAM, 6+ cores)" {
        Get-SystemTier -RamGB 32 -Cores 8 | Should -Be "High-End"
    }

    It "Should classify Mid-Range system (8GB RAM, 4 cores)" {
        Get-SystemTier -RamGB 8 -Cores 4 | Should -Be "Mid-Range"
    }

    It "Should classify Low-End system (4GB RAM, 2 cores)" {
        Get-SystemTier -RamGB 4 -Cores 2 | Should -Be "Low-End"
    }

    It "Should classify 16GB/4-core as Mid-Range (needs 6+ cores for High-End)" {
        Get-SystemTier -RamGB 16 -Cores 4 | Should -Be "Mid-Range"
    }
}

Describe "Get-PowerPlanName" {
    It "Should extract a parenthesized name (modern powercfg output)" {
        $out = "Power Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance)"
        Get-PowerPlanName $out | Should -Be "High performance"
    }

    It "Should extract a double-quoted name (legacy powercfg output)" {
        $out = 'Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  "Balanced"'
        Get-PowerPlanName $out | Should -Be "Balanced"
    }

    It "Should return Unknown when no name is present" {
        Get-PowerPlanName "no plan name here" | Should -Be "Unknown"
    }
}

Describe "Get-HealthScore hardening" {
    It "Should return 100 when optional keys (IsLaptop) are absent" {
        # The post-optimization re-score can pass a partial hashtable; a
        # missing key must not crash or wrongly deduct.
        $results = @{
            RAMUsedPct = 30; TempSizeMB = 10; TelemetryEnabled = $false
            CurrentPowerPlan = "High performance"; VisualEffects = "Performance"
        }
        Get-HealthScore -AnalysisResults $results | Should -Be 100
    }

    It "Should treat a single-element StartupItems collection as count 1" {
        $results = @{
            RAMUsedPct = 30; TempSizeMB = 10; ServicesToDisable = @()
            TelemetryEnabled = $false; CurrentPowerPlan = "High performance"
            Disks = @(); VisualEffects = "Performance"
            StartupItems = @{ Name = "OnlyOne" }
        }
        # One startup item is below every threshold, so the score stays 100.
        Get-HealthScore -AnalysisResults $results | Should -Be 100
    }
}

Describe "Health Score Calculation" {
    It "Should return 100 for a perfect system" {
        $results = @{
            RAMUsedPct        = 30
            StartupItems      = @()
            TempSizeMB        = 10
            ServicesToDisable  = @()
            TelemetryEnabled  = $false
            CurrentPowerPlan   = "High performance"
            Disks             = @(@{ Health = "HEALTHY" })
            VisualEffects      = "Performance"
        }
        $score = Get-HealthScore -AnalysisResults $results
        $score | Should -Be 100
    }

    It "Should deduct points for high RAM usage" {
        $results = @{
            RAMUsedPct        = 90
            StartupItems      = @()
            TempSizeMB        = 10
            ServicesToDisable  = @()
            TelemetryEnabled  = $false
            CurrentPowerPlan   = "High performance"
            Disks             = @(@{ Health = "HEALTHY" })
            VisualEffects      = "Performance"
        }
        $score = Get-HealthScore -AnalysisResults $results
        $score | Should -Be 85
    }

    It "Should deduct points for many startup items" {
        $items = 1..20 | ForEach-Object { @{ Name = "Item$_" } }
        $results = @{
            RAMUsedPct        = 30
            StartupItems      = $items
            TempSizeMB        = 10
            ServicesToDisable  = @()
            TelemetryEnabled  = $false
            CurrentPowerPlan   = "High performance"
            Disks             = @(@{ Health = "HEALTHY" })
            VisualEffects      = "Performance"
        }
        $score = Get-HealthScore -AnalysisResults $results
        $score | Should -Be 85
    }

    It "Should deduct points for bloated temp files" {
        $results = @{
            RAMUsedPct        = 30
            StartupItems      = @()
            TempSizeMB        = 600
            ServicesToDisable  = @()
            TelemetryEnabled  = $false
            CurrentPowerPlan   = "High performance"
            Disks             = @(@{ Health = "HEALTHY" })
            VisualEffects      = "Performance"
        }
        $score = Get-HealthScore -AnalysisResults $results
        $score | Should -Be 90
    }

    It "Should deduct points for telemetry enabled" {
        $results = @{
            RAMUsedPct        = 30
            StartupItems      = @()
            TempSizeMB        = 10
            ServicesToDisable  = @()
            TelemetryEnabled  = $true
            CurrentPowerPlan   = "High performance"
            Disks             = @(@{ Health = "HEALTHY" })
            VisualEffects      = "Performance"
        }
        $score = Get-HealthScore -AnalysisResults $results
        $score | Should -Be 95
    }

    It "Should deduct points for critical disk health" {
        $results = @{
            RAMUsedPct        = 30
            StartupItems      = @()
            TempSizeMB        = 10
            ServicesToDisable  = @()
            TelemetryEnabled  = $false
            CurrentPowerPlan   = "High performance"
            Disks             = @(@{ Health = "CRITICAL" })
            VisualEffects      = "Performance"
        }
        $score = Get-HealthScore -AnalysisResults $results
        $score | Should -Be 85
    }

    It "Should deduct points for Balanced power plan on a desktop" {
        $results = @{
            IsLaptop          = $false
            RAMUsedPct        = 30
            StartupItems      = @()
            TempSizeMB        = 10
            ServicesToDisable  = @()
            TelemetryEnabled  = $false
            CurrentPowerPlan   = "Balanced"
            Disks             = @(@{ Health = "HEALTHY" })
            VisualEffects      = "Performance"
        }
        $score = Get-HealthScore -AnalysisResults $results
        $score | Should -Be 90
    }

    It "Should not deduct points for Balanced power plan on a laptop" {
        $results = @{
            IsLaptop          = $true
            RAMUsedPct        = 30
            StartupItems      = @()
            TempSizeMB        = 10
            ServicesToDisable  = @()
            TelemetryEnabled  = $false
            CurrentPowerPlan   = "Balanced"
            Disks             = @(@{ Health = "HEALTHY" })
            VisualEffects      = "Performance"
        }
        $score = Get-HealthScore -AnalysisResults $results
        $score | Should -Be 100
    }

    It "Should not deduct points for Power saver on a laptop" {
        $results = @{
            IsLaptop          = $true
            RAMUsedPct        = 30
            StartupItems      = @()
            TempSizeMB        = 10
            ServicesToDisable  = @()
            TelemetryEnabled  = $false
            CurrentPowerPlan   = "Power saver"
            Disks             = @(@{ Health = "HEALTHY" })
            VisualEffects      = "Performance"
        }
        $score = Get-HealthScore -AnalysisResults $results
        $score | Should -Be 100
    }

    It "Should accumulate multiple deductions" {
        $items = 1..20 | ForEach-Object { @{ Name = "Item$_" } }
        $svcs = 1..6 | ForEach-Object { @{ Name = "Svc$_" } }
        $results = @{
            RAMUsedPct        = 90
            StartupItems      = $items
            TempSizeMB        = 600
            ServicesToDisable  = $svcs
            TelemetryEnabled  = $true
            CurrentPowerPlan   = "Balanced"
            Disks             = @(@{ Health = "CRITICAL" })
            VisualEffects      = "Auto"
        }
        $score = Get-HealthScore -AnalysisResults $results
        # -15 RAM, -15 startup, -10 temp, -10 services, -5 telemetry, -10 power, -15 disk, -5 visual = -85
        $score | Should -Be 15
    }

    It "Should not go below 0" {
        $items = 1..20 | ForEach-Object { @{ Name = "Item$_" } }
        $svcs = 1..6 | ForEach-Object { @{ Name = "Svc$_" } }
        $results = @{
            RAMUsedPct        = 90
            StartupItems      = $items
            TempSizeMB        = 600
            ServicesToDisable  = $svcs
            TelemetryEnabled  = $true
            CurrentPowerPlan   = "Balanced"
            Disks             = @(@{ Health = "CRITICAL" }, @{ Health = "CRITICAL" }, @{ Health = "CRITICAL" })
            VisualEffects      = "Auto"
        }
        $score = Get-HealthScore -AnalysisResults $results
        $score | Should -BeGreaterOrEqual 0
    }
}

Describe "Get-StartupItem" {
    It "Should be invocable and return enumerable output" {
        $items = @(Get-StartupItem)
        $items.GetType().IsArray | Should -Be $true
    }

    It "Each item should expose Name, Source, and Path keys" {
        $items = @(Get-StartupItem)
        foreach ($it in $items) {
            $it -is [hashtable]       | Should -Be $true
            $it.ContainsKey('Name')   | Should -Be $true
            $it.ContainsKey('Source') | Should -Be $true
            $it.ContainsKey('Path')   | Should -Be $true
        }
    }

    It "Source values should be one of the known origins" {
        $items = @(Get-StartupItem)
        $valid = @('Registry', 'StartupFolder', 'ScheduledTask')
        foreach ($it in $items) {
            $valid | Should -Contain $it.Source
        }
    }
}
