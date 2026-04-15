#!/bin/sh
# Shared proxy config: read config file and export env vars
# Sourced by entrypoint.sh and reload_proxy.sh

CONF_FILE=${PROXY_CONF:-/etc/claude-proxy.conf}
if [ -f "$CONF_FILE" ]; then
    VLLM_URL=$(grep '^VLLM_URL=' "$CONF_FILE" | cut -d= -f2-)
    MODEL=$(grep '^MODEL=' "$CONF_FILE" | cut -d= -f2-)
    API_KEY=$(grep '^API_KEY=' "$CONF_FILE" | cut -d= -f2-)
    PROXY_PORT=$(grep '^PROXY_PORT=' "$CONF_FILE" | cut -d= -f2-)
    DEBUG=$(grep '^DEBUG=' "$CONF_FILE" | cut -d= -f2-)
    DEBUG_FULL=$(grep '^DEBUG_FULL=' "$CONF_FILE" | cut -d= -f2-)
fi

VLLM_URL=${VLLM_URL}
MODEL=${MODEL:-glm-5}
API_KEY=${API_KEY:-sk-placeholder}
PROXY_PORT=${PROXY_PORT:-8082}
DEBUG=${DEBUG:-0}
DEBUG_FULL=${DEBUG_FULL:-0}
DEBUG_PORT=${DEBUG_PORT:-8083}

export OPENAI_API_KEY="$API_KEY"
export OPENAI_BASE_URL="$VLLM_URL"
export BIG_MODEL="$MODEL"
export MIDDLE_MODEL="$MODEL"
export SMALL_MODEL="$MODEL"
export EXTRA_MODELS="$MODEL"

export ANTHROPIC_MODEL="$MODEL"
