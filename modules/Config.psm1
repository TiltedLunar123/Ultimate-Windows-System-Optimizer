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
    @{ Name = "WSearch";                    Desc = "Windows Search Indexer" },
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

function Set-RegValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord"
    )

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
    Set-DryRunMode, Get-DryRunMode
