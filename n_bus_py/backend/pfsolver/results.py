"""Assemble power flow results dict from converged state.

Port of: internal/core/pf_build_results.m (122 lines)
"""

from __future__ import annotations

import numpy as np

from . import power_injections


def build_results(
    model,
    V_final: np.ndarray,
    delta_final: np.ndarray,
    mismatch_history: np.ndarray,
    iterations: int,
    converged: bool,
    method_name: str,
) -> dict:
    """Build complete results dict from converged (or final) state.

    Returns dict with all standard fields matching the MATLAB output.
    """
    P_final, Q_final = power_injections.calculate_power_injections(
        V_final, delta_final, model.Ybus
    )

    # Actual generation at generator buses (slack + PV)
    P_gen_actual = model.P_gen.copy()
    Q_gen_actual = model.Q_gen.copy()
    gen_buses = np.concatenate([model.slack_buses, model.pv_buses]).astype(int)
    P_gen_actual[gen_buses] = P_final[gen_buses] + model.P_load[gen_buses]
    Q_gen_actual[gen_buses] = Q_final[gen_buses] + model.Q_load[gen_buses]

    # Line flows and losses
    P_from, Q_from, P_loss_line, Q_loss_line = power_injections.calculate_line_flows(
        V_final, delta_final, model.line_data, model.line_from_idx, model.line_to_idx
    )

    # Totals
    P_total_gen = float(np.sum(P_gen_actual))
    Q_total_gen = float(np.sum(Q_gen_actual))
    P_total_load = float(np.sum(model.P_load))
    Q_total_load = float(np.sum(model.Q_load))
    P_total_loss = float(np.sum(P_loss_line))
    Q_total_loss = float(np.sum(Q_loss_line))

    # Shunt injections
    P_shunt = -(V_final**2) * model.G_shunt
    Q_shunt = (V_final**2) * model.B_shunt

    V_base_kV = model.base_values.get("V_base_kV", 0.0)
    if V_base_kV > 0:
        V_display_kV = V_final * V_base_kV
    else:
        V_display_kV = np.full_like(V_final, np.nan)

    return {
        "system_name": model.system_name,
        "method": method_name,
        "external_bus_ids": model.external_bus_ids,
        "bus_type": model.bus_type,
        "bus_voltage": V_final,
        "bus_voltage_kV": V_display_kV,
        "bus_angle": delta_final,
        "bus_angle_deg": np.rad2deg(delta_final),
        "P_generation": P_gen_actual,
        "Q_generation": Q_gen_actual,
        "P_generation_specified": model.P_gen,
        "Q_generation_specified": model.Q_gen,
        "P_injection": P_final,
        "Q_injection": Q_final,
        "P_net_specified": model.P_net,
        "Q_net_specified": model.Q_net,
        "P_load": model.P_load,
        "Q_load": model.Q_load,
        "G_shunt": model.G_shunt,
        "B_shunt": model.B_shunt,
        "Q_min": model.Q_min,
        "Q_max": model.Q_max,
        "P_shunt_injected": P_shunt,
        "Q_shunt_injected": Q_shunt,
        "P_shunt_injected_total": float(np.sum(P_shunt)),
        "Q_shunt_injected_total": float(np.sum(Q_shunt)),
        "line_endpoints": model.line_data[:, :2].astype(int),
        "line_B_half": model.line_data[:, 4],
        "line_tap_ratio": model.line_data[:, 5],
        "line_phase_shift_deg": model.line_data[:, 6],
        "line_flow_P": P_from,
        "line_flow_Q": Q_from,
        "line_loss_P": P_loss_line,
        "line_loss_Q": Q_loss_line,
        "P_loss_total": P_total_loss,
        "Q_loss_total": Q_total_loss,
        "P_total_gen": P_total_gen,
        "Q_total_gen": Q_total_gen,
        "P_total_load": P_total_load,
        "Q_total_load": Q_total_load,
        "base_values": model.base_values,
        "mismatch_history": mismatch_history[: max(0, iterations)].tolist(),
        "iterations": iterations,
        "converged": converged,
        "metadata": {
            "num_buses": model.num_buses,
            "num_lines": model.num_lines,
            "slack_bus_ids": model.external_bus_ids[model.slack_buses].tolist(),
            "pv_bus_ids": model.external_bus_ids[model.pv_buses].tolist(),
            "pq_bus_ids": model.external_bus_ids[model.pq_buses].tolist(),
        },
    }
