# ============================================================
# VMWARE_vSAN_StoragePolicy_ZABBIX - Write-Log.ps1
# ============================================================
# Auteur      : Sabri CHARCHOUF
# Date        : 20/06/2026
# Version     : 8.0
#
# Description :
#   Logging centralisé pour toutes les fonctions du projet.
#   Gère l'écriture de logs dans 3 canaux (EXECUTION, VMIMPACT, ERRORS).
#
# Architecture :
#   Appelé par toutes les fonctions et scripts du projet.
#   Chargé en deuxième dans BIN\Start-VsanStoragePolicyCollection.ps1.
#
# Environment :
#   Agnostique (pas de chemin hardcodé)
#
#Requires -Version 7.0
# ============================================================

<#
.SYNOPSIS
    Logging centralisé pour toutes les fonctions d'un projet PowerShell.
.DESCRIPTION
    Fournit 3 canaux de logs horodatés (EXECUTION, VMIMPACT, ERRORS) avec affichage console coloré.
.PARAMETER Type
    Le canal de log cible (EXECUTION, VMIMPACT, ou ERRORS).
.PARAMETER Message
    Le message à écrire dans le log.
.PARAMETER Level
    Niveau de log (INFO, SUCCESS, WARNING, ERROR).
.PARAMETER DryRun
    Si vrai, préfixe le log par [DRYRUN].
#>
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("EXECUTION", "VMIMPACT", "ERRORS")]
        [string]$Type,

        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO",

        [Parameter(Mandatory=$false)]
        [bool]$DryRun = $false # Conforme aux paramètres optionnels
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $dryrunTag = if ($DryRun) { "[DRYRUN] " } else { "" }
    $ligne     = "$timestamp | $Level | $dryrunTag$Message"

    $resolvedExecPath  = if ($global:logExecutionPath) { $global:logExecutionPath } else { $logExecutionPath }
    $resolvedImpactPath= if ($global:logVMImpactPath)  { $global:logVMImpactPath }  else { $logVMImpactPath }
    $resolvedErrorPath = if ($global:logErrorsPath)    { $global:logErrorsPath }    else { $logErrorsPath }
    $resolvedDate      = if ($global:date)             { $global:date }             else { $date }

    switch ($Type) {
        "EXECUTION" {
            $logFile = if ($resolvedExecPath)   { Join-Path $resolvedExecPath   "Execution_$resolvedDate.log" } else { $null }
        }
        "VMIMPACT" {
            $logFile = if ($resolvedImpactPath) { Join-Path $resolvedImpactPath "VMImpact_$resolvedDate.log"  } else { $null }
        }
        "ERRORS" {
            $logFile = if ($resolvedErrorPath)  { Join-Path $resolvedErrorPath  "Errors_$resolvedDate.log"   } else { $null }
        }
    }

    if ($logFile) {
        $dossier = Split-Path $logFile -Parent
        if (-not (Test-Path $dossier)) {
            New-Item -ItemType Directory -Path $dossier -Force | Out-Null
        }
        Add-Content -Path $logFile -Value $ligne -Encoding UTF8
    }

    $couleur = switch ($Level) {
        "INFO"    { "Gray"   }
        "SUCCESS" { "Green"  }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red"    }
        default   { "White"  }
    }

    Write-Host "  [LOG-$Type] $ligne" -ForegroundColor $couleur
}
