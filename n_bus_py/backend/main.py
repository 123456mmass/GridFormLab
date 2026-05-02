"""N-Bus Power Flow — FastAPI application entry point.

Mounts:
    /api/*   — Solver endpoints (api.router)
    /ai/*    — AI analysis endpoints (ai_service.router)

Run:
    cd backend
    python main.py
    # or: uvicorn main:app --host 0.0.0.0 --port 8000 --reload
"""

from __future__ import annotations

import logging
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from api.router import router as api_router
from ai_service.router import router as ai_router
from auth.router import router as auth_router

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("nbus")


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting N-Bus Power Flow API")
    try:
        from db.database import init_db
        await init_db()
        logger.info("Database tables verified")
    except Exception as e:
        logger.warning("Database init skipped (DB not available): %s", e)
    yield
    logger.info("Shutting down")


app = FastAPI(
    title="N-Bus Power Flow API",
    version="1.0.0",
    description="Power system analysis toolkit — 12 solver methods, AI-powered analysis",
    lifespan=lifespan,
)

# ── CORS ─────────────────────────────────────────────────────

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost",
        "http://127.0.0.1",
        "http://localhost:3000",
        "http://localhost:5173",
    ],
    allow_origin_regex=r"^http://(localhost|127\.0\.0\.1):\d+$",
    allow_methods=["*"],
    allow_headers=["Authorization", "Content-Type"],
)


# ── Global exception handler ────────────────────────────────

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.exception("Unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(status_code=500, content={"error": "Internal server error"})


# ── Middleware: request timing ───────────────────────────────

@app.middleware("http")
async def timing_middleware(request: Request, call_next):
    t0 = time.perf_counter()
    response = await call_next(request)
    elapsed_ms = (time.perf_counter() - t0) * 1000
    response.headers["X-Response-Time-Ms"] = f"{elapsed_ms:.1f}"
    return response


# ── Mount routers ────────────────────────────────────────────

app.include_router(auth_router, prefix="/auth")
app.include_router(api_router)
app.include_router(ai_router)


# ── Root redirect ────────────────────────────────────────────

@app.get("/")
async def root():
    return {
        "service": "N-Bus Power Flow API",
        "version": "1.0.0",
        "docs": "/docs",
        "health": "/api/health",
        "ai_health": "/ai/health",
    }


# ── Entry point ──────────────────────────────────────────────

if __name__ == "__main__":
    import os

    import uvicorn

    host = os.getenv("HOST", "127.0.0.1")
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run("main:app", host=host, port=port, reload=True, log_level="info")
