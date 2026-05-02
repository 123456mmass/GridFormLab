"""Economic Dispatch — KKT conditions + iterative limit enforcement.

Minimize Σ (a_i·P_i² + b_i·P_i + c_i) subject to:
    Σ P_i = P_load + P_loss
    P_min_i ≤ P_i ≤ P_max_i

KKT conditions: Equal incremental cost for all unconstrained generators.
    IC_i(P_i) = dF_i/dP_i = 2·a_i·P_i + b_i = λ

Algorithm:
    1. Estimate total load (including losses)
    2. Solve unconstrained: P_i = (λ - b_i) / (2·a_i)
    3. Σ P_i = P_target → λ = (P_target + Σ b_i/(2·a_i)) / Σ 1/(2·a_i)
    4. Enforce limits: fix violating units at limits, redistribute residual
    5. Repeat until all units within limits

Standard method used in power system operations (unit commitment pre-dispatch).
"""

from __future__ import annotations

import time as _time

import numpy as np


_DEFAULTS = {
    "include_losses": False,
    "loss_penalty_factor": 0.05,  # Estimated loss as fraction of load
    "verbose": False,
}


def solve(case_data: dict, options: dict | None = None) -> dict:
    """Run Economic Dispatch.

    Extracts generator data from case, runs KKT-based dispatch.

    Args:
        case_data: dict with bus_data (generator info) and gen_cost_data (optional)
        options: dict with include_losses, loss_penalty_factor

    Returns:
        dict with optimal dispatch, lambda, total cost, generator outputs
    """
    opts = dict(_DEFAULTS)
    if options:
        opts.update(options)

    t0 = _time.perf_counter()

    # Extract generator data from case
    bus_data = np.atleast_2d(case_data["bus_data"])
    bus_types = bus_data[:, 1].astype(int)

    # Find generator buses (slack + PV)
    gen_mask = np.isin(bus_types, [1, 2])
    gen_indices = np.where(gen_mask)[0]
    n_gen = len(gen_indices)

    if n_gen == 0:
        return {"error": "No generator buses found", "converged": False}

    # Extract or estimate generator cost data
    gen_cost = case_data.get("gen_cost_data", None)
    if gen_cost is not None:
        gen_cost = np.atleast_2d(gen_cost)
    else:
        # Default cost coefficients: a, b, c for each generator
        gen_cost = np.zeros((n_gen, 3))
        for i, bus_idx in enumerate(gen_indices):
            P_max = bus_data[bus_idx, 5]
            gen_cost[i, 0] = 0.01  # a (quadratic)
            gen_cost[i, 1] = 20.0   # b (linear)
            gen_cost[i, 2] = 0.0    # c (constant)

    # Generator limits
    P_load_total = float(np.sum(bus_data[:, 6]))  # P_load column

    P_min = np.zeros(n_gen)
    P_max = np.zeros(n_gen)
    for i, bus_idx in enumerate(gen_indices):
        pg = bus_data[bus_idx, 4]
        pcol5 = bus_data[bus_idx, 5]
        P_max[i] = max(pg, pcol5)
        P_min[i] = min(pg, pcol5)
        if P_max[i] <= 0:
            P_max[i] = P_load_total * 3.0  # slack bus: unlimited

    P_min = np.maximum(P_min, 0)  # Non-negative
    P_max = np.maximum(P_max, P_min + 0.01)  # P_max > P_min

    # Estimate losses if requested
    if opts["include_losses"]:
        P_target = P_load_total * (1.0 + opts["loss_penalty_factor"])
    else:
        P_target = P_load_total

    # Cost coefficients per generator
    a = gen_cost[:, 0].copy()
    b = gen_cost[:, 1].copy()

    # Ensure positive a (convex cost)
    a[a <= 0] = 1e-6

    # KKT iterative dispatch
    active = np.ones(n_gen, dtype=bool)
    P_opt = np.zeros(n_gen)
    lam = 0.0
    iterations = 0

    for it in range(50):
        iterations = it + 1

        # Solve unconstrained for active generators
        sum_inv_2a = np.sum(1.0 / (2.0 * a[active]))
        sum_b_over_2a = np.sum(b[active] / (2.0 * a[active]))

        # Residual power to dispatch among active units
        residual = P_target - np.sum(P_opt[~active])

        if sum_inv_2a < 1e-15:
            break

        lam = (residual + sum_b_over_2a) / sum_inv_2a

        # Compute dispatch for active units
        P_new = np.zeros(n_gen)
        P_new[active] = (lam - b[active]) / (2.0 * a[active])

        # Check limits
        violations = False
        for i in range(n_gen):
            if not active[i]:
                continue
            if P_new[i] < P_min[i]:
                P_opt[i] = P_min[i]
                active[i] = False
                violations = True
            elif P_new[i] > P_max[i]:
                P_opt[i] = P_max[i]
                active[i] = False
                violations = True
            else:
                P_opt[i] = P_new[i]

        if not violations:
            break

    # Compute total cost
    c = gen_cost[:, 2]
    total_cost = float(np.sum(a * P_opt**2 + b * P_opt + c))

    # Power balance
    P_dispatched = float(np.sum(P_opt))
    P_mismatch = P_target - P_dispatched

    elapsed_ms = (_time.perf_counter() - t0) * 1000

    return {
        "method": "Economic Dispatch (KKT)",
        "converged": abs(P_mismatch) < 1e-4 * max(abs(P_target), 1.0),
        "iterations": iterations,
        "lambda": float(lam),
        "total_cost": total_cost,
        "P_target": float(P_target),
        "P_load_total": P_load_total,
        "P_dispatched": P_dispatched,
        "P_mismatch": float(P_mismatch),
        "P_generation": P_opt.tolist(),
        "P_min": P_min.tolist(),
        "P_max": P_max.tolist(),
        "incremental_cost": (2.0 * a * P_opt + b).tolist(),
        "active_generators": active.tolist(),
        "cost_coefficients": {"a": a.tolist(), "b": b.tolist(), "c": c.tolist()},
        "execution_time_ms": round(elapsed_ms, 2),
        "options": opts,
    }
