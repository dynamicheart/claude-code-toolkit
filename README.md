# Claude Code Toolkit

[![Docker](https://img.shields.io/badge/ghcr.io-dynamicheart%2Fclaude--code--toolkit%2Fclaude--code-blue)](https://github.com/dynamicheart/claude-code-toolkit/pkgs/container/claude-code-toolkit%2Fclaude-code)

Connect Claude Code to self-hosted vLLM services for offline development and testing model agent capabilities.

## Architecture

```
Your terminal
  │
  ▼
docker exec -it claude_container claude
  │
  ▼
┌─────────────────────────────┐
│       claude container       │
│                             │
│  Claude Code CLI            │
│       ▲                     │
│       │ http://127.0.0.1:3456
│  claude-code-router         │
└───────┼─────────────────────┘
        │
        ▼
  vLLM Service (OpenAI protocol)
  http://<ip>:<port>/v1
```

## claude-container

One Docker image with Claude Code + [claude-code-router](https://github.com/musistudio/claude-code-router), connecting to any OpenAI-compatible vLLM endpoint.

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

- **claude-code-router**: model routing, `enhancetool` (tool_use error tolerance), multi-provider
- **Debug proxy**: built-in request/response logging for diagnosing tool_use and streaming issues
- **Hot-reload**: switch vLLM URL or config without restarting the container
- **Offline-friendly**: all telemetry and auto-updates disabled
