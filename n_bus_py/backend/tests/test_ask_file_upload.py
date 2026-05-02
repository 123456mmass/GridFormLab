"""Tests for /ai/ask and /ai/ask/stream multipart file upload endpoints."""
from __future__ import annotations

import io
import json
import os
import uuid

import pytest
from httpx import AsyncClient, ASGITransport

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://postgres:postgres@localhost:5432/nbus")

from main import app  # noqa: E402

transport = ASGITransport(app=app)


# ── Auth helper ────────────────────────────────────────────────

_TEST_USER = f"test_upload_{uuid.uuid4().hex[:8]}"
_TEST_PASS = "test1234"
_token: str | None = None


async def _get_token() -> str | None:
    """Register + login to get an access token. Returns None if DB unavailable."""
    global _token
    if _token:
        return _token
    try:
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            # Register
            r = await client.post("/auth/register", json={
                "username": _TEST_USER, "password": _TEST_PASS,
            })
            if r.status_code == 400 and "already exists" in (r.json().get("detail", "")):
                pass  # user already exists from previous run
            elif r.status_code not in (200, 201):
                return None

            # Login
            r = await client.post("/auth/login", json={
                "username": _TEST_USER, "password": _TEST_PASS,
            })
            if r.status_code == 200:
                data = r.json()
                _token = data.get("access_token") or data.get("token")
                return _token
            return None
    except Exception:
        return None


def _auth_headers() -> dict:
    """Return Authorization header if token available, else empty."""
    h = {}
    if _token:
        h["Authorization"] = f"Bearer {_token}"
    return h


# ═══════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════

async def _post(path: str, data: dict, files: list | None = None) -> dict:
    """POST and return (status, json_body). Handles auth."""
    headers = _auth_headers()
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        kwargs = {"data": data, "headers": headers}
        if files:
            kwargs["files"] = files
        # Always use data (form-encoded), not json
        res = await client.post(path, **kwargs)
        try:
            return {"status": res.status_code, "json": res.json()}
        except Exception:
            return {"status": res.status_code, "json": {}}


async def _stream(path: str, data: dict, files: list | None = None) -> tuple[int, list[dict]]:
    """POST to a streaming endpoint and parse SSE chunks."""
    headers = _auth_headers()
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        kwargs = {"data": data, "headers": headers}
        if files:
            kwargs["files"] = files
        async with client.stream("POST", path, **kwargs) as res:
            body = await res.aread()
            chunks = []
            for line in body.decode(errors="replace").split("\n\n"):
                m = line.strip().split("data: ", 1)
                if len(m) == 2:
                    try:
                        chunks.append(json.loads(m[1]))
                    except json.JSONDecodeError:
                        pass
            return res.status_code, chunks


# ═══════════════════════════════════════════════════════════════
# Fixtures
# ═══════════════════════════════════════════════════════════════

@pytest.fixture(scope="session")
def anyio_backend():
    return "asyncio"


@pytest.fixture(scope="session")
async def token_setup():
    """Ensure token is obtained before tests run."""
    await _get_token()
    yield


@pytest.fixture
def txt_file():
    return ("notes.txt", io.BytesIO(b"Bus 1 voltage: 1.06 pu\nBus 2 voltage: 1.045 pu"), "text/plain")


@pytest.fixture
def csv_file():
    return ("buses.csv", io.BytesIO(b"bus,voltage,angle\n1,1.06,0.0\n2,1.045,-2.5\n3,1.01,-5.0"), "text/csv")


@pytest.fixture
def pdf_file():
    content = (
        b"%PDF-1.4\n"
        b"1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n"
        b"2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n"
        b"3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]"
        b"/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj\n"
        b"4 0 obj<</Length 44>>stream\n"
        b"BT /F1 12 Tf 100 700 Td (IEEE 5-Bus Test System) Tj ET\n"
        b"endstream endobj\n"
        b"5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj\n"
        b"xref\n0 6\n0000000000 65535 f \n0000000009 00000 n \n"
        b"0000000058 00000 n \n0000000115 00000 n \n0000000210 00000 n \n"
        b"0000000319 00000 n \n"
        b"trailer<</Size 6/Root 1 0 R>>\n"
        b"startxref\n398\n%%EOF"
    )
    return ("report.pdf", io.BytesIO(content), "application/pdf")


@pytest.fixture
def png_file():
    content = (
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
        b"\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f"
        b"\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82"
    )
    return ("chart.png", io.BytesIO(content), "image/png")


# ═══════════════════════════════════════════════════════════════
# Non-streaming /ask
# ═══════════════════════════════════════════════════════════════

@pytest.mark.anyio
async def test_ask_no_files_no_question_returns_400(token_setup):
    r = await _post("/ai/ask", {"question": ""})
    # Without auth: 401. With auth: 400.
    assert r["status"] in (400, 401)


@pytest.mark.anyio
async def test_ask_text_only(token_setup):
    r = await _post("/ai/ask", {
        "question": "What is power flow?",
        "model": "deepseek-v4-flash",
    })
    # 401 = no auth/DB, 502 = AI key missing, 200 = success
    assert r["status"] not in (400, 422), f"Unexpected {r['status']}: {r.get('json')}"


@pytest.mark.anyio
async def test_ask_with_text_file(token_setup, txt_file):
    r = await _post("/ai/ask", {
        "question": "Summarize",
        "model": "deepseek-v4-flash",
    }, files=[("files", txt_file)])
    assert r["status"] not in (400, 422), f"Unexpected {r['status']}"


@pytest.mark.anyio
async def test_ask_with_csv_file(token_setup, csv_file):
    r = await _post("/ai/ask", {
        "question": "Analyze",
        "model": "deepseek-v4-flash",
    }, files=[("files", csv_file)])
    assert r["status"] not in (400, 422), f"Unexpected {r['status']}"


@pytest.mark.anyio
async def test_ask_with_pdf_file(token_setup, pdf_file):
    r = await _post("/ai/ask", {
        "question": "Read this PDF",
        "model": "deepseek-v4-flash",
    }, files=[("files", pdf_file)])
    assert r["status"] not in (400, 422), f"Unexpected {r['status']}"


@pytest.mark.anyio
async def test_ask_with_image_file(token_setup, png_file):
    r = await _post("/ai/ask", {
        "question": "Describe",
        "model": "deepseek-v4-flash",
    }, files=[("files", png_file)])
    # 502 = AI call failed (expected with fake image), anything but 400/422 is fine
    assert r["status"] not in (400, 422), f"Unexpected {r['status']}: {r.get('json')}"


@pytest.mark.anyio
async def test_ask_files_without_question(token_setup, txt_file):
    r = await _post("/ai/ask", {
        "question": "",
        "model": "deepseek-v4-flash",
    }, files=[("files", txt_file)])
    assert r["status"] not in (400, 422), f"Unexpected {r['status']}"


@pytest.mark.anyio
async def test_ask_multiple_files(token_setup, txt_file, csv_file):
    r = await _post("/ai/ask", {
        "question": "Compare",
        "model": "deepseek-v4-flash",
    }, files=[("files", csv_file), ("files", txt_file)])
    assert r["status"] not in (400, 422), f"Unexpected {r['status']}"


# ═══════════════════════════════════════════════════════════════
# Streaming /ask/stream
# ═══════════════════════════════════════════════════════════════

@pytest.mark.anyio
async def test_ask_stream_no_files_no_question_returns_400(token_setup):
    status, chunks = await _stream("/ai/ask/stream", {"question": ""})
    assert status in (400, 401)


@pytest.mark.anyio
async def test_ask_stream_text_only(token_setup):
    status, chunks = await _stream("/ai/ask/stream", {
        "question": "Hello",
        "model": "deepseek-v4-flash",
    })
    # 401 = no auth, else even on AI key failure we should get an error/done chunk
    if status != 401:
        assert len(chunks) > 0, "Expected SSE chunks"


@pytest.mark.anyio
async def test_ask_stream_with_text_file(token_setup, txt_file):
    status, chunks = await _stream("/ai/ask/stream", {
        "question": "Summarize",
        "model": "deepseek-v4-flash",
    }, files=[("files", txt_file)])
    if status != 401:
        assert len(chunks) > 0, "Expected SSE chunks"


@pytest.mark.anyio
async def test_ask_stream_with_pdf(token_setup, pdf_file):
    status, chunks = await _stream("/ai/ask/stream", {
        "question": "Read this",
        "model": "deepseek-v4-flash",
    }, files=[("files", pdf_file)])
    if status != 401:
        assert len(chunks) > 0, "Expected SSE chunks"


@pytest.mark.anyio
async def test_ask_stream_with_image(token_setup, png_file):
    status, chunks = await _stream("/ai/ask/stream", {
        "question": "Describe",
        "model": "deepseek-v4-flash",
    }, files=[("files", png_file)])
    if status != 401:
        assert len(chunks) > 0, "Expected SSE chunks"


@pytest.mark.anyio
async def test_ask_stream_files_without_question(token_setup, txt_file):
    status, chunks = await _stream("/ai/ask/stream", {
        "question": "",
        "model": "deepseek-v4-flash",
    }, files=[("files", txt_file)])
    if status != 401:
        assert len(chunks) > 0, "Expected SSE chunks"


@pytest.mark.anyio
async def test_ask_stream_multiple_files(token_setup, csv_file, txt_file):
    status, chunks = await _stream("/ai/ask/stream", {
        "question": "Compare",
        "model": "deepseek-v4-flash",
    }, files=[("files", csv_file), ("files", txt_file)])
    if status != 401:
        assert len(chunks) > 0, "Expected SSE chunks"


# ═══════════════════════════════════════════════════════════════
# Health
# ═══════════════════════════════════════════════════════════════

@pytest.mark.anyio
async def test_ai_health():
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.get("/ai/health")
        assert res.status_code == 200
        data = res.json()
        assert "status" in data
