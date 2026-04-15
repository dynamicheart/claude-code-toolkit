#!/bin/sh
# Hot-reload router: change config and run this, no container restart needed
set -e

. /usr/local/bin/proxy-env.sh

# Kill old processes
kill $(pgrep -f "debug-proxy.py") 2>/dev/null && echo "[debug] Stopped old debug proxy" || true
kill $(pgrep -f "claude-code-router") 2>/dev/null && echo "[router] Stopped old router" || true
sleep 1

# Regenerate config if no custom config
CCR_CONFIG_DIR="/root/.claude-code-router"
mkdir -p "$CCR_CONFIG_DIR"

if [ -n "$ROUTER_CONFIG" ] && [ -f "$ROUTER_CONFIG" ]; then
    cp "$ROUTER_CONFIG" "$CCR_CONFIG_DIR/config.json"
    echo "[router] Using custom config: ${ROUTER_CONFIG}"
else
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
sleep 2

# Determine which URL Claude Code should talk to
if [ "$DEBUG" = "1" ]; then
    DEBUG_LOG="/var/log/debug-proxy.log"
    echo "[debug] Starting debug proxy :${DEBUG_PORT} -> :${ROUTER_PORT}"
    PROXY_PORT="$ROUTER_PORT" DEBUG_PORT="$DEBUG_PORT" DEBUG_FULL="$DEBUG_FULL" \
        python3 /opt/debug-proxy.py >> "$DEBUG_LOG" 2>&1 &
    echo "[debug] PID: $!, log: ${DEBUG_LOG}"
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
