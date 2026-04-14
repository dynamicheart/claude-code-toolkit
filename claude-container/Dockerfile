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
RUN apk add --no-cache git curl build-base less bash su-exec python3 py3-pip

# Install claude-code-proxy
RUN pip install --break-system-packages -U claude-code-proxy

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code@latest

RUN mkdir -p /workspace

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY reload_proxy.sh /usr/local/bin/reload_proxy.sh
COPY start_proxy.sh /opt/start_proxy.sh
COPY claude-wrapper.sh /usr/local/bin/claude-wrapper.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/reload_proxy.sh /opt/start_proxy.sh /usr/local/bin/claude-wrapper.sh

# Rename real claude -> claude.real, wrapper -> claude
RUN mv /usr/local/bin/claude /usr/local/bin/claude.real \
    && mv /usr/local/bin/claude-wrapper.sh /usr/local/bin/claude

WORKDIR /workspace

ENV SHELL=/bin/bash
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sh", "-c", "echo 'Claude Code container is ready!' && tail -f /dev/null"]
