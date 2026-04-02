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

#######################################
#    Install language pack (Italian)  #
#######################################

[CmdletBinding()]
Param (
    [Parameter(Mandatory)]
    [ValidateSet("Italian (Italy)")]
    [System.String[]]$LanguageList
)

function Install-LanguagePack {
    BEGIN {
        $templateFilePathFolder = "C:\HostPatch"
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Log "[LANGPACK] - Start - Install language pack (Italian)"

        # populate dictionary (only Italian)
        $LanguagesDictionary = @{}
        $LanguagesDictionary.Add("Italian (Italy)", "it-IT")

        try {
            Write-Log "[LANGPACK] - Action - Disable LanguageComponentsInstaller tasks"
            Disable-ScheduledTask -TaskName "\Microsoft\Windows\LanguageComponentsInstaller\Installation"
            Disable-ScheduledTask -TaskName "\Microsoft\Windows\LanguageComponentsInstaller\ReconcileLanguageResources"
            Write-Log "[LANGPACK] - Result - LanguageComponentsInstaller tasks disabled"
        }
        catch {
            Write-Log "[LANGPACK] - Error - Failed to disable LanguageComponentsInstaller tasks: $($_.Exception.Message)" "ERROR"
        }
    }

    PROCESS {
        foreach ($Language in $LanguageList) {
            for ($i = 1; $i -le 5; $i++) {
                try {
                    Write-Log "[LANGPACK] - Action - Install language [$Language], attempt $i"
                    $LanguageCode = $LanguagesDictionary.$Language
                    Install-Language -Language $LanguageCode -ErrorAction Stop
                    Write-Log "[LANGPACK] - Result - Language installed: $LanguageCode"
                    break
                }
                catch {
                    Write-Log "[LANGPACK] - Error - Install attempt $i failed: $($_.Exception.Message)" "ERROR"
                    if ($i -eq 5) {
                        Write-Log "[LANGPACK] - Result - All install attempts failed for $Language" "ERROR"
                    }
                }
            }
        }
    }

    END {
        try {
            if (Test-Path -Path $templateFilePathFolder -ErrorAction SilentlyContinue) {
                Write-Log "[LANGPACK] - Action - Cleanup temp folder $templateFilePathFolder"
                Remove-Item -Path $templateFilePathFolder -Force -Recurse -ErrorAction Continue
                Write-Log "[LANGPACK] - Result - Temp folder removed"
            }
        }
        catch {
            Write-Log "[LANGPACK] - Error - Cleanup failed: $($_.Exception.Message)" "ERROR"
        }

        try {
            Write-Log "[LANGPACK] - Action - Enable LanguageComponentsInstaller tasks"
            Enable-ScheduledTask -TaskName "\Microsoft\Windows\LanguageComponentsInstaller\Installation"
            Enable-ScheduledTask -TaskName "\Microsoft\Windows\LanguageComponentsInstaller\ReconcileLanguageResources"
            Write-Log "[LANGPACK] - Result - LanguageComponentsInstaller tasks enabled"
        }
        catch {
            Write-Log "[LANGPACK] - Error - Failed to enable LanguageComponentsInstaller tasks: $($_.Exception.Message)" "ERROR"
        }

        $stopwatch.Stop()
        $elapsedTime = $stopwatch.Elapsed
        Write-Log "[LANGPACK] - Summary - ExitCode: $LASTEXITCODE, Duration: $elapsedTime"
    }
}

Install-LanguagePack -LanguageList "Italian (Italy)"

#######################################
#    Set default Language (Italian)   #
#######################################

[CmdletBinding()]
Param (
    [Parameter(Mandatory)]
    [ValidateSet("Italian (Italy)")]
    [string]$Language
)

function Get-RegionInfo($Name='*') {
    try {
        Write-Log "[LANG-DEFAULT] - Action - Get region info for $Name"
        $cultures = [System.Globalization.CultureInfo]::GetCultures('InstalledWin32Cultures')

        $languageTag = $null
        foreach($culture in $cultures) {        
            if($culture.DisplayName -eq $Name) {
                $languageTag = $culture.Name
                break
            }
        }

        if ($null -eq $languageTag) {
            Write-Log "[LANG-DEFAULT] - Result - No culture found for $Name"
            return
        } else {
            $region = [System.Globalization.RegionInfo]$culture.Name
            Write-Log "[LANG-DEFAULT] - Result - Found culture: $languageTag, GeoID: $($region.GeoId)"
            return @($languageTag, $region.GeoId)
        }
    }
    catch {
        Write-Log "[LANG-DEFAULT] - Error - Get-RegionInfo failed: $($_.Exception.Message)" "ERROR"
        return
    }
}

function UpdateUserLanguageList($languageTag) {
    try {
        Write-Log "[LANG-DEFAULT] - Action - Update user language list with $languageTag"
        $userLanguageList = New-WinUserLanguageList -Language $languageTag
        $installedUserLanguagesList = Get-WinUserLanguageList

        foreach($language in $installedUserLanguagesList) {
            $userLanguageList.Add($language.LanguageTag)
        }

        Set-WinUserLanguageList -LanguageList $userLanguageList -Force
        Write-Log "[LANG-DEFAULT] - Result - User language list updated"
    }
    catch {
        Write-Log "[LANG-DEFAULT] - Error - UpdateUserLanguageList failed: $($_.Exception.Message)" "ERROR"
    }
}

function UpdateRegionSettings($GeoID) {
    try {
        Write-Log "[LANG-DEFAULT] - Action - Update region settings with GeoID $GeoID"

        try {
            Write-Log "[LANG-DEFAULT] - Action - Remove DeviceRegion registry key"
            Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Control Panel\DeviceRegion" `
                                -Name "DeviceRegion" -Force -ErrorAction Continue
            Write-Log "[LANG-DEFAULT] - Result - DeviceRegion registry key removed (if existed)"
        }
        catch {
            Write-Log "[LANG-DEFAULT] - Warning - Remove DeviceRegion key failed: $($_.Exception.Message)" "WARN"
        }

        New-ItemProperty -Path "HKU\.DEFAULT\Control Panel\International\Geo" `
                         -Name "Nation" -Value $GeoID -PropertyType String -Force
        Set-WinHomeLocation -GeoId $GeoID
        Write-Log "[LANG-DEFAULT] - Result - Region settings updated"
    }
    catch {
        Write-Log "[LANG-DEFAULT] - Error - UpdateRegionSettings failed: $($_.Exception.Message)" "ERROR"
    }
}

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
Write-Log "[LANG-DEFAULT] - Start - Set default Language (Italian)"

$templateFilePathFolder = "C:\AVDImage"
$LanguagesDictionary = @{}
$LanguagesDictionary.Add("Italian (Italy)", "it-IT")

try {
    Write-Log "[LANG-DEFAULT] - Action - Disable LanguageComponentsInstaller tasks"
    Disable-ScheduledTask -TaskName "\Microsoft\Windows\LanguageComponentsInstaller\Installation"
    Disable-ScheduledTask -TaskName "\Microsoft\Windows\LanguageComponentsInstaller\ReconcileLanguageResources"
    Write-Log "[LANG-DEFAULT] - Result - LanguageComponentsInstaller tasks disabled"
}
catch {
    Write-Log "[LANG-DEFAULT] - Error - Failed to disable LanguageComponentsInstaller tasks: $($_.Exception.Message)" "ERROR"
}

$languageDetails = Get-RegionInfo -Name $Language

if($null -eq $languageDetails) {
    $LanguageTag = $LanguagesDictionary.$Language 
} else {
    $languageTag = $languageDetails[0]
    $GeoID = $languageDetails[1]
    $LanguageTag = $languageTag
}

$foundLanguage = $false

try {
    Write-Log "[LANG-DEFAULT] - Action - Check installed language packs"
    $installedLanguages = Get-InstalledLanguage
    foreach($languagePack in $installedLanguages) {
        $languageID = $languagePack.LanguageId
        if($languageID -eq $LanguageTag) {
            $foundLanguage = $true
            break
        }
    } 
    if ($foundLanguage) {
        Write-Log "[LANG-DEFAULT] - Result - Language pack already installed: $LanguageTag"
    }
}
catch {
    Write-Log "[LANG-DEFAULT] - Error - Get-InstalledLanguage failed: $($_.Exception.Message)" "ERROR"
}

if(-Not $foundLanguage) {
    for($i=1; $i -le 5; $i++) {
        try {
            Write-Log "[LANG-DEFAULT] - Action - Install language pack $LanguageTag, attempt $i"
            Install-Language -Language $LanguageTag -ErrorAction Stop
            Write-Log "[LANG-DEFAULT] - Result - Language pack installed: $LanguageTag"
            break
        }
        catch {
            Write-Log "[LANG-DEFAULT] - Error - Install attempt $i failed: $($_.Exception.Message)" "ERROR"
            if ($i -eq 5) {
                Write-Log "[LANG-DEFAULT] - Result - All attempts failed for language pack $LanguageTag" "ERROR"
            }
        }
    }
}

try {
    Write-Log "[LANG-DEFAULT] - Action - Set system preferred UI language to $LanguageTag"
    Set-SystemPreferredUILanguage -Language $LanguageTag
    Set-WinSystemLocale -SystemLocale $LanguageTag
    Set-Culture -CultureInfo $LanguageTag
    UpdateUserLanguageList -languageTag $LanguageTag
    Write-Log "[LANG-DEFAULT] - Result - Default language set to $Language ($LanguageTag)"
}
catch {
    Write-Log "[LANG-DEFAULT] - Error - Setting default language failed: $($_.Exception.Message)" "ERROR"
}

try {
    $GeoID = (New-Object System.Globalization.RegionInfo($LanguageTag.Split("-")[1])).GeoId
    UpdateRegionSettings($GeoID)
}
catch {
    Write-Log "[LANG-DEFAULT] - Error - GeoID calculation or region update failed: $($_.Exception.Message)" "ERROR"
}

try {
    if (Test-Path -Path $templateFilePathFolder -ErrorAction SilentlyContinue) {
        Write-Log "[LANG-DEFAULT] - Action - Remove temp folder $templateFilePathFolder"
        Remove-Item -Path $templateFilePathFolder -Force -Recurse -ErrorAction Continue
        Write-Log "[LANG-DEFAULT] - Result - Temp folder removed"
    }
}
catch {
    Write-Log "[LANG-DEFAULT] - Error - Removing temp folder failed: $($_.Exception.Message)" "ERROR"
}

try {
    Write-Log "[LANG-DEFAULT] - Action - Enable LanguageComponentsInstaller tasks"
    Enable-ScheduledTask -TaskName "\Microsoft\Windows\LanguageComponentsInstaller\Installation"
    Enable-ScheduledTask -TaskName "\Microsoft\Windows\LanguageComponentsInstaller\ReconcileLanguageResources"
    Write-Log "[LANG-DEFAULT] - Result - LanguageComponentsInstaller tasks enabled"
}
catch {
    Write-Log "[LANG-DEFAULT] - Error - Failed to enable LanguageComponentsInstaller tasks: $($_.Exception.Message)" "ERROR"
}

$stopwatch.Stop()
$elapsedTime = $stopwatch.Elapsed
Write-Log "[LANG-DEFAULT] - Summary - ExitCode: $LASTEXITCODE, Duration: $elapsedTime"

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

#######################################
#    RDP Shortpath            #
#######################################


# Reference: https://docs.microsoft.com/en-us/azure/virtual-desktop/shortpath

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
Write-Log 'AVD AIB Customization: Configure RDP shortpath and Windows Defender Firewall'

# rdp shortpath reg key
$WinstationsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations'

$regKeyName = "fUseUdpPortRedirector"
$regKeyValue = "1"

$portName = "UdpPortNumber"
$portValue = "3390"


IF(!(Test-Path $WinstationsKey)) {
    New-Item -Path $WinstationsKey -Force | Out-Null
}

try {
    New-ItemProperty -Path $WinstationsKey -Name $regKeyName -ErrorAction:SilentlyContinue -PropertyType:dword -Value $regKeyValue -Force | Out-Null
    New-ItemProperty -Path $WinstationsKey -Name $portName -ErrorAction:SilentlyContinue -PropertyType:dword -Value $portValue -Force | Out-Null
}
catch {
    Write-Log "*** AVD AIB CUSTOMIZER PHASE *** RDP Shortpath - Cannot add the registry key *** : [$($_.Exception.Message)]"
    Write-Log "Message: [$($_.Exception.Message)"]
}

# set up windows defender firewall

try {
    New-NetFirewallRule -DisplayName 'Remote Desktop - Shortpath (UDP-In)'  -Action Allow -Description 'Inbound rule for the Remote Desktop service to allow RDP traffic. [UDP 3390]' -Group '@FirewallAPI.dll,-28752' -Name 'RemoteDesktop-UserMode-In-Shortpath-UDP'  -PolicyStore PersistentStore -Profile Domain, Private -Service TermService -Protocol udp -LocalPort 3390 -Program '%SystemRoot%\system32\svchost.exe' -Enabled:True
}
catch {
    Write-Log "*** AVD AIB CUSTOMIZER PHASE *** Cannot create firewall rule *** : [$($_.Exception.Message)]"
}
 

$stopwatch.Stop()
$elapsedTime = $stopwatch.Elapsed
Write-Log "*** AVD AIB CUSTOMIZER PHASE : Configure RDP shortpath and Windows Defender Firewall  - Exit Code: $LASTEXITCODE ***"
Write-Log "*** AVD AIB CUSTOMIZER PHASE: Configure RDP shortpath and Windows Defender Firewall - Time taken: $elapsedTime ***"
 

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

