#!/bin/sh
# Hot-reload proxy: change config and run this, no container restart needed
set -e

. /usr/local/bin/proxy-env.sh

# Kill old proxy and debug proxy
kill $(pgrep -f "claude-code-proxy") 2>/dev/null && echo "[proxy] Stopped old proxy" || true
kill $(pgrep -f "debug-proxy.py") 2>/dev/null && echo "[debug] Stopped old debug proxy" || true
sleep 1

echo "[proxy] Starting claude-code-proxy -> ${VLLM_URL} (port: ${PROXY_PORT})"
claude-code-proxy --port "$PROXY_PORT" &
sleep 2

# Determine which URL Claude Code should talk to
if [ "$DEBUG" = "1" ]; then
    DEBUG_LOG="/var/log/debug-proxy.log"
    echo "[debug] Starting debug proxy :${DEBUG_PORT} -> :${PROXY_PORT}"
    PROXY_PORT="$PROXY_PORT" DEBUG_PORT="$DEBUG_PORT" DEBUG_FULL="$DEBUG_FULL" \
        python3 /opt/debug-proxy.py >> "$DEBUG_LOG" 2>&1 &
    echo "[debug] PID: $!, log: ${DEBUG_LOG}"
    sleep 1
    CLAUDE_URL="http://127.0.0.1:${DEBUG_PORT}"
else
    CLAUDE_URL="http://127.0.0.1:${PROXY_PORT}"
fi

echo "[proxy] Reload done, Claude will use ${CLAUDE_URL}"

# Update persisted env vars
cat > /etc/claude-proxy.env <<ENVEOF
export ANTHROPIC_BASE_URL="${CLAUDE_URL}"
export ANTHROPIC_AUTH_TOKEN="anyvalue"
export OPENAI_API_KEY="$API_KEY"
export OPENAI_BASE_URL="$VLLM_URL"
export BIG_MODEL="$MODEL"
export MIDDLE_MODEL="$MODEL"
export SMALL_MODEL="$MODEL"
export EXTRA_MODELS="$MODEL"
export ANTHROPIC_MODEL="$MODEL"
ENVEOF
