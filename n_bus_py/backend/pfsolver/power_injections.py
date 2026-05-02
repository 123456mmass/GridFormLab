"""Vectorized bus power injection calculations.

P_i = V_i * sum_j [ V_j * (G_ij*cos(d_i - d_j) + B_ij*sin(d_i - d_j)) ]
Q_i = V_i * sum_j [ V_j * (G_ij*sin(d_i - d_j) - B_ij*cos(d_i - d_j)) ]

Port of: internal/core/pf_calculate_power_injections.m
"""

from __future__ import annotations

import numpy as np


def calculate_power_injections(
    V: np.ndarray,
    delta: np.ndarray,
    Ybus: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    """Compute P_calc and Q_calc at each bus from voltages and Ybus.

    Args:
        V: bus voltage magnitudes [N] (pu)
        delta: bus voltage angles [N] (rad)
        Ybus: complex admittance matrix [N x N]

    Returns:
        (P_calc, Q_calc) each [N] in pu
    """
    G = Ybus.real
    B = Ybus.imag

    # delta_ij = delta_i - delta_j  [N x N]
    d_ij = delta[:, np.newaxis] - delta[np.newaxis, :]

    cos_d = np.cos(d_ij)
    sin_d = np.sin(d_ij)

    # V_i * V_j for each pair
    VV = V[:, np.newaxis] * V[np.newaxis, :]

    G_cos = G * cos_d
    B_sin = B * sin_d
    G_sin = G * sin_d
    B_cos = B * cos_d

    P = np.sum(VV * (G_cos + B_sin), axis=1)
    Q = np.sum(VV * (G_sin - B_cos), axis=1)

    return P, Q


def calculate_line_flows(
    V: np.ndarray,
    delta: np.ndarray,
    line_data: np.ndarray,
    line_from_idx: np.ndarray,
    line_to_idx: np.ndarray,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Compute per-line flows and losses using pi-model current injection.

    Args:
        V: bus voltages [N]
        delta: bus angles [N] (rad)
        line_data: M x 7 [from_bus, to_bus, R, X, B_half, tap, phase_deg]
        line_from_idx, line_to_idx: 0-based indices [M]

    Returns:
        (P_from, Q_from, P_loss, Q_loss) each [M]
    """
    M = line_data.shape[0]

    Vc = V * np.exp(1j * delta)
    Vf = Vc[line_from_idx]  # [M]
    Vt = Vc[line_to_idx]    # [M]

    R = line_data[:, 2]
    X = line_data[:, 3]
    B_half = line_data[:, 4]
    tap_ratio = line_data[:, 5]
    phase_deg = line_data[:, 6]

    with np.errstate(divide="ignore", invalid="ignore"):
        y_series = 1.0 / (R + 1j * X)
    y_series[~np.isfinite(y_series)] = 1e10
    y_shunt = 1j * B_half
    tap = tap_ratio * np.exp(1j * np.deg2rad(phase_deg))
    tap_conj = np.conj(tap)
    tap_mag_sq = np.abs(tap) ** 2

    I_f = ((y_series + y_shunt) / tap_mag_sq) * Vf - (y_series / tap_conj) * Vt
    I_t = (y_series + y_shunt) * Vt - (y_series / tap) * Vf

    S_f = Vf * np.conj(I_f)
    S_t = Vt * np.conj(I_t)

    P_from = S_f.real
    Q_from = S_f.imag
    P_loss = (S_f + S_t).real
    Q_loss = (S_f + S_t).imag

    return P_from, Q_from, P_loss, Q_loss
