"""DC Power Flow — linear approximation of AC power flow.

Assumptions:
- All bus voltages = 1.0 pu
- Line resistances << reactances (R ≈ 0)
- Small angle differences (sin(θ) ≈ θ)

P = B * θ    where B(i,j) = -1/X_ij, B(i,i) = Σ(1/X_ij)
θ_slack = 0
θ = B_reduced⁻¹ * P_reduced  (single linear solve, NO iterations)
P_line = (θ_from - θ_to) / X_line

Used in: market clearing, generation planning, contingency analysis,
         security-constrained OPF, N-1 screening
"""

from __future__ import annotations

import time as _time

import numpy as np


_DEFAULTS = {
    "ignore_resistance": True,
    "verbose": False,
}


def solve(case_data: dict, options: dict | None = None) -> dict:
    """Run DC power flow (single linear solve).

    Args:
        case_data: dict with bus_data, line_data, base_values
        options: dict with ignore_resistance

    Returns:
        results dict with angles, line flows, no voltages
    """
    opts = dict(_DEFAULTS)
    if options:
        opts.update(options)

    t0 = _time.perf_counter()

    # Normalize
    from .model import normalize_case_data
    cd = normalize_case_data(case_data)
    bus_data = cd["bus_data"]
    line_data = cd["line_data"]
    system_name = cd.get("system_name", "Unknown")

    num_buses = bus_data.shape[0]
    num_lines = line_data.shape[0]
    bus_ids = bus_data[:, 0].astype(int).tolist()

    # Bus indices
    id_to_idx = {bid: i for i, bid in enumerate(bus_ids)}
    line_from_idx = np.array([id_to_idx[int(b)] for b in line_data[:, 0]], dtype=int)
    line_to_idx = np.array([id_to_idx[int(b)] for b in line_data[:, 1]], dtype=int)

    # Build B matrix (susceptance-based)
    X = line_data[:, 3].copy()
    # Avoid division by zero
    X[X == 0] = 1e-10

    B = np.zeros((num_buses, num_buses))
    for k in range(num_lines):
        f = line_from_idx[k]
        t = line_to_idx[k]
        b_ij = 1.0 / X[k]
        B[f, f] += b_ij
        B[t, t] += b_ij
        B[f, t] -= b_ij
        B[t, f] -= b_ij

    # Identify slack bus
    bus_types = bus_data[:, 1].astype(int)
    slack_idx = int(np.where(bus_types == 1)[0][0])

    # Remove slack row and column
    non_slack = [i for i in range(num_buses) if i != slack_idx]
    B_red = B[np.ix_(non_slack, non_slack)]

    # Power injection: P_net = P_gen - P_load (pu)
    P_gen = bus_data[:, 4]
    P_load = bus_data[:, 6]
    P_net = P_gen - P_load
    P_red = P_net[non_slack]

    # Solve B_red * θ_red = P_red
    try:
        theta_red = np.linalg.solve(B_red, P_red)
    except np.linalg.LinAlgError:
        theta_red = np.linalg.lstsq(B_red, P_red, rcond=None)[0]

    # Full angle vector (slack = 0)
    theta = np.zeros(num_buses)
    theta[non_slack] = theta_red

    # Compute line flows: P_line = (θ_from - θ_to) / X
    P_flow = np.zeros(num_lines)
    for k in range(num_lines):
        f = line_from_idx[k]
        t = line_to_idx[k]
        P_flow[k] = (theta[f] - theta[t]) / X[k]

    # Power balance
    P_loss = 0.0  # DC approximation has no losses
    P_total_gen = float(np.sum(P_net[P_net > 0]))  # approximation

    elapsed_ms = (_time.perf_counter() - t0) * 1000

    return {
        "system_name": system_name,
        "method": "DC Power Flow",
        "external_bus_ids": np.array(bus_ids),
        "bus_angle_deg": np.rad2deg(theta),
        "bus_angle": theta,
        "bus_voltage": np.ones(num_buses),  # DC assumption
        "bus_voltage_kV": np.full(num_buses, cd["base_values"].get("V_base_kV", 230.0)),
        "P_injection": P_net,
        "P_total_gen": P_total_gen,
        "P_total_load": float(np.sum(P_load)),
        "P_loss_total": P_loss,
        "Q_loss_total": 0.0,
        "line_endpoints": line_data[:, :2].astype(int),
        "line_flow_P": P_flow,
        "line_flow_Q": np.zeros(num_lines),
        "line_loss_P": np.zeros(num_lines),
        "line_loss_Q": np.zeros(num_lines),
        "iterations": 1,
        "converged": True,
        "execution_time_ms": round(elapsed_ms, 4),
        "options": opts,
        "metadata": {
            "num_buses": num_buses,
            "num_lines": num_lines,
            "slack_bus_id": bus_ids[slack_idx],
            "is_linear": True,
        },
    }
