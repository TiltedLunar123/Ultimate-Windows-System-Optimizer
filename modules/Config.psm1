# Config.psm1 - Shared constants, tier definitions, and registry helper

# Valid section names for -Only / -Skip filtering
$script:ValidSections = @(
    "Cleanup", "Services", "Power", "VisualEffects", "Privacy",
    "Network", "Performance", "Explorer", "SSD", "Memory",
    "ScheduledTasks", "ContextMenu", "Boot", "Disk", "Features",
    "Notifications", "BackgroundApps", "Security"
)

# Bloat services list
$script:BloatServiceDefinitions = @(
    @{ Name = "DiagTrack";                  Desc = "Connected User Experience & Telemetry" },
    @{ Name = "dmwappushservice";           Desc = "WAP Push Message Routing" },
    @{ Name = "SysMain";                    Desc = "Superfetch (can hurt SSDs)" },
    @{ Name = "XblAuthManager";             Desc = "Xbox Live Auth Manager" },
    @{ Name = "XblGameSave";               Desc = "Xbox Live Game Save" },
    @{ Name = "XboxGipSvc";                Desc = "Xbox Accessory Management" },
    @{ Name = "XboxNetApiSvc";             Desc = "Xbox Live Networking" },
    @{ Name = "WMPNetworkSvc";             Desc = "Windows Media Player Sharing" },
    @{ Name = "lfsvc";                     Desc = "Geolocation Service" },
    @{ Name = "MapsBroker";                Desc = "Downloaded Maps Manager" },
    @{ Name = "RetailDemo";                Desc = "Retail Demo Service" },
    @{ Name = "RemoteRegistry";            Desc = "Remote Registry (security risk)" },
    @{ Name = "Fax";                       Desc = "Fax Service" },
    @{ Name = "WerSvc";                    Desc = "Windows Error Reporting" },
    @{ Name = "TabletInputService";        Desc = "Touch Keyboard (if no touchscreen)" },
    @{ Name = "PhoneSvc";                  Desc = "Phone Service" },
    @{ Name = "wisvc";                     Desc = "Windows Insider Service" }
)

# Scheduled tasks to disable
$script:BloatScheduledTasks = @(
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
    "\Microsoft\Windows\Maps\MapsUpdateTask",
    "\Microsoft\Windows\Maps\MapsToastTask",
    "\Microsoft\Windows\Feedback\Siuf\DmClient",
    "\Microsoft\Windows\Windows Error Reporting\QueueReporting",
    "\Microsoft\Windows\CloudExperienceHost\CreateObjectTask"
)

# Windows features to disable
$script:FeaturesToDisable = @(
    "WindowsMediaPlayer",
    "WorkFolders-Client",
    "Printing-Foundation-Features",
    "FaxServicesClientPackage"
)

# Named optimization presets. Each maps to a curated set of sections so a
# user can pick an intent ("just privacy", "tune for games") instead of
# hand-listing sections. "Balanced" is every section (the default run).
# A preset composes with -Skip; -Only still overrides a preset entirely.
$script:OptimizationPresets = [ordered]@{
    Balanced = $script:ValidSections
    Gaming   = @("Cleanup", "Power", "VisualEffects", "Network", "Performance",
                 "SSD", "Memory", "ScheduledTasks", "Boot", "Disk", "BackgroundApps")
    Privacy  = @("Privacy", "Services", "Notifications", "BackgroundApps",
                 "ScheduledTasks", "Security")
    Minimal  = @("Cleanup", "Privacy")
}

function Get-PresetNameList {
    return @($script:OptimizationPresets.Keys)
}

function Test-PresetName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    return @($script:OptimizationPresets.Keys) -contains $Name
}

function Get-PresetSection {
    param([string]$Name)
    if (-not (Test-PresetName $Name)) { return @() }
    return @($script:OptimizationPresets[$Name])
}

function Resolve-EnabledSection {
    # Compute the final, canonically-ordered list of sections to run from a
    # preset plus -Only/-Skip. -Only wins outright; otherwise the preset
    # (or all sections) is the base, with -Skip removed.
    param(
        [string]$PresetName,
        [string[]]$Only,
        [string[]]$Skip
    )

    $all = $script:ValidSections
    if ($Only -and $Only.Count -gt 0) {
        $base = $all | Where-Object { $_ -in $Only }
    } elseif ($PresetName -and (Test-PresetName $PresetName)) {
        $presetSections = Get-PresetSection -Name $PresetName
        $base = $all | Where-Object { $_ -in $presetSections }
    } else {
        $base = $all
    }

    if ($Skip -and $Skip.Count -gt 0) {
        $base = $base | Where-Object { $_ -notin $Skip }
    }
    return @($base)
}

function Get-OSBuildNumber {
    # Parse a Win32_OperatingSystem build string into an int. Returns 0 if
    # the build is empty/non-numeric (e.g. when hardware detection failed
    # and left OSBuild blank), so callers can compare without [int] throwing.
    param($Build)
    $n = 0
    [void][int]::TryParse("$Build", [ref]$n)
    return $n
}

# DryRun state - set by the entry point
$script:DryRunMode = $false

function Set-DryRunMode {
    [CmdletBinding(SupportsShouldProcess)]
    param([bool]$Enabled)
    if (-not $PSCmdlet.ShouldProcess("DryRunMode", "Set to $Enabled")) { return }
    $script:DryRunMode = $Enabled
}

function Get-DryRunMode {
    return $script:DryRunMode
}

function Get-OptimizerDataDir {
    # Returns a writable directory for optimizer artifacts (log, undo
    # JSON). Prefers $env:LOCALAPPDATA\UWSO because NTFS ACLs already
    # restrict it to the current user. Falls back to $env:TEMP, then the
    # user's Desktop as a last resort. Verifies write access by touching
    # a probe file before returning - covers redirected-to-readonly
    # Desktop, full TEMP volumes, etc.
    $candidates = @()
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'UWSO') }
    if ($env:TEMP)         { $candidates += $env:TEMP }
    if ($env:USERPROFILE)  { $candidates += (Join-Path $env:USERPROFILE 'Desktop') }

    foreach ($dir in $candidates) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        try {
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
            }
            $probe = Join-Path $dir (".uwso_probe_" + [Guid]::NewGuid().ToString('N'))
            Set-Content -LiteralPath $probe -Value 'probe' -ErrorAction Stop
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
            return $dir
        } catch {
            continue
        }
    }

    # Every candidate failed - return the first non-empty so callers
    # have a path to surface in their own error messages.
    foreach ($dir in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($dir)) { return $dir }
    }
    return $env:TEMP
}

# Hive prefixes Set-RegValue is allowed to touch. Anything else is
# almost certainly a typo or a bug in the caller, and silently creating
# arbitrary registry keys is exactly the kind of thing this script
# should never do. Kept narrow on purpose; add a prefix here if a
# legitimate need shows up.
$script:AllowedRegHives = @(
    'HKCU:\', 'HKLM:\', 'HKCR:\', 'HKU:\', 'HKCC:\'
)

# Registry value kinds the undo system knows how to capture and restore.
# Reject anything else so a typo in a caller can't write a value the undo
# file then fails to roll back.
$script:AllowedRegTypes = @(
    'String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord'
)

function Test-RegPathAllowed {
    [CmdletBinding()]
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    foreach ($prefix in $script:AllowedRegHives) {
        if ($Path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Set-RegValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord"
    )

    if (-not (Test-RegPathAllowed -Path $Path)) {
        if (Get-Command Log -ErrorAction SilentlyContinue) {
            Log "[ERROR] Rejected registry path '$Path' - must start with one of: $($script:AllowedRegHives -join ', ')"
        }
        return $false
    }

    if ($Type -notin $script:AllowedRegTypes) {
        if (Get-Command Log -ErrorAction SilentlyContinue) {
            Log "[ERROR] Rejected registry type '$Type' for $Path\$Name - must be one of: $($script:AllowedRegTypes -join ', ')"
        }
        return $false
    }

    # Save state for undo before making changes
    Save-RegistryState -Path $Path -Name $Name -NewValue $Value -Type $Type

    if ($script:DryRunMode) {
        Write-Dry "Would set $Path\$Name = $Value"
        return $true
    }

    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
        return $true
    } catch {
        Log "[ERROR] Failed to set registry value $Path\$Name : $_"
        return $false
    }
}

function Get-ValidSectionList {
    return $script:ValidSections
}

function Get-BloatServiceDefinition {
    return $script:BloatServiceDefinitions
}

function Get-BloatScheduledTaskList {
    return $script:BloatScheduledTasks
}

function Get-FeaturesToDisable {
    return $script:FeaturesToDisable
}

function Test-SectionEnabled {
    param(
        [string]$SectionName,
        [string[]]$Only,
        [string[]]$Skip
    )

    if ($Only -and $Only.Count -gt 0) {
        return ($SectionName -in $Only)
    }
    if ($Skip -and $Skip.Count -gt 0) {
        return ($SectionName -notin $Skip)
    }
    return $true
}

Export-ModuleMember -Function Set-RegValue, Get-ValidSectionList, Get-BloatServiceDefinition,
    Get-BloatScheduledTaskList, Get-FeaturesToDisable, Test-SectionEnabled,
    Set-DryRunMode, Get-DryRunMode, Get-OptimizerDataDir, Test-RegPathAllowed,
    Get-PresetNameList, Test-PresetName, Get-PresetSection, Resolve-EnabledSection,
    Get-OSBuildNumber
