"""Unit tests for AI service endpoints."""

import pytest
from fastapi.testclient import TestClient
from unittest.mock import AsyncMock, patch

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ["LLM_API_KEY"] = "test-key"
os.environ["API_AUTH_TOKEN"] = ""

from server import app

client = TestClient(app)


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] in ("ok", "degraded")
    assert "version" in data


@pytest.mark.asyncio
async def test_analyze_success():
    with patch("server._call_gpt", new_callable=AsyncMock) as mock_gpt:
        mock_gpt.return_value = '{"assessment": "Good", "issues": [], "recommendations": []}'
        payload = {
            "method": "NR",
            "system_name": "5-bus",
            "num_buses": 5,
            "num_lines": 5,
            "converged": True,
            "iterations": 4,
            "P_loss_total": 0.06,
            "Q_loss_total": 0.03,
        }
        response = client.post("/analyze", json=payload)
        assert response.status_code == 200
        assert "analysis" in response.json()


def test_analyze_validation_error():
    response = client.post("/analyze", json={})
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_compare_success():
    with patch("server._call_gpt", new_callable=AsyncMock) as mock_gpt:
        mock_gpt.return_value = '{"winner": "NR", "comparison": []}'
        payload = {
            "results_a": {
                "method": "NR", "system_name": "5-bus", "num_buses": 5, "num_lines": 5,
                "converged": True, "iterations": 4, "P_loss_total": 0.06, "Q_loss_total": 0.03,
            },
            "results_b": {
                "method": "GS", "system_name": "5-bus", "num_buses": 5, "num_lines": 5,
                "converged": True, "iterations": 20, "P_loss_total": 0.06, "Q_loss_total": 0.03,
            },
            "method_a": "NR",
            "method_b": "GS",
        }
        response = client.post("/compare", json=payload)
        assert response.status_code == 200


def test_ask_empty_question():
    response = client.post("/ask", json={"question": ""})
    assert response.status_code == 422


def test_ask_too_long():
    response = client.post("/ask", json={"question": "x" * 20000})
    assert response.status_code == 422


def test_sanitize_input():
    from server import _sanitize_user_input
    result = _sanitize_user_input("hello", 10)
    assert len(result) <= 10


def test_extract_json():
    from utils import extract_json_block
    text = 'some text {"key": "value"} more text'
    result = extract_json_block(text)
    assert result == {"key": "value"}


def test_extract_json_nested():
    from utils import extract_json_block
    text = '{"a": {"b": [1, 2, 3]}, "c": "d"}'
    result = extract_json_block(text)
    assert result == {"a": {"b": [1, 2, 3]}, "c": "d"}
