#!/usr/bin/env python3
"""Debug proxy: transparent HTTP proxy that logs requests and responses.
Can sit at any layer: Claude Code ↔ router, or router ↔ LLM provider.
Start with DEBUG=1 in claude-proxy.conf or environment."""

import os
import json
from flask import Flask, request, Response
import requests

# TARGET_URL: where to forward requests (supports remote hosts)
# If TARGET_URL is set, use it directly; otherwise construct from PROXY_PORT
TARGET_URL = os.environ.get("TARGET_URL", f"http://127.0.0.1:{os.environ.get('PROXY_PORT', '3456')}")
DEBUG_PORT = int(os.environ.get("DEBUG_PORT", "8083"))
DEBUG_TOOLS = os.environ.get("DEBUG_TOOLS", "1") == "1"
LAYER_TAG = os.environ.get("LAYER_TAG", "anthropic")  # "anthropic" or "openai"

LOG_FILE = os.environ.get("LOG_FILE", "/var/log/cc2ccr.log")
FULL_LOG = os.environ.get("FULL_LOG", "/var/log/cc2ccr-full.log")

app = Flask(__name__)


def log(tag, msg):
    print(f"[debug-proxy:{LAYER_TAG}] [{tag}] {msg}", flush=True)


def log_full(tag, data):
    """Write complete data to the full log file."""
    if isinstance(data, str):
        text = data
    elif isinstance(data, (dict, list)):
        try:
            text = json.dumps(data, indent=2, ensure_ascii=False)
        except Exception:
            text = str(data)
    else:
        text = str(data)
    with open(FULL_LOG, "a") as f:
        f.write(f"\n{'='*80}\n[{tag}]\n{text}\n")


def parse_sse_event(line):
    """Parse a single SSE data line into a dict, or None."""
    if not line.startswith("data: "):
        return None
    payload = line[6:].strip()
    if payload == "[DONE]":
        return None
    try:
        return json.loads(payload)
    except Exception:
        return None


def log_stream_event(event):
    """Log a parsed SSE event with structured info."""
    etype = event.get("type", "?")

    if etype == "message_start":
        msg = event.get("message", {})
        log("SSE", f"message_start id={msg.get('id', '?')} model={msg.get('model', '?')}")

    elif etype == "content_block_start":
        idx = event.get("index", "?")
        block = event.get("content_block", {})
        btype = block.get("type", "?")
        if btype == "tool_use":
            log("SSE", f"content_block_start[{idx}] type=tool_use name={block.get('name', '?')} id={block.get('id', '?')}")
        elif btype == "text":
            log("SSE", f"content_block_start[{idx}] type=text")
        else:
            log("SSE", f"content_block_start[{idx}] type={btype}")

    elif etype == "content_block_delta":
        idx = event.get("index", "?")
        delta = event.get("delta", {})
        dtype = delta.get("type", "?")
        if dtype == "input_json_delta":
            partial = delta.get("partial_json", "")
            log("SSE", f"content_block_delta[{idx}] input_json: {partial[:200]}")
        elif dtype == "text_delta":
            text = delta.get("text", "")
            log("SSE", f"content_block_delta[{idx}] text: {text[:200]}")
        else:
            log("SSE", f"content_block_delta[{idx}] type={dtype}")

    elif etype == "content_block_stop":
        log("SSE", f"content_block_stop[{event.get('index', '?')}]")

    elif etype == "message_delta":
        delta = event.get("delta", {})
        stop = delta.get("stop_reason", "?")
        usage = event.get("usage", {})
        log("SSE", f"message_delta stop_reason={stop} output_tokens={usage.get('output_tokens', '?')}")

    elif etype == "message_stop":
        log("SSE", "message_stop")

    elif etype == "ping":
        pass  # ignore pings

    else:
        log("SSE", f"type={etype} {json.dumps(event, ensure_ascii=False)[:200]}")


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
    log_full("REQ", data)

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

        # Buffer for SSE line reassembly across chunks
        line_buf = ""

        def generate():
            nonlocal line_buf
            for chunk in resp.iter_content(chunk_size=None):
                if not chunk:
                    continue
                yield chunk

                # Real-time SSE event parsing and logging
                text = chunk.decode("utf-8", errors="replace")
                log_full("SSE:chunk", text)
                line_buf += text
                while "\n" in line_buf:
                    line, line_buf = line_buf.split("\n", 1)
                    line = line.strip()
                    if not line:
                        continue
                    event = parse_sse_event(line)
                    if event:
                        log_stream_event(event)

            # Flush remaining buffer
            if line_buf.strip():
                event = parse_sse_event(line_buf.strip())
                if event:
                    log_stream_event(event)

            log("SSE", "--- stream ended ---")

        return Response(generate(), status=resp.status_code,
                        content_type=resp.headers.get("Content-Type"))
    else:
        resp = requests.post(url, headers=headers, json=data)
        try:
            body = resp.json()
            log_full("RESP", body)
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
            log_full("RESP:raw", resp.text)
        return Response(resp.content, status=resp.status_code,
                        content_type=resp.headers.get("Content-Type"))


@app.route("/", methods=["GET"])
def health():
    return {"status": "debug-proxy ok"}


if __name__ == "__main__":
    log("START", f"Debug proxy [layer={LAYER_TAG}] :{DEBUG_PORT} -> {TARGET_URL}")
    log("START", f"Full logging -> {FULL_LOG}")
    app.run(host="127.0.0.1", port=DEBUG_PORT)
