"""Shared utilities: retry, formatting, structured output extraction."""

from __future__ import annotations

import asyncio
import json
import logging
import re
from typing import Any

from . import config

logger = logging.getLogger("ai_service")


async def retry_gpt_call(func, *args, **kwargs):
    """Call a GPT async function with exponential backoff retry.

    Only retries on transient errors (network, server, rate-limit).
    Permanent errors (auth, bad request) are re-raised immediately.
    """
    max_retries = config.MAX_RETRIES
    retry_delay = config.RETRY_DELAY
    retry_backoff = config.RETRY_BACKOFF

    if max_retries < 1:
        return await func(*args, **kwargs)

    last_exc: Exception | None = None
    delay = retry_delay

    for attempt in range(1, max_retries + 1):
        try:
            return await func(*args, **kwargs)
        except Exception as e:
            last_exc = e
            if _is_permanent_error(e):
                logger.error("Permanent error on attempt %d: %s", attempt, e)
                raise
            logger.warning(
                "GPT call attempt %d/%d failed (retriable): %s",
                attempt, max_retries, e,
            )
            if attempt < max_retries:
                await asyncio.sleep(delay)
                delay *= retry_backoff

    if last_exc is not None:
        raise last_exc


def _is_permanent_error(exc: Exception) -> bool:
    """Check if an exception corresponds to a non-retriable error."""
    msg = str(exc).lower()
    permanent_markers = [
        "authentication", "unauthorized", "invalid api key",
        "invalid_request_error", "not found", "insufficient_quota",
    ]
    for marker in permanent_markers:
        if marker in msg:
            return True
    status = getattr(exc, "status_code", None)
    if status is not None and 400 <= status < 500 and status != 429:
        return True
    return False


def extract_json_block(text: str) -> dict[str, Any] | None:
    """Extract a JSON object from text, handling nested braces."""
    if not text:
        return None

    m = re.search(r"```(?:json)?\s*(\{.*\})\s*```", text, re.DOTALL)
    if m:
        try:
            return json.loads(m.group(1))
        except json.JSONDecodeError:
            pass

    start = text.find("{")
    if start == -1:
        return None

    depth = 0
    for i in range(start, len(text)):
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                candidate = text[start:i + 1]
                try:
                    return json.loads(candidate)
                except json.JSONDecodeError:
                    break
    return None


def format_bus_table(bus_data: dict) -> str:
    """Pretty-print bus results as a text table."""
    if not bus_data:
        return "  (no bus data)"

    keys = ["bus", "type", "voltage", "angle", "Pgen", "Qgen", "Pload", "Qload"]
    arrays = {k: bus_data.get(k, []) for k in keys}
    n = min(max((len(v) if isinstance(v, list) else 0 for v in arrays.values()), default=0), 500)

    lines = ["Bus  Type     V(pu)    Angle(deg)  Pgen(pu)  Qgen(pu)  Pload(pu) Qload(pu)"]
    defaults = {
        "bus": [""] * n, "type": [""] * n,
        "voltage": [0.0] * n, "angle": [0.0] * n,
        "Pgen": [0.0] * n, "Qgen": [0.0] * n,
        "Pload": [0.0] * n, "Qload": [0.0] * n,
    }

    for i in range(n):
        def _get(key, fmt):
            arr = arrays.get(key, [])
            val = arr[i] if i < len(arr) else defaults[key][i]
            if isinstance(val, str):
                return f"{val:>{fmt}}"
            return f"{val:{fmt}}"

        lines.append(
            f"{_get('bus', '>3')}  {_get('type', '<6')}  {_get('voltage', '>7.4f')}  "
            f"{_get('angle', '>10.3f')}  {_get('Pgen', '>8.4f')}  {_get('Qgen', '>8.4f')}  "
            f"{_get('Pload', '>8.4f')}  {_get('Qload', '>8.4f')}"
        )
    return "\n".join(lines)


def validate_user_input(text: str, max_length: int = 10000) -> str:
    """Basic sanitization: truncate overlong inputs."""
    if len(text) > max_length:
        logger.warning("Input truncated from %d to %d chars", len(text), max_length)
        return text[:max_length]
    return text
