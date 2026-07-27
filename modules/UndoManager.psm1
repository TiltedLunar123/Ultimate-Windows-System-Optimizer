# UndoManager.psm1 - Save and restore state for rollback
#
# Entries carry a Kind so the file can hold more than registry values.
# 'Registry' is the original shape and stays the default when the field is
# missing, which is what old undo files look like. 'Service' was added for
# issue #2. Scheduled tasks, optional features and bcdedit are still not
# covered; see the rollback section of the README.

$script:UndoEntries = [System.Collections.Generic.List[hashtable]]::new()

function Get-UndoEntryKind {
    # Undo files written before Kind existed are all registry entries.
    param($Entry)

    if ($Entry -is [hashtable]) {
        if ($Entry.ContainsKey('Kind') -and $Entry.Kind) { return [string]$Entry.Kind }
        return 'Registry'
    }
    if ($Entry -and $Entry.PSObject.Properties['Kind'] -and $Entry.Kind) { return [string]$Entry.Kind }
    return 'Registry'
}

function Save-ServiceState {
    # Record what a service looked like before the optimizer disables it.
    # Startup type alone is not enough: a service that was running needs to
    # be started again, or undo leaves it configured correctly and dead.
    param(
        [string]$Name,
        [string]$NewStartupType = 'Disabled'
    )

    $entry = @{
        Kind       = 'Service'
        Path       = "Service:\$Name"
        Name       = $Name
        NewValue   = $NewStartupType
        Type       = 'Service'
        OldValue   = $null
        Existed    = $false
        WasRunning = $false
    }

    try {
        $svc = Get-Service -Name $Name -ErrorAction Stop
        $entry.OldValue   = [string]$svc.StartType
        $entry.WasRunning = ($svc.Status -eq 'Running')
        $entry.Existed    = $true
    } catch {
        $null = $_  # Service isn't installed on this machine, nothing to put back.
    }

    $script:UndoEntries.Add($entry)
}

function Restore-ServiceState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Name,
        [string]$StartupType,
        [bool]$WasRunning
    )

    if ([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($StartupType)) { return $false }
    if (-not $PSCmdlet.ShouldProcess($Name, "Restore startup type to $StartupType")) { return $false }

    try {
        try {
            Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
        } catch {
            # Windows PowerShell 5.1 has no AutomaticDelayedStart value for
            # -StartupType even though Get-Service reports it. Automatic is
            # the closest thing that will actually apply.
            if ($StartupType -eq 'AutomaticDelayedStart') {
                Set-Service -Name $Name -StartupType Automatic -ErrorAction Stop
            } else {
                throw
            }
        }

        if ($WasRunning) {
            Start-Service -Name $Name -ErrorAction Stop
        }
        return $true
    } catch {
        Write-Warning "Failed to restore service ${Name}: $_"
        return $false
    }
}

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
            Kind       = Get-UndoEntryKind -Entry $e
            Path       = $e.Path
            Name       = $e.Name
            NewValue   = if ($e.NewValue -is [byte[]]) { [Convert]::ToBase64String($e.NewValue) } else { $e.NewValue }
            Type       = $e.Type
            OldValue   = if ($e.OldValue -is [byte[]]) { [Convert]::ToBase64String($e.OldValue) } else { $e.OldValue }
            Existed    = $e.Existed
            IsBase64   = ($e.OldValue -is [byte[]] -or $e.NewValue -is [byte[]])
            WasRunning = if ($e.ContainsKey('WasRunning')) { [bool]$e.WasRunning } else { $false }
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
        # Warn, don't error. A missing path is a user mistake, not a fault,
        # and the caller already handles the $false return with a friendly
        # message. Write-Error made the outcome depend on the caller's
        # ErrorActionPreference: it returned $false locally but threw under
        # Stop (as CI runs), so the behavior was never deterministic.
        Write-Warning "Undo file not found: $FilePath"
        return $false
    }

    $entries = Get-Content -Path $FilePath -Raw | ConvertFrom-Json
    $restored = 0
    $failed = 0
    $skipped = 0

    foreach ($entry in $entries) {
        try {
            if ((Get-UndoEntryKind -Entry $entry) -eq 'Service') {
                if (-not $entry.Existed) {
                    # The service was not installed when the run happened, so
                    # there is no prior state to put back.
                    $skipped++
                    continue
                }
                $wasRunning = [bool]($entry.PSObject.Properties['WasRunning'] -and $entry.WasRunning)
                if (Restore-ServiceState -Name $entry.Name -StartupType ([string]$entry.OldValue) -WasRunning $wasRunning) {
                    $restored++
                } else {
                    $failed++
                }
                continue
            }

            if ($entry.Existed) {
                $value = $entry.OldValue
                if ($entry.IsBase64 -and $value -is [string]) {
                    $value = [Convert]::FromBase64String($value)
                }
                if (-not (Test-Path $entry.Path)) {
                    New-Item -Path $entry.Path -Force | Out-Null
                }
                # Older undo files (pre-Type field) default to DWord.
                $type = if ($entry.PSObject.Properties['Type'] -and $entry.Type) { $entry.Type } else { 'DWord' }
                Set-ItemProperty -Path $entry.Path -Name $entry.Name -Value $value -Type $type -Force
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
    $summary = "    Undo complete: $restored restored, $failed failed out of $($entries.Count) entries."
    if ($skipped -gt 0) { $summary += " $skipped had nothing to restore." }
    Write-Host $summary -ForegroundColor Cyan
    return ($failed -eq 0)
}

function Get-UndoEntry {
    return , $script:UndoEntries
}

function Clear-UndoEntry {
    $script:UndoEntries.Clear()
}

Export-ModuleMember -Function Save-RegistryState, Export-UndoFile, Restore-FromUndoFile,
    Get-UndoEntry, Clear-UndoEntry, Set-UndoFileAcl,
    Save-ServiceState, Restore-ServiceState, Get-UndoEntryKind
