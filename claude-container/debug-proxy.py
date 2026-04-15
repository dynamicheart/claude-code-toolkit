#!/usr/bin/env python3
"""Debug proxy: sits between Claude Code and claude-code-proxy.
Logs requests (model, tools) and responses (content, stop_reason).
Start with DEBUG=1 in claude-proxy.conf or environment."""

import os
import sys
import json
from flask import Flask, request, Response
import requests

TARGET_PORT = os.environ.get("PROXY_PORT", "8082")
TARGET_URL = f"http://127.0.0.1:{TARGET_PORT}"
DEBUG_PORT = int(os.environ.get("DEBUG_PORT", "8083"))
DEBUG_TOOLS = os.environ.get("DEBUG_TOOLS", "1") == "1"

app = Flask(__name__)


def log(tag, msg):
    print(f"[debug-proxy] [{tag}] {msg}", flush=True)


@app.route("/v1/<path:path>", methods=["GET", "POST"])
def proxy(path):
    url = f"{TARGET_URL}/v1/{path}"

    if request.method == "GET":
        resp = requests.get(url, headers=dict(request.headers))
        return Response(resp.content, status=resp.status_code,
                        content_type=resp.headers.get("Content-Type"))

    data = request.get_json(silent=True) or {}

    # Log request
    model = data.get("model", "?")
    stream = data.get("stream", False)
    tools = data.get("tools", [])
    messages = data.get("messages", [])
    tool_names = []
    for t in tools:
        name = t.get("name") or (t.get("function") or {}).get("name") or "?"
        tool_names.append(name)

    log("REQ", f"POST /v1/{path} model={model} stream={stream} tools({len(tools)}): {tool_names}")

    # Log last message (usually tool_result or user message)
    if messages:
        last = messages[-1]
        role = last.get("role", "?")
        content = last.get("content", "")
        if isinstance(content, list):
            types = [c.get("type", "?") for c in content]
            log("REQ", f"  last_msg: role={role} blocks={types}")
            for c in content:
                if c.get("type") == "tool_result":
                    result_content = c.get("content", "")
                    if isinstance(result_content, str):
                        preview = result_content[:200]
                    else:
                        preview = json.dumps(result_content, ensure_ascii=False)[:200]
                    log("REQ", f"  tool_result[{c.get('tool_use_id', '?')}]: {preview}...")
        else:
            preview = str(content)[:200]
            log("REQ", f"  last_msg: role={role} content={preview}")

    if DEBUG_TOOLS and tools:
        log("TOOLS", json.dumps(tools, indent=2, ensure_ascii=False)[:2000])

    # Forward request
    headers = {k: v for k, v in request.headers if k.lower() != "host"}
    headers["Content-Type"] = "application/json"

    if stream:
        resp = requests.post(url, headers=headers, json=data, stream=True)
        chunks = []

        def generate():
            for chunk in resp.iter_content(chunk_size=None):
                if chunk:
                    chunks.append(chunk)
                    yield chunk
            # Log streamed response summary
            full = b"".join(chunks).decode("utf-8", errors="replace")
            # Extract tool_use from SSE data
            for line in full.split("\n"):
                if line.startswith("data: ") and "tool_use" in line:
                    log("RESP:stream", f"  tool_use chunk: {line[:300]}")
                if "stop_reason" in line:
                    log("RESP:stream", f"  {line.strip()[:300]}")

        return Response(generate(), status=resp.status_code,
                        content_type=resp.headers.get("Content-Type"))
    else:
        resp = requests.post(url, headers=headers, json=data)
        try:
            body = resp.json()
            stop = body.get("stop_reason", "?")
            content = body.get("content", [])
            types = [c.get("type", "?") for c in content] if isinstance(content, list) else []
            log("RESP", f"status={resp.status_code} stop_reason={stop} content_types={types}")
            for c in content if isinstance(content, list) else []:
                if c.get("type") == "tool_use":
                    log("RESP", f"  tool_use: {c.get('name')} input={json.dumps(c.get('input', {}), ensure_ascii=False)[:200]}")
                elif c.get("type") == "text":
                    log("RESP", f"  text: {c.get('text', '')[:200]}")
        except Exception:
            log("RESP", f"status={resp.status_code} body={resp.text[:300]}")
        return Response(resp.content, status=resp.status_code,
                        content_type=resp.headers.get("Content-Type"))


@app.route("/", methods=["GET"])
def health():
    return {"status": "debug-proxy ok"}


if __name__ == "__main__":
    log("START", f"Debug proxy :{DEBUG_PORT} -> claude-code-proxy :{TARGET_PORT}")
    app.run(host="127.0.0.1", port=DEBUG_PORT)
