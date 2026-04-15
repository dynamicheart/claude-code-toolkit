# Claude Code 容器方案

一个 Docker 镜像，将 Claude Code 接入自建的 vLLM 服务（OpenAI 协议）。

[English](README.md)

## 架构

```
你的终端
  │
  ▼
docker exec -it claude_container claude
  │
  ▼
┌─────────────────────────────┐
│        claude 容器           │
│                             │
│  Claude Code CLI            │
│       ▲                     │
│       │ http://127.0.0.1:8082
│  claude-code-proxy          │
└───────┼─────────────────────┘
        │
        ▼
  vLLM 服务 (OpenAI 协议)
  http://<ip>:<port>/v1
```

## 快速开始

### 1. 创建配置文件

```bash
# 复制配置模板并编辑
cp claude-proxy.conf.example ~/claude-proxy.conf
vim ~/claude-proxy.conf
```

### 2. 启动容器

```bash
docker run -d --name claude_container \
    -v ~/claude-proxy.conf:/etc/claude-proxy.conf \
    -v $(pwd):/workspace \
    -e USER_UID=$(id -u) \
    -e USER_GID=$(id -g) \
    ghcr.io/dynamicheart/claude-code-toolkit/claude-code:latest
```

### 3. 使用

```bash
# 默认工作目录：/workspace
docker exec -it claude_container claude

# 指定项目目录（Claude Code 以此为项目根目录）
docker exec -it -w /workspace/my-project claude_container claude
```

## 切换 vLLM 地址（不删容器）

```bash
# 1. 改配置
vim ~/claude-proxy.conf

# 2. 热重载（Claude 会话不丢失）
docker exec claude_container reload_proxy
```

## 配置说明

### 配置文件参数

| 变量 | 默认值 | 说明 |
|---|---|---|
| `VLLM_URL` | *(必填)* | vLLM 服务地址（OpenAI 协议） |
| `MODEL` | `glm-5` | 模型名称（映射到 BIG_MODEL / MIDDLE_MODEL / SMALL_MODEL） |
| `API_KEY` | `sk-placeholder` | API Key（vLLM 不需要认证时保持默认） |
| `PROXY_PORT` | `8082` | claude-code-proxy 监听端口 |

### 环境变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `USER_UID` | `1000` | 宿主机 UID，避免文件权限问题 |
| `USER_GID` | `1000` | 宿主机 GID，避免文件权限问题 |
| `PROXY_CONF` | `/etc/claude-proxy.conf` | 配置文件路径（可覆盖） |

## 常见场景

### vLLM 在远程服务器

```bash
echo "VLLM_URL=http://192.168.1.100:8000/v1" > ~/claude-proxy.conf
docker exec claude_container reload_proxy
```

### 挂载多个项目目录

```bash
docker run -d --name claude_container \
    -v ~/claude-proxy.conf:/etc/claude-proxy.conf \
    -v ~/project-a:/workspace/a \
    -v ~/project-b:/workspace/b \
    -e USER_UID=$(id -u) \
    -e USER_GID=$(id -g) \
    ghcr.io/dynamicheart/claude-code-toolkit/claude-code:latest

# 指定工作目录
docker exec -it -w /workspace/a claude_container claude
```

### 使用 docker compose

```bash
cd claude-container/compose/
cp .env.example .env
vim .env
docker compose up -d --build
docker exec -it claude_container claude
```

## 文件说明

```
claude-container/
├── Dockerfile                    # 镜像构建
├── entrypoint.sh                 # UID/GID 映射 + 自动启动 proxy
├── proxy-env.sh                  # 共享 proxy 配置（被脚本 source）
├── claude-wrapper.sh             # docker exec 包装器（加载环境变量）
├── reload_proxy.sh               # 热重载：改配置不重启容器
├── claude-proxy.conf.example     # docker run 配置模板
├── compose/
│   ├── docker-compose.yml        # compose 编排（可选）
│   └── .env.example              # compose 配置模板
└── README.md                     # English docs
```

## 镜像内置工具

| 工具 | 用途 |
|---|---|
| Claude Code CLI | AI 编程助手 |
| claude-code-proxy | API 协议转换（OpenAI → Anthropic） |
| git | 版本管理 |
| curl | 网络请求 |
| build-base (gcc/make) | 编译 native 依赖 |
| less | 文件查看 |
| bash | Shell 环境 |
