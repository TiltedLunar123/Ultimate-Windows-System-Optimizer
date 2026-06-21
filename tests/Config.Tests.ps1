BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot "..\modules"
    Import-Module (Join-Path $modulesPath "UI.psm1")     -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Config.psm1") -Force -DisableNameChecking
}

Describe "Test-RegPathAllowed" {
    # This is the allow-list that keeps Set-RegValue from writing anywhere
    # outside the standard registry hives. It is a security boundary, so the
    # accept and reject sides both need to be pinned down.
    It "Should accept each of the standard hive prefixes" {
        foreach ($p in @(
            'HKCU:\Software\Test',
            'HKLM:\SYSTEM\CurrentControlSet',
            'HKCR:\.txt',
            'HKU:\.DEFAULT',
            'HKCC:\Software')) {
            Test-RegPathAllowed -Path $p | Should -BeTrue -Because "$p is a real hive"
        }
    }

    It "Should match the prefix without caring about case" {
        Test-RegPathAllowed -Path 'hklm:\software\foo' | Should -BeTrue
        Test-RegPathAllowed -Path 'HkCu:\Software\Bar'  | Should -BeTrue
    }

    It "Should reject a hive name that is missing the colon-backslash" {
        Test-RegPathAllowed -Path 'HKLM\Software\Foo' | Should -BeFalse
    }

    It "Should reject the long-form hive names" {
        Test-RegPathAllowed -Path 'HKEY_LOCAL_MACHINE\Software' | Should -BeFalse
    }

    It "Should reject a plain filesystem path" {
        Test-RegPathAllowed -Path 'C:\Windows\System32' | Should -BeFalse
    }

    It "Should reject empty, whitespace, and null input" {
        Test-RegPathAllowed -Path ''    | Should -BeFalse
        Test-RegPathAllowed -Path '   ' | Should -BeFalse
        Test-RegPathAllowed -Path $null | Should -BeFalse
    }
}

Describe "Test-SectionEnabled" {
    # Drives the -Only / -Skip filtering. With neither switch every section
    # runs; -Only restricts to a set; -Skip removes from it; and -Only wins
    # when both are supplied.
    It "Should enable any section when neither Only nor Skip is given" {
        Test-SectionEnabled -SectionName 'Privacy' | Should -BeTrue
    }

    It "Should keep only the named sections when Only is set" {
        Test-SectionEnabled -SectionName 'Privacy' -Only @('Privacy', 'Network') | Should -BeTrue
        Test-SectionEnabled -SectionName 'Cleanup' -Only @('Privacy', 'Network') | Should -BeFalse
    }

    It "Should drop the named sections when Skip is set" {
        Test-SectionEnabled -SectionName 'Privacy' -Skip @('Privacy') | Should -BeFalse
        Test-SectionEnabled -SectionName 'Network' -Skip @('Privacy') | Should -BeTrue
    }

    It "Should let Only take precedence when both Only and Skip are given" {
        # Only is checked first, so Skip is ignored once Only is present.
        Test-SectionEnabled -SectionName 'Privacy' -Only @('Privacy') -Skip @('Privacy') | Should -BeTrue
        Test-SectionEnabled -SectionName 'Network' -Only @('Privacy') -Skip @('Network') | Should -BeFalse
    }
}

Describe "Constant section and bloat tables" {
    It "Should expose a non-empty, duplicate-free section list" {
        $sections = Get-ValidSectionList
        $sections.Count | Should -BeGreaterThan 0
        $sections | Should -Contain 'Privacy'
        $sections | Should -Contain 'Security'
        ($sections | Sort-Object -Unique).Count | Should -Be $sections.Count
    }

    It "Should give every bloat service a name and a description" {
        $services = Get-BloatServiceDefinition
        $services.Count | Should -BeGreaterThan 0
        foreach ($svc in $services) {
            $svc.Name | Should -Not -BeNullOrEmpty
            $svc.Desc | Should -Not -BeNullOrEmpty
        }
    }

    It "Should not list the same bloat service twice" {
        $names = (Get-BloatServiceDefinition).Name
        ($names | Sort-Object -Unique).Count | Should -Be $names.Count
    }

    It "Should point every scheduled-task entry at a Windows task path" {
        $tasks = Get-BloatScheduledTaskList
        $tasks.Count | Should -BeGreaterThan 0
        foreach ($t in $tasks) {
            $t | Should -BeLike '\Microsoft\Windows\*'
        }
    }

    It "Should return a non-empty feature list" {
        (Get-FeaturesToDisable).Count | Should -BeGreaterThan 0
    }
}

Describe "Dry-run state" {
    AfterEach {
        # Leave the flag the way the rest of the suite expects it.
        Set-DryRunMode -Enabled $false
    }

    It "Should round-trip the dry-run flag" {
        Set-DryRunMode -Enabled $true
        Get-DryRunMode | Should -BeTrue
        Set-DryRunMode -Enabled $false
        Get-DryRunMode | Should -BeFalse
    }
}

Describe "Get-OptimizerDataDir" {
    It "Should return a path that exists and can be written to" {
        $dir = Get-OptimizerDataDir
        $dir | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $dir | Should -BeTrue
        # The contract is a writable directory, so prove a probe file lands.
        $probe = Join-Path $dir (".uwso_test_" + [Guid]::NewGuid().ToString('N'))
        { Set-Content -LiteralPath $probe -Value 'x' -ErrorAction Stop } | Should -Not -Throw
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    }
}
