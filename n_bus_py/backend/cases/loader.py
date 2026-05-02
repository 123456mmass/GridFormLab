"""Case data loader — YAML files to dicts with schema validation."""

from __future__ import annotations

import os
import yaml


_CASE_DIR = os.path.dirname(os.path.abspath(__file__))


def load_case(name: str) -> dict:
    """Load a case by name (without .yaml extension).

    Example: load_case('ieee5bus')
    """
    fpath = os.path.join(_CASE_DIR, f"{name}.yaml")
    if not os.path.exists(fpath):
        raise FileNotFoundError(f"Case not found: {name}. Available: {list_cases()}")
    with open(fpath, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)
    _validate(data)
    return data


def list_cases() -> list[str]:
    """List all available case names."""
    cases = []
    for f in sorted(os.listdir(_CASE_DIR)):
        if f.endswith(".yaml") and not f.startswith("_"):
            cases.append(f.replace(".yaml", ""))
    return cases


def _validate(data: dict) -> None:
    """Basic structure validation."""
    if "bus_data" not in data:
        raise ValueError("Case missing 'bus_data'")
    if "line_data" not in data:
        raise ValueError("Case missing 'line_data'")
    data.setdefault("system_name", "Unnamed")
    data.setdefault("base_values", {})
