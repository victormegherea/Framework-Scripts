#!/usr/bin/powershell
#
#  Copy the latest kernel build from the secure share to the local directory,
#  then install it, set the default kernel, switch out this script for the
#  secondary boot replacement, and reboot the machine.
#
#  Start by cleaning out any existing downloads
#

$pw=convertto-securestring -AsPlainText -force -string 'Pa$$w0rd!'
$cred=new-object -typename system.management.automation.pscredential -argumentlist "psRemote",$pw
$s=new-PSSession -computername mslk-boot-test-host.redmond.corp.microsoft.com -credential $cred -authentication Basic

#
#  What OS are we on?
#
$linuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData
$c = $linuxInfo.ID
$c=$c -replace '"',""

function callItIn($c, $m) {
    $output_path="c:\temp\$c"
    
    $m | out-file -Append $output_path
    return
}

function phoneHome($m) {
    invoke-command -session $s -ScriptBlock ${function:callItIn} -ArgumentList $c,$m
}

phoneHome "Starting copy file scipt" 
cd /tmp
$kernFolder="./latest_kernel"
If (Test-Path $kernFolder) {
    Remove-Item -Recurse -Force $kernFolder
}
new-item $kernFolder -type directory

#
#  Now see if we can mount the drop folder
#
if ((Test-Path "/mnt/ostcnix") -eq 0) {
    mount /mnt/ostcnix
}

if ((Test-Path "/mnt/ostcnix/latest") -eq 0) {
    phoneHome "Latest directory was not on mount point!  No kernel to install!" 
    $LASTEXITCODE = 1
    exit $LASTERRORCODE
}

#
#  Copy the files
#
phoneHome "Copying the kernel from the drop share" 
cd /tmp/latest_kernel
copy-Item -Path "/mnt/ostcnix/latest/*" -Destination "./"

#
#  What OS are we on?
#
$linuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData
$linuxOs = $linuxInfo.ID
phoneHome "Operating system is $linuxOs"

#
#  Remove the old sentinel file
#
Remove-Item -Force "/root/expected_version"

#
#  Figure out the kernel name
#
$rpmName=(get-childitem kernel-[0-9]*.rpm).name
$kernelName=($rpmName -split ".rpm")[0]
phoneHome "Kernel name is $kernelName" 

#
#  Figure out the kernel version
#
$kernelVersion=($kernelName -split "-")[1]

#
#  For some reason, the file is -, but the kernel is _
#
$kernelVersion=($kernelVersion -replace "_","-")
phoneHome "Kernel version is $kernelVersion" 
$kernelVersion | Out-File -Path "/root/expected_version"

#
#  Do the right thing for the platform
#
if ($linuxOs -eq '"centos"') {
    #
    #  CentOS
    #
    $kernelDevelName="kernel-devel-"+(($kernelName -split "-")[1]+"-")+($kernelName -split "-")[2]
    phoneHome "Kernel Devel Package name is $kerneldevelName" 

    #
    #  Install the new kernel
    #
    phoneHome "Installing the RPM kernel devel package" 
    rpm -ivh $kernelDevelName".rpm"
    phoneHome "Installing the RPM kernel package" 
    rpm -ivh $kernelName".rpm"

    #
    #  Now set the boot order to the first selection, so the new kernel comes up
    #
    phoneHome "Setting the reboot for selection 0"
    grub2-reboot 0
} else {
    #
    #  Figure out the kernel name
    #
    $debKernName=(get-childitem linux-image-*.deb)[0].Name
    phoneHome "Debian Kernel name is $DebKernName" 

    #
    #  Construct the right version from the file name
    #
    $kernelVerionSplit=$kernelVersion -split "-"
    $kernelVersion=$kernelVersionSplit[2]+"-"+$kernelVersionSplit[4]
    phoneHome "Kernel version is $kernelVersion" 
    $kernelVersion | Out-File -Path "/root/expected_version"

    #
    #  Debian
    #
    $kernDevName=(get-childitem linux-image-*.deb)[1].Name
    phoneHome "Kernel Devel Package name is $kernDevName" 

    phoneHome "Installing the DEB kernel devel package" 
    dpkg -i $kernDevName

    phoneHome "Installing the DEB kernel package" 
    dpkg -i $debKernName

    #
    #  Now set the boot order to the first selection, so the new kernel comes up
    #
    phoneHome "Setting the reboot for selection 0"
    grub-set-default 0
}

#
#  Copy the post-reboot script to RunOnce
#
copy-Item -Path "/root/Framework-Scripts/report_kernel_version.ps1" -Destination "/etc/local/runonce.d"

phoneHome "Rebooting now..."

remove-pssession $s

reboot
