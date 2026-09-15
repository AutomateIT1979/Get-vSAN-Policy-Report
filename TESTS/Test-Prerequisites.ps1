# ============================================================
# VMWARE_vSAN_StoragePolicy_ZABBIX - Test-Prerequisites.ps1
# ============================================================
# Auteur      : Sabri CHARCHOUF
# Date        : 15/09/2026
# Version     : 1.0
#
# Description :
#   Vérifie la présence des dépendances, de la config et des
#   credentials nécessaires à l'exécution de l'orchestrateur.
#
# Architecture :
#   Indépendant de BIN\. Ne lance aucune action métier.
#
# Environment :
#   Agnostique
#
#Requires -Version 7.0
# ============================================================

$ErrorActionPreference = 'Stop'

Write-Host "=== VÉRIFICATION DES PRÉREQUIS ===" -ForegroundColor Cyan

# 1. Configuration
$configFile = "$PSScriptRoot\..\CONF\config.ps1"
if (Test-Path $configFile) {
    Write-Host "[OK] Fichier de configuration trouvé." -ForegroundColor Green
    . $configFile
} else {
    Write-Host "[ERREUR] config.ps1 introuvable dans CONF\" -ForegroundColor Red
    exit 1
}

# 2. Module PowerCLI
if (Get-Module -ListAvailable -Name VMware.PowerCLI) {
    Write-Host "[OK] Module VMware.PowerCLI disponible." -ForegroundColor Green
} else {
    Write-Host "[ERREUR] Module VMware.PowerCLI introuvable sur cette machine." -ForegroundColor Red
    exit 1
}

# 3. GLOBAL_CONF (Si utilisé)
$globalParams = "\\<SERVEUR_REBOND>\d$\SCRIPTS\GLOBAL_CONF\global_params.ps1"
if (Test-Path $globalParams) {
    Write-Host "[OK] global_params.ps1 accessible." -ForegroundColor Green
} else {
    Write-Host "[ERREUR] global_params.ps1 inaccessible." -ForegroundColor Red
    exit 1
}

Write-Host "=== TOUS LES PRÉREQUIS SONT VALIDES ===" -ForegroundColor Cyan
exit 0
