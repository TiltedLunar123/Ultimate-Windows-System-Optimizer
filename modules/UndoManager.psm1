# UndoManager.psm1 - Save and restore registry state for rollback

$script:UndoEntries = [System.Collections.Generic.List[hashtable]]::new()

function Save-RegistryState {
    param(
        [string]$Path,
        [string]$Name,
        $NewValue,
        [string]$Type = "DWord"
    )

    $entry = @{
        Path     = $Path
        Name     = $Name
        NewValue = $NewValue
        Type     = $Type
        OldValue = $null
        Existed  = $false
    }

    try {
        if (Test-Path $Path) {
            $current = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $current) {
                $entry.OldValue = $current.$Name
                $entry.Existed = $true
            }
        }
    } catch {
        $null = $_  # Key or value doesn't exist yet - that's fine
    }

    $script:UndoEntries.Add($entry)
}

function Export-UndoFile {
    param(
        [string]$OutputDir = "$env:USERPROFILE\Desktop"
    )

    if ($script:UndoEntries.Count -eq 0) {
        return $null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $filePath = Join-Path $OutputDir "undo_$timestamp.json"

    # Convert to serializable format
    $exportData = @()
    foreach ($e in $script:UndoEntries) {
        $exportData += @{
            Path     = $e.Path
            Name     = $e.Name
            NewValue = if ($e.NewValue -is [byte[]]) { [Convert]::ToBase64String($e.NewValue) } else { $e.NewValue }
            Type     = $e.Type
            OldValue = if ($e.OldValue -is [byte[]]) { [Convert]::ToBase64String($e.OldValue) } else { $e.OldValue }
            Existed  = $e.Existed
            IsBase64 = ($e.OldValue -is [byte[]] -or $e.NewValue -is [byte[]])
        }
    }

    $exportData | ConvertTo-Json -Depth 5 | Out-File -FilePath $filePath -Encoding UTF8 -Force
    return $filePath
}

function Restore-FromUndoFile {
    param(
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        Write-Error "Undo file not found: $FilePath"
        return $false
    }

    $entries = Get-Content -Path $FilePath -Raw | ConvertFrom-Json
    $restored = 0
    $failed = 0

    foreach ($entry in $entries) {
        try {
            if ($entry.Existed) {
                $value = $entry.OldValue
                if ($entry.IsBase64 -and $value -is [string]) {
                    $value = [Convert]::FromBase64String($value)
                }
                if (-not (Test-Path $entry.Path)) {
                    New-Item -Path $entry.Path -Force | Out-Null
                }
                Set-ItemProperty -Path $entry.Path -Name $entry.Name -Value $value -Force
                $restored++
            } else {
                # Value didn't exist before, remove it
                if (Test-Path $entry.Path) {
                    Remove-ItemProperty -Path $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
                    $restored++
                }
            }
        } catch {
            Write-Warning "Failed to restore $($entry.Path)\$($entry.Name): $_"
            $failed++
        }
    }

    Write-Host ""
    Write-Host "    Undo complete: $restored restored, $failed failed out of $($entries.Count) entries." -ForegroundColor Cyan
    return ($failed -eq 0)
}

function Get-UndoEntry {
    return $script:UndoEntries
}

function Clear-UndoEntry {
    $script:UndoEntries.Clear()
}

Export-ModuleMember -Function Save-RegistryState, Export-UndoFile, Restore-FromUndoFile,
    Get-UndoEntry, Clear-UndoEntry
