# ============================================================
# VMWARE_vSAN_StoragePolicy_ZABBIX - Write-VmStoragePolicyComplianceJson.ps1
# ============================================================
# Auteur      : Sabri CHARCHOUF
# Date        : 15/09/2026
# Version     : 8.2
#
# Description :
#   Génère le JSON final de conformité vSAN pour Zabbix.
#
# Usage :
#   Write-VmStoragePolicyComplianceJson -JsonPath "C:\..." -CurrentResults $res -VCenterStatus $vcStatus
#
# Prérequis :
#   - Aucuns
#
# Architecture :
#   Production ($global:DryRun = $false) : lecture de l'existant, fusion,
#   marquage stale, écriture .tmp, Move-Item.
#   DryRun ($global:DryRun = $true) : instantané isolé du run en cours,
#   sans lecture ni fusion avec un fichier précédent (décision Sabri,
#   16/09/2026 - évite la confusion entre l'état d'un run de test et
#   celui d'un run précédent).
#
# Environment :
#   Agnostique
#
#Requires -Version 7.0
# ============================================================

$ErrorActionPreference = 'Stop'

function Write-VmStoragePolicyComplianceJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JsonPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$CurrentResults,

        [Parameter(Mandatory = $true)]
        [hashtable]$VCenterStatus
    )

    try {
        $nowString = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
        $previousData = $null

        # 1. Lecture de l'état précédent - jamais en DryRun (instantané isolé,
        # voir note Architecture en tête de fichier).
        if (-not $global:DryRun -and (Test-Path $JsonPath)) {
            try {
                $rawContent = Get-Content -Path $JsonPath -Raw -ErrorAction Stop
                $previousData = $rawContent | ConvertFrom-Json -ErrorAction Stop
                Write-Log -Message "JSON précédent chargé avec succès." -Level 'INFO' -Type 'EXECUTION'
            } catch {
                Write-Log -Message "[ALERTE] Fichier JSON existant corrompu ou illisible, création à neuf." -Level 'WARNING' -Type 'EXECUTION'
            }
        }

        # 2. Préparation de la nouvelle structure
        $finalVms = @{}
        $vcentersStatusNode = @{}

        # Initialisation du statut des vCenters
        foreach ($vc in $VCenterStatus.Keys) {
            $status = $VCenterStatus[$vc]
            $lastSuccess = $nowString
            if ($status -ne 'ok' -and $previousData -and $previousData.vcentersStatus -and $previousData.vcentersStatus.$vc) {
                $lastSuccess = $previousData.vcentersStatus.$vc.lastSuccessAt
            }
            $vcentersStatusNode[$vc] = @{
                status        = $status
                lastSuccessAt = $lastSuccess
            }
        }

        # 3. Traitement des nouvelles données (Fresh ou Error_Collecting_Entity)
        # Le périmètre de collecte est déjà limité aux VMs sur cluster
        # vSAN-enabled (voir Get-VmStoragePolicyCompliance.ps1). Depuis
        # le schéma 1.1, les données de policy sont détaillées par entité :
        # VM Home + chaque disque virtuel, car les policies peuvent diverger.
        if ($CurrentResults) {
            foreach ($vm in $CurrentResults) {
                $compositeKey = "$($vm.VCenter)::$($vm.InstanceUuid)"
                $isFresh = $vm.collectionStatus -eq 'fresh'

                $entityNodes = [System.Collections.Generic.List[object]]::new()
                foreach ($entity in @($vm.Entities)) {
                    [void]$entityNodes.Add(@{
                        entityName          = $entity.EntityName
                        entityId            = $entity.EntityId
                        storagePolicyName   = $entity.StoragePolicyName
                        complianceStatus    = $entity.ComplianceStatus
                        datastore           = $entity.Datastore
                        datastoreType       = $entity.DatastoreType
                        datastoreMismatch   = if ($isFresh) { $entity.DatastoreMismatch } else { $null }
                        lastComplianceCheck = $entity.LastComplianceCheck
                    })
                }

                $finalVms[$compositeKey] = @{
                    vcenter             = $vm.VCenter
                    vmName              = $vm.VMName
                    vmInstanceUuid      = $vm.InstanceUuid
                    vmMoRef             = if ($vm.VMId) { ($vm.VMId -split '-')[-1] } else { $null }
                    cluster             = $vm.Cluster
                    overallComplianceStatus = $vm.OverallComplianceStatus
                    policyMismatch      = if ($isFresh) { [bool]$vm.PolicyMismatch } else { $null }
                    entities            = [object[]]$entityNodes.ToArray()
                    collectionStatus    = $vm.collectionStatus
                    staleSince          = $null
                }
            }
        }

        # 4. Traitement du Stale (données précédentes absentes des nouvelles)
        if ($previousData -and $previousData.vmStoragePolicyCompliance) {
            foreach ($oldKey in $previousData.vmStoragePolicyCompliance.psobject.properties.name) {
                if (-not $finalVms.ContainsKey($oldKey)) {
                    $oldObj = $previousData.vmStoragePolicyCompliance.$oldKey
                    $vc = $oldObj.vcenter

                    $newStatus = 'missing_after_success'
                    if ($VCenterStatus[$vc] -ne 'ok') {
                        $newStatus = 'stale_vcenter_unreachable'
                    }

                    # Conservation du staleSince original si déjà stale
                    $staleSince = $oldObj.staleSince
                    if (-not $staleSince) {
                        $staleSince = $nowString
                    }

                    $oldEntities = [System.Collections.Generic.List[object]]::new()
                    if ($oldObj.entities) {
                        foreach ($oldEntity in @($oldObj.entities)) {
                            [void]$oldEntities.Add(@{
                                entityName          = $oldEntity.entityName
                                entityId            = $oldEntity.entityId
                                storagePolicyName   = $oldEntity.storagePolicyName
                                complianceStatus    = $oldEntity.complianceStatus
                                datastore           = $oldEntity.datastore
                                datastoreType       = $oldEntity.datastoreType
                                datastoreMismatch   = $null
                                lastComplianceCheck = $oldEntity.lastComplianceCheck
                            })
                        }
                    }
                    else {
                        [void]$oldEntities.Add(@{
                            entityName          = "VM Home"
                            entityId            = if ($oldObj.vmMoRef) { "VirtualMachine-vm-$($oldObj.vmMoRef)" } else { $oldKey }
                            storagePolicyName   = $oldObj.storagePolicyName
                            complianceStatus    = $oldObj.complianceStatus
                            datastore           = $oldObj.datastore
                            datastoreType       = $oldObj.datastoreType
                            datastoreMismatch   = $null
                            lastComplianceCheck = $oldObj.lastComplianceCheck
                        })
                    }

                    $overallStatus = if ($oldObj.overallComplianceStatus) {
                        $oldObj.overallComplianceStatus
                    }
                    else {
                        $oldObj.complianceStatus
                    }

                    $finalVms[$oldKey] = @{
                        vcenter             = $oldObj.vcenter
                        vmName              = $oldObj.vmName
                        vmInstanceUuid      = $oldObj.vmInstanceUuid
                        vmMoRef             = $oldObj.vmMoRef
                        cluster             = $oldObj.cluster
                        overallComplianceStatus = $overallStatus
                        # Données non fraîches : on ne réaffirme pas les
                        # anomalies ou divergences, elles devront être
                        # reconfirmées au prochain run réussi.
                        policyMismatch      = $null
                        entities            = [object[]]$oldEntities.ToArray()
                        collectionStatus    = $newStatus
                        staleSince          = $staleSince
                    }
                }
            }
        }

        # 5. Assemblage final
        $outputObject = @{
            schemaVersion             = "1.1"
            generatedAt               = $nowString
            generatedBy               = "VMWARE_vSAN_StoragePolicy_ZABBIX"
            vcentersStatus            = $vcentersStatusNode
            vmStoragePolicyCompliance = $finalVms
        }

        $jsonOutput = $outputObject | ConvertTo-Json -Depth 10

        # 6. Écriture atomique - toujours réelle, DryRun redirige juste vers
        # un chemin local (DRYRUN\) au lieu du chemin de production UNC.
        $tmpPath = "$JsonPath.tmp"
        $targetDir = Split-Path -Path $JsonPath -Parent
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        }

        [System.IO.File]::WriteAllText($tmpPath, $jsonOutput)
        Move-Item -Path $tmpPath -Destination $JsonPath -Force

        if ($global:DryRun) {
            Write-Log -Message "[DRYRUN] Fichier JSON généré (local) : $JsonPath ($($finalVms.Count) VMs)" -Level 'INFO' -Type 'EXECUTION'
        } else {
            Write-Log -Message "[OK] Fichier JSON généré avec succès : $JsonPath ($($finalVms.Count) VMs)" -Level 'INFO' -Type 'EXECUTION'
        }
    }
    catch {
        Write-Log -Message "[ERREUR] Échec lors de la génération du JSON : $($_.Exception.Message)" -Level 'ERROR' -Type 'ERRORS'
        throw
    }
}
