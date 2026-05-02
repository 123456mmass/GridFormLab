"""Core model builder: case normalization, validation, Ybus construction, bus classification.

Port of: internal/core/pf_prepare_case.m (185 lines MATLAB)
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np


@dataclass
class ModelResult:
    """Complete computational model for power flow solvers."""

    case_data: dict
    system_name: str
    base_values: dict
    bus_data: np.ndarray  # N x 12
    line_data: np.ndarray  # M x 7
    external_bus_ids: np.ndarray  # N
    num_buses: int
    num_lines: int
    bus_type: np.ndarray  # N: 1=slack, 2=PV, 3=PQ
    V_spec: np.ndarray  # N
    angle_spec_deg: np.ndarray  # N
    P_gen: np.ndarray
    Q_gen: np.ndarray
    P_load: np.ndarray
    Q_load: np.ndarray
    G_shunt: np.ndarray
    B_shunt: np.ndarray
    Q_min: np.ndarray
    Q_max: np.ndarray
    P_net: np.ndarray
    Q_net: np.ndarray
    slack_buses: np.ndarray
    pv_buses: np.ndarray
    pq_buses: np.ndarray
    line_from_idx: np.ndarray  # 0-based
    line_to_idx: np.ndarray  # 0-based
    Ybus: np.ndarray  # complex N x N
    Gbus: np.ndarray  # real N x N
    Bbus: np.ndarray  # real N x N
    delta_idx: np.ndarray  # pv_buses + pq_buses (angle unknowns)
    V_idx: np.ndarray  # pq_buses only (voltage unknowns)
    n_delta: int
    n_V: int
    n_total: int


# ── Public API ───────────────────────────────────────────────


def prepare_model(case_data: dict) -> ModelResult:
    """Build computational model from raw case data.

    Pipeline: normalize -> validate -> classify buses -> build Ybus -> build indices
    """
    cd = normalize_case_data(case_data)
    validate_case_data(cd)
    return _build_model(cd)


# ── Normalization ────────────────────────────────────────────


def normalize_case_data(case_data: dict) -> dict:
    """Pad bus_data to 12 cols, line_data to 7 cols. Fill defaults."""
    cd = dict(case_data)  # shallow copy top-level

    cd.setdefault("system_name", "Unnamed System")
    cd.setdefault("base_values", {})
    cd["base_values"].setdefault("S_base_MVA", 100.0)
    cd["base_values"].setdefault("V_base_kV", 230.0)
    cd["base_values"].setdefault("frequency_Hz", 60.0)

    # Normalize bus_data to 12 columns
    bus = np.atleast_2d(np.array(cd["bus_data"], dtype=float))
    n_rows, n_cols = bus.shape
    if n_cols == 8:
        extra = np.zeros((n_rows, 4))
        extra[:, 2:] = -1e6  # Qmin, Qmax default
        bus = np.hstack([bus, extra])
    elif n_cols == 10:
        extra = np.full((n_rows, 2), -1e6)
        extra[:, 1] = 1e6  # Qmax
        bus = np.hstack([bus, extra])
    elif n_cols == 12:
        pass
    else:
        bus = _pad_to_12(bus, n_rows, n_cols)
    # Replace -Inf/Inf defaults with large finite values
    qmin = bus[:, 10].copy()
    qmax = bus[:, 11].copy()
    qmin[np.isneginf(qmin) | (qmin < -1e5)] = -1e6
    qmax[np.isposinf(qmax) | (qmax > 1e5)] = 1e6
    bus[:, 10] = qmin
    bus[:, 11] = qmax
    cd["bus_data"] = bus

    # Normalize line_data to 7 columns
    lines = np.atleast_2d(np.array(cd["line_data"], dtype=float))
    nr, nc = lines.shape
    if nc == 4:
        extra = np.zeros((nr, 3))
        extra[:, 1] = 1.0  # tap_ratio
        lines = np.hstack([lines, extra])
    elif nc == 5:
        extra = np.ones((nr, 2))
        extra[:, 1] = 0.0  # phase_shift
        lines = np.hstack([lines, extra])
    elif nc == 6:
        extra = np.zeros((nr, 1))  # phase_shift
        lines = np.hstack([lines, extra])
    elif nc == 7:
        pass
    else:
        lines = _pad_to_7(lines, nr, nc)
    # Replace tap=0 with 1.0
    lines[lines[:, 5] == 0, 5] = 1.0
    cd["line_data"] = lines

    return cd


def _pad_to_12(bus, n_rows, n_cols):
    """Handle non-standard bus column counts by padding or truncating."""
    padded = np.zeros((n_rows, 12))
    copy_cols = min(n_cols, 12)
    padded[:, :copy_cols] = bus[:, :copy_cols]
    if n_cols < 10:
        padded[:, 8:10] = 0.0
    if n_cols < 12:
        padded[:, 10] = -1e6
        padded[:, 11] = 1e6
    return padded


def _pad_to_7(lines, nr, nc):
    padded = np.zeros((nr, 7))
    copy_cols = min(nc, 7)
    padded[:, :copy_cols] = lines[:, :copy_cols]
    if nc < 5:
        padded[:, 4] = 0.0  # B_half
    if nc < 6:
        padded[:, 5] = 1.0  # tap_ratio
    if nc < 7:
        padded[:, 6] = 0.0  # phase_shift
    return padded


# ── Validation ───────────────────────────────────────────────


def validate_case_data(cd: dict) -> None:
    """Raise ValueError if case data is invalid."""
    bus_data = cd["bus_data"]
    line_data = cd["line_data"]

    bus_ids = bus_data[:, 0]
    if len(set(bus_ids)) != len(bus_ids):
        raise ValueError("Duplicate bus numbers in bus_data column 1")

    bus_types = bus_data[:, 1]
    slack_mask = bus_types == 1
    if np.sum(slack_mask) != 1:
        raise ValueError(f"Need exactly 1 slack bus, found {np.sum(slack_mask)}")

    invalid_types = ~np.isin(bus_types, [1, 2, 3])
    if np.any(invalid_types):
        raise ValueError(f"Invalid bus types: {bus_types[invalid_types]}")

    if np.any(bus_data[:, 2] <= 0):
        raise ValueError("All bus voltage magnitudes must be positive")

    qmin = bus_data[:, 10]
    qmax = bus_data[:, 11]
    if np.any(qmin > qmax):
        raise ValueError("Q_min > Q_max for some buses")

    line_ids = set(line_data[:, 0].astype(int)) | set(line_data[:, 1].astype(int))
    unknown = line_ids - set(bus_ids.astype(int))
    if unknown:
        raise ValueError(f"Line references non-existent buses: {unknown}")

    # Check non-zero impedance
    R = line_data[:, 2]
    X = line_data[:, 3]
    if np.any((R == 0) & (X == 0)):
        raise ValueError("Lines have zero impedance (R=0 and X=0)")


# ── Model builder ────────────────────────────────────────────


def _build_model(cd: dict) -> ModelResult:
    """Assemble ModelResult from normalized case data."""
    bus_data = cd["bus_data"]
    line_data = cd["line_data"]
    bv = cd["base_values"]

    num_buses = bus_data.shape[0]
    num_lines = line_data.shape[0]

    external_bus_ids = bus_data[:, 0].astype(int)
    bus_type = bus_data[:, 1].astype(int)
    V_spec = bus_data[:, 2].copy()
    angle_spec_deg = bus_data[:, 3].copy()
    P_gen = bus_data[:, 4].copy()
    Q_gen = bus_data[:, 5].copy()
    P_load = bus_data[:, 6].copy()
    Q_load = bus_data[:, 7].copy()
    G_shunt = bus_data[:, 8].copy()
    B_shunt = bus_data[:, 9].copy()
    Q_min = bus_data[:, 10].copy()
    Q_max = bus_data[:, 11].copy()

    P_net = P_gen - P_load
    Q_net = Q_gen - Q_load

    # Bus classification
    slack_buses = np.where(bus_type == 1)[0]
    pv_buses = np.where(bus_type == 2)[0]
    pq_buses = np.where(bus_type == 3)[0]

    # Map line bus numbers to internal 0-based indices
    id_to_idx = {int(bid): i for i, bid in enumerate(external_bus_ids)}
    line_from_idx = np.array([id_to_idx[int(b)] for b in line_data[:, 0]], dtype=int)
    line_to_idx = np.array([id_to_idx[int(b)] for b in line_data[:, 1]], dtype=int)

    # Build Ybus
    Ybus = build_ybus(bus_data, line_data, line_from_idx, line_to_idx)

    # Unknown indices
    delta_idx = np.concatenate([pv_buses, pq_buses]).astype(int)
    V_idx = pq_buses.astype(int)

    return ModelResult(
        case_data=cd,
        system_name=cd["system_name"],
        base_values=bv,
        bus_data=bus_data,
        line_data=line_data,
        external_bus_ids=external_bus_ids,
        num_buses=num_buses,
        num_lines=num_lines,
        bus_type=bus_type,
        V_spec=V_spec,
        angle_spec_deg=angle_spec_deg,
        P_gen=P_gen,
        Q_gen=Q_gen,
        P_load=P_load,
        Q_load=Q_load,
        G_shunt=G_shunt,
        B_shunt=B_shunt,
        Q_min=Q_min,
        Q_max=Q_max,
        P_net=P_net,
        Q_net=Q_net,
        slack_buses=slack_buses,
        pv_buses=pv_buses,
        pq_buses=pq_buses,
        line_from_idx=line_from_idx,
        line_to_idx=line_to_idx,
        Ybus=Ybus,
        Gbus=Ybus.real.copy(),
        Bbus=Ybus.imag.copy(),
        delta_idx=delta_idx,
        V_idx=V_idx,
        n_delta=len(delta_idx),
        n_V=len(V_idx),
        n_total=len(delta_idx) + len(V_idx),
    )


# ── Ybus construction ────────────────────────────────────────


def build_ybus(
    bus_data: np.ndarray,
    line_data: np.ndarray,
    line_from_idx: np.ndarray,
    line_to_idx: np.ndarray,
) -> np.ndarray:
    """Build complex N x N admittance matrix using transformer pi-model.

    y_series = 1 / (R + jX)
    y_shunt  = j * B_half / 2  (each end gets B_half)
    tap = tap_ratio * exp(j * deg2rad(phase_shift))

    Y(from,from) += (y_series + y_shunt) / (tap * conj(tap))
    Y(to,to)     += y_series + y_shunt
    Y(from,to)   -= y_series / conj(tap)
    Y(to,from)   -= y_series / tap
    """
    n = bus_data.shape[0]
    Y = np.zeros((n, n), dtype=complex)

    R = line_data[:, 2]
    X = line_data[:, 3]
    B_half = line_data[:, 4]
    tap_ratio = line_data[:, 5]
    phase_shift_deg = line_data[:, 6]

    # Series admittance
    with np.errstate(divide="ignore", invalid="ignore"):
        y_series = 1.0 / (R + 1j * X)
    # Handle zero impedance: large admittance
    y_series[~np.isfinite(y_series)] = 1e10

    y_shunt = 1j * B_half

    # Tap with phase shift
    tap = tap_ratio * np.exp(1j * np.deg2rad(phase_shift_deg))
    tap_conj = np.conj(tap)
    tap_mag_sq = tap * tap_conj  # |tap|^2

    for k in range(line_data.shape[0]):
        f = line_from_idx[k]
        t = line_to_idx[k]
        ys = y_series[k]
        ysh = y_shunt[k]
        tp = tap[k]
        tc = tap_conj[k]
        tmsq = tap_mag_sq[k]

        Y[f, f] += (ys + ysh) / tmsq
        Y[t, t] += ys + ysh
        Y[f, t] -= ys / tc
        Y[t, f] -= ys / tp

    # Shunt admittances from bus data
    Gsh = bus_data[:, 8]
    Bsh = bus_data[:, 9]
    for i in range(n):
        Y[i, i] += complex(Gsh[i], Bsh[i])

    return Y
