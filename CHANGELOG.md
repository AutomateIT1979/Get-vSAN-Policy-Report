# Changelog - VMWARE_vSAN_StoragePolicy_ZABBIX

## [1.0.0] - 2026-09-15
### Added
- Refonte complète du projet (anciennement Get-vSAN-Policy-Report).
- Implémentation du pattern Zabbix (JSON multi-vCenter).
- Création de `Start-VsanStoragePolicyCollection.ps1`.
- Fonctions `Connect-VCenter`, `Get-VmStoragePolicyCompliance`, `Write-VmStoragePolicyComplianceJson`.
- Architecture de gestion du 'stale' et clé composite pour Zabbix.
