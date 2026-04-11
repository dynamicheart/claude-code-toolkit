#!/bin/sh
# Hot-reload proxy: change config and run this, no container restart needed
set -e

CONF_FILE=${PROXY_CONF:-/etc/claude-proxy.conf}

if [ ! -f "$CONF_FILE" ]; then
    echo "Config file not found: $CONF_FILE"
    exit 1
fi

# Read config
VLLM_URL=$(grep '^VLLM_URL=' "$CONF_FILE" | cut -d= -f2-)
MODEL=$(grep '^MODEL=' "$CONF_FILE" | cut -d= -f2-)
API_KEY=$(grep '^API_KEY=' "$CONF_FILE" | cut -d= -f2-)
PROXY_PORT=$(grep '^PROXY_PORT=' "$CONF_FILE" | cut -d= -f2-)

VLLM_URL=${VLLM_URL:-http://localhost:8000/v1}
MODEL=${MODEL:-glm-5}
API_KEY=${API_KEY:-sk-placeholder}
PROXY_PORT=${PROXY_PORT:-8082}

# Kill old proxy
kill $(pgrep -f "uvicorn server:app") 2>/dev/null && echo "[proxy] Stopped old process" || true
sleep 1

# Start new proxy
export OPENAI_API_KEY="$API_KEY"
export OPENAI_BASE_URL="$VLLM_URL"
export BIG_MODEL="$MODEL"
export MIDDLE_MODEL="$MODEL"
export SMALL_MODEL="$MODEL"

echo "[proxy] Starting claude-code-proxy -> ${VLLM_URL} (port: ${PROXY_PORT})"
uvicorn server:app --host 0.0.0.0 --port "$PROXY_PORT" &

sleep 2
echo "[proxy] Reload done, Claude will use http://127.0.0.1:${PROXY_PORT}"
