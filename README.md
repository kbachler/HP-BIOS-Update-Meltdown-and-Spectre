# HP-BIOS-Update-Meltdown-and-Spectre
HP BIOS Update: Meltdown and Spectre

This script performs a BIOS update for Meltdown and Spectre. This update is scripted specifically for HP models 840G3, 9470m, 9480m, z220, z230, z240, z420 and z440, and was deployed to 500+ computers through SCCM. All models have OS Windows 7 and PowerShell version 3. Here we check for an encrypted drive, if found we run a script to disable and re-enable the drive for the update. -Path is specific to the location of the model and the downloaded/extracted update from HP.

![alt text](https://github.com/kbachler/images/blob/master/4.JPG)
