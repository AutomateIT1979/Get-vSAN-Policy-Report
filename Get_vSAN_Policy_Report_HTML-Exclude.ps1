<#
.COMPONENT
    Script PowerShell
.NOTES
    Auteur: Sabri CHARCHOUF
    Date : 08 octobre 2023
    Entreprise: Ecritel
    Version: 1.0
.DESCRIPTION
    Le script permet de récuérer les règles de chaque vSAN Policy suivantes :
        - Management Storage Policy - Large
        - VVol No Requirements Policy
        - Management Storage Policy - Stretched Lite
        - VM Encryption Policy
        - Management Storage policy - Encryption
        - Management Storage Policy - Single Node
        - Management Storage policy - Thin
        - Host-local PMem Default Storage Policy
        - vSAN Default Storage Policy
        - Management Storage Policy - Regular
        - SP-ENCRYPTION-VM
        - Management Storage Policy - Stretched
.SYNOPSIS
    Chaque Policy a des règles bien spéciphique définissent les exigences de stockage pour vos machines virtuelles. 
    Ces stratégies déterminent comment les objets de stockage de machine virtuelle sont provisionnés et alloués dans le datastore pour garantir le niveau de service requis.
    Il existe 5 ensembles de règles par défaut disponibles avec les stratégies de "vSAN Default Storage Policy":
        1.Number of Failures to Tolerate
        2.Number of disk stripes per object
        3.Object space reservation
        4.Flash read cache reservation
        5.Force provisioning
.EXAMPLE
    Il faut renseigner le vcenter a verifié ($vCenter).
    Si vous souhaitez exclure des stratégies vSAN spécifiques du rapport, ajoutez le nom de la stratégie à ce tableau.
    lancer le script Get_vSAN_Policy_Report_Console-Exclude.ps1
#>
#You can add multiple vCenter Servers. Note Credentials need to work on all vCenters.
$vCenter = ("piccolo-vcenter-01.ecritel.net") 
#Message d'authentification vCenter.
$Creds = Get-Credential
#Si vous souhaitez exclure des stratégies vSAN spécifiques du rapport, ajoutez le nom de la stratégie à ce tableau.
[array]$SpbmExclude = ("Management Storage Policy - Stretched","Management Storage Policy - Regular","Management Storage policy - Thin","Management Storage Policy - Single Node","Management Storage Policy - Stretched Lite","Management Storage Policy - Large"," VVol No Requirements Policy"," Management Storage Policy - Stretched Lite","VM Encryption Policy","Management Storage policy - Encryption")

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
#caractère de remplacement (*) pour représenter toutes les propriétés.
$RuleSetReport | Format-List -Property *
