"""Holomorphic Embedding — core Taylor series + Padé approximant.

HELM (Trias, 2012): Embed α into power flow, expand V(α) as Maclaurin
series, evaluate at α=1 via Padé. Finds operable solution without
initial guess. Natural voltage collapse detection (Padé pole location).

PQ bus embedding:
    Σ_j Y_ij V_j(α) = α S_i* / V_i*(α*)

PV bus embedding:
    |V_i(α)|² = |V_sp|²
    Re(V_i*(α*) · I_i(α)) = α P_sp_i

Germ (α=0): zero-injection network, slack fixed, all other I=0.
"""

from __future__ import annotations

import numpy as np


def compute_germ(model) -> np.ndarray:
    """Compute HELM germ V[0] — zero-injection network with PV constraints.

    At α=0:
      PQ buses: I_i = 0 (zero complex injection)
      PV buses: |V| = V_sp, P = 0 (zero active power)
      Slack: V = V_spec (fixed)

    Solved via fixed-point iteration between PQ voltage solve and PV angle
    adjustment. Shunt elements are included in Ybus.
    """
    N = model.num_buses
    Ybus = model.Ybus
    V_sp = model.V_spec.copy()

    slack = int(model.slack_buses[0])
    V_slack = V_sp[slack] * np.exp(1j * np.deg2rad(model.angle_spec_deg[slack]))

    non_slack = sorted(set(range(N)) - {slack})
    pv_set = set(int(b) for b in model.pv_buses)
    pq_set = set(int(b) for b in model.pq_buses)

    # Initial guess: all buses at slack voltage
    V0 = np.full(N, V_slack, dtype=complex)

    # Separate indices
    pq_list = sorted(pq_set)
    pv_list = sorted(pv_set)

    for _ in range(20):
        # Set PV voltages to V_sp with current angle
        for i in pv_list:
            ang_i = np.angle(V0[i])
            V0[i] = V_sp[i] * np.exp(1j * ang_i)

        # Solve for PQ bus voltages: I_PQ = 0
        # Y_PQ,PQ · V_PQ = -Y_PQ,slack · V_slack - Y_PQ,PV · V_PV
        if len(pq_list) > 0:
            pq_idx = np.array(pq_list, dtype=int)
            Y_pq_pq = Ybus[np.ix_(pq_idx, pq_idx)]

            rhs = -Ybus[pq_idx, slack] * V_slack
            if len(pv_list) > 0:
                pv_idx_arr = np.array(pv_list, dtype=int)
                rhs -= Ybus[np.ix_(pq_idx, pv_idx_arr)] @ V0[pv_idx_arr]

            V0[pq_idx] = np.linalg.solve(Y_pq_pq, rhs)

        # Adjust PV angles to zero real power
        max_delta = 0.0
        for i in pv_list:
            I_i = Ybus[i, :] @ V0
            P_i = float(np.real(np.conj(V0[i]) * I_i))
            # Decoupled angle adjustment: ∂P/∂θ ≈ |V|² * (-B_ii)
            B_ii = float(Ybus[i, i].imag)
            dP_dtheta = -abs(V0[i])**2 * B_ii
            if abs(dP_dtheta) > 1e-12:
                dtheta = -P_i / dP_dtheta
                dtheta = np.clip(dtheta, -0.5, 0.5)  # limit step
                V0[i] = V0[i] * np.exp(1j * dtheta)
                max_delta = max(max_delta, abs(dtheta))

        if max_delta < 1e-9:
            break

    # Final: V_slack fixed
    V0[slack] = V_slack

    return V0


def build_helm_real_matrix(model, V0: np.ndarray) -> np.ndarray:
    """Build constant 2R × 2R real matrix for HELM coefficient solves.

    R = num non-slack buses. Each bus → 2 real unknowns (Re(V[n]), Im(V[n])).
    PQ bus: 2 rows from complex Ybus equation.
    PV bus: row 2*i from voltage constraint, row 2*i+1 from power equation.

    Returns matrix M such that M @ x_n = rhs_n at each order n.
    """
    N = model.num_buses
    slack = int(model.slack_buses[0])
    non_slack = sorted(set(range(N)) - {slack})
    nslack_arr = np.array(non_slack, dtype=int)
    R = len(non_slack)
    dim = 2 * R

    bus_to_row = {bus: idx for idx, bus in enumerate(non_slack)}

    M = np.zeros((dim, dim))
    Ybus = model.Ybus
    G, Bmat = Ybus.real, Ybus.imag

    I0 = Ybus @ V0  # current at germ

    for bus_i in non_slack:
        ri = bus_to_row[bus_i]
        row_r = 2 * ri
        row_i = 2 * ri + 1

        if bus_i in model.pq_buses:
            # Complex Ybus row: Σ_j Y_ij V_j[n] = RHS_i
            for bus_j in non_slack:
                rj = bus_to_row[bus_j]
                col_r = 2 * rj
                col_i = 2 * rj + 1
                M[row_r, col_r] = G[bus_i, bus_j]
                M[row_r, col_i] = -Bmat[bus_i, bus_j]
                M[row_i, col_r] = Bmat[bus_i, bus_j]
                M[row_i, col_i] = G[bus_i, bus_j]

        elif bus_i in model.pv_buses:
            V0i_r = V0[bus_i].real
            V0i_i = V0[bus_i].imag
            I0i_r = I0[bus_i].real
            I0i_i = I0[bus_i].imag

            # Row r: voltage magnitude constraint
            # Re(V_i*[0] · V_i[n]) = V0i_r * Re(V_i[n]) + V0i_i * Im(V_i[n])
            col_r = 2 * ri
            col_i = 2 * ri + 1
            M[row_r, col_r] = V0i_r
            M[row_r, col_i] = V0i_i
            # Other columns (V_j[n] for j ≠ i): zero contribution

            # Row i: active power constraint
            # Re(V_i*[0] · I_i[n]) + Re(V_i*[n] · I_i[0]) = RHS_pow
            # = Re(V_i*[0] Σ_j Y_ij V_j[n]) + (I0i_r * Re(V_i[n]) + I0i_i * Im(V_i[n]))
            #
            # Re(V_i*[0] · Y_ij V_j[n]) for each j:
            # V_i*[0] · Y_ij · V_j[n] = (V0i_r - j·V0i_i)(G+jB)(V_jr + j·V_ji)
            # Real part per V_j[n]:
            #   Re(V_j[n]) contributes: V0i_r*G - V0i_i*B for Re, V0i_r*(-B) - V0i_i*G for Im
            # Wait, let me be careful:
            # (V0i_r - j·V0i_i)(G_ij + j·B_ij)(V_jr + j·V_ji)
            # = (V0i_r - j·V0i_i)[(G_ij·V_jr - B_ij·V_ji) + j(G_ij·V_ji + B_ij·V_jr)]
            # = V0i_r(G_ij·V_jr - B_ij·V_ji) - j·V0i_i(G_ij·V_jr - B_ij·V_ji)
            #   + j·V0i_r(G_ij·V_ji + B_ij·V_jr) + V0i_i(G_ij·V_ji + B_ij·V_jr)
            # Real part:
            # = V0i_r·G_ij·V_jr - V0i_r·B_ij·V_ji + V0i_i·G_ij·V_ji + V0i_i·B_ij·V_jr
            # = (V0i_r·G_ij + V0i_i·B_ij)·V_jr + (-V0i_r·B_ij + V0i_i·G_ij)·V_ji

            for bus_j in non_slack:
                rj = bus_to_row[bus_j]
                col_rj = 2 * rj
                col_ij = 2 * rj + 1
                Gij = G[bus_i, bus_j]
                Bij = Bmat[bus_i, bus_j]

                coef_re = V0i_r * Gij + V0i_i * Bij
                coef_im = -V0i_r * Bij + V0i_i * Gij

                M[row_i, col_rj] = coef_re
                M[row_i, col_ij] = coef_im

            # Add I0 contribution for V_i[n] itself
            # Re(V_i*[n]·I_i[0]) = I0i_r * Re(V_i[n]) + I0i_i * Im(V_i[n])
            M[row_i, col_r] += I0i_r
            M[row_i, col_i] += I0i_i

    return M


def compute_helm_rhs(
    model, V_coeffs: list[np.ndarray], W_list: list[np.ndarray],
    n: int, V0: np.ndarray, I0: np.ndarray,
) -> np.ndarray:
    """Compute RHS vector for order n in the 2R real system.

    Returns 2R real vector.
    """
    N = model.num_buses
    slack = int(model.slack_buses[0])
    non_slack = sorted(set(range(N)) - {slack})
    nslack_arr = np.array(non_slack, dtype=int)
    R = len(non_slack)
    dim = 2 * R
    bus_to_row = {bus: idx for idx, bus in enumerate(non_slack)}

    rhs = np.zeros(dim)
    S_conj = np.conj(model.P_net + 1j * model.Q_net)

    for bus_i in non_slack:
        ri = bus_to_row[bus_i]
        row_r = 2 * ri
        row_i = 2 * ri + 1

        if bus_i in model.pq_buses:
            # RHS_i = S_i* · W_i[n-1]
            val = S_conj[bus_i] * W_list[n - 1][bus_i]
            rhs[row_r] = val.real
            rhs[row_i] = val.imag

        elif bus_i in model.pv_buses:
            V0i = V0[bus_i]
            V0i_abs2 = abs(V0i)**2 + 1e-12

            # Voltage magnitude RHS:
            # Re(V_i*[0]·V_i[n]) = -½ Σ_{k=1}^{n-1} V_i*[k]·V_i[n-k]
            vol_rhs = 0.0
            if n >= 2:
                s = 0.0
                for k in range(1, n):
                    s += (V_coeffs[k][bus_i].real * V_coeffs[n - k][bus_i].real +
                          V_coeffs[k][bus_i].imag * V_coeffs[n - k][bus_i].imag)
                vol_rhs = -0.5 * s
            rhs[row_r] = vol_rhs

            # Power RHS at PV bus:
            # Re(V_i*(α*)·I_i(α)) = α·P_sp
            # At order n (n ≥ 1):
            # Re(V_i*[0]·I_i[n]) + Re(V_i*[n]·I_i[0])
            #   = P_sp_i * δ_{n,1} - Re(Σ_{k=1}^{n-1} V_i*[k]·I_i[n-k])
            pow_rhs = 0.0
            if n == 1:
                pow_rhs = model.P_net[bus_i]
            if n >= 2:
                s = 0.0
                for k in range(1, n):
                    # I_i[n-k] = Σ_j Y_ij V_j[n-k]
                    I_ik = sum(model.Ybus[bus_i, j] * V_coeffs[n - k][j] for j in range(N))
                    s += (V_coeffs[k][bus_i].real * I_ik.real +
                          V_coeffs[k][bus_i].imag * I_ik.imag)
                pow_rhs -= s
            rhs[row_i] = pow_rhs

    return rhs


def solve_helm_coefficients(model, n_max: int = 20) -> list[np.ndarray]:
    """Compute V[0] through V[n_max] HELM voltage coefficients.

    Returns list of complex voltage vectors (each shape [N]).
    """
    N = model.num_buses
    slack = int(model.slack_buses[0])

    V0 = compute_germ(model)
    I0 = model.Ybus @ V0

    non_slack = sorted(set(range(N)) - {slack})
    nslack_arr = np.array(non_slack, dtype=int)
    R = len(non_slack)

    V_coeffs = [V0]
    W_list = [1.0 / np.conj(V0)]

    M = build_helm_real_matrix(model, V0)

    try:
        M_inv = np.linalg.inv(M)
    except np.linalg.LinAlgError:
        # Degenerate case — use pseudoinverse
        M_inv = np.linalg.pinv(M)

    for n_val in range(1, n_max + 1):
        rhs = compute_helm_rhs(model, V_coeffs, W_list, n_val, V0, I0)
        x = M_inv @ rhs

        Vn = np.zeros(N, dtype=complex)
        for bus_i in non_slack:
            ri = sorted(non_slack).index(bus_i)
            Vn[bus_i] = x[2 * ri] + 1j * x[2 * ri + 1]

        V_coeffs.append(Vn)

        # Compute W[n] from W recurrence
        Wn = np.zeros(N, dtype=complex)
        V0c_inv = 1.0 / np.conj(V0)
        for i in range(N):
            s = 0.0 + 0.0j
            for k in range(n_val):
                s += W_list[k][i] * np.conj(V_coeffs[n_val - k][i])
            Wn[i] = -V0c_inv[i] * s
        W_list.append(Wn)

    return V_coeffs


def pade_approx(coeffs: np.ndarray, L: int = 8, M: int = 8) -> complex:
    """Padé [L/M] approximant of Σ c[n] αⁿ evaluated at α=1.

    P(z) = (Σ a_i z^i) / (1 + Σ b_j z^j) matching L+M+1 Taylor terms.
    Works with complex coefficients (voltage series).
    """
    n_avail = len(coeffs)
    L = min(L, n_avail - 1)
    M = min(M, n_avail - L - 1)
    if M <= 0:
        return complex(np.sum(coeffs[: L + 1]))

    A = np.zeros((M, M), dtype=complex)
    for i in range(M):
        for j in range(M):
            idx = L + i - j
            if 0 <= idx < n_avail:
                A[i, j] = coeffs[idx]

    b_rhs = np.array([-coeffs[L + 1 + i] for i in range(M)], dtype=complex)

    try:
        b = np.linalg.solve(A, b_rhs)
    except np.linalg.LinAlgError:
        return complex(np.sum(coeffs[: n_avail]))

    a = np.zeros(L + 1, dtype=complex)
    for i in range(L + 1):
        s = coeffs[i]
        for j in range(1, min(i, M) + 1):
            s += b[j - 1] * coeffs[i - j]
        a[i] = s

    den = 1.0 + np.sum(b)
    if abs(den) < 1e-12:
        return complex(np.sum(coeffs[: n_avail]))

    return complex(np.sum(a) / den)


def evaluate_helm(V_coeffs: list[np.ndarray], L: int = 8, M: int = 8) -> np.ndarray:
    """Evaluate HELM series at α=1 with Padé [L/M] per bus.

    Returns complex voltage vector.
    """
    N = len(V_coeffs[0])
    V_result = np.zeros(N, dtype=complex)
    n_coeffs = len(V_coeffs)

    for i in range(N):
        c = np.array([V_coeffs[k][i] for k in range(n_coeffs)])
        V_result[i] = pade_approx(c, L, M)

    return V_result
