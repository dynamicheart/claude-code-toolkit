#!/bin/sh
# Based on https://github.com/nezhar/claude-container
# MIT License - Copyright (c) 2025 nezhar

set -e

USER_UID=${USER_UID:-1000}
USER_GID=${USER_GID:-1000}

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

# Read config file (takes priority), fallback to env vars
CONF_FILE=${PROXY_CONF:-/etc/claude-proxy.conf}
if [ -f "$CONF_FILE" ]; then
    VLLM_URL=$(grep '^VLLM_URL=' "$CONF_FILE" | cut -d= -f2-)
    MODEL=$(grep '^MODEL=' "$CONF_FILE" | cut -d= -f2-)
    API_KEY=$(grep '^API_KEY=' "$CONF_FILE" | cut -d= -f2-)
    PROXY_PORT=$(grep '^PROXY_PORT=' "$CONF_FILE" | cut -d= -f2-)
fi

# Apply defaults (env vars from docker compose / docker run are preserved)
VLLM_URL=${VLLM_URL}
MODEL=${MODEL:-glm-5}
API_KEY=${API_KEY:-sk-placeholder}
PROXY_PORT=${PROXY_PORT:-8082}

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

# Start claude-code-proxy in background
if [ -n "$VLLM_URL" ]; then
    export OPENAI_API_KEY="$API_KEY"
    export OPENAI_BASE_URL="$VLLM_URL"
    export BIG_MODEL="$MODEL"
    export MIDDLE_MODEL="$MODEL"
    export SMALL_MODEL="$MODEL"

    PROXY_LOG="/var/log/claude-proxy.log"
    echo "[proxy] Starting claude-code-proxy -> ${VLLM_URL} (port: ${PROXY_PORT})"
    claude-code-proxy --port "$PROXY_PORT" >> "$PROXY_LOG" 2>&1 &
    PROXY_PID=$!
    echo "[proxy] PID: ${PROXY_PID}, log: ${PROXY_LOG}"

    # Health check — wait up to 120s for proxy to become ready
    PROXY_READY=false
    for i in $(seq 1 120); do
        if curl -sf "http://127.0.0.1:${PROXY_PORT}/v1/models" >/dev/null 2>&1; then
            echo "[proxy] Ready! (verified in ~${i}s)"
            PROXY_READY=true
            break
        fi
        if ! kill -0 "$PROXY_PID" 2>/dev/null; then
            echo "[proxy] ERROR: uvicorn crashed during startup!"
            echo "--- last 20 lines of log ---"
            tail -20 "$PROXY_LOG" 2>/dev/null || echo "(no log yet)"
            exit 1
        fi
        sleep 1
    done
    if [ "$PROXY_READY" = false ]; then
        echo "[proxy] WARNING: proxy not responding after 10s (PID ${PROXY_PID} still alive)"
    fi

    export ANTHROPIC_BASE_URL="http://127.0.0.1:${PROXY_PORT}"
    export ANTHROPIC_API_KEY="anyvalue"
    echo "[proxy] Claude will use ${ANTHROPIC_BASE_URL}"

    # Persist env vars so docker exec can pick them up
    cat > /etc/claude-proxy.env <<ENVEOF
export ANTHROPIC_BASE_URL="http://127.0.0.1:${PROXY_PORT}"
export ANTHROPIC_API_KEY="anyvalue"
export OPENAI_API_KEY="$API_KEY"
export OPENAI_BASE_URL="$VLLM_URL"
export BIG_MODEL="$MODEL"
export MIDDLE_MODEL="$MODEL"
export SMALL_MODEL="$MODEL"
ENVEOF
fi

exec su-exec "${USER_NAME}" "$@"
