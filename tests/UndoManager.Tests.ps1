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
}

Describe "Undo File Restore" {
    It "Should fail gracefully with non-existent file" {
        { Restore-FromUndoFile -FilePath "C:\nonexistent\file.json" } | Should -Throw
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
