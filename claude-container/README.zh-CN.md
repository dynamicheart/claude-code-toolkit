# Claude Code 容器方案

一个 Docker 镜像，将 Claude Code 接入自建的 vLLM 服务（OpenAI 协议）。

[English](README.md)

## 架构

支持两种后端模式，通过配置文件中的 `ROUTER_MODE` 切换：

**Proxy 模式**（默认）：轻量级 Anthropic → OpenAI 协议转换
```
Claude Code → claude-code-proxy (:8082) → vLLM
```

**Router 模式**：模型路由、enhancetool 容错、多 Provider 支持（[claude-code-router](https://github.com/musistudio/claude-code-router)）
```
Claude Code → claude-code-router (:3456) → vLLM
```

**开启 Debug 代理**（`DEBUG=1`）：拦截并记录所有请求和响应
```
Claude Code → debug-proxy (:8083) → proxy/router → vLLM
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
| `ROUTER_MODE` | `proxy` | 后端模式：`proxy`（claude-code-proxy）或 `router`（claude-code-router） |
| `PROXY_PORT` | `8082` | claude-code-proxy 监听端口（仅 proxy 模式） |
| `ROUTER_CONFIG` | *(无)* | 自定义 claude-code-router 配置文件路径（仅 router 模式） |
| `DEBUG` | `0` | 设为 `1` 开启 debug 代理（请求/响应日志） |
| `DEBUG_FULL` | `0` | 设为 `1` 记录完整的请求/响应 body |

### 环境变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `USER_UID` | `1000` | 宿主机 UID，避免文件权限问题 |
| `USER_GID` | `1000` | 宿主机 GID，避免文件权限问题 |
| `PROXY_CONF` | `/etc/claude-proxy.conf` | 配置文件路径（可覆盖） |

## Router 模式

使用 [claude-code-router](https://github.com/musistudio/claude-code-router) 作为后端，支持模型路由、`enhancetool` 转换器（tool_use 容错）、多 Provider。

```bash
# 简单用法：从 VLLM_URL/MODEL/API_KEY 自动生成配置
echo "ROUTER_MODE=router" >> ~/claude-proxy.conf
docker exec claude_container reload_proxy

# 高级用法：挂载自定义 claude-code-router 配置
docker run -d --name claude_container \
    -v ~/claude-proxy.conf:/etc/claude-proxy.conf \
    -v ~/my-router-config.json:/etc/claude-router-config.json \
    -v $(pwd):/workspace \
    -e USER_UID=$(id -u) \
    -e USER_GID=$(id -g) \
    ghcr.io/dynamicheart/claude-code-toolkit/claude-code:latest
```

在 conf 文件中设置 `ROUTER_CONFIG=/etc/claude-router-config.json` 即可。

## Debug 代理

内置 debug 代理，用于诊断 tool_use 失败、流式传输问题、模型兼容性问题。

### 开启

在 `claude-proxy.conf` 中添加：
```
DEBUG=1
DEBUG_FULL=1
```

### 日志文件

| 文件 | 内容 |
|---|---|
| `/var/log/debug-proxy.log` | 摘要：模型、工具名、stop_reason、SSE 事件 |
| `/var/log/debug-proxy-full.log` | 完整的请求/响应 body（需 `DEBUG_FULL=1`） |

### 查看日志

```bash
# 实时查看摘要日志
docker exec claude_container tail -f /var/log/debug-proxy.log

# 查看完整请求/响应
docker exec claude_container cat /var/log/debug-proxy-full.log
```

### 日志内容

- **请求**：模型名、stream 模式、tool 列表、最后一条消息内容
- **SSE 事件**（实时）：`message_start`、`content_block_start`（tool_use name/id）、`content_block_delta`（input_json、text）、`message_delta`（stop_reason、output_tokens）
- **响应**（非流式）：状态码、stop_reason、content 类型、tool_use 详情

两种后端模式均支持 debug 代理。

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
├── entrypoint.sh                 # UID/GID 映射 + 自动启动后端
├── proxy-env.sh                  # 共享配置（被脚本 source）
├── claude-wrapper.sh             # docker exec 包装器（加载环境变量）
├── reload_proxy.sh               # 热重载：改配置不重启容器
├── debug-proxy.py                # Debug 代理（请求/响应日志）
├── claude-proxy.conf.example     # 配置模板
├── compose/
│   ├── docker-compose.yml        # compose 编排（可选）
│   └── .env.example              # compose 配置模板
└── README.md                     # English docs
```

## 镜像内置工具

| 工具 | 用途 |
|---|---|
| Claude Code CLI | AI 编程助手 |
| claude-code-proxy | API 协议转换（Anthropic → OpenAI） |
| claude-code-router | 模型路由、enhancetool、多 Provider |
| debug-proxy | 请求/响应日志，调试诊断 |
| git | 版本管理 |
| curl | 网络请求 |
| build-base (gcc/make) | 编译 native 依赖 |
| less | 文件查看 |
| bash | Shell 环境 |
