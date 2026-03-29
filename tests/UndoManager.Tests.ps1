BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot "..\modules"
    Import-Module (Join-Path $modulesPath "UI.psm1")          -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "UndoManager.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $modulesPath "Config.psm1")      -Force -DisableNameChecking
}

Describe "Undo File Generation" {
    BeforeEach {
        Clear-UndoEntries
    }

    It "Should save registry state entries" {
        Save-RegistryState -Path "HKCU:\TestPath" -Name "TestName" -NewValue 1 -Type "DWord"
        $entries = Get-UndoEntries
        $entries.Count | Should -Be 1
        $entries[0].Path | Should -Be "HKCU:\TestPath"
        $entries[0].Name | Should -Be "TestName"
        $entries[0].NewValue | Should -Be 1
    }

    It "Should save multiple entries" {
        Save-RegistryState -Path "HKCU:\Path1" -Name "Name1" -NewValue 1
        Save-RegistryState -Path "HKCU:\Path2" -Name "Name2" -NewValue 0
        Save-RegistryState -Path "HKCU:\Path3" -Name "Name3" -NewValue "test" -Type "String"
        $entries = Get-UndoEntries
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
        Clear-UndoEntries
        $entries = Get-UndoEntries
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
}
