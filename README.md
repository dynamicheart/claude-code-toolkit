# Claude Code Toolkit

Connect Claude Code to self-hosted vLLM services for testing model agent capabilities.

## Architecture

```
Your terminal
  │
  ▼
docker exec -it claude claude
  │
  ▼
┌─────────────────────────────┐
│       claude container       │
│                             │
│  Claude Code CLI            │
│       ▲                     │
│       │ http://127.0.0.1:8082
│  claude-code-proxy          │
└───────┼─────────────────────┘
        │
        ▼
  vLLM Service (OpenAI protocol)
  http://<ip>:<port>/v1
```

## claude-container

One Docker image with Claude Code + claude-code-proxy, connecting to any OpenAI-compatible vLLM endpoint.

See [claude-container/README.md](claude-container/README.md) | [中文文档](claude-container/README.zh-CN.md)

### Quick Start

```bash
# 1. Create config
cp claude-container/claude-proxy.conf.example ~/claude-proxy.conf
vim ~/claude-proxy.conf

# 2. Run
docker run -d --name claude \
    -v ~/claude-proxy.conf:/etc/claude-proxy.conf \
    -v $(pwd):/workspace \
    -e USER_UID=$(id -u) -e USER_GID=$(id -g) \
    claude-code:latest

# 3. Use
docker exec -it claude claude
```
