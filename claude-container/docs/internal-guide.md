# Claude Code 容器使用指南

## 架构

```
你的终端
  │
  ▼
docker exec -it claude_container claude
  │
  ▼
┌────────────────────────────┐
│       Docker 容器           │
│                            │
│  Claude Code CLI           │
│       │                    │
│  claude-code-router (:3456)│
└───────┼────────────────────┘
        │
        ▼
  LLM 服务 (OpenAI 协议)
```

## 1. 安装

```bash
wget https://klx-pytorch-work-bd.bd.bcebos.com/training/yangjianbang/paddle/lockbot/claude-code-20260414-347f984.tar
docker load < claude-code-20260414-347f984.tar
```

## 2. 配置

```bash
cat > ~/claude-proxy.conf << 'EOF'
VLLM_URL=http://10.0.0.100:8000/v1
MODEL=glm-5
API_KEY=sk-placeholder
EOF
```

> 把 `VLLM_URL` 改成你的 LLM 服务地址，`MODEL` 改成部署的模型名。

## 3. 启动

```bash
docker run -d --name claude_container \
    -v ~/claude-proxy.conf:/etc/claude-proxy.conf \
    -v $(pwd):/workspace \
    -e USER_UID=$(id -u) \
    -e USER_GID=$(id -g) \
    -e TZ=Asia/Shanghai \
    claude-code:latest
```

## 4. 使用

```bash
docker exec -it claude_container claude
```

指定项目目录：

```bash
docker exec -it -w /workspace/my-project claude_container claude
```

## 5. 切换 LLM 地址

```bash
vim ~/claude-proxy.conf
docker exec claude_container reload_proxy
```

不需要重启容器。
