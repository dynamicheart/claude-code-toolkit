#!/bin/sh
# Based on https://github.com/nezhar/claude-container
# MIT License - Copyright (c) 2025 nezhar

set -e

USER_UID=${USER_UID:-1000}
USER_GID=${USER_GID:-1000}

# Load config
CONF_FILE=${PROXY_CONF:-/etc/claude-proxy.conf}
if [ ! -f "$CONF_FILE" ]; then
    echo "ERROR: Config file not found: ${CONF_FILE}"
    echo "Mount it with: -v ~/claude-proxy.conf:${CONF_FILE}"
    exit 1
fi
. /usr/local/bin/proxy-env.sh

if [ -z "$VLLM_URL" ]; then
    echo "ERROR: VLLM_URL is not set in ${CONF_FILE}"
    echo "Add: VLLM_URL=http://<host>:<port>/v1"
    exit 1
fi

# ---------- helper: health check ----------
# Usage: wait_for_port <port> <name> <pid> <log_file>
wait_for_port() {
    _port=$1 _name=$2 _pid=$3 _log=$4
    _ready=false
    for i in $(seq 1 30); do
        if curl -s -o /dev/null "http://127.0.0.1:${_port}/" 2>/dev/null; then
            echo "[${_name}] Ready! (verified in ~${i}s)"
            _ready=true
            break
        fi
        if ! kill -0 "$_pid" 2>/dev/null; then
            echo "[${_name}] ERROR: crashed during startup!"
            echo "--- last 20 lines of log ---"
            tail -20 "$_log" 2>/dev/null || echo "(no log yet)"
            exit 1
        fi
        sleep 1
    done
    if [ "$_ready" = false ]; then
        echo "[${_name}] WARNING: not responding after 30s (PID ${_pid} still alive)"
    fi
}

# ---------- Start claude-code-router ----------
CCR_CONFIG_DIR="/root/.claude-code-router"
mkdir -p "$CCR_CONFIG_DIR"

    # Strip /v1 from VLLM_URL to get base URL for backend debug proxy
    VLLM_BASE="${VLLM_URL%/v1}"
    VLLM_BASE="${VLLM_BASE%/}"
    BACKEND_DEBUG_PORT=${BACKEND_DEBUG_PORT:-8084}

    if [ -n "$ROUTER_CONFIG" ] && [ -f "$ROUTER_CONFIG" ]; then
        cp "$ROUTER_CONFIG" "$CCR_CONFIG_DIR/config.json"
        echo "[router] Using custom config: ${ROUTER_CONFIG}"
    else
        # When DEBUG=1, route ccr through backend debug proxy to capture OpenAI requests
        if [ "$DEBUG" = "1" ]; then
            VLLM_CHAT_URL="http://127.0.0.1:${BACKEND_DEBUG_PORT}/v1/chat/completions"
        else
            VLLM_CHAT_URL="${VLLM_URL%/}/chat/completions"
        fi

        cat > "$CCR_CONFIG_DIR/config.json" <<CCREOF
{
  "LOG": true,
  "NON_INTERACTIVE_MODE": true,
  "Providers": [
    {
      "name": "vllm",
      "api_base_url": "${VLLM_CHAT_URL}",
      "api_key": "${API_KEY}",
      "models": ["${MODEL}"],
      "transformer": {
        "use": ["enhancetool"]
      }
    }
  ],
  "Router": {
    "default": "vllm,${MODEL}"
  }
}
CCREOF
        echo "[router] Generated config for ${MODEL} -> ${VLLM_CHAT_URL}"
    fi

    # If DEBUG=1, start backend debug proxy (OpenAI layer: ccr -> provider)
    if [ "$DEBUG" = "1" ]; then
        BACKEND_LOG="/var/log/ccr2provider.log"
        echo "[debug] Starting backend debug proxy :${BACKEND_DEBUG_PORT} -> ${VLLM_BASE} (OpenAI layer)"
        TARGET_URL="$VLLM_BASE" DEBUG_PORT="$BACKEND_DEBUG_PORT" \
            LAYER_TAG="openai" LOG_FILE="$BACKEND_LOG" \
            FULL_LOG="/var/log/ccr2provider-full.log" \
            python3 /opt/debug-proxy.py >> "$BACKEND_LOG" 2>&1 &
        echo "[debug] PID: $!, log: ${BACKEND_LOG}"
        sleep 1
    fi

    ROUTER_LOG="/var/log/claude-router.log"
    echo "[router] Starting claude-code-router (port: ${ROUTER_PORT})"
    ccr start >> "$ROUTER_LOG" 2>&1 &
    ROUTER_PID=$!
    echo "[router] PID: ${ROUTER_PID}, log: ${ROUTER_LOG}"

    wait_for_port "$ROUTER_PORT" "router" "$ROUTER_PID" "$ROUTER_LOG"

    export ANTHROPIC_AUTH_TOKEN="anyvalue"

    # If DEBUG=1, start frontend debug proxy (Anthropic layer: Claude Code -> ccr)
    if [ "$DEBUG" = "1" ]; then
        FRONTEND_LOG="/var/log/cc2ccr.log"
        echo "[debug] Starting frontend debug proxy :${DEBUG_PORT} -> :${ROUTER_PORT} (Anthropic layer)"
        TARGET_URL="http://127.0.0.1:${ROUTER_PORT}" DEBUG_PORT="$DEBUG_PORT" \
            LAYER_TAG="anthropic" LOG_FILE="$FRONTEND_LOG" \
            FULL_LOG="/var/log/cc2ccr-full.log" \
            python3 /opt/debug-proxy.py >> "$FRONTEND_LOG" 2>&1 &
        echo "[debug] PID: $!, log: ${FRONTEND_LOG}"
        sleep 1
        export ANTHROPIC_BASE_URL="http://127.0.0.1:${DEBUG_PORT}"
    else
        export ANTHROPIC_BASE_URL="http://127.0.0.1:${ROUTER_PORT}"
    fi

    echo "[router] Claude will use ${ANTHROPIC_BASE_URL}"

    # Persist env vars so docker exec can pick them up
    cat > /etc/claude-proxy.env <<ENVEOF
export ANTHROPIC_BASE_URL="${ANTHROPIC_BASE_URL}"
export ANTHROPIC_AUTH_TOKEN="anyvalue"
export ANTHROPIC_MODEL="$MODEL"
ENVEOF

# Drop privileges if non-root, otherwise run directly
if [ "$USER_UID" -eq 0 ]; then
    exec "$@"
fi

# Create user with matching UID/GID
if ! getent group "$USER_GID" >/dev/null 2>&1; then
    addgroup -g "$USER_GID" claude 2>/dev/null || true
fi
GROUP_NAME=$(getent group "$USER_GID" 2>/dev/null | cut -d: -f1)
GROUP_NAME=${GROUP_NAME:-claude}

if ! getent passwd "$USER_UID" >/dev/null 2>&1; then
    adduser -D -u "$USER_UID" -G "$GROUP_NAME" -h /home/claude -s /bin/bash claude 2>/dev/null || true
fi
USER_NAME=$(getent passwd "$USER_UID" 2>/dev/null | cut -d: -f1)
USER_NAME=${USER_NAME:-claude}

exec su-exec "${USER_NAME}" "$@"
