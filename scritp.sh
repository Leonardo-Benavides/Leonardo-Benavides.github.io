#!/usr/bin/env bash
# ==============================================================================
# Script de Release y Versionado Automático para 9io7adc_web
# ==============================================================================
set -euo pipefail

# Colores para salida interactiva
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # Sin color

# Directorio del repositorio
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MANIFEST_FILE="$SCRIPT_DIR/manifest.json"
MANIFEST_S3="$SCRIPT_DIR/manifest-esp32s3.json"
MANIFEST_ESP32="$SCRIPT_DIR/manifest-esp32.json"
HTML_FILE="$SCRIPT_DIR/index.html"
BINARY_LOCAL="$SCRIPT_DIR/merged-binary.bin"
BINARY_SOURCE="$SCRIPT_DIR/../9io7adc/build/merged-binary.bin"

# Manejo de cancelación limpia con Ctrl+C
trap 'echo -e "\n${RED}Operación cancelada por el usuario.${NC}"; exit 130' INT

# ------------------------------------------------------------------------------
# Función auxiliar: Confirmación estricta 1 (Sí) o 0 (No/Volver)
# Retorna 0 si eligió 1, retorna 1 si eligió 0
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

# ------------------------------------------------------------------------------
# 1. Detección de versión actual
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
    CURRENT_VERSION="1.0"
fi

echo -e "\n${CYAN}${BOLD}=== GESTIÓN DE RELEASE Y VERSIONADO (9io7adc_web) ===${NC}"
echo -e "Versión actual detectada: ${YELLOW}${BOLD}$CURRENT_VERSION${NC}\n"

# ------------------------------------------------------------------------------
# 2. Cálculo o definición de la nueva versión
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
            read -r -p "$(echo -e "${BOLD}Introduce la nueva versión manualmente (ej. 1.6 o 2.0): ${NC}")" manual_ver
            manual_ver="$(echo "$manual_ver" | xargs)" # Trim
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
# 3. Selección interactiva de Conventional Commits
# ------------------------------------------------------------------------------
seleccionar_tipo_commit() {
    while true; do
        echo -e "${CYAN}${BOLD}Selecciona el tipo de cambio para el commit:${NC}"
        echo -e "  ${BOLD}1)${NC} ${GREEN}feat${NC}     - Nueva funcionalidad"
        echo -e "  ${BOLD}2)${NC} ${RED}fix${NC}      - Corrección de un error / bug"
        echo -e "  ${BOLD}3)${NC} ${BLUE}docs${NC}     - Documentación"
        echo -e "  ${BOLD}4)${NC} ${YELLOW}style${NC}    - Formato visual, CSS o indentación"
        echo -e "  ${BOLD}5)${NC} ${CYAN}refactor${NC} - Refactorización de código sin alterar lógica"
        echo -e "  ${BOLD}6)${NC} ${YELLOW}perf${NC}     - Mejora de rendimiento"
        echo -e "  ${BOLD}7)${NC} ${BLUE}test${NC}     - Pruebas / tests"
        echo -e "  ${BOLD}8)${NC} ${NC}chore${NC}    - Tareas de mantenimiento o scripts"
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
                echo -e "${RED}Opción no válida. Por favor introduce un número del 1 al 9.${NC}\n"
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
# 4. Descripción del commit y scope opcional
# ------------------------------------------------------------------------------
definir_mensaje_commit() {
    while true; do
        read -r -p "$(echo -e "${BOLD}Descripción breve del cambio: ${NC}")" desc_commit
        desc_commit="$(echo "$desc_commit" | xargs)"
        if [[ -z "$desc_commit" ]]; then
            echo -e "${RED}La descripción no puede estar vacía.${NC}"
            continue
        fi

        # Scope opcional
        local scope=""
        if confirmar_1_0 "¿Deseas agregar un alcance/scope? (ej. display, adc, web)"; then
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
# 5. Detección y copia opcional del binario compilado
# ------------------------------------------------------------------------------
gestionar_binario() {
    if [[ -f "$BINARY_SOURCE" ]]; then
        echo -e "${CYAN}Se detectó un binario compilado en:${NC} $BINARY_SOURCE"
        if confirmar_1_0 "¿Deseas copiar el nuevo binario a ./merged-binary.bin y ./merged-binary-esp32s3.bin?"; then
            cp -v "$BINARY_SOURCE" "$BINARY_LOCAL"
            cp -v "$BINARY_SOURCE" "$SCRIPT_DIR/merged-binary-esp32s3.bin"
            echo -e "${GREEN}Binarios actualizados exitosamente.${NC}\n"
        else
            echo -e "${YELLOW}Se conservarán los binarios existentes.${NC}\n"
        fi
    fi
}

gestionar_binario

# ------------------------------------------------------------------------------
# 6. Actualización atómica de manifests e index.html
# ------------------------------------------------------------------------------
echo -e "${CYAN}${BOLD}Actualizando archivos a la versión $NEW_VERSION...${NC}"

# 6.1 Actualizar manifest.json, manifest-esp32s3.json y manifest-esp32.json
for mf in "$MANIFEST_FILE" "$MANIFEST_S3" "$MANIFEST_ESP32"; do
    if [[ -f "$mf" ]]; then
        sed -i -E "s/(\"version\":[[:space:]]*\")[^\"]+(\")/\1$NEW_VERSION\2/" "$mf"
    fi
done

# 6.2 Actualizar index.html (en el badge)
sed -i -E "s/(<span class=\"badge\" id=\"version-badge\">.*• v)[^<]+(<\/span>)/\1$NEW_VERSION\2/" "$HTML_FILE"

# Verificar cambios aplicados
echo -e "${GREEN}Archivos actualizados:${NC}"
git --no-pager diff "$MANIFEST_FILE" "$MANIFEST_S3" "$MANIFEST_ESP32" "$HTML_FILE" || true
echo ""

# ------------------------------------------------------------------------------
# 7. Confirmación final antes de Git commit y tag
# ------------------------------------------------------------------------------
TAG_NAME="v$NEW_VERSION"

echo -e "${BOLD}Resumen de la operación:${NC}"
echo -e "  • Nueva versión: ${GREEN}$NEW_VERSION${NC}"
echo -e "  • Tag de Git:    ${GREEN}$TAG_NAME${NC}"
echo -e "  • Commit:        ${GREEN}$COMMIT_MSG${NC}"
echo ""

if ! confirmar_1_0 "¿Deseas aplicar estos cambios, hacer git add, commit y crear el tag?"; then
    echo -e "${YELLOW}Operación cancelada. Revirtiendo modificaciones...${NC}"
    git checkout "$MANIFEST_FILE" "$MANIFEST_S3" "$MANIFEST_ESP32" "$HTML_FILE" 2>/dev/null || true
    if git ls-files --error-unmatch "$BINARY_LOCAL" >/dev/null 2>&1; then
        git checkout "$BINARY_LOCAL" 2>/dev/null || true
    fi
    echo -e "${RED}Cambios descartados. El repositorio no fue alterado.${NC}"
    exit 0
fi

# Git Add
git add "$MANIFEST_FILE" "$MANIFEST_S3" "$MANIFEST_ESP32" "$HTML_FILE"
if git status --porcelain | grep -qE "merged-binary.*\.bin"; then
    git add "$SCRIPT_DIR"/merged-binary*.bin
fi
if git status --porcelain | grep -qE "(scritp|script)\.sh"; then
    git add "$SCRIPT_DIR/scritp.sh"
    if [[ -e "$SCRIPT_DIR/script.sh" || -L "$SCRIPT_DIR/script.sh" ]]; then
        git add "$SCRIPT_DIR/script.sh"
    fi
fi

# Git Commit
git commit -m "$COMMIT_MSG"
echo -e "${GREEN}✔ Commit creado.${NC}"

# Git Tag
git tag -a "$TAG_NAME" -m "$COMMIT_MSG"
echo -e "${GREEN}✔ Tag '$TAG_NAME' creado.${NC}\n"

# ------------------------------------------------------------------------------
# 8. Sincronización con el repositorio remoto
# ------------------------------------------------------------------------------
CURRENT_BRANCH=$(git branch --show-current || echo "master")
REMOTE=$(git remote | head -n 1 || echo "")

if [[ -n "$REMOTE" ]]; then
    echo -e "Remoto detectado: ${CYAN}${BOLD}$REMOTE${NC} (rama: ${BOLD}$CURRENT_BRANCH${NC})"
    if confirmar_1_0 "¿Deseas hacer push al remoto '$REMOTE' y subir el tag '$TAG_NAME'?"; then
        echo -e "${CYAN}Subiendo commits y tags al remoto...${NC}"
        git push "$REMOTE" "$CURRENT_BRANCH"
        git push "$REMOTE" "$TAG_NAME"
        echo -e "\n${GREEN}${BOLD}¡Release completado y publicado exitosamente! 🚀${NC}"
    else
        echo -e "${YELLOW}Push omitido. Los cambios y el tag han quedado guardados localmente.${NC}"
    fi
else
    echo -e "${YELLOW}No se detectó ningún remoto configurado. Release guardado únicamente en local.${NC}"
fi

exit 0
