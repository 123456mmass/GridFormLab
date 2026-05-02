"""Gauss-Seidel power flow solver with acceleration factor.

Port of: +pfsolver/powerflow_gauss_seidel.m (133 lines)
"""

from __future__ import annotations

import time as _time

import numpy as np

from . import mismatch, model, power_injections
from .solver_helpers import build_result

_DEFAULTS = {
    "max_iter": 300,
    "tolerance": 1e-6,
    "acceleration": 1.4,
    "verbose": False,
}


def solve(case_data: dict, options: dict | None = None) -> dict:
    """Run Gauss-Seidel power flow.

    Args:
        case_data: dict with system_name, base_values, bus_data, line_data
        options: optional dict with max_iter, tolerance, acceleration

    Returns:
        results dict
    """
    opts = dict(_DEFAULTS)
    if options:
        opts.update(options)

    t0 = _time.perf_counter()
    m = model.prepare_model(case_data)

    accel = opts["acceleration"]
    max_iter = opts["max_iter"]
    tol = opts["tolerance"]

    # Complex voltage vector: flat start
    Vc = m.V_spec * np.exp(1j * np.deg2rad(m.angle_spec_deg))
    # Force PQ buses to 1.0 + j0 at start
    Vc[m.pq_buses] = 1.0 + 0j

    Ybus = m.Ybus
    mis_hist = []

    for it in range(1, max_iter + 1):
        max_mis = 0.0

        # Update each non-slack bus
        all_buses = np.arange(m.num_buses)
        non_slack = all_buses[~np.isin(all_buses, m.slack_buses)]

        for i in non_slack:
            i = int(i)
            # Sum over all OTHER buses
            sum_yv = Ybus[i] @ Vc - Ybus[i, i] * Vc[i]

            if i in m.pv_buses:
                # For PV: calculate Q to maintain |V|
                Q_calc = -np.imag(np.conj(Vc[i]) * (Ybus[i] @ Vc))
                S_spec = m.P_net[i] + 1j * Q_calc
            else:
                S_spec = m.P_net[i] + 1j * m.Q_net[i]

            V_raw = (np.conj(S_spec) / np.conj(Vc[i]) - sum_yv) / Ybus[i, i]

            # Acceleration
            V_new = Vc[i] + accel * (V_raw - Vc[i])

            # Enforce PV voltage magnitude
            if i in m.pv_buses:
                V_new = m.V_spec[i] * np.exp(1j * np.angle(V_new))

            # Guard against zero/nan
            if np.abs(V_new) < 1e-10 or not np.isfinite(V_new):
                V_new = 0.1 * np.exp(1j * np.angle(Vc[i]) if abs(Vc[i]) > 1e-10 else 0)

            Vc[i] = V_new

        # Check convergence via shared mismatch function
        V_abs = np.abs(Vc)
        delta = np.angle(Vc)
        P_calc, Q_calc = power_injections.calculate_power_injections(
            V_abs, delta, Ybus
        )
        mis_vec, _, _, _, _ = mismatch.calculate_mismatch(
            np.array([]), m, P_calc=P_calc, Q_calc=Q_calc, V=V_abs, delta=delta
        )
        max_mis = float(np.max(np.abs(mis_vec)))
        mis_hist.append(max_mis)

        if max_mis < tol:
            return build_result(m, np.abs(Vc), np.angle(Vc), mis_hist,
                              it, True, "Gauss-Seidel", t0, opts, acceleration=accel)
    return build_result(m, np.abs(Vc), np.angle(Vc), mis_hist,
                       max_iter, False, "Gauss-Seidel", t0, opts, acceleration=accel)
