BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot "..\modules"
    Import-Module (Join-Path $modulesPath "UI.psm1")          -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "UndoManager.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Config.psm1")      -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Analysis.psm1")    -Force -DisableNameChecking
}

Describe "System Tier Classification" {
    It "Should classify High-End system (16GB+ RAM, 6+ cores)" {
        $results = @{
            TotalRAMGB = 32; CPUCores = 8; RAMUsedPct = 50;
            StartupItems = @(); TempSizeMB = 50; ServicesToDisable = @();
            TelemetryEnabled = $false; CurrentPowerPlan = "High performance";
            Disks = @(); VisualEffects = "Performance"
        }
        # Simulate tier logic
        if ($results.TotalRAMGB -ge 16 -and $results.CPUCores -ge 6) {
            $tier = "High-End"
        } elseif ($results.TotalRAMGB -ge 8 -and $results.CPUCores -ge 4) {
            $tier = "Mid-Range"
        } else {
            $tier = "Low-End"
        }
        $tier | Should -Be "High-End"
    }

    It "Should classify Mid-Range system (8GB RAM, 4 cores)" {
        $results = @{ TotalRAMGB = 8; CPUCores = 4 }
        if ($results.TotalRAMGB -ge 16 -and $results.CPUCores -ge 6) {
            $tier = "High-End"
        } elseif ($results.TotalRAMGB -ge 8 -and $results.CPUCores -ge 4) {
            $tier = "Mid-Range"
        } else {
            $tier = "Low-End"
        }
        $tier | Should -Be "Mid-Range"
    }

    It "Should classify Low-End system (4GB RAM, 2 cores)" {
        $results = @{ TotalRAMGB = 4; CPUCores = 2 }
        if ($results.TotalRAMGB -ge 16 -and $results.CPUCores -ge 6) {
            $tier = "High-End"
        } elseif ($results.TotalRAMGB -ge 8 -and $results.CPUCores -ge 4) {
            $tier = "Mid-Range"
        } else {
            $tier = "Low-End"
        }
        $tier | Should -Be "Low-End"
    }

    It "Should classify 16GB/4-core as Mid-Range (needs 6+ cores for High-End)" {
        $results = @{ TotalRAMGB = 16; CPUCores = 4 }
        if ($results.TotalRAMGB -ge 16 -and $results.CPUCores -ge 6) {
            $tier = "High-End"
        } elseif ($results.TotalRAMGB -ge 8 -and $results.CPUCores -ge 4) {
            $tier = "Mid-Range"
        } else {
            $tier = "Low-End"
        }
        $tier | Should -Be "Mid-Range"
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

    It "Should deduct points for Balanced power plan" {
        $results = @{
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
