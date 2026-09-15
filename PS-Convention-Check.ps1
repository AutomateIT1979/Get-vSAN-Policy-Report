# ============================================================
# VMWARE_vSAN_StoragePolicy_ZABBIX - PS-Convention-Check.ps1
# ============================================================
# Auteur      : Sabri CHARCHOUF
# Date        : 15/09/2026
# Version     : 8.0
#
# Description :
#   Controle les conventions PowerShell automatisables avant commit.
#
# Usage :
#   .\PS-Convention-Check.ps1 -Path .\FUNCTIONS
#
# Prérequis :
#   - PowerShell 5.1 minimum pour le hook Git
#
# Architecture :
#   Analyse textuelle des fichiers .ps1 et retour non nul si violation.
#
# Environment :
#   Agnostique
#
#Requires -Version 5.1
# ============================================================

param(
    [string]$Path = ".",        # Fichier .ps1 ou repertoire
    [switch]$Verbose
)

$violations = [System.Collections.Generic.List[PSCustomObject]]::new()
$files = if (Test-Path $Path -PathType Leaf) {
    Get-Item $Path
} else {
    Get-ChildItem $Path -Recurse -Filter "*.ps1" |
        Where-Object {
            $_.FullName -notmatch '\\\.git\\' -and
            $_.FullName -notmatch '\\\.local-docs\\'
        }
}

foreach ($file in $files) {
    $lignes  = Get-Content $file.FullName -ErrorAction SilentlyContinue
    $isDotSourced = $file.Name -notmatch '^(Main|Run|Start|BIN|Report|Scan-Secrets|PS-Convention-Check)' -and
                    $file.DirectoryName -match 'FUNCTIONS'
    $hasHeader = $false

    # Ignore le header des scripts de controle racine.
    if ($file.Name -eq 'Scan-Secrets.ps1' -or $file.Name -eq 'PS-Convention-Check.ps1') {
        $hasHeader = $true
    }

    for ($i = 0; $i -lt $lignes.Count; $i++) {
        $l   = $lignes[$i]
        $num = $i + 1

        # Convention 1 : ConvertTo-Json sans -Depth.
        if ($l -match 'ConvertTo-Json' -and $l -notmatch '-Depth') {
            $violations.Add([PSCustomObject]@{
                Fichier = $file.Name; Ligne = $num; Regle = 'ConvertTo-Json sans -Depth 10'
                Extrait = $l.Trim()
            })
        }

        # Convention 2 : $PSScriptRoot dans un fichier dot-source.
        if ($isDotSourced -and $l -match '\$PSScriptRoot') {
            $violations.Add([PSCustomObject]@{
                Fichier = $file.Name; Ligne = $num; Regle = '$PSScriptRoot interdit dans fichier dot-source'
                Extrait = $l.Trim()
            })
        }

        # Convention 3 : variables reservees PowerShell.
        foreach ($reserved in @('host', 'Verbose', 'file')) {
            if ($l -match "^\s*\`$$reserved\b\s*=") {
                $violations.Add([PSCustomObject]@{
                    Fichier = $file.Name; Ligne = $num; Regle = "Variable reservee PowerShell : `$$reserved"
                    Extrait = $l.Trim()
                })
            }
        }

        # Convention 4 : DryRun = $false par defaut.
        if ($l -match '\$DryRun\s*=\s*\$false' -and $l -notmatch '#') {
            $violations.Add([PSCustomObject]@{
                Fichier = $file.Name; Ligne = $num; Regle = 'DryRun = $false interdit par defaut'
                Extrait = $l.Trim()
            })
        }

        # Convention 5 : emojis dans Write-Host.
        if ($l -match 'Write-Host' -and ($l -match '[\u2600-\u27BF]' -or $l -match '[\uD83C-\uD83E][\uDC00-\uDFFF]')) {
            $violations.Add([PSCustomObject]@{
                Fichier = $file.Name; Ligne = $num; Regle = 'Emoji dans Write-Host - utiliser [OK]/[ERREUR]/[ALERTE]'
                Extrait = $l.Trim()
            })
        }

        # Convention 6 : header present.
        if ($num -le 10 -and $l -match '# Auteur') { $hasHeader = $true }
    }

    # Convention 6 suite : header manquant.
    if (-not $hasHeader) {
        $violations.Add([PSCustomObject]@{
            Fichier = $file.Name; Ligne = 0; Regle = 'Header obligatoire manquant (# Auteur, # Date, # Version)'
            Extrait = '(debut de fichier)'
        })
    }

    # Convention 7 : ConvertTo-Json avec -Depth different de 10.
    $lignes | Select-String 'ConvertTo-Json.*-Depth\s+(?!10\b)\d+' | ForEach-Object {
        $violations.Add([PSCustomObject]@{
            Fichier = $file.Name; Ligne = $_.LineNumber; Regle = 'ConvertTo-Json : -Depth doit etre 10'
            Extrait = $_.Line.Trim()
        })
    }
}

# Rapport.
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  PS-CONVENTION-CHECK" -ForegroundColor Cyan
Write-Host "  Fichiers analyses : $($files.Count)" -ForegroundColor Cyan
Write-Host "  Violations        : $($violations.Count)" -ForegroundColor $(if ($violations.Count -eq 0) {'Green'} else {'Red'})
Write-Host "============================================`n" -ForegroundColor Cyan

if ($violations.Count -gt 0) {
    $violations | Format-Table Fichier, Ligne, Regle, Extrait -Wrap -AutoSize
    Write-Host "[BLOQUE] $($violations.Count) violation(s) - corriger avant commit." -ForegroundColor Red
    exit 1
} else {
    Write-Host "[OK] Aucune violation de convention." -ForegroundColor Green
    exit 0
}
