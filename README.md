# Claude Code Toolkit

[![Docker](https://img.shields.io/badge/ghcr.io-dynamicheart%2Fclaude--code--toolkit%2Fclaude--code-blue)](https://github.com/dynamicheart/claude-code-toolkit/pkgs/container/claude-code-toolkit%2Fclaude-code)

Connect Claude Code to self-hosted vLLM services for offline development and testing model agent capabilities.

## Architecture

Two backend modes — switch with `ROUTER_MODE` in config:

```
Proxy mode (default):  Claude Code → claude-code-proxy → vLLM
Router mode:           Claude Code → claude-code-router → vLLM
Debug mode (DEBUG=1):  Claude Code → debug-proxy → proxy/router → vLLM
```

## claude-container

One Docker image with Claude Code + claude-code-proxy + claude-code-router, connecting to any OpenAI-compatible vLLM endpoint.

See [claude-container/README.md](claude-container/README.md) | [中文文档](claude-container/README.zh-CN.md)

### Quick Start

```bash
# 1. Create config
cp claude-container/claude-proxy.conf.example ~/claude-proxy.conf
vim ~/claude-proxy.conf

# 2. Run
docker run -d --name claude_container \
    -v ~/claude-proxy.conf:/etc/claude-proxy.conf \
    -v $(pwd):/workspace \
    -e USER_UID=$(id -u) -e USER_GID=$(id -g) \
    -e TZ=Asia/Shanghai \
    ghcr.io/dynamicheart/claude-code-toolkit/claude-code:latest

# 3. Use
docker exec -it claude_container claude

# Or specify project directory
docker exec -it -w /workspace/my-project claude_container claude
```

### Features

- **Two backend modes**: `proxy` (lightweight) or `router` (model routing, enhancetool, multi-provider)
- **Debug proxy**: built-in request/response logging for diagnosing tool_use and streaming issues
- **Hot-reload**: switch vLLM URL or mode without restarting the container
- **Offline-friendly**: all telemetry and auto-updates disabled
