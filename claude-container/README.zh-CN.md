# Claude Code 容器方案

一个 Docker 镜像，将 Claude Code 接入自建的 vLLM 服务（OpenAI 协议）。

[English](README.md)

## 架构

```
Claude Code → claude-code-router (:3456) → vLLM
```

开启 Debug 代理（`DEBUG=1`）：
```
Claude Code → debug-proxy (:8083) → claude-code-router (:3456) → vLLM
```

使用 [claude-code-router](https://github.com/musistudio/claude-code-router) 作为后端，内置 `enhancetool` 对 tool_use 做容错。

## 快速开始

### 1. 创建配置文件

```bash
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
    -e TZ=Asia/Shanghai \
    ghcr.io/dynamicheart/claude-code-toolkit/claude-code:latest
```

### 3. 使用

```bash
docker exec -it claude_container claude

# 指定项目目录
docker exec -it -w /workspace/my-project claude_container claude
```

## 热重载（不删容器）

```bash
vim ~/claude-proxy.conf
docker exec claude_container reload_proxy
```

## 配置说明

### 配置文件参数

| 变量 | 默认值 | 说明 |
|---|---|---|
| `VLLM_URL` | *(必填)* | vLLM 服务地址（OpenAI 协议） |
| `MODEL` | `glm-5` | vLLM 上的模型名称 |
| `API_KEY` | `sk-placeholder` | API Key（vLLM 不需要认证时保持默认） |
| `ROUTER_CONFIG` | *(无)* | 自定义 claude-code-router 配置文件路径 |
| `DEBUG` | `0` | 设为 `1` 开启 debug 代理 |
| `DEBUG_FULL` | `0` | 设为 `1` 记录完整请求/响应 body |

### 环境变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `USER_UID` | `1000` | 宿主机 UID，避免文件权限问题 |
| `USER_GID` | `1000` | 宿主机 GID，避免文件权限问题 |
| `TZ` | `UTC` | 时区（如 `Asia/Shanghai`、`America/New_York`） |
| `PROXY_CONF` | `/etc/claude-proxy.conf` | 配置文件路径（可覆盖） |

## 自定义路由配置

需要高级路由（多模型、think/background 分流、多 Provider）时，挂载自定义 [claude-code-router 配置](https://github.com/musistudio/claude-code-router)：

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

在 conf 文件中设置 `ROUTER_CONFIG=/etc/claude-router-config.json` 即可。

## Debug 代理

排查 tool_use 失败和流式传输问题：

```bash
# 在配置中开启
echo "DEBUG=1" >> ~/claude-proxy.conf
docker exec claude_container reload_proxy

# 查看日志
docker exec claude_container tail -f /var/log/debug-proxy.log

# 完整请求/响应（需 DEBUG_FULL=1）
docker exec claude_container cat /var/log/debug-proxy-full.log
```

## 常见场景

### 挂载多个项目目录

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
├── entrypoint.sh                 # UID/GID 映射 + 自动启动 router
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
| claude-code-router | 模型路由 + enhancetool（tool_use 容错） |
| debug-proxy | 请求/响应日志，调试诊断 |
| git | 版本管理 |
| curl | 网络请求 |
| build-base (gcc/make) | 编译 native 依赖 |
| less | 文件查看 |
| bash | Shell 环境 |
