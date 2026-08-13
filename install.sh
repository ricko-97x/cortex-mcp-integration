#!/usr/bin/env bash
# =============================================================================
# install.sh — Installation du serveur MCP Cortex (Docker ou Podman)
#
# Usage:
#   sudo ./install.sh <chemin/package-cortex-mcp> [install|start|stop|status|logs|update|test|uninstall]
#
# Exemples:
#   sudo ./install.sh /tmp/cortex-mcp install
#   sudo ./install.sh install            # si le package est déjà dans /opt/cortex-mcp
#   sudo ./install.sh status
#
# Prérequis:
#   - Docker OU Podman installé
#   - Package "Cortex MCP Server" extrait (téléchargé depuis la console XSIAM:
#     Settings → Configurations → Integrations → Cortex MCP Server)
#   - Un fichier .env renseigné (créé depuis .env.example si absent)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/cortex-mcp"
IMAGE_NAME="cortex-mcp"
CONTAINER_NAME="cortex-mcp"
HOST_PORT="${CORTEX_MCP_HOST_PORT:-8080}"
CONTAINER_PORT=8080
DEPLOY_ENV_EXAMPLE="${SCRIPT_DIR}/deploy/.env.example"

# ---------------------------------------------------------------------------
# Détection du moteur de conteneur (Docker en priorité, sinon Podman)
# ---------------------------------------------------------------------------
detect_engine() {
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        ENGINE="docker"
    elif command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
        ENGINE="podman"
    else
        echo "❌ Aucun moteur de conteneur détecté (docker ou podman)."
        echo "   Installez Docker:   sudo apt install docker.io docker-compose-v2"
        echo "   Installez Podman:   sudo apt install podman podman-compose"
        exit 1
    fi
    echo "✅ Moteur de conteneur détecté: ${ENGINE^^}"
}

# ---------------------------------------------------------------------------
# Vérification des droits root
# ---------------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "❌ Ce script doit être exécuté en root (utilisez sudo)."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Copie du package officiel vers $INSTALL_DIR
# ---------------------------------------------------------------------------
install_package() {
    local src="${1:-}"

    if [[ -z "$src" ]]; then
        if [[ -f "${INSTALL_DIR}/Dockerfile" && -d "${INSTALL_DIR}/src" ]]; then
            echo "✅ Package déjà présent dans ${INSTALL_DIR}"
            return 0
        fi
        echo "❌ Aucun chemin de package fourni et ${INSTALL_DIR} est vide."
        echo "   Usage: $0 <chemin/package-cortex-mcp> install"
        exit 1
    fi

    src="$(realpath "$src")"
    if [[ ! -f "${src}/Dockerfile" || ! -d "${src}/src" ]]; then
        echo "❌ Le dossier '${src}' ne ressemble pas à un package Cortex MCP"
        echo "   (Dockerfile ou src/ manquant). Vérifiez le contenu extrait du zip."
        exit 1
    fi

    mkdir -p "$INSTALL_DIR"
    echo "📦 Copie du package vers ${INSTALL_DIR} ..."
    cp -a "${src}/." "$INSTALL_DIR/"
    chown -R root:root "$INSTALL_DIR"
    echo "✅ Package copié."
}

# ---------------------------------------------------------------------------
# Création du fichier .env depuis l'exemple
# ---------------------------------------------------------------------------
setup_env() {
    if [[ -f "${INSTALL_DIR}/.env" ]]; then
        echo "✅ .env déjà présent (${INSTALL_DIR}/.env)"
        return 0
    fi

    local example="${INSTALL_DIR}/.env.example"
    if [[ ! -f "$example" && -f "$DEPLOY_ENV_EXAMPLE" ]]; then
        example="$DEPLOY_ENV_EXAMPLE"
    fi
    if [[ ! -f "$example" ]]; then
        echo "❌ Aucun .env.example trouvé. Créez ${INSTALL_DIR}/.env manuellement."
        exit 1
    fi

    cp "$example" "${INSTALL_DIR}/.env"
    echo "⚠️  Fichier ${INSTALL_DIR}/.env créé depuis l'exemple —"
    echo "    ÉDITEZ-LE avec vos vraies valeurs (URL tenant, clé API, ID) avant de démarrer."
    echo "    nano ${INSTALL_DIR}/.env"
}

# ---------------------------------------------------------------------------
# Validation du .env (placeholders encore présents ?)
# ---------------------------------------------------------------------------
validate_env() {
    local env_file="${INSTALL_DIR}/.env"
    [[ -f "$env_file" ]] || return 0
    if grep -Eq '<(votre-tenant|VOTRE_CLE_API|VOTRE_ID_DE_CLE)>' "$env_file" 2>/dev/null; then
        echo "❌ Le fichier ${env_file} contient encore des placeholders."
        echo "   Éditez-le avec vos vraies valeurs avant de démarrer:"
        echo "   nano ${env_file}"
        exit 1
    fi
    echo "✅ .env validé."
}

# ---------------------------------------------------------------------------
# Construction de l'image
# ---------------------------------------------------------------------------
build_image() {
    echo "🔨 Construction de l'image ${IMAGE_NAME} (${ENGINE})..."
    if [[ "$ENGINE" == "docker" ]]; then
        docker build -t "${IMAGE_NAME}" "$INSTALL_DIR"
    else
        podman build -t "${IMAGE_NAME}" "$INSTALL_DIR"
    fi
    echo "✅ Image construite."
}

# ---------------------------------------------------------------------------
# Vérification que le port hôte est libre
# ---------------------------------------------------------------------------
check_port_free() {
    if ss -tlnp 2>/dev/null | grep -qE "[:.]${HOST_PORT} "; then
        echo "❌ Le port ${HOST_PORT} est déjà utilisé par un autre processus/conteneur :" >&2
        ss -tlnp 2>/dev/null | grep -E "[:.]${HOST_PORT} " | sed 's/^/   /' >&2
        echo "" >&2
        echo "   Pour libérer le port :" >&2
        echo "     docker ps -a --format '{{.Names}} {{.Ports}}' | grep 8080   # trouver le conteneur" >&2
        echo "     docker rm -f <NOM_CONTENEUR>                                # le supprimer" >&2
        echo "     ss -tlnp | grep 8080                                        # vérifier que le port est libre" >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Démarrage du conteneur
# ---------------------------------------------------------------------------
start_container() {
    check_port_free
    if [[ "$ENGINE" == "docker" ]]; then
        docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
        docker run -d \
            --name "${CONTAINER_NAME}" \
            --restart unless-stopped \
            -p "${HOST_PORT}:${CONTAINER_PORT}" \
            --env-file "${INSTALL_DIR}/.env" \
            "${IMAGE_NAME}"
    else
        podman rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
        podman run -d \
            --name "${CONTAINER_NAME}" \
            --restart unless-stopped \
            -p "${HOST_PORT}:${CONTAINER_PORT}" \
            --env-file "${INSTALL_DIR}/.env" \
            "${IMAGE_NAME}"
    fi
    echo "✅ Conteneur ${CONTAINER_NAME} démarré sur le port ${HOST_PORT}."
    if [[ "$ENGINE" == "podman" ]]; then
        echo "⚠️  Podman : la politique '--restart unless-stopped' ne s'applique qu'avec le"
        echo "    service systemd du conteneur. Pour un redémarrage automatique au boot,"
        echo "    générez une unit systemd: podman generate systemd --new --name ${CONTAINER_NAME}"
    fi
}

# ---------------------------------------------------------------------------
# Test de santé (handshake MCP initialize)
# ---------------------------------------------------------------------------
health_check() {
    echo "🔍 Test de santé (POST /api/v1/stream/mcp initialize)..."
    local url="http://localhost:${HOST_PORT}/api/v1/stream/mcp"
    local payload='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"install-script","version":"1.0"}}}'
    local out
    out=$(curl -s -m 10 -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json, text/event-stream" \
        -d "$payload" || true)

    if echo "$out" | grep -q '"serverInfo"'; then
        echo "✅ Serveur MCP opérationnel sur ${url}"
    else
        echo "⚠️  Le serveur a répondu mais la réponse ne contient pas de serverInfo."
        echo "   Vérifiez les logs: $0 logs"
        echo "   Réponse: $(echo "$out" | head -c 300)"
    fi
}

# ---------------------------------------------------------------------------
# Test complet : handshake + liste des outils
# ---------------------------------------------------------------------------
test_tools() {
    echo "🔍 Test complet (initialize + tools/list)..."
    local url="http://localhost:${HOST_PORT}/api/v1/stream/mcp"
    local payload='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"install-script","version":"1.0"}}}'
    local session
    session=$(curl -s -i -m 10 -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json, text/event-stream" \
        -d "$payload" 2>/dev/null | grep -i '^mcp-session-id:' | tr -d '\r' | awk '{print $2}')
    if [[ -z "$session" ]]; then
        echo "⚠️  Pas de Mcp-Session-Id reçu — serveur injoignable ou réponse inattendue."
        return 1
    fi
    echo "✅ Session MCP obtenue: ${session}"
    curl -s -m 15 -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json, text/event-stream" \
        -H "Mcp-Session-Id: ${session}" \
        -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//' | sort | sed 's/^/   - /'
}

# ---------------------------------------------------------------------------
# Commandes utilitaires
# ---------------------------------------------------------------------------
run_cmd() { # $1 = commande (start|stop|status|logs|update|uninstall)
    local cmd="${1:-install}"
    if [[ "$ENGINE" == "docker" ]]; then
        case "$cmd" in
            start)     start_container ;;
            stop)      docker stop "${CONTAINER_NAME}" && echo "🛑 Conteneur arrêté." ;;
            status)    docker ps --filter "name=${CONTAINER_NAME}" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' ;;
            logs)      docker logs -f "${CONTAINER_NAME}" ;;
            update)    docker exec -it "${CONTAINER_NAME}" python src/cli.py update ;;
            uninstall) docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true; docker rmi "${IMAGE_NAME}" >/dev/null 2>&1 || true; echo "🗑️  Conteneur et image supprimés (les données du package restent dans ${INSTALL_DIR})." ;;
            test)      test_tools ;;
        esac
    else
        case "$cmd" in
            start)     start_container ;;
            stop)      podman stop "${CONTAINER_NAME}" && echo "🛑 Conteneur arrêté." ;;
            status)    podman ps --filter "name=${CONTAINER_NAME}" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' ;;
            logs)      podman logs -f "${CONTAINER_NAME}" ;;
            update)    podman exec -it "${CONTAINER_NAME}" python src/cli.py update ;;
            uninstall) podman rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true; podman rmi "${IMAGE_NAME}" >/dev/null 2>&1 || true; echo "🗑️  Conteneur et image supprimés (les données du package restent dans ${INSTALL_DIR})." ;;
            test)      test_tools ;;
        esac
    fi
}

# ---------------------------------------------------------------------------
# Installation complète
# ---------------------------------------------------------------------------
do_install() {
    local src="${1:-}"
    install_package "$src"
    setup_env
    validate_env
    build_image
    start_container
    sleep 3
    health_check
    echo ""
    echo "✅ Installation terminée."
    echo "   - Serveur MCP: http://<IP_DU_SERVEUR>:${HOST_PORT}/api/v1/stream/mcp"
    echo "   - Logs:        $0 logs"
    echo "   - Statut:      $0 status"
}

# ---------------------------------------------------------------------------
main() {
    local action="install"
    local pkg=""
    for arg in "$@"; do
        case "$arg" in
            install|start|stop|status|logs|update|test|uninstall) action="$arg" ;;
            *) pkg="$arg" ;;
        esac
    done

    check_root
    detect_engine

    case "$action" in
        install)   do_install "$pkg" ;;
        *)         run_cmd "$action" ;;
    esac
}

main "$@"