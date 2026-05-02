"""Build the 4-block Newton-Raphson Jacobian matrix (dense or sparse).

J = [ J11  J12 ]   J11 = dP/ddelta   (n_delta x n_delta)
    [ J21  J22 ]   J12 = dP/dV       (n_delta x n_V)
                    J21 = dQ/ddelta   (n_V x n_delta)
                    J22 = dQ/dV       (n_V x n_V)

Port of: internal/core/pf_build_jacobian.m (59 lines)
"""

from __future__ import annotations

import numpy as np
from scipy.sparse import issparse, lil_matrix
from scipy.sparse.linalg import spsolve


def solve_jacobian(J, mis):
    """Solve J·dx = mis, handling both sparse (csr) and dense (ndarray) matrices."""
    if issparse(J):
        return spsolve(J, mis)
    return np.linalg.solve(J, mis)


def build_jacobian(
    V: np.ndarray,
    delta: np.ndarray,
    P_calc: np.ndarray,
    Q_calc: np.ndarray,
    model,
    sparse: bool = True,
) -> np.ndarray:
    """Build full NR Jacobian (n_total x n_total).

    When sparse=True, returns scipy.sparse.csr_matrix for use with spsolve.
    Falls back to dense numpy array when sparse=False (legacy / debugging).
    """
    if not sparse:
        return _build_dense(V, delta, P_calc, Q_calc, model)
    return _build_sparse(V, delta, P_calc, Q_calc, model)


def _build_sparse(V, delta, P_calc, Q_calc, model):
    """Build sparse CSR Jacobian — only non-zero at Ybus-connected buses."""
    G = model.Gbus
    B = model.Bbus
    d_idx = model.delta_idx
    v_idx = model.V_idx
    nd = model.n_delta
    nv = model.n_V
    nt = model.n_total
    N = model.num_buses

    # Build adjacency from Ybus (only iterate over connected buses)
    adj = _build_adjacency(G, B, N)

    J = lil_matrix((nt, nt))

    # ── J11: dP_i / ddelta_j ──
    for i in range(nd):
        bi = d_idx[i]
        for bj in adj[bi]:
            j = _find_idx(d_idx, bj)
            if j < 0:
                continue
            d_ij = delta[bi] - delta[bj]
            if i == j:
                J[i, j] = -Q_calc[bi] - B[bi, bi] * V[bi] ** 2
            else:
                J[i, j] = V[bi] * V[bj] * (G[bi, bj] * np.sin(d_ij) - B[bi, bj] * np.cos(d_ij))

    # ── J12: dP_i / dV_j ──
    for i in range(nd):
        bi = d_idx[i]
        for bj in adj[bi]:
            j = _find_idx(v_idx, bj)
            if j < 0:
                continue
            d_ij = delta[bi] - delta[bj]
            if bi == bj:
                J[i, nd + j] = P_calc[bi] / V[bi] + G[bi, bi] * V[bi]
            else:
                J[i, nd + j] = V[bi] * (G[bi, bj] * np.cos(d_ij) + B[bi, bj] * np.sin(d_ij))

    # ── J21: dQ_i / ddelta_j ──
    for i in range(nv):
        bi = v_idx[i]
        for bj in adj[bi]:
            j = _find_idx(d_idx, bj)
            if j < 0:
                continue
            d_ij = delta[bi] - delta[bj]
            if bi == bj:
                J[nd + i, j] = P_calc[bi] - G[bi, bi] * V[bi] ** 2
            else:
                J[nd + i, j] = -V[bi] * V[bj] * (G[bi, bj] * np.cos(d_ij) + B[bi, bj] * np.sin(d_ij))

    # ── J22: dQ_i / dV_j ──
    for i in range(nv):
        bi = v_idx[i]
        for bj in adj[bi]:
            j = _find_idx(v_idx, bj)
            if j < 0:
                continue
            d_ij = delta[bi] - delta[bj]
            if i == j:
                J[nd + i, nd + j] = Q_calc[bi] / V[bi] - B[bi, bi] * V[bi]
            else:
                J[nd + i, nd + j] = V[bi] * (G[bi, bj] * np.sin(d_ij) - B[bi, bj] * np.cos(d_ij))

    return J.tocsr()


def _build_dense(V, delta, P_calc, Q_calc, model):
    """Original dense Jacobian (for reference / debugging)."""
    G = model.Gbus
    B = model.Bbus
    d_idx = model.delta_idx
    v_idx = model.V_idx
    nd = model.n_delta
    nv = model.n_V
    nt = model.n_total

    J = np.zeros((nt, nt))

    for i in range(nd):
        bi = d_idx[i]
        for j in range(nd):
            bj = d_idx[j]
            d_ij = delta[bi] - delta[bj]
            if i == j:
                J[i, j] = -Q_calc[bi] - B[bi, bi] * V[bi] ** 2
            else:
                J[i, j] = V[bi] * V[bj] * (G[bi, bj] * np.sin(d_ij) - B[bi, bj] * np.cos(d_ij))

    for i in range(nd):
        bi = d_idx[i]
        for j in range(nv):
            bj = v_idx[j]
            d_ij = delta[bi] - delta[bj]
            if bi == bj:
                J[i, nd + j] = P_calc[bi] / V[bi] + G[bi, bi] * V[bi]
            else:
                J[i, nd + j] = V[bi] * (G[bi, bj] * np.cos(d_ij) + B[bi, bj] * np.sin(d_ij))

    for i in range(nv):
        bi = v_idx[i]
        for j in range(nd):
            bj = d_idx[j]
            d_ij = delta[bi] - delta[bj]
            if bi == bj:
                J[nd + i, j] = P_calc[bi] - G[bi, bi] * V[bi] ** 2
            else:
                J[nd + i, j] = -V[bi] * V[bj] * (G[bi, bj] * np.cos(d_ij) + B[bi, bj] * np.sin(d_ij))

    for i in range(nv):
        bi = v_idx[i]
        for j in range(nv):
            bj = v_idx[j]
            d_ij = delta[bi] - delta[bj]
            if i == j:
                J[nd + i, nd + j] = Q_calc[bi] / V[bi] - B[bi, bi] * V[bi]
            else:
                J[nd + i, nd + j] = V[bi] * (G[bi, bj] * np.sin(d_ij) - B[bi, bj] * np.cos(d_ij))

    return J


def _build_adjacency(G, B, N):
    """Return dict mapping bus index -> list of connected bus indices."""
    adj = {}
    for i in range(N):
        adj[i] = np.where((G[i] != 0) | (B[i] != 0))[0]
    return adj


def _find_idx(idx_array, bus_idx):
    """Find position of bus_idx in idx_array. Returns -1 if not found."""
    for k, v in enumerate(idx_array):
        if v == bus_idx:
            return k
    return -1


def build_fast_decoupled_matrices(model) -> tuple[np.ndarray, np.ndarray]:
    """Build constant B' and B'' matrices for Fast Decoupled Load Flow (XB scheme).

    B' = imag(Ybus) restricted to delta_idx  (for P-δ)
    B'' = imag(Ybus) restricted to V_idx       (for Q-V)

    Returns:
        B_prime: [n_delta x n_delta]
        B_double_prime: [n_V x n_V]
    """
    Bbus = model.Bbus
    B_prime = Bbus[np.ix_(model.delta_idx, model.delta_idx)].copy()
    B_double_prime = Bbus[np.ix_(model.V_idx, model.V_idx)].copy()
    return B_prime, B_double_prime
