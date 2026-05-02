"""Security checks for AI service routes."""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

import main
from ai_service import config
from ai_service.router import _safe_case_paths


def test_ask_stream_requires_auth_when_token_configured(monkeypatch):
    monkeypatch.setattr(config, "AI_ENABLED", True)
    monkeypatch.setattr(config, "API_AUTH_TOKEN", "secret-token")

    client = TestClient(main.app)
    response = client.post("/ai/ask/stream", json={"question": "hello"})

    assert response.status_code == 401


def test_safe_case_paths_rejects_traversal():
    with pytest.raises(HTTPException):
        _safe_case_paths("../outside")


def test_safe_case_paths_stays_inside_cases_dir():
    yaml_path, csv_path = _safe_case_paths("custom_case_1")
    cases_dir = Path(__file__).resolve().parents[1] / "backend" / "cases"

    assert yaml_path.parent == cases_dir
    assert csv_path.parent == cases_dir
    assert yaml_path.name == "custom_case_1.yaml"
    assert csv_path.name == "custom_case_1.csv"
