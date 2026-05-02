"""CPF Predictor-Corrector — arclength continuation power flow.

Traces P-V curve by solving the augmented system:
    F(x, λ) = P(λ) - P_calc(x) = 0  (power flow at load level λ)
    (x-x_prev)^T * v_x + (λ-λ_prev) * v_λ = Δs  (arclength constraint)

Uses local parametrization (fix λ during corrector) for stability.
Standard tool for voltage stability analysis (P-V / Q-V nose curves).
"""

from __future__ import annotations

import time as _time

import numpy as np

from . import model, results, state, jacobian

_DEFAULTS = {
    "lambda_start": 0.0,
    "lambda_target": 2.5,
    "step_size": 0.2,
    "max_corrector_iter": 15,
    "max_steps": 100,
    "nr_max_iter": 30,
    "tolerance": 1e-6,
    "verbose": False,
}


def solve(case_data: dict, options: dict | None = None) -> dict:
    """Run CPF Predictor-Corrector continuation.

    Uses local parametrization: predictor via tangent, corrector via NR
    at fixed lambda. Step is cut if corrector diverges.

    Args:
        case_data: dict with bus_data, line_data, base_values
        options: dict with lambda_start, lambda_target, step_size, etc.

    Returns:
        results dict with P-V curve points, nose point estimate
    """
    opts = dict(_DEFAULTS)
    if options:
        opts.update(options)

    t0 = _time.perf_counter()
    m = model.prepare_model(case_data)

    lam_target = opts["lambda_target"]
    step = opts["step_size"]
    max_corr = opts["max_corrector_iter"]
    max_steps = opts["max_steps"]
    tol = opts["tolerance"]

    # Solve base case at lam=0 (no load) using NR
    x = state.initial_state(m)
    lam = 0.0

    _save_gen = m.P_gen.copy()
    _save_net = m.P_net.copy()

    # Base NR
    ok, iters = _nr_solve_lambda(x, m, lam, opts["nr_max_iter"], tol)
    if not ok:
        elapsed_ms = (_time.perf_counter() - t0) * 1000
        return {
            "method": "CPF PC", "converged": False,
            "error": f"Base case (lam=0) NR did not converge",
            "execution_time_ms": round(elapsed_ms, 2), "options": opts,
        }

    total_iters = iters
    pv_curve = [(float(lam), float(np.mean(x[m.n_delta:])))]

    x_prev = x.copy()
    lam_prev = lam

    v_x_prev = None  # previous tangent for arclength

    for _step_num in range(max_steps):
        if lam >= lam_target:
            break

        # Predictor: compute tangent via secant (previous two points)
        if v_x_prev is None:
            # First step: perturb lam and solve to get tangent direction
            x_pred = x.copy()
            lam_pred = lam + step
            ok_pred, _ = _nr_solve_lambda(x_pred, m, lam_pred, max_corr, tol)

            if not ok_pred:
                step *= 0.5
                if step < 1e-4:
                    break
                continue

            v_x = (x_pred - x) / step
            v_lam = 1.0
        else:
            v_x = v_x_prev.copy()
            v_lam = (lam - lam_prev) / step
            if v_lam < 0:
                v_x = -v_x
                v_lam = -v_lam

        # Tangent step
        x_pred = x + step * v_x
        lam_pred = lam + step * v_lam

        # Corrector: NR at fixed lambda
        x_corr = x_pred.copy()
        lam_corr = lam_pred
        ok_corr, iters_corr = _nr_solve_lambda(x_corr, m, lam_corr, max_corr, tol)
        total_iters += iters_corr

        if ok_corr:
            # Accept
            x_prev = x.copy()
            lam_prev = lam
            v_x_prev = (x_corr - x) / (lam_corr - lam) if abs(lam_corr - lam) > 1e-12 else v_x
            x = x_corr.copy()
            lam = lam_corr
            pv_curve.append((float(lam), float(np.mean(x[m.n_delta:]))))
            step = min(step * 1.3, opts["step_size"] * 3)
        else:
            step *= 0.5
            if step < 1e-4:
                break

    # Restore original model
    m.P_gen[:] = _save_gen
    m.P_net[:] = _save_net

    V_f, d_f = state.state_to_voltage_angle(x, m)
    elapsed_ms = (_time.perf_counter() - t0) * 1000

    lam_values = [p[0] for p in pv_curve]
    nose_lambda = max(lam_values) if lam_values else lam

    from . import results as res_mod
    r = res_mod.build_results(
        m, V_f, d_f, np.array([float(lam)]), total_iters,
        lam >= lam_target * 0.5, "CPF PC"
    )
    r["execution_time_ms"] = round(elapsed_ms, 2)
    r["options"] = opts
    r["cpf_lambda_final"] = float(lam)
    r["cpf_nose_lambda"] = float(nose_lambda)
    r["cpf_pv_curve"] = [(float(l), float(v)) for l, v in pv_curve]
    r["cpf_steps"] = len(pv_curve)
    return r


def _nr_solve_lambda(x_io, m, lam, max_iter, tol) -> tuple[bool, int]:
    """Run NR at load level lambda. Mutates x_io in place."""
    for it in range(1, max_iter + 1):
        V, delta = state.state_to_voltage_angle(x_io, m)
        from .power_injections import calculate_power_injections
        P_calc, Q_calc = calculate_power_injections(V, delta, m.Ybus)

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
