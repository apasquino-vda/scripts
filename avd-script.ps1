$WorkDir = "C:\ImageBuilder"
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$logFile = Join-Path $WorkDir "avd-patch-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

"--- AVD PATCH SCRIPT START $(Get-Date) ---" | Tee-Object -FilePath $logFile -Append
"User: $(whoami)" | Tee-Object -FilePath $logFile -Append

try {

    # script START
	
	Add-LocalGroupMember -Group 'FSLogix Profile Exclude List' -Member 'localadmin'

	$fsxKey = 'HKLM:\SOFTWARE\FSLogix\Profiles'

	# Create FSLogix Profiles key if needed
	New-Item -Path $fsxKey -Force | Out-Null

	# Enable FSLogix profile containers
	New-ItemProperty -Path $fsxKey -Name 'Enabled' -PropertyType DWord -Value 1 -Force | Out-Null

	# Point to your Azure Files share
	New-ItemProperty -Path $fsxKey -Name 'VHDLocations' -PropertyType String -Value '\\avdsmbtestap.file.core.windows.net\fslogix' -Force | Out-Null
	

	# Use VHDX, 30 GB example size
	New-ItemProperty -Path $fsxKey -Name 'VolumeType' -PropertyType String -Value 'vhdx' -Force | Out-Null
	New-ItemProperty -Path $fsxKey -Name 'SizeInMBs' -PropertyType DWord -Value 30000 -Force | Out-Null

	# Clean local profile once container is applied
	New-ItemProperty -Path $fsxKey -Name 'DeleteLocalProfileWhenVHDShouldApply' -PropertyType DWord -Value 1 -Force | Out-Null

	# (Optional but recommended) Use a clear include group for FSLogix users – adjust DOMAIN\Group
	#New-ItemProperty -Path $fsxKey -Name 'IncludeUserGroups' -PropertyType MultiString -Value @('DOMAIN\FSLogix_Profile_Users') -Force | Out-Null

	# (Optional) Exclude local admins from FSLogix
	#New-ItemProperty -Path $fsxKey -Name 'ExcludeUserGroups' -PropertyType MultiString -Value @('BUILTIN\Administrators') -Force | Out-Null



	# Enable Cloud Kerberos Ticket Retrieval
	$kerbKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters'
	New-Item -Path $kerbKey -Force | Out-Null
	New-ItemProperty -Path $kerbKey -Name 'CloudKerberosTicketRetrievalEnabled' -PropertyType DWord -Value 1 -Force | Out-Null

	# Allow loading the credential key from the profile
	$aadKey = 'HKLM:\Software\Policies\Microsoft\AzureADAccount'
	New-Item -Path $aadKey -Force | Out-Null
	New-ItemProperty -Path $aadKey -Name 'LoadCredKeyFromProfile' -PropertyType DWord -Value 1 -Force | Out-Null






	# Install Notepad++ (silent install)
	$nppPath = "C:\ImageBuilder\npp.8.6.Installer.x64.exe"
	Invoke-WebRequest -Uri "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.6/npp.8.6.Installer.x64.exe" -OutFile $nppPath
	Start-Process $nppPath -ArgumentList "/S" -Wait

    # TimeZone Redirection
	
	New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "fEnableTimeZoneRedirection" -PropertyType DWord -Value 1 -Force | Out-Null
	
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

	# List Available RSAT Tools
	# Get-WindowsCapability -Name RSAT* -Online | Select-Object -Property DisplayName, State

	# Install Specific Tool (Example - AD Tools)
	# Add-WindowsCapability -Online -Name "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"
	
	# Disable StorageSense

    #New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense" -Name "AllowStorageSenseGlobal" -PropertyType DWord -Value 0 -Force | Out-Null

	#Install ALL RSAT Tools
	#Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online


	# Download VDOT
	#$URL = 'https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/archive/refs/heads/main.zip'
	#$ZIP = 'VDOT.zip'
	#Invoke-WebRequest -Uri $URL -OutFile $ZIP -ErrorAction 'Stop'

	# Extract VDOT from ZIP archive
	#Expand-Archive -LiteralPath $ZIP -Force -ErrorAction 'Stop'
		
	# Run VDOT
	#& .\VDOT\Virtual-Desktop-Optimization-Tool-main\Windows_VDOT.ps1 -AcceptEULA -Restart


    # script end
	
    "Script running..." | Tee-Object -FilePath $logFile -Append

    "Script finished OK" | Tee-Object -FilePath $logFile -Append
}
catch {
    "ERROR: $($_.Exception.Message)" | Tee-Object -FilePath $logFile -Append
    "STACK: $($_.ScriptStackTrace)" | Tee-Object -FilePath $logFile -Append
    throw
}
finally {
    "--- AVD PATCH SCRIPT END $(Get-Date) ---" | Tee-Object -FilePath $logFile -Append
}




