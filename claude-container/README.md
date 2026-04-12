# Claude Code Container

Connect Claude Code to your self-hosted vLLM service (OpenAI-compatible) via a single Docker image.

[中文文档](README.zh-CN.md)

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

## Quick Start

### 1. Create config file

```bash
# Copy the example config and edit
cp claude-proxy.conf.example ~/claude-proxy.conf
vim ~/claude-proxy.conf
```

### 2. Run container

```bash
docker run -d --name claude \
    -v ~/claude-proxy.conf:/etc/claude-proxy.conf \
    -v $(pwd):/workspace \
    -e USER_UID=$(id -u) \
    -e USER_GID=$(id -g) \
    ghcr.io/dynamicheart/claude-code-toolkit/claude-code:latest
```

### 3. Use Claude

```bash
docker exec -it claude claude
```

## Switch vLLM URL (no container restart)

```bash
# 1. Edit config
vim ~/claude-proxy.conf

# 2. Hot-reload proxy (Claude sessions are preserved)
docker exec claude reload_proxy
```

## Configuration

### Config File Parameters

| Variable | Default | Description |
|---|---|---|
| `VLLM_URL` | *(required)* | vLLM service URL (OpenAI-compatible) |
| `MODEL` | `glm-5` | Model name (mapped to BIG_MODEL / MIDDLE_MODEL / SMALL_MODEL) |
| `API_KEY` | `sk-placeholder` | API key (keep default if vLLM has no auth) |
| `PROXY_PORT` | `8082` | claude-code-proxy listen port |

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `USER_UID` | `1000` | Host UID for file permission mapping |
| `USER_GID` | `1000` | Host GID for file permission mapping |
| `PROXY_CONF` | `/etc/claude-proxy.conf` | Config file path (overridable) |

## Common Scenarios

### Remote vLLM server

```bash
echo "VLLM_URL=http://192.168.1.100:8000/v1" > ~/claude-proxy.conf
docker exec claude reload_proxy
```

### Multiple project directories

```bash
docker run -d --name claude \
    -v ~/claude-proxy.conf:/etc/claude-proxy.conf \
    -v ~/project-a:/workspace/a \
    -v ~/project-b:/workspace/b \
    -e USER_UID=$(id -u) \
    -e USER_GID=$(id -g) \
    ghcr.io/dynamicheart/claude-code-toolkit/claude-code:latest

# Work in a specific project
docker exec -it -w /workspace/a claude claude
```

### With docker compose

```bash
cd claude-container/compose/
cp .env.example .env
vim .env
docker compose up -d --build
docker exec -it claude claude
```

## Files

```
claude-container/
├── Dockerfile                    # Image build
├── entrypoint.sh                 # UID/GID mapping + auto-start proxy
├── reload_proxy.sh               # Hot-reload proxy without restart
├── start_proxy.sh                # Standalone proxy startup (debug)
├── claude-proxy.conf.example     # Config template for docker run
├── compose/
│   ├── docker-compose.yml        # Compose orchestration (optional)
│   └── .env.example              # Compose config template
└── README.md                     # This file
```

## Built-in Tools

| Tool | Purpose |
|---|---|
| Claude Code CLI | AI coding assistant |
| claude-code-proxy | API protocol conversion (OpenAI -> Anthropic) |
| git | Version control |
| curl | Network requests |
| build-base (gcc/make) | Compile native dependencies |
| less | File viewer |
| bash | Shell environment |
