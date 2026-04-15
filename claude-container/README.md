# Claude Code Container

Connect Claude Code to your self-hosted vLLM service (OpenAI-compatible) via a single Docker image.

[中文文档](README.zh-CN.md)

## Architecture

Two backend modes available — switch with `ROUTER_MODE` in config:

**Proxy mode** (default): lightweight Anthropic → OpenAI translation
```
Claude Code → claude-code-proxy (:8082) → vLLM
```

**Router mode**: model routing, enhancetool, multi-provider ([claude-code-router](https://github.com/musistudio/claude-code-router))
```
Claude Code → claude-code-router (:3456) → vLLM
```

**With debug proxy** (`DEBUG=1`): intercepts and logs all requests/responses
```
Claude Code → debug-proxy (:8083) → proxy/router → vLLM
```

## Quick Start

### 1. Create config file

```bash
# Copy the example config and edit
cp claude-proxy.conf.example ~/claude-proxy.conf
vim ~/claude-proxy.conf
```

### 2. Run container

```bash
docker run -d --name claude_container \
    -v ~/claude-proxy.conf:/etc/claude-proxy.conf \
    -v $(pwd):/workspace \
    -e USER_UID=$(id -u) \
    -e USER_GID=$(id -g) \
    -e TZ=Asia/Shanghai \
    ghcr.io/dynamicheart/claude-code-toolkit/claude-code:latest
```

### 3. Use Claude

```bash
# Default working directory: /workspace
docker exec -it claude_container claude

# Specify a project directory (Claude Code uses this as project root)
docker exec -it -w /workspace/my-project claude_container claude
```

## Switch vLLM URL (no container restart)

```bash
# 1. Edit config
vim ~/claude-proxy.conf

# 2. Hot-reload proxy (Claude sessions are preserved)
docker exec claude_container reload_proxy
```

## Configuration

### Config File Parameters

| Variable | Default | Description |
|---|---|---|
| `VLLM_URL` | *(required)* | vLLM service URL (OpenAI-compatible) |
| `MODEL` | `glm-5` | Model name (mapped to BIG_MODEL / MIDDLE_MODEL / SMALL_MODEL) |
| `API_KEY` | `sk-placeholder` | API key (keep default if vLLM has no auth) |
| `ROUTER_MODE` | `proxy` | Backend mode: `proxy` (claude-code-proxy) or `router` (claude-code-router) |
| `PROXY_PORT` | `8082` | claude-code-proxy listen port (proxy mode only) |
| `ROUTER_CONFIG` | *(none)* | Custom claude-code-router config path (router mode only) |
| `DEBUG` | `0` | Set to `1` to enable debug proxy (request/response logging) |
| `DEBUG_FULL` | `0` | Set to `1` to log complete request/response bodies |

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `USER_UID` | `1000` | Host UID for file permission mapping |
| `USER_GID` | `1000` | Host GID for file permission mapping |
| `PROXY_CONF` | `/etc/claude-proxy.conf` | Config file path (overridable) |
| `TZ` | `UTC` | Timezone (e.g. `Asia/Shanghai`, `America/New_York`) |

## Router Mode

Use [claude-code-router](https://github.com/musistudio/claude-code-router) as the backend for model routing, `enhancetool` transformer (tool_use error tolerance), and multi-provider support.

```bash
# Simple: auto-generate config from VLLM_URL/MODEL/API_KEY
echo "ROUTER_MODE=router" >> ~/claude-proxy.conf
docker exec claude_container reload_proxy

# Advanced: mount a custom claude-code-router config
docker run -d --name claude_container \
    -v ~/claude-proxy.conf:/etc/claude-proxy.conf \
    -v ~/my-router-config.json:/etc/claude-router-config.json \
    -v $(pwd):/workspace \
    -e USER_UID=$(id -u) \
    -e USER_GID=$(id -g) \
    ghcr.io/dynamicheart/claude-code-toolkit/claude-code:latest
```

With `ROUTER_CONFIG=/etc/claude-router-config.json` in your conf file.

## Debug Proxy

A built-in debug proxy for diagnosing tool_use failures, streaming issues, and model compatibility problems.

### Enable

Add to `claude-proxy.conf`:
```
DEBUG=1
DEBUG_FULL=1
```

### Log files

| File | Content |
|---|---|
| `/var/log/debug-proxy.log` | Summary: model, tool names, stop_reason, SSE events |
| `/var/log/debug-proxy-full.log` | Complete request/response bodies (when `DEBUG_FULL=1`) |

### View logs

```bash
# Real-time summary
docker exec claude_container tail -f /var/log/debug-proxy.log

# Full request/response bodies
docker exec claude_container cat /var/log/debug-proxy-full.log
```

### What it logs

- **Request**: model, stream mode, tool list, last message content
- **SSE events** (real-time): `message_start`, `content_block_start` (tool_use name/id), `content_block_delta` (input_json, text), `message_delta` (stop_reason, output_tokens)
- **Response** (non-stream): status, stop_reason, content types, tool_use details

Works with both proxy and router modes.

## Common Scenarios

### Remote vLLM server

```bash
echo "VLLM_URL=http://192.168.1.100:8000/v1" > ~/claude-proxy.conf
docker exec claude_container reload_proxy
```

### Multiple project directories

```bash
docker run -d --name claude_container \
    -v ~/claude-proxy.conf:/etc/claude-proxy.conf \
    -v ~/project-a:/workspace/a \
    -v ~/project-b:/workspace/b \
    -e USER_UID=$(id -u) \
    -e USER_GID=$(id -g) \
    ghcr.io/dynamicheart/claude-code-toolkit/claude-code:latest

# Work in a specific project
docker exec -it -w /workspace/a claude_container claude
```

### With docker compose

```bash
cd claude-container/compose/
cp .env.example .env
vim .env
docker compose up -d --build
docker exec -it claude_container claude
```

## Files

```
claude-container/
├── Dockerfile                    # Image build
├── entrypoint.sh                 # UID/GID mapping + auto-start backend
├── proxy-env.sh                  # Shared config (sourced by scripts)
├── claude-wrapper.sh             # Wrapper for docker exec (sources env)
├── reload_proxy.sh               # Hot-reload without restart
├── debug-proxy.py                # Debug proxy for request/response logging
├── claude-proxy.conf.example     # Config template
├── compose/
│   ├── docker-compose.yml        # Compose orchestration (optional)
│   └── .env.example              # Compose config template
└── README.md                     # This file
```

## Built-in Tools

| Tool | Purpose |
|---|---|
| Claude Code CLI | AI coding assistant |
| claude-code-proxy | API protocol conversion (Anthropic → OpenAI) |
| claude-code-router | Model routing, enhancetool, multi-provider |
| debug-proxy | Request/response logging for debugging |
| git | Version control |
| curl | Network requests |
| build-base (gcc/make) | Compile native dependencies |
| less | File viewer |
| bash | Shell environment |
