"""Configuration — loaded from environment variables with sensible defaults.

Looks for .env in backend/ directory."""

from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv

_env_path = Path(__file__).resolve().parents[1] / ".env"
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
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "").strip()

DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY", os.getenv("LLM_API_KEY", "")).strip()
DEEPSEEK_BASE_URL = os.getenv("DEEPSEEK_BASE_URL", os.getenv("LLM_BASE_URL", "https://api.deepseek.com/v1"))

MERCURY_API_KEY = os.getenv("MERCURY_API_KEY", os.getenv("LLM_API_KEY", "")).strip()
MERCURY_BASE_URL = os.getenv("MERCURY_BASE_URL", "https://api.inceptionlabs.ai/v1")

NVIDIA_API_KEY = os.getenv("NVIDIA_API_KEY", "").strip()
NVIDIA_BASE_URL = os.getenv("NVIDIA_BASE_URL", "https://integrate.api.nvidia.com/v1")

API_KEY = GEMINI_API_KEY  # Default to Gemini for internal use
AI_ENABLED = bool(GEMINI_API_KEY or DEEPSEEK_API_KEY or MERCURY_API_KEY or NVIDIA_API_KEY)
MODEL = os.getenv("LLM_MODEL", "gemini-3.1-flash")
OCR_MODEL = os.getenv("OCR_MODEL", "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning")
IMPORT_MODEL = os.getenv("IMPORT_MODEL", "openai/gpt-oss-120b")
MAX_TOKENS = _int_env("MAX_TOKENS", 4096)

# ── Server ──────────────────────────────────────────────────
HOST = os.getenv("HOST", "127.0.0.1")
PORT = _int_env("PORT", 8000)
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()

# ── Auth ────────────────────────────────────────────────────
API_AUTH_TOKEN = os.getenv("API_AUTH_TOKEN", "").strip()

# JWT Authentication
JWT_SECRET = os.getenv("JWT_SECRET", "dev-secret-change-in-production").strip()
JWT_ALGORITHM = os.getenv("JWT_ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = _int_env("ACCESS_TOKEN_EXPIRE_MINUTES", 30)
REFRESH_TOKEN_EXPIRE_DAYS = _int_env("REFRESH_TOKEN_EXPIRE_DAYS", 7)
ALLOW_SELF_REGISTRATION = os.getenv("ALLOW_SELF_REGISTRATION", "true").lower() == "true"

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
