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
        $firstVm.datastoreMismatch | Should -Be $false
    }

    It "Should flag datastoreMismatch when a vSAN-cluster VM is on a non-vsan datastore" {
        $mockResults = @(
            [PSCustomObject]@{
                VMName = "TestVM2"
                VMId = "vm-2"
                InstanceUuid = "3333-4444"
                VCenter = "vc1"
                ComplianceStatus = "notApplicable"
                StoragePolicy = "none"
                Datastore = "vmfsDatastore"
                DatastoreType = "VMFS"
                Cluster = "Cluster1"
                TimeOfCheck = $null
                collectionStatus = "fresh"
            }
        )
        $vcStatus = @{ "vc1" = "ok" }

        Write-VmStoragePolicyComplianceJson -JsonPath $script:jsonOutput -CurrentResults $mockResults -VCenterStatus $vcStatus

        $content = Get-Content $script:jsonOutput -Raw | ConvertFrom-Json
        $vms = $content.vmStoragePolicyCompliance
        $firstVm = $vms."vc1::3333-4444"
        $firstVm.datastoreMismatch | Should -Be $true
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

Describe "VMWARE_vSAN_StoragePolicy_ZABBIX Collector performance guards" {

    BeforeAll {
        # Stubs mockables : les tests unitaires ne chargent pas PowerCLI.
        function Get-VM { }
        function Get-Datastore { }
        function Get-Cluster { }
        function Get-VMHost { }
        function Get-View { }
        function Get-SpbmEntityConfiguration { }
        function Write-Log { param($Message, $Level, $Type) }

        . "$PSScriptRoot\..\FUNCTIONS\Get-VmStoragePolicyCompliance.ps1"
    }

    BeforeEach {
        $script:mockVm = [PSCustomObject]@{
            Name            = "TestVM"
            Id              = "VirtualMachine-vm-1"
            VMHostId        = "HostSystem-host-1"
            DatastoreIdList = @("Datastore-datastore-1")
        }
        $script:mockVm | Add-Member -MemberType ScriptProperty -Name ExtensionData -Value {
            throw "ExtensionData ne doit pas etre lu pendant l'assemblage."
        }
    }

    It "Should resolve InstanceUuid through bulk Get-View without reading VM ExtensionData" {
        Mock Get-VM { @($script:mockVm) }
        Mock Get-Datastore {
            [PSCustomObject]@{
                Id   = "Datastore-datastore-1"
                Name = "vsanDatastore"
                Type = "vsan"
            }
        }
        Mock Get-Cluster {
            [PSCustomObject]@{
                Id          = "ClusterComputeResource-domain-c1"
                Name        = "Cluster1"
                VsanEnabled = $true
            }
        }
        Mock Get-VMHost {
            [PSCustomObject]@{
                Id       = "HostSystem-host-1"
                ParentId = "ClusterComputeResource-domain-c1"
            }
        }
        Mock Get-View {
            [PSCustomObject]@{
                MoRef  = [PSCustomObject]@{
                    Type  = "VirtualMachine"
                    Value = "vm-1"
                }
                Config = [PSCustomObject]@{
                    InstanceUuid = "1111-2222"
                }
            }
        }
        Mock Get-SpbmEntityConfiguration {
            [PSCustomObject]@{
                Entity           = [PSCustomObject]@{ Id = "VirtualMachine-vm-1" }
                ComplianceStatus = "compliant"
                StoragePolicy    = [PSCustomObject]@{ Name = "vSAN Default" }
                TimeOfCheck      = [datetime]"2026-09-16T12:00:00Z"
            }
        }

        $result = @(Get-VmStoragePolicyCompliance -VCenterName "vc-test")

        $result.Count | Should -Be 1
        $result[0].InstanceUuid | Should -Be "1111-2222"
        Should -Invoke Get-View -Times 1 -Exactly
    }
}
