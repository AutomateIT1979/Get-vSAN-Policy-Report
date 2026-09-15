# ============================================================
# VMWARE_vSAN_StoragePolicy_ZABBIX - VMWARE_vSAN_StoragePolicy_ZABBIX.Tests.ps1
# ============================================================
# Auteur      : Sabri CHARCHOUF
# Date        : 15/09/2026
# Version     : 8.0
#
# Description :
#   Tests Pester du schéma JSON et de la logique de stale.
#
# Usage :
#   Invoke-Pester -Path .\TESTS
#
# Prérequis :
#   - Module Pester
#
# Architecture :
#   Zéro action réelle, valide les cas nominaux.
#
# Environment :
#   Agnostique
#
#Requires -Version 7.0
# ============================================================

Describe "VMWARE_vSAN_StoragePolicy_ZABBIX JSON Schema and Writer" {

    BeforeAll {
        $script:jsonOutput = Join-Path $TestDrive "output.json"
        . "$PSScriptRoot\..\FUNCTIONS\Write-VmStoragePolicyComplianceJson.ps1"

        # Mock de Write-Log
        function Write-Log { param($Message, $Level, $Type) }
        $global:DryRun = $false
    }

    It "Should implement schemaVersion and generatedAt" {
        $mockResults = @(
            [PSCustomObject]@{
                VMName = "TestVM"
                VMId = "vm-1"
                InstanceUuid = "1111-2222"
                VCenter = "vc1"
                ComplianceStatus = "compliant"
                StoragePolicy = "vSAN Default"
                Datastore = "vsanDatastore"
                DatastoreType = "vsan"
                Cluster = "Cluster1"
                ClusterVsanEnabled = $true
                TimeOfCheck = "2026-09-15"
                collectionStatus = "fresh"
            }
        )
        $vcStatus = @{ "vc1" = "ok" }

        Write-VmStoragePolicyComplianceJson -JsonPath $script:jsonOutput -CurrentResults $mockResults -VCenterStatus $vcStatus

        $content = Get-Content $script:jsonOutput -Raw | ConvertFrom-Json
        $content.schemaVersion | Should -Be "1.0"
        $content.generatedAt | Should -Not -BeNullOrEmpty

        $vms = $content.vmStoragePolicyCompliance
        $keys = @($vms.psobject.properties.name)
        $keys.Count | Should -Be 1

        $firstVm = $vms."$($keys[0])"
        $firstVm.vmInstanceUuid | Should -Be "1111-2222"
        $firstVm.collectionStatus | Should -Be "fresh"
    }

    It "Should track missing_after_success when VM disappears and vCenter is ok" {
        $previousJson = @{
            vmStoragePolicyCompliance = @{
                "vc1::1111-2222" = @{
                    vcenter = "vc1"
                    collectionStatus = "fresh"
                }
            }
        } | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($script:jsonOutput, $previousJson)

        $vcStatus = @{ "vc1" = "ok" }
        Write-VmStoragePolicyComplianceJson -JsonPath $script:jsonOutput -CurrentResults @() -VCenterStatus $vcStatus

        $content = Get-Content $script:jsonOutput -Raw | ConvertFrom-Json
        $vms = $content.vmStoragePolicyCompliance
        $keys = @($vms.psobject.properties.name)
        $keys.Count | Should -Be 1

        $firstVm = $vms."$($keys[0])"
        $firstVm.collectionStatus | Should -Be "missing_after_success"
    }

    It "Should track stale_vcenter_unreachable when vCenter fails" {
        $previousJson = @{
            vmStoragePolicyCompliance = @{
                "vc1::1111-2222" = @{
                    vcenter = "vc1"
                    collectionStatus = "fresh"
                }
            }
        } | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($script:jsonOutput, $previousJson)

        $vcStatus = @{ "vc1" = "error" }
        Write-VmStoragePolicyComplianceJson -JsonPath $script:jsonOutput -CurrentResults @() -VCenterStatus $vcStatus

        $content = Get-Content $script:jsonOutput -Raw | ConvertFrom-Json
        $vms = $content.vmStoragePolicyCompliance
        $keys = @($vms.psobject.properties.name)
        $keys.Count | Should -Be 1

        $firstVm = $vms."$($keys[0])"
        $firstVm.collectionStatus | Should -Be "stale_vcenter_unreachable"
    }
}
