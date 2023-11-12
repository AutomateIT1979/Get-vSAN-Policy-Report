# A PowerCLI script that retrieves VSAN related info and outputs it in HTML format.
# Jason Fenech (Aug 16)
#----------------------------------------------------------[Libraries]-----------------------------------------------
# Uncomment the 2 lines below if running script using PowerShell (not PowerCLI)
#
Import-Module VMware.VimAutomation.Core -ErrorAction SilentlyContinue
Import-Module VMware.VimAutomation.Storage -ErrorAction SilentlyContinue
#----------------------------------------------------------[Declarations]--------------------------------------------
#Change the following as required
####################################################################################
$vSANFile = ".\vsan.html"                   #Path to generated report
$vCenter="172.18.123.36"                           #vCenter hostname or IP Address
$clusName = "Cluster-PICCOLO"                        #Cluster name
$user="administrator@vsphere.local"                                      #vCenter Server user
$pass="BGpzbyZSm6*"                                  #vCenter Server user's password
$vSANPolName="Virtual SAN Default Storage Policy" #vSAN Storage Policy - Assuming default name
$vSANDSName="vsanDatastore"                       #Default name for the VSAN DS
####################################################################################

$vSANIssues=""                                    #Holds VSAN error / warning msg
$dn=0                                             #Disk counter

#Style applied to tables
$style = @"
table {
font-family: arial, sans-serif;
border-collapse: collapse;
}
 td, th {
 border: 1px solid #dddddd;
 text-align: left;
 padding: 8px;
 font-size: 14px;
}
 tr:nth-child(1) {
 background-color: #ddcccc;
}
"@
#----------------------------------------------------------[Execution]-----------------------------------------------
#Drop any existing open VI connections and connect to vCenter Server $vCenter
try{
   Disconnect-VIServer * -force -Confirm:$false -ErrorAction SilentlyContinue
   Connect-VIServer -Server $vCenter -User $user -Password $pass -ErrorAction Stop
}
catch{
   Write-Host "Failed to connect to vCenter Server $vCenter"
   exit                                           #Exit script on error
}

#Retrieve cluster and vSAN info
$Clus = Get-Cluster -Name $ClusName
$vSanDisks = Get-VSanDisk
$vSanDGroups = Get-VsanDiskGroup
$vSANPolicy = (Get-SpbmStoragePolicy -Name $vSANPolName).AnyOfRuleSets.allofrules
$vSANDS = (Get-Datastore -Name $vSANDSName)

#Write HTML doc header
(@"
<!DOCTYPE html>
<head>
 <title>VSAN Report</title>
 <style>$style</style>
</head>
 <body>
  <h2>VSAN Report - Cluster $ClusName</h2><hr>
"@) | Out-File $vSANFile -Append

#--------------------------------------------------------------------------------------------------------------------
#Write vSAN General Info Table Header and Data
(@"
<br>
<font color=#2F2F2F><h3>General Info</h3></font>
<table>
 <tr>
  <th>VSAN enabled?</th>
  <th>Disk Groups</th>
  <th>SSD Disks</th>
  <th>Non-SSD Disks</th>
  <th>Disk Claim Mode</th>
 </tr>
 <tr>
  <td>$($clus.VsanEnabled)</td>
  <td>$(($vSanDGroups).count)</td>
  <td>$(($vSanDisks | Where-Object {$_.IsSSD -eq "True"}).count)</td>
  <td>$(($vSanDisks | Where-Object {$_.IsSSD -ne "True"}).count)</td>
  <td>$($clus.VsanDiskClaimMode)</td>
 </tr>
</table>
"@) | Out-File $vSANFile -Append

#--------------------------------------------------------------------------------------------------------------------
#Check if there are any issues related to the VSAN config
if ($Clus.ExtensionData.ConfigIssue.ObjectName -eq "VSAN")
   {$vSANIssues = $Clus.ExtensionData.ConfigIssue[0].FullFormattedMessage}

#vSAN Health Table Header and Data
(@"
<br>
<font color=#2F2F2F><h3>Health</h3></font>
 <table>
  <tr>
   <th>Issues</th>
  </tr>
  <tr>
   <td>$vSANIssues</td>
  </tr>
 </table>
"@) | Out-File $vSANFile -Append

#--------------------------------------------------------------------------------------------------------------------
#vSAN Disks Info Table Header and Data
(@"
<br>
<font color=#2F2F2F><h3>Disks</h3></font>
 <table>
  <tr>
   <th>Disk #</th>
   <th>Name</th>
   <th>Health</th>
   <th>Vendor</th>
   <th>Model</th>
   <th>SSD</th>
   <th>Size (GB)</th>
   <th>Queue Depth</th>
   <th>Format Ver.</th>
   <th>vSAN UIID</th>
   <th>ESXi Host</th>
   <th>Disk Group</th>
  </tr>
"@) | Out-File $vSANFile -Append

#Return data for every vSAN disk found
$vSanDisks | ForEach-Object {
    $diskSize = ($_.ExtensionData.Capacity.BlockSize * $_.ExtensionData.Capacity.Block) / (1024*1024*1024);

$health = $_.ExtensionData.OperationalState
 if ($health -eq "ok") {$health="<font color=""green""><b>Healthy</b></font>"}
   else {$health="<font color=""red""><b>Check Disk</b></font>"}
(@"
 <tr>
  <td>$dn</td>
  <td>$($_.Name)</td>
  <td>$health</td>
  <td>$($_.ExtensionData.Vendor)</td>
  <td>$($_.ExtensionData.Model)</td>
  <td>$($_.IsSsd)</td>
  <td>$diskSize</td>
  <td>$($_.ExtensionData.QueueDepth)</td>
  <td>$($_.ExtensionData.VsanDiskInfo.FormatVersion)</td>
  <td>$($_.ExtensionData.VsanDiskInfo.VsanUuid)</td>
  <td>$($_.VsanDiskGroup.vmhost.name)</td>
  <td>$($_.VsanDiskGroup)</td>
 </tr>
"@) | Out-File $vSANFile -Append

#Disk counter
 $dn++
}

#--------------------------------------------------------------------------------------------------------------------
#vSAN Datastore Table Header and Data

(@"
</table>
<br>
 <font color=#2F2F2F><h3>vSAN Datastore Details</h3></font>
 <table>
  <tr>
   <th>State</th>
   <th>Capacity (GB)</th>
   <th>Free Space (GB)</th>
   <th>ID</th>
  </tr>
  <tr>
   <td>$($vSANDS.State)</td>
   <td>$($vSANDS.CapacityGB)</td>
   <td>$($vSANDS.FreeSpaceGB)</td>
   <td>$($vSANDS.Id)</td>
  </tr> 
</table>
"@) | Out-File $vSANFile -Append

#--------------------------------------------------------------------------------------------------------------------
#vSAN Storage Policy Table Header and Data

(@"
</table>
 <br>
 <font color=#2F2F2F><h3>vSAN Storage Policy</h3></font>
<table>
<tr>
"@) | Out-File $vSANFile -Append

#Get rules set capabilities
$vSANPolicy | ForEach-Object {                                    
(@"
 <th>
  $($_.Capability)
 </th>
"@) | Out-File $vSANFile -Append
}

#Close current row and start a new one
"</tr><tr>" | Out-File $vSANFile -Append 

#Get rules set capabilities values
$vSANPolicy | ForEach-Object { 
(@"
 <td>
  $($_.value)
 </td>
"@) | Out-File $vSANFile -Append
}

#--------------------------------------------------------------------------------------------------------------------
#Write file tail
$(@"
</tr>
</table>
</body>
</html>
"@) | Out-File $vSANFile -Append