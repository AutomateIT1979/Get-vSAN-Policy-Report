# ============================================================
# VMWARE_vSAN_StoragePolicy_ZABBIX - Start-VsanStoragePolicyCollection.ps1
# ============================================================
# Auteur      : Sabri CHARCHOUF
# Date        : 15/09/2026
# Version     : 8.0
#
# Description :
#   Orchestrateur principal du projet. Boucle sur les vCenters,
#   collecte la conformité vSAN, et génère le JSON final.
#
# Usage :
#   .\Start-VsanStoragePolicyCollection.ps1
#
# Prérequis :
#   - VMware.PowerCLI
#   - Fichiers AES
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

$scriptStartTime = Get-Date

# 1. Chargement de la configuration
. "$PSScriptRoot\..\CONF\config.ps1"

# 2. Chargement des fonctions (Write-Log EN PREMIER)
. "$PSScriptRoot\..\FUNCTIONS\Write-Log.ps1"
. "$PSScriptRoot\..\FUNCTIONS\Initialize-PowerCLI.ps1"
. "$PSScriptRoot\..\FUNCTIONS\Connect-VCenter.ps1"
. "$PSScriptRoot\..\FUNCTIONS\Get-VmStoragePolicyCompliance.ps1"
. "$PSScriptRoot\..\FUNCTIONS\Write-VmStoragePolicyComplianceJson.ps1"

Write-Log -Message "=== DÉBUT EXÉCUTION VMWARE_vSAN_StoragePolicy_ZABBIX ===" -Level 'INFO' -Type 'EXECUTION'

try {
    # 3. Chargement du module PowerCLI + config SSL/CEIP (obligatoire avant tout Connect-VIServer)
    Initialize-PowerCLI

    # 4. Récupération des credentials (AES via GLOBAL_CONF)
    Write-Log -Message "Récupération des credentials pour $($Config.CredentialDomain)\$($Config.CredentialAccountName)..." -Level 'INFO' -Type 'EXECUTION'
    # -UserName : certains comptes de service nécessitent le format UPN complet
    # pour l'authentification SSO vCenter (voir CONF\config.ps1, CredentialUserName).
    # Si non défini, Get-AesCredential retombe sur le format Domain\Compte.
    $getAesCredParams = @{
        Domain      = $Config.CredentialDomain
        AccountName = $Config.CredentialAccountName
    }
    if ($Config.ContainsKey('CredentialUserName') -and $Config.CredentialUserName) {
        $getAesCredParams.UserName = $Config.CredentialUserName
    }
    $cred = Get-AesCredential @getAesCredParams

    $allResults = @()
    $vcentersStatus = @{}

    # 5. Boucle sur les vCenters
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

    # 6. Génération JSON - en DryRun, écriture réelle mais redirigée vers
    # DRYRUN\ (créé si absent) au lieu du chemin de production UNC.
    $jsonTargetPath = if ($global:DryRun) { $Config.DryRunOutputPath } else { $Config.JsonOutputPath }
    Write-Log -Message "Écriture du fichier JSON de sortie ($jsonTargetPath)..." -Level 'INFO' -Type 'EXECUTION'
    Write-VmStoragePolicyComplianceJson -JsonPath $jsonTargetPath -CurrentResults $allResults -VCenterStatus $vcentersStatus

    $duration = (Get-Date) - $scriptStartTime
    Write-Log -Message "=== FIN EXÉCUTION AVEC SUCCÈS | Durée totale=$([math]::Round($duration.TotalMinutes,2)) min ($([math]::Round($duration.TotalSeconds,1)) sec) ===" -Level 'INFO' -Type 'EXECUTION'
    exit 0
}
catch {
    $duration = (Get-Date) - $scriptStartTime
    Write-Log -Message "[ERREUR FATALE] Orchestrateur : $($_.Exception.Message) | Durée avant échec=$([math]::Round($duration.TotalMinutes,2)) min" -Level 'ERROR' -Type 'ERRORS'
    exit 1
}
