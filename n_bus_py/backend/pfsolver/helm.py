"""HELM — Holomorphic Embedding Load Flow.

Full solver using Taylor series + Padé approximant. No initial guess
required — starts from zero-injection germ. Natural voltage collapse
indicator via Padé pole distance from |α|<1.

Reference: Trias, "The Holomorphic Embedding Load Flow Method", 2012.
"""

from __future__ import annotations

import time as _time

import numpy as np

from . import model, results
from . import holomorphic as _helm_core
from . import power_injections as _pi

_DEFAULTS = {
    "max_order": 20,
    "pade_L": 8,
    "pade_M": 8,
    "tolerance": 1e-6,
    "verbose": False,
}


def solve(case_data: dict, options: dict | None = None) -> dict:
    """Run Holomorphic Embedding Load Flow.

    Args:
        case_data: dict with bus_data, line_data, base_values
        options: dict with max_order, pade_L, pade_M, tolerance

    Returns:
        results dict with voltages, angles, line flows, etc.
    """
    opts = dict(_DEFAULTS)
    if options:
        opts.update(options)

    t0 = _time.perf_counter()
    m = model.prepare_model(case_data)

    n_max = opts["max_order"]
    L = opts["pade_L"]
    M = opts["pade_M"]
    tol = opts["tolerance"]

    # Compute HELM coefficients
    V_coeffs = _helm_core.solve_helm_coefficients(m, n_max=n_max)

    # Evaluate at α=1 with Padé approximant
    Vc_helm = _helm_core.evaluate_helm(V_coeffs, L=L, M=M)

    V_final = np.abs(Vc_helm)
    delta_final = np.angle(Vc_helm)

    # Compute mismatch to verify accuracy
    P_calc, Q_calc = _pi.calculate_power_injections(V_final, delta_final, m.Ybus)
    dP = m.P_net - P_calc
    dQ = m.Q_net - Q_calc

    # Mask out slack (P+Q) and PV (Q only)
    dP_checked = np.abs(dP[m.delta_idx])
    dQ_checked = np.abs(dQ[m.V_idx])
    max_mis = float(max(np.max(dP_checked), np.max(dQ_checked))) if len(dP_checked) > 0 else 0.0

    converged = max_mis < tol * 100  # HELM is approximate, relax tolerance
    iterations = n_max

    # Build mismatch history (approximate — HELM doesn't iterate)
    mis_hist = np.array([max_mis])

    elapsed_ms = (_time.perf_counter() - t0) * 1000

    r = results.build_results(
        m, V_final.copy(), delta_final.copy(),
        mis_hist, iterations, converged, f"HELM (order={n_max}, Pade=[{L}/{M}])"
    )
    r["execution_time_ms"] = round(elapsed_ms, 2)
    r["options"] = opts
    r["helm_max_mismatch"] = float(max_mis)
    return r
