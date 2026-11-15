# ==============================================================================
# Script de Inicializacion y Vinculacion de Proyectos (Web Flasher Template)
# Compatible con Windows PowerShell 5.1 y PowerShell 7+
# ==============================================================================
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $ScriptDir

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ------------------------------------------------------------------------------
# Confirmacion interactiva [1: Si, 0: No]
# ------------------------------------------------------------------------------
function Confirmar-1-0 {
    param([string]$PromptMsg)
    while ($true) {
        Write-Host "$PromptMsg " -NoNewline -ForegroundColor White
        $respuesta = Read-Host "[1: Si, 0: Volver/No]"
        $respuesta = $respuesta.Trim()
        if ($respuesta -eq "1") { return $true }
        if ($respuesta -eq "0") { return $false }
        Write-Host "[!] Entrada invalida. Escribe 1 o 0 y pulsa Enter." -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "           INICIALIZADOR DE WEB FLASHER (ESP32-S3)               " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------------------------
# 1. Escaneo y Seleccion del Proyecto de Firmware
# ------------------------------------------------------------------------------
$ParentDir = Split-Path -Parent $ScriptDir
$Candidatos = @()

if (Test-Path $ParentDir) {
    $Dirs = Get-ChildItem -Path $ParentDir -Directory -ErrorAction SilentlyContinue
    foreach ($d in $Dirs) {
        if ($d.FullName -ne $ScriptDir) {
            $Candidatos += $d.FullName
        }
    }
}

Write-Host "Paso 1: Selecciona el proyecto de firmware a vincular:" -ForegroundColor White
$TotalCandidatos = $Candidatos.Count

if ($TotalCandidatos -gt 0) {
    for ($i = 0; $i -lt $TotalCandidatos; $i++) {
        $projDir = $Candidatos[$i]
        $projBase = Split-Path -Leaf $projDir
        $idx = $i + 1
        Write-Host "  $idx) " -NoNewline -ForegroundColor White
        Write-Host "$projBase " -NoNewline -ForegroundColor Cyan
        if (Test-Path (Join-Path $projDir "CMakeLists.txt")) {
            Write-Host "(ESP-IDF detectado)" -ForegroundColor Green
        } else {
            Write-Host ""
        }
    }
    $manualOption = $TotalCandidatos + 1
    Write-Host "  $manualOption) Introducir otra ruta manualmente..." -ForegroundColor White
} else {
    Write-Host "No se detectaron proyectos hermanos en $ParentDir" -ForegroundColor Yellow
}

$FirmwareDir = ""
while ($true) {
    if ($TotalCandidatos -gt 0) {
        Write-Host ""
        $maxOpt = $TotalCandidatos + 1
        $selIdx = Read-Host "Elige una opcion [1-$maxOpt]"
        $selIdx = $selIdx.Trim()
        $parsedIdx = 0
        if ([int]::TryParse($selIdx, [ref]$parsedIdx)) {
            if ($parsedIdx -ge 1 -and $parsedIdx -le $TotalCandidatos) {
                $FirmwareDir = $Candidatos[$parsedIdx - 1]
                break
            } elseif ($parsedIdx -eq ($TotalCandidatos + 1)) {
                $manualPath = Read-Host "Introduce la ruta absoluta o relativa al proyecto"
                $manualPath = $manualPath.Trim().Trim('"').Trim("'")
                if ($manualPath -and (Test-Path $manualPath -PathType Container)) {
                    $FirmwareDir = (Resolve-Path $manualPath).Path
                    break
                } else {
                    Write-Host "El directorio '$manualPath' no existe." -ForegroundColor Red
                }
            } else {
                Write-Host "Opcion no valida." -ForegroundColor Red
            }
        } else {
            Write-Host "Opcion no valida." -ForegroundColor Red
        }
    } else {
        $manualPath = Read-Host "Introduce la ruta al proyecto de firmware"
        $manualPath = $manualPath.Trim().Trim('"').Trim("'")
        if ($manualPath -and (Test-Path $manualPath -PathType Container)) {
            $FirmwareDir = (Resolve-Path $manualPath).Path
            break
        } else {
            Write-Host "El directorio '$manualPath' no existe." -ForegroundColor Red
        }
    }
}

$DefaultName = Split-Path -Leaf $FirmwareDir
Write-Host ""
Write-Host "Proyecto seleccionado: " -NoNewline
Write-Host "$DefaultName" -ForegroundColor Green -NoNewline
Write-Host " ($FirmwareDir)"
Write-Host ""

# ------------------------------------------------------------------------------
# 2. Configuracion de Nombre, Version y Rama Git
# ------------------------------------------------------------------------------
Write-Host "Paso 2: Datos de personalizacion de la pagina:" -ForegroundColor White

$inputTitle = Read-Host "Nombre a mostrar en la web [por defecto: $DefaultName]"
$ProjectTitle = if ([string]::IsNullOrWhiteSpace($inputTitle)) { $DefaultName } else { $inputTitle.Trim() }

$inputVer = Read-Host "Version inicial [por defecto: 0.1]"
$InitialVersion = if ([string]::IsNullOrWhiteSpace($inputVer)) { "0.1" } else { $inputVer.Trim() }

$DefaultBranch = "${DefaultName}_web"
$inputBranch = Read-Host "Nombre de la rama Git para esta web [por defecto: $DefaultBranch]"
$TargetBranch = if ([string]::IsNullOrWhiteSpace($inputBranch)) { $DefaultBranch } else { $inputBranch.Trim() }

Write-Host ""
Write-Host "Resumen de configuracion:" -ForegroundColor White
Write-Host "  * Proyecto:         " -NoNewline; Write-Host "$DefaultName" -ForegroundColor Green
Write-Host "  * Titulo web:       " -NoNewline; Write-Host "$ProjectTitle" -ForegroundColor Green
Write-Host "  * Version base:     " -NoNewline; Write-Host "v$InitialVersion" -ForegroundColor Green
Write-Host "  * Directorio build: " -NoNewline; Write-Host "$FirmwareDir" -ForegroundColor Cyan
Write-Host "  * Rama Git destino: " -NoNewline; Write-Host "$TargetBranch" -ForegroundColor Yellow
Write-Host ""

if (-not (Confirmar-1-0 "Deseas aplicar esta configuracion?")) {
    Write-Host "Configuracion cancelada. No se modifico ningun archivo." -ForegroundColor Yellow
    exit 0
}

# ------------------------------------------------------------------------------
# 3. Aplicar personalizacion en index.html y manifest.json
# ------------------------------------------------------------------------------
Write-Host ""
Write-Host "Actualizando archivos web..." -ForegroundColor Cyan

$HtmlFile = Join-Path $ScriptDir "index.html"
$ManifestFile = Join-Path $ScriptDir "manifest.json"

if (Test-Path $HtmlFile) {
    $htmlContent = [System.IO.File]::ReadAllText($HtmlFile, $Utf8NoBom)
    $htmlContent = [regex]::Replace($htmlContent, '(<title id="page-title">)[^<]+(</title>)', "`${1}Instalador Web - $ProjectTitle`${2}")
    $htmlContent = [regex]::Replace($htmlContent, '(<h2 id="project-heading">)[^<]+(</h2>)', "`${1}Flasheo Web: $ProjectTitle`${2}")
    $htmlContent = [regex]::Replace($htmlContent, '(<span class="badge" id="version-badge">.*?v)[^<]+(</span>)', "`${1}$InitialVersion`${2}")
    [System.IO.File]::WriteAllText($HtmlFile, $htmlContent, $Utf8NoBom)
}

if (Test-Path $ManifestFile) {
    $manifestContent = [System.IO.File]::ReadAllText($ManifestFile, $Utf8NoBom)
    $manifestContent = [regex]::Replace($manifestContent, '("name":\s*")[^"]+(")', "`${1}$ProjectTitle (ESP32-S3)`${2}")
    $manifestContent = [regex]::Replace($manifestContent, '("version":\s*")[^"]+(")', "`${1}$InitialVersion`${2}")
    [System.IO.File]::WriteAllText($ManifestFile, $manifestContent, $Utf8NoBom)
}

# ------------------------------------------------------------------------------
# 4. Guardar archivo local de configuracion (.web_config)
# ------------------------------------------------------------------------------
$ConfigFile = Join-Path $ScriptDir ".web_config"
$FirmwareDirNormalized = $FirmwareDir -replace '\\', '/'
$configContent = @"
# Archivo de configuracion generado por init_web
PROJECT_NAME="$DefaultName"
PROJECT_TITLE="$ProjectTitle"
FIRMWARE_DIR="$FirmwareDirNormalized"
BRANCH_NAME="$TargetBranch"
INITIAL_VERSION="$InitialVersion"
"@
[System.IO.File]::WriteAllText($ConfigFile, $configContent, $Utf8NoBom)
Write-Host "[OK] Archivo .web_config generado." -ForegroundColor Green

# ------------------------------------------------------------------------------
# 5. Deteccion y copia de binarios iniciales si existen
# ------------------------------------------------------------------------------
$BuildDir = Join-Path $FirmwareDir "build"
if (Test-Path $BuildDir -PathType Container) {
    $binFound = ""
    $cand1 = Join-Path $BuildDir "merged-binary-esp32s3.bin"
    $cand2 = Join-Path $BuildDir "merged-binary.bin"
    if (Test-Path $cand1 -PathType Leaf) {
        $binFound = $cand1
    } elseif (Test-Path $cand2 -PathType Leaf) {
        $binFound = $cand2
    }

    if ($binFound) {
        Write-Host "Detectado binario ESP32-S3 compilado en: $binFound" -ForegroundColor Cyan
        if (Confirmar-1-0 "Deseas copiar a ./merged-binary-esp32s3.bin ahora?") {
            $destBin = Join-Path $ScriptDir "merged-binary-esp32s3.bin"
            Copy-Item -Path $binFound -Destination $destBin -Force
            Write-Host "[OK] Binario ESP32-S3 copiado." -ForegroundColor Green
        }
    }
}

# ------------------------------------------------------------------------------
# 6. Creacion y conmutacion a la nueva rama Git
# ------------------------------------------------------------------------------
Write-Host ""
Write-Host "Configurando rama Git '$TargetBranch'..." -ForegroundColor Cyan

$ErrorActionPreference = "Continue"
git show-ref --verify --quiet "refs/heads/$TargetBranch" 2>$null
$branchExists = ($LASTEXITCODE -eq 0)

if ($branchExists) {
    Write-Host "La rama local '$TargetBranch' ya existe. Conmutando a ella..." -ForegroundColor Yellow
    git checkout "$TargetBranch"
} else {
    Write-Host "Creando nueva rama local '$TargetBranch'..." -ForegroundColor Green
    git checkout -b "$TargetBranch"
}
$ErrorActionPreference = "Stop"

# ------------------------------------------------------------------------------
# 7. Opcion de auto-eliminacion limpia del script
# ------------------------------------------------------------------------------
Write-Host ""
if (Confirmar-1-0 "Deseas eliminar los scripts de inicializacion (init_web.ps1 / init_web.bat / init_web.sh) para dejar el repositorio limpio?") {
    foreach ($f in @("init_web.ps1", "init_web.bat", "init_web.sh")) {
        $p = Join-Path $ScriptDir $f
        if (Test-Path $p) {
            Remove-Item -Path $p -Force
        }
    }
    Write-Host "[OK] Scripts de inicializacion eliminados." -ForegroundColor Green
} else {
    Write-Host "Scripts de inicializacion conservados." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Inicializacion completada exitosamente!" -ForegroundColor Green
Write-Host "Estas en la rama: " -NoNewline; Write-Host "$TargetBranch" -ForegroundColor Cyan
Write-Host "Para publicar nuevos releases y actualizaciones en Windows, utiliza: " -NoNewline
Write-Host ".\release.ps1" -ForegroundColor White -NoNewline
Write-Host " (o " -NoNewline
Write-Host ".\release.bat" -ForegroundColor White -NoNewline
Write-Host ")"
Write-Host ""
