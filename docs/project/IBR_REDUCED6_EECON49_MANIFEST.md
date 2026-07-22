# Reduced 6-state IBR models (EECON49-P4) — parameter & state manifest (FROZEN)

Scope: two reduced-order SMIB device models used for the GFL-vs-GFM comparison,
each with **6 states = 2 per functional block**. Structure and numeric values
follow the EECON49-P4 (KMITL) formulation; underlying block equations trace to
Yazdani-Iravani 2010 / Teodorescu 2011 (GFL) and the VSG literature (GFM).
Classification: **PROJECT_DERIVED_SOURCE_MAPPED** (reduced-order assembly of
sourced blocks). Frozen before results.

## Common per-unit / base contract
- `Sbase = Mbase = 100 MVA`, `fbase = 60 Hz`, `omega_b = 2*pi*fbase`, `kappa = Sbase/Mbase = 1`.
- Internal states on inverter base; `current_injection`/`electrical_power` return system base.
- `L = 0.15 pu`, `R_t = 0.015 pu` are per-unit COUPLING REACTANCE / resistance.
- SMIB operating point: `V = 1.0∠0 pu`, `P = 0.40 pu`, `Q = 0.10 pu`, `Z_line = 0.02 + j0.20 pu`.
- Low-voltage division floor `V_div_min = 0.1` (fail-closed).

## GFL 6-state (`ibr.gfl_reduced6_model`, device_type `ibr_gfl_reduced6`)
Blocks: **IBR + GFL(PLL) + PQ**. State order (fixed):

| # | State | Block | Meaning |
|---|-------|-------|---------|
| 1 | `i_d` | IBR | d-axis L-filter current (pu inv) |
| 2 | `i_q` | IBR | q-axis L-filter current (pu inv) |
| 3 | `delta_PLL` | GFL | SRF-PLL angle (rad) |
| 4 | `xi_PLL` | GFL | PLL PI integrator (pu·s) |
| 5 | `xi_P` | PQ | active-power outer-PI integrator (pu·s) |
| 6 | `xi_Q` | PQ | reactive-power outer-PI integrator (pu·s) |

Gains (EECON49-P4, SOURCE_DEFINED_STUDY_VALUE):
`kp_PLL=1.20, ki_PLL=5.00` (rad/s form, **NO omega_b factor**),
`kp_P=kp_Q=0.80, ki_P=ki_Q=2.50`, `kp_i=0.30` (proportional current).
Reductions (PROJECT_DERIVED): P/Q measurement filters and current-PI integrators
removed; power measured algebraically; current loop proportional + decoupling;
no limiter/LVRT.

Equilibrium (closed form): `delta_PLL0=angle(V)`, `i_d0=kappa*P/|V|`,
`i_q0=-kappa*Q/|V|`, `xi_PLL0=0`, `xi_P0=i_d0/ki_P`, `xi_Q0=-i_q0/ki_Q`.
Verified: `||f0||inf=2.79e-13`, stable (max_real=-0.582), complex PLL pair
`-0.582 ± j2.145` (0.341 Hz).

## GFM 6-state (`ibr.gfm_reduced6_model`, device_type `ibr_gfm_reduced6`)
Blocks: **IBR + VSG + GFM** (NO PLL). State order (fixed):

| # | State | Block | Meaning |
|---|-------|-------|---------|
| 1 | `i_d` | IBR | d-axis L-filter current (pu inv) |
| 2 | `i_q` | IBR | q-axis L-filter current (pu inv) |
| 3 | `omega` | VSG | virtual rotor speed (pu) |
| 4 | `delta` | VSG | rotor angle vs grid frame (rad) |
| 5 | `E` | GFM | internal voltage magnitude (pu) |
| 6 | `xi_V` | GFM | d-axis voltage-PI integrator (pu·s) |

Gains (EECON49-P4, SOURCE_DEFINED_STUDY_VALUE):
`M=0.08 s, Dv=1.50` (swing); `tau_E=0.05 s, kQ=0.25, kE=8.00` (Q-V droop);
`kp_V=1.20, ki_V=4.50` (voltage PI); `kp_i=0.30` (proportional current).
Reductions (PROJECT_DERIVED): governor/turbine/damper removed (algebraic damping
`Dv`); single d-axis voltage integrator; current loop proportional; no limiter.

Voltage-loop pairing (reactance-coupled, physics-verified): `v_gd = E + X*i_q`,
`v_gq = -X*i_d`, so the d-axis magnitude error drives `i_q` (reactive) and the
q-axis error drives `i_d` (active/synchronizing):
`i_q_ref = -(kp_V*(E-v_gd)+ki_V*xi_V)`, `i_d_ref = kp_V*(0-v_gq)`. A same-axis
pairing was verified UNSTABLE (`+1.09`, xi_V participation 72%); the cross pairing
is stable.

Equilibrium (closed form): `omega0=1`; `delta0 = atan2(-(Ar+Bi),(Ai-Br))` with
`A=kappa*I_net`, `B=kp_V*V`, `I_net=conj((P+jQ)/V)` (branch chosen so `v_gd0>0`);
`E0=v_gd0`, `xi_V0=-i_q0/ki_V`; the Q-V droop reference is back-solved so
`d(E)/dt=0` exactly. Verified: `||f0||inf=0`, stable (max_real=-0.555), complex
swing pair `-7.09 ± j67.6` (10.76 Hz, low-inertia).

## No-PLL contract (GFM)
The GFM rotor angle derives ONLY from the swing integrator
`d(delta)/dt = omega_b*(omega-1)`; never from `angle(V)`. Construction rejects
dormant PLL/governor/limiter option fields.
