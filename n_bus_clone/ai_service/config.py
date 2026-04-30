"""Configuration — loaded from environment variables with sensible defaults."""

from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv

_env_path = Path(__file__).resolve().parent / ".env"
load_dotenv(_env_path, override=False)


def _require(key: str) -> str:
    val = os.getenv(key, "").strip()
    if not val:
        raise RuntimeError(
            f"Missing required environment variable: {key}. "
            f"Copy .env.example to .env and fill in your values."
        )
    return val


def _int_env(key: str, default: int) -> int:
    try:
        return int(os.getenv(key, str(default)))
    except (ValueError, TypeError):
        raise RuntimeError(
            f"Environment variable {key} must be an integer, got: {os.getenv(key)!r}"
        )


def _float_env(key: str, default: float) -> float:
    try:
        return float(os.getenv(key, str(default)))
    except (ValueError, TypeError):
        raise RuntimeError(
            f"Environment variable {key} must be a number, got: {os.getenv(key)!r}"
        )


# ── LLM API ─────────────────────────────────────────────────
API_KEY = _require("LLM_API_KEY")
BASE_URL = os.getenv("LLM_BASE_URL", "https://api.deepseek.com")
MODEL = os.getenv("LLM_MODEL", "deepseek-v4-flash")
MAX_TOKENS = _int_env("MAX_TOKENS", 4096)

# ── Server ──────────────────────────────────────────────────
HOST = os.getenv("HOST", "127.0.0.1")
PORT = _int_env("PORT", 8000)
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()

# ── Auth ────────────────────────────────────────────────────
API_AUTH_TOKEN = os.getenv("API_AUTH_TOKEN", "").strip()
# If set, clients must pass this token in the Authorization header.
# Leave empty to require no authentication (development only).

# ── Rate limiting ───────────────────────────────────────────
RATE_LIMIT_REQUESTS = _int_env("RATE_LIMIT_REQUESTS", 30)
RATE_LIMIT_WINDOW_SEC = _int_env("RATE_LIMIT_WINDOW_SEC", 60)

# ── Retry ───────────────────────────────────────────────────
MAX_RETRIES = _int_env("MAX_RETRIES", 3)
RETRY_DELAY = _float_env("RETRY_DELAY", 1.0)
RETRY_BACKOFF = _float_env("RETRY_BACKOFF", 2.0)

# ── Input validation ────────────────────────────────────────
MAX_INPUT_LENGTH = _int_env("MAX_INPUT_LENGTH", 10000)
MAX_BUS_DATA_ITEMS = _int_env("MAX_BUS_DATA_ITEMS", 500)
