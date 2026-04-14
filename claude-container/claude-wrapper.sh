#!/bin/sh
# Wrapper for claude CLI — sources proxy env vars set by entrypoint.sh
[ -f /etc/claude-proxy.env ] && . /etc/claude-proxy.env
exec /usr/local/bin/claude.real "$@"
