"""AC OPF — pattern search over P_gen and voltage magnitudes.

Minimize generation cost subject to AC power flow constraints.

Algorithm: Coordinate pattern search
    1. Start from feasible NR solution
    2. Perturb each control variable (P_gen, V_mag) by ±step
    3. Run NR to evaluate new operating point
    4. Accept if lower cost AND all constraints satisfied
    5. Reduce step when no improvement found
    6. Repeat until step < minimum

Constraints:
    - Power flow equations (via NR convergence)
    - P_min ≤ P_gen ≤ P_max
    - V_min ≤ V ≤ V_max

No external optimization library — pure pattern search from scratch.
"""

from __future__ import annotations

import time as _time

import numpy as np

from . import model, results, state, mismatch, jacobian

_DEFAULTS = {
    "max_iter": 200,
    "step_init": 0.1,
    "step_min": 0.001,
    "step_decay": 0.7,
    "nr_max_iter": 30,
    "tolerance": 1e-6,
    "V_min": 0.90,
    "V_max": 1.10,
    "flow_penalty": 1e3,
    "verbose": False,
}


def solve(case_data: dict, options: dict | None = None) -> dict:
    """Run AC Optimal Power Flow via pattern search.

    Args:
        case_data: dict with bus_data, line_data, base_values, gen_cost_data (optional)
        options: dict with max_iter, step_init, step_min, nr_max_iter, tolerance

    Returns:
        results dict with optimal dispatch, voltages, cost
    """
    opts = dict(_DEFAULTS)
    if options:
        opts.update(options)

    t0 = _time.perf_counter()
    m = model.prepare_model(case_data)

    gen_buses = np.concatenate([m.slack_buses, m.pv_buses]).astype(int)
    n_gen = len(gen_buses)

    # Cost data
    gen_cost = case_data.get("gen_cost_data")
    if gen_cost is not None:
        gen_cost = np.atleast_2d(gen_cost)
    else:
        gen_cost = np.zeros((n_gen, 3))
        for i in range(n_gen):
            gen_cost[i, 0] = 0.01
            gen_cost[i, 1] = 20.0
            gen_cost[i, 2] = 0.0

    a_cost = gen_cost[:, 0]
    b_cost = gen_cost[:, 1]
    c_cost = gen_cost[:, 2]

    # Control bounds
    P_max = np.array([max(m.P_gen[b], m.P_load[b] + 0.1, 0.5) for b in gen_buses])
    P_min = np.zeros(n_gen)
    for i, b in enumerate(gen_buses):
        P_min[i] = max(0.0, m.P_load[b] * 0.2 if m.P_load[b] > 0 else 0.0)

    V_min_ctrl = opts["V_min"]
    V_max_ctrl = opts["V_max"]
    flow_penalty = opts["flow_penalty"]

    # Initial feasible solution via NR
    x_base = state.initial_state(m)
    base_converged, nr_iters = _run_nr(x_base, m, opts["nr_max_iter"], opts["tolerance"])
    if not base_converged:
        return {
            "method": "AC OPF (Pattern Search)",
            "converged": False,
            "error": "Base case NR did not converge",
            "execution_time_ms": 0.0,
        }

    V_base, delta_base = state.state_to_voltage_angle(x_base, m)
    P_gen_base = _extract_gen_power(V_base, delta_base, m, gen_buses)
    V_gen_base = V_base[gen_buses].copy()

    best_cost = _compute_cost(P_gen_base, a_cost, b_cost, c_cost)
    best_P = P_gen_base.copy()
    best_V = V_gen_base.copy()
    best_x = x_base.copy()

    step = opts["step_init"]
    step_min = opts["step_min"]
    decay = opts["step_decay"]
    max_iter = opts["max_iter"]
    total_nr_iters = nr_iters

    # Save original P_gen / P_net to restore between perturbations
    P_gen_orig = m.P_gen.copy()
    P_net_orig = m.P_net.copy()

    for _it in range(max_iter):
        improved = False

        for var_idx in range(n_gen * 2):
            gen_idx = var_idx // 2
            is_V = (var_idx % 2 == 1)
            bus = gen_buses[gen_idx]

            for direction in [-1, 1]:
                if is_V:
                    # Voltage perturbation: adjust V in state
                    new_V = best_V[gen_idx] + direction * step
                    new_V = np.clip(new_V, V_min_ctrl, V_max_ctrl)
                    if abs(new_V - best_V[gen_idx]) < 1e-12:
                        continue

                    x_test = best_x.copy()
                    # Find position of this bus in V_idx
                    if bus in m.V_idx:
                        idx_in_V = list(m.V_idx).index(bus)
                        x_test[m.n_delta + idx_in_V] = new_V
                else:
                    # P_gen perturbation: modify model P_net temporarily
                    new_P = best_P[gen_idx] + direction * step * P_max[gen_idx]
                    new_P = np.clip(new_P, P_min[gen_idx], P_max[gen_idx])
                    if abs(new_P - best_P[gen_idx]) < 1e-12:
                        continue

                    # Apply perturbation to model
                    m.P_gen[bus] = new_P
                    m.P_net[bus] = new_P - m.P_load[bus]
                    x_test = best_x.copy()

                # Run NR
                x_try = x_test.copy()
                converged, nr_i = _run_nr(x_try, m, opts["nr_max_iter"], opts["tolerance"])
                total_nr_iters += nr_i

                # Restore model if P was modified
                if not is_V:
                    m.P_gen[bus] = P_gen_orig[bus]
                    m.P_net[bus] = P_net_orig[bus]

                if not converged:
                    continue

                V_try, delta_try = state.state_to_voltage_angle(x_try, m)
                P_gen_try = _extract_gen_power(V_try, delta_try, m, gen_buses)

                feasible, penalty = _check_constraints(
                    V_try, delta_try, m, P_gen_try,
                    P_min, P_max, V_min_ctrl, V_max_ctrl, flow_penalty
                )

                cost_try = _compute_cost(P_gen_try, a_cost, b_cost, c_cost) + penalty

                if feasible and cost_try < best_cost - 1e-10:
                    best_cost = cost_try
                    best_P = P_gen_try.copy()
                    best_V = V_try[gen_buses].copy()
                    best_x = x_try.copy()
                    improved = True

        if not improved:
            step *= decay
            if step < step_min:
                break

    V_final, delta_final = state.state_to_voltage_angle(best_x, m)
    elapsed_ms = (_time.perf_counter() - t0) * 1000

    r = results.build_results(
        m, V_final, delta_final, np.array([best_cost]), total_nr_iters, True,
        "AC OPF (Pattern Search)"
    )
    r["execution_time_ms"] = round(elapsed_ms, 2)
    r["options"] = opts
    r["opf_total_cost"] = float(best_cost)
    r["opf_P_gen"] = best_P.tolist()
    r["opf_V_gen"] = best_V.tolist()
    r["opf_gen_buses"] = gen_buses.tolist()
    return r


def _run_nr(x, m, max_iter, tol) -> tuple[bool, int]:
    """Run NR from state x. Returns (converged, iterations). Modifies x in place."""
    for it in range(1, max_iter + 1):
        V, delta = state.state_to_voltage_angle(x, m)
        P_calc, Q_calc = _calc_power(V, delta, m.Ybus)
        dP = m.P_net[m.delta_idx] - P_calc[m.delta_idx]
        dQ = m.Q_net[m.V_idx] - Q_calc[m.V_idx]
        mis = np.concatenate([dP, dQ])

        if np.max(np.abs(mis)) < tol:
            return True, it

        J = jacobian.build_jacobian(V, delta, P_calc, Q_calc, m)
        try:
            dx = jacobian.solve_jacobian(J, mis)
        except np.linalg.LinAlgError:
            return False, it

        x += dx
        V_vals = x[m.n_delta:]
        V_vals[V_vals <= 0] = 0.1
        x[m.n_delta:] = V_vals

    return False, max_iter


def _extract_gen_power(V, delta, m, gen_buses) -> np.ndarray:
    """Extract P_gen at generator buses from converged state."""
    P_calc, Q_calc = _calc_power(V, delta, m.Ybus)
    P_gen = np.zeros(len(gen_buses))
    for i, b in enumerate(gen_buses):
        P_gen[i] = P_calc[b] + m.P_load[b]
    return P_gen


def _compute_cost(P_gen, a, b, c) -> float:
    """Quadratic cost: Σ (a·P² + b·P + c)."""
    return float(np.sum(a * P_gen**2 + b * P_gen + c))


def _check_constraints(V, delta, m, P_gen, P_min, P_max, V_min, V_max, flow_penalty):
    """Check all OPF constraints. Returns (feasible, penalty)."""
    penalty = 0.0
    feasible = True

    for i in m.pq_buses:
        if V[i] < V_min:
            penalty += flow_penalty * (V_min - V[i])**2
            feasible = False
        elif V[i] > V_max:
            penalty += flow_penalty * (V[i] - V_max)**2
            feasible = False

    for i in range(len(P_gen)):
        if P_gen[i] < P_min[i] - 1e-9:
            penalty += flow_penalty * (P_min[i] - P_gen[i])**2
            feasible = False
        elif P_gen[i] > P_max[i] + 1e-9:
            penalty += flow_penalty * (P_gen[i] - P_max[i])**2
            feasible = False

    return feasible, penalty


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
