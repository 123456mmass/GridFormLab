"""State vector <-> voltage/angle conversion.

Port of: internal/core/pf_initial_state.m
         internal/core/pf_state_to_voltage_angle.m
"""

from __future__ import annotations

import numpy as np


def initial_state(model) -> np.ndarray:
    """Build initial NR state vector: x = [angle(delta_idx); V(V_idx)].

    Flat start: angles=0, voltages=specified (or 1.0 for PQ).
    """
    n = model.n_total
    x = np.zeros(n)

    # Angles for PV and PQ buses
    x[: model.n_delta] = np.deg2rad(model.angle_spec_deg[model.delta_idx])

    # Voltage magnitudes for PQ buses
    V_pq = model.V_spec[model.V_idx].copy()
    # For any PQ bus with 0 specified voltage, use 1.0
    V_pq[V_pq == 0] = 1.0
    x[model.n_delta :] = V_pq

    return x


def state_to_voltage_angle(x: np.ndarray, model) -> tuple[np.ndarray, np.ndarray]:
    """Decode state vector x into full V, delta vectors for all N buses.

    Args:
        x: state vector [n_total] = [delta(pv+pq); V(pq)]
        model: ModelResult with bus indices

    Returns:
        V: voltage magnitudes [N]
        delta: voltage angles [N] (rad)
    """
    N = model.num_buses
    V = model.V_spec.copy()
    delta = np.deg2rad(model.angle_spec_deg.copy())

    # Decode angles for PV + PQ buses
    delta[model.delta_idx] = x[: model.n_delta]

    # Decode voltages for PQ buses
    V[model.V_idx] = x[model.n_delta :]

    return V, delta
