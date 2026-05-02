"""Mismatch (power error) vector computation.

Port of: internal/core/pf_calculate_mismatch.m
"""

from __future__ import annotations

import numpy as np

from . import power_injections, state


def calculate_mismatch(
    x: np.ndarray,
    model,
    P_spec: np.ndarray | None = None,
    Q_spec: np.ndarray | None = None,
    P_calc: np.ndarray | None = None,
    Q_calc: np.ndarray | None = None,
    V: np.ndarray | None = None,
    delta: np.ndarray | None = None,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Compute mismatch vector and derived quantities.

    mismatch = [P_spec(delta_idx) - P_calc(delta_idx);
                 Q_spec(V_idx) - Q_calc(V_idx)]

    When P_calc/Q_calc/V/delta are pre-computed (e.g. by Gauss-Seidel),
    pass them directly to skip the decode+recompute step.

    Returns:
        mismatch: [n_total]
        P_calc: [N]
        Q_calc: [N]
        V: [N]
        delta: [N] (rad)
    """
    if V is None or delta is None:
        V, delta = state.state_to_voltage_angle(x, model)
    if P_calc is None or Q_calc is None:
        P_calc, Q_calc = power_injections.calculate_power_injections(V, delta, model.Ybus)

    if P_spec is None:
        P_spec = model.P_net
    if Q_spec is None:
        Q_spec = model.Q_net

    mismatch = np.zeros(model.n_total)
    mismatch[: model.n_delta] = (
        P_spec[model.delta_idx] - P_calc[model.delta_idx]
    )
    mismatch[model.n_delta :] = (
        Q_spec[model.V_idx] - Q_calc[model.V_idx]
    )

    return mismatch, P_calc, Q_calc, V, delta
