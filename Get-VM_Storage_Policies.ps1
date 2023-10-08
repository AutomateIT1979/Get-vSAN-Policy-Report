# This script extracts the Rules from vSAN Storage Policies and formats into a report.
# Tested on vSphere 6.7 Update 3.
# Script Author: Nicholas Mangraviti #VirtuallyWired
# Date: 20th October 2019
# Version: 1.0
# Blog URL: virtuallywired.io
# Usage: Just enter the vCenter URL or IP and Specify the Names of Policies to Exclude from the Report.


# You can add multiple vCenter Servers. Note Credentials need to work on all vCenters.

$vCenter = ("172.18.3.10") 

# Prompt for vCenter Credentials

$Creds = Get-Credential # Or Import Stored Credentials

# If you want to Exclude specific vSAN Policies from the Report, Add the name of the policy to this Array.

[array]$SpbmExclude = ("Management Storage Policy - Large"," VVol No Requirements Policy"," Management Storage Policy - Stretched Lite","VM Encryption Policy","Management Storage policy - Encryption")

## Don't Edit Below This Line ##

Connect-VIServer -Server $vCenter -Credential $Creds

$VsanPolicies = Get-SpbmStoragePolicy | Where-Object { $_.AnyOfRuleSets -like "*VSAN*" -and $_.Name -notin $SpbmExclude }
$RuleSetReport = @()
Foreach ($VsanPolicy in $VsanPolicies) {

    $RuleSet = $VsanPolicy.AnyOfRuleSets.allOfRules

    $hostFailuresToTolerate = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.hostFailuresToTolerate" }).Value
    $subFailuresToTolerate = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.subFailuresToTolerate" }).Value
    $locality = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.locality" }).Value
    $checksumDisabled = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.checksumDisabled" }).Value
    $stripeWidth = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.stripeWidth" }).Value
    $forceProvisioning = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.forceProvisioning" }).Value
    $iopsLimit = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.iopsLimit" }).Value
    $cacheReservation = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.cacheReservation" }).Value
    $proportionalCapacity = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.proportionalCapacity" }).Value
    $replicaPreference = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.replicaPreference" }).Value

    $RuleSetReport += New-Object PSObject -Property ([ordered]@{
                
            StoragePolicyName      = $VsanPolicy.Name
            hostFailuresToTolerate = IF ($null -ne $hostFailuresToTolerate) { $hostFailuresToTolerate } else { "--" }
            subFailuresToTolerate  = IF ($null -ne $subFailuresToTolerate) { $subFailuresToTolerate } else { "--" }
            locality               = IF ($null -ne $locality) { $locality } else { "--" }            
            checksumDisabled       = IF ($null -ne $checksumDisabled) { $checksumDisabled } else { "--" }    
            stripeWidth            = IF ($null -ne $stripeWidth) { $stripeWidth } else { "--" }          
            forceProvisioning      = IF ($null -ne $forceProvisioning) { $forceProvisioning } else { "--" }    
            iopsLimit              = IF ($null -ne $iopsLimit) { $iopsLimit } else { "--" }           
            cacheReservation       = IF ($null -ne $cacheReservation) { $cacheReservation } else { "--" }     
            proportionalCapacity   = IF ($null -ne $proportionalCapacity) { $proportionalCapacity } else { "--" }  
            replicaPreference      = IF ($null -ne $replicaPreference) { $replicaPreference } else { "RAID-0 (No Data Redundancy)" }
            vCenter                = ([regex]::Matches($VsanPolicy.Uid, '@(.+):').Groups[1].Value)     

        })
}

Disconnect-VIServer * -Force -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

$RuleSetReport | Format-Table -Property *
