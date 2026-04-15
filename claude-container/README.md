# Claude Code Container

Connect Claude Code to your self-hosted vLLM service (OpenAI-compatible) via a single Docker image.

[中文文档](README.zh-CN.md)

## Architecture

```
Claude Code → claude-code-router (:3456) → vLLM
```

With debug proxy (`DEBUG=1`):
```
Claude Code → debug-proxy (:8083) → claude-code-router (:3456) → vLLM
```

Uses [claude-code-router](https://github.com/musistudio/claude-code-router) as the backend, with built-in `enhancetool` for tool_use error tolerance.

## Quick Start

### 1. Create config file

```bash
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
docker exec -it claude_container claude

# Specify a project directory
docker exec -it -w /workspace/my-project claude_container claude
```

## Hot-Reload (no container restart)

```bash
vim ~/claude-proxy.conf
docker exec claude_container reload_proxy
```

## Configuration

### Config File Parameters

| Variable | Default | Description |
|---|---|---|
| `VLLM_URL` | *(required)* | vLLM service URL (OpenAI-compatible) |
| `MODEL` | `glm-5` | Model name on vLLM |
| `API_KEY` | `sk-placeholder` | API key (keep default if vLLM has no auth) |
| `ROUTER_CONFIG` | *(none)* | Custom claude-code-router config path |
| `DEBUG` | `0` | Set to `1` to enable debug proxy |
| `DEBUG_FULL` | `0` | Set to `1` to log complete request/response bodies |

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `USER_UID` | `1000` | Host UID for file permission mapping |
| `USER_GID` | `1000` | Host GID for file permission mapping |
| `TZ` | `UTC` | Timezone (e.g. `Asia/Shanghai`, `America/New_York`) |
| `PROXY_CONF` | `/etc/claude-proxy.conf` | Config file path (overridable) |

## Custom Router Config

For advanced routing (multiple models, think/background split, multi-provider), mount a custom [claude-code-router config](https://github.com/musistudio/claude-code-router):

```bash
docker run -d --name claude_container \
    -v ~/claude-proxy.conf:/etc/claude-proxy.conf \
    -v ~/my-router-config.json:/etc/claude-router-config.json \
    -v $(pwd):/workspace \
    -e USER_UID=$(id -u) \
    -e USER_GID=$(id -g) \
    -e TZ=Asia/Shanghai \
    ghcr.io/dynamicheart/claude-code-toolkit/claude-code:latest
```

With `ROUTER_CONFIG=/etc/claude-router-config.json` in your conf file.

## Debug Proxy

For diagnosing tool_use failures and streaming issues:

```bash
# Enable in config
echo "DEBUG=1" >> ~/claude-proxy.conf
docker exec claude_container reload_proxy

# View logs
docker exec claude_container tail -f /var/log/debug-proxy.log

# Full request/response bodies (DEBUG_FULL=1)
docker exec claude_container cat /var/log/debug-proxy-full.log
```

## Common Scenarios

### Multiple project directories

```bash
docker run -d --name claude_container \
    -v ~/claude-proxy.conf:/etc/claude-proxy.conf \
    -v ~/project-a:/workspace/a \
    -v ~/project-b:/workspace/b \
    -e USER_UID=$(id -u) -e USER_GID=$(id -g) \
    -e TZ=Asia/Shanghai \
    ghcr.io/dynamicheart/claude-code-toolkit/claude-code:latest

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
├── entrypoint.sh                 # UID/GID mapping + auto-start router
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
| claude-code-router | Model routing + enhancetool (tool_use error tolerance) |
| debug-proxy | Request/response logging for debugging |
| git | Version control |
| curl | Network requests |
| build-base (gcc/make) | Compile native dependencies |
| less | File viewer |
| bash | Shell environment |
