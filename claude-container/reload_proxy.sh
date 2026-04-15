#!/bin/sh
# Hot-reload router: change config and run this, no container restart needed
set -e

. /usr/local/bin/proxy-env.sh

# Kill old processes (all layers)
kill $(pgrep -f "debug-proxy.py") 2>/dev/null && echo "[debug] Stopped old debug proxies" || true
kill $(pgrep -f "claude-code-router") 2>/dev/null && echo "[router] Stopped old router" || true
sleep 1

# Strip /v1 from VLLM_URL to get base URL for backend debug proxy
VLLM_BASE="${VLLM_URL%/v1}"
VLLM_BASE="${VLLM_BASE%/}"
BACKEND_DEBUG_PORT=${BACKEND_DEBUG_PORT:-8084}

# Regenerate config if no custom config
CCR_CONFIG_DIR="/root/.claude-code-router"
mkdir -p "$CCR_CONFIG_DIR"

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
sleep 2

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
    CLAUDE_URL="http://127.0.0.1:${DEBUG_PORT}"
else
    CLAUDE_URL="http://127.0.0.1:${ROUTER_PORT}"
fi

echo "[router] Reload done, Claude will use ${CLAUDE_URL}"

# Update persisted env vars
cat > /etc/claude-proxy.env <<ENVEOF
export ANTHROPIC_BASE_URL="${CLAUDE_URL}"
export ANTHROPIC_AUTH_TOKEN="anyvalue"
export ANTHROPIC_MODEL="$MODEL"
ENVEOF
