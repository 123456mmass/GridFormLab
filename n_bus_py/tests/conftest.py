"""Shared test fixtures."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

# Add backend to path for imports
BACKEND = Path(__file__).resolve().parents[1] / "backend"
sys.path.insert(0, str(BACKEND))

from cases import loader as case_loader  # noqa: E402
from pfsolver import model  # noqa: E402


@pytest.fixture(scope="session")
def case_data():
    """Load IEEE 5-bus case once per test session."""
    return case_loader.load_case("ieee5bus")


@pytest.fixture(scope="session")
def m(case_data):
    """Build ModelResult once per test session."""
    return model.prepare_model(case_data)


@pytest.fixture(scope="session")
def case_data_dict(case_data):
    return case_data
