function dev = gfl_model(device_id, bus_id, bus_position, V0_pu, params, P_ref_pu, Q_ref_pu)
%GFL_MODEL  Production GFL (grid-following) inverter device, Phase 5 STRUCTURAL_ONLY.
%
%   dev = gfl_model(DEVICE_ID, BUS_ID, BUS_POSITION, V0_PU, PARAMS, P_REF_PU, Q_REF_PU)
%   returns a device struct conforming to the stability.composite_dae ABI
%   (R3 Revision 2: f, current_injection, electrical_power, x0, u0,
%   state_names, reconstruct; all taking (t, x_dev, y, u_dev, event_context)).
%
%   Model: reduced positive-sequence RMS GFL (PROJECT_DERIVED reduction from
%   Ding et al. NREL/CP-6A40-83340 Sec II-B Eqs.7-10). The 14-state EMT/LCL
%   GFL is reduced to 6 states by eliminating the LCL filter and treating the
%   inner current loop as algebraic (ideal-inner-loop reduction).
%
%   State vector (6, fixed order, PROJECT_DERIVED interface contract):
%     x_gfl = [delta_pll; eps_pll; P_f; Q_f; phi_P; phi_Q]
%       delta_pll - PLL angle (network frame, rel. to synchronous ref)  [rad]
%       eps_pll   - PLL PI integrator                                  [pu*s]
%       P_f       - filtered measured active power                     [pu]
%       Q_f       - filtered measured reactive power                   [pu]
%       phi_P     - power-loop d-axis PI integrator                     [pu*s]
%       phi_Q     - power-loop q-axis PI integrator                     [pu*s]
%
%   Inputs (nu=2):
%     u = [P_ref; Q_ref]   active/reactive power references [pu, system base]
%
%   Governing equations (frozen, see IEEE14_IBR_GFL_PHASE5_PROVENANCE.md):
%     Vd_pll =  cos(delta_pll)*Re(V_bus) + sin(delta_pll)*Im(V_bus)
%     Vq_pll = -sin(delta_pll)*Re(V_bus) + cos(delta_pll)*Im(V_bus)
%     d(eps_pll)/dt   = Vq_pll
%     d(delta_pll)/dt = omega0*(kpPLL*Vq_pll + kiPLL*eps_pll)   % omega0 PRESENT
%     Pinv_meas = Re(V_bus*conj(I_gfl))   (S = V*conj(I), generator convention)
%     Qinv_meas = Im(V_bus*conj(I_gfl))
%     d(P_f)/dt = omega_c*(Pinv_meas - P_f)
%     d(Q_f)/dt = omega_c*(Qinv_meas - Q_f)
%     d(phi_P)/dt = +(P_ref - P_f)
%     d(phi_Q)/dt = +(Q_ref - Q_f)
%     i_d* = +Kps*(P_ref - P_f) + Kis*phi_P
%     i_q* = -Kps*(Q_ref - Q_f) - Kis*phi_Q        % Q-sign: Q = -V0*i_q* at lock
%     I_gfl = (i_d* + j*i_q*)*exp(j*delta_pll)      % positive INTO network, SYSTEM base
%
%   Equilibrium initialization (from PF warm-start V_bus=V0*exp(j*theta0)):
%     delta_pll0 = theta0;  eps_pll0 = 0;
%     P_f0 = P_ref;  Q_f0 = Q_ref;
%     phi_P0 = +P_ref/(V0*Kis);  phi_Q0 = +Q_ref/(V0*Kis);
%     i_d*0 = +P_ref/V0;  i_q*0 = -Q_ref/V0.
%
%   Classification:
%     - omega0, S_base, omega_c: SOURCE_VERBATIM (REGFM_B1 Table 1 / Ding Table I).
%     - kpPLL=0.265, kiPLL=2.65: SOURCE_VERBATIM values from REGFM_B1 Table 1;
%       CASE_DEFINED/PROJECT_MAPPED application to the Ding-derived GFL.
%     - Kps=1.0, Kis=10.0: ASSUMED_DIAGNOSTIC (Ding Table I lacks; a-priori
%       critically-damped rationale). Excluded from production acceptance.
%     - The RMS reduction (ideal inner loop, LCL elimination): PROJECT_DERIVED.
%
%   STATUS: IEEE14_IBR_GFL_MODEL_READY = STRUCTURAL_ONLY. No catalog/runtime
%   registration, no production-readiness claim. Kps/Kis must be source-closed
%   before any production acceptance.
%
%   Source: docs/project/IEEE14_IBR_GFL_PHASE5_PROVENANCE.md;
%           docs/project/IEEE14_IBR_DECISION_LEDGER.md (Item 1);
%           docs/project/IEEE14_IBR_FROZEN_CONTRACT.md (GFL item).
%   Primary sources: Ding NREL/CP-6A40-83340 Sec II-B (Eqs.7-10);
%           REGFM_B1 NREL/TP-5D00-90260 Table 1.

arguments
    device_id (1,1) string
    bus_id (1,1) double
    bus_position (1,1) double
    V0_pu (1,1) double
    params struct
    P_ref_pu (1,1) double
    Q_ref_pu (1,1) double
end

% --- Parameters (frozen BEFORE results; see provenance doc) -----------------
% Defaults reflect the Phase 5 freeze; params may override ONLY for diagnostic
% sensitivity studies (never to force a pass). Production acceptance uses the
% frozen defaults.
omega0 = 376.9911184307752;   % 2*pi*60 rad/s, SOURCE_VERBATIM (REGFM_B1 Table 1 omega0)
omega_c = 10.0;               % rad/s, SOURCE_VERBATIM (Ding Table I)
kpPLL = 0.265;                % pu, SOURCE_VERBATIM value (REGFM_B1 Table 1)
kiPLL = 2.65;                 % pu/s, SOURCE_VERBATIM value (REGFM_B1 Table 1)
Kps = 1.0;                    % ASSUMED_DIAGNOSTIC (Ding Table I lacks)
Kis = 10.0;                   % 1/s, ASSUMED_DIAGNOSTIC (Ding Table I lacks)
Sbase = 100.0;                % MVA, SOURCE_VERBATIM (system base; no Mbase factor)
% Allow param override for diagnostic studies only (does NOT enter production).
if isfield(params,'omega0')  && ~isempty(params.omega0),  omega0  = params.omega0;  end
if isfield(params,'omega_c') && ~isempty(params.omega_c), omega_c = params.omega_c; end
if isfield(params,'kpPLL')   && ~isempty(params.kpPLL),   kpPLL   = params.kpPLL;   end
if isfield(params,'kiPLL')   && ~isempty(params.kiPLL),   kiPLL   = params.kiPLL;   end
if isfield(params,'Kps')     && ~isempty(params.Kps),     Kps     = params.Kps;     end
if isfield(params,'Kis')     && ~isempty(params.Kis),     Kis     = params.Kis;     end

% --- Validate V0 (finite, positive; needed for initialization) --------------
if ~isfinite(V0_pu) || V0_pu <= 0
    error('ibr:gfl_model:badV0', ...
        'V0_pu must be finite positive (got %.6g); PF warm-start required.', V0_pu);
end

% --- Initial state (from PF warm-start; V_bus assumed = V0_pu*exp(j*theta0))
% The caller passes V0_pu = |V_bus|; the initial PLL angle is taken as the bus
% angle, which is set externally via x0 override when the full PF angle is
% known. For the structural default, theta0 = 0 (bus at angle 0). The mixed
% equilibrium solver / TS driver supplies the actual bus angle through y.
theta0 = 0.0;
delta_pll0 = theta0;
eps_pll0 = 0.0;
P_f0 = P_ref_pu;
Q_f0 = Q_ref_pu;
phi_P0 = P_ref_pu / (V0_pu * Kis);
phi_Q0 = Q_ref_pu / (V0_pu * Kis);
x0 = [delta_pll0; eps_pll0; P_f0; Q_f0; phi_P0; phi_Q0];
u0 = [P_ref_pu; Q_ref_pu];

% --- Captured constants for closures ----------------------------------------
bp = bus_position;   % 1-based index into y for this device's bus

% --- DQ transform: network-frame V_bus (complex) -> PLL-frame (Vd_pll, Vq_pll)
% y layout: [Re(V1), Im(V1), Re(V2), Im(V2), ...] interleaved. bus_position
% gives the 1-based bus index. V_bus = y(2*bp-1) + 1i*y(2*bp).
dq_from_y = @(delta_pll, y) deal( ...
    cos(delta_pll)*y(2*bp-1) + sin(delta_pll)*y(2*bp), ...
   -sin(delta_pll)*y(2*bp-1) + cos(delta_pll)*y(2*bp) );

% --- Current injection (depends on x, y, u_dev) -----------------------------
% I_gfl = (i_d* + j*i_q*)*exp(j*delta_pll), positive INTO network, system base.
% i_d*/i_q* are the FULL Ding Eq.10 form (incl. the Kps feedthrough term),
% so a step in P_ref/Q_ref (u_dev) produces an algebraic jump in I_gfl.
I_gfl_of_xyu = @(x_dev, y, u_dev) gfl_current_injection(x_dev, y, u_dev, bp, Kps, Kis);

% --- Differential RHS f(t, x_dev, y, u_dev, event_context) -----------------
f = @(t, x_dev, y, u_dev, event_context) gfl_f( ...
    x_dev, y, u_dev, bp, omega0, omega_c, kpPLL, kiPLL, Kps, Kis, I_gfl_of_xyu);

% --- current_injection(t, x_dev, y, u_dev, event_context): complex, INTO net
current_injection = @(t, x_dev, y, u_dev, event_context) I_gfl_of_xyu(x_dev, y, u_dev);

% --- electrical_power(t, x_dev, y, u_dev, event_context): Pe (pu, system base)
electrical_power = @(t, x_dev, y, u_dev, event_context) gfl_pe(x_dev, y, u_dev, bp, Kps, Kis);

% --- reconstruct(t, x_dev, y, u_dev, event_context): struct -----------------
reconstruct = @(t, x_dev, y, u_dev, event_context) gfl_reconstruct( ...
    x_dev, y, u_dev, bp, omega0, omega_c, kpPLL, kiPLL, Kps, Kis);

% --- Assemble device struct (composite_dae ABI, R3 Revision 2) --------------
dev = struct();
dev.name = char(device_id);
dev.device_id = char(device_id);
dev.bus_id = bus_id;
dev.device_type = 'ibr_gfl';
dev.mode = 'gfl';
dev.nx = 6;
dev.nu = 2;
dev.state_names = {'delta_pll','eps_pll','P_f','Q_f','phi_P','phi_Q'};
dev.input_names = {'P_ref','Q_ref'};
dev.x0 = x0;
dev.u0 = u0;
dev.f = f;
dev.current_injection = current_injection;
dev.electrical_power = electrical_power;
dev.reconstruct = reconstruct;
% Provenance metadata (serializable; NO function handles).
dev.provenance = struct( ...
    'model','gfl_phase5_structural_only', ...
    'source','Ding NREL/CP-6A40-83340 Sec II-B Eqs.7-10 (RMS-reduced) + REGFM_B1 NREL/TP-5D00-90260 Table 1', ...
    'provenance_doc','docs/project/IEEE14_IBR_GFL_PHASE5_PROVENANCE.md', ...
    'V0_pu', V0_pu, ...
    'params', struct('omega0',omega0,'omega_c',omega_c,'kpPLL',kpPLL, ...
                     'kiPLL',kiPLL,'Kps',Kps,'Kis',Kis,'Sbase',Sbase), ...
    'param_classifications', struct( ...
        'omega0','SOURCE_VERBATIM', ...
        'omega_c','SOURCE_VERBATIM', ...
        'kpPLL','SOURCE_VERBATIM_value_CASE_DEFINED_PROJECT_MAPPED_application', ...
        'kiPLL','SOURCE_VERBATIM_value_CASE_DEFINED_PROJECT_MAPPED_application', ...
        'Kps','ASSUMED_DIAGNOSTIC', ...
        'Kis','ASSUMED_DIAGNOSTIC'), ...
    'readiness','STRUCTURAL_ONLY');
end

% =========================================================================
function dx = gfl_f(x_dev, y, u_dev, bp, omega0, omega_c, kpPLL, kiPLL, Kps, Kis, I_gfl_fn)
%GFL_F  Differential RHS (6 states).
%   x_dev = [delta_pll; eps_pll; P_f; Q_f; phi_P; phi_Q]
%   u_dev = [P_ref; Q_ref]
delta_pll = x_dev(1);
eps_pll   = x_dev(2);
P_f       = x_dev(3);
Q_f       = x_dev(4);
phi_P     = x_dev(5);
phi_Q     = x_dev(6);
[P_ref, Q_ref] = refs_from_u(u_dev, P_f, Q_f);

% DQ transform of the local bus voltage into the PLL frame.
Vd_pll =  cos(delta_pll)*y(2*bp-1) + sin(delta_pll)*y(2*bp);
Vq_pll = -sin(delta_pll)*y(2*bp-1) + cos(delta_pll)*y(2*bp);

% PLL (Ding Eq.8, deviation form; omega0 multiplier PRESENT).
d_eps_pll   = Vq_pll;
d_delta_pll = omega0*(kpPLL*Vq_pll + kiPLL*eps_pll);

% Measured output power (generator convention S = V*conj(I)).
I_gfl = I_gfl_fn(x_dev, y, u_dev);
V_bus = complex(y(2*bp-1), y(2*bp));
S = V_bus * conj(I_gfl);
Pinv_meas = real(S);
Qinv_meas = imag(S);

% Power measurement filter (Ding Eq.2).
d_P_f = omega_c*(Pinv_meas - P_f);
d_Q_f = omega_c*(Qinv_meas - Q_f);

% Power-loop PI integrators (Ding Eq.9; both positive power error).
d_phi_P = P_ref - P_f;
d_phi_Q = Q_ref - Q_f;

dx = [d_delta_pll; d_eps_pll; d_P_f; d_Q_f; d_phi_P; d_phi_Q];
end

% =========================================================================
function I = gfl_current_injection(x_dev, y, u_dev, bp, Kps, Kis)
%GFL_CURRENT_INJECTION  Complex current injection (positive INTO network).
%   Full Ding Eq.10 form (incl. Kps feedthrough): a step in u_dev(1)/u_dev(2)
%   produces an algebraic jump in I_gfl (direct feedthrough).
delta_pll = x_dev(1);
P_f       = x_dev(3);
Q_f       = x_dev(4);
phi_P     = x_dev(5);
phi_Q     = x_dev(6);
[P_ref, Q_ref] = refs_from_u(u_dev, P_f, Q_f);
% Algebraic current references (Ding Eq.10; Q-sign CORRECTED).
i_d_star =  Kps*(P_ref - P_f) + Kis*phi_P;
i_q_star = -Kps*(Q_ref - Q_f) - Kis*phi_Q;
I = (i_d_star + 1i*i_q_star) * exp(1i*delta_pll);
end

% =========================================================================
function Pe = gfl_pe(x_dev, y, u_dev, bp, Kps, Kis)
%GFL_PE  Electrical active power output (pu, system base). S = V*conj(I).
I = gfl_current_injection(x_dev, y, u_dev, bp, Kps, Kis);
V_bus = complex(y(2*bp-1), y(2*bp));
Pe = real(V_bus * conj(I));
end

% =========================================================================
function out = gfl_reconstruct(x_dev, y, u_dev, bp, omega0, omega_c, kpPLL, kiPLL, Kps, Kis)
%GFL_RECONSTRUCT  Device outputs for diagnostics.
delta_pll = x_dev(1);
eps_pll   = x_dev(2);
P_f       = x_dev(3);
Q_f       = x_dev(4);
phi_P     = x_dev(5);
phi_Q     = x_dev(6);
Vd_pll =  cos(delta_pll)*y(2*bp-1) + sin(delta_pll)*y(2*bp);
Vq_pll = -sin(delta_pll)*y(2*bp-1) + cos(delta_pll)*y(2*bp);
I = gfl_current_injection(x_dev, y, u_dev, bp, Kps, Kis);
V_bus = complex(y(2*bp-1), y(2*bp));
S = V_bus * conj(I);
out = struct( ...
    'delta_pll', delta_pll, 'eps_pll', eps_pll, ...
    'P_f', P_f, 'Q_f', Q_f, 'phi_P', phi_P, 'phi_Q', phi_Q, ...
    'Vd_pll', Vd_pll, 'Vq_pll', Vq_pll, ...
    'I_gfl', I, 'Vbus', abs(V_bus), 'Pe', real(S), 'Qe', imag(S), ...
    'omega0', omega0, 'omega_c', omega_c, 'kpPLL', kpPLL, 'kiPLL', kiPLL, ...
    'Kps', Kps, 'Kis', Kis);
end

% =========================================================================
function [P_ref, Q_ref] = refs_from_u(u_dev, P_f, Q_f)
%REFS_FROM_U  Extract P_ref/Q_ref from u_dev; degenerate fallback for probes
%   that do not carry u (FD/Jacobian probes on x only). The fallback uses the
%   current filtered values as the references (equilibrium probe); it is NOT
%   a production path. The TS driver and equilibrium solver MUST supply u_dev.
if isempty(u_dev)
    P_ref = P_f;
    Q_ref = Q_f;
else
    P_ref = u_dev(1);
    Q_ref = u_dev(2);
end
end
