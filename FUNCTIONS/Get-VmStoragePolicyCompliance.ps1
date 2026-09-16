# ============================================================
# VMWARE_vSAN_StoragePolicy_ZABBIX - Get-VmStoragePolicyCompliance.ps1
# ============================================================
# Auteur      : Sabri CHARCHOUF
# Date        : 15/09/2026
# Version     : 8.4
#
# Description :
#   Collecte la conformité des Storage Policies pour les VMs dont
#   le cluster est vSAN-enabled (périmètre du projet : monitoring
#   vSAN, pas l'ensemble du vCenter). La collecte distingue la VM
#   Home et chaque disque virtuel, car leurs policies peuvent diverger.
#
# Usage :
#   Get-VmStoragePolicyCompliance -VCenterName "vcenter.domain.local"
#
# Prérequis :
#   - VMware.PowerCLI
#   - Session ouverte sur le vCenter cible
#   - Le compte utilisé doit avoir le privilège vCenter catégorie
#     "VM storage policies" > "View VM storage policies" pour que
#     Get-SpbmEntityConfiguration retourne StoragePolicy/ComplianceStatus
#     (confirmé le 16/09/2026 - PAS "Profile-driven Storage", nom
#     de catégorie erroné supposé initialement).
#   - Sans -CheckComplianceNow, ComplianceStatus ne reflète que le
#     dernier calcul mis en cache par vCenter (quasi toujours "none"
#     si aucune vérification n'a jamais été déclenchée côté vCenter -
#     confirmé le 16/09/2026 via tests console).
#
# Architecture :
#   Utilise des lookups (HashTables) pour éviter les boucles
#   sur les cmdlets PowerCLI (Get-Datastore, Get-Cluster). Les
#   lookups cluster/host sont construits AVANT la collecte SPBM
#   pour permettre le filtrage au périmètre vSAN en amont.
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

        # 2. Lookups (Datastores, Clusters, Hosts) pour perf O(1) - construits
        # avant le filtre vSAN pour pouvoir déterminer le cluster de chaque VM.
        Write-Log -Message "Construction des tables de correspondances (Lookups)..." -Level 'INFO' -Type 'EXECUTION'

        $datastoreLookup = @{}
        $datastoreByName = @{}
        Get-Datastore -Server $VCenterName -ErrorAction Stop | ForEach-Object {
            $datastoreLookup[$_.Id] = $_
            $datastoreByName[$_.Name] = $_
        }

        $clusterLookup = @{}
        Get-Cluster -Server $VCenterName -ErrorAction Stop | ForEach-Object {
            $clusterLookup[$_.Id] = $_
        }

        $hostClusterLookup = @{}
        Get-VMHost -Server $VCenterName -ErrorAction Stop | ForEach-Object {
            $hostClusterLookup[$_.Id] = $clusterLookup[$_.ParentId]
        }

        # 3. Périmètre du projet : uniquement les VMs dont le cluster est
        # vSAN-enabled. Les VMs sur clusters non-vSAN (Nutanix NFS, SAN VMFS)
        # sont hors périmètre - ce n'est pas ce qu'on monitore ici.
        $vsanVms = @($allVms | Where-Object {
            $clusterObj = $hostClusterLookup[$_.VMHostId]
            $clusterObj -and $clusterObj.VsanEnabled
        })
        $vsanScopeMessage = "VMs sur cluster vSAN-enabled : {0} / {1} VMs au total sur {2}" -f `
            $vsanVms.Count, $allVms.Count, $VCenterName
        Write-Log -Message $vsanScopeMessage -Level 'INFO' -Type 'EXECUTION'
        if ($vsanVms.Count -eq 0) {
            Write-Log -Message "[ALERTE] Aucune VM sur cluster vSAN-enabled trouvée sur $VCenterName" -Level 'WARNING' -Type 'EXECUTION'
            return @()
        }

        # 4. Lookup InstanceUuid via Get-View en bulk. Evite l'accès
        # $vm.ExtensionData dans la boucle d'assemblage : sur les objets
        # PowerCLI, ExtensionData peut déclencher un appel API par VM.
        $uuidMessage = "Récupération en bulk des InstanceUuid pour {0} VMs..." -f $vsanVms.Count
        Write-Log -Message $uuidMessage -Level 'INFO' -Type 'EXECUTION'
        $instanceUuidLookup = @{}
        $vmViewIds = @($vsanVms | ForEach-Object { $_.Id })
        for ($i = 0; $i -lt $vmViewIds.Count; $i += 1000) {
            $end = [math]::Min($i + 999, $vmViewIds.Count - 1)
            $vmViewBatch = $vmViewIds[$i..$end]
            $vmViews = @(Get-View -Server $VCenterName -Id $vmViewBatch -Property Config.InstanceUuid -ErrorAction Stop)
            foreach ($vmView in $vmViews) {
                if ($vmView.MoRef -and $vmView.MoRef.Value -and $vmView.Config -and $vmView.Config.InstanceUuid) {
                    $vmPowerCliId = "$($vmView.MoRef.Type)-$($vmView.MoRef.Value)"
                    $instanceUuidLookup[$vmPowerCliId] = $vmView.Config.InstanceUuid
                }
            }
        }

        # 5. Collecte des disques en bulk, au même périmètre vSAN que les VMs.
        Write-Log -Message "Récupération des disques pour $($vsanVms.Count) VMs..." -Level 'INFO' -Type 'EXECUTION'
        $allDisks = [System.Collections.Generic.List[object]]::new()
        $diskByVmId = @{}
        $batchSize = 1000

        for ($i = 0; $i -lt $vsanVms.Count; $i += $batchSize) {
            $end = [math]::Min($i + $batchSize - 1, $vsanVms.Count - 1)
            $batch = $vsanVms[$i..$end]
            try {
                foreach ($disk in @(Get-HardDisk -VM $batch -ErrorAction Stop)) {
                    [void]$allDisks.Add($disk)
                }
            }
            catch {
                $diskBatchError = "[ALERTE] Echec du lot disques [{0}-{1}] ({2} VMs) : {3} - repli VM par VM" -f `
                    $i, $end, $batch.Count, $_.Exception.Message
                Write-Log -Message $diskBatchError -Level 'WARNING' -Type 'ERRORS'
                foreach ($vmInBatch in $batch) {
                    try {
                        foreach ($disk in @(Get-HardDisk -VM $vmInBatch -ErrorAction Stop)) {
                            [void]$allDisks.Add($disk)
                        }
                    }
                    catch {
                        $diskVmError = "[WARN] Disques indisponibles pour la VM {0} : {1}" -f `
                            $vmInBatch.Name, $_.Exception.Message
                        Write-Log -Message $diskVmError -Level 'WARNING' -Type 'ERRORS'
                    }
                }
            }
        }

        foreach ($disk in $allDisks) {
            if (-not $disk.ParentId) {
                continue
            }

            if (-not $diskByVmId.ContainsKey($disk.ParentId)) {
                $diskByVmId[$disk.ParentId] = [System.Collections.Generic.List[object]]::new()
            }
            [void]$diskByVmId[$disk.ParentId].Add($disk)
        }

        # 6. Collecte SPBM VM Home en bulk, uniquement sur le périmètre vSAN.
        Write-Log -Message "Récupération des entités SPBM VM Home pour $($vsanVms.Count) VMs..." -Level 'INFO' -Type 'EXECUTION'
        $spbmList = [System.Collections.Generic.List[object]]::new()
        $failedVmIds = @{}
        for ($i = 0; $i -lt $vsanVms.Count; $i += $batchSize) {
            $end = [math]::Min($i + $batchSize - 1, $vsanVms.Count - 1)
            $batch = $vsanVms[$i..$end]
            try {
                # -CheckComplianceNow force le recalcul côté vCenter au lieu de
                # lire le cache (souvent jamais rempli, voir Prérequis en tête
                # de fichier - confirmé le 16/09/2026 via tests console).
                foreach ($spbm in @(Get-SpbmEntityConfiguration -VM $batch -Server $VCenterName -CheckComplianceNow -ErrorAction Stop)) {
                    [void]$spbmList.Add($spbm)
                }
            }
            catch {
                # Une seule VM invalide (supprimée/en cours de vMotion) fait échouer
                # tout le lot - repli VM par VM pour ne pas perdre les autres.
                $spbmVmBatchError = "[ALERTE] Echec du lot SPBM VM [{0}-{1}] ({2} VMs) : {3} - repli VM par VM" -f `
                    $i, $end, $batch.Count, $_.Exception.Message
                Write-Log -Message $spbmVmBatchError -Level 'WARNING' -Type 'ERRORS'
                foreach ($vmInBatch in $batch) {
                    try {
                        foreach ($spbm in @(Get-SpbmEntityConfiguration -VM $vmInBatch -Server $VCenterName -CheckComplianceNow -ErrorAction Stop)) {
                            [void]$spbmList.Add($spbm)
                        }
                    }
                    catch {
                        $spbmVmError = "[WARN] SPBM indisponible pour la VM {0} : {1}" -f `
                            $vmInBatch.Name, $_.Exception.Message
                        Write-Log -Message $spbmVmError -Level 'WARNING' -Type 'ERRORS'
                        $failedVmIds[$vmInBatch.Id] = $true
                    }
                }
            }
        }

        $spbmLookup = @{}
        foreach ($spbm in $spbmList) {
            if ($spbm.Entity -and $spbm.Entity.Id) {
                $spbmLookup[$spbm.Entity.Id] = $spbm
            }
        }

        # 7. Collecte SPBM disque en bulk. Les disques sont pipeés vers la
        # cmdlet, conformément au contrat PowerCLI vérifié en console.
        Write-Log -Message "Récupération des entités SPBM disque pour $($allDisks.Count) disques..." -Level 'INFO' -Type 'EXECUTION'
        $diskSpbmList = [System.Collections.Generic.List[object]]::new()
        $failedDiskIds = @{}
        $allDiskArray = $allDisks.ToArray()
        for ($i = 0; $i -lt $allDiskArray.Count; $i += $batchSize) {
            $end = [math]::Min($i + $batchSize - 1, $allDiskArray.Count - 1)
            $batch = $allDiskArray[$i..$end]
            try {
                foreach ($spbm in @($batch | Get-SpbmEntityConfiguration -Server $VCenterName -CheckComplianceNow -ErrorAction Stop)) {
                    [void]$diskSpbmList.Add($spbm)
                }
            }
            catch {
                $spbmDiskBatchError = "[ALERTE] Echec du lot SPBM disque [{0}-{1}] ({2} disques) : {3} - repli disque par disque" -f `
                    $i, $end, $batch.Count, $_.Exception.Message
                Write-Log -Message $spbmDiskBatchError -Level 'WARNING' -Type 'ERRORS'
                foreach ($diskInBatch in $batch) {
                    try {
                        foreach ($spbm in @($diskInBatch | Get-SpbmEntityConfiguration -Server $VCenterName -CheckComplianceNow -ErrorAction Stop)) {
                            [void]$diskSpbmList.Add($spbm)
                        }
                    }
                    catch {
                        $spbmDiskError = "[WARN] SPBM indisponible pour le disque {0} : {1}" -f `
                            $diskInBatch.Name, $_.Exception.Message
                        Write-Log -Message $spbmDiskError -Level 'WARNING' -Type 'ERRORS'
                        $failedDiskIds[$diskInBatch.Id] = $true
                    }
                }
            }
        }

        $diskSpbmLookup = @{}
        foreach ($spbm in $diskSpbmList) {
            if ($spbm.Entity -and $spbm.Entity.Id) {
                $diskSpbmLookup[$spbm.Entity.Id] = $spbm
            }
        }

        # 8. Assemblage final par VM, avec détail VM Home + disques.
        Write-Log -Message "Assemblage des données de conformité..." -Level 'INFO' -Type 'EXECUTION'
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()
        # Ordre opérationnel explicite, sans utiliser la valeur numérique de
        # l'enum PowerCLI. A ajuster si un statut réel nouveau est observé.
        $statusSeverity = @{
            "error"         = 700
            "noncompliant"  = 600
            "outofdate"     = 500
            "unknown"       = 400
            "notapplicable" = 300
            "none"          = 200
            "compliant"     = 100
        }

        foreach ($vm in $vsanVms) {
            try {
                $collectionStatus = "fresh"
                $spbm = $spbmLookup[$vm.Id]
                if ($failedVmIds.ContainsKey($vm.Id)) {
                    $collectionStatus = "error_collecting_entity"
                }

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
                if ($instanceUuidLookup.ContainsKey($vm.Id)) {
                    $instanceUuid = $instanceUuidLookup[$vm.Id]
                }

                $entities = [System.Collections.Generic.List[PSCustomObject]]::new()

                $vmStoragePolicyName = "none"
                if ($spbm -and $spbm.StoragePolicy -and $spbm.StoragePolicy.Name) {
                    $vmStoragePolicyName = $spbm.StoragePolicy.Name
                }

                $vmComplianceStatus = "none"
                if ($null -ne $spbm -and $null -ne $spbm.ComplianceStatus) {
                    $vmComplianceStatus = $spbm.ComplianceStatus.ToString()
                }

                $vmLastComplianceCheck = $null
                if ($spbm -and $spbm.TimeOfCheck) {
                    $vmLastComplianceCheck = $spbm.TimeOfCheck.ToString("yyyy-MM-ddTHH:mm:ssZ")
                }

                [void]$entities.Add([PSCustomObject]@{
                    EntityName          = "VM Home"
                    EntityId            = $vm.Id
                    StoragePolicyName   = $vmStoragePolicyName
                    ComplianceStatus    = $vmComplianceStatus
                    Datastore           = $dsName
                    DatastoreType       = $dsType
                    DatastoreMismatch   = [bool]($dsType -and $dsType -ne 'vsan')
                    LastComplianceCheck = $vmLastComplianceCheck
                })

                if ($diskByVmId.ContainsKey($vm.Id)) {
                    foreach ($disk in $diskByVmId[$vm.Id]) {
                        $diskSpbm = $diskSpbmLookup[$disk.Id]
                        if ($failedDiskIds.ContainsKey($disk.Id)) {
                            $collectionStatus = "error_collecting_entity"
                        }

                        $diskDsName = $null
                        if ($disk.Filename -and $disk.Filename -match '^\[(.+?)\]') {
                            $diskDsName = $matches[1]
                        }

                        $diskDsType = "Unknown"
                        if ($diskDsName -and $datastoreByName.ContainsKey($diskDsName)) {
                            $diskDsType = $datastoreByName[$diskDsName].Type
                        }
                        elseif (-not $diskDsName) {
                            $diskDsName = "Unknown"
                        }

                        $diskStoragePolicyName = "none"
                        if ($diskSpbm -and $diskSpbm.StoragePolicy -and $diskSpbm.StoragePolicy.Name) {
                            $diskStoragePolicyName = $diskSpbm.StoragePolicy.Name
                        }

                        $diskComplianceStatus = "none"
                        if ($null -ne $diskSpbm -and $null -ne $diskSpbm.ComplianceStatus) {
                            $diskComplianceStatus = $diskSpbm.ComplianceStatus.ToString()
                        }

                        $diskLastComplianceCheck = $null
                        if ($diskSpbm -and $diskSpbm.TimeOfCheck) {
                            $diskLastComplianceCheck = $diskSpbm.TimeOfCheck.ToString("yyyy-MM-ddTHH:mm:ssZ")
                        }

                        [void]$entities.Add([PSCustomObject]@{
                            EntityName          = $disk.Name
                            EntityId            = $disk.Id
                            StoragePolicyName   = $diskStoragePolicyName
                            ComplianceStatus    = $diskComplianceStatus
                            Datastore           = $diskDsName
                            DatastoreType       = $diskDsType
                            DatastoreMismatch   = [bool]($diskDsType -and $diskDsType -ne 'vsan')
                            LastComplianceCheck = $diskLastComplianceCheck
                        })
                    }
                }

                $entityArray = $entities.ToArray()
                $overallComplianceStatus = "none"
                $worstScore = 0
                foreach ($status in @($entityArray.ComplianceStatus)) {
                    if (-not $status) {
                        continue
                    }

                    $statusKey = $status.ToString().ToLowerInvariant()
                    $score = if ($statusSeverity.ContainsKey($statusKey)) { $statusSeverity[$statusKey] } else { 350 }
                    if ($score -gt $worstScore) {
                        $worstScore = $score
                        $overallComplianceStatus = $status.ToString()
                    }
                }

                $distinctPolicies = @($entityArray.StoragePolicyName |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Select-Object -Unique)

                [void]$results.Add([PSCustomObject]@{
                    VMName                  = $vm.Name
                    VMId                    = $vm.Id
                    InstanceUuid            = $instanceUuid
                    VCenter                 = $VCenterName
                    Cluster                 = if ($clusterObj) { $clusterObj.Name } else { "Unknown" }
                    OverallComplianceStatus = $overallComplianceStatus
                    PolicyMismatch          = ($distinctPolicies.Count -gt 1)
                    Entities                = $entityArray
                    collectionStatus        = $collectionStatus
                })
            }
            catch {
                Write-Log -Message "[WARN] Erreur d'extraction pour la VM $($vm.Name) : $($_.Exception.Message)" -Level 'WARNING' -Type 'ERRORS'

                $instanceUuid = $vm.Id
                if ($instanceUuidLookup.ContainsKey($vm.Id)) {
                    $instanceUuid = $instanceUuidLookup[$vm.Id]
                }

                [void]$results.Add([PSCustomObject]@{
                    VMName                  = $vm.Name
                    VMId                    = $vm.Id
                    InstanceUuid            = $instanceUuid
                    VCenter                 = $VCenterName
                    Cluster                 = "Unknown"
                    OverallComplianceStatus = "error"
                    PolicyMismatch          = $null
                    Entities                = @([PSCustomObject]@{
                            EntityName          = "VM Home"
                            EntityId            = $vm.Id
                            StoragePolicyName   = "error"
                            ComplianceStatus    = "error"
                            Datastore           = "Unknown"
                            DatastoreType       = "Unknown"
                            DatastoreMismatch   = $null
                            LastComplianceCheck = $null
                        })
                    collectionStatus        = "error_collecting_entity"
                })
            }
        }

        $doneMessage = "[OK] Collecte terminée pour {0} ({1} VMs analysées, périmètre vSAN)" -f `
            $VCenterName, $results.Count
        Write-Log -Message $doneMessage -Level 'INFO' -Type 'EXECUTION'
        return $results.ToArray()
    }
    catch {
        Write-Log -Message "[ERREUR] Échec de la collecte sur $VCenterName : $($_.Exception.Message)" -Level 'ERROR' -Type 'ERRORS'
        return $null
    }
}
