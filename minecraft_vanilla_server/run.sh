#!/usr/bin/env bash
set -euo pipefail

RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

echo "-----------------------------------------------------------"
echo " Minecraft Vanilla Dedicated Server (Home Assistant Add-on)"
echo "-----------------------------------------------------------"

# -----------------------------------------------------------
# Optionen
# -----------------------------------------------------------
DATA_DIR="$(jq -r '.data_dir' /data/options.json)"
XMS_MB="$(jq -r '.xms_mb' /data/options.json)"
XMX_MB="$(jq -r '.xmx_mb' /data/options.json)"

[[ "${DATA_DIR}" == "null" || -z "${DATA_DIR}" ]] && DATA_DIR="/share/minecraft-vanilla"

CONTAINER_PORT="25565"

mkdir -p "${DATA_DIR}"
cd "${DATA_DIR}"

LOG_DIR="${DATA_DIR}/logs"
LOG_FILE="${LOG_DIR}/ha_console.log"
mkdir -p "${LOG_DIR}"

# -----------------------------------------------------------
# Java 25 automatisch installieren (Temurin)
# -----------------------------------------------------------
JRE_DIR="${DATA_DIR}/.jre/25"
JAVA_HOME="${JRE_DIR}"
JAVA_BIN="${JAVA_HOME}/bin/java"

install_java() {
    if [[ -x "${JAVA_BIN}" ]]; then
        return 0
    fi

    log_info "Java 25 has not been found!"

    mkdir -p "${JRE_DIR}"
    TMP="/tmp/jre25.tar.gz"
    
    URL="https://api.adoptium.net/v3/binary/latest/25/ga/linux/x64/jre/hotspot/normal/eclipse"
    
    curl -fL --retry 3 --retry-delay 2 "${URL}" -o "${TMP}"
    rm -rf "${JRE_DIR:?}/"*
    tar -xzf "${TMP}" -C "${JRE_DIR}" --strip-components=1
    rm -f "${TMP}"

    [[ -x "${JAVA_BIN}" ]] || { log_error "Java Installation fehlgeschlagen"; exit 1; }
}

install_java
export JAVA_HOME
export PATH="${JAVA_HOME}/bin:${PATH}"

log_info "Java Version: $(java -version 2>&1 | head -n1)"

# -----------------------------------------------------------
# Server-JAR (Hardcoded to bypass broken API lookups)
# -----------------------------------------------------------
SERVER_JAR="server.jar"

# Directly utilizing the exact static Mojang link you provided
JAR_URL="https://piston-data.mojang.com/v1/objects/823e2250d24b3ddac457a60c92a6a941943fcd6a/server.jar"

URL_MARKER=".server_jar_url.txt"
if [[ ! -f "${SERVER_JAR}" || ! -f "${URL_MARKER}" || "$(cat "${URL_MARKER}")" != "${JAR_URL}" ]]; then
    log_info "Lade Server-JAR herunter"
    curl -fL --retry 3 --retry-delay 2 "${JAR_URL}" -o "${SERVER_JAR}"
    echo "${JAR_URL}" > "${URL_MARKER}"
fi

# -----------------------------------------------------------
# EULA IMMER akzeptieren
# -----------------------------------------------------------
cat > ./eula.txt <<'EOF'
#By changing the setting below to TRUE you are indicating your agreement to the Minecraft EULA (https://aka.ms).
eula=true
EOF
log_info "EULA has automatically been accepted!"

# -----------------------------------------------------------
# server.properties – Port fest setzen
# -----------------------------------------------------------
if [[ -f "./server.properties" ]]; then
    sed -i "s/^server-port=.*/server-port=${CONTAINER_PORT}/" ./server.properties || true
else
    echo "server-port=${CONTAINER_PORT}" > ./server.properties
fi

# -----------------------------------------------------------
# Start
# -----------------------------------------------------------
export JAVA_TOOL_OPTIONS="-Xms${XMS_MB}M -Xmx${XMX_MB}M"

log_info "Starte Minecraft Vanilla Server"
log_info "Port (Container): ${CONTAINER_PORT}"
log_info "RAM             : Xms=${XMS_MB}M / Xmx=${XMX_MB}M"
log_info "Datenverzeichnis: ${DATA_DIR}"
log_info "Logdatei        : ${LOG_FILE}"
echo "-----------------------------------------------------------"

{
  echo ""
  echo "==================== $(date -Iseconds) ===================="
  echo "Minecraft Vanilla | Port ${CONTAINER_PORT} | Xms/Xmx ${XMS_MB}/${XMX_MB} MB"
  echo "==========================================================="
} >> "${LOG_FILE}"

exec java -jar "${SERVER_JAR}" nogui 2>&1 | tee -a "${LOG_FILE}"
