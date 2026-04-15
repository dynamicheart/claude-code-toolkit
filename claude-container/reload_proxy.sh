#!/bin/sh
# Hot-reload proxy: change config and run this, no container restart needed
set -e

. /usr/local/bin/proxy-env.sh

# Kill old proxy
kill $(pgrep -f "claude-code-proxy") 2>/dev/null && echo "[proxy] Stopped old process" || true
sleep 1

echo "[proxy] Starting claude-code-proxy -> ${VLLM_URL} (port: ${PROXY_PORT})"
claude-code-proxy --port "$PROXY_PORT" &

sleep 2
echo "[proxy] Reload done, Claude will use http://127.0.0.1:${PROXY_PORT}"

# Update persisted env vars
cat > /etc/claude-proxy.env <<ENVEOF
export ANTHROPIC_BASE_URL="http://127.0.0.1:${PROXY_PORT}"
export ANTHROPIC_AUTH_TOKEN="anyvalue"
export OPENAI_API_KEY="$API_KEY"
export OPENAI_BASE_URL="$VLLM_URL"
export BIG_MODEL="$MODEL"
export MIDDLE_MODEL="$MODEL"
export SMALL_MODEL="$MODEL"
export EXTRA_MODELS="$MODEL"
export ANTHROPIC_MODEL="$MODEL"
ENVEOF
