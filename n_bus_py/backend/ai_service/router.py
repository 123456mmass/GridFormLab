"""AI analysis router — mounted at /ai in main FastAPI app.

Endpoints:
    GET  /ai/health
    GET  /ai/metrics
    POST /ai/analyze
    POST /ai/analyze/cpf
    POST /ai/analyze/opf
    POST /ai/compare
    POST /ai/report
    POST /ai/ask
    POST /ai/ask/stream
"""

from __future__ import annotations

import asyncio
import base64
import csv
import json
import logging
import re
import time
import uuid
import yaml
from collections import defaultdict
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, UploadFile, File, Form
from fastapi.responses import JSONResponse, StreamingResponse
from google import genai
from google.genai import types
from openai import AsyncOpenAI

from . import config, models, prompts, utils
from auth.dependencies import get_current_user

logger = logging.getLogger("ai_service")

gemini_client = genai.Client(api_key=config.GEMINI_API_KEY) if config.GEMINI_API_KEY else None

deepseek_client = AsyncOpenAI(api_key=config.DEEPSEEK_API_KEY, base_url=config.DEEPSEEK_BASE_URL) if config.DEEPSEEK_API_KEY else None
mercury_client = AsyncOpenAI(api_key=config.MERCURY_API_KEY, base_url=config.MERCURY_BASE_URL) if config.MERCURY_API_KEY else None
nvidia_client = AsyncOpenAI(api_key=config.NVIDIA_API_KEY, base_url=config.NVIDIA_BASE_URL) if config.NVIDIA_API_KEY else None

router = APIRouter(prefix="/ai")

# ── Metrics ──────────────────────────────────────────────────

_metrics: dict[str, int] = defaultdict(int)
_start_time = time.time()
_rate_limit_store: dict[str, list[float]] = {}  # deprecated, will be removed
_CASE_NAME_RE = re.compile(r"^[a-z0-9_][a-z0-9_-]{0,199}$")
_IMAGE_MIME_TYPES = {
    "image/png",
    "image/jpeg",
    "image/webp",
    "image/heic",
    "image/heif",
}


# ── Dependencies ────────────────────────────────────────────

async def _check_auth(request: Request):
    """Validate JWT from Authorization header. Returns None on success, JSONResponse on failure."""
    from auth.utils import decode_token
    from db.operations import get_user_by_id
    import jwt as pyjwt
    
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return JSONResponse(status_code=401, content={"error": "Not authenticated"})
    try:
        payload = decode_token(auth_header.removeprefix("Bearer "))
        if payload.get("type") != "access":
            return JSONResponse(status_code=401, content={"error": "Not an access token"})
    except pyjwt.ExpiredSignatureError:
        return JSONResponse(status_code=401, content={"error": "Token expired"})
    except pyjwt.InvalidTokenError:
        return JSONResponse(status_code=401, content={"error": "Invalid token"})
    return None


async def _check_rate_limit(request: Request):
    return None


# ── Gemini helpers ──────────────────────────────────────────────

async def _call_gemini(system: str, user_msg: str) -> str:
    if not gemini_client:
        raise ValueError("Gemini client not configured")
    async def _do_call() -> str:
        resp = await gemini_client.aio.models.generate_content(
            model=config.MODEL,
            contents=user_msg,
            config=types.GenerateContentConfig(
                system_instruction=system,
                max_output_tokens=config.MAX_TOKENS,
                temperature=0.1
            )
        )
        return resp.text if resp.text else ""

    text = await utils.retry_gpt_call(_do_call)
    if not text:
        logger.warning("Gemini returned empty response")
        return ""
    return text


async def _ocr_image_with_gemini(content: bytes, mime_type: str) -> str:
    if not gemini_client:
        raise ValueError("Gemini client not configured for OCR")

    async def _do_call() -> str:
        resp = await gemini_client.aio.models.generate_content(
            model=config.OCR_MODEL,
            contents=[
                types.Part.from_bytes(data=content, mime_type=mime_type),
                (
                    "OCR this power-system case image. Return only the visible text and table "
                    "values, preserving row order and line breaks. Do not explain."
                ),
            ],
            config=types.GenerateContentConfig(
                max_output_tokens=min(config.MAX_TOKENS, 8192),
                temperature=0,
            ),
        )
        return resp.text if resp.text else ""

    text = await utils.retry_gpt_call(_do_call)
    if not text:
        raise ValueError("Gemini OCR returned empty text")
    return text


async def _ocr_image_with_nvidia(content: bytes, mime_type: str) -> str:
    if not nvidia_client:
        raise ValueError("NVIDIA client not configured for OCR")

    image_data = base64.b64encode(content).decode("ascii")
    image_url = f"data:{mime_type};base64,{image_data}"

    async def _do_call() -> str:
        resp = await nvidia_client.chat.completions.create(
            model=config.OCR_MODEL,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": (
                                "OCR this power-system case image. Return only the visible text "
                                "and table values, preserving row order and line breaks. Do not explain."
                            ),
                        },
                        {"type": "image_url", "image_url": {"url": image_url}},
                    ],
                }
            ],
            temperature=0.2,
            top_p=0.95,
            max_tokens=min(config.MAX_TOKENS, 65536),
            extra_body={
                "chat_template_kwargs": {"enable_thinking": True},
                "reasoning_budget": min(4096, config.MAX_TOKENS),
            },
        )
        return resp.choices[0].message.content or ""

    text = await utils.retry_gpt_call(_do_call)
    if not text:
        raise ValueError("NVIDIA OCR returned empty text")
    return text


async def _ocr_image(content: bytes, mime_type: str) -> str:
    if nvidia_client:
        return await _ocr_image_with_nvidia(content, mime_type)
    return await _ocr_image_with_gemini(content, mime_type)


async def _call_nvidia_import(system: str, user_msg: str) -> str:
    """Use NVIDIA reasoning model for file→structured-data extraction."""
    if not nvidia_client:
        raise ValueError("NVIDIA client not configured")

    async def _do_call() -> str:
        resp = await nvidia_client.chat.completions.create(
            model=config.IMPORT_MODEL,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user_msg},
            ],
            temperature=0.2,
            top_p=0.95,
            max_tokens=min(config.MAX_TOKENS, 65536),
            extra_body={
                "chat_template_kwargs": {"enable_thinking": True},
                "reasoning_budget": 16384,
            },
        )
        return resp.choices[0].message.content or ""

    text = await utils.retry_gpt_call(_do_call)
    if not text:
        raise ValueError("NVIDIA import returned empty text")
    return text

# ── OpenAI helpers ──────────────────────────────────────────────

async def _call_gpt(system: str, user_msg: str, model_name: str = None) -> str:
    target = (model_name or config.MODEL).lower()
    if target.startswith("mercury"):
        client_to_use = mercury_client
    elif target.startswith("nvidia") or target.startswith("openai/") or target.startswith("qwen/"):
        client_to_use = nvidia_client
    else:
        client_to_use = deepseek_client
    if not client_to_use:
        raise ValueError("OpenAI-compatible client not configured")

    async def _do_call() -> str:
        resp = await client_to_use.chat.completions.create(
            model=model_name or config.MODEL,
            max_tokens=config.MAX_TOKENS,
            temperature=0.1,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user_msg},
            ],
        )
        if not resp.choices:
            return ""
        content = resp.choices[0].message.content
        return content if content is not None else ""

    text = await utils.retry_gpt_call(_do_call)
    if not text:
        logger.warning("GPT returned empty response")
        return ""
    return text


def _sanitize(text: str, max_len: int = 10000) -> str:
    return utils.validate_user_input(text, max_len)


async def _get_or_create_session(
    user_id: str,
    session_type: str,
    conv_id: str | None = None,
) -> tuple[str, list[dict[str, str]]]:
    """DB-backed session manager. Loads existing or creates a new session."""
    from db import operations as db_ops

    if conv_id:
        messages = await db_ops.get_conversation(conv_id)
        if messages is not None:
            return conv_id, messages
    new_id = uuid.uuid4().hex[:12]
    return new_id, []


async def _save_session(
    conv_id: str,
    user_id: str,
    session_type: str,
    messages: list[dict],
    title: str | None = None,
    persona_id: int | None = None,
    analysis_context: dict | None = None,
):
    """Persist session to DB (fire-and-forget)."""
    from db import operations as db_ops

    try:
        await db_ops.save_conversation(
            conv_id=conv_id,
            user_id=user_id,
            session_type=session_type,
            messages=messages,
            title=title,
            persona_id=persona_id,
            analysis_context=analysis_context,
        )
    except Exception:
        logger.warning("Failed to persist conversation (DB may be unavailable)", exc_info=True)


def _require_ai():
    if not config.AI_ENABLED:
        raise HTTPException(503, "AI service disabled — set an AI API key in .env")


def _extract_user_id(request: Request) -> str:
    """Extract user_id from JWT in Authorization header."""
    from auth.utils import decode_token
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        try:
            payload = decode_token(auth.removeprefix("Bearer "))
            return payload.get("sub", "unknown")
        except Exception:
            pass
    return "unknown"


async def _build_system_prompt(user_id: str, persona_id: int | None = None) -> str:
    """Build system prompt with optional persona overlay."""
    base = prompts.SYSTEM_PROMPT
    persona = None
    if persona_id:
        from db import operations as db_ops
        persona = await db_ops.get_persona_by_id(persona_id, user_id)
    if not persona:
        try:
            from db import operations as db_ops
            persona = await db_ops.get_default_persona(user_id)
        except Exception:
            pass
    if not persona:
        return base

    parts = [base]
    if persona.get("custom_prompt"):
        parts.append(f"\n\n[USER PERSONA INSTRUCTIONS]\n{persona['custom_prompt']}")
    tone = persona.get("ai_tone")
    style = persona.get("ai_style")
    lang = persona.get("language_preference")
    if any([tone, style, lang]):
        meta = [f"Tone: {tone or 'natural'}", f"Style: {style or 'conversational'}"]
        if lang: meta.append(f"Language: {'Thai' if lang == 'th' else 'English'}")
        parts.append(f"\n\n[RESPONSE PREFERENCES]\n{'; '.join(meta)}.")
    return "\n".join(parts)


def _safe_case_paths(case_name: str) -> tuple[Path, Path]:
    normalized = case_name.strip().lower()
    if not _CASE_NAME_RE.fullmatch(normalized):
        raise HTTPException(
            422,
            "case_name must contain only lowercase letters, numbers, underscores, or hyphens",
        )

    cases_dir = Path(__file__).resolve().parents[1] / "cases"
    cases_dir.mkdir(parents=True, exist_ok=True)
    base = (cases_dir / normalized).resolve()
    if base.parent != cases_dir.resolve():
        raise HTTPException(422, "Invalid case_name path")
    return base.with_suffix(".yaml"), base.with_suffix(".csv")


# ── Endpoints ────────────────────────────────────────────────

@router.get("/health", response_model=models.HealthResponse)
async def health():
    api_status = "unknown"
    try:
        if gemini_client:
            # simple check
            api_status = "connected"
        elif deepseek_client or mercury_client:
            api_status = "connected"
        else:
            api_status = "not_configured"
    except asyncio.TimeoutError:
        api_status = "timeout"
    except Exception as e:
        api_status = f"error: {type(e).__name__}"

    return models.HealthResponse(
        status="ok" if api_status == "connected" else "degraded",
        api_status=api_status,
        uptime_sec=round(time.time() - _start_time, 1),
    )


@router.get("/metrics")
async def metrics():
    lines = []
    for name, value in _metrics.items():
        safe_name = name.replace(".", "_").replace("-", "_")
        lines.append(f"nbus_{safe_name}_total {value}")
    lines.append(f"nbus_uptime_seconds {time.time() - _start_time:.1f}")
    lines.append(f"nbus_conversations_active 0")  # now DB-backed
    return JSONResponse(content="\n".join(lines) + "\n")


@router.post("/analyze", response_model=models.AnalysisResponse)
async def analyze(req: models.AnalyzeRequest, request: Request):
    _require_ai()
    if auth_err := await _check_auth(request):
        return auth_err
    if rate_err := await _check_rate_limit(request):
        return rate_err

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
        method=_sanitize(req.method),
        system_name=_sanitize(req.system_name),
        num_buses=req.num_buses,
        num_lines=req.num_lines,
        result_data="\n".join(parts),
    )

    try:
        text = await _call_gemini(prompts.SYSTEM_PROMPT, prompt)
        parsed = utils.extract_json_block(text)
        structured = models.AnalyzerFinding(**parsed) if parsed else None
        return models.AnalysisResponse(analysis=text, structured=structured)
    except Exception as e:
        logger.error("analyze GPT call failed: %s", e)
        raise HTTPException(502, "AI service temporarily unavailable")


@router.post("/analyze/cpf", response_model=models.CPFAnalysisResponse)
async def analyze_cpf(req: models.CPFRequest, request: Request):
    _require_ai()
    if auth_err := await _check_auth(request):
        return auth_err
    if rate_err := await _check_rate_limit(request):
        return rate_err

    prompt = prompts.CPF_PROMPT_TEMPLATE.format(
        method=_sanitize(req.method),
        system_name=_sanitize(req.system_name),
        num_buses=req.num_buses,
        target_bus=req.target_bus,
        num_points=req.num_points,
        nose_detected="Yes" if req.nose_detected else "No",
        lambda_min=req.lambda_min,
        lambda_max=req.lambda_max,
        voltage_min=req.voltage_min,
        voltage_max=req.voltage_max,
        stop_reason=_sanitize(req.stop_reason),
    )

    try:
        text = await _call_gemini(prompts.SYSTEM_PROMPT, prompt)
        parsed = utils.extract_json_block(text)
        structured = models.CPFFinding(**parsed) if parsed else None
        return models.CPFAnalysisResponse(analysis=text, structured=structured)
    except Exception as e:
        logger.error("analyze/cpf GPT call failed: %s", e)
        raise HTTPException(502, "AI service temporarily unavailable")


@router.post("/analyze/opf", response_model=models.OPFAnalysisResponse)
async def analyze_opf(req: models.OPFRequest, request: Request):
    _require_ai()
    if auth_err := await _check_auth(request):
        return auth_err
    if rate_err := await _check_rate_limit(request):
        return rate_err

    dispatch_lines = []
    if req.generators:
        for g in req.generators:
            dispatch_lines.append(
                f"  Gen {g.get('id', '?')}: {g.get('P_MW', 0):.2f} MW, "
                f"cost={g.get('cost', 0):.2f} $/h, limit={g.get('limit', 'free')}"
            )

    prompt = prompts.OPF_PROMPT_TEMPLATE.format(
        system_name=_sanitize(req.system_name),
        demand=req.demand_MW,
        total_cost=req.total_cost,
        lambda_cost=req.lambda_cost,
        residual=req.balance_residual,
        dispatch_table="\n".join(dispatch_lines) if dispatch_lines else "  (no generator data)",
    )

    try:
        text = await _call_gemini(prompts.SYSTEM_PROMPT, prompt)
        parsed = utils.extract_json_block(text)
        structured = models.OPFFinding(**parsed) if parsed else None
        return models.OPFAnalysisResponse(analysis=text, structured=structured)
    except Exception as e:
        logger.error("analyze/opf GPT call failed: %s", e)
        raise HTTPException(502, "AI service temporarily unavailable")


@router.post("/compare", response_model=models.CompareResponse)
async def compare(req: models.CompareRequest, request: Request):
    _require_ai()
    if auth_err := await _check_auth(request):
        return auth_err
    if rate_err := await _check_rate_limit(request):
        return rate_err

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
        method_a=_sanitize(req.method_a),
        system_a=_sanitize(req.results_a.system_name),
        buses_a=req.results_a.num_buses,
        lines_a=req.results_a.num_lines,
        data_a=_summarize(req.results_a),
        method_b=_sanitize(req.method_b),
        system_b=_sanitize(req.results_b.system_name),
        buses_b=req.results_b.num_buses,
        lines_b=req.results_b.num_lines,
        data_b=_summarize(req.results_b),
    )

    try:
        text = await _call_gemini(prompts.SYSTEM_PROMPT, prompt)
        parsed = utils.extract_json_block(text) or {}
        return models.CompareResponse(
            analysis=text,
            winner=parsed.get("winner"),
            comparison_table=parsed.get("comparison"),
        )
    except Exception as e:
        logger.error("compare GPT call failed: %s", e)
        raise HTTPException(502, "AI service temporarily unavailable")


@router.post("/report", response_model=models.ReportResponse)
async def report(req: models.ReportRequest, request: Request):
    _require_ai()
    if auth_err := await _check_auth(request):
        return auth_err
    if rate_err := await _check_rate_limit(request):
        return rate_err

    sections = []
    for mr in req.methods:
        parts = [
            f"Method: {_sanitize(mr.method)}",
            f"Converged: {mr.converged}",
            f"Iterations: {mr.iterations}",
            f"P_loss: {mr.P_loss_total:.6f} pu",
            f"Q_loss: {mr.Q_loss_total:.6f} pu",
        ]
        if mr.bus_data:
            parts.append("\nBus results:\n" + utils.format_bus_table(mr.bus_data))
        sections.append(f"### Results for {mr.method}\n" + "\n".join(parts))

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
        system_name=_sanitize(req.system_name),
        results_sections="\n\n".join(sections),
        cpf_section=cpf_section,
        opf_section=opf_section,
        language=req.language,
        include_recommendations=req.include_recommendations,
    )

    try:
        text = await _call_gemini(prompts.SYSTEM_PROMPT, prompt)
        return models.ReportResponse(report=text)
    except Exception as e:
        logger.error("report GPT call failed: %s", e)
        raise HTTPException(502, "AI service temporarily unavailable")


# ── File processing helpers ───────────────────────────────────

async def _process_uploaded_file(file: UploadFile) -> dict:
    """Process an uploaded file. Returns dict with type, text_content, image_base64, mime_type."""
    content = await file.read()
    filename = file.filename or "unknown"
    mime = file.content_type or "application/octet-stream"
    result = {"filename": filename, "mime_type": mime}

    # PDF
    if filename.lower().endswith(".pdf") or mime == "application/pdf":
        try:
            from pypdf import PdfReader
            from io import BytesIO
            reader = PdfReader(BytesIO(content))
            text = "\n".join(page.extract_text() or "" for page in reader.pages)
            result["type"] = "text"
            result["text_content"] = f"[FILE: {filename}]\n{text}\n[/FILE: {filename}]"
            return result
        except Exception as e:
            logger.warning("PDF extraction failed for %s: %s", filename, e)
            result["type"] = "text"
            result["text_content"] = f"[FILE: {filename} (binary PDF, could not extract)]"
            return result

    # Images
    if mime in _IMAGE_MIME_TYPES or any(filename.lower().endswith(ext) for ext in (".png", ".jpg", ".jpeg", ".webp", ".heic", ".heif")):
        b64 = base64.b64encode(content).decode("ascii")
        result["type"] = "image"
        result["image_base64"] = b64
        return result

    # Text / CSV / MD / JSON / YAML etc.
    try:
        text = content.decode("utf-8", errors="ignore")
        ext = Path(filename).suffix.lower()
        label = {".csv": "CSV", ".json": "JSON", ".yaml": "YAML", ".yml": "YAML", ".md": "Markdown"}.get(ext, "text")
        result["type"] = "text"
        result["text_content"] = f"[{label} FILE: {filename}]\n{text[:20000]}\n[/{label} FILE: {filename}]"
        return result
    except Exception:
        result["type"] = "text"
        result["text_content"] = f"[FILE: {filename} (binary, could not read)]"
        return result


def _is_vision_model(model: str) -> bool:
    """Check if model supports native image vision."""
    return any(model.startswith(p) for p in ("nvidia/", "openai/", "qwen/"))


async def _build_user_content(
    question: str,
    results_json: str | None,
    files: list[UploadFile],
    target_model: str,
) -> tuple[str, list[dict] | None]:
    """
    Build user message content from question, results, and files.
    Returns (user_msg_text, vision_content_array).
    vision_content_array is None for text-only models.
    """
    file_parts_text: list[str] = []
    image_parts: list[dict] = []
    use_vision = _is_vision_model(target_model) and files

    for f in files:
        processed = await _process_uploaded_file(f)
        if processed.get("type") == "image" and use_vision:
            image_parts.append({
                "type": "image_url",
                "image_url": {"url": f"data:{processed['mime_type']};base64,{processed['image_base64']}"},
            })
        elif processed.get("type") == "text":
            file_parts_text.append(processed["text_content"])
        elif processed.get("type") == "image":
            # Image but model doesn't support vision — OCR it
            b64_data = base64.b64decode(processed["image_base64"])
            ocr_text = await _ocr_image(b64_data, processed["mime_type"])
            file_parts_text.append(f"[OCR from {processed['filename']}]\n{ocr_text}\n[/OCR]")

    # Build the full text
    clean_question = _sanitize(question)
    text_msg = f"[USER_QUESTION_START]\n{clean_question}\n[USER_QUESTION_END]"
    if results_json:
        text_msg += f"\n\n[DATA_CONTEXT_START]\n{_sanitize(results_json, max_len=50000)}\n[DATA_CONTEXT_END]"
    if file_parts_text:
        text_msg += "\n\n" + "\n\n".join(file_parts_text)

    if use_vision and image_parts:
        # Build multimodal content array
        vision_content = [{"type": "text", "text": text_msg}]
        vision_content.extend(image_parts)
        return text_msg, vision_content

    return text_msg, None


# ── Ask endpoints ────────────────────────────────────────────

def _parse_ask_fields(
    question: str = Form(""),
    results_json: str | None = Form(None),
    conversation_id: str | None = Form(None),
    model: str | None = Form(None),
    persona_id: int | None = Form(None),
    session_title: str | None = Form(None),
):
    """Shared Form-based parsing for ask endpoints — allows multipart + files."""
    return {
        "question": question,
        "results_json": results_json,
        "conversation_id": conversation_id,
        "model": model,
        "persona_id": persona_id,
        "session_title": session_title,
    }


async def _run_ask(
    fields: dict,
    user_id: str,
    session_type: str,
    conv_id: str,
    history: list[dict],
    system_prompt: str,
    target_model: str,
    user_msg: str,
    vision_content: list[dict] | None,
) -> str:
    """Run the actual AI call — used by both /ask and /ask/stream."""
    if target_model.startswith("gemini"):
        if not gemini_client:
            raise ValueError("Gemini API is not configured.")
        gemini_history = []
        for msg in history:
            role = "model" if msg["role"] == "assistant" else "user"
            gemini_history.append({"role": role, "parts": [{"text": msg["content"]}]})
        # Gemini doesn't support vision content array — use text only
        gemini_history.append({"role": "user", "parts": [{"text": user_msg}]})

        resp = await gemini_client.aio.models.generate_content(
            model=target_model,
            contents=gemini_history,
            config=types.GenerateContentConfig(
                system_instruction=system_prompt,
                max_output_tokens=config.MAX_TOKENS,
                temperature=0.1,
            ),
        )
        return resp.text if resp.text else ""
    else:
        client_to_use = None
        if target_model.startswith("deepseek"):
            client_to_use = deepseek_client
        elif target_model.startswith("mercury"):
            client_to_use = mercury_client
        elif target_model.startswith("nvidia") or target_model.startswith("openai/") or target_model.startswith("qwen/"):
            client_to_use = nvidia_client

        if not client_to_use:
            raise ValueError(f"API client for model '{target_model}' is not configured.")

        messages = [{"role": "system", "content": system_prompt}]
        messages.extend(history)
        # Use vision content array if available, else plain text
        content = vision_content if vision_content else user_msg
        messages.append({"role": "user", "content": content})

        resp = await client_to_use.chat.completions.create(
            model=target_model,
            max_tokens=config.MAX_TOKENS,
            temperature=0.1,
            messages=messages,
        )
        text = resp.choices[0].message.content if resp.choices else ""
        return text if text else ""


@router.post("/ask", response_model=models.AskResponse)
async def ask(
    request: Request,
    fields: dict = Depends(_parse_ask_fields),
    files: list[UploadFile] = File(default=[]),
):
    _require_ai()
    if auth_err := await _check_auth(request):
        return auth_err

    _metrics["ask_requests"] += 1

    question = fields["question"]
    results_json = fields["results_json"]
    conversation_id = fields["conversation_id"]
    model = fields["model"]
    persona_id = fields["persona_id"]
    session_title = fields["session_title"]

    if not question and not files:
        raise HTTPException(400, "question is required")

    user_id = _extract_user_id(request)
    session_type = "analysis" if results_json else "chat"
    conv_id, history = await _get_or_create_session(user_id, session_type, conversation_id)

    target_model = model or config.MODEL
    recent = history[-10:]
    system_prompt = await _build_system_prompt(user_id, persona_id)

    try:
        user_msg, vision_content = await _build_user_content(question, results_json, files, target_model)
        text = await _run_ask(
            fields=fields, user_id=user_id, session_type=session_type,
            conv_id=conv_id, history=recent, system_prompt=system_prompt,
            target_model=target_model, user_msg=user_msg, vision_content=vision_content,
        )

        history.append({"role": "user", "content": user_msg})
        history.append({"role": "assistant", "content": text})
        if len(history) > 40:
            history[:] = history[-40:]

        title = session_title or question[:50]
        analysis_ctx = None
        if results_json:
            try:
                analysis_ctx = json.loads(results_json)
            except Exception:
                analysis_ctx = {"raw": results_json[:5000]}

        await _save_session(conv_id, user_id, session_type, history, title=title,
                          persona_id=persona_id, analysis_context=analysis_ctx)

        return models.AskResponse(answer=text, conversation_id=conv_id)
    except Exception as e:
        logger.error("/ask call failed: %s", e)
        _metrics["ask_errors"] += 1
        raise HTTPException(502, "AI service temporarily unavailable")


@router.post("/ask/stream")
async def ask_stream(
    request: Request,
    fields: dict = Depends(_parse_ask_fields),
    files: list[UploadFile] = File(default=[]),
):
    _require_ai()
    if auth_err := await _check_auth(request):
        return auth_err

    _metrics["ask_stream_requests"] += 1

    question = fields["question"]
    results_json = fields["results_json"]
    conversation_id = fields["conversation_id"]
    model = fields["model"]
    persona_id = fields["persona_id"]
    session_title = fields["session_title"]

    if not question and not files:
        raise HTTPException(400, "question is required")

    user_id = _extract_user_id(request)
    session_type = "analysis" if results_json else "chat"
    conv_id, history = await _get_or_create_session(user_id, session_type, conversation_id)

    target_model = model or config.MODEL
    recent = history[-10:]
    system_prompt = await _build_system_prompt(user_id, persona_id)

    async def generate():
        full_text = ""
        thinking_text = ""
        try:
            user_msg, vision_content = await _build_user_content(question, results_json, files, target_model)
            if target_model.startswith("gemini"):
                if not gemini_client:
                    raise ValueError("Gemini API is not configured.")
                gemini_history = []
                for msg in recent:
                    role = "model" if msg["role"] == "assistant" else "user"
                    gemini_history.append({"role": role, "parts": [{"text": msg["content"]}]})
                gemini_history.append({"role": "user", "parts": [{"text": user_msg}]})

                stream = await gemini_client.aio.models.generate_content_stream(
                    model=target_model,
                    contents=gemini_history,
                    config=types.GenerateContentConfig(
                        system_instruction=system_prompt,
                        max_output_tokens=config.MAX_TOKENS,
                        temperature=0.1,
                    ),
                )
                async for chunk in stream:
                    if chunk.text:
                        d = chunk.text
                        full_text += d
                        yield f"data: {json.dumps({'token': d})}\n\n"
                    if hasattr(chunk, 'thought') and chunk.thought:
                        thinking_text += str(chunk.thought)
                        yield f"data: {json.dumps({'thinking': str(chunk.thought)})}\n\n"
            else:
                client_to_use = None
                if target_model.startswith("deepseek"):
                    client_to_use = deepseek_client
                elif target_model.startswith("mercury"):
                    client_to_use = mercury_client
                elif target_model.startswith("nvidia") or target_model.startswith("openai/") or target_model.startswith("qwen/"):
                    client_to_use = nvidia_client

                if not client_to_use:
                    raise ValueError(f"API client for model '{target_model}' is not configured.")

                messages = [{"role": "system", "content": system_prompt}]
                messages.extend(recent)
                content = vision_content if vision_content else user_msg
                messages.append({"role": "user", "content": content})

                stream_max_tokens = 8192 if target_model.startswith("deepseek") else config.MAX_TOKENS
                stream = await client_to_use.chat.completions.create(
                    model=target_model,
                    max_tokens=stream_max_tokens,
                    temperature=0.1,
                    messages=messages,
                    stream=True,
                )
                async for chunk in stream:
                    if chunk.choices:
                        delta = chunk.choices[0].delta
                        if hasattr(delta, 'reasoning_content') and delta.reasoning_content:
                            t = delta.reasoning_content
                            thinking_text += t
                            yield f"data: {json.dumps({'thinking': t})}\n\n"
                        if delta.content:
                            tmp = delta.content
                            full_text += tmp
                            yield f"data: {json.dumps({'token': tmp})}\n\n"

            yield f"data: {json.dumps({'done': True, 'conversation_id': conv_id})}\n\n"

            history.append({"role": "user", "content": user_msg})
            history.append({"role": "assistant", "content": full_text})
            if len(history) > 40:
                history[:] = history[-40:]

            title = session_title or question[:50]
            analysis_ctx = None
            if results_json:
                try:
                    analysis_ctx = json.loads(results_json)
                except Exception:
                    analysis_ctx = {"raw": results_json[:5000]}
            await _save_session(conv_id, user_id, session_type, history, title=title,
                              persona_id=persona_id, analysis_context=analysis_ctx)
        except Exception as e:
            logger.error("/ask/stream failed: %s", e)
            _metrics["ask_stream_errors"] += 1
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(generate(), media_type="text/event-stream")

@router.post("/import_case")
async def import_case(
    request: Request,
    file: UploadFile = File(...),
    case_name: str = Form(...)
):
    _require_ai()
    if auth_err := await _check_auth(request):
        return auth_err
    if rate_err := await _check_rate_limit(request):
        return rate_err

    content = await file.read()
    text = ""
    filename = (file.filename or "").lower()
    content_type = (file.content_type or "").lower()
    
    try:
        if filename.endswith(".pdf"):
            import io
            from pypdf import PdfReader
            pdf = PdfReader(io.BytesIO(content))
            for page in pdf.pages:
                text += page.extract_text() + "\n"
        elif content_type in _IMAGE_MIME_TYPES or filename.endswith((".png", ".jpg", ".jpeg", ".webp", ".heic", ".heif")):
            mime_type = content_type if content_type in _IMAGE_MIME_TYPES else "image/jpeg"
            text = await _ocr_image(content, mime_type)
        else:
            text = content.decode("utf-8", errors="ignore")
    except Exception as e:
        logger.error("Failed to extract text from file: %s", e)
        raise HTTPException(400, f"Failed to read file: {e}")

    if len(text) > 50000:
        text = text[:50000] # truncate if too long

    prompt = prompts.IMPORT_CASE_PROMPT + f"\n\n[FILE CONTENT START]\n{text}\n[FILE CONTENT END]"
    
    try:
        # Prefer NVIDIA for data extraction; fall back to Gemini
        if nvidia_client:
            try:
                response_text = await _call_nvidia_import(prompts.SYSTEM_PROMPT, prompt)
            except Exception:
                logger.warning("NVIDIA import failed, falling back to Gemini")
                response_text = await _call_gemini(prompts.SYSTEM_PROMPT, prompt)
        else:
            response_text = await _call_gemini(prompts.SYSTEM_PROMPT, prompt)
        parsed = utils.extract_json_block(response_text)
        
        if not parsed:
            raise ValueError("AI failed to extract structured JSON data.")
            
        # Ensure base structure exists
        if "bus_data" not in parsed or "line_data" not in parsed:
            raise ValueError("AI output missing bus_data or line_data.")

        yaml_path, csv_path = _safe_case_paths(case_name)
        
        # Save as YAML
        with open(yaml_path, "w", encoding="utf-8") as f:
            yaml.dump(parsed, f, sort_keys=False, default_flow_style=None)
            
        # Generate CSV representation
        with open(csv_path, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["--- BUS DATA ---"])
            writer.writerow(["bus_id", "type", "Vmag", "Vangle", "Pgen", "Qgen", "Pload", "Qload", "Gsh", "Bsh", "Qmin", "Qmax"])
            for bus in parsed["bus_data"]:
                writer.writerow(bus)
            writer.writerow([])
            writer.writerow(["--- LINE DATA ---"])
            writer.writerow(["from_bus", "to_bus", "R", "X", "B_half", "tap", "phase"])
            for line in parsed["line_data"]:
                writer.writerow(line)
                
        # Read back CSV for response
        with open(csv_path, "r", encoding="utf-8") as f:
            csv_content = f.read()

        return JSONResponse(content={
            "success": True,
            "message": f"Successfully imported {yaml_path.name} and {csv_path.name}",
            "parsed_data": parsed,
            "csv_content": csv_content
        })
        
    except Exception as e:
        logger.error("/import_case Gemini call failed: %s", e)
        raise HTTPException(502, f"AI extraction failed: {str(e)}")


# ── Session Endpoints ───────────────────────────────────────

@router.get("/sessions")
async def list_sessions(request: Request, type: str | None = None):
    if auth_err := await _check_auth(request):
        return auth_err
    user_id = _extract_user_id(request)
    try:
        from db import operations as db_ops
        sessions = await db_ops.list_user_sessions(user_id, type)
        return sessions
    except Exception as e:
        logger.error("Failed to list sessions: %s", e)
        raise HTTPException(503, "Database unavailable")


@router.post("/sessions")
async def create_session(request: Request, body: dict):
    if auth_err := await _check_auth(request):
        return auth_err
    user_id = _extract_user_id(request)
    session_id = uuid.uuid4().hex[:12]
    try:
        from db import operations as db_ops
        await db_ops.save_conversation(
            conv_id=session_id,
            user_id=user_id,
            session_type=body.get("session_type", "chat"),
            messages=[],
            title=body.get("title"),
        )
        return {"id": session_id}
    except Exception as e:
        logger.error("Failed to create session: %s", e)
        raise HTTPException(503, "Database unavailable")


@router.get("/sessions/{session_id}")
async def get_session(request: Request, session_id: str):
    if auth_err := await _check_auth(request):
        return auth_err
    try:
        from db import operations as db_ops
        session = await db_ops.get_conversation_full(session_id)
        if session is None:
            raise HTTPException(404, "Session not found")
        return session
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to get session: %s", e)
        raise HTTPException(503, "Database unavailable")


@router.delete("/sessions/{session_id}")
async def delete_session(request: Request, session_id: str):
    if auth_err := await _check_auth(request):
        return auth_err
    user_id = _extract_user_id(request)
    try:
        from db import operations as db_ops
        ok = await db_ops.delete_session(session_id, user_id)
        if not ok:
            raise HTTPException(404, "Session not found or access denied")
        return {"deleted": True}
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to delete session: %s", e)
        raise HTTPException(503, "Database unavailable")


@router.patch("/sessions/{session_id}/title")
async def update_session_title(request: Request, session_id: str, body: dict):
    if auth_err := await _check_auth(request):
        return auth_err
    title = body.get("title", "").strip()
    if not title:
        raise HTTPException(422, "Title is required")
    try:
        from db import operations as db_ops
        ok = await db_ops.update_session_title(session_id, title)
        if not ok:
            raise HTTPException(404, "Session not found")
        return {"title": title}
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to update session title: %s", e)
        raise HTTPException(503, "Database unavailable")


# ── Persona Endpoints ───────────────────────────────────────

@router.get("/personas")
async def list_personas(request: Request):
    if auth_err := await _check_auth(request):
        return auth_err
    user_id = _extract_user_id(request)
    try:
        from db import operations as db_ops
        return await db_ops.get_personas(user_id)
    except Exception as e:
        logger.error("Failed to list personas: %s", e)
        raise HTTPException(503, "Database unavailable")


@router.post("/personas")
async def create_persona(request: Request, body: dict):
    if auth_err := await _check_auth(request):
        return auth_err
    user_id = _extract_user_id(request)
    try:
        from db import operations as db_ops
        return await db_ops.create_persona(user_id, body)
    except Exception as e:
        logger.error("Failed to create persona: %s", e)
        raise HTTPException(503, "Database unavailable")


@router.put("/personas/{persona_id}")
async def update_persona(request: Request, persona_id: int, body: dict):
    if auth_err := await _check_auth(request):
        return auth_err
    user_id = _extract_user_id(request)
    try:
        from db import operations as db_ops
        ok = await db_ops.update_persona(persona_id, user_id, body)
        if not ok:
            raise HTTPException(404, "Persona not found or access denied")
        return {"updated": True}
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to update persona: %s", e)
        raise HTTPException(503, "Database unavailable")


@router.delete("/personas/{persona_id}")
async def delete_persona(request: Request, persona_id: int):
    if auth_err := await _check_auth(request):
        return auth_err
    user_id = _extract_user_id(request)
    try:
        from db import operations as db_ops
        ok = await db_ops.delete_persona(persona_id, user_id)
        if not ok:
            raise HTTPException(404, "Persona not found or access denied")
        return {"deleted": True}
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to delete persona: %s", e)
        raise HTTPException(503, "Database unavailable")
