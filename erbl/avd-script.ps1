# Write-Host "No customizations"

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

################################################################################################

Write-Log "TimeZone Redirection"
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "fEnableTimeZoneRedirection" -PropertyType DWord -Value 1 -Force | Out-Null

################################################################################################

Write-Log "Desktop and First Run"
# Desktop and First Run
# Load the default user registry hive
reg load "HKU\DefaultUser" "C:\Users\Default\NTUSER.DAT"
# Set default desktop wallpaper
#reg add "HKU\DefaultUser\Control Panel\Desktop" /v Wallpaper /t REG_SZ /d "C:\Windows\Web\Wallpaper\Corporate\company-wallpaper.jpg" /f
# Set default Start menu layout (if using a custom layout)
#reg add "HKU\DefaultUser\SOFTWARE\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount" /v "LockedStartLayout" /t REG_DWORD /d 1 /f
# Disable first-run experience
reg add "HKU\DefaultUser\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-338389Enabled" /t REG_DWORD /d 0 /f
# Unload the hive
[gc]::Collect()
reg unload "HKU\DefaultUser"

###############################
# Install specific RSAT Tools if not already installed
###############################
Write-Log "RSAT ADDS"
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
Write-Log "RSAT GPO"
Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0
Write-Log "RSAT DNS"
Add-WindowsCapability -Online -Name Rsat.Dns.Tools~~~~0.0.1.0
Write-Log "RSAT DHCP"
Add-WindowsCapability -Online -Name Rsat.DHCP.Tools~~~~0.0.1.0

# Install All RSAT Tools at Once:
# Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online

###############################
# SSMS
###############################

$ssmsPaths = @(
    "C:\Program Files (x86)\Microsoft SQL Server Management Studio 20\Common7\IDE\Ssms.exe"
)

$ssmsInstalled = $false
foreach ($p in $ssmsPaths) {
    if (Test-Path $p) {
        $ssmsInstalled = $true
        Write-Log "[SSMS] - Detected installation at: $p"
        break
    }
}

if (-not $ssmsInstalled) {
    try {
        Write-Log "[SSMS] - Action - Download latest SSMS"
        $DownloadUrl  = "https://aka.ms/ssmsfullsetup"
        $InstallerPath = Join-Path $WorkDir "SSMS-Setup-ENU.exe"

        Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing
        Write-Log "[SSMS] - Result - Downloaded to $InstallerPath"

        Write-Log "[SSMS] - Action - Silent install"
        Start-Process -FilePath $InstallerPath -ArgumentList "/Install /Quiet /Norestart" -Wait -NoNewWindow
        Write-Log "[SSMS] - Result - Installation completed"

        Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Log "[SSMS] - Error - Installation failed: $($_.Exception.Message)" "ERROR"
    }
}
else {
    Write-Log "[SSMS] - Skip - SSMS already installed"
}

###############################
# Visual Studio Code
###############################

$vscodePaths = @(
    "C:\Program Files\Microsoft VS Code\Code.exe",
)

$vscodeInstalled = $false
foreach ($p in $vscodePaths) {
    if (Test-Path $p) {
        $vscodeInstalled = $true
        Write-Log "[VSC] - Detected installation at: $p"
        break
    }
}

if (-not $vscodeInstalled) {
    try {
        Write-Log "[VSC] - Action - Download latest Visual Studio Code"
        $DownloadUrl  = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64"
        $InstallerPath = Join-Path $WorkDir "VSCodeSetup-x64-*.exe"

        Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing
        Write-Log "[VSC] - Result - Downloaded to $InstallerPath"

        Write-Log "[VSC] - Action - Silent install"
        Start-Process -FilePath $InstallerPath -ArgumentList "/verysilent", "/mergetasks='!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath'" -Wait -NoNewWindow
        Write-Log "[VSC] - Result - Installation completed"
        Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Log "[VSC] - Error - Installation failed: $($_.Exception.Message)" "ERROR"
    }
}
else {
    Write-Log "[VSC] - Skip - Visual Studio Code already installed"
}

###############################
# Final Reboot
###############################

Write-Log "--- AVD PATCH SCRIPT END (reboot requested) ---"

Write-Log "[SYSTEM] - Action - Initiate reboot (shutdown /r /t 0 /f)"
shutdown /r /t 0 /f

exit 0

