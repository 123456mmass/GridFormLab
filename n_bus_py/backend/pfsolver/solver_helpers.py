"""Shared helpers to eliminate duplicated timing, error-handling, and result-building code."""

from __future__ import annotations

import functools
import time as _time
from collections.abc import Callable

import numpy as np

from . import model, results


def build_result(
    m: model.ModelResult,
    V_final: np.ndarray,
    delta_final: np.ndarray,
    mis_hist: np.ndarray | list,
    iterations: int,
    converged: bool,
    method_name: str,
    t_start: float,
    opts: dict | None = None,
    **extra,
) -> dict:
    """Wrap results.build_results + timing + options into one call."""
    elapsed_ms = (_time.perf_counter() - t_start) * 1000
    r = results.build_results(
        m, V_final, delta_final, np.asarray(mis_hist),
        iterations, converged, method_name,
    )
    r["execution_time_ms"] = round(elapsed_ms, 2)
    r["options"] = opts or {}
    r.update(extra)
    return r


def solver_method(method_name: str):
    """Decorator that handles model prep, timing, and result finalization.

    The decorated function should accept (case_data, m, opts) and return
    a dict ready for results.build_results, or call build_result itself.

    If the function returns a raw tuple (V, delta, mis, it, conv),
    the decorator calls build_result automatically.
    """

    def decorator(func: Callable):
        @functools.wraps(func)
        def wrapper(case_data: dict, options: dict | None = None) -> dict:
            t0 = _time.perf_counter()
            m = model.prepare_model(case_data)
            try:
                raw = func(case_data, m, options or {})
                if isinstance(raw, dict):
                    elapsed = (_time.perf_counter() - t0) * 1000
                    raw.setdefault("execution_time_ms", round(elapsed, 2))
                    raw.setdefault("options", options or {})
                    return raw
                V_f, d_f, mis, it, conv = raw
                return build_result(m, V_f, d_f, mis, it, conv, method_name, t0, options)
            except Exception as exc:
                elapsed_ms = (_time.perf_counter() - t0) * 1000
                return {
                    "system_name": m.system_name if hasattr(m, 'system_name') else "",
                    "method": method_name,
                    "converged": False,
                    "iterations": 0,
                    "error": str(exc),
                    "execution_time_ms": round(elapsed_ms, 2),
                    "options": options or {},
                }

        return wrapper

    return decorator
