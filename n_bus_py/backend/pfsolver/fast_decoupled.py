"""Fast Decoupled Load Flow — XB scheme.

B' and B'' are constant, factored once. Decoupled P-δ and Q-V iterations.
3-5x faster than full NR, standard in industry.

Formulation (Stott & Alsac, 1974):
    ΔP/V = B' * Δδ   →   Δδ = B'⁻¹ * (ΔP/V)
    ΔQ/V = B'' * ΔV   →   ΔV = B''⁻¹ * (ΔQ/V)

Key: B' uses 1/X values (ignore R, shunts, taps), B'' uses the same.
These are NOT the same as the NR Jacobian sub-blocks.
"""

from __future__ import annotations

import time as _time

import numpy as np

from . import model, power_injections
from .solver_helpers import build_result

_DEFAULTS = {
    "max_iter": 50,
    "tolerance": 1e-6,
    "verbose": False,
}


def solve(case_data: dict, options: dict | None = None) -> dict:
    """Run Fast Decoupled Load Flow (XB scheme).

    Uses separate B', B'' constructed from 1/X branch susceptances.
    """
    opts = dict(_DEFAULTS)
    if options:
        opts.update(options)

    t0 = _time.perf_counter()
    m = model.prepare_model(case_data)

    max_iter = opts["max_iter"]
    tol = opts["tolerance"]

    # Build B' (for P-δ) and B'' (for Q-V) from branch reactances
    N = m.num_buses
    line_data = m.line_data
    X = line_data[:, 3].copy()
    X[X == 0] = 1e-10  # avoid div-by-zero

    B1 = np.zeros((N, N))
    B2 = np.zeros((N, N))

    for k in range(m.num_lines):
        f = m.line_from_idx[k]
        t = m.line_to_idx[k]
        bij = 1.0 / X[k]

        B1[f, f] += bij
        B1[t, t] += bij
        B1[f, t] -= bij
        B1[t, f] -= bij

        B2[f, f] += bij
        B2[t, t] += bij
        B2[f, t] -= bij
        B2[t, f] -= bij

    # Extract B' = B1[delta_idx, delta_idx], B'' = B2[V_idx, V_idx]
    B_prime = B1[np.ix_(m.delta_idx, m.delta_idx)]
    B_double_prime = B2[np.ix_(m.V_idx, m.V_idx)]

    # Pre-factor
    try:
        Bp_inv = np.linalg.inv(B_prime)
        Bdp_inv = np.linalg.inv(B_double_prime)
    except np.linalg.LinAlgError:
        return _failed_result(m, "Singular B' or B'' matrix")

    # Initial state
    V = m.V_spec.copy()
    delta = np.deg2rad(m.angle_spec_deg.copy())
    V[V == 0] = 1.0

    mis_hist = []

    for it in range(1, max_iter + 1):
        P_calc, Q_calc = power_injections.calculate_power_injections(V, delta, m.Ybus)

        # ── P-δ correction ──
        dP = m.P_net[m.delta_idx] - P_calc[m.delta_idx]
        dP_div_V = dP / np.maximum(V[m.delta_idx], 0.01)
        d_delta = Bp_inv @ dP_div_V
        delta[m.delta_idx] += d_delta

        # ── Q-V correction ──
        dQ = m.Q_net[m.V_idx] - Q_calc[m.V_idx]
        dQ_div_V = dQ / np.maximum(V[m.V_idx], 0.01)
        dV_corr = Bdp_inv @ dQ_div_V
        V[m.V_idx] += dV_corr

        # Guard
        V = np.maximum(V, 0.01)

        max_mis = float(max(np.max(np.abs(dP)), np.max(np.abs(dQ))))
        mis_hist.append(max_mis)

        if max_mis < tol:
            return build_result(m, V.copy(), delta.copy(), mis_hist,
                              it, True, "Fast Decoupled (XB)", t0, opts)
    return build_result(m, V.copy(), delta.copy(), mis_hist,
                       max_iter, False, "Fast Decoupled (XB)", t0, opts)



def _failed_result(m, reason):
    return {
        "method": "Fast Decoupled (XB)",
        "converged": False,
        "iterations": 0,
        "error": reason,
        "bus_voltage": m.V_spec,
        "bus_angle_deg": m.angle_spec_deg,
    }
