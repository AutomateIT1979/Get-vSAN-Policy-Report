# ============================================================
# VMWARE_vSAN_StoragePolicy_ZABBIX - Initialize-PowerCLI.ps1
# ============================================================
# Auteur      : Sabri CHARCHOUF
# Date        : 16/09/2026
# Version     : 8.0
#
# Description :
#   Détecte et charge le module PowerCLI disponible sur le
#   serveur d'exécution, puis applique la configuration SSL/CEIP
#   requise avant tout Connect-VIServer. Priorité VCF.PowerCLI
#   (officiel depuis juin 2025), repli sur VMware.PowerCLI (déprécié
#   mais fonctionnel).
#
# Usage :
#   Initialize-PowerCLI
#
# Prérequis :
#   - Write-Log.ps1 chargé avant (canaux EXECUTION et ERRORS)
#   - Au moins un module PowerCLI installé (VCF.PowerCLI ou VMware.PowerCLI)
#
# Architecture :
#   Appelé par Start-VsanStoragePolicyCollection.ps1, avant la boucle
#   sur $Config.vCenters. Ne prend aucun paramètre, throw si aucun
#   module PowerCLI n'est disponible.
#
# Environment :
#   Agnostique
#
#Requires -Version 7.0
# ============================================================

Function Initialize-PowerCLI {

    $funcStart = Get-Date

    Write-Log -Type EXECUTION -Message "Initialize-PowerCLI : démarrage détection modules PowerCLI" -Level INFO

    $vcfModule = Get-Module -ListAvailable -Name "VCF.PowerCLI" |
        Sort-Object Version -Descending |
        Select-Object -First 1

    $vmwareModule = Get-Module -ListAvailable -Name "VMware.PowerCLI" |
        Sort-Object Version -Descending |
        Select-Object -First 1

    $moduleToLoad = $null
    $moduleVersion = $null

    if ($vcfModule) {
        $moduleVersion = $vcfModule.Version
        $moduleToLoad  = "VCF.PowerCLI"

        Write-Log -Type EXECUTION -Message "Initialize-PowerCLI : VCF.PowerCLI détecté - Version $moduleVersion à utiliser" -Level INFO

        if ($vmwareModule) {
            Write-Log -Type ERRORS -Message "Initialize-PowerCLI : coexistence modules | VCF ($($vcfModule.Version)) et VMware ($($vmwareModule.Version)) - risque conflit" -Level WARNING
        }

    } elseif ($vmwareModule) {
        $moduleVersion = $vmwareModule.Version
        $moduleToLoad  = "VMware.PowerCLI"

        Write-Log -Type ERRORS -Message "Initialize-PowerCLI : VMware.PowerCLI $moduleVersion utilisé - déprécié depuis juin 2025 - migration VCF.PowerCLI recommandée" -Level WARNING

    } else {
        Write-Log -Type ERRORS -Message "Initialize-PowerCLI : ERREUR FATALE - aucun module PowerCLI disponible sur ce serveur" -Level ERROR
        throw "Aucun module PowerCLI disponible. Installation nécessaire."
    }

    try {
        Import-Module $moduleToLoad -ErrorAction Stop
        Write-Log -Type EXECUTION -Message "Initialize-PowerCLI : $moduleToLoad $moduleVersion chargé avec succès" -Level SUCCESS
    }
    catch {
        Write-Log -Type ERRORS -Message "Initialize-PowerCLI : erreur fatale chargement $moduleToLoad | $_" -Level ERROR
        throw "Chargement du module $moduleToLoad impossible."
    }

    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore `
                               -ParticipateInCEIP $false `
                               -Scope Session -Confirm:$false | Out-Null

    $funcDuration = (Get-Date) - $funcStart

    Write-Log -Type EXECUTION -Message "Initialize-PowerCLI : terminée | Module=$moduleToLoad | Version=$moduleVersion | SSL=Ignore | CEIP=false | Durée=$([math]::Round($funcDuration.TotalSeconds,2)) sec" -Level SUCCESS
}
