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
        [string]$OutputDir
    )

    if ($script:UndoEntries.Count -eq 0) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        if (Get-Command Get-OptimizerDataDir -ErrorAction SilentlyContinue) {
            $OutputDir = Get-OptimizerDataDir
        } else {
            $OutputDir = $env:TEMP
        }
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
    Set-UndoFileAcl -FilePath $filePath
    return $filePath
}

function Set-UndoFileAcl {
    # Lock the undo JSON down to the current user. The file lists every
    # registry path the optimizer touched, which is enough system-config
    # detail that it shouldn't be world-readable on a shared machine.
    # Failure to set the ACL is logged, not fatal - the file still
    # exists and the optimization run is otherwise complete.
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$FilePath)

    if (-not (Test-Path -LiteralPath $FilePath)) { return }
    if (-not $PSCmdlet.ShouldProcess($FilePath, "Restrict ACL to current user")) { return }

    try {
        $acl = Get-Acl -LiteralPath $FilePath
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($rule in @($acl.Access)) {
            [void]$acl.RemoveAccessRule($rule)
        }
        $userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $userSid,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $FilePath -AclObject $acl
    } catch {
        if (Get-Command Log -ErrorAction SilentlyContinue) {
            Log "[WARN] Could not restrict ACL on undo file '$FilePath': $_"
        }
    }
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
    return , $script:UndoEntries
}

function Clear-UndoEntry {
    $script:UndoEntries.Clear()
}

Export-ModuleMember -Function Save-RegistryState, Export-UndoFile, Restore-FromUndoFile,
    Get-UndoEntry, Clear-UndoEntry, Set-UndoFileAcl
