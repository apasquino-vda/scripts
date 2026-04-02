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

###############################
# FSLogix configuration
###############################

try {
    Write-Log "[FSLOGIX] - Action - Add 'localadmin' to 'FSLogix Profile Exclude List'"
    Add-LocalGroupMember -Group 'FSLogix Profile Exclude List' -Member 'localadmin'
    Write-Log "[FSLOGIX] - Result - User added"

    $fsxKey = 'HKLM:\SOFTWARE\FSLogix\Profiles'

    Write-Log "[FSLOGIX] - Action - Ensure FSLogix Profiles key exists: $fsxKey"
    New-Item -Path $fsxKey -Force | Out-Null

    New-ItemProperty -Path $fsxKey -Name 'Enabled' -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $fsxKey -Name 'VHDLocations' -PropertyType String -Value '\\avdsmbtestap.file.core.windows.net\fslogix' -Force | Out-Null
    New-ItemProperty -Path $fsxKey -Name 'VolumeType' -PropertyType String -Value 'vhdx' -Force | Out-Null
    New-ItemProperty -Path $fsxKey -Name 'SizeInMBs' -PropertyType DWord -Value 30000 -Force | Out-Null
    New-ItemProperty -Path $fsxKey -Name 'DeleteLocalProfileWhenVHDShouldApply' -PropertyType DWord -Value 1 -Force | Out-Null

    Write-Log "[FSLOGIX] - Result - FSLogix configuration completed"
}
catch {
    Write-Log "[FSLOGIX] - Error - FSLogix configuration failed: $($_.Exception.Message)" "ERROR"
}

###############################
# Cloud Kerberos / AAD keys
###############################

try {
    Write-Log "[KERBEROS] - Action - Configure CloudKerberosTicketRetrievalEnabled"
    $kerbKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters'
    New-Item -Path $kerbKey -Force | Out-Null
    New-ItemProperty -Path $kerbKey -Name 'CloudKerberosTicketRetrievalEnabled' -PropertyType DWord -Value 1 -Force | Out-Null
    Write-Log "[KERBEROS] - Result - CloudKerberosTicketRetrievalEnabled set to 1"
}
catch {
    Write-Log "[KERBEROS] - Error - Kerberos configuration failed: $($_.Exception.Message)" "ERROR"
}

try {
    Write-Log "[AAD] - Action - Configure LoadCredKeyFromProfile"
    $aadKey = 'HKLM:\Software\Policies\Microsoft\AzureADAccount'
    New-Item -Path $aadKey -Force | Out-Null
    New-ItemProperty -Path $aadKey -Name 'LoadCredKeyFromProfile' -PropertyType DWord -Value 1 -Force | Out-Null
    Write-Log "[AAD] - Result - LoadCredKeyFromProfile set to 1"
}
catch {
    Write-Log "[AAD] - Error - AzureAD Account configuration failed: $($_.Exception.Message)" "ERROR"
}

###############################
# TimeZone redirection
###############################

try {
    Write-Log "[TZ] - Action - Enable TimeZone Redirection"
    New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" `
                     -Name "fEnableTimeZoneRedirection" -PropertyType DWord -Value 1 -Force | Out-Null
    Write-Log "[TZ] - Result - TimeZone Redirection enabled"
}
catch {
    Write-Log "[TZ] - Error - TimeZone Redirection setup failed: $($_.Exception.Message)" "ERROR"
}

###############################
# Default user hive modifications
###############################

$defaultUserHive   = "HKU\DefaultUser"
$defaultUserNtuser = "C:\Users\Default\NTUSER.DAT"
$hiveLoaded = $false

try {
    Write-Log "[DEFAULT-HIVE] - Action - Load default user hive from $defaultUserNtuser"
    reg load $defaultUserHive $defaultUserNtuser | Out-Null
    $hiveLoaded = $true

    Write-Log "[DEFAULT-HIVE] - Action - Disable first-run experience"
    reg add "$defaultUserHive\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        /v "SubscribedContent-338389Enabled" /t REG_DWORD /d 0 /f | Out-Null

    Write-Log "[DEFAULT-HIVE] - Result - Default user hive modifications completed"
}
catch {
    Write-Log "[DEFAULT-HIVE] - Error - Default user hive modifications failed: $($_.Exception.Message)" "ERROR"
}
finally {
    if ($hiveLoaded) {
        try {
            Write-Log "[DEFAULT-HIVE] - Action - Force garbage collection before unloading hive"
            [gc]::Collect()

            Write-Log "[DEFAULT-HIVE] - Action - Unload default user hive"
            reg unload $defaultUserHive | Out-Null
            Write-Log "[DEFAULT-HIVE] - Result - Default user hive unloaded"
        }
        catch {
            Write-Log "[DEFAULT-HIVE] - Error - Unloading default user hive failed: $($_.Exception.Message)" "ERROR"
        }
    }
}


###############################
# RSAT tools (AD DS + DNS)
###############################

try {
    Write-Log "[RSAT] - Action - Install RSAT tools for AD DS and DNS"

    $rsatCapabilities = @(
        "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0",
        "Rsat.Dns.Tools~~~~0.0.1.0"
    )

    foreach ($cap in $rsatCapabilities) {
        try {
            Write-Log "[RSAT] - Action - Install capability $cap"
            Add-WindowsCapability -Online -Name $cap -ErrorAction Stop | Out-Null
            Write-Log "[RSAT] - Result - Capability installed: $cap"
        }
        catch {
            Write-Log "[RSAT] - Error - Failed to install $cap: $($_.Exception.Message)" "ERROR"
        }
    }

    Write-Log "[RSAT] - Summary - RSAT AD DS + DNS installation attempted"
}
catch {
    Write-Log "[RSAT] - Error - RSAT installation block failed: $($_.Exception.Message)" "ERROR"
}

###############################
# SSMS
###############################

try {
    Write-Log "[SSMS] - Action - Download latest SSMS"
    $DownloadUrl = "https://aka.ms/ssmsfullsetup"
    $InstallerPath = Join-Path $WorkDir "SSMS-Setup-ENU.exe"

    Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing
    Write-Log "[SSMS] - Result - SSMS downloaded to $InstallerPath"

    Write-Log "[SSMS] - Action - Silent install SSMS"
    Start-Process -FilePath $InstallerPath -ArgumentList "/Install /Quiet /Norestart" -Wait -NoNewWindow
    Write-Log "[SSMS] - Result - SSMS installation completed"
}
catch {
    Write-Log "[SSMS] - Error - SSMS installation failed: $($_.Exception.Message)" "ERROR"
}

###############################
# Visual Studio Code
###############################

try {
    Write-Log "[VSC] - Action - Download latest Visual Studio Code"
    $DownloadUrl = "https://update.code.visualstudio.com/latest/win32-x64-user/stable"
    $InstallerPath = Join-Path $WorkDir "VSCodeSetup-x64.exe"

    Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing
    Write-Log "[VSC] - Result - VS Code downloaded to $InstallerPath"

    Write-Log "[VSC] - Action - Silent install Visual Studio Code"
    Start-Process -FilePath $InstallerPath `
        -ArgumentList "/VERYSILENT /NORESTART /MERGETASKS=""addcontextmenufiles,addcontextmenufolders,addtopath""" `
        -Wait -NoNewWindow

    Write-Log "[VSC] - Result - Visual Studio Code installation completed"

    Write-Log "[VSC] - Action - Remove installer $InstallerPath"
    Remove-Item $InstallerPath -Force
    Write-Log "[VSC] - Result - Installer removed"
}
catch {
    Write-Log "[VSC] - Error - Visual Studio Code installation failed: $($_.Exception.Message)" "ERROR"
}

Write-Log "--- AVD PATCH SCRIPT END (reboot requested) ---"

Write-Log "[SYSTEM] - Action - Initiate reboot (shutdown /r /t 0 /f)"
shutdown /r /t 0 /f

exit 0
