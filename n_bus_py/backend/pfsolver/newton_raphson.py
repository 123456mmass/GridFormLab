"""Newton-Raphson power flow solver with Q-limit enforcement.

Port of: +pfsolver/powerflow_newton_raphson.m (234 lines)
"""

from __future__ import annotations

import time as _time

import numpy as np
from scipy.sparse.linalg import spsolve

from . import jacobian, mismatch, model, state
from .solver_helpers import build_result

_DEFAULTS = {
    "max_iter": 20,
    "tolerance": 1e-6,
    "enforce_q_limits": False,
    "q_limit_tolerance": 1e-4,
    "max_q_limit_switches": 20,
    "verbose": False,
}


def solve(case_data: dict, options: dict | None = None) -> dict:
    """Run Newton-Raphson power flow.

    Args:
        case_data: dict with system_name, base_values, bus_data, line_data
        options: optional dict with max_iter, tolerance, etc.

    Returns:
        results dict with voltages, powers, line flows, metadata
    """
    opts = dict(_DEFAULTS)
    if options:
        opts.update(options)

    t0 = _time.perf_counter()
    m = model.prepare_model(case_data)
    working_bus_data = m.bus_data.copy()

    q_switching_events = []
    q_switching_rounds = 0

    converged = False
    iterations = 0
    mismatch_hist = np.array([])
    V_final = m.V_spec.copy()
    delta_final = np.deg2rad(m.angle_spec_deg.copy())

    while True:
        # Build model with current working bus data
        cd = dict(case_data)
        cd["bus_data"] = working_bus_data
        m = model.prepare_model(cd)

        x = state.initial_state(m)
        iters, conv, mis_hist = _solve_base(x, m, opts)

        V_final, delta_final = state.state_to_voltage_angle(x, m)

        if not conv:
            converged = False
            iterations = iters
            mismatch_hist = mis_hist
            break

        converged = True
        iterations = iters
        mismatch_hist = mis_hist

        # Q-limit enforcement
        if not opts["enforce_q_limits"]:
            break

        if q_switching_rounds >= opts["max_q_limit_switches"]:
            break

        # Check PV bus Q violations
        Q_calc, _ = _compute_gen_Q(V_final, delta_final, m)
        violations = _check_q_violations(m, Q_calc, opts["q_limit_tolerance"])

        if not violations:
            break

        q_switching_rounds += 1
        for bus_idx, new_type in violations:
            q_switching_events.append(
                {
                    "round": q_switching_rounds,
                    "bus": int(m.external_bus_ids[bus_idx]),
                    "old_type": int(working_bus_data[bus_idx, 1]),
                    "new_type": new_type,
                }
            )
            working_bus_data[bus_idx, 1] = new_type

        # Warm-start voltages from last solution
        working_bus_data[:, 2] = V_final
        working_bus_data[:, 3] = np.rad2deg(delta_final)

    return build_result(
        m, V_final, delta_final, mismatch_hist, iterations, converged,
        "Newton-Raphson", t0, opts,
        q_limit_switching={
            "enabled": opts["enforce_q_limits"],
            "events": q_switching_events,
            "rounds": q_switching_rounds,
        },
    )


def _solve_base(x: np.ndarray, m, opts: dict) -> tuple[int, bool, np.ndarray]:
    """Core NR iteration loop on a single bus-type configuration."""
    max_iter = opts["max_iter"]
    tol = opts["tolerance"]
    mis_hist = []

    for it in range(1, max_iter + 1):
        mis, P_c, Q_c, V, delta = mismatch.calculate_mismatch(x, m)

        max_mis = float(np.max(np.abs(mis)))
        mis_hist.append(max_mis)

        if max_mis < tol:
            return it, True, np.array(mis_hist)

        J = jacobian.build_jacobian(V, delta, P_c, Q_c, m, sparse=True)
        try:
            dx = spsolve(J, mis)
        except Exception:
            return it, False, np.array(mis_hist)

        x += dx

        # Guard against negative voltages
        V_vals = x[m.n_delta :]
        zero_mask = V_vals <= 0
        if np.any(zero_mask):
            V_vals[zero_mask] = 0.1
            x[m.n_delta :] = V_vals

    return max_iter, False, np.array(mis_hist)


def _compute_gen_Q(V, delta, m):
    """Compute reactive power at generator buses."""
    from . import power_injections

    P, Q = power_injections.calculate_power_injections(V, delta, m.Ybus)
    gen_buses = np.concatenate([m.slack_buses, m.pv_buses]).astype(int)
    Q_gen = Q[gen_buses] + m.Q_load[gen_buses]
    return Q_gen, gen_buses


def _check_q_violations(m, Q_actual, tol) -> list[tuple[int, int]]:
    """Return list of (bus_index, new_type) for PV buses violating Q limits."""
    violations = []
    for idx in m.pv_buses:
        q = Q_actual[idx] if idx in np.concatenate([m.slack_buses, m.pv_buses]) else 0
        # Recalculate precisely
        P, Q = power_injections.calculate_power_injections(
            m.V_spec, np.deg2rad(m.angle_spec_deg), m.Ybus
        )
        q = Q[idx] + m.Q_load[idx]

        if q > m.Q_max[idx] + tol:
            violations.append((int(idx), 3))  # Switch PV -> PQ
        elif q < m.Q_min[idx] - tol:
            violations.append((int(idx), 3))  # Switch PV -> PQ

    return violations


# Import at bottom for circular reference
from . import power_injections  # noqa: E402
