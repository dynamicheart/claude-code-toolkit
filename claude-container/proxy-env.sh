#!/bin/sh
# Shared config: read config file and export env vars
# Sourced by entrypoint.sh and reload_proxy.sh

CONF_FILE=${PROXY_CONF:-/etc/claude-proxy.conf}
if [ -f "$CONF_FILE" ]; then
    VLLM_URL=$(grep '^VLLM_URL=' "$CONF_FILE" | cut -d= -f2-)
    MODEL=$(grep '^MODEL=' "$CONF_FILE" | cut -d= -f2-)
    API_KEY=$(grep '^API_KEY=' "$CONF_FILE" | cut -d= -f2-)
    ROUTER_CONFIG=$(grep '^ROUTER_CONFIG=' "$CONF_FILE" | cut -d= -f2-)
    DEBUG=$(grep '^DEBUG=' "$CONF_FILE" | cut -d= -f2-)
fi

VLLM_URL=${VLLM_URL}
MODEL=${MODEL:-glm-5}
API_KEY=${API_KEY:-sk-placeholder}
ROUTER_PORT=${ROUTER_PORT:-3456}
DEBUG=${DEBUG:-0}
DEBUG_PORT=${DEBUG_PORT:-8083}

export ANTHROPIC_MODEL="$MODEL"
