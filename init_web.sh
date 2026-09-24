#!/usr/bin/env bash
# ==============================================================================
# Script de Inicialización y Vinculación de Proyectos (Web Flasher Template)
# ==============================================================================
set -euo pipefail

# Colores de salida
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

trap 'echo -e "\n${RED}Operación cancelada por el usuario.${NC}"; exit 130' INT

# ------------------------------------------------------------------------------
# Confirmación interactiva [1: Sí, 0: No]
# ------------------------------------------------------------------------------
confirmar_1_0() {
    local prompt_msg="$1"
    local respuesta=""
    while true; do
        read -r -p "$(echo -e "${BOLD}${prompt_msg}${NC} [1: Sí, 0: Volver/No]: ")" respuesta
        case "$respuesta" in
            1) return 0 ;;
            0) return 1 ;;
            *) echo -e "${RED}⚠️  Entrada inválida. Escribe 1 o 0 y pulsa Enter.${NC}" ;;
        esac
    done
}

echo -e "\n${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║      INICIALIZADOR DE WEB FLASHER (ESP32 / ESP32-S3)         ║${NC}"
echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}\n"

# ------------------------------------------------------------------------------
# 1. Escaneo y Selección del Proyecto de Firmware
# ------------------------------------------------------------------------------
PARENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CANDIDATOS=()

for d in "$PARENT_DIR"/*/; do
    [[ -d "$d" ]] || continue
    d_clean="${d%/}"
    d_name="$(basename "$d_clean")"
    # Omitir el directorio actual
    if [[ "$d_clean" == "$SCRIPT_DIR" ]]; then
        continue
    fi
    CANDIDATOS+=("$d_clean")
done

echo -e "${BOLD}Paso 1: Selecciona el proyecto de firmware a vincular:${NC}"
TOTAL_CANDIDATOS=${#CANDIDATOS[@]}

if [[ $TOTAL_CANDIDATOS -gt 0 ]]; then
    for i in "${!CANDIDATOS[@]}"; do
        proj_dir="${CANDIDATOS[$i]}"
        proj_base="$(basename "$proj_dir")"
        has_idf=""
        if [[ -f "$proj_dir/CMakeLists.txt" ]]; then
            has_idf="${GREEN}(ESP-IDF detectado)${NC}"
        fi
        echo -e "  ${BOLD}$((i + 1)))${NC} ${CYAN}${proj_base}${NC} $has_idf"
    done
    echo -e "  ${BOLD}$((TOTAL_CANDIDATOS + 1)))${NC} Introducir otra ruta manualmente..."
else
    echo -e "${YELLOW}No se detectaron proyectos hermanos en $PARENT_DIR${NC}"
fi

FIRMWARE_DIR=""
while true; do
    if [[ $TOTAL_CANDIDATOS -gt 0 ]]; then
        read -r -p "$(echo -e "\n${BOLD}Elige una opción [1-$((TOTAL_CANDIDATOS + 1))]: ${NC}")" sel_idx
        if [[ "$sel_idx" =~ ^[0-9]+$ ]] && (( sel_idx >= 1 && sel_idx <= TOTAL_CANDIDATOS )); then
            FIRMWARE_DIR="${CANDIDATOS[$((sel_idx - 1))]}"
            break
        elif [[ "$sel_idx" -eq $((TOTAL_CANDIDATOS + 1)) ]]; then
            # Entrada manual
            read -r -p "$(echo -e "${BOLD}Introduce la ruta absoluta o relativa al proyecto: ${NC}")" manual_path
            manual_path="$(cd "$manual_path" 2>/dev/null && pwd || echo "$manual_path")"
            if [[ -d "$manual_path" ]]; then
                FIRMWARE_DIR="$manual_path"
                break
            else
                echo -e "${RED}El directorio '$manual_path' no existe.${NC}"
            fi
        else
            echo -e "${RED}Opción no válida.${NC}"
        fi
    else
        read -r -p "$(echo -e "${BOLD}Introduce la ruta al proyecto de firmware: ${NC}")" manual_path
        manual_path="$(cd "$manual_path" 2>/dev/null && pwd || echo "$manual_path")"
        if [[ -d "$manual_path" ]]; then
            FIRMWARE_DIR="$manual_path"
            break
        else
            echo -e "${RED}El directorio '$manual_path' no existe.${NC}"
        fi
    fi
done

DEFAULT_NAME="$(basename "$FIRMWARE_DIR")"
echo -e "\nProyecto seleccionado: ${GREEN}${BOLD}$DEFAULT_NAME${NC} ($FIRMWARE_DIR)\n"

# ------------------------------------------------------------------------------
# 2. Configuración de Nombre, Versión y Rama Git
# ------------------------------------------------------------------------------
echo -e "${BOLD}Paso 2: Datos de personalización de la página:${NC}"

# Nombre visible
read -r -p "$(echo -e "Nombre a mostrar en la web [por defecto: ${YELLOW}$DEFAULT_NAME${NC}]: ")" input_title
PROJECT_TITLE="${input_title:-$DEFAULT_NAME}"

# Versión inicial
read -r -p "$(echo -e "Versión inicial [por defecto: ${YELLOW}0.1${NC}]: ")" input_ver
INITIAL_VERSION="${input_ver:-0.1}"

# Nombre de la rama
DEFAULT_BRANCH="${DEFAULT_NAME}_web"
read -r -p "$(echo -e "Nombre de la rama Git para esta web [por defecto: ${YELLOW}$DEFAULT_BRANCH${NC}]: ")" input_branch
TARGET_BRANCH="${input_branch:-$DEFAULT_BRANCH}"

echo -e "\n${BOLD}Resumen de configuración:${NC}"
echo -e "  • Proyecto:        ${GREEN}$DEFAULT_NAME${NC}"
echo -e "  • Título web:      ${GREEN}$PROJECT_TITLE${NC}"
echo -e "  • Versión base:    ${GREEN}v$INITIAL_VERSION${NC}"
echo -e "  • Directorio build:${CYAN}$FIRMWARE_DIR${NC}"
echo -e "  • Rama Git destino:${YELLOW}$TARGET_BRANCH${NC}\n"

if ! confirmar_1_0 "¿Deseas aplicar esta configuración?"; then
    echo -e "${YELLOW}Configuración cancelada. No se modificó ningún archivo.${NC}"
    exit 0
fi

# ------------------------------------------------------------------------------
# 3. Aplicar personalización en index.html y manifests
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}Actualizando archivos web...${NC}"

# index.html
sed -i -E "s/(<title id=\"page-title\">)[^<]+(<\/title>)/\1Instalador Web - $PROJECT_TITLE\2/" "$SCRIPT_DIR/index.html"
sed -i -E "s/(<h2 id=\"project-heading\">)[^<]+(<\/h2>)/\1Flasheo Web: $PROJECT_TITLE\2/" "$SCRIPT_DIR/index.html"
sed -i -E "s/(<span class=\"badge\" id=\"version-badge\">.*• v)[^<]+(<\/span>)/\1$INITIAL_VERSION\2/" "$SCRIPT_DIR/index.html"

# manifest.json
sed -i -E "s/(\"name\":[[:space:]]*\")[^\"]+(\")/\1$PROJECT_TITLE (Auto)\2/" "$SCRIPT_DIR/manifest.json"
sed -i -E "s/(\"version\":[[:space:]]*\")[^\"]+(\")/\1$INITIAL_VERSION\2/" "$SCRIPT_DIR/manifest.json"

# manifest-esp32s3.json
if [[ -f "$SCRIPT_DIR/manifest-esp32s3.json" ]]; then
    sed -i -E "s/(\"name\":[[:space:]]*\")[^\"]+(\")/\1$PROJECT_TITLE (ESP32-S3)\2/" "$SCRIPT_DIR/manifest-esp32s3.json"
    sed -i -E "s/(\"version\":[[:space:]]*\")[^\"]+(\")/\1$INITIAL_VERSION\2/" "$SCRIPT_DIR/manifest-esp32s3.json"
fi

# manifest-esp32.json
if [[ -f "$SCRIPT_DIR/manifest-esp32.json" ]]; then
    sed -i -E "s/(\"name\":[[:space:]]*\")[^\"]+(\")/\1$PROJECT_TITLE (ESP32)\2/" "$SCRIPT_DIR/manifest-esp32.json"
    sed -i -E "s/(\"version\":[[:space:]]*\")[^\"]+(\")/\1$INITIAL_VERSION\2/" "$SCRIPT_DIR/manifest-esp32.json"
fi

# ------------------------------------------------------------------------------
# 4. Guardar archivo local de configuración
# ------------------------------------------------------------------------------
CONFIG_FILE="$SCRIPT_DIR/.web_config"
cat > "$CONFIG_FILE" <<EOF
# Archivo de configuración generado por init_web.sh
PROJECT_NAME="$DEFAULT_NAME"
PROJECT_TITLE="$PROJECT_TITLE"
FIRMWARE_DIR="$FIRMWARE_DIR"
BRANCH_NAME="$TARGET_BRANCH"
INITIAL_VERSION="$INITIAL_VERSION"
EOF
echo -e "${GREEN}✔ Archivo .web_config generado.${NC}"

# ------------------------------------------------------------------------------
# 5. Detección y copia de binarios iniciales si existen
# ------------------------------------------------------------------------------
BUILD_DIR="$FIRMWARE_DIR/build"
if [[ -d "$BUILD_DIR" ]]; then
    if [[ -f "$BUILD_DIR/merged-binary.bin" ]]; then
        echo -e "${CYAN}Detectado binario ESP32-S3 compilado en:${NC} $BUILD_DIR/merged-binary.bin"
        if confirmar_1_0 "¿Deseas copiar a ./merged-binary-esp32s3.bin ahora?"; then
            cp -v "$BUILD_DIR/merged-binary.bin" "$SCRIPT_DIR/merged-binary-esp32s3.bin"
            echo -e "${GREEN}✔ Binario ESP32-S3 copiado.${NC}"
        fi
    fi
    if [[ -f "$BUILD_DIR/merged-binary-esp32.bin" ]]; then
        echo -e "${CYAN}Detectado binario ESP32 compilado en:${NC} $BUILD_DIR/merged-binary-esp32.bin"
        if confirmar_1_0 "¿Deseas copiar a ./merged-binary-esp32.bin ahora?"; then
            cp -v "$BUILD_DIR/merged-binary-esp32.bin" "$SCRIPT_DIR/merged-binary-esp32.bin"
            echo -e "${GREEN}✔ Binario ESP32 copiado.${NC}"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 6. Creación y conmutación a la nueva rama Git
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}Configurando rama Git '$TARGET_BRANCH'...${NC}"
CURRENT_BRANCH="$(git branch --show-current || echo "master")"

if git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
    echo -e "${YELLOW}La rama local '$TARGET_BRANCH' ya existe. Conmutando a ella...${NC}"
    git checkout "$TARGET_BRANCH"
else
    echo -e "${GREEN}Creando nueva rama local '$TARGET_BRANCH'...${NC}"
    git checkout -b "$TARGET_BRANCH"
fi

# ------------------------------------------------------------------------------
# 7. Opción de auto-eliminación limpia del script
# ------------------------------------------------------------------------------
echo ""
if confirmar_1_0 "¿Deseas eliminar este script 'init_web.sh' para dejar el repositorio limpio?"; then
    rm -- "$0"
    echo -e "${GREEN}✔ init_web.sh eliminado.${NC}"
else
    echo -e "${YELLOW}init_web.sh conservado.${NC}"
fi

echo -e "\n${GREEN}${BOLD}¡Inicialización completada exitosamente! 🎉${NC}"
echo -e "Estás en la rama: ${BOLD}${CYAN}$TARGET_BRANCH${NC}"
echo -e "Para publicar nuevos releases y actualizaciones, utiliza: ${BOLD}./release.sh${NC}\n"
