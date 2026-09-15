# VMWARE_vSAN_StoragePolicy_ZABBIX

Collecte la conformité des "VM Storage Policies" vSAN pour ingestion dans Zabbix. Ce script génère un export JSON consolidé (multi-vCenter).

## Prérequis

- Compte de service : `<COMPTE_SERVICE>` (Authentification AD standard).
- Fichiers AES : `aeskey_<COMPTE_SERVICE>.txt` et `credpassword_<COMPTE_SERVICE>.txt` dans le dossier `GLOBAL_CONF`.
- VMware.PowerCLI module installé sur le serveur d'exécution.

## Lancement

Exécuter via le script orchestrateur :
```powershell
.\BIN\Start-VsanStoragePolicyCollection.ps1
```

Note : L'exécution est simulée (`DryRun = $true`) par défaut dans `CONF\config.ps1`. Le fichier JSON n'est physiquement créé que si `DryRun` est désactivé.

## Sortie JSON

Le script produit un fichier JSON contenant le statut de chaque VM sur les vCenters définis, incluant :
- La policy assignée
- Le statut de conformité (`compliant`, `nonCompliant`, etc.)
- Le cluster et si vSAN y est activé (`ClusterVsanEnabled`)
- Le datastore et son type (`DatastoreType`)

## Références

- Broadcom KB — vSAN Health Service : vSAN Storage Policy (cas Not Applicable lié à un datastore non-vSAN) : [KB 326534](https://knowledge.broadcom.com/external/article/326534/vsan-health-service-vsan-storage-policy.html)
