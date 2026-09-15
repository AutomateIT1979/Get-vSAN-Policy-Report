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
        . "$PSScriptRoot\..\FUNCTIONS\Write-Log.ps1"
        $global:logExecutionPath = Join-Path $TestDrive "exec"
        $global:logVMImpactPath  = Join-Path $TestDrive "impact"
        $global:logErrorsPath    = Join-Path $TestDrive "error"
        New-Item -ItemType Directory -Path $global:logExecutionPath -Force | Out-Null
        New-Item -ItemType Directory -Path $global:logErrorsPath -Force | Out-Null
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
            }
        )
        $vcStatus = @{ "vc1" = "ok" }
        
        Write-VmStoragePolicyComplianceJson -JsonPath $script:jsonOutput -CurrentResults $mockResults -VCenterStatus $vcStatus

        $content = Get-Content $script:jsonOutput -Raw | ConvertFrom-Json
        $content.schemaVersion | Should -Be "1.0"
        $content.generatedAt | Should -Not -BeNullOrEmpty
        $content.data.Length | Should -Be 1
        $content.data[0].vmInstanceUuid | Should -Be "1111-2222"
        $content.data[0].collectionStatus | Should -Be "fresh"
    }

    It "Should track stale_vcenter_unreachable when vCenter fails" {
        # Modify VC status to error
        $vcStatus = @{ "vc1" = "error" }
        
        Write-VmStoragePolicyComplianceJson -JsonPath $script:jsonOutput -CurrentResults @() -VCenterStatus $vcStatus

        $content = Get-Content $script:jsonOutput -Raw | ConvertFrom-Json
        $content.data.Length | Should -Be 1
        $content.data[0].collectionStatus | Should -Be "stale_vcenter_unreachable"
    }

    It "Should mark VM as missing_after_success if it disappears and vCenter is ok" {
        # Modify VC status to ok, but empty results
        $vcStatus = @{ "vc1" = "ok" }
        
        Write-VmStoragePolicyComplianceJson -JsonPath $script:jsonOutput -CurrentResults @() -VCenterStatus $vcStatus

        $content = Get-Content $script:jsonOutput -Raw | ConvertFrom-Json
        $content.data.Length | Should -Be 1
        $content.data[0].collectionStatus | Should -Be "missing_after_success"
    }
}
