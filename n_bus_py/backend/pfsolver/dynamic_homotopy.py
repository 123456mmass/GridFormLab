"""Dynamic Homotopy — natural parameter continuation from zero load.

Define H(x, λ) = F_λ(x) where loads/generation scale with λ.
λ: 0 → 1, where λ=0 = no load (easy), λ=1 = full load (target).

Method (natural parameter continuation):
    1. Start at λ=0: easy solution (no load, just network)
    2. Step λ forward: λ_{k+1} = λ_k + Δλ
    3. Predictor: x_pred = x_k (previous solution as initial guess)
    4. Corrector: NR on F_λ(x) = 0 at new λ
    5. Cut step if NR fails, increase if converges fast
    6. Continue until λ=1

More robust than flat-start NR for stressed/heavily-loaded systems.
"""

from __future__ import annotations

import time as _time

import numpy as np

from . import model, results, state, mismatch, jacobian

_DEFAULTS = {
    "step_size": 0.2,
    "min_step": 0.01,
    "max_corrector_iter": 20,
    "max_iter": 300,
    "tolerance": 1e-6,
    "verbose": False,
}


def solve(case_data: dict, options: dict | None = None) -> dict:
    """Run Dynamic Homotopy (natural parameter continuation).

    Starts at λ=0, steps to λ=1. Reuses previous solution as warm start.

    Args:
        case_data: dict with bus_data, line_data, base_values
        options: dict with step_size, max_iter, tolerance

    Returns:
        results dict
    """
    opts = dict(_DEFAULTS)
    if options:
        opts.update(options)

    t0 = _time.perf_counter()
    m = model.prepare_model(case_data)

    h = opts["step_size"]
    h_min = opts["min_step"]
    max_corr = opts["max_corrector_iter"]
    max_iter = opts["max_iter"]
    tol = opts["tolerance"]

    total_nr_iters = 0
    mis_hist = []

    # Save original model
    P_gen_orig = m.P_gen.copy()
    P_net_orig = m.P_net.copy()
    Q_gen_orig = m.Q_gen.copy()
    Q_net_orig = m.Q_net.copy()

    # Start at lam=0: no load, no generation (except slack covers losses)
    lam = 0.0
    x = state.initial_state(m)

    # Solve base case at lam=0
    _set_load_level(m, lam, P_gen_orig, P_net_orig, Q_gen_orig, Q_net_orig)
    ok, iters = _nr_solve(x, m, max_corr, tol, mis_hist)
    total_nr_iters += iters

    if not ok:
        # Try from different initial state
        x = state.initial_state(m)
        x[m.n_delta:] = 1.0  # all PQ voltages at 1.0
        ok, iters = _nr_solve(x, m, max_corr, tol, mis_hist)
        total_nr_iters += iters

    if not ok:
        elapsed_ms = (_time.perf_counter() - t0) * 1000
        V_f, d_f = state.state_to_voltage_angle(x, m)
        r = results.build_results(m, V_f, d_f, np.array(mis_hist), total_nr_iters, False, "Dynamic Homotopy")
        r["execution_time_ms"] = round(elapsed_ms, 2)
        r["options"] = opts
        r["error"] = "Base case (lam=0) did not converge"
        return r

    while lam < 1.0 and total_nr_iters < max_iter:
        lam_next = min(1.0, lam + h)

        # Set new load level
        _set_load_level(m, lam_next, P_gen_orig, P_net_orig, Q_gen_orig, Q_net_orig)

        # NR solve at new lam (warm start from current x)
        ok, iters = _nr_solve(x, m, max_corr, tol, mis_hist)
        total_nr_iters += iters

        if ok:
            lam = lam_next
            h = min(h * 1.2, 0.5)  # Increase step if converging well
        else:
            h *= 0.5  # Cut step
            if h < h_min:
                break
            # Restore load level
            _set_load_level(m, lam, P_gen_orig, P_net_orig, Q_gen_orig, Q_net_orig)

    # Restore original model
    m.P_gen[:] = P_gen_orig
    m.P_net[:] = P_net_orig
    m.Q_gen[:] = Q_gen_orig
    m.Q_net[:] = Q_net_orig

    V_f, d_f = state.state_to_voltage_angle(x, m)
    elapsed_ms = (_time.perf_counter() - t0) * 1000

    final_mis = float(mis_hist[-1]) if mis_hist else 1.0
    converged = lam >= 0.99 and final_mis < tol

    r = results.build_results(
        m, V_f, d_f, np.array(mis_hist), total_nr_iters, converged,
        f"Dynamic Homotopy (lam_final={lam:.3f})"
    )
    r["execution_time_ms"] = round(elapsed_ms, 2)
    r["options"] = opts
    r["homotopy_final_lambda"] = float(lam)
    return r


def _set_load_level(m, lam, P_gen_orig, P_net_orig, Q_gen_orig, Q_net_orig):
    """Scale generation and load by lambda."""
    # Loads scale with lambda, generation also scales (at PV buses)
    m.P_load_scaled = lam * m.P_load.copy()  # Not actually an attr, just conceptually
    m.P_gen[:] = lam * P_gen_orig
    m.P_net[:] = m.P_gen - lam * m.P_load
    m.Q_gen[:] = lam * Q_gen_orig
    m.Q_net[:] = m.Q_gen - lam * m.Q_load


def _nr_solve(x_io, m, max_iter, tol, mis_hist) -> tuple[bool, int]:
    """Run NR at current load level. Mutates x_io, appends to mis_hist."""
    for it in range(1, max_iter + 1):
        V, delta = state.state_to_voltage_angle(x_io, m)
        from .power_injections import calculate_power_injections
        P_calc, Q_calc = calculate_power_injections(V, delta, m.Ybus)

        dP = m.P_net[m.delta_idx] - P_calc[m.delta_idx]
        dQ = m.Q_net[m.V_idx] - Q_calc[m.V_idx]
        mis = np.concatenate([dP, dQ])

        max_mis = float(np.max(np.abs(mis)))
        mis_hist.append(max_mis)

        if max_mis < tol:
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
