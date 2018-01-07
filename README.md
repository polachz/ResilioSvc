# ResilioSvc
PowerShell script to manage Resilio Sync Service on Windows Core Server or Workstations without Resilio setup

This script install, remove or update the Resilio Sync Service on the Windows Core Server where default setup doesn't work, because is not possible to fill appropriate credentials of the account uder the service will run.

This script installs the service under the LocalService account and configures the Windows Firewall exception. We just need to extract the "**Resilio Sync.exe**" from another installation of the Resilio Sync, for exemple from a workstation. This executable have to be placed to same directory as the script or we have to specify Source directory where the executable is placed as paremeter of the script.

The script also supports the *sync.conf* file. This file allows to change listening port of the web interface, can specify Storage path (must be in linux notation with slashs instead of windows backslashes) etc see [here](https://help.resilio.com/hc/en-us/articles/206178884-Running-Sync-in-configuration-mode) for details. Original example can be downloaded from the Resilio pages [here](http://internal.getsync.com/support/sample.conf). The sync.conf file have to be placed in same source directory as the "**Resilio Sync.exe**".

The main usage of the script is **resiliosvc.ps1 *action*** where the action can be:

* **Info**  - Shows information about the service
* **Install** -Installs the Resilio Sync Service under the LocalService account.
* **Delete** - Uninstalls already installed Resilio Sync Service
* **Update** - Updates service binary

Next supported parameters are:

* **SourceDir**
		Valid for install and update operations. Specifies the directory, where the Resilio binary and optionally sync.conf are stored If empty, script expects these files in current directory
* **BinaryDestination**
    Valid for install operation only, Specifies a folder where the Resilio Sync service will be installed Default value is *C:\ProgramData\Resilio Sync Service*
    
Examples of usage:

* **resilio_svc.ps1 info**

  Shows information about the service - If is installed or not and other parameters
* **resilio_svc.ps1 install -SourceDir C:\res_src**

  Install the service binary from source C:\res_src directory
* **Resilio_svc.ps1 install -SourceDir C:\res_src -BinaryDestination C:\ResilioSvc**

  Install the service binary from source C:\res_src directory to destination C:\ResilioSvc
* **resilio_svc.ps1 update -SourceDir C:\res_src**

  Updates the service binary by new binary from source C:\res_src directory
* **resilio_svc.ps1 delete**

  Uninstall the service.
