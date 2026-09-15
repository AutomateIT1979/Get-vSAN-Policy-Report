# ============================================================
# VMWARE_vSAN_StoragePolicy_ZABBIX - Connect-VCenter.ps1
# ============================================================
# Auteur      : Sabri CHARCHOUF
# Date        : 15/09/2026
# Version     : 8.0
#
# Description :
#   Wrapper générique pour la connexion au vCenter.
#
# Usage :
#   Connect-VCenter -VCenter "vcenter" -Credential $cred
#
# Prérequis :
#   - VMware.PowerCLI
#
# Architecture :
#   Appelé par Start-VsanStoragePolicyCollection.ps1
#
# Environment :
#   Agnostique
#
#Requires -Version 7.0
# ============================================================

$ErrorActionPreference = 'Stop'

function Connect-VCenter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VCenter,

        [Parameter(Mandatory = $true)]
        [pscredential]$Credential
    )

    try {
        Write-Log -Message "Tentative de connexion au vCenter : $VCenter" -Level 'INFO' -Type 'EXECUTION'

        $connection = Connect-VIServer -Server $VCenter -Credential $Credential -ErrorAction Stop

        if ($connection.IsConnected) {
            Write-Log -Message "[OK] Connecté au vCenter $VCenter" -Level 'INFO' -Type 'EXECUTION'
            return $connection
        } else {
            Write-Log -Message "[ERREUR] Échec de la connexion au vCenter $VCenter (Objet non connecté)" -Level 'ERROR' -Type 'ERRORS'
            return $null
        }
    }
    catch {
        Write-Log -Message "[ERREUR] Impossible de se connecter au vCenter $VCenter : $($_.Exception.Message)" -Level 'ERROR' -Type 'ERRORS'
        return $null
    }
}
