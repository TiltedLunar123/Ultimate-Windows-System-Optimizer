# UndoManager.psm1 - Capture and restore system state for rollback.
# Covers registry values plus non-registry changes (services, scheduled
# tasks, optional features, boot timeout) so the undo file can reverse
# everything the optimizer modifies, not just the registry.

$script:UndoEntries = [System.Collections.Generic.List[hashtable]]::new()
# De-dup guard: the same registry value or service can be touched by more
# than one section in a single run. We only want to record the FIRST-seen
# pre-run state, otherwise a later capture stores an already-modified value
# as the "original" and rollback reverts to an intermediate state.
$script:SeenKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Save-RegistryState {
    param(
        [string]$Path,
        [string]$Name,
        $NewValue,
        [string]$Type = "DWord"
    )

    $key = "REG|$Path|$Name"
    if ($script:SeenKeys.Contains($key)) { return }

    $entry = @{
        Kind     = 'Registry'
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
    [void]$script:SeenKeys.Add($key)
}

function Save-ServiceState {
    # Record a service's startup type and running state before it is
    # stopped/disabled so the undo file can put it back.
    param([string]$Name)

    $key = "SVC|$Name"
    if ($script:SeenKeys.Contains($key)) { return }

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return }

    $script:UndoEntries.Add(@{
        Kind         = 'Service'
        Name         = $Name
        OldStartType = "$($svc.StartType)"
        WasRunning   = ($svc.Status -eq 'Running')
    })
    [void]$script:SeenKeys.Add($key)
}

function Save-ScheduledTaskState {
    # We only ever disable tasks that are currently enabled, so restoring
    # simply means re-enabling. Record identity for that.
    param([string]$TaskPath, [string]$TaskName)

    $key = "TASK|$TaskPath|$TaskName"
    if ($script:SeenKeys.Contains($key)) { return }

    $script:UndoEntries.Add(@{
        Kind     = 'ScheduledTask'
        TaskPath = $TaskPath
        TaskName = $TaskName
    })
    [void]$script:SeenKeys.Add($key)
}

function Save-FeatureState {
    # Optional features are only disabled when currently Enabled, so restore
    # re-enables them.
    param([string]$FeatureName)

    $key = "FEAT|$FeatureName"
    if ($script:SeenKeys.Contains($key)) { return }

    $script:UndoEntries.Add(@{
        Kind        = 'Feature'
        FeatureName = $FeatureName
    })
    [void]$script:SeenKeys.Add($key)
}

function Save-BcdTimeout {
    # Capture the current boot menu timeout before bcdedit changes it.
    # bcdedit output is best-effort to parse; default to the Windows
    # standard of 30 seconds if the value can't be read.
    $key = "BCD|timeout"
    if ($script:SeenKeys.Contains($key)) { return }

    $old = 30
    try {
        $out = bcdedit /enum '{bootmgr}' 2>$null
        $line = $out | Where-Object { $_ -match '^\s*timeout\s+\d+' } | Select-Object -First 1
        if ($line -and $line -match '(\d+)\s*$') { $old = [int]$Matches[1] }
    } catch {
        $null = $_
    }

    $script:UndoEntries.Add(@{
        Kind       = 'BcdTimeout'
        OldTimeout = $old
    })
    [void]$script:SeenKeys.Add($key)
}

function Save-RegistryKeyState {
    # Record whether a registry KEY existed before we created it. Some tweaks
    # work purely by a key's presence (e.g. the Windows 11 classic context
    # menu), and value-level undo can't delete a key - so undo needs to know
    # to remove a key we added wholesale.
    param([string]$Path)

    $key = "REGKEY|$Path"
    if ($script:SeenKeys.Contains($key)) { return }

    $existed = $false
    try { $existed = [bool](Test-Path -LiteralPath $Path) } catch { $null = $_ }

    $script:UndoEntries.Add(@{
        Kind    = 'RegistryKey'
        Path    = $Path
        Existed = $existed
    })
    [void]$script:SeenKeys.Add($key)
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

    # Convert to a serializable format. Registry entries Base64-encode any
    # byte[] values; non-registry entries are already JSON-friendly scalars.
    $exportData = @()
    foreach ($e in $script:UndoEntries) {
        $kind = if ($e.ContainsKey('Kind')) { $e.Kind } else { 'Registry' }
        if ($kind -eq 'Registry') {
            $exportData += @{
                Kind     = 'Registry'
                Path     = $e.Path
                Name     = $e.Name
                NewValue = if ($e.NewValue -is [byte[]]) { [Convert]::ToBase64String($e.NewValue) } else { $e.NewValue }
                Type     = $e.Type
                OldValue = if ($e.OldValue -is [byte[]]) { [Convert]::ToBase64String($e.OldValue) } else { $e.OldValue }
                Existed  = $e.Existed
                IsBase64 = ($e.OldValue -is [byte[]] -or $e.NewValue -is [byte[]])
            }
        } else {
            # Clone the action entry verbatim - all fields are scalars.
            $copy = @{}
            foreach ($k in $e.Keys) { $copy[$k] = $e[$k] }
            $exportData += $copy
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

function Get-UndoFileList {
    # Return undo_*.json files in a directory, newest first. Used by the
    # entry point for -Undo Latest and -ListUndo.
    param([string]$Directory)

    if ([string]::IsNullOrWhiteSpace($Directory)) {
        if (Get-Command Get-OptimizerDataDir -ErrorAction SilentlyContinue) {
            $Directory = Get-OptimizerDataDir
        } else {
            $Directory = $env:TEMP
        }
    }

    if (-not (Test-Path -LiteralPath $Directory)) { return @() }
    return @(Get-ChildItem -LiteralPath $Directory -Filter 'undo_*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
}

function Restore-FromUndoFile {
    param(
        [string]$FilePath
    )

    if ([string]::IsNullOrWhiteSpace($FilePath) -or -not (Test-Path -LiteralPath $FilePath)) {
        Write-Warning "Undo file not found: $FilePath"
        return $false
    }

    # A truncated or hand-edited undo file should fail cleanly, not throw an
    # unhandled parse error.
    try {
        $raw = Get-Content -LiteralPath $FilePath -Raw -ErrorAction Stop
        $entries = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warning "Undo file is not valid JSON: $FilePath"
        return $false
    }

    # A single-entry file deserializes to one object, not an array.
    $entries = @($entries)
    if ($entries.Count -eq 0) {
        Write-Warning "Undo file contains no entries: $FilePath"
        return $false
    }

    $restored = 0
    $failed = 0

    foreach ($entry in $entries) {
        $kind = if ($entry.PSObject.Properties['Kind'] -and $entry.Kind) { $entry.Kind } else { 'Registry' }
        try {
            switch ($kind) {
                'Service' {
                    $target = switch -Regex ("$($entry.OldStartType)") {
                        'Disabled' { 'Disabled' }
                        'Manual'   { 'Manual' }
                        'Auto'     { 'Automatic' }
                        default    { 'Manual' }
                    }
                    Set-Service -Name $entry.Name -StartupType $target -ErrorAction Stop
                    if ($entry.WasRunning) {
                        Start-Service -Name $entry.Name -ErrorAction SilentlyContinue
                    }
                    $restored++
                }
                'ScheduledTask' {
                    Enable-ScheduledTask -TaskPath $entry.TaskPath -TaskName $entry.TaskName -ErrorAction Stop | Out-Null
                    $restored++
                }
                'Feature' {
                    Enable-WindowsOptionalFeature -Online -FeatureName $entry.FeatureName -NoRestart -ErrorAction Stop | Out-Null
                    $restored++
                }
                'BcdTimeout' {
                    $t = 30
                    if ([int]::TryParse("$($entry.OldTimeout)", [ref]$t)) {
                        bcdedit /timeout $t 2>&1 | Out-Null
                        $restored++
                    }
                }
                'RegistryKey' {
                    # We only remove keys we created (Existed = false).
                    if (-not $entry.Existed -and (Test-Path -LiteralPath $entry.Path)) {
                        Remove-Item -LiteralPath $entry.Path -Recurse -Force -ErrorAction Stop
                    }
                    $restored++
                }
                default {
                    # Registry entry
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
                }
            }
        } catch {
            Write-Warning "Failed to restore entry ($kind): $_"
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
    $script:SeenKeys.Clear()
}

Export-ModuleMember -Function Save-RegistryState, Save-RegistryKeyState, Save-ServiceState,
    Save-ScheduledTaskState, Save-FeatureState, Save-BcdTimeout, Export-UndoFile,
    Restore-FromUndoFile, Get-UndoEntry, Clear-UndoEntry, Set-UndoFileAcl, Get-UndoFileList
