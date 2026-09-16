# VMWARE_vSAN_StoragePolicy_ZABBIX

Collecte la conformité des "VM Storage Policies" pour les VMs situées sur un cluster **vSAN-enabled**, pour ingestion dans Zabbix. Ce script génère un export JSON consolidé (multi-vCenter).

## Périmètre

Seules les VMs dont le **cluster** est vSAN-enabled sont collectées (pas l'ensemble du vCenter). La collecte distingue la **VM Home** et chaque **disque virtuel**, car une VM peut avoir une policy sur son objet VM Home et une autre policy sur un ou plusieurs disques.

Une entité située sur un cluster vSAN mais dont le **datastore** n'est pas de type `vsan` reste incluse : c'est une anomalie réelle à surveiller (voir champ `datastoreMismatch` dans `entities[]`), pas un cas à filtrer.

## Prérequis

- Compte de service : `<COMPTE_SERVICE>` (Authentification AD standard, format UPN complet requis pour certains comptes — voir `CONF\config.ps1`, `CredentialUserName`).
- Fichiers AES : `aeskey_<COMPTE_SERVICE>.txt` et `credpassword_<COMPTE_SERVICE>.txt` dans le dossier `GLOBAL_CONF`.
- VMware.PowerCLI module installé sur le serveur d'exécution.
- **Privilège vCenter** : catégorie **"VM storage policies" → "View VM storage policies"** sur le compte de service (posé au niveau racine du vCenter). Sans lui, `Get-SpbmEntityConfiguration` ne peut retourner ni la policy assignée ni le statut de conformité — confirmé le 16/09/2026, ce n'est PAS la catégorie "Profile-driven Storage".

## Lancement

Exécuter via le script orchestrateur :
```powershell
.\BIN\Start-VsanStoragePolicyCollection.ps1
```

## Mode DryRun vs Production

- **DryRun** (`$global:DryRun = $true` dans `CONF\config.ps1`, par défaut) : écrit un JSON réel dans `DRYRUN\VM_Storage_Policies_Compliance.json` (créé automatiquement si absent), mais en **instantané isolé** — aucune lecture ni fusion avec un run précédent, le fichier est simplement écrasé à chaque exécution. Sert à inspecter le résultat d'un run sans risque de confusion avec l'historique.
- **Production** (`$global:DryRun = $false`) : écrit vers `Config.JsonOutputPath` (UNC Zabbix), avec **fusion et gestion du stale** — une VM absente d'un run est reportée avec un `collectionStatus` dégradé plutôt que supprimée du JSON (voir ci-dessous).

## Schéma JSON — référence des champs

```json
{
  "schemaVersion": "1.1",
  "generatedAt": "2026-09-16T08:58:59Z",
  "generatedBy": "VMWARE_vSAN_StoragePolicy_ZABBIX",
  "vcentersStatus": {
    "<vcenter>": { "status": "ok|error", "lastSuccessAt": "..." }
  },
  "vmStoragePolicyCompliance": {
    "<vcenter>::<vmInstanceUuid>": {
      "vcenter": "...",
      "vmName": "...",
      "vmInstanceUuid": "...",
      "vmMoRef": "...",
      "cluster": "...",
      "overallComplianceStatus": "compliant|nonCompliant|notApplicable|none|error",
      "policyMismatch": true,
      "entities": [
        {
          "entityName": "VM Home",
          "entityId": "VirtualMachine-vm-123456",
          "storagePolicyName": "...",
          "complianceStatus": "compliant|nonCompliant|notApplicable|none|error",
          "datastore": "...",
          "datastoreType": "vsan|VMFS|NFS|...",
          "datastoreMismatch": false,
          "lastComplianceCheck": "..."
        },
        {
          "entityName": "Hard disk 1",
          "entityId": "VirtualMachine-vm-123456/2000",
          "storagePolicyName": "...",
          "complianceStatus": "compliant|nonCompliant|notApplicable|none|error",
          "datastore": "...",
          "datastoreType": "vsan|VMFS|NFS|...",
          "datastoreMismatch": false,
          "lastComplianceCheck": "..."
        }
      ],
      "collectionStatus": "fresh|stale_vcenter_unreachable|missing_after_success|error_collecting_entity",
      "staleSince": null
    }
  }
}
```

| Champ | Description |
|---|---|
| `vmInstanceUuid` | Identifiant stable de la VM (survit à un renommage), utilisé dans la clé composite. |
| `vmMoRef` | Identifiant technique court côté vCenter (ex. `1256466`, extrait de `VirtualMachine-vm-1256466`). Sert à retrouver directement l'objet VM via l'API/MOB vCenter en cas de support, indépendamment du nom ou de l'UUID. |
| `overallComplianceStatus` | Statut consolidé le plus défavorable parmi la VM Home et tous les disques collectés. L'ordre de sévérité est textuel et explicite, sans dépendre de la valeur numérique de l'enum PowerCLI. |
| `policyMismatch` | **`true`** si au moins deux entités de la même VM (VM Home/disques) portent des noms de policy différents. `null` si la ligne n'est pas `fresh`. |
| `entities[]` | Liste détaillée des objets contrôlés : une entrée `VM Home` et une entrée par disque virtuel. |
| `entityId` | Identifiant stable de l'entité contrôlée. Pour un disque, le format observé est `VirtualMachine-vm-.../2000`, `.../2001`, etc. |
| `datastoreMismatch` | Dans `entities[]`, **`true`** si l'entité est sur un cluster vSAN mais son datastore n'est pas de type `vsan`. `null` si la ligne n'est pas `fresh` (donnée non réaffirmée tant qu'un run réussi ne l'a pas reconfirmée). |
| `collectionStatus` | Fiabilité de la ligne : `fresh` (collectée avec succès ce run), `stale_vcenter_unreachable` (le vCenter a échoué, dernière donnée connue conservée), `missing_after_success` (le vCenter a répondu mais cette VM n'y est plus), `error_collecting_entity` (erreur de collecte sur cette VM précise). À vérifier avant de faire confiance à `complianceStatus`/`datastoreMismatch`. |
| `staleSince` | Horodatage de la **première fois** où la VM a été constatée absente d'une collecte fraîche. `null` tant qu'elle est activement collectée. |

## Références

- Broadcom KB — vSAN Health Service : vSAN Storage Policy (cas Not Applicable lié à un datastore non-vSAN) : [KB 326534](https://knowledge.broadcom.com/external/article/326534/vsan-health-service-vsan-storage-policy.html)
