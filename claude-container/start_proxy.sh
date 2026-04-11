#!/bin/bash
# Standalone proxy startup (for debugging)
set -e

VLLM_URL=${VLLM_URL:-http://localhost:8000/v1}
MODEL=${MODEL:-glm-5}
API_KEY=${API_KEY:-sk-placeholder}
PROXY_PORT=${PROXY_PORT:-8082}

echo "Starting claude-code-proxy"
echo "  Target: ${VLLM_URL}"
echo "  Model:  ${MODEL}"
echo "  Port:   ${PROXY_PORT}"

export OPENAI_API_KEY="$API_KEY"
export OPENAI_BASE_URL="$VLLM_URL"
export BIG_MODEL="$MODEL"
export MIDDLE_MODEL="$MODEL"
export SMALL_MODEL="$MODEL"

exec uvicorn server:app --host 0.0.0.0 --port "$PROXY_PORT"
