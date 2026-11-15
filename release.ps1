# ==============================================================================
# Script de Release y Versionado Automatico Estandarizado (Web Flasher)
# Compatible con Windows PowerShell 5.1 y PowerShell 7+
# ==============================================================================
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $ScriptDir

$ConfigFile = Join-Path $ScriptDir ".web_config"
$ManifestFile = Join-Path $ScriptDir "manifest.json"
$HtmlFile = Join-Path $ScriptDir "index.html"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ------------------------------------------------------------------------------
# Funcion auxiliar: Confirmacion estricta 1 (Si) o 0 (No/Volver)
# ------------------------------------------------------------------------------
function Confirmar-1-0 {
    param([string]$PromptMsg)
    while ($true) {
        Write-Host "$PromptMsg " -NoNewline -ForegroundColor White
        $respuesta = Read-Host "[1: Si, 0: Volver/No]"
        $respuesta = $respuesta.Trim()
        if ($respuesta -eq "1") { return $true }
        if ($respuesta -eq "0") { return $false }
        Write-Host "[!] Entrada invalida. Debes escribir 1 o 0 y presionar Enter." -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "         GESTION DE RELEASE Y VERSIONADO (RELEASE.PS1)           " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------------------------
# 1. Carga de configuracion o resolucion de ruta de firmware
# ------------------------------------------------------------------------------
$ProjectName = ""
$FirmwareDir = ""
$BranchName = ""

if (Test-Path $ConfigFile -PathType Leaf) {
    $lines = Get-Content -Path $ConfigFile -Encoding UTF8
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $key = $Matches[1]
            $val = $Matches[2].Trim().Trim('"').Trim("'")
            switch ($key) {
                "PROJECT_NAME" { $ProjectName = $val }
                "FIRMWARE_DIR" { $FirmwareDir = $val }
                "BRANCH_NAME"  { $BranchName  = $val }
            }
        }
    }
    if ($FirmwareDir) {
        $FirmwareDir = $FirmwareDir -replace '/', '\'
    }
    Write-Host "Configuracion cargada desde .web_config:" -ForegroundColor Cyan
    Write-Host "  * Proyecto:     " -NoNewline; Write-Host ($(if ($ProjectName) { $ProjectName } else { "Desconocido" })) -ForegroundColor Green
    Write-Host "  * Directorio:   " -NoNewline; Write-Host "$FirmwareDir" -ForegroundColor Cyan
    Write-Host "  * Rama destino: " -NoNewline; Write-Host "$BranchName" -ForegroundColor Yellow
    Write-Host ""
}

if ([string]::IsNullOrWhiteSpace($FirmwareDir) -or -not (Test-Path $FirmwareDir -PathType Container)) {
    $ParentDir = Split-Path -Parent $ScriptDir
    $Candidatos = @()
    if (Test-Path $ParentDir) {
        $Dirs = Get-ChildItem -Path $ParentDir -Directory -ErrorAction SilentlyContinue
        foreach ($c in $Dirs) {
            if ($c.FullName -ne $ScriptDir -and (Test-Path (Join-Path $c.FullName "CMakeLists.txt"))) {
                $Candidatos += $c.FullName
            }
        }
    }

    if ($Candidatos.Count -eq 1) {
        $FirmwareDir = $Candidatos[0]
        Write-Host "Proyecto detectado automaticamente: " -NoNewline
        Write-Host "$FirmwareDir" -ForegroundColor Green
        Write-Host ""
    } elseif ($Candidatos.Count -gt 1) {
        Write-Host "Selecciona el proyecto de firmware a vincular:" -ForegroundColor White
        for ($i = 0; $i -lt $Candidatos.Count; $i++) {
            $idx = $i + 1
            $base = Split-Path -Leaf $Candidatos[$i]
            Write-Host "  $idx) " -NoNewline
            Write-Host "$base" -ForegroundColor Cyan -NoNewline
            Write-Host " ($($Candidatos[$i]))"
        }
        $manualOpt = $Candidatos.Count + 1
        Write-Host "  $manualOpt) Introducir ruta manualmente..."

        while ($true) {
            $selIdx = Read-Host "Elige una opcion [1-$manualOpt]"
            $selIdx = $selIdx.Trim()
            $parsedIdx = 0
            if ([int]::TryParse($selIdx, [ref]$parsedIdx)) {
                if ($parsedIdx -ge 1 -and $parsedIdx -le $Candidatos.Count) {
                    $FirmwareDir = $Candidatos[$parsedIdx - 1]
                    break
                } elseif ($parsedIdx -eq $manualOpt) {
                    $manualPath = Read-Host "Introduce la ruta al proyecto"
                    $manualPath = $manualPath.Trim().Trim('"').Trim("'")
                    if ($manualPath -and (Test-Path $manualPath -PathType Container)) {
                        $FirmwareDir = (Resolve-Path $manualPath).Path
                        break
                    } else {
                        Write-Host "El directorio '$manualPath' no existe." -ForegroundColor Red
                    }
                } else {
                    Write-Host "Opcion invalida." -ForegroundColor Red
                }
            } else {
                Write-Host "Opcion invalida." -ForegroundColor Red
            }
        }
    } else {
        $manualPath = Read-Host "Introduce la ruta al proyecto de firmware"
        $manualPath = $manualPath.Trim().Trim('"').Trim("'")
        if ($manualPath -and (Test-Path $manualPath -PathType Container)) {
            $FirmwareDir = (Resolve-Path $manualPath).Path
        }
    }

    # Guardar en .web_config para futuras ejecuciones
    if ($FirmwareDir -and (Test-Path $FirmwareDir -PathType Container) -and -not (Test-Path $ConfigFile)) {
        $projBase = Split-Path -Leaf $FirmwareDir
        $fwNorm = $FirmwareDir -replace '\\', '/'
        $ErrorActionPreference = "Continue"
        $currBr = (git branch --show-current 2>$null)
        $ErrorActionPreference = "Stop"
        if ([string]::IsNullOrWhiteSpace($currBr)) { $currBr = "master" }
        $cfgText = @"
# Archivo local de configuracion generado automaticamente
PROJECT_NAME="$projBase"
FIRMWARE_DIR="$fwNorm"
BRANCH_NAME="$currBr"
"@
        [System.IO.File]::WriteAllText($ConfigFile, $cfgText, $Utf8NoBom)
        Write-Host "[OK] Configuracion guardada en .web_config" -ForegroundColor Green
        Write-Host ""
    }
}

# ------------------------------------------------------------------------------
# 2. Deteccion de version actual
# ------------------------------------------------------------------------------
if (-not (Test-Path $ManifestFile -PathType Leaf)) {
    Write-Host "Error: No se encontro el archivo manifest.json en $ManifestFile" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $HtmlFile -PathType Leaf)) {
    Write-Host "Error: No se encontro el archivo index.html en $HtmlFile" -ForegroundColor Red
    exit 1
}

$manifestRaw = [System.IO.File]::ReadAllText($ManifestFile, $Utf8NoBom)
$CurrentVersion = "0.1"
if ($manifestRaw -match '"version"\s*:\s*"([^"]+)"') {
    $CurrentVersion = $Matches[1].Trim()
} else {
    Write-Host "No se pudo extraer la version actual de manifest.json. Usando 0.1 por defecto." -ForegroundColor Yellow
}

Write-Host "Version actual detectada: " -NoNewline
Write-Host "$CurrentVersion" -ForegroundColor Yellow
Write-Host ""

# ------------------------------------------------------------------------------
# 3. Calculo o definicion de la nueva version
# ------------------------------------------------------------------------------
$Sugerida = ""
if ($CurrentVersion -match '^(\d+)\.(\d+)$') {
    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    $Sugerida = "$major.$($minor + 1)"
} elseif ($CurrentVersion -match '^(\d+)\.(\d+)\.(\d+)$') {
    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    $patch = [int]$Matches[3]
    $Sugerida = "$major.$minor.$($patch + 1)"
}

$NewVersion = ""
while ($true) {
    if ($Sugerida) {
        Write-Host "Nueva version calculada automaticamente: " -NoNewline
        Write-Host "$Sugerida" -ForegroundColor Green
        if (Confirmar-1-0 "Deseas usar la version sugerida ($Sugerida)?") {
            $NewVersion = $Sugerida
            break
        }
    }

    while ($true) {
        $manualVer = Read-Host "Introduce la nueva version manualmente (ej. 0.2 o 1.0)"
        $manualVer = $manualVer.Trim()
        if ([string]::IsNullOrWhiteSpace($manualVer)) {
            Write-Host "La version no puede estar vacia." -ForegroundColor Red
            continue
        }
        if (Confirmar-1-0 "Confirmas que la nueva version sea '$manualVer'?") {
            $NewVersion = $manualVer
            break
        }
    }
    if ($NewVersion) { break }
}

Write-Host "Version acordada: " -NoNewline
Write-Host "$NewVersion" -ForegroundColor Green
Write-Host ""

# ------------------------------------------------------------------------------
# 4. Seleccion interactiva de Conventional Commits
# ------------------------------------------------------------------------------
$CommitType = ""
while ($true) {
    Write-Host "Selecciona el tipo de cambio para el commit:" -ForegroundColor Cyan
    Write-Host "  1) feat     - Nueva funcionalidad" -ForegroundColor Green
    Write-Host "  2) fix      - Correccion de un error / bug" -ForegroundColor Red
    Write-Host "  3) docs     - Documentacion" -ForegroundColor Blue
    Write-Host "  4) style    - Formato visual, CSS o UI" -ForegroundColor Yellow
    Write-Host "  5) refactor - Refactorizacion de codigo" -ForegroundColor Cyan
    Write-Host "  6) perf     - Mejora de rendimiento" -ForegroundColor Yellow
    Write-Host "  7) test     - Pruebas / tests" -ForegroundColor Blue
    Write-Host "  8) chore    - Mantenimiento, dependencias o scripts" -ForegroundColor White
    Write-Host "  9) Personalizado (escribir otro prefijo)" -ForegroundColor White

    $optTipo = (Read-Host "Opcion [1-9]").Trim()
    $tipoElegido = ""

    switch ($optTipo) {
        "1" { $tipoElegido = "feat" }
        "2" { $tipoElegido = "fix" }
        "3" { $tipoElegido = "docs" }
        "4" { $tipoElegido = "style" }
        "5" { $tipoElegido = "refactor" }
        "6" { $tipoElegido = "perf" }
        "7" { $tipoElegido = "test" }
        "8" { $tipoElegido = "chore" }
        "9" {
            $tipoElegido = (Read-Host "Escribe el prefijo personalizado").Trim()
        }
        default {
            Write-Host "Opcion no valida." -ForegroundColor Red
            Write-Host ""
            continue
        }
    }

    if ([string]::IsNullOrWhiteSpace($tipoElegido)) {
        Write-Host "El tipo no puede estar vacio." -ForegroundColor Red
        Write-Host ""
        continue
    }

    Write-Host "Has seleccionado el tipo: " -NoNewline
    Write-Host "$tipoElegido" -ForegroundColor Green
    if (Confirmar-1-0 "Confirmas el tipo de cambio '$tipoElegido'?") {
        $CommitType = $tipoElegido
        break
    } else {
        Write-Host "Regresando al menu de seleccion..." -ForegroundColor Yellow
        Write-Host ""
    }
}
Write-Host ""

# ------------------------------------------------------------------------------
# 5. Descripcion del commit y scope opcional
# ------------------------------------------------------------------------------
$CommitMsg = ""
while ($true) {
    $descCommit = (Read-Host "Descripcion breve del cambio").Trim()
    if ([string]::IsNullOrWhiteSpace($descCommit)) {
        Write-Host "La descripcion no puede estar vacia." -ForegroundColor Red
        continue
    }

    $scope = ""
    if (Confirmar-1-0 "Deseas agregar un alcance/scope? (ej. web, ui, esp32s3)") {
        $scope = (Read-Host "Nombre del alcance/scope").Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($scope)) {
        $fullMsg = "${CommitType}(${scope}): ${descCommit}"
    } else {
        $fullMsg = "${CommitType}: ${descCommit}"
    }

    Write-Host ""
    Write-Host "Mensaje resultante:"
    Write-Host "  $fullMsg" -ForegroundColor Green

    if (Confirmar-1-0 "Confirmas este mensaje de commit?") {
        $CommitMsg = $fullMsg
        break
    } else {
        Write-Host "Reescribiendo la descripcion..." -ForegroundColor Yellow
        Write-Host ""
    }
}
Write-Host ""

# ------------------------------------------------------------------------------
# 6. Deteccion, generacion y copia de binarios compilados
# ------------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($FirmwareDir) -or -not (Test-Path $FirmwareDir -PathType Container)) {
    Write-Host "[!] No se ha especificado un directorio de firmware valido. Se omite la copia de binarios." -ForegroundColor Yellow
    Write-Host ""
} else {
    $BuildDir = Join-Path $FirmwareDir "build"
    $BinSource = ""
    $Chip = "esp32s3"

    $flasherArgsFile = Join-Path $BuildDir "flasher_args.json"
    if (Test-Path $flasherArgsFile -PathType Leaf) {
        $faText = [System.IO.File]::ReadAllText($flasherArgsFile, $Utf8NoBom)
        if ($faText -match '"chip"\s*:\s*"([^"]+)"') {
            $Chip = $Matches[1].Trim()
        }
    }

    $candS3 = Join-Path $BuildDir "merged-binary-esp32s3.bin"
    $candGen = Join-Path $BuildDir "merged-binary.bin"
    if (Test-Path $candS3 -PathType Leaf) {
        $BinSource = $candS3
    } elseif (Test-Path $candGen -PathType Leaf) {
        $BinSource = $candGen
    }

    # Si no existe, verificar si hay compilacion y ofrecer generarlo con idf.py merge-bin
    if (-not $BinSource) {
        $bootloaderDir = Join-Path $BuildDir "bootloader"
        if ((Test-Path $flasherArgsFile -PathType Leaf) -or (Test-Path $bootloaderDir -PathType Container)) {
            Write-Host "[!] Se detecto compilacion en $BuildDir pero falta el archivo 'merged-binary.bin' unificado." -ForegroundColor Yellow
            if (Confirmar-1-0 "Deseas generarlo automaticamente ahora ejecutando 'idf.py merge-bin'?") {
                Write-Host "Ejecutando 'idf.py merge-bin' en $FirmwareDir..." -ForegroundColor Cyan
                Push-Location $FirmwareDir
                $ErrorActionPreference = "Continue"
                try {
                    idf.py merge-bin
                } catch {
                    Write-Host "No se pudo invocar 'idf.py' directamente desde esta terminal." -ForegroundColor Yellow
                }
                $ErrorActionPreference = "Stop"
                Pop-Location

                if (Test-Path $candGen -PathType Leaf) {
                    $BinSource = $candGen
                    Write-Host "[OK] merged-binary.bin generado con exito." -ForegroundColor Green
                    Write-Host ""
                } else {
                    Write-Host "No se pudo generar merged-binary.bin automaticamente." -ForegroundColor Red
                    Write-Host ""
                }
            }
        }
    }

    # Si aun no se encuentra, permitir indicar la ruta manual
    if (-not $BinSource) {
        Write-Host "[!] No se encontro ningun binario en: $BuildDir" -ForegroundColor Yellow
        if (Confirmar-1-0 "Deseas introducir manualmente la ruta a un archivo .bin compilado?") {
            $manualBin = (Read-Host "Ruta completa al archivo .bin").Trim().Trim('"').Trim("'")
            if ($manualBin -and (Test-Path $manualBin -PathType Leaf)) {
                $BinSource = (Resolve-Path $manualBin).Path
            } else {
                Write-Host "El archivo '$manualBin' no existe." -ForegroundColor Red
            }
        }
    }

    # Proceder a copiar si se tiene el binario origen
    if ($BinSource -and (Test-Path $BinSource -PathType Leaf)) {
        Write-Host ""
        Write-Host "Binario compilado detectado ($Chip): $BinSource" -ForegroundColor Cyan
        $TargetChipBin = Join-Path $ScriptDir "merged-binary-esp32s3.bin"

        if (Confirmar-1-0 "Deseas copiar este binario a ./merged-binary-esp32s3.bin?") {
            Copy-Item -Path $BinSource -Destination $TargetChipBin -Force
            $fileInfo = Get-Item $TargetChipBin
            $sizeKB = [math]::Round($fileInfo.Length / 1KB, 2)
            Write-Host "[OK] Binario ESP32-S3 actualizado exitosamente ($sizeKB KB)." -ForegroundColor Green
            Write-Host ""
        } else {
            Write-Host "Se conservara el binario existente." -ForegroundColor Yellow
            Write-Host ""
        }
    } else {
        Write-Host "[!] Se omitio la actualizacion de binarios (no se encontraron archivos nuevos)." -ForegroundColor Yellow
        Write-Host ""
    }
}

# ------------------------------------------------------------------------------
# 7. Actualizacion atomica de manifest.json e index.html
# ------------------------------------------------------------------------------
Write-Host "Actualizando archivos a la version $NewVersion..." -ForegroundColor Cyan

$manifestContent = [System.IO.File]::ReadAllText($ManifestFile, $Utf8NoBom)
$manifestContent = [regex]::Replace($manifestContent, '("version":\s*")[^"]+(")', "`${1}$NewVersion`${2}")
[System.IO.File]::WriteAllText($ManifestFile, $manifestContent, $Utf8NoBom)

$htmlContent = [System.IO.File]::ReadAllText($HtmlFile, $Utf8NoBom)
$htmlContent = [regex]::Replace($htmlContent, '(<span class="badge" id="version-badge">.*?v)[^<]+(</span>)', "`${1}$NewVersion`${2}")
[System.IO.File]::WriteAllText($HtmlFile, $htmlContent, $Utf8NoBom)

Write-Host "Archivos actualizados:" -ForegroundColor Green
$ErrorActionPreference = "Continue"
git --no-pager diff "$ManifestFile" "$HtmlFile" 2>$null
$ErrorActionPreference = "Stop"
Write-Host ""

# ------------------------------------------------------------------------------
# 8. Confirmacion final antes de Git commit y tag
# ------------------------------------------------------------------------------
$TagName = "v$NewVersion"

Write-Host "Resumen de la operacion:" -ForegroundColor White
Write-Host "  * Nueva version: " -NoNewline; Write-Host "$NewVersion" -ForegroundColor Green
Write-Host "  * Tag de Git:    " -NoNewline; Write-Host "$TagName" -ForegroundColor Green
Write-Host "  * Commit:        " -NoNewline; Write-Host "$CommitMsg" -ForegroundColor Green
Write-Host ""

if (-not (Confirmar-1-0 "Deseas aplicar estos cambios, hacer git add, commit y crear el tag?")) {
    Write-Host "Operacion cancelada. Revirtiendo modificaciones..." -ForegroundColor Yellow
    $ErrorActionPreference = "Continue"
    git checkout -- "$ManifestFile" "$HtmlFile" "merged-binary-esp32s3.bin" 2>$null
    $ErrorActionPreference = "Stop"
    Write-Host "Cambios descartados. El repositorio no fue alterado." -ForegroundColor Red
    exit 0
}

$ErrorActionPreference = "Continue"
git add "$ManifestFile" "$HtmlFile"
if (Test-Path (Join-Path $ScriptDir "merged-binary-esp32s3.bin")) {
    git add "merged-binary-esp32s3.bin"
}
foreach ($extraFile in @("release.sh", "release.ps1", "release.bat", "init_web.sh", "init_web.ps1", "init_web.bat", "script.sh", ".gitattributes")) {
    if (Test-Path (Join-Path $ScriptDir $extraFile)) {
        git add $extraFile 2>$null
    }
}

git commit -m "$CommitMsg"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error al crear el commit." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Commit creado." -ForegroundColor Green

git tag -a "$TagName" -m "$CommitMsg"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error al crear el tag '$TagName' (verifica si ya existe)." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Tag '$TagName' creado." -ForegroundColor Green
Write-Host ""

# ------------------------------------------------------------------------------
# 9. Sincronizacion con el repositorio remoto
# ------------------------------------------------------------------------------
$CurrentBranch = (git branch --show-current 2>$null)
if ([string]::IsNullOrWhiteSpace($CurrentBranch)) { $CurrentBranch = "master" }

$Remotes = @(git remote 2>$null)
$Remote = if ($Remotes.Count -gt 0) { $Remotes[0].Trim() } else { "" }

if (-not [string]::IsNullOrWhiteSpace($Remote)) {
    Write-Host "Remoto detectado: " -NoNewline
    Write-Host "$Remote" -ForegroundColor Cyan -NoNewline
    Write-Host " (rama activa: $CurrentBranch)"
    if (Confirmar-1-0 "Deseas hacer push al remoto '$Remote' en la rama '$CurrentBranch'?") {
        Write-Host "Subiendo commits y tags al remoto..." -ForegroundColor Cyan
        git push "$Remote" "$CurrentBranch"
        git push "$Remote" "$TagName"
        Write-Host ""
        Write-Host "Release completado y publicado exitosamente!" -ForegroundColor Green
    } else {
        Write-Host "Push omitido. Los cambios y el tag han quedado guardados localmente." -ForegroundColor Yellow
    }
} else {
    Write-Host "No se detecto ningun remoto configurado. Release guardado localmente." -ForegroundColor Yellow
}
$ErrorActionPreference = "Stop"

exit 0
