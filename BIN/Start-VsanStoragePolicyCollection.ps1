# ============================================================
# VMWARE_vSAN_StoragePolicy_ZABBIX - Start-VsanStoragePolicyCollection.ps1
# ============================================================
# Auteur      : Sabri CHARCHOUF
# Date        : 15/09/2026
# Version     : 1.0
#
# Description :
#   Orchestrateur principal du projet. Boucle sur les vCenters,
#   collecte la conformité vSAN, et génère le JSON final.
#
# Architecture :
#   Zéro logique métier. Appelle les fonctions de FUNCTIONS\.
#
# Environment :
#   Agnostique
#
#Requires -Version 7.0
# ============================================================

$ErrorActionPreference = 'Stop'

# 1. Chargement de la configuration
. "$PSScriptRoot\..\CONF\config.ps1"

# 2. Chargement des fonctions (Write-Log EN PREMIER)
. "$PSScriptRoot\..\FUNCTIONS\Write-Log.ps1"
. "$PSScriptRoot\..\FUNCTIONS\Connect-VCenter.ps1"
. "$PSScriptRoot\..\FUNCTIONS\Get-VmStoragePolicyCompliance.ps1"
. "$PSScriptRoot\..\FUNCTIONS\Write-VmStoragePolicyComplianceJson.ps1"

Write-Log -Message "=== DÉBUT EXÉCUTION VMWARE_vSAN_StoragePolicy_ZABBIX ===" -Level 'INFO' -Type 'EXECUTION'

try {
    # 3. Récupération des credentials (AES via GLOBAL_CONF)
    Write-Log -Message "Récupération des credentials pour $($Config.CredentialDomain)\$($Config.CredentialAccountName)..." -Level 'INFO' -Type 'EXECUTION'
    $cred = Get-AesCredential -Domain $Config.CredentialDomain -AccountName $Config.CredentialAccountName

    $allResults = @()
    $vcentersStatus = @{}

    # 4. Boucle sur les vCenters
    foreach ($vc in $Config.vCenters) {
        Write-Log -Message "Traitement du vCenter : $vc" -Level 'INFO' -Type 'EXECUTION'

        $connection = Connect-VCenter -VCenter $vc -Credential $cred
        if ($connection) {
            $vcResults = Get-VmStoragePolicyCompliance -VCenterName $vc
            if ($null -ne $vcResults) {
                $vcentersStatus[$vc] = 'ok'
                $allResults += $vcResults
            } else {
                $vcentersStatus[$vc] = 'error'
                Write-Log -Message "[ALERTE] Échec de collecte pour $vc (stale_vcenter_unreachable)" -Level 'WARNING' -Type 'EXECUTION'
            }

            # Déconnexion propre
            try {
                Disconnect-VIServer -Server $vc -Confirm:$false -Force -ErrorAction Stop
                Write-Log -Message "Déconnecté proprement du vCenter $vc" -Level 'INFO' -Type 'EXECUTION'
            } catch {
                Write-Log -Message "[WARN] Erreur lors de la déconnexion de $vc : $($_.Exception.Message)" -Level 'WARNING' -Type 'EXECUTION'
            }
        } else {
            $vcentersStatus[$vc] = 'error'
            Write-Log -Message "[ALERTE] Passage du vCenter $vc en erreur (stale_vcenter_unreachable)" -Level 'WARNING' -Type 'EXECUTION'
        }
    }

    # 5. Génération JSON
    Write-Log -Message "Écriture du fichier JSON de sortie..." -Level 'INFO' -Type 'EXECUTION'
    Write-VmStoragePolicyComplianceJson -JsonPath $Config.JsonOutputPath -CurrentResults $allResults -VCenterStatus $vcentersStatus

    Write-Log -Message "=== FIN EXÉCUTION AVEC SUCCÈS ===" -Level 'INFO' -Type 'EXECUTION'
    exit 0
}
catch {
    Write-Log -Message "[ERREUR FATALE] Orchestrateur : $($_.Exception.Message)" -Level 'ERROR' -Type 'ERRORS'
    exit 1
}
