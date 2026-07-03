BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot "..\modules"
    Import-Module (Join-Path $modulesPath "UI.psm1")       -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Config.psm1")   -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Services.psm1") -Force -DisableNameChecking

    $script:sampleServices = @(
        [pscustomobject]@{ Name = 'DiagTrack';   Desc = 'Connected User Experiences and Telemetry' }
        [pscustomobject]@{ Name = 'dmwappushsvc'; Desc = 'Device Management WAP Push' }
    )
}

Describe "Invoke-ServicesOptimization in DryRun" {
    # The module is already correct here: it prints [DRY] and continues before it
    # touches a service. This guards that against a regression, so a dry run can
    # never stop a service or count a fix. Stop-Service and Set-Service are mocked
    # so a real dry run can never reach the host even if the guard breaks.
    BeforeEach {
        Reset-FixCounter
        Set-DryRunMode $true
        Mock -ModuleName Services Stop-Service {}
        Mock -ModuleName Services Set-Service  {}
    }

    AfterAll {
        Set-DryRunMode $false
        Reset-FixCounter
    }

    It "Should not increment the fix counter" {
        Invoke-ServicesOptimization -Analysis @{ ServicesToDisable = $script:sampleServices } | Out-Null
        Get-FixCount | Should -Be 0
    }

    It "Should not stop or disable any service" {
        Invoke-ServicesOptimization -Analysis @{ ServicesToDisable = $script:sampleServices } | Out-Null
        Should -Invoke -ModuleName Services Stop-Service -Times 0
        Should -Invoke -ModuleName Services Set-Service  -Times 0
    }

    It "Should record a [DRY] line for each service" {
        Invoke-ServicesOptimization -Analysis @{ ServicesToDisable = $script:sampleServices } | Out-Null
        $joined = (Get-Report) -join "`n"
        $joined | Should -Match '\[DRY\]  Would disable service: .*DiagTrack'
        $joined | Should -Match '\[DRY\]  Would disable service: .*dmwappushsvc'
    }
}

Describe "Invoke-ServicesOptimization outside DryRun" {
    BeforeEach {
        Reset-FixCounter
        Set-DryRunMode $false
        Mock -ModuleName Services Stop-Service {}
        Mock -ModuleName Services Set-Service  {}
    }

    AfterAll {
        Reset-FixCounter
    }

    It "Should count one fix per service actually disabled" {
        Invoke-ServicesOptimization -Analysis @{ ServicesToDisable = $script:sampleServices } | Out-Null
        Get-FixCount | Should -Be $script:sampleServices.Count
        Should -Invoke -ModuleName Services Stop-Service -Times $script:sampleServices.Count
    }

    It "Should do nothing when the disable list is empty" {
        Invoke-ServicesOptimization -Analysis @{ ServicesToDisable = @() } | Out-Null
        Get-FixCount | Should -Be 0
        Should -Invoke -ModuleName Services Stop-Service -Times 0
    }
}
