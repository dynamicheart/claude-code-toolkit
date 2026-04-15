# Claude Code Toolkit

[![Docker](https://img.shields.io/badge/ghcr.io-dynamicheart%2Fclaude--code--toolkit%2Fclaude--code-blue)](https://github.com/dynamicheart/claude-code-toolkit/pkgs/container/claude-code-toolkit%2Fclaude-code)

Connect Claude Code to self-hosted LLM services (vLLM, SGLang, or any OpenAI-compatible endpoint) for offline development and testing model agent capabilities.

## Architecture

```
Claude Code → claude-code-router (:3456) → LLM Provider (OpenAI protocol)
```

With debug proxy (`DEBUG=1`):
```
Claude Code → debug-proxy (:8083) → ccr (:3456) → debug-proxy (:8084) → LLM Provider
               [cc2ccr.log]                         [ccr2provider.log]
```

## claude-container

One Docker image with Claude Code + [claude-code-router](https://github.com/musistudio/claude-code-router), connecting to any OpenAI-compatible endpoint.

See [claude-container/README.md](claude-container/README.md) | [中文文档](claude-container/README.zh-CN.md)
