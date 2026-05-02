"""CPF Load Scaling — repeated NR with incremental load increase.

Simpler alternative to predictor-corrector CPF. Runs full NR at each
load level λ, stepping λ from start to target/max. Records P-V curve
at each converged point.

Less sophisticated than arclength CPF but easier to implement and debug.
Useful for: P-V nose curve tracing, voltage stability margin calculation.
"""

from __future__ import annotations

import time as _time

import numpy as np

from . import model, results, state, mismatch, jacobian

_DEFAULTS = {
    "lambda_start": 0.0,
    "lambda_target": 3.0,
    "lambda_step": 0.1,
    "nr_max_iter": 30,
    "tolerance": 1e-6,
    "verbose": False,
}


def solve(case_data: dict, options: dict | None = None) -> dict:
    """Run CPF via direct load scaling.

    Solves full NR at each λ level, reusing previous solution as initial guess.

    Args:
        case_data: dict with bus_data, line_data, base_values
        options: dict with lambda_start, lambda_target, lambda_step, etc.

    Returns:
        results dict at final λ with full P-V curve data
    """
    opts = dict(_DEFAULTS)
    if options:
        opts.update(options)

    t0 = _time.perf_counter()
    m = model.prepare_model(case_data)

    lam_start = opts["lambda_start"]
    lam_target = opts["lambda_target"]
    lam_step = opts["lambda_step"]
    nr_max_iter = opts["nr_max_iter"]
    tol = opts["tolerance"]

    # Solve base case (λ = lam_start) — use flat start for first solve
    x = state.initial_state(m)
    pv_curve = []
    total_nr_iters = 0
    max_lam = lam_start
    min_voltage = 1.0

    lam = lam_start
    converged = True

    while lam <= lam_target + 1e-9:
        lam_converged, nr_iters = _solve_at_lambda(x, m, lam, nr_max_iter, tol)

        if lam_converged:
            total_nr_iters += nr_iters
            V_f, d_f = state.state_to_voltage_angle(x, m)
            avg_v = float(np.mean(V_f[m.V_idx])) if len(m.V_idx) > 0 else 1.0
            pv_curve.append((float(lam), avg_v))
            max_lam = lam
            min_voltage = min(min_voltage, avg_v)

            lam += lam_step
            # Use current solution as warm-start for next λ
        else:
            # Reduce step size near nose
            lam_step *= 0.5
            if lam_step < 1e-4:
                converged = False
                break
            lam -= lam_step * 2  # Back up slightly
            if lam < lam_start:
                lam = lam_start
            # Re-solve from base case at this λ
            x = state.initial_state(m)
            lam += lam_step

    V_f, d_f = state.state_to_voltage_angle(x, m)
    elapsed_ms = (_time.perf_counter() - t0) * 1000

    r = results.build_results(
        m, V_f, d_f, np.array([max_lam]), total_nr_iters,
        converged, f"CPF Load Scaling (λ_max={max_lam:.2f})"
    )
    r["execution_time_ms"] = round(elapsed_ms, 2)
    r["options"] = opts
    r["cpf_lambda_final"] = float(max_lam)
    r["cpf_nose_lambda"] = float(max_lam)
    r["cpf_pv_curve"] = [(float(l), float(v)) for l, v in pv_curve]
    r["cpf_steps"] = len(pv_curve)
    return r


def _solve_at_lambda(x_io, m, lam, max_iter, tol) -> tuple[bool, int]:
    """Solve power flow at load level λ. Mutates x_io in place.

    Returns (converged, iterations).
    """
    for it in range(1, max_iter + 1):
        V, delta = state.state_to_voltage_angle(x_io, m)
        P_calc, Q_calc = _calc_power(V, delta, m.Ybus)

        # Scaled mismatch
        P_target = m.P_gen - lam * m.P_load
        Q_target = m.Q_gen - lam * m.Q_load

        dP = P_target[m.delta_idx] - P_calc[m.delta_idx]
        dQ = Q_target[m.V_idx] - Q_calc[m.V_idx]
        mis = np.concatenate([dP, dQ])

        if np.max(np.abs(mis)) < tol:
            return True, it

        J = jacobian.build_jacobian(V, delta, P_calc, Q_calc, m)
        try:
            dx = jacobian.solve_jacobian(J, mis)
        except np.linalg.LinAlgError:
            return False, it

        x_io += dx
        V_vals = x_io[m.n_delta:]
        V_vals[V_vals <= 0] = 0.1
        x_io[m.n_delta:] = V_vals

    return False, max_iter


def _calc_power(V, delta, Ybus):
    G = Ybus.real
    B = Ybus.imag
    d_ij = delta[:, None] - delta[None, :]
    VV = V[:, None] * V[None, :]
    cos_d = np.cos(d_ij)
    sin_d = np.sin(d_ij)
    P = V * np.sum(VV * (G * cos_d + B * sin_d), axis=1)
    Q = V * np.sum(VV * (G * sin_d - B * cos_d), axis=1)
    return P, Q
