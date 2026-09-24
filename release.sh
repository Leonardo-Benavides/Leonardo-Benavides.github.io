#!/usr/bin/env bash
# ==============================================================================
# Script de Release y Versionado Automático Estandarizado (Web Flasher)
# ==============================================================================
set -euo pipefail

# Colores para salida interactiva
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG_FILE="$SCRIPT_DIR/.web_config"
MANIFEST_FILE="$SCRIPT_DIR/manifest.json"
HTML_FILE="$SCRIPT_DIR/index.html"

trap 'echo -e "\n${RED}Operación cancelada por el usuario.${NC}"; exit 130' INT

# ------------------------------------------------------------------------------
# Función auxiliar: Confirmación estricta 1 (Sí) o 0 (No/Volver)
# ------------------------------------------------------------------------------
confirmar_1_0() {
    local prompt_msg="$1"
    local respuesta=""
    while true; do
        read -r -p "$(echo -e "${BOLD}${prompt_msg}${NC} [1: Sí, 0: Volver/No]: ")" respuesta
        case "$respuesta" in
            1) return 0 ;;
            0) return 1 ;;
            *) echo -e "${RED}⚠️  Entrada inválida. Debes escribir 1 o 0 y presionar Enter.${NC}" ;;
        esac
    done
}

echo -e "\n${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║           GESTIÓN DE RELEASE Y VERSIONADO (RELEASE.SH)        ║${NC}"
echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}\n"

# ------------------------------------------------------------------------------
# 1. Carga de configuración o resolución de ruta de firmware
# ------------------------------------------------------------------------------
FIRMWARE_DIR=""
TARGET_BRANCH=""

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    echo -e "Configuración cargada desde ${CYAN}.web_config${NC}:"
    echo -e "  • Proyecto:     ${GREEN}${PROJECT_NAME:-Desconocido}${NC}"
    echo -e "  • Directorio:   ${CYAN}${FIRMWARE_DIR:-}${NC}"
    echo -e "  • Rama destino: ${YELLOW}${BRANCH_NAME:-}${NC}\n"
fi

if [[ -z "$FIRMWARE_DIR" || ! -d "$FIRMWARE_DIR" ]]; then
    PARENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    CANDIDATOS=()
    for c in "$PARENT_DIR"/*/; do
        [[ -d "$c" ]] || continue
        c_clean="${c%/}"
        if [[ "$c_clean" != "$SCRIPT_DIR" && -f "$c_clean/CMakeLists.txt" ]]; then
            CANDIDATOS+=("$c_clean")
        fi
    done

    if [[ ${#CANDIDATOS[@]} -eq 1 ]]; then
        FIRMWARE_DIR="${CANDIDATOS[0]}"
        echo -e "Proyecto detectado automáticamente: ${GREEN}${FIRMWARE_DIR}${NC}\n"
    elif [[ ${#CANDIDATOS[@]} -gt 1 ]]; then
        echo -e "${BOLD}Selecciona el proyecto de firmware a vincular:${NC}"
        for i in "${!CANDIDATOS[@]}"; do
            echo -e "  $((i + 1))) ${CYAN}$(basename "${CANDIDATOS[$i]}")${NC} (${CANDIDATOS[$i]})"
        done
        echo -e "  $(( ${#CANDIDATOS[@]} + 1 ))) Introducir ruta manualmente..."
        while true; do
            read -r -p "$(echo -e "${BOLD}Elige una opción [1-$(( ${#CANDIDATOS[@]} + 1 ))]: ${NC}")" sel_idx
            if [[ "$sel_idx" =~ ^[0-9]+$ ]] && (( sel_idx >= 1 && sel_idx <= ${#CANDIDATOS[@]} )); then
                FIRMWARE_DIR="${CANDIDATOS[$((sel_idx - 1))]}"
                break
            elif [[ "$sel_idx" -eq $(( ${#CANDIDATOS[@]} + 1 )) ]]; then
                read -r -p "$(echo -e "${BOLD}Introduce la ruta al proyecto: ${NC}")" manual_path
                manual_path="$(cd "$manual_path" 2>/dev/null && pwd || echo "$manual_path")"
                if [[ -d "$manual_path" ]]; then
                    FIRMWARE_DIR="$manual_path"
                    break
                else
                    echo -e "${RED}El directorio '$manual_path' no existe.${NC}"
                fi
            else
                echo -e "${RED}Opción inválida.${NC}"
            fi
        done
    else
        read -r -p "$(echo -e "${BOLD}Introduce la ruta al proyecto de firmware: ${NC}")" manual_path
        manual_path="$(cd "$manual_path" 2>/dev/null && pwd || echo "$manual_path")"
        if [[ -d "$manual_path" ]]; then
            FIRMWARE_DIR="$manual_path"
        fi
    fi

    # Guardar en .web_config para futuras ejecuciones
    if [[ -n "$FIRMWARE_DIR" && -d "$FIRMWARE_DIR" && ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" <<EOF
# Archivo local de configuración generado automáticamente
PROJECT_NAME="$(basename "$FIRMWARE_DIR")"
FIRMWARE_DIR="$FIRMWARE_DIR"
BRANCH_NAME="$(git branch --show-current || echo "master")"
EOF
        echo -e "${GREEN}✔ Configuración guardada en .web_config${NC}\n"
    fi
fi

# ------------------------------------------------------------------------------
# 2. Detección de versión actual
# ------------------------------------------------------------------------------
if [[ ! -f "$MANIFEST_FILE" ]]; then
    echo -e "${RED}Error: No se encontró el archivo manifest.json en $MANIFEST_FILE${NC}"
    exit 1
fi

if [[ ! -f "$HTML_FILE" ]]; then
    echo -e "${RED}Error: No se encontró el archivo index.html en $HTML_FILE${NC}"
    exit 1
fi

CURRENT_VERSION=$(grep -oP '"version":\s*"\K[^"]+' "$MANIFEST_FILE" || true)

if [[ -z "$CURRENT_VERSION" ]]; then
    echo -e "${YELLOW}No se pudo extraer la versión actual de manifest.json.${NC}"
    CURRENT_VERSION="0.1"
fi

echo -e "Versión actual detectada: ${YELLOW}${BOLD}$CURRENT_VERSION${NC}\n"

# ------------------------------------------------------------------------------
# 3. Cálculo o definición de la nueva versión
# ------------------------------------------------------------------------------
seleccionar_version() {
    local sugerida=""
    if [[ "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
        local major="${BASH_REMATCH[1]}"
        local minor="${BASH_REMATCH[2]}"
        local next_minor=$((minor + 1))
        sugerida="${major}.${next_minor}"
    elif [[ "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        local major="${BASH_REMATCH[1]}"
        local minor="${BASH_REMATCH[2]}"
        local patch="${BASH_REMATCH[3]}"
        local next_patch=$((patch + 1))
        sugerida="${major}.${minor}.${next_patch}"
    else
        sugerida=""
    fi

    while true; do
        if [[ -n "$sugerida" ]]; then
            echo -e "Nueva versión calculada automáticamente: ${GREEN}${BOLD}$sugerida${NC}"
            if confirmar_1_0 "¿Deseas usar la versión sugerida ($sugerida)?"; then
                NEW_VERSION="$sugerida"
                break
            fi
        fi

        # Entrada manual
        while true; do
            read -r -p "$(echo -e "${BOLD}Introduce la nueva versión manualmente (ej. 0.2 o 1.0): ${NC}")" manual_ver
            manual_ver="$(echo "$manual_ver" | xargs)"
            if [[ -z "$manual_ver" ]]; then
                echo -e "${RED}La versión no puede estar vacía.${NC}"
                continue
            fi
            if confirmar_1_0 "¿Confirmas que la nueva versión sea '${manual_ver}'?"; then
                NEW_VERSION="$manual_ver"
                return 0
            fi
        done
    done
}

seleccionar_version
echo -e "Versión acordada: ${GREEN}${BOLD}$NEW_VERSION${NC}\n"

# ------------------------------------------------------------------------------
# 4. Selección interactiva de Conventional Commits
# ------------------------------------------------------------------------------
seleccionar_tipo_commit() {
    while true; do
        echo -e "${CYAN}${BOLD}Selecciona el tipo de cambio para el commit:${NC}"
        echo -e "  ${BOLD}1)${NC} ${GREEN}feat${NC}     - Nueva funcionalidad"
        echo -e "  ${BOLD}2)${NC} ${RED}fix${NC}      - Corrección de un error / bug"
        echo -e "  ${BOLD}3)${NC} ${BLUE}docs${NC}     - Documentación"
        echo -e "  ${BOLD}4)${NC} ${YELLOW}style${NC}    - Formato visual, CSS o UI"
        echo -e "  ${BOLD}5)${NC} ${CYAN}refactor${NC} - Refactorización de código"
        echo -e "  ${BOLD}6)${NC} ${YELLOW}perf${NC}     - Mejora de rendimiento"
        echo -e "  ${BOLD}7)${NC} ${BLUE}test${NC}     - Pruebas / tests"
        echo -e "  ${BOLD}8)${NC} ${NC}chore${NC}    - Mantenimiento, dependencias o scripts"
        echo -e "  ${BOLD}9)${NC} Personalizado (escribir otro prefijo)"

        read -r -p "$(echo -e "${BOLD}Opción [1-9]: ${NC}")" opt_tipo

        local tipo_elegido=""
        case "$opt_tipo" in
            1) tipo_elegido="feat" ;;
            2) tipo_elegido="fix" ;;
            3) tipo_elegido="docs" ;;
            4) tipo_elegido="style" ;;
            5) tipo_elegido="refactor" ;;
            6) tipo_elegido="perf" ;;
            7) tipo_elegido="test" ;;
            8) tipo_elegido="chore" ;;
            9)
                read -r -p "$(echo -e "${BOLD}Escribe el prefijo personalizado: ${NC}")" tipo_elegido
                tipo_elegido="$(echo "$tipo_elegido" | xargs)"
                ;;
            *)
                echo -e "${RED}Opción no válida.${NC}\n"
                continue
                ;;
        esac

        if [[ -z "$tipo_elegido" ]]; then
            echo -e "${RED}El tipo no puede estar vacío.${NC}\n"
            continue
        fi

        echo -e "Has seleccionado el tipo: ${GREEN}${BOLD}${tipo_elegido}${NC}"
        if confirmar_1_0 "¿Confirmas el tipo de cambio '${tipo_elegido}'?"; then
            COMMIT_TYPE="$tipo_elegido"
            break
        else
            echo -e "${YELLOW}Regresando al menú de selección...${NC}\n"
        fi
    done
}

seleccionar_tipo_commit
echo ""

# ------------------------------------------------------------------------------
# 5. Descripción del commit y scope opcional
# ------------------------------------------------------------------------------
definir_mensaje_commit() {
    while true; do
        read -r -p "$(echo -e "${BOLD}Descripción breve del cambio: ${NC}")" desc_commit
        desc_commit="$(echo "$desc_commit" | xargs)"
        if [[ -z "$desc_commit" ]]; then
            echo -e "${RED}La descripción no puede estar vacía.${NC}"
            continue
        fi

        local scope=""
        if confirmar_1_0 "¿Deseas agregar un alcance/scope? (ej. web, ui, esp32s3)"; then
            read -r -p "$(echo -e "${BOLD}Nombre del alcance/scope: ${NC}")" scope
            scope="$(echo "$scope" | xargs)"
        fi

        local full_msg=""
        if [[ -n "$scope" ]]; then
            full_msg="${COMMIT_TYPE}(${scope}): ${desc_commit}"
        else
            full_msg="${COMMIT_TYPE}: ${desc_commit}"
        fi

        echo -e "\nMensaje resultante:"
        echo -e "  ${BOLD}${GREEN}${full_msg}${NC}"

        if confirmar_1_0 "¿Confirmas este mensaje de commit?"; then
            COMMIT_MSG="$full_msg"
            break
        else
            echo -e "${YELLOW}Reescribiendo la descripción...${NC}\n"
        fi
    done
}

definir_mensaje_commit
echo ""

# ------------------------------------------------------------------------------
# 6. Detección, generación y copia de binarios compilados
# ------------------------------------------------------------------------------
gestionar_binarios() {
    if [[ -z "$FIRMWARE_DIR" || ! -d "$FIRMWARE_DIR" ]]; then
        echo -e "${YELLOW}⚠️  No se ha especificado un directorio de firmware válido. Se omite la copia de binarios.${NC}\n"
        return 0
    fi

    local build_dir="$FIRMWARE_DIR/build"
    local bin_source=""
    local chip="esp32s3"

    # Detectar chip desde flasher_args.json si está disponible
    if [[ -f "$build_dir/flasher_args.json" ]]; then
        local detected_chip
        detected_chip=$(grep -oP '"chip"\s*:\s*"\K[^"]+' "$build_dir/flasher_args.json" 2>/dev/null || echo "")
        [[ -n "$detected_chip" ]] && chip="$detected_chip"
    fi

    # 1. Comprobar si merged-binary-esp32s3.bin o merged-binary.bin ya existe en el build
    if [[ -f "$build_dir/merged-binary-esp32s3.bin" ]]; then
        bin_source="$build_dir/merged-binary-esp32s3.bin"
    elif [[ -f "$build_dir/merged-binary.bin" ]]; then
        bin_source="$build_dir/merged-binary.bin"
    fi

    # 2. Si no existe, verificar si el proyecto está compilado y ofrecer generarlo con idf.py merge-bin
    if [[ -z "$bin_source" ]]; then
        if [[ -f "$build_dir/flasher_args.json" || -d "$build_dir/bootloader" ]]; then
            echo -e "${YELLOW}⚠️  Se detectó compilación en $build_dir pero falta el archivo 'merged-binary.bin' unificado.${NC}"
            if confirmar_1_0 "¿Deseas generarlo automáticamente ahora ejecutando 'idf.py merge-bin'?"; then
                echo -e "${CYAN}Ejecutando 'idf.py merge-bin' en $FIRMWARE_DIR...${NC}"
                (cd "$FIRMWARE_DIR" && idf.py merge-bin) || true
                if [[ -f "$build_dir/merged-binary.bin" ]]; then
                    bin_source="$build_dir/merged-binary.bin"
                    echo -e "${GREEN}✔ merged-binary.bin generado con éxito.${NC}\n"
                else
                    echo -e "${RED}No se pudo generar merged-binary.bin automáticamente.${NC}\n"
                fi
            fi
        fi
    fi

    # 3. Si aún no se encuentra, permitir indicar la ruta manual o avisar
    if [[ -z "$bin_source" ]]; then
        echo -e "${YELLOW}⚠️  No se encontró ningún binario en:${NC} $build_dir"
        if confirmar_1_0 "¿Deseas introducir manualmente la ruta a un archivo .bin compilado?"; then
            read -r -p "$(echo -e "${BOLD}Ruta completa al archivo .bin: ${NC}")" manual_bin
            if [[ -f "$manual_bin" ]]; then
                bin_source="$manual_bin"
            else
                echo -e "${RED}El archivo '$manual_bin' no existe.${NC}"
            fi
        fi
    fi

    # 4. Proceder a copiar si se tiene el binario origen
    if [[ -n "$bin_source" && -f "$bin_source" ]]; then
        echo -e "\n${CYAN}Binario compilado detectado (${chip}):${NC} $bin_source"
        local target_chip_bin="$SCRIPT_DIR/merged-binary-esp32s3.bin"

        if confirmar_1_0 "¿Deseas copiar este binario a ./merged-binary-esp32s3.bin?"; then
            cp -v "$bin_source" "$target_chip_bin"
            echo -e "${GREEN}✔ Binario ESP32-S3 actualizado exitosamente.${NC}\n"
            ls -lh "$target_chip_bin"
            echo ""
        else
            echo -e "${YELLOW}Se conservará el binario existente.${NC}\n"
        fi
    else
        echo -e "${YELLOW}⚠️  Se omitió la actualización de binarios (no se encontraron archivos nuevos).${NC}\n"
    fi
}

gestionar_binarios

# ------------------------------------------------------------------------------
# 7. Actualización atómica de manifests e index.html
# ------------------------------------------------------------------------------
echo -e "${CYAN}${BOLD}Actualizando archivos a la versión $NEW_VERSION...${NC}"

# Actualizar manifest
sed -i -E "s/(\"version\":[[:space:]]*\")[^\"]+(\")/\1$NEW_VERSION\2/" "$MANIFEST_FILE"

# Actualizar index.html (badge)
sed -i -E "s/(<span class=\"badge\" id=\"version-badge\">.*• v)[^<]+(<\/span>)/\1$NEW_VERSION\2/" "$HTML_FILE"

echo -e "${GREEN}Archivos actualizados:${NC}"
git --no-pager diff "$MANIFEST_FILE" "$HTML_FILE" 2>/dev/null || true
echo ""

# ------------------------------------------------------------------------------
# 8. Confirmación final antes de Git commit y tag
# ------------------------------------------------------------------------------
TAG_NAME="v$NEW_VERSION"

echo -e "${BOLD}Resumen de la operación:${NC}"
echo -e "  • Nueva versión: ${GREEN}$NEW_VERSION${NC}"
echo -e "  • Tag de Git:    ${GREEN}$TAG_NAME${NC}"
echo -e "  • Commit:        ${GREEN}$COMMIT_MSG${NC}"
echo ""

if ! confirmar_1_0 "¿Deseas aplicar estos cambios, hacer git add, commit y crear el tag?"; then
    echo -e "${YELLOW}Operación cancelada. Revirtiendo modificaciones...${NC}"
    git checkout "$MANIFEST_FILE" "$HTML_FILE" "$SCRIPT_DIR/merged-binary-esp32s3.bin" 2>/dev/null || true
    echo -e "${RED}Cambios descartados. El repositorio no fue alterado.${NC}"
    exit 0
fi

# Git Add
git add "$MANIFEST_FILE" "$HTML_FILE"
[[ -f "$SCRIPT_DIR/merged-binary-esp32s3.bin" ]] && git add "$SCRIPT_DIR/merged-binary-esp32s3.bin"
git add "$SCRIPT_DIR/release.sh"
[[ -f "$SCRIPT_DIR/init_web.sh" ]] && git add "$SCRIPT_DIR/init_web.sh"
[[ -e "$SCRIPT_DIR/script.sh" || -L "$SCRIPT_DIR/script.sh" ]] && git add "$SCRIPT_DIR/script.sh"

# Git Commit
git commit -m "$COMMIT_MSG"
echo -e "${GREEN}✔ Commit creado.${NC}"

# Git Tag
git tag -a "$TAG_NAME" -m "$COMMIT_MSG"
echo -e "${GREEN}✔ Tag '$TAG_NAME' creado.${NC}\n"

# ------------------------------------------------------------------------------
# 9. Sincronización con el repositorio remoto
# ------------------------------------------------------------------------------
CURRENT_BRANCH=$(git branch --show-current || echo "master")
REMOTE=$(git remote | head -n 1 || echo "")

if [[ -n "$REMOTE" ]]; then
    echo -e "Remoto detectado: ${CYAN}${BOLD}$REMOTE${NC} (rama activa: ${BOLD}$CURRENT_BRANCH${NC})"
    if confirmar_1_0 "¿Deseas hacer push al remoto '$REMOTE' en la rama '$CURRENT_BRANCH'?"; then
        echo -e "${CYAN}Subiendo commits y tags al remoto...${NC}"
        git push "$REMOTE" "$CURRENT_BRANCH"
        git push "$REMOTE" "$TAG_NAME"
        echo -e "\n${GREEN}${BOLD}¡Release completado y publicado exitosamente! 🚀${NC}"
    else
        echo -e "${YELLOW}Push omitido. Los cambios y el tag han quedado guardados localmente.${NC}"
    fi
else
    echo -e "${YELLOW}No se detectó ningún remoto configurado. Release guardado localmente.${NC}"
fi

exit 0
