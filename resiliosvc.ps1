<#
    .Synopsis 
        Manages Resilio Sync as Service on Core Server
        
    .Description
        This script install, remove or update the Resilio Sync Service on the Windows Core Server where default 
		setup doesn't work. It offers three operations:
		- Info shows information about the service
		- Install the service under LocalService account.
		- Delete already installed service
		- Update service binary

		
	.Parameter Action    
        Specify required action: info, install, delete or update
 
    .Parameter SourceDir    
		Valid for install and update. Specifies the directory, where the Resilio binary and optionally sync.conf are stored"
		If empty, script expects these files in current directory

    .Parameter BinaryDestination
		Valid for install. Specifies a folder where the Resilio Sync service will be installed
		Default value is C:\ProgramData\Resilio Sync Service

	.Example
        resilio_svc.ps1 info
		Shows information about the service - If is installed or not and other parameters

    .Example
        resilio_svc.ps1 install -SourceDir C:\res_src
		Install the service binary from source C:\res_src directory

	.Example
        resilio_svc.ps1 install -SourceDir C:\res_src -BinaryDestination C:\ResilioSvc
		Install the service binary from source C:\res_src directory to destination C:\ResilioSvc
		
    .Example
        resilio_svc.ps1 update -SourceDir C:\res_src
		Updates the service binary by new binary from source C:\res_src directory

    .Example
        resilio_svc.ps1 delete
		Uninstall the service.
	
    .Notes
        NAME:      resiliosvc.ps1
        AUTHOR:    Zdenek Polach
		WEBSITE:   https://polach.me

#>
[CmdletBinding(SupportsShouldProcess=$True)]
Param(
	[Parameter(Mandatory=$True,Position=1)][ValidateSet("info","install","delete","update")][string]$Action,
	[ValidateScript({Test-Path $_})][string]$SourceDir =".\",
	[string]$BinaryDestination ="C:\ProgramData\Resilio Sync Service" 
)

#Name of the service as registered in the system
$serviceName = "rslsyncsvc"
#Display name of the service, as shown in Service Manager
$displayName ="Resilio Sync Service"
#name of the resilio sync executable
$executableFileName = "Resilio Sync.exe"
#name off the config file
$configFileName ="sync.conf"
#storage folder
$storageFolder = "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\Resilio Sync Service"

#firewall rule names
$tcpRuleName = "Resilio Sync Service TCP"
$udpRuleName = "Resilio Sync Service UDP"

function IsServiceInstalled {   
	param($ServiceName)

	if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue -ErrorVariable WindowsServiceExistsError)
    {
       return $true
    }
    return $false
}

function IsServiceRunning {
	param($ServiceName)

	$arrService = Get-Service -Name $ServiceName
	if ($arrService.Status -eq "Running"){ 
		return $true
	}
	return $false
}
function StartService {
	param($ServiceName)
	if( IsServiceRunning($ServiceName) ){
		return $true
	}
	Start-Service -Name $ServiceName -ErrorAction SilentlyContinue #| Out-Null
	if( IsServiceRunning($ServiceName) ){
		return $true
	}
	return $false
}

function StopService{
	param($ServiceName)
	if( IsServiceRunning($ServiceName) ){
		Stop-Service -Name $ServiceName -ErrorAction SilentlyContinue | Out-Null
		if( IsServiceRunning($ServiceName) ){
			return $false
		}else{
			return $true
		}
	} else{
		return $true
	}

}
function ServiceInfo{

	param($ServiceName, [ref]$svcBinDir)

	Write-Host "Checking Service ""$ServiceName"" status..."
	$srvObj = Get-WmiObject win32_service -filter "Name='$ServiceName'"
	if(!$srvObj){
		Write-Host "Service ""$ServiceName"" is not installed" -ForegroundColor Red
		return $false
	}
	Write-Host "Service ""$ServiceName"" is  installed" -ForegroundColor green
	$userName = $srvObj.StartName
	$mode = $srvObj.StartMode
	Write-Host "Service account is: ""$userName"" account" -ForegroundColor green
	Write-Host "Service start mode is: ""$mode""" -ForegroundColor green
	if(IsServiceRunning($ServiceName)){
		Write-Host "Service state is running" -ForegroundColor green
	}else{
		Write-Host "Service state is stopped" -ForegroundColor green
	}
	$svcPath = $srvObj.PathName
	Write-Host "Service path is: $svcPath" -ForegroundColor Green
	#extract directory - remove quotations, if any
	$pure =  $svcPath -replace '"', ""
	$index = $pure.IndexOf('/SVC')
	if ($index -ge 0) {
		$pure = $pure.Substring(0, $pure.IndexOf('/SVC'))
	}
	$svcDir = Split-Path $pure
	Write-Host "Service binary folder is: $svcDir" -ForegroundColor Green
	$svcBinDir.Value = $svcDir
	return $true

}
function DeleteFolderWithConfirmation{
	param($folderPath)
	$title = "Delete Folder with Files"
	$message = "Do you want to delete the Folder $folderPath and files in the folder?"
	$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", `
    "Deletes all the files in the folder."
	$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", `
    "Retains all the files in the folder."

	$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

	$result = $host.ui.PromptForChoice($title, $message, $options, 0) 

	switch ($result)
		{
			0 {Remove-Item –path $folderPath -Recurse -force -ErrorAction SilentlyContinue}
			1 {}
		}

}

function DeleteService{
	param($ServiceName)
	if(-Not(IsServiceInstalled($ServiceName) ) ){
		Write-Host "Service ""$ServiceName"" is  not installed" -ForegroundColor red
		return $false
	}
	$binDir=""
	ServiceInfo $serviceName ([ref]$binDir)
	Write-Host "Going to stop and delete the service ""$ServiceName""..."
	
	if(-Not(StopService($ServiceName))){
		Write-Host "Unable to stop Service ""$ServiceName""!!!" -ForegroundColor red
		return $false
	}
	(Get-WmiObject Win32_Service -filter "name='$ServiceName'").Delete() | Out-Null
	if(IsServiceInstalled($ServiceName) ){
		Write-Host "Unable to remove Service ""$ServiceName""!!!" -ForegroundColor red
		return $false
	}else{
		Write-Host "Service ""$ServiceName"" Succesfully removed" -ForegroundColor green
	}
	Write-Host "Going to remove firewall rules...."


	if(Get-NetFirewallRule -DisplayName $tcpRuleName -ErrorAction SilentlyContinue ){
		Remove-NetFirewallRule -DisplayName $tcpRuleName -ErrorAction SilentlyContinue | Out-Null
		if(-Not(Get-NetFirewallRule -DisplayName $tcpRuleName -ErrorAction SilentlyContinue )){
			Write-Host "The firewall rule ""$tcpRuleName"" succesfully deleted." -ForegroundColor green
		}else{
			Write-Host "Unable to delete the firewall rule ""$tcpRuleName""" -ForegroundColor red
		}
	}
	#udp rule
	if(Get-NetFirewallRule -DisplayName $udpRuleName -ErrorAction SilentlyContinue ){
		Remove-NetFirewallRule -DisplayName $udpRuleName -ErrorAction SilentlyContinue | Out-Null
		if(-Not(Get-NetFirewallRule -DisplayName $udpRuleName -ErrorAction SilentlyContinue )){
			Write-Host "The firewall rule ""$udpRuleName"" succesfully deleted." -ForegroundColor Green
		}else{
			Write-Host "Unable to delete the firewall rule ""$udpRuleName""" -ForegroundColor red
		}
	}
	Write-Host "Firewall rules succesfully deleted" -ForegroundColor Green
	#now remove the exe file 
	$exePath = Join-Path -Path $binDir -ChildPath $executableFileName
	if(-Not (Test-Path -Path $exePath -ErrorAction SilentlyContinue) ) {
		Write-Host "Service Executable ""$executableFileName"" doesn't exist in service folder ""$binDir""!" -foregroundcolor red	
		Write-Host "Please clean files manualy.. Unable to continue with delete operation." -foregroundcolor red	
		return $false
	}
	Remove-Item –path $exePath -force -ErrorAction SilentlyContinue | Out-Null
	if(-Not (Test-Path -Path $exePath -ErrorAction SilentlyContinue) ) {
		Write-Host "Succesfully deleted ""$executableFileName"" in service folder" -foregroundcolor green	
	} else {
		Write-Host "Unable to delete Executable file ""$executableFileName"" in service folder!!" -foregroundcolor red	
		Write-Host "Please clean files manualy.. Unable to continue with delete operation." -foregroundcolor red	
		return $false
	}
	#now remote the folder. But, just if 
	Write-Host "Going to delete service folder ""$binDir""...."
	DeleteFolderWithConfirmation $binDir
	if(-Not (Test-Path -Path $binDir -ErrorAction SilentlyContinue) ) {
		Write-Host ""
		Write-Host "Succesfully deleted ""$binDir"" folder" -foregroundcolor green	
		Write-Host ""
	} else {
		Write-Host ""
		Write-Host "WARNING: Unable to delete ""$binDir"" folder!!" -foregroundcolor Yellow	
		Write-Host "Please clean files manualy.. " -foregroundcolor Yellow	
		Write-Host ""
	}
	Write-Host "Going to delete storage folder ""$storageFolder""...."
	Write-Host "WARNING: The storage folder can contains imporant data." -foregroundcolor Yellow	
	DeleteFolderWithConfirmation $storageFolder
	if(-Not (Test-Path -Path $storageFolder -ErrorAction SilentlyContinue) ) {
		Write-Host ""
		Write-Host "Succesfully deleted ""$storageFolder"" folder" -foregroundcolor green	
		Write-Host ""
	} else {
		Write-Host ""
		Write-Host "WARNING: Unable to delete ""$storageFolder"" folder!!" -foregroundcolor Yellow	
		Write-Host "Please clean files manualy.. " -foregroundcolor Yellow	
		Write-Host ""
	}
	Write-Host "The service ""$displayName"" and their files has been succesfully removed." -ForegroundColor Green
}

function UpdateService{
	if(-Not(IsServiceInstalled($serviceName) ) ){
		Write-Host "Service ""$serviceName"" is  not installed" -ForegroundColor red
		Write-Host "Unable to update the service" -ForegroundColor red
		return $false
	}
	#check if exectutable source exists
	$binarySource = Join-Path -Path $SourceDir -ChildPath $executableFileName
	if(-Not (Test-Path -Path $binarySource -ErrorAction SilentlyContinue) ) {
		Write-Host "Source Executable file ""$executableFileName"" doesn't exist in  ""$SourceDir""!" -foregroundcolor red	
		Write-Host "No file for update" -foregroundcolor red	
		return $false
	}
	$binDir=""
	ServiceInfo $serviceName ([ref]$binDir)
	Write-Host "Going to update ""$executableFileName"" in the ""$binDir"" folder..." 
	$exeDestPath = Join-Path -Path $binDir -ChildPath $executableFileName
	if(-Not (Test-Path -Path $exeDestPath -ErrorAction SilentlyContinue) ) {
		Write-Host "Service Executable ""$executableFileName"" doesn't exist in service folder ""$binDir""!" -foregroundcolor red	
		Write-Host "Unable to continue with update" -foregroundcolor red	
		return $false
	}
	if(-Not(StopService $ServiceName)){
		Write-Host "Unable to stop Service ""$serviceName""!" -foregroundcolor red	
		Write-Host "Unable to continue with update" -foregroundcolor red	
		return $false
	}
	#delete the file if exist to put here fresh validated copy
	Remove-Item –path $exeDestPath -force -ErrorAction SilentlyContinue | Out-Null
	if(-Not (Test-Path -Path $exeDestPath -ErrorAction SilentlyContinue) ) {
		Write-Host "Succesfully deleted ""$executableFileName"" in destination folder" -foregroundcolor green	
	} else {
		Write-Host "Unable to delete Executable file ""$executableFileName"" in destination!!" -foregroundcolor red	
		return $false
	}
	#copy new item
	Copy-Item $binarySource $binDir
	if(Test-Path -Path $exeDestPath -ErrorAction SilentlyContinue) {
		Write-Host "Executable file ""$executableFileName"" successfully updated in destination" -foregroundcolor green	
	} else {
		Write-Host "Unable to copy ""$executableFileName"" to destination ""$BinaryDestination""" -foregroundcolor red
		return $false
	}
	#and finally start the service again
	if(-Not(StartService $ServiceName)){
		Write-Host "Unable to start Service ""$serviceName"" again!" -foregroundcolor red	
		return $false
	}
	Write-Host "Update of the ""$executableFileName"" in the ""$binDir"" folder was succesfull." -ForegroundColor Green
	return $true
}
function InstallService
{
	$startUpType ="Automatic"
	$description = "Enables you to synchronise specific folders between standalone devices. If you disable or stop this service, Resilio Sync will not keep your data up to date, which may result in conflicts and possible overwriting of changes made on this device."	
	
	#$storageFolder = "E:\Storage\Resilio Sync Service"
	Write-Host "Installing ""$displayName"" to the ""$BinaryDestination"" folder..." -foregroundcolor white
	#check if the service is not already installed
	if (IsServiceInstalled($serviceName)){
		Write-Host "The ""$displayName"" is already installed. Can't continue with install!" -foregroundcolor red
		return $false
	}
	#check if exectutable source exists
	$binarySource = Join-Path -Path $SourceDir -ChildPath $executableFileName
	if(-Not (Test-Path -Path $binarySource -ErrorAction SilentlyContinue) ) {
		Write-Host "Executable file ""$executableFileName"" doesn't exist in  ""$SourceDir""!" -foregroundcolor red	
		return $false
	}
	#check if executable is not already copied to the destination
	$exePath = Join-Path -Path $BinaryDestination -ChildPath $executableFileName
	if(Test-Path -Path $exePath -ErrorAction SilentlyContinue) {
		Write-Host "Warning: Executable file ""$executableFileName"" already exist in destination!!" -foregroundcolor yellow	
		#delete the file if exist to put here fresh validated copy
		Remove-Item –path $exePath -force -ErrorAction SilentlyContinue | Out-Null
		if(-Not (Test-Path -Path $exePath -ErrorAction SilentlyContinue) ) {
			Write-Host "This file has been succesfully deleted" -foregroundcolor green	
		} else {
			Write-Host "Unable to delete Executable file ""$executableFileName"" in destination!!" -foregroundcolor red	
			return $false
		}
	}
	#create path to the executable on destination if not exist yet
	New-Item -path $BinaryDestination -type directory -ErrorAction SilentlyContinue | Out-Null
	if(Test-Path -Path $BinaryDestination -ErrorAction SilentlyContinue) {
		#copy file to destination
		Copy-Item $binarySource $BinaryDestination
		if(Test-Path -Path $exePath -ErrorAction SilentlyContinue) {
			Write-Host "Executable file ""$executableFileName"" successfully copied to destination" -foregroundcolor green	
		} else {
			Write-Host "Unable to copy ""$executableFileName"" to destination ""$BinaryDestination""" -foregroundcolor red
			return $false
		}
	}else{
		Write-Host "Unable to create destination folder ""$BinaryDestination""" -foregroundcolor red
		return $false
	}
	#check if sync.conf is in source directory
	$confSource = Join-Path -Path $SourceDir -ChildPath $configFileName
	if(Test-Path -Path $confSource -ErrorAction SilentlyContinue) {
		#config is present. Copy it to the storage folder
		Write-Host "Config file ""$configFileName"" found. Copying it to Storage Folder..." -foregroundcolor white	
		#create storage folder
		New-Item -path $storageFolder -type directory -ErrorAction SilentlyContinue | Out-Null
		if(-Not (Test-Path -Path $storageFolder -ErrorAction SilentlyContinue) ){
			Write-Host "Unable to create Storage Folder ""$storageFolder""" -foregroundcolor red
			return $false
		}
		#copy file to destination
		Copy-Item $confSource $storageFolder -Force
		$confDest = Join-Path -Path $storageFolder -ChildPath $configFileName
		if(-Not (Test-Path -Path $confDest -ErrorAction SilentlyContinue) ){
			Write-Host "Unable to copy ""$configFileName"" to Storage Folder!!" -foregroundcolor red
			return $false
		}
		Write-Host "The file ""$configFileName"" sucessfully copied to Storage Folder" -foregroundcolor green
	} else {
		Write-Host "Config file ""$configFileName"" not found found." -foregroundcolor yellow	
		Write-Host "Service will be configured by default values" -foregroundcolor yellow	
	}

	##All files are in place. Now install the service ###

	#Create credentials for the LocalService account. Service will run as LocalService
	$pwd = ConvertTo-SecureString -String "dummy" -AsPlainText -Force
	$login="NT AUTHORITY\LocalService"
	$creds = New-Object System.Management.Automation.PSCredential($login, $pwd)

	
	$binaryPath ="""$exePath"" /SVC -n rslsyncsvc"
	Write-Host "Creating ""$displayName"" Service record..." -foregroundcolor white
	New-Service -name $serviceName -binaryPathName $binaryPath -displayName $displayName -startupType Automatic -credential $creds -ErrorAction SilentlyContinue | Out-Null
	if (-Not (IsServiceInstalled($serviceName) ) ){
		Write-Host "Creating of the ""$displayName"" service record failed!" -foregroundcolor red
		return $false
	}
	#Ok, we now have a service. Modify startup to delayed
	$command = "sc.exe config $serviceName start= delayed-auto"
	$Output = Invoke-Expression -Command $Command -ErrorAction SilentlyContinue
	if($LASTEXITCODE -ne 0){
		Write-Host "Warning: Failed to set $serviceName to delayed start. More details: $Output" -foregroundcolor yellow
	} else {
		Write-Host "Successfully changed $serviceName service to delayed start" -foregroundcolor green
	}
	#Now create a firewall rules for the service
	Write-Host "Creating ""Resilio Sync"" firewall rules..." -foregroundcolor white
	#tcp rule
	$ruleObj = Get-NetFirewallRule -DisplayName $tcpRuleName -ErrorAction SilentlyContinue 
	if($ruleObj){
		Write-Host "WARNING: The firewall rule ""$tcpRuleName"" already exists!! Re-Creating the rule.." -ForegroundColor Yellow
		Remove-NetFirewallRule -DisplayName $tcpRuleName -ErrorAction SilentlyContinue | Out-Null
		$ruleObj = Get-NetFirewallRule -DisplayName $tcpRuleName -ErrorAction SilentlyContinue 
		if(!$ruleObj){
			Write-Host "The old firewall rule ""$tcpRuleName"" succesfully deleted.." -ForegroundColor Yellow
		}else{
			Write-Host "Unable to delete the firewall rule ""$tcpRuleName""" -ForegroundColor red
		}
	}
	New-NetFirewallRule -DisplayName $tcpRuleName -Direction Inbound -Program $exePath -Protocol TCP -EdgeTraversalPolicy Allow -Action Allow -ErrorAction SilentlyContinue | Out-Null
	$ruleObj = Get-NetFirewallRule -DisplayName $tcpRuleName -ErrorAction SilentlyContinue 
	if(!$ruleObj){
		Write-Host "Unable to create the firewall rule ""$tcpRuleName""" -ForegroundColor red
		return $false
	}
	#udp rule
	$ruleObj = Get-NetFirewallRule -DisplayName $udpRuleName -ErrorAction SilentlyContinue 
	if($ruleObj){
		Write-Host "WARNING: The firewall rule ""$udpRuleName"" already exists!! Re-Creating the rule.." -ForegroundColor Yellow
		Remove-NetFirewallRule -DisplayName $udpRuleName -ErrorAction SilentlyContinue | Out-Null
		$ruleObj = Get-NetFirewallRule -DisplayName $udpRuleName -ErrorAction SilentlyContinue 
		if(!$ruleObj){
			Write-Host "The old firewall rule ""$udpRuleName"" succesfully deleted.." -ForegroundColor Yellow
		}else{
			Write-Host "Unable to delete the firewall rule ""$udpRuleName""" -ForegroundColor red
		}
	}
	New-NetFirewallRule -DisplayName $udpRuleName -Direction Inbound -Program $exePath -Protocol UDP -EdgeTraversalPolicy Allow -Action Allow -ErrorAction SilentlyContinue | Out-Null
	$ruleObj = Get-NetFirewallRule -DisplayName $udpRuleName -ErrorAction SilentlyContinue 
	if(!$ruleObj){
		Write-Host "Unable to create the firewall rule ""$udpRuleName""" -ForegroundColor red
		return $false
	}
	Write-Host """Resilio Sync"" firewall rules created succesfully." -foregroundcolor green
	Write-Host "Going to start the service $serviceName ..."
	if (-Not(StartService $serviceName) ){
		Write-Host "Warning: Unableto start  $serviceName !" -foregroundcolor yellow
		return $true
	}else{
		Write-Host "The service $serviceName has been succesfully installed and started." -foregroundcolor green
	}
	return $true
}

switch($Action)
{
	"info" {$doui = "aa" ; ServiceInfo $serviceName ([ref]$doui) ;	break	}
	"install" {write-host "Service Install is requested" ;InstallService;  break}
	"delete" { write-host "Service Delete is requested" ; DeleteService $serviceName ; break }
	"update"{ write-host "Service Update is requested" ; UpdateService ;break }
}


