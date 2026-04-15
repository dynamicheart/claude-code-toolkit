#!/bin/sh
# Based on https://github.com/nezhar/claude-container
# MIT License - Copyright (c) 2025 nezhar

set -e

USER_UID=${USER_UID:-1000}
USER_GID=${USER_GID:-1000}

# Load proxy config
. /usr/local/bin/proxy-env.sh

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

# ---------- helper: start debug proxy ----------
# Usage: start_debug_proxy <backend_port>
# Sets ANTHROPIC_BASE_URL to debug proxy or backend directly
start_debug_proxy() {
    _backend_port=$1
    if [ "$DEBUG" = "1" ]; then
        DEBUG_LOG="/var/log/debug-proxy.log"
        echo "[debug] Starting debug proxy :${DEBUG_PORT} -> :${_backend_port}"
        PROXY_PORT="$_backend_port" DEBUG_PORT="$DEBUG_PORT" DEBUG_FULL="$DEBUG_FULL" \
            python3 /opt/debug-proxy.py >> "$DEBUG_LOG" 2>&1 &
        echo "[debug] PID: $!, log: ${DEBUG_LOG}"
        sleep 1
        export ANTHROPIC_BASE_URL="http://127.0.0.1:${DEBUG_PORT}"
    else
        export ANTHROPIC_BASE_URL="http://127.0.0.1:${_backend_port}"
    fi
}

# ---------- Start backend based on ROUTER_MODE ----------
if [ -n "$VLLM_URL" ]; then

    if [ "$ROUTER_MODE" = "router" ]; then
        # ===== Router mode: claude-code-router =====
        CCR_CONFIG_DIR="/root/.claude-code-router"
        mkdir -p "$CCR_CONFIG_DIR"

        if [ -n "$ROUTER_CONFIG" ] && [ -f "$ROUTER_CONFIG" ]; then
            # Use user-provided config
            cp "$ROUTER_CONFIG" "$CCR_CONFIG_DIR/config.json"
            echo "[router] Using custom config: ${ROUTER_CONFIG}"
        else
            # Auto-generate minimal config from env vars
            VLLM_CHAT_URL="${VLLM_URL%/}/chat/completions"
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

        ROUTER_LOG="/var/log/claude-router.log"
        echo "[router] Starting claude-code-router (port: ${ROUTER_PORT})"
        ccr start >> "$ROUTER_LOG" 2>&1 &
        ROUTER_PID=$!
        echo "[router] PID: ${ROUTER_PID}, log: ${ROUTER_LOG}"

        wait_for_port "$ROUTER_PORT" "router" "$ROUTER_PID" "$ROUTER_LOG"

        export ANTHROPIC_AUTH_TOKEN="anyvalue"
        start_debug_proxy "$ROUTER_PORT"

    else
        # ===== Proxy mode: claude-code-proxy (default) =====

        # Auto-patch fastapi.py to accept Claude Code model names
        FASTAPI_FILE=$(python3 -c "import server.fastapi; print(server.fastapi.__file__)" 2>/dev/null)
        if [ -n "$FASTAPI_FILE" ] && [ -f "$FASTAPI_FILE" ]; then
            if ! grep -q "AUTO PATCH" "$FASTAPI_FILE"; then
                echo "[proxy] Patching fastapi.py ..."
                cat >> "$FASTAPI_FILE" << 'PATCHEOF'

# ===== AUTO PATCH START =====
import os
EXTRA_MODELS = os.environ.get("EXTRA_MODELS", "")
if EXTRA_MODELS:
    try:
        OPENAI_MODELS.extend([m.strip() for m in EXTRA_MODELS.split(",")])
    except Exception:
        pass
# ===== AUTO PATCH END =====
PATCHEOF
            fi
        fi

        PROXY_LOG="/var/log/claude-proxy.log"
        echo "[proxy] Starting claude-code-proxy -> ${VLLM_URL} (port: ${PROXY_PORT})"
        claude-code-proxy --port "$PROXY_PORT" >> "$PROXY_LOG" 2>&1 &
        PROXY_PID=$!
        echo "[proxy] PID: ${PROXY_PID}, log: ${PROXY_LOG}"

        wait_for_port "$PROXY_PORT" "proxy" "$PROXY_PID" "$PROXY_LOG"

        export ANTHROPIC_AUTH_TOKEN="anyvalue"
        start_debug_proxy "$PROXY_PORT"
    fi

    echo "[${ROUTER_MODE}] Claude will use ${ANTHROPIC_BASE_URL}"

    # Persist env vars so docker exec can pick them up
    cat > /etc/claude-proxy.env <<ENVEOF
export ANTHROPIC_BASE_URL="${ANTHROPIC_BASE_URL}"
export ANTHROPIC_AUTH_TOKEN="anyvalue"
export OPENAI_API_KEY="$API_KEY"
export OPENAI_BASE_URL="$VLLM_URL"
export BIG_MODEL="$MODEL"
export MIDDLE_MODEL="$MODEL"
export SMALL_MODEL="$MODEL"
export EXTRA_MODELS="$MODEL"
export ANTHROPIC_MODEL="$MODEL"
ENVEOF
fi

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
