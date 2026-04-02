# AVD Patch Script for Custom Script Extension with Reboot

$ErrorActionPreference = 'Stop'

# Working + log directory
$WorkDir = "C:\HostPatch"
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$logFile = Join-Path $WorkDir "avd-patch-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] [$Level] $Message"
    $entry | Tee-Object -FilePath $logFile -Append
}

Write-Log "--- AVD PATCH SCRIPT START ---"
Write-Log "User: $(whoami)"

try {
    Write-Log "Script running..."

    # =========================
    # FSLogix: local group + registry
    # =========================

    Write-Log "Adding 'localadmin' to 'FSLogix Profile Exclude List'..."
    Add-LocalGroupMember -Group 'FSLogix Profile Exclude List' -Member 'localadmin'

    $fsxKey = 'HKLM:\SOFTWARE\FSLogix\Profiles'

    Write-Log "Ensuring FSLogix Profiles key exists: $fsxKey"
    New-Item -Path $fsxKey -Force | Out-Null

    Write-Log "Enabling FSLogix profile containers (Enabled=1)..."
    New-ItemProperty -Path $fsxKey -Name 'Enabled' -PropertyType DWord -Value 1 -Force | Out-Null

    Write-Log "Setting FSLogix VHDLocations..."
    New-ItemProperty -Path $fsxKey -Name 'VHDLocations' -PropertyType String -Value '\\avdsmbtestap.file.core.windows.net\fslogix' -Force | Out-Null

    Write-Log "Setting FSLogix VolumeType to vhdx..."
    New-ItemProperty -Path $fsxKey -Name 'VolumeType' -PropertyType String -Value 'vhdx' -Force | Out-Null

    Write-Log "Setting FSLogix SizeInMBs to 30000..."
    New-ItemProperty -Path $fsxKey -Name 'SizeInMBs' -PropertyType DWord -Value 30000 -Force | Out-Null

    Write-Log "Enabling DeleteLocalProfileWhenVHDShouldApply..."
    New-ItemProperty -Path $fsxKey -Name 'DeleteLocalProfileWhenVHDShouldApply' -PropertyType DWord -Value 1 -Force | Out-Null

    # =========================
    # Cloud Kerberos / AAD keys
    # =========================

    $kerbKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters'
    Write-Log "Configuring CloudKerberosTicketRetrievalEnabled..."
    New-Item -Path $kerbKey -Force | Out-Null
    New-ItemProperty -Path $kerbKey -Name 'CloudKerberosTicketRetrievalEnabled' -PropertyType DWord -Value 1 -Force | Out-Null

    $aadKey = 'HKLM:\Software\Policies\Microsoft\AzureADAccount'
    Write-Log "Configuring LoadCredKeyFromProfile..."
    New-Item -Path $aadKey -Force | Out-Null
    New-ItemProperty -Path $aadKey -Name 'LoadCredKeyFromProfile' -PropertyType DWord -Value 1 -Force | Out-Null

    # =========================
    # Notepad++ installation
    # =========================

    $nppPath = Join-Path $WorkDir "npp.8.6.Installer.x64.exe"
    Write-Log "Downloading Notepad++ to $nppPath..."
    Invoke-WebRequest -Uri "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.6/npp.8.6.Installer.x64.exe" -OutFile $nppPath

    Write-Log "Starting silent Notepad++ installation..."
    Start-Process $nppPath -ArgumentList "/S" -Wait
    Write-Log "Notepad++ installation completed."

    # =========================
    # TimeZone redirection
    # =========================

    Write-Log "Enabling TimeZone Redirection..."
    New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" `
                     -Name "fEnableTimeZoneRedirection" -PropertyType DWord -Value 1 -Force | Out-Null

    # =========================
    # Default user hive modifications
    # =========================

    $defaultUserHive   = "HKU\DefaultUser"
    $defaultUserNtuser = "C:\Users\Default\NTUSER.DAT"
    $hiveLoaded = $false

    try {
        Write-Log "Loading default user hive from $defaultUserNtuser..."
        reg load $defaultUserHive $defaultUserNtuser | Out-Null
        $hiveLoaded = $true

        Write-Log "Disabling first-run experience for default user..."
        reg add "$defaultUserHive\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
            /v "SubscribedContent-338389Enabled" /t REG_DWORD /d 0 /f | Out-Null

        Write-Log "Default user hive modifications completed."
    }
    finally {
        if ($hiveLoaded) {
            Write-Log "Forcing garbage collection before unloading hive..."
            [gc]::Collect()

            Write-Log "Unloading default user hive..."
            reg unload $defaultUserHive | Out-Null
            Write-Log "Default user hive unloaded."
        }
    }

    # =========================
    # RSAT tools
    # =========================

    Write-Log "Installing all RSAT tools..."
    Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online | Out-Null
    Write-Log "RSAT tools installation completed."

    Write-Log "Script finished OK. Initiating reboot..."

    # --- Reboot section ---
    # /r = restart, /t 0 = no timeout (immediate), /f = force running apps to close
    # Adjust timeout if you want a delay, e.g. /t 60 for 60 seconds.
    shutdown /r /t 0 /f

    # Custom Script Extension will typically see this as success if it reaches here;
    # the VM will restart immediately after this command.
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)" "ERROR"
    Write-Log "STACK: $($_.ScriptStackTrace)" "ERROR"
    # For Custom Script Extension, non-zero exit code marks failure
    exit 1
}
finally {
    Write-Log "--- AVD PATCH SCRIPT END ---"
}

# If we reach here without error, exit 0 (though reboot will usually interrupt first)
exit 0
