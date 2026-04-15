# Based on https://github.com/nezhar/claude-container
# MIT License - Copyright (c) 2025 nezhar

FROM node:22-alpine

# Tools required by Claude Code
#   git: version control (diff, commit, log)
#   curl: network requests
#   build-base (gcc/make): compile native npm modules
#   less: view large files
#   bash, su-exec: runtime
#   python3, py3-pip: claude-code-proxy
RUN apk add --no-cache git curl build-base less bash su-exec python3 py3-pip tzdata

# Install claude-code-proxy and claude-code-router
RUN pip install --break-system-packages -U claude-code-proxy flask requests
RUN npm install -g @musistudio/claude-code-router

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code@latest \
    && claude --version > /etc/claude-code-version \
    && echo "Claude Code version: $(cat /etc/claude-code-version)"

RUN mkdir -p /workspace

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY reload_proxy.sh /usr/local/bin/reload_proxy.sh
COPY claude-wrapper.sh /usr/local/bin/claude-wrapper.sh
COPY proxy-env.sh /usr/local/bin/proxy-env.sh
COPY debug-proxy.py /opt/debug-proxy.py
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/reload_proxy.sh /usr/local/bin/claude-wrapper.sh /usr/local/bin/proxy-env.sh

# Rename real claude -> claude.real, wrapper -> claude
RUN mv /usr/local/bin/claude /usr/local/bin/claude.real \
    && mv /usr/local/bin/claude-wrapper.sh /usr/local/bin/claude

RUN mkdir -p /root/.claude/skills /root/.claude/agents /root/.claude/commands \
    /etc/claude-code/.claude/skills /etc/claude-code/.claude/agents /etc/claude-code/.claude/commands

# Pre-warm: trigger first-run initialization before offline ENV is set
RUN timeout 10 claude.real --help > /dev/null 2>&1 || true

# Offline-friendly defaults (set AFTER pre-warm so build can reach anthropic)
ENV DISABLE_AUTOUPDATER=1
ENV DISABLE_TELEMETRY=1
ENV DISABLE_ERROR_REPORTING=1
ENV CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
ENV CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL=1
ENV CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE=1

WORKDIR /workspace

ENV SHELL=/bin/bash
ENV TERM=xterm-256color
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sh", "-c", "echo 'Claude Code container is ready!' && tail -f /dev/null"]
