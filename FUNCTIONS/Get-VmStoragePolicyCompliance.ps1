# ============================================================
# VMWARE_vSAN_StoragePolicy_ZABBIX - Get-VmStoragePolicyCompliance.ps1
# ============================================================
# Auteur      : Sabri CHARCHOUF
# Date        : 15/09/2026
# Version     : 8.0
#
# Description :
#   Collecte la conformité des Storage Policies (vSAN) pour
#   l'ensemble des VMs d'un vCenter donné. Combine les infos
#   de cluster (VsanEnabled) et de datastore (Type).
#
# Usage :
#   Get-VmStoragePolicyCompliance -VCenterName "vcenter.domain.local"
#
# Prérequis :
#   - VMware.PowerCLI
#   - Session ouverte sur le vCenter cible
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
        Write-Log -Message "Début de la collecte des VMs sur $VCenterName" -Level 'INFO' -Type 'EXECUTION'

        # 1. Collecte en bulk (forcée en tableau pour éviter les erreurs de scalaires)
        $allVms = @(Get-VM -Server $VCenterName -ErrorAction Stop)
        if (-not $allVms -or $allVms.Count -eq 0) {
            Write-Log -Message "[ALERTE] Aucune VM trouvée sur $VCenterName" -Level 'WARNING' -Type 'EXECUTION'
            return @()
        }

        # 2. Collecte SPBM en bulk
        Write-Log -Message "Récupération des entités SPBM pour $($allVms.Count) VMs..." -Level 'INFO' -Type 'EXECUTION'
        # Utilisation de lots pour éviter les timeouts si trop de VMs
        $spbmList = @()
        $failedVmIds = @{}
        $batchSize = 1000
        for ($i = 0; $i -lt $allVms.Count; $i += $batchSize) {
            $end = [math]::Min($i + $batchSize - 1, $allVms.Count - 1)
            $batch = $allVms[$i..$end]
            try {
                $spbmList += @(Get-SpbmEntityConfiguration -VM $batch -Server $VCenterName -ErrorAction Stop)
            }
            catch {
                # Une seule VM invalide (supprimée/en cours de vMotion) fait échouer
                # tout le lot - repli VM par VM pour ne pas perdre les autres.
                Write-Log -Message "[ALERTE] Echec du lot SPBM [$i-$end] ($($batch.Count) VMs) : $($_.Exception.Message) - repli VM par VM" -Level 'WARNING' -Type 'ERRORS'
                foreach ($vmInBatch in $batch) {
                    try {
                        $spbmList += @(Get-SpbmEntityConfiguration -VM $vmInBatch -Server $VCenterName -ErrorAction Stop)
                    }
                    catch {
                        Write-Log -Message "[WARN] SPBM indisponible pour la VM $($vmInBatch.Name) : $($_.Exception.Message)" -Level 'WARNING' -Type 'ERRORS'
                        $failedVmIds[$vmInBatch.Id] = $true
                    }
                }
            }
        }

        # 3. Lookups (Datastores, Clusters, Hosts, SPBM) pour perf O(1)
        Write-Log -Message "Construction des tables de correspondances (Lookups)..." -Level 'INFO' -Type 'EXECUTION'

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
        Write-Log -Message "Assemblage des données de conformité..." -Level 'INFO' -Type 'EXECUTION'
        $results = @()

        foreach ($vm in $allVms) {
            try {
                if ($failedVmIds.ContainsKey($vm.Id)) {
                    throw "SPBM non collecté pour cette VM (échec de lot, voir logs ERRORS)"
                }

                $spbm = $spbmLookup[$vm.Id]

                $dsName = "Unknown"
                $dsType = "Unknown"
                if ($vm.DatastoreIdList -and $vm.DatastoreIdList.Count -gt 0) {
                    $ds = $datastoreLookup[$vm.DatastoreIdList[0]]
                    if ($ds) {
                        $dsName = $ds.Name
                        $dsType = $ds.Type
                    }
                }

                $clusterObj = $hostClusterLookup[$vm.VMHostId]

                $instanceUuid = $vm.Id
                if ($vm.ExtensionData -and $vm.ExtensionData.Config -and $vm.ExtensionData.Config.InstanceUuid) {
                    $instanceUuid = $vm.ExtensionData.Config.InstanceUuid
                }

                $results += [PSCustomObject]@{
                    VMName             = $vm.Name
                    VMId               = $vm.Id
                    InstanceUuid       = $instanceUuid
                    VCenter            = $VCenterName
                    ComplianceStatus   = if ($spbm -and $spbm.ComplianceStatus) { $spbm.ComplianceStatus } else { "none" }
                    StoragePolicy      = if ($spbm -and $spbm.StoragePolicy) { $spbm.StoragePolicy.Name } else { "none" }
                    Datastore          = $dsName
                    DatastoreType      = $dsType
                    Cluster            = if ($clusterObj) { $clusterObj.Name } else { "Unknown" }
                    ClusterVsanEnabled = if ($clusterObj -and $null -ne $clusterObj.VsanEnabled) { [bool]$clusterObj.VsanEnabled } else { $false }
                    TimeOfCheck        = if ($spbm -and $spbm.CheckTime) { $spbm.CheckTime.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $null }
                    collectionStatus   = "fresh"
                }
            }
            catch {
                Write-Log -Message "[WARN] Erreur d'extraction pour la VM $($vm.Name) : $($_.Exception.Message)" -Level 'WARNING' -Type 'ERRORS'

                $instanceUuid = $vm.Id
                if ($vm.ExtensionData -and $vm.ExtensionData.Config -and $vm.ExtensionData.Config.InstanceUuid) {
                    $instanceUuid = $vm.ExtensionData.Config.InstanceUuid
                }

                $results += [PSCustomObject]@{
                    VMName             = $vm.Name
                    VMId               = $vm.Id
                    InstanceUuid       = $instanceUuid
                    VCenter            = $VCenterName
                    ComplianceStatus   = "error"
                    StoragePolicy      = "error"
                    Datastore          = "Unknown"
                    DatastoreType      = "Unknown"
                    Cluster            = "Unknown"
                    ClusterVsanEnabled = $false
                    TimeOfCheck        = $null
                    collectionStatus   = "error_collecting_entity"
                }
            }
        }

        Write-Log -Message "[OK] Collecte terminée pour $VCenterName ($($results.Count) VMs analysées)" -Level 'INFO' -Type 'EXECUTION'
        return $results
    }
    catch {
        Write-Log -Message "[ERREUR] Échec de la collecte sur $VCenterName : $($_.Exception.Message)" -Level 'ERROR' -Type 'ERRORS'
        return $null
    }
}
