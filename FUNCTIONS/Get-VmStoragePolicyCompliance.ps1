# ============================================================
# VMWARE_vSAN_StoragePolicy_ZABBIX - Get-VmStoragePolicyCompliance.ps1
# ============================================================
# Auteur      : Sabri CHARCHOUF
# Date        : 15/09/2026
# Version     : 1.0
#
# Description :
#   Collecte la conformité des Storage Policies (vSAN) pour
#   l'ensemble des VMs d'un vCenter donné. Combine les infos
#   de cluster (VsanEnabled) et de datastore (Type).
#
# Architecture :
#   Utilise des lookups (HashTables) pour éviter les boucles
#   sur les cmdlets PowerCLI (Get-Datastore, Get-Cluster).
#
# Environment :
#   Agnostique
#
#Requires -Version 7.0
# ============================================================

$ErrorActionPreference = 'Stop'

function Get-VmStoragePolicyCompliance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VCenterName
    )

    try {
        Write-Log -Message "Début de la collecte des VMs sur $VCenterName" -Level 'INFO' -LogType 'EXECUTION'

        # 1. Collecte en bulk
        $allVms = Get-VM -Server $VCenterName -ErrorAction Stop
        if (-not $allVms) {
            Write-Log -Message "[ALERTE] Aucune VM trouvée sur $VCenterName" -Level 'WARN' -LogType 'EXECUTION'
            return @()
        }

        # 2. Collecte SPBM en bulk
        Write-Log -Message "Récupération des entités SPBM pour $($allVms.Count) VMs..." -Level 'INFO' -LogType 'EXECUTION'
        # Utilisation de lots pour éviter les timeouts si trop de VMs
        $spbmList = @()
        $batchSize = 1000
        for ($i = 0; $i -lt $allVms.Count; $i += $batchSize) {
            $batch = $allVms[$i..($i + $batchSize - 1)]
            $spbmList += Get-SpbmEntityConfiguration -VM $batch -Server $VCenterName -ErrorAction Stop
        }

        # 3. Lookups (Datastores, Clusters, Hosts, SPBM) pour perf O(1)
        Write-Log -Message "Construction des tables de correspondances (Lookups)..." -Level 'INFO' -LogType 'EXECUTION'
        
        $datastoreLookup = @{}
        Get-Datastore -Server $VCenterName -ErrorAction Stop | ForEach-Object {
            $datastoreLookup[$_.Id] = $_
        }

        $clusterLookup = @{}
        Get-Cluster -Server $VCenterName -ErrorAction Stop | ForEach-Object {
            $clusterLookup[$_.Id] = $_
        }

        $hostClusterLookup = @{}
        Get-VMHost -Server $VCenterName -ErrorAction Stop | ForEach-Object {
            $hostClusterLookup[$_.Id] = $clusterLookup[$_.ParentId]
        }

        $spbmLookup = @{}
        foreach ($spbm in $spbmList) {
            if ($spbm.Entity -and $spbm.Entity.Id) {
                $spbmLookup[$spbm.Entity.Id] = $spbm
            }
        }

        # 4. Assemblage
        Write-Log -Message "Assemblage des données de conformité..." -Level 'INFO' -LogType 'EXECUTION'
        $results = @()

        foreach ($vm in $allVms) {
            $vmId = $vm.Id
            $instanceUuid = if ($vm.ExtensionData -and $vm.ExtensionData.Config) { $vm.ExtensionData.Config.InstanceUuid } else { $null }
            if (-not $instanceUuid) { $instanceUuid = $vm.Uid } # fallback
            
            $vmSpbm = $spbmLookup[$vmId]
            
            # Gestion Cluster
            $vmCluster = $hostClusterLookup[$vm.VMHostId]
            $clusterName = if ($vmCluster) { $vmCluster.Name } else { 'Unknown' }
            $clusterVsanEnabled = if ($vmCluster -and $null -ne $vmCluster.VsanEnabled) { [bool]$vmCluster.VsanEnabled } else { $false }
            
            # Gestion Datastores
            $dsNames = @()
            $dsTypes = @()
            if ($vm.DatastoreIdList) {
                foreach ($dsId in $vm.DatastoreIdList) {
                    $ds = $datastoreLookup[$dsId]
                    if ($ds) {
                        $dsNames += $ds.Name
                        $dsTypes += $ds.Type
                    }
                }
            }
            $datastoreJoined = ($dsNames | Select-Object -Unique) -join ', '
            $datastoreTypeJoined = ($dsTypes | Select-Object -Unique) -join ', '

            # Gestion SPBM (valeurs depuis la recon)
            $spName = if ($vmSpbm -and $vmSpbm.StoragePolicy) { $vmSpbm.StoragePolicy.Name } else { 'none' }
            $spStatus = if ($vmSpbm -and $vmSpbm.ComplianceStatus) { $vmSpbm.ComplianceStatus.ToString() } else { 'none' }
            $spCheckTime = if ($vmSpbm -and $vmSpbm.TimeOfCheck) { $vmSpbm.TimeOfCheck.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $null }

            $results += [PSCustomObject]@{
                VCenter             = $VCenterName
                VmName              = $vm.Name
                InstanceUuid        = $instanceUuid
                MoRef               = ($vmId -split '-')[-1]
                Cluster             = $clusterName
                ClusterVsanEnabled  = $clusterVsanEnabled
                Datastore           = if ($datastoreJoined) { $datastoreJoined } else { 'none' }
                DatastoreType       = if ($datastoreTypeJoined) { $datastoreTypeJoined } else { 'none' }
                StoragePolicyName   = $spName
                ComplianceStatus    = $spStatus
                LastComplianceCheck = $spCheckTime
            }
        }

        Write-Log -Message "[OK] Collecte terminée pour $VCenterName ($($results.Count) VMs analysées)" -Level 'INFO' -LogType 'EXECUTION'
        return $results
    }
    catch {
        Write-Log -Message "[ERREUR] Échec de la collecte sur $VCenterName : $($_.Exception.Message)" -Level 'ERROR' -LogType 'ERRORS'
        return @()
    }
}
