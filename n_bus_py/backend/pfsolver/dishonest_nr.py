"""Dishonest Newton-Raphson — Jacobian freeze variant.

Same as NR but the Jacobian is reused for K iterations before rebuilding.
~40% fewer Jacobian evaluations with minor convergence impact.

This is the simplest acceleration: trade Jacobian accuracy for speed.
Useful when Jacobian construction dominates runtime (large systems).
"""

from __future__ import annotations

import time as _time

import numpy as np

from . import jacobian, mismatch, model, results, state

_DEFAULTS = {
    "max_iter": 50,
    "tolerance": 1e-6,
    "jacobian_update_freq": 3,   # Rebuild Jacobian every K iterations
    "enforce_q_limits": False,
    "q_limit_tolerance": 1e-4,
    "verbose": False,
}


def solve(case_data: dict, options: dict | None = None) -> dict:
    """Run Dishonest Newton-Raphson power flow.

    Rebuilds Jacobian only every `jacobian_update_freq` iterations.
    """
    opts = dict(_DEFAULTS)
    if options:
        opts.update(options)

    t0 = _time.perf_counter()
    m = model.prepare_model(case_data)

    x = state.initial_state(m)
    update_freq = opts["jacobian_update_freq"]
    max_iter = opts["max_iter"]
    tol = opts["tolerance"]

    mis_hist = []
    J = None  # Jacobian cache

    for it in range(1, max_iter + 1):
        mis, P_c, Q_c, V, delta = mismatch.calculate_mismatch(x, m)

        max_mis = float(np.max(np.abs(mis)))
        mis_hist.append(max_mis)

        if max_mis < tol:
            V_f, d_f = state.state_to_voltage_angle(x, m)
            elapsed_ms = (_time.perf_counter() - t0) * 1000
            r = results.build_results(m, V_f, d_f, np.array(mis_hist), it, True,
                                      f"Dishonest NR (K={update_freq})")
            r["execution_time_ms"] = round(elapsed_ms, 2)
            r["options"] = opts
            return r

        # Rebuild Jacobian only at specified frequency
        if J is None or (it - 1) % update_freq == 0:
            J = jacobian.build_jacobian(V, delta, P_c, Q_c, m)

        try:
            dx = jacobian.solve_jacobian(J, mis)
        except np.linalg.LinAlgError:
            # If solve with frozen J fails, rebuild and retry
            J = jacobian.build_jacobian(V, delta, P_c, Q_c, m)
            dx = jacobian.solve_jacobian(J, mis)

        x += dx

        # Guard against negative voltages
        V_vals = x[m.n_delta:]
        zero_mask = V_vals <= 0
        if np.any(zero_mask):
            V_vals[zero_mask] = 0.1
            x[m.n_delta:] = V_vals

    V_f, d_f = state.state_to_voltage_angle(x, m)
    elapsed_ms = (_time.perf_counter() - t0) * 1000
    r = results.build_results(m, V_f, d_f, np.array(mis_hist), max_iter, False,
                              f"Dishonest NR (K={update_freq})")
    r["execution_time_ms"] = round(elapsed_ms, 2)
    r["options"] = opts
    return r
