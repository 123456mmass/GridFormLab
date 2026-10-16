# MCP stdio server for the user's search gateway (birdsphichitchai.dev).
# Zero external dependencies: Python stdlib only. Tools: web_search, web_fetch.
# Config: GATEWAY_BASE + GATEWAY_TOKEN come from the environment (.mcp.json).
import json, os, sys, urllib.request, urllib.error

BASE = os.environ.get("GATEWAY_BASE", "https://gateway.birdsphichitchai.dev").rstrip("/")
TOKEN = os.environ.get("GATEWAY_TOKEN", "")
NAME = "birds-gateway"
VERSION = "1.0.0"

def _post(path, payload):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            # The gateway sits behind Cloudflare and rejects default
            # Python-urllib UA (error 1010). curl passes; mirror its UA.
            "User-Agent": os.environ.get("GATEWAY_UA", "curl/8.6.0"),
            "Authorization": "Bearer " + TOKEN,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:2000]
        raise RuntimeError(f"HTTP {e.code} from gateway: {body}")
    except Exception as e:  # noqa: BLE001 - report any transport error to the model
        raise RuntimeError(f"gateway call failed: {e}")

def t_web_search(args):
    q = args.get("query")
    if not q:
        raise RuntimeError("query is required")
    payload = {
        "model": args.get("model", "searxng"),
        "query": q,
        "search_type": args.get("search_type", "web"),
        "max_results": int(args.get("max_results", 5)),
    }
    return _post("/v1/search", payload)

def t_web_fetch(args):
    u = args.get("url")
    if not u:
        raise RuntimeError("url is required")
    payload = {
        "model": args.get("model", "local-fetch"),
        "url": u,
        "format": args.get("format", "markdown"),
        "max_characters": int(args.get("max_characters", 0)),
    }
    return _post("/v1/web/fetch", payload)

TOOLS = {
    "web_search": t_web_search,
    "web_fetch": t_web_fetch,
}

TOOL_SPECS = [
    {
        "name": "web_search",
        "description": "Web search via the user's searxng gateway. Returns JSON results with titles/urls/snippets. Use for current events, standards references, and any question needing external sources.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search query text"},
                "max_results": {"type": "integer", "description": "Number of results (default 5)", "default": 5},
                "search_type": {"type": "string", "description": "web (default) or news", "default": "web"},
            },
            "required": ["query"],
        },
    },
    {
        "name": "web_fetch",
        "description": "Fetch a URL as markdown via the user's fetch gateway. Use to read search results or documentation pages in full.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "url": {"type": "string", "description": "URL to fetch"},
                "format": {"type": "string", "description": "markdown (default) or text", "default": "markdown"},
                "max_characters": {"type": "integer", "description": "0 = no limit", "default": 0},
            },
            "required": ["url"],
        },
    },
]

def _ok(req_id, result):
    return {"jsonrpc": "2.0", "id": req_id, "result": result}

def _err(req_id, code, msg):
    return {"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": msg}}

def handle(msg):
    method = msg.get("method", "")
    rid = msg.get("id")
    if method == "initialize":
        return _ok(rid, {
            "protocolVersion": msg.get("params", {}).get("protocolVersion", "2024-11-05"),
            "capabilities": {"tools": {}},
            "serverInfo": {"name": NAME, "version": VERSION},
        })
    if method == "ping":
        return _ok(rid, {})
    if method == "tools/list":
        return _ok(rid, {"tools": TOOL_SPECS})
    if method == "tools/call":
        p = msg.get("params", {}) or {}
        name = p.get("name", "")
        args = p.get("arguments", {}) or {}
        fn = TOOLS.get(name)
        if fn is None:
            return _err(rid, -32602, f"unknown tool: {name}")
        try:
            text = fn(args)
            return _ok(rid, {"content": [{"type": "text", "text": text}], "isError": False})
        except Exception as e:  # noqa: BLE001 - surface tool errors as tool results
            return _ok(rid, {"content": [{"type": "text", "text": f"ERROR: {e}"}], "isError": True})
    if rid is None:
        return None  # notification: no response
    return _err(rid, -32601, f"method not found: {method}")

def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:  # noqa: BLE001 - older stdio may lack reconfigure
        pass
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        out = handle(msg)
        if out is not None:
            try:
                sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")
                sys.stdout.flush()
            except (BrokenPipeError, OSError):
                break  # host closed the pipe; exit quietly

if __name__ == "__main__":
    main()
