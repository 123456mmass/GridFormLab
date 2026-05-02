"""Power-system AI analysis service.

Endpoints:
    GET  /health              — service status with dependency check
    GET  /metrics             — Prometheus-compatible metrics
    POST /analyze             — analyze power flow results (NR, GS)
    POST /analyze/cpf         — analyze CPF results
    POST /analyze/opf         — analyze OPF / economic dispatch
    POST /compare             — compare two solver results
    POST /report              — generate comprehensive report
    POST /ask                 — free-form question with conversation history
    POST /ask/stream          — streaming SSE response for /ask

Run:
    cd ai_service
    pip install -r requirements.txt
    python server.py
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import time
import uuid
from collections import defaultdict
from typing import Any

from openai import AsyncOpenAI
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse

import config
import models
import prompts
import utils

# ── Logging ──────────────────────────────────────────────────

logging.basicConfig(
    level=getattr(logging, config.LOG_LEVEL, logging.INFO),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("ai_service")

# ── Client ───────────────────────────────────────────────────

client = AsyncOpenAI(api_key=config.API_KEY, base_url=config.BASE_URL)

# ── Conversation store ───────────────────────────────────────

_conversations: dict[str, list[dict[str, str]]] = defaultdict(list)
MAX_CONVERSATION_TURNS = 20
CONVERSATION_TTL_SEC = 3600  # 1 hour
_conversation_timestamps: dict[str, float] = {}

# ── Metrics counters ─────────────────────────────────────────

_metrics: dict[str, int] = defaultdict(int)
_start_time = time.time()

app = FastAPI(title="Power-System AI Analyst", version="1.0.0")

# ── CORS ─────────────────────────────────────────────────────

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost",
        "http://127.0.0.1",
        "http://localhost:3000",
        "http://localhost:5173",
    ],
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"],
)


# ── Auth middleware ──────────────────────────────────────────

@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    if config.API_AUTH_TOKEN:
        auth_header = request.headers.get("Authorization", "")
        expected = f"Bearer {config.API_AUTH_TOKEN}"
        if auth_header != expected:
            return JSONResponse(
                status_code=401,
                content={"error": "Unauthorized. Provide a valid Bearer token."},
            )
    return await call_next(request)


# ── Rate limiting ────────────────────────────────────────────

_rate_limit_store: dict[str, list[float]] = {}

@app.middleware("http")
async def rate_limit_middleware(request: Request, call_next):
    if not config.API_AUTH_TOKEN:
        # No rate limiting when auth is disabled (dev mode)
        return await call_next(request)

    client_ip = request.client.host if request.client else "unknown"
    now = time.monotonic()
    window = config.RATE_LIMIT_WINDOW_SEC
    max_requests = config.RATE_LIMIT_REQUESTS

    timestamps = _rate_limit_store.get(client_ip, [])
    timestamps = [t for t in timestamps if now - t < window]
    _rate_limit_store[client_ip] = timestamps

    if len(timestamps) >= max_requests:
        logger.warning("Rate limit exceeded for %s", client_ip)
        return JSONResponse(
            status_code=429,
            content={"error": f"Rate limit exceeded ({max_requests} requests per {window}s)."},
        )

    timestamps.append(now)
    return await call_next(request)


# ── Exception handler ────────────────────────────────────────

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.exception("Unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(
        status_code=500,
        content={"error": "Internal server error"},
    )


# ── GPT helpers ──────────────────────────────────────────────

async def _call_gpt(system: str, user_msg: str) -> str:
    """Single-turn async GPT call with retry and null-output guard."""

    async def _do_call() -> str:
        resp = await client.chat.completions.create(
            model=config.MODEL,
            max_tokens=config.MAX_TOKENS,
            temperature=0.1,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user_msg},
            ],
        )
        if not resp.choices:
            logger.warning("GPT returned empty choices list")
            return ""
        content = resp.choices[0].message.content
        return content if content is not None else ""

    text = await utils.retry_gpt_call(_do_call)
    if not text:
        logger.warning("GPT returned empty response")
        return ""
    logger.debug("GPT response length: %d chars", len(text))
    return text


def _sanitize_user_input(text: str, max_len: int = 10000) -> str:
    """Truncate user-provided text to prevent prompt overflow."""
    return utils.validate_user_input(text, max_len)


# ── Endpoints ────────────────────────────────────────────────

@app.get("/health", response_model=models.HealthResponse)
async def health():
    """Health check with LLM API connectivity test."""
    api_status = "unknown"
    try:
        test_resp = await asyncio.wait_for(
            client.models.list(), timeout=5.0
        )
        api_status = "connected" if test_resp else "empty_response"
    except asyncio.TimeoutError:
        api_status = "timeout"
    except Exception as e:
        api_status = f"error: {type(e).__name__}"

    uptime_sec = time.time() - _start_time
    return models.HealthResponse(
        status="ok" if api_status == "connected" else "degraded",
        version="2.0.0",
        api_status=api_status,
        uptime_sec=round(uptime_sec, 1),
    )


@app.get("/metrics")
async def metrics():
    """Prometheus-compatible metrics endpoint."""
    lines = []
    for name, value in _metrics.items():
        safe_name = name.replace(".", "_").replace("-", "_")
        lines.append(f"nbus_{safe_name}_total {value}")
    lines.append(f"nbus_uptime_seconds {time.time() - _start_time:.1f}")
    lines.append(f"nbus_conversations_active {len(_conversations)}")
    return JSONResponse(content="\n".join(lines) + "\n")


@app.post("/analyze", response_model=models.AnalysisResponse)
async def analyze(req: models.AnalyzeRequest):
    """Analyze power flow results (NR or GS)."""
    parts = [
        f"Converged: {req.converged}",
        f"Iterations: {req.iterations}",
        f"P_loss: {req.P_loss_total:.6f} pu",
        f"Q_loss: {req.Q_loss_total:.6f} pu",
    ]
    if req.bus_data:
        parts.append("\nBus results:\n" + utils.format_bus_table(req.bus_data))
    if req.mismatch_history:
        parts.append(f"\nMismatch history (last 5): {req.mismatch_history[-5:]}")

    prompt = prompts.ANALYZE_PROMPT_TEMPLATE.format(
        method=_sanitize_user_input(req.method),
        system_name=_sanitize_user_input(req.system_name),
        num_buses=req.num_buses,
        num_lines=req.num_lines,
        result_data="\n".join(parts),
    )

    try:
        text = await _call_gpt(prompts.SYSTEM_PROMPT, prompt)
        structured = _parse_analyzer_finding(text)
        return models.AnalysisResponse(analysis=text, structured=structured)
    except Exception as e:
        logger.error("GPT call failed: %s", e)
        raise HTTPException(status_code=502, detail="AI service temporarily unavailable")


@app.post("/analyze/cpf", response_model=models.CPFAnalysisResponse)
async def analyze_cpf(req: models.CPFRequest):
    """Analyze CPF results for voltage stability."""
    prompt = prompts.CPF_PROMPT_TEMPLATE.format(
        method=_sanitize_user_input(req.method),
        system_name=_sanitize_user_input(req.system_name),
        num_buses=req.num_buses,
        target_bus=req.target_bus,
        num_points=req.num_points,
        nose_detected="Yes" if req.nose_detected else "No",
        lambda_min=req.lambda_min,
        lambda_max=req.lambda_max,
        voltage_min=req.voltage_min,
        voltage_max=req.voltage_max,
        stop_reason=_sanitize_user_input(req.stop_reason),
    )

    try:
        text = await _call_gpt(prompts.SYSTEM_PROMPT, prompt)
        structured = _parse_cpf_finding(text)
        return models.CPFAnalysisResponse(analysis=text, structured=structured)
    except Exception as e:
        logger.error("GPT call failed: %s", e)
        raise HTTPException(status_code=502, detail="AI service temporarily unavailable")


@app.post("/analyze/opf", response_model=models.OPFAnalysisResponse)
async def analyze_opf(req: models.OPFRequest):
    """Analyze economic dispatch results."""
    dispatch_lines = []
    if req.generators:
        for g in req.generators:
            dispatch_lines.append(
                f"  Gen {g.get('id', '?')}: {g.get('P_MW', 0):.2f} MW, "
                f"cost={g.get('cost', 0):.2f} $/h, limit={g.get('limit', 'free')}"
            )

    prompt = prompts.OPF_PROMPT_TEMPLATE.format(
        system_name=_sanitize_user_input(req.system_name),
        demand=req.demand_MW,
        total_cost=req.total_cost,
        lambda_cost=req.lambda_cost,
        residual=req.balance_residual,
        dispatch_table="\n".join(dispatch_lines) if dispatch_lines else "  (no generator data)",
    )

    try:
        text = await _call_gpt(prompts.SYSTEM_PROMPT, prompt)
        structured = _parse_opf_finding(text)
        return models.OPFAnalysisResponse(analysis=text, structured=structured)
    except Exception as e:
        logger.error("GPT call failed: %s", e)
        raise HTTPException(status_code=502, detail="AI service temporarily unavailable")


@app.post("/compare", response_model=models.CompareResponse)
async def compare(req: models.CompareRequest):
    """Compare two solver results side-by-side."""
    def _summarize(r: models.AnalyzeRequest) -> str:
        parts = [
            f"Converged: {r.converged}",
            f"Iterations: {r.iterations}",
            f"P_loss: {r.P_loss_total:.6f} pu",
            f"Q_loss: {r.Q_loss_total:.6f} pu",
        ]
        if r.bus_data:
            parts.append("\nBus results:\n" + utils.format_bus_table(r.bus_data))
        if r.mismatch_history:
            parts.append(f"\nMismatch history (last 5): {r.mismatch_history[-5:]}")
        return "\n".join(parts)

    prompt = prompts.COMPARE_PROMPT_TEMPLATE.format(
        method_a=_sanitize_user_input(req.method_a),
        system_a=_sanitize_user_input(req.results_a.system_name),
        buses_a=req.results_a.num_buses,
        lines_a=req.results_a.num_lines,
        data_a=_summarize(req.results_a),
        method_b=_sanitize_user_input(req.method_b),
        system_b=_sanitize_user_input(req.results_b.system_name),
        buses_b=req.results_b.num_buses,
        lines_b=req.results_b.num_lines,
        data_b=_summarize(req.results_b),
    )

    try:
        text = await _call_gpt(prompts.SYSTEM_PROMPT, prompt)
        parsed = utils.extract_json_block(text) or {}
        return models.CompareResponse(
            analysis=text,
            winner=parsed.get("winner"),
            comparison_table=parsed.get("comparison"),
        )
    except Exception as e:
        logger.error("GPT call failed: %s", e)
        raise HTTPException(status_code=502, detail="AI service temporarily unavailable")


@app.post("/report", response_model=models.ReportResponse)
async def report(req: models.ReportRequest):
    """Generate a comprehensive power system analysis report."""
    sections = []

    for method_result in req.methods:
        parts = [
            f"Method: {_sanitize_user_input(method_result.method)}",
            f"Converged: {method_result.converged}",
            f"Iterations: {method_result.iterations}",
            f"P_loss: {method_result.P_loss_total:.6f} pu",
            f"Q_loss: {method_result.Q_loss_total:.6f} pu",
        ]
        if method_result.bus_data:
            parts.append("\nBus results:\n" + utils.format_bus_table(method_result.bus_data))
        sections.append(f"### Results for {method_result.method}\n" + "\n".join(parts))

    cpf_section = "### Continuation Power Flow\nNo CPF data provided."
    if req.cpf_result:
        cpf_section = (
            f"### Continuation Power Flow\n"
            f"Target bus: {req.cpf_result.target_bus}\n"
            f"Nose detected: {req.cpf_result.nose_detected}\n"
            f"Lambda range: {req.cpf_result.lambda_min:.4f} – {req.cpf_result.lambda_max:.4f}\n"
            f"Voltage range: {req.cpf_result.voltage_min:.4f} – {req.cpf_result.voltage_max:.4f} pu\n"
            f"Stop reason: {req.cpf_result.stop_reason}"
        )

    opf_section = "### Economic Dispatch\nNo OPF data provided."
    if req.opf_result:
        gen_lines = []
        if req.opf_result.generators:
            for g in req.opf_result.generators:
                gen_lines.append(
                    f"  Gen {g.get('id', '?')}: {g.get('P_MW', 0):.2f} MW, "
                    f"cost={g.get('cost', 0):.2f} $/h"
                )
        opf_section = (
            f"### Economic Dispatch\n"
            f"Total demand: {req.opf_result.demand_MW:.2f} MW\n"
            f"Total cost: {req.opf_result.total_cost:.2f} $/h\n"
            f"Incremental cost: {req.opf_result.lambda_cost:.4f} $/MWh\n"
            f"Generator dispatch:\n" + "\n".join(gen_lines)
        )

    prompt = prompts.REPORT_PROMPT_TEMPLATE.format(
        system_name=_sanitize_user_input(req.system_name),
        results_sections="\n\n".join(sections),
        cpf_section=cpf_section,
        opf_section=opf_section,
        language=req.language,
        include_recommendations=req.include_recommendations,
    )

    try:
        text = await _call_gpt(prompts.SYSTEM_PROMPT, prompt)
        return models.ReportResponse(report=text)
    except Exception as e:
        logger.error("GPT call failed: %s", e)
        raise HTTPException(status_code=502, detail="AI service temporarily unavailable")


def _get_or_create_conversation(conv_id: str | None) -> tuple[str, list[dict[str, str]]]:
    """Get existing conversation or create a new one. Returns (conv_id, history)."""
    now = time.time()
    if conv_id and conv_id in _conversations:
        # Check TTL
        if now - _conversation_timestamps.get(conv_id, 0) < CONVERSATION_TTL_SEC:
            _conversation_timestamps[conv_id] = now
            return conv_id, _conversations[conv_id]
        else:
            del _conversations[conv_id]
    new_id = uuid.uuid4().hex[:12]
    _conversations[new_id] = []
    _conversation_timestamps[new_id] = now
    return new_id, _conversations[new_id]


def _cleanup_expired_conversations():
    """Remove expired conversations."""
    now = time.time()
    expired = [
        cid for cid, ts in _conversation_timestamps.items()
        if now - ts > CONVERSATION_TTL_SEC
    ]
    for cid in expired:
        del _conversations[cid]
        del _conversation_timestamps[cid]


@app.post("/ask", response_model=models.AskResponse)
async def ask(req: models.AskRequest):
    """Free-form question with conversation history support.

    Pass conversation_id to continue a previous conversation.
    User input is wrapped in delimiters to mitigate prompt injection.
    """
    _metrics["ask_requests"] += 1
    _cleanup_expired_conversations()

    conv_id, history = _get_or_create_conversation(req.conversation_id)

    user_msg = f"[USER_QUESTION_START]\n{_sanitize_user_input(req.question)}\n[USER_QUESTION_END]"
    if req.results_json:
        safe_json = _sanitize_user_input(req.results_json, max_len=50000)
        user_msg += f"\n\n[DATA_CONTEXT_START]\n{safe_json}\n[DATA_CONTEXT_END]"

    # Build messages with conversation history
    messages = [{"role": "system", "content": prompts.SYSTEM_PROMPT}]
    # Include last N turns from history
    recent = history[-(MAX_CONVERSATION_TURNS * 2):]
    messages.extend(recent)
    messages.append({"role": "user", "content": user_msg})

    try:
        resp = await client.chat.completions.create(
            model=config.MODEL,
            max_tokens=config.MAX_TOKENS,
            temperature=0.1,
            messages=messages,
        )
        text = resp.choices[0].message.content if resp.choices else ""
        if text is None:
            text = ""

        # Store in conversation history
        history.append({"role": "user", "content": user_msg})
        history.append({"role": "assistant", "content": text})
        if len(history) > MAX_CONVERSATION_TURNS * 2:
            history[:] = history[-(MAX_CONVERSATION_TURNS * 2):]

        return models.AskResponse(answer=text, conversation_id=conv_id)
    except Exception as e:
        logger.error("/ask GPT call failed: %s", e)
        _metrics["ask_errors"] += 1
        raise HTTPException(status_code=502, detail="AI service temporarily unavailable")


@app.post("/ask/stream")
async def ask_stream(req: models.AskRequest):
    """Streaming version of /ask using Server-Sent Events."""
    _metrics["ask_stream_requests"] += 1
    _cleanup_expired_conversations()

    conv_id, history = _get_or_create_conversation(req.conversation_id)

    user_msg = f"[USER_QUESTION_START]\n{_sanitize_user_input(req.question)}\n[USER_QUESTION_END]"
    if req.results_json:
        safe_json = _sanitize_user_input(req.results_json, max_len=50000)
        user_msg += f"\n\n[DATA_CONTEXT_START]\n{safe_json}\n[DATA_CONTEXT_END]"

    messages = [{"role": "system", "content": prompts.SYSTEM_PROMPT}]
    recent = history[-(MAX_CONVERSATION_TURNS * 2):]
    messages.extend(recent)
    messages.append({"role": "user", "content": user_msg})

    async def generate():
        full_text = ""
        try:
            stream = await client.chat.completions.create(
                model=config.MODEL,
                max_tokens=config.MAX_TOKENS,
                temperature=0.1,
                messages=messages,
                stream=True,
            )
            async for chunk in stream:
                if chunk.choices and chunk.choices[0].delta.content:
                    delta = chunk.choices[0].delta.content
                    full_text += delta
                    yield f"data: {json.dumps({'token': delta})}\n\n"
            yield f"data: {json.dumps({'done': True, 'conversation_id': conv_id})}\n\n"

            # Store in history
            history.append({"role": "user", "content": user_msg})
            history.append({"role": "assistant", "content": full_text})
            if len(history) > MAX_CONVERSATION_TURNS * 2:
                history[:] = history[-(MAX_CONVERSATION_TURNS * 2):]
        except Exception as e:
            logger.error("/ask/stream failed: %s", e)
            _metrics["ask_stream_errors"] += 1
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(generate(), media_type="text/event-stream")


# ── Structured output parsers ────────────────────────────────

def _parse_analyzer_finding(text: str) -> models.AnalyzerFinding | None:
    parsed = utils.extract_json_block(text)
    if not parsed:
        logger.debug("No JSON block found in analyzer response")
        return None
    try:
        return models.AnalyzerFinding(**parsed)
    except Exception as e:
        logger.warning("Failed to parse analyzer finding: %s", e)
        return None


def _parse_cpf_finding(text: str) -> models.CPFFinding | None:
    parsed = utils.extract_json_block(text)
    if not parsed:
        logger.debug("No JSON block found in CPF response")
        return None
    try:
        return models.CPFFinding(**parsed)
    except Exception as e:
        logger.warning("Failed to parse CPF finding: %s", e)
        return None


def _parse_opf_finding(text: str) -> models.OPFFinding | None:
    parsed = utils.extract_json_block(text)
    if not parsed:
        logger.debug("No JSON block found in OPF response")
        return None
    try:
        return models.OPFFinding(**parsed)
    except Exception as e:
        logger.warning("Failed to parse OPF finding: %s", e)
        return None


# ── Main ─────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn

    auth_status = "enabled" if config.API_AUTH_TOKEN else "DISABLED (dev mode)"
    print(f"Starting AI analysis service on http://{config.HOST}:{config.PORT}")
    print(f"Model: {config.MODEL}")
    print(f"Auth: {auth_status}")
    print(f"Docs:  http://{config.HOST}:{config.PORT}/docs")
    uvicorn.run(app, host=config.HOST, port=config.PORT, log_level=config.LOG_LEVEL.lower())
