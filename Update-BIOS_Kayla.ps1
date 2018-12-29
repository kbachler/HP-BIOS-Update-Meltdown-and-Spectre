#--------------------------------------------------------------------------------------------------------------------------------------------------
# 09-04-2018 Kayla Bachler
# Script to install BIOS update on HP machines for Meltdown and Spectre.
# If the drive is encrypted we want to disable it from flashing BIOS
#
# SYNTAX for HPQFlash and HPBIOSUPDREC :

<# HPQFlash [-s] [-pPasswordFile] [-fROMBINFile] [-a] [-u] [-h] [-?]
    -s: Silent mode.
    -p: Specify encrypted password file created with the HpqPswd utility.
    -f: Specify ROM BIN file. Default is BIN file in same folder as exe.
    -a: (Silent mode only) Always flash, ignore version comparison.
    -u: (Silent mode only) microcode update.
    -h: Create HP_TOOLS partition if not present.
    -?: Display usage.
#>
<# HPBiosUpdRec [-s] [-pPasswordFile] [-fROMBINFile] [-a] [-h] [-?]
    -s: Silent mode.
    -p: Specify encrypted password file created with the HpqPswd utility.
    -f: Specify ROM BIN file. Default is BIN file in same folder as exe.
    -a: (Silent mode only) Always flash, ignore version comparison.
    -h: Create HP_TOOLS partition if not present.
    -?: Display usage.
    -b: Suspend BitLocker if needed.
    -r: Do not reboot after the BIOS update.
#> 
# References: 
# https://msdn.microsoft.com/en-us/library/windows/desktop/aa376483(v=vs.85).aspx
# http://balazsberki.com/2016/12/powershell-and-scheduling/
# https://community.spiceworks.com/topic/2005262-command-line-syntax-to-update-password-protected-bios?utm_source=copy_paste&utm_campaign=growth 
#--------------------------------------------------------------------------------------------------------------------------------------------------
# Only needed for locally running the script:
# Set-Location -Path \\snopud.com\root\DCM\Scripts\HP\Meltdown_Spectre
# Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell" -Name "ExecutionPolicy"
# Set-ExecutionPolicy Bypass

Push-Location $PSScriptRoot\..  # Go to directory where script exists
$logfile = ".\logs\$env:COMPUTERNAME.txt"  # Logging txt file for script outputs

# Get state of local machine protection: Disabled = empty/null, Enabled = data
$pState = gwmi -Namespace root/CIMV2/Security/MicrosoftVolumeEncryption -class Win32_EncryptableVolume
$model = (Get-WmiObject Win32_Computersystem).model  # Model of local machine
$repeatCount = 3
$batteryStatus = (Get-WmiObject Win32_Battery).batterystatus
$batteryErrorCode = 228377 #Stands for BATERR

#If the laptop is not connected to AC adapter return error code
if ($batteryStatus -eq "1") {
    Exit $batteryErrorCode
}

# Trims the model name to the modelpath we need for our file directory
function setModelPath{ 
param($inModel)
    switch -Wildcard ($inModel){
        'HP EliteBook 840 G3*' { $modelpath = '840G3' }
        'HP EliteBook Folio 9470m*'  { $modelpath = '9470m' }
        'HP EliteBook Folio 9480m*'  { $modelpath = '9480m' }
        'HP Z220*'   { $modelpath = 'z220' }
        'HP Z230*'  { $modelpath = 'z230' }
        'HP Z240*'  { $modelpath = 'z240' }
        'HP Z420*'  { $modelpath = 'z420' }
        'HP Z440*'  { $modelpath = 'z440' }
        default   {$modelpath = 'unknown' }
    }
    return $modelpath
}
"Model: $model" | Out-File -FilePath $logfile -Append

# Assign the model path based on the system model for local machine
$modelpath = setModelPath($model)
"ModelPath: $modelpath" | Out-File -FilePath $logfile -Append

# If the local machine is one of these models: z220, z230, 9470m or z420, step into
if ($modelpath -eq "z220" -or $modelpath -eq "z230" -or $modelpath -eq "z420" -or $modelpath -eq "9470m"){ 
    "$modelpath is an older model (z220, z230, 9470m or z420)" | Out-File -FilePath $logfile -Append
    # Step into if local machine is protected/bitlocker enabled
    if ($pState -ne $null -and $pState -ne 0) {

        # GetProtectionStatus: Indicates the status of security for the encryption key
        # 0 = Decrypted, 1 = Encrypted, 2 = Unknown
        $pStatus = $pState.GetProtectionStatus().protectionstatus
     
        # If the PC is encrypted, disable Bitlocker
        if ($pStatus -eq 1) {
            "This PC is encrypted: 1" | Out-File -FilePath $logfile -Append
            Start-Process -FilePath -Wait ".\Scripts\DisableBitlocker.cmd" -Verb RunAs

            <# The following chunk of code is responsible for creating a scheduled task in Windows Task Scheduler to 
               re-enable Bitlocker. After the install.cmd has ran, the PC is rebooted, bitlocker is enabled, then
               the scheduled task is deleted.
            #>
            $Hostname = $env:COMPUTERNAME
            $taskRunAsuser = "SYSTEM"
            # Create the object for our scheduled task
            $service = New-Object -ComObject("Schedule.Service")
            $service.Connect($Hostname)
            #$rootFolder = $service.GetFolder("\Microsoft\Windows\Powershell")
            $rootFolder = $service.GetFolder("\")

            # Complete the Task description
            $taskDefinition = $service.NewTask(0)
            $regInfo = $taskDefinition.RegistrationInfo
            $regInfo.Description = 'Enable Bitlocker after BIOS update'

            # Create Triggers for the task - Our trigger is run task at startup
            $triggers = $taskDefinition.Triggers
            $trigger = $triggers.Create(8)
            $trigger.Id = "StartUpTriggerId"
            $trigger.Enabled = $True

            # Create Actions for the task. Our action is to call the EnableBitlocker.cmd
            $command = ".\Scripts\HP\Meltdown_Spectre\Scripts\EnableBitlocker.cmd"
            $Action = $taskDefinition.Actions.Create(0)
            $Action.Path = $command

            # Create Task for Task Scheduler - Returns task creation-status as failed or succeeded
            try {
              $res = $rootFolder.RegisterTaskDefinition( "EnableBitlocker", $taskDefinition, 2, $taskRunAsuser , $taskRunasUserPwd , 2) | Out-String
            } catch {
              "ERROR: Failed While Attempting to Create Windows Scheduled Task: "| Out-File -FilePath $logfile -Append
              $_ | Out-File -FilePath $logfile -Append
            }

            if ($res -like "*<RegistrationInfo>*") {
              $res
              "SUCCESS: Windows Scheduled Task was Created!"| Out-File -FilePath $logfile -Append
            }
        }
    }
    # Run install.cmd script for BIOS upgrade
    "Running install script for $env:COMPUTERNAME ($modelpath)" | Out-File -FilePath $logfile -Append
    Start-Process -Wait -FilePath ".\Content\$modelpath\install.cmd"  #We want forced reboot here, -r not recognized??
    "COMPLETE: Installed BIOS script for $env:COMPUTERNAME ($modelpath)" | Out-File -FilePath $logfile -Append
} else {
    # Run install for updated BIOS - Newer models:
    "Newer Model (z240, z440, 9480m or 840G3)" | Out-File -FilePath $logfile -Append
    "Running install script for $env:COMPUTERNAME ($modelpath)" | Out-File -FilePath $logfile -Append
    Start-Process -Wait -FilePath ".\Content\$modelpath\install.cmd"
    "COMPLETE: Installed BIOS script for $env:COMPUTERNAME ($modelpath)" | Out-File -FilePath $logfile -Append
}