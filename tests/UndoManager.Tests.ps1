BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot "..\modules"
    Import-Module (Join-Path $modulesPath "UI.psm1")          -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "UndoManager.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Config.psm1")      -Force -DisableNameChecking
}

Describe "Undo File Generation" {
    BeforeEach {
        Import-Module (Join-Path $modulesPath "UndoManager.psm1") -Force -DisableNameChecking
        Clear-UndoEntry
    }

    It "Should save registry state entries" {
        Save-RegistryState -Path "HKCU:\TestPath" -Name "TestName" -NewValue 1 -Type "DWord"
        $entries = Get-UndoEntry
        $entries.Count | Should -Be 1
        $entries[0].Path | Should -Be "HKCU:\TestPath"
        $entries[0].Name | Should -Be "TestName"
        $entries[0].NewValue | Should -Be 1
    }

    It "Should save multiple entries" {
        Save-RegistryState -Path "HKCU:\Path1" -Name "Name1" -NewValue 1
        Save-RegistryState -Path "HKCU:\Path2" -Name "Name2" -NewValue 0
        Save-RegistryState -Path "HKCU:\Path3" -Name "Name3" -NewValue "test" -Type "String"
        $entries = Get-UndoEntry
        $entries.Count | Should -Be 3
    }

    It "Should export undo file as JSON" {
        Save-RegistryState -Path "HKCU:\TestPath" -Name "TestName" -NewValue 42
        $tempDir = $env:TEMP
        $filePath = Export-UndoFile -OutputDir $tempDir
        $filePath | Should -Not -BeNullOrEmpty
        Test-Path $filePath | Should -Be $true

        $content = Get-Content $filePath -Raw | ConvertFrom-Json
        $content.Count | Should -BeGreaterOrEqual 1
        $content[0].Path | Should -Be "HKCU:\TestPath"

        # Cleanup
        Remove-Item $filePath -Force -ErrorAction SilentlyContinue
    }

    It "Should return null when no entries exist" {
        $filePath = Export-UndoFile -OutputDir $env:TEMP
        $filePath | Should -BeNullOrEmpty
    }

    It "Should clear entries" {
        Save-RegistryState -Path "HKCU:\Path1" -Name "Name1" -NewValue 1
        Clear-UndoEntry
        $entries = Get-UndoEntry
        $entries.Count | Should -Be 0
    }

    It "Should record only the first-seen value when the same key is saved twice" {
        Save-RegistryState -Path "HKCU:\Dup" -Name "N" -NewValue 1
        Save-RegistryState -Path "HKCU:\Dup" -Name "N" -NewValue 2
        $entries = Get-UndoEntry
        $entries.Count | Should -Be 1
        $entries[0].NewValue | Should -Be 1
    }

    It "Should record a registry KEY state for key-presence tweaks" {
        Save-RegistryKeyState -Path "HKCU:\Software\UWSOKeyTest_$(Get-Random)"
        $entries = Get-UndoEntry
        $entries.Count | Should -Be 1
        $entries[0].Kind | Should -Be "RegistryKey"
        $entries[0].ContainsKey('Existed') | Should -Be $true
    }
}

Describe "Undo File Restore" {
    It "Should fail gracefully (return false, not throw) with a non-existent file" {
        # A throw here would fail the test; we also assert the graceful $false.
        # 3>$null suppresses the expected warning stream.
        $result = Restore-FromUndoFile -FilePath "C:\nonexistent\file.json" 3>$null
        $result | Should -Be $false
    }

    It "Should return false on malformed JSON" {
        $bad = Join-Path $env:TEMP "uwso_bad_$(Get-Random).json"
        "{ this is not valid json " | Out-File -FilePath $bad -Encoding UTF8
        try {
            Restore-FromUndoFile -FilePath $bad | Should -Be $false
        } finally {
            Remove-Item $bad -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should coerce a single-entry (non-array) undo file without throwing" {
        $single = Join-Path $env:TEMP "uwso_single_$(Get-Random).json"
        $testPath = "HKCU:\Software\UWSOSingle_$(Get-Random)"
        ([pscustomobject]@{
            Kind = "Registry"; Path = $testPath; Name = "V"; NewValue = 1
            OldValue = $null; Type = "DWord"; Existed = $false; IsBase64 = $false
        }) | ConvertTo-Json | Out-File -FilePath $single -Encoding UTF8
        try {
            { Restore-FromUndoFile -FilePath $single } | Should -Not -Throw
        } finally {
            Remove-Item $single -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should remove a key we created (RegistryKey, Existed=false) on restore" {
        $key = "HKCU:\Software\UWSOKeyRestore_$(Get-Random)"
        New-Item -Path $key -Force | Out-Null
        $file = Join-Path $env:TEMP "uwso_key_$(Get-Random).json"
        @( @{ Kind = "RegistryKey"; Path = $key; Existed = $false } ) |
            ConvertTo-Json | Out-File -FilePath $file -Encoding UTF8
        try {
            Restore-FromUndoFile -FilePath $file | Out-Null
            Test-Path $key | Should -Be $false
        } finally {
            Remove-Item $key -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $file -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should read and process a valid undo file" {
        $tempFile = Join-Path $env:TEMP "test_undo_$(Get-Random).json"
        $data = @(
            @{
                Path     = "HKCU:\Software\OptimizerTest_$(Get-Random)"
                Name     = "TestValue"
                NewValue = 1
                OldValue = $null
                Type     = "DWord"
                Existed  = $false
                IsBase64 = $false
            }
        )
        $data | ConvertTo-Json -Depth 5 | Out-File $tempFile -Encoding UTF8

        # Should not throw
        $result = Restore-FromUndoFile -FilePath $tempFile
        $result | Should -BeOfType [bool]

        # Cleanup
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }

    It "Should preserve the registry value type when restoring (String stays String)" {
        $testPath = "HKCU:\Software\UWSOTestRestore_$(Get-Random)"
        $tempFile = Join-Path $env:TEMP "test_undo_type_$(Get-Random).json"

        # Pre-create a String value so Existed = true and OldValue is the string.
        New-Item -Path $testPath -Force | Out-Null
        Set-ItemProperty -Path $testPath -Name "MyVal" -Value "original" -Type String -Force

        $data = @(
            @{
                Path     = $testPath
                Name     = "MyVal"
                NewValue = "changed"
                OldValue = "original"
                Type     = "String"
                Existed  = $true
                IsBase64 = $false
            }
        )
        $data | ConvertTo-Json -Depth 5 | Out-File $tempFile -Encoding UTF8

        # Simulate optimizer overwriting it as a different type.
        Set-ItemProperty -Path $testPath -Name "MyVal" -Value 0 -Type DWord -Force

        Restore-FromUndoFile -FilePath $tempFile | Out-Null

        $kind = (Get-Item -Path $testPath).GetValueKind("MyVal")
        $kind | Should -Be "String"
        (Get-ItemProperty -Path $testPath -Name "MyVal")."MyVal" | Should -Be "original"

        Remove-Item -Path $testPath -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }

    It "Should default to DWord when an older undo file has no Type field" {
        $testPath = "HKCU:\Software\UWSOTestRestore_$(Get-Random)"
        $tempFile = Join-Path $env:TEMP "test_undo_legacy_$(Get-Random).json"

        New-Item -Path $testPath -Force | Out-Null

        # Legacy entry: no Type field at all.
        $data = @(
            [pscustomobject]@{
                Path     = $testPath
                Name     = "LegacyVal"
                NewValue = 1
                OldValue = 0
                Existed  = $true
                IsBase64 = $false
            }
        )
        $data | ConvertTo-Json -Depth 5 | Out-File $tempFile -Encoding UTF8

        Restore-FromUndoFile -FilePath $tempFile | Out-Null

        $kind = (Get-Item -Path $testPath).GetValueKind("LegacyVal")
        $kind | Should -Be "DWord"

        Remove-Item -Path $testPath -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

Describe "Non-registry undo restore (mocked - no host changes)" {
    It "Should restore a Service entry via Set-Service" {
        Mock -ModuleName UndoManager Set-Service {}
        Mock -ModuleName UndoManager Start-Service {}
        $file = Join-Path $env:TEMP "uwso_svc_$(Get-Random).json"
        @( @{ Kind = "Service"; Name = "Fax"; OldStartType = "Manual"; WasRunning = $false } ) |
            ConvertTo-Json | Out-File -FilePath $file -Encoding UTF8
        try {
            Restore-FromUndoFile -FilePath $file | Should -Be $true
            Should -Invoke -ModuleName UndoManager Set-Service -Times 1
        } finally {
            Remove-Item $file -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should restore a ScheduledTask entry via Enable-ScheduledTask" {
        Mock -ModuleName UndoManager Enable-ScheduledTask {}
        $file = Join-Path $env:TEMP "uwso_task_$(Get-Random).json"
        @( @{ Kind = "ScheduledTask"; TaskPath = "\Microsoft\Windows\Foo\"; TaskName = "Bar" } ) |
            ConvertTo-Json | Out-File -FilePath $file -Encoding UTF8
        try {
            Restore-FromUndoFile -FilePath $file | Should -Be $true
            Should -Invoke -ModuleName UndoManager Enable-ScheduledTask -Times 1
        } finally {
            Remove-Item $file -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should restore a Feature entry via Enable-WindowsOptionalFeature" {
        Mock -ModuleName UndoManager Enable-WindowsOptionalFeature {}
        $file = Join-Path $env:TEMP "uwso_feat_$(Get-Random).json"
        @( @{ Kind = "Feature"; FeatureName = "WindowsMediaPlayer" } ) |
            ConvertTo-Json | Out-File -FilePath $file -Encoding UTF8
        try {
            Restore-FromUndoFile -FilePath $file | Should -Be $true
            Should -Invoke -ModuleName UndoManager Enable-WindowsOptionalFeature -Times 1
        } finally {
            Remove-Item $file -Force -ErrorAction SilentlyContinue
        }
    }
}
