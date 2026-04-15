#!/bin/sh
# Based on https://github.com/nezhar/claude-container
# MIT License - Copyright (c) 2025 nezhar

set -e

USER_UID=${USER_UID:-1000}
USER_GID=${USER_GID:-1000}

# Load proxy config
. /usr/local/bin/proxy-env.sh

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
    PROXY_LOG="/var/log/claude-proxy.log"
    echo "[proxy] Starting claude-code-proxy -> ${VLLM_URL} (port: ${PROXY_PORT})"
    claude-code-proxy --port "$PROXY_PORT" >> "$PROXY_LOG" 2>&1 &
    PROXY_PID=$!
    echo "[proxy] PID: ${PROXY_PID}, log: ${PROXY_LOG}"

    # Health check — wait up to 30s for proxy to become ready
    PROXY_READY=false
    for i in $(seq 1 30); do
        if curl -s -o /dev/null "http://127.0.0.1:${PROXY_PORT}/" 2>/dev/null; then
            echo "[proxy] Ready! (verified in ~${i}s)"
            PROXY_READY=true
            break
        fi
        if ! kill -0 "$PROXY_PID" 2>/dev/null; then
            echo "[proxy] ERROR: proxy crashed during startup!"
            echo "--- last 20 lines of log ---"
            tail -20 "$PROXY_LOG" 2>/dev/null || echo "(no log yet)"
            exit 1
        fi
        sleep 1
    done
    if [ "$PROXY_READY" = false ]; then
        echo "[proxy] WARNING: proxy not responding after 30s (PID ${PROXY_PID} still alive)"
    fi

    export ANTHROPIC_AUTH_TOKEN="anyvalue"

    # If DEBUG=1, start debug proxy between Claude Code and claude-code-proxy
    if [ "$DEBUG" = "1" ]; then
        DEBUG_LOG="/var/log/debug-proxy.log"
        echo "[debug] Starting debug proxy :${DEBUG_PORT} -> :${PROXY_PORT}"
        PROXY_PORT="$PROXY_PORT" DEBUG_PORT="$DEBUG_PORT" DEBUG_FULL="$DEBUG_FULL" \
            python3 /opt/debug-proxy.py >> "$DEBUG_LOG" 2>&1 &
        DEBUG_PID=$!
        echo "[debug] PID: ${DEBUG_PID}, log: ${DEBUG_LOG}"
        sleep 1
        # Claude Code talks to debug proxy, which forwards to claude-code-proxy
        export ANTHROPIC_BASE_URL="http://127.0.0.1:${DEBUG_PORT}"
    else
        export ANTHROPIC_BASE_URL="http://127.0.0.1:${PROXY_PORT}"
    fi

    echo "[proxy] Claude will use ${ANTHROPIC_BASE_URL}"

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
