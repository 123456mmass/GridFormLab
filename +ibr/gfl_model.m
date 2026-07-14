function dev = gfl_model(device_id, bus_id, bus_position, bus_ids, V0, params, P_ref_pu, Q_ref_pu)
%GFL_MODEL  Production GFL (grid-following) inverter device, Phase 5 STRUCTURAL_ONLY.
%
%   dev = gfl_model(DEVICE_ID, BUS_ID, BUS_POSITION, BUS_IDS, V0, PARAMS, P_REF_PU, Q_REF_PU)
%   returns a device struct conforming to the stability.composite_dae ABI
%   (R3 Revision 2: f, current_injection, electrical_power, x0, u0,
%   state_names, reconstruct; all taking (t, x_dev, y, u_dev, event_context)).
%   The optional equilibrium initializer has the uniform device signature
%     x_eq = equilibrium_initialize(V_bus, P_terminal_pu, ...
%                                  Q_terminal_pu, event_context)
%   and returns the exact six-state equilibrium for the supplied terminal
%   voltage and system-base terminal power. It does not solve network KCL.
%
%   BUS_IDS  - the network's external bus-ID vector (1 x nb). BUS_POSITION
%              indexes y for voltage measurement; BUS_ID is the external ID
%              used for injection mapping. They must refer to the same bus:
%              bus_ids(bus_position) == bus_id (else :busMappingMismatch).
%   V0       - complex PF-solved bus voltage at this device's bus. The PLL
%              initializes locked to angle(V0); |V0| is used for the PI init.
%              A real V0 is accepted (treated as magnitude with angle 0).
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
    bus_ids (1,:) double
    V0 (1,1) {mustBeFinite}
    params struct
    P_ref_pu (1,1) double
    Q_ref_pu (1,1) double
end

% --- F3: Validate bus_id <-> bus_position consistency -----------------------
% bus_position indexes the shared y vector (voltage measurement); bus_id is
% the external ID used for injection mapping in composite_dae. They MUST
% refer to the same physical bus: bus_ids(bus_position) == bus_id.
% Round-2 F3: bus_position must be a finite integer (a fractional position is
% a caller bug; without this guard it falls through to bus_ids(1.5) and errors
% with the generic MATLAB:badsubscript instead of our stable ID).
if ~isfinite(bus_position) || bus_position ~= floor(bus_position)
    error('ibr:gfl_model:busMappingMismatch', ...
        'bus_position must be a finite integer (got %.6g).', bus_position);
end
if bus_position < 1 || bus_position > numel(bus_ids)
    error('ibr:gfl_model:busMappingMismatch', ...
        'bus_position %d out of range [1, %d] for bus_ids.', bus_position, numel(bus_ids));
end
if bus_ids(bus_position) ~= bus_id
    error('ibr:gfl_model:busMappingMismatch', ...
        'bus_ids(%d)=%d != bus_id=%d; bus_position and bus_id must refer to the same bus.', ...
        bus_position, bus_ids(bus_position), bus_id);
end

% --- F1: Complex V0 (PF-solved bus voltage) -> magnitude + angle ------------
% V0 may be real (legacy: magnitude, angle 0) or complex (full PF voltage).
% delta_pll0 = angle(V0) so the PLL initializes locked to the bus angle.
if ~isfinite(V0) || abs(V0) <= 0
    error('ibr:gfl_model:badV0', ...
        'V0 must be finite with |V0|>0 (got %.6g); PF warm-start required.', V0);
end
V0_mag = abs(V0);
theta0 = angle(V0);

% --- F2 (round-2): finite P_ref/Q_ref validation ---------------------------
% The arguments block only enforces (1,1) double; a non-finite reference
% (NaN/Inf) would propagate into x0/u0 and the PI integrators, producing
% silent NaN/Inf trajectories. Validate before any use.
if ~isfinite(P_ref_pu)
    error('ibr:gfl_model:badRef', ...
        'P_ref_pu must be finite (got %.6g).', P_ref_pu);
end
if ~isfinite(Q_ref_pu)
    error('ibr:gfl_model:badRef', ...
        'Q_ref_pu must be finite (got %.6g).', Q_ref_pu);
end

% --- Parameters (frozen BEFORE results; see provenance doc) -----------------
% Defaults reflect the Phase 5 freeze; params may override ONLY for diagnostic
% sensitivity studies (never to force a pass). Production acceptance uses the
% frozen defaults. F4: any override reclassifies that parameter to
% DIAGNOSTIC_ONLY in the provenance; non-finite/non-physical overrides error.
omega0 = 376.9911184307752;   % 2*pi*60 rad/s, SOURCE_VERBATIM (REGFM_B1 Table 1 omega0)
omega_c = 10.0;               % rad/s, SOURCE_VERBATIM (Ding Table I)
kpPLL = 0.265;                % pu, SOURCE_VERBATIM value (REGFM_B1 Table 1)
kiPLL = 2.65;                 % pu/s, SOURCE_VERBATIM value (REGFM_B1 Table 1)
Kps = 1.0;                    % ASSUMED_DIAGNOSTIC (Ding Table I lacks)
Kis = 10.0;                   % 1/s, ASSUMED_DIAGNOSTIC (Ding Table I lacks)
Sbase = 100.0;                % MVA, SOURCE_VERBATIM (system base; no Mbase factor)

% Track which parameters were overridden (F4 provenance reclassification).
overridden = struct('omega0',false,'omega_c',false,'kpPLL',false, ...
    'kiPLL',false,'Kps',false,'Kis',false);
if isfield(params,'omega0')  && ~isempty(params.omega0),  omega0  = params.omega0;  overridden.omega0  = true; end
if isfield(params,'omega_c') && ~isempty(params.omega_c), omega_c = params.omega_c; overridden.omega_c = true; end
if isfield(params,'kpPLL')   && ~isempty(params.kpPLL),   kpPLL   = params.kpPLL;   overridden.kpPLL   = true; end
if isfield(params,'kiPLL')   && ~isempty(params.kiPLL),   kiPLL   = params.kiPLL;   overridden.kiPLL   = true; end
if isfield(params,'Kps')     && ~isempty(params.Kps),     Kps     = params.Kps;     overridden.Kps     = true; end
if isfield(params,'Kis')     && ~isempty(params.Kis),     Kis     = params.Kis;     overridden.Kis     = true; end

% F4: validate every parameter (finite; positive for physical ones).
validate_param('omega0', omega0, true);
validate_param('omega_c', omega_c, true);
validate_param('kpPLL', kpPLL, true);
validate_param('kiPLL', kiPLL, true);
validate_param('Kps', Kps, true);
validate_param('Kis', Kis, true);

% --- Initial state (from PF warm-start; V_bus = V0 = V0_mag*exp(j*theta0)) --
% F1: delta_pll0 = angle(V_bus) = theta0 (PLL locked to the bus angle).
delta_pll0 = theta0;
eps_pll0 = 0.0;
P_f0 = P_ref_pu;
Q_f0 = Q_ref_pu;
phi_P0 = P_ref_pu / (V0_mag * Kis);
phi_Q0 = Q_ref_pu / (V0_mag * Kis);
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

% --- Optional exact device-equilibrium initializer -------------------------
% PROJECT_DERIVED inversion of the sourced reduced GFL equations. The caller
% must use matching u=[P_terminal;Q_terminal] when evaluating the returned
% state. Network KCL remains owned by composite_dae/mixed_equilibrium_solve.
equilibrium_initialize = @(V_bus, P_terminal_pu, Q_terminal_pu, event_context) ...
    gfl_equilibrium_initialize(V_bus, P_terminal_pu, Q_terminal_pu, ...
        event_context, Kis);

% --- Assemble device struct (composite_dae ABI, R3 Revision 2) --------------
dev = struct();
dev.name = char(device_id);
dev.device_id = char(device_id);
dev.bus_id = bus_id;
dev.bus_position = bus_position;          % F3: stored explicitly
dev.bus_ids = bus_ids(:).';               % F3: network external bus IDs
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
dev.equilibrium_initialize = equilibrium_initialize;
% F4: parameter classifications — frozen defaults keep their original label;
% any overridden parameter is reclassified DIAGNOSTIC_ONLY.
cls_omega0  = ternary(overridden.omega0,  'DIAGNOSTIC_ONLY', 'SOURCE_VERBATIM');
cls_omega_c = ternary(overridden.omega_c, 'DIAGNOSTIC_ONLY', 'SOURCE_VERBATIM');
cls_kpPLL   = ternary(overridden.kpPLL,   'DIAGNOSTIC_ONLY', 'SOURCE_VERBATIM_value_CASE_DEFINED_PROJECT_MAPPED_application');
cls_kiPLL   = ternary(overridden.kiPLL,   'DIAGNOSTIC_ONLY', 'SOURCE_VERBATIM_value_CASE_DEFINED_PROJECT_MAPPED_application');
cls_Kps     = ternary(overridden.Kps,     'DIAGNOSTIC_ONLY', 'ASSUMED_DIAGNOSTIC');
cls_Kis     = ternary(overridden.Kis,     'DIAGNOSTIC_ONLY', 'ASSUMED_DIAGNOSTIC');
% Provenance metadata (serializable; NO function handles).
dev.provenance = struct( ...
    'model','gfl_phase5_structural_only', ...
    'source','Ding NREL/CP-6A40-83340 Sec II-B Eqs.7-10 (RMS-reduced) + REGFM_B1 NREL/TP-5D00-90260 Table 1', ...
    'provenance_doc','docs/project/IEEE14_IBR_GFL_PHASE5_PROVENANCE.md', ...
    'V0', V0, 'V0_mag', V0_mag, 'theta0', theta0, ...
    'bus_id', bus_id, 'bus_position', bus_position, ...
    'params', struct('omega0',omega0,'omega_c',omega_c,'kpPLL',kpPLL, ...
                     'kiPLL',kiPLL,'Kps',Kps,'Kis',Kis,'Sbase',Sbase), ...
    'param_classifications', struct( ...
        'omega0',cls_omega0, ...
        'omega_c',cls_omega_c, ...
        'kpPLL',cls_kpPLL, ...
        'kiPLL',cls_kiPLL, ...
        'Kps',cls_Kps, ...
        'Kis',cls_Kis), ...
    'param_overridden', overridden, ...
    'readiness','STRUCTURAL_ONLY');
end

% =========================================================================
function x_eq = gfl_equilibrium_initialize( ...
    V_bus, P_terminal_pu, Q_terminal_pu, event_context, Kis) %#ok<INUSD>
%GFL_EQUILIBRIUM_INITIALIZE  Exact reduced-GFL device equilibrium.
%   P_terminal_pu and Q_terminal_pu use the generator convention
%   S=V*conj(I), positive INTO the network, on the system base.
if ~isscalar(V_bus) || ~isfinite(V_bus) || abs(V_bus) <= 0
    error('ibr:gfl_model:equilibriumBadVoltage', ...
        'Equilibrium V_bus must be a finite nonzero scalar phasor.');
end
if ~isscalar(P_terminal_pu) || ~isscalar(Q_terminal_pu) || ...
        ~isreal(P_terminal_pu) || ~isreal(Q_terminal_pu) || ...
        ~isfinite(P_terminal_pu) || ~isfinite(Q_terminal_pu)
    error('ibr:gfl_model:equilibriumBadPower', ...
        'Equilibrium terminal P/Q must be finite real scalars on system base.');
end

Vmag = abs(V_bus);
delta_pll = angle(V_bus);     % positive-d-axis PLL lock
eps_pll = 0.0;
P_f = P_terminal_pu;
Q_f = Q_terminal_pu;
% With zero power error, Ding Eq.10 gives id*=Kis*phi_P and
% iq*=-Kis*phi_Q. At PLL lock S=Vmag*(id-j*iq).
phi_P = P_terminal_pu / (Vmag*Kis);
phi_Q = Q_terminal_pu / (Vmag*Kis);
x_eq = [delta_pll; eps_pll; P_f; Q_f; phi_P; phi_Q];
end

% =========================================================================
function out = ternary(cond, val_true, val_false)
%TERNARY  Inline conditional (MATLAB has no ternary operator).
if cond, out = val_true; else, out = val_false; end
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
function [P_ref, Q_ref] = refs_from_u(u_dev, ~, ~)
%REFS_FROM_U  Extract P_ref/Q_ref from u_dev (FAIL-CLOSED, F2).
%   The composite_dae ABI passes u_dev for nu>0 devices; an empty or
%   non-finite u_dev is a caller bug, not a degenerate probe. The GFL device
%   refuses to evaluate f / current_injection without a valid 2-element input.
if isempty(u_dev)
    error('ibr:gfl_model:missingInput', ...
        'u_dev is empty; the GFL requires u=[P_ref;Q_ref] (nu=2).');
end
% Round-2 F1: reject BOTH undersized and oversized inputs. The nu=2 contract
% requires exactly 2 elements; a 3+ element u_dev was previously silently
% truncated (only the first 2 used), hiding an ABI violation.
if numel(u_dev) ~= 2
    error('ibr:gfl_model:badInput', ...
        'u_dev has %d element(s); expected exactly 2 ([P_ref;Q_ref]).', numel(u_dev));
end
if ~isfinite(u_dev(1)) || ~isfinite(u_dev(2))
    error('ibr:gfl_model:badInput', ...
        'u_dev has non-finite entries (P_ref=%.6g, Q_ref=%.6g).', u_dev(1), u_dev(2));
end
P_ref = u_dev(1);
Q_ref = u_dev(2);
end

% =========================================================================
function validate_param(name, val, must_be_positive)
%VALIDATE_PARAM  F4: validate a parameter is finite (and positive if physical).
if ~isfinite(val)
    error('ibr:gfl_model:badParam', ...
        'parameter %s is non-finite (%.6g).', name, val);
end
if must_be_positive && val <= 0
    error('ibr:gfl_model:badParam', ...
        'parameter %s must be positive (got %.6g).', name, val);
end
end
