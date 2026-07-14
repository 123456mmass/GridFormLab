function dev = regfm_b1_vsg_model(device_id, bus_id, bus_position, bus_ids, V0, params, P_ref_pu, V_ref_pu)
%REGFM_B1_VSG_MODEL  Production GFM (grid-forming) VSM inverter, Phase 6 STRUCTURAL_ONLY.
%
%   dev = regfm_b1_vsg_model(DEVICE_ID, BUS_ID, BUS_POSITION, BUS_IDS, V0, PARAMS,
%                            P_REF_PU, V_REF_PU) returns a device struct conforming
%   to the stability.composite_dae ABI (R3 Revision 2: f, current_injection,
%   electrical_power, x0, u0, state_names, reconstruct; all taking
%   (t, x_dev, y, u_dev, event_context)).
%
%   BUS_IDS  - the network's external bus-ID vector (1 x nb). BUS_POSITION
%              indexes y for voltage measurement; BUS_ID is the external ID
%              used for injection mapping. They must refer to the same bus:
%              bus_ids(bus_position) == bus_id (else :busMappingMismatch).
%   V0       - complex PF-solved bus voltage at this device's bus. The PLL/VSM
%              angle initializes to angle(V0); |V0| is used for filter init.
%              A real V0 is accepted (treated as magnitude with angle 0).
%   P_REF_PU - active power reference [pu, SYSTEM base] (external ABI).
%   V_REF_PU - voltage magnitude reference [pu, system base].
%
%   Model: REGFM_B1 (NREL/TP-5D00-90260) VSM grid-forming inverter. Voltage-
%   source-behind-impedance output stage (Eq.13), VSM swing control (Fig.2),
%   measurement filters (Eqs.1-5), Q-V droop + voltage PI (Fig.3), PLL (Fig.4).
%   Phase-G-1 implements Eq.13 ImaxF transient clamp (Fig.7) and VPLLfrz PLL
%   freeze (Fig.4). Anti-windup, PQ priority, Fig.6 active-current limiter,
%   Eqs.10-11 Emin/Emax are deferred to Phase-G-2.
%
%   Per-unit base contract (user-confirmed, FROZEN before results):
%     External ABI: u(1)=P_ref on SYSTEM base (Sbase=100 MVA).
%     Internal REGFM: kappa = Sbase/Mbase; P_ref_inv = kappa*P_ref_sys.
%     Swing + filters run on INVERTER base (REGFM_B1 Eq.1 semantics).
%     current_injection and reconstructed P/Q return on SYSTEM base (composite KCL).
%     NO double conversion: P_ref converted once at the boundary.
%     Mbase = CASE_DEFINED unity-PF nameplate proxy (NOT Pmax-MW proven).
%
%   State vector (11, fixed order, PROJECT_DERIVED interface contract):
%     x_gfm = [omega_m; delta_VSM; x_washout; x_Eint; delta_PLL; x_PLL_int;
%              Pinv_f; Idinv_f; Qinv_f; Vinv_f; Iqinv_f]
%       omega_m    - VSM speed deviation (inverter base)              [pu]
%       delta_VSM  - VSM angle (network frame)                       [rad]
%       x_washout   - transient damping washout (Fig.2 D2*s/(s+wD))  [pu]
%       x_Eint      - voltage PI integral (Fig.3)                    [pu*s]
%       delta_PLL   - PLL angle (Fig.4)                              [rad]
%       x_PLL_int   - PLL PI integrator (Fig.4)                      [pu*s]
%       Pinv_f      - filtered active power (Eq.1, inv base)         [pu]
%       Idinv_f     - filtered active current (Eq.2, inv base)       [pu]
%       Qinv_f      - filtered reactive power (Eq.3, inv base)        [pu]
%       Vinv_f      - filtered voltage magnitude (Eq.4)              [pu]
%       Iqinv_f     - filtered reactive current (Eq.5, inv base)      [pu]
%
%   Inputs (nu=2): u = [P_ref; V_ref]  (pu, system base)
%     SOURCE_TRANSFORMED/PROJECT_MAPPED: with frozen flags VdrpFlag=0, QVFlag=1
%     the plant controller changes Vref and init sets Qref=0 (REGFM_B1 Fig.3 note).
%
%   Governing equations (frozen, see IEEE14_IBR_GFM_PHASE6_PROVENANCE.md):
%     Boundary: kappa = Sbase/Mbase; P_ref_inv = kappa*P_ref_sys.
%     V_bus = y(2*bp-1) + 1i*y(2*bp)   (network common xy frame)
%     dq via delta_PLL (Eqs.6-9):
%       Id =  Ix*cos(dPLL) + Iy*sin(dPLL)
%       Iq = -Ix*sin(dPLL) + Iy*cos(dPLL)
%       Vd =  Vx*cos(dPLL) + Vy*sin(dPLL)
%       Vq = -Vx*sin(dPLL) + Vy*cos(dPLL)
%     Output stage (Eq.13, LINEAR branch only; ImaxF clamp deferred):
%       I = (EVSM*exp(1i*delta_VSM) - V_bus)/(Re + 1i*XL)   % positive INTO net
%     Measured power (generator convention S = V*conj(I), SYSTEM base):
%       P_meas = Re(V_bus*conj(I));  Q_meas = Im(V_bus*conj(I))
%     Filters (Eqs.1-5, kappa = Sbase/Mbase):
%       Tpf*dPinv_f/dt  = kappa*P_meas  - Pinv_f    (Eq.1)
%       TIf*dIdinv_f/dt = kappa*Id     - Idinv_f   (Eq.2)
%       TQf*dQinv_f/dt  = kappa*Q_meas - Qinv_f    (Eq.3)
%       TVf*dVinv_f/dt  = |V_bus|      - Vinv_f    (Eq.4)
%       TIf*dIqinv_f/dt = kappa*Iq     - Iqinv_f   (Eq.5)
%     PLL (Fig.4; Delta-omegaPLL limits + freeze deferred):
%       dx_PLL_int/dt = Vq
%       d(delta_PLL)/dt = omega0*(kpPLL*Vq + kiPLL*x_PLL_int)
%     VSM swing (Fig.2, SOURCE_TRANSFORMED, FROZEN under flag profile
%       omegaFlag=0, FFlag=1, omega_ref=1 pu; INVERTER base):
%       2H*d(omega_m)/dt = P_ref_inv - Pinv_f ...
%                          - (1/mp + D1)*omega_m - D2*(omega_m - x_washout)
%       d(x_washout)/dt  = wD*(omega_m - x_washout)
%       d(delta_VSM)/dt   = omega0*omega_m
%     Voltage PI (Fig.3; Emax/Emin deferred):
%       d(x_Eint)/dt = V_ref - Vinv_f
%       EVSM = V_ref - mq*Qinv_f + kpv*(V_ref - Vinv_f) + kiv*x_Eint
%
%   Equilibrium (PROJECT_DERIVED): omega_m=0, x_washout=0, Pinv_f=P_ref_inv,
%     P_meas=P_ref_sys (system base), Vinv_f=|V|, delta_PLL=angle(V_bus),
%     delta_VSM=power angle s.t. I=(EVSM*exp(j*delta_VSM)-V)/(Re+jXL) delivers P_ref.
%
%   Classification:
%     - All REGFM_B1 Table 1 example values: SOURCE_VERBATIM (CASE_DEFINED
%       application to IEEE14 IBR converters). NO ASSUMED_DIAGNOSTIC (unlike
%       the GFL Kps/Kis).
%     - VSM swing ODE form (Fig.2 block-diagram collapse): SOURCE_TRANSFORMED.
%     - u=[P_ref;V_ref] mapping: SOURCE_TRANSFORMED/PROJECT_MAPPED.
%     - Mbase: CASE_DEFINED unity-PF nameplate proxy.
%
%   STATUS: IEEE14_IBR_GFM_MODEL_READY = STRUCTURAL_ONLY.
%   Phase-G-1 (Eq.13 clamp + VPLL freeze): IMPLEMENTED_STRUCTURAL_ONLY.
%   Phase-G-2 (anti-windup, PQ priority, Fig.6, Eqs.10-11): DEFERRED.
%   IBR_PRODUCTION_INTEGRATION_READY = NOT_READY.
%
%   Source: docs/project/IEEE14_IBR_GFM_PHASE6_PROVENANCE.md;
%           docs/project/IEEE14_IBR_DECISION_LEDGER.md (Item 2);
%           docs/project/IEEE14_IBR_FROZEN_CONTRACT.md (GFM item).
%   Primary source: REGFM_B1 NREL/TP-5D00-90260 (docs/paper/90260.pdf).

arguments
    device_id (1,1) string
    bus_id (1,1) double
    bus_position (1,1) double
    bus_ids (1,:) double
    V0 (1,1) double
    params struct
    P_ref_pu (1,1) double
    V_ref_pu (1,1) double
end

% --- F3: Validate bus_id <-> bus_position consistency -----------------------
if ~isfinite(bus_position) || bus_position ~= floor(bus_position)
    error('ibr:regfm_b1_vsg_model:busMappingMismatch', ...
        'bus_position must be a finite integer (got %.6g).', bus_position);
end
if bus_position < 1 || bus_position > numel(bus_ids)
    error('ibr:regfm_b1_vsg_model:busMappingMismatch', ...
        'bus_position %d out of range [1, %d] for bus_ids.', bus_position, numel(bus_ids));
end
if bus_ids(bus_position) ~= bus_id
    error('ibr:regfm_b1_vsg_model:busMappingMismatch', ...
        'bus_ids(%d)=%d != bus_id=%d; bus_position and bus_id must refer to the same bus.', ...
        bus_position, bus_ids(bus_position), bus_id);
end

% --- F1: Complex V0 (PF-solved bus voltage) -> magnitude + angle ------------
if ~isfinite(V0) || abs(V0) <= 0
    error('ibr:regfm_b1_vsg_model:badV0', ...
        'V0 must be finite with |V0|>0 (got %.6g); PF warm-start required.', V0);
end
V0_mag = abs(V0);
theta0 = angle(V0);

% --- F2: finite P_ref/V_ref validation -------------------------------------
if ~isfinite(P_ref_pu)
    error('ibr:regfm_b1_vsg_model:badRef', ...
        'P_ref_pu must be finite (got %.6g).', P_ref_pu);
end
if ~isfinite(V_ref_pu)
    error('ibr:regfm_b1_vsg_model:badRef', ...
        'V_ref_pu must be finite (got %.6g).', V_ref_pu);
end

% --- Parameters (frozen BEFORE results; REGFM_B1 Table 1 example values) ---
% All SOURCE_VERBATIM from REGFM_B1 NREL/TP-5D00-90260 Table 1. params may
% override ONLY for diagnostic sensitivity studies (never to force a pass).
% Production acceptance uses the frozen defaults. Any override reclassifies
% that parameter to DIAGNOSTIC_ONLY in the provenance.
omega0   = 376.9911184307752;  % 2*pi*60 rad/s, SOURCE_VERBATIM (Table 1 omega0)
H        = 0.5;                % s, SOURCE_VERBATIM (Table 1)
D1       = 0.0;                % pu, SOURCE_VERBATIM (Table 1)
D2       = 100.0;              % pu, SOURCE_VERBATIM (Table 1)
wD       = 50.0;               % pu, SOURCE_VERBATIM (Table 1)
mp       = 0.02;               % pu, SOURCE_VERBATIM (Table 1) P-f droop
mq       = 0.05;               % pu, SOURCE_VERBATIM (Table 1) Q-V droop
kpv      = 0.0;                % pu, SOURCE_VERBATIM (Table 1)
kiv      = 5.0;                % pu/s, SOURCE_VERBATIM (Table 1)
Re       = 0.0;                % pu, SOURCE_VERBATIM (Table 1)
XL       = 0.1;                % pu, SOURCE_VERBATIM (Table 1)
kpPLL    = 0.265;              % pu, SOURCE_VERBATIM (Table 1)
kiPLL    = 2.65;               % pu/s, SOURCE_VERBATIM (Table 1)
Tpf      = 0.02;               % s, SOURCE_VERBATIM (Table 1)
TQf      = 0.02;               % s, SOURCE_VERBATIM (Table 1)
TVf      = 0.02;               % s, SOURCE_VERBATIM (Table 1)
TIf      = 0.02;               % s, SOURCE_VERBATIM (Table 1)
ImaxSS   = 1.0;                % pu, SOURCE_VERBATIM (Table 1) [deferred limiter]
ImaxF    = 1.5;                % pu, SOURCE_VERBATIM (Table 1) [deferred limiter]
kf       = 0.9;                % NA, SOURCE_VERBATIM (Table 1) [deferred limiter]
kI       = 2.0;                % pu/s, SOURCE_VERBATIM (Table 1) [deferred limiter]
Ke       = 1.0;                % NA, SOURCE_VERBATIM (Table 1) [deferred limiter]
VPLLfrz  = 0.05;               % pu, SOURCE_VERBATIM (Table 1) [deferred freeze]
% Frozen flag profile (Phase 6, before results)
omegaFlag = 0;  VdrpFlag = 0;  QVFlag = 1;  PQFlag = 1;  FFlag = 1;  ESFlag = 1;
omega_ref = 1.0; % pu (frozen)
Sbase    = 100.0;              % MVA, SOURCE_VERBATIM (system base)
Mbase    = 100.0;              % MVA, CASE_DEFINED unity-PF nameplate proxy (default; per-IBR override)

% Track which parameters were overridden (F4 provenance reclassification).
overridden = struct('omega0',false,'H',false,'D1',false,'D2',false,'wD',false, ...
    'mp',false,'mq',false,'kpv',false,'kiv',false,'Re',false,'XL',false, ...
    'kpPLL',false,'kiPLL',false,'Tpf',false,'TQf',false,'TVf',false,'TIf',false, ...
    'Mbase',false);
ov_fields = fieldnames(overridden);
for fi = 1:numel(ov_fields)
    f = ov_fields{fi};
    if isfield(params, f) && ~isempty(params.(f))
        eval([f ' = params.' f ';']);
        overridden.(f) = true;
    end
end

% F4: validate every parameter (finite; positive for physical ones).
validate_param('omega0', omega0, true);
validate_param('H', H, true);
validate_param('D1', D1, false);
validate_param('D2', D2, false);
validate_param('wD', wD, true);
validate_param('mp', mp, true);
validate_param('mq', mq, false);
validate_param('kpv', kpv, false);
validate_param('kiv', kiv, false);
validate_param('Re', Re, false);
validate_param('XL', XL, true);
validate_param('kpPLL', kpPLL, false);
validate_param('kiPLL', kiPLL, false);
validate_param('Tpf', Tpf, true);
validate_param('TQf', TQf, true);
validate_param('TVf', TVf, true);
validate_param('TIf', TIf, true);
validate_param('Mbase', Mbase, true);   % nameplate proxy must be positive finite

% Boundary mapping: system base -> inverter base (NO double conversion).
kappa = Sbase / Mbase;
P_ref_inv = kappa * P_ref_pu;   % inverter base (REGFM_B1 Eq.1 semantics)

% --- Initial state (from PF warm-start; V_bus = V0 = V0_mag*exp(j*theta0)) --
omega_m0   = 0.0;
delta_VSM0 = theta0;            % VSM angle initialized to bus angle
x_washout0 = 0.0;
x_Eint0    = 0.0;
delta_PLL0 = theta0;            % PLL locked to bus angle
x_PLL_int0 = 0.0;
Pinv_f0    = P_ref_inv;         % inv base (Eq.1 steady state)
Idinv_f0   = 0.0;               % refined by Newton
Qinv_f0    = 0.0;              % Qref=0 init (VdrpFlag=0, QVFlag=1)
Vinv_f0    = V0_mag;
Iqinv_f0   = 0.0;
x0 = [omega_m0; delta_VSM0; x_washout0; x_Eint0; delta_PLL0; x_PLL_int0; ...
      Pinv_f0; Idinv_f0; Qinv_f0; Vinv_f0; Iqinv_f0];
u0 = [P_ref_pu; V_ref_pu];

% --- Captured constants for closures ----------------------------------------
bp = bus_position;   % 1-based index into y for this device's bus

% --- Differential RHS f(t, x_dev, y, u_dev, event_context) -----------------
f = @(t, x_dev, y, u_dev, event_context) gfm_f( ...
    x_dev, y, u_dev, bp, omega0, H, D1, D2, wD, mp, mq, kpv, kiv, Re, XL, ...
    kpPLL, kiPLL, Tpf, TQf, TVf, TIf, kappa, ImaxF, VPLLfrz);

% --- current_injection(t, x_dev, y, u_dev, event_context): complex, INTO net
current_injection = @(t, x_dev, y, u_dev, event_context) ...
    gfm_current_injection_g1( ...
    x_dev, y, u_dev, bp, kpv, kiv, mq, Re, XL, kappa, ImaxF);

% --- electrical_power(t, x_dev, y, u_dev, event_context): Pe (pu, system base)
electrical_power = @(t, x_dev, y, u_dev, event_context) gfm_pe_g1( ...
    x_dev, y, u_dev, bp, kpv, kiv, mq, Re, XL, kappa, ImaxF);

% --- reconstruct(t, x_dev, y, u_dev, event_context): struct -----------------
reconstruct = @(t, x_dev, y, u_dev, event_context) gfm_reconstruct_g1( ...
    x_dev, y, u_dev, bp, omega0, H, D1, D2, wD, mp, mq, kpv, kiv, Re, XL, ...
    kpPLL, kiPLL, Tpf, TQf, TVf, TIf, kappa, Mbase, Sbase, ImaxF, VPLLfrz);

% --- Assemble device struct (composite_dae ABI, R3 Revision 2) --------------
dev = struct();
dev.name = char(device_id);
dev.device_id = char(device_id);
dev.bus_id = bus_id;
dev.bus_position = bus_position;
dev.bus_ids = bus_ids(:).';
dev.device_type = 'ibr_gfm';
dev.mode = 'GFM';
dev.nx = 11;
dev.nu = 2;
dev.state_names = {'omega_m','delta_VSM','x_washout','x_Eint','delta_PLL', ...
    'x_PLL_int','Pinv_f','Idinv_f','Qinv_f','Vinv_f','Iqinv_f'};
dev.input_names = {'P_ref','V_ref'};
dev.x0 = x0;
dev.u0 = u0;
dev.f = f;
dev.current_injection = current_injection;
dev.electrical_power = electrical_power;
dev.reconstruct = reconstruct;
% F4: parameter classifications — frozen defaults keep their original label;
% any overridden parameter is reclassified DIAGNOSTIC_ONLY. Mbase is a
% CASE_DEFINED nameplate proxy (not a REGFM_B1 Table 1 value), so it keeps
% CASE_DEFINED unless overridden.
cls = @(nm) ternary(overridden.(nm), 'DIAGNOSTIC_ONLY', 'SOURCE_VERBATIM');
cls_Mbase = ternary(overridden.Mbase, 'DIAGNOSTIC_ONLY', 'CASE_DEFINED');
dev.provenance = struct( ...
    'model','gfm_regfm_b1_phase6_structural_only', ...
    'source','REGFM_B1 NREL/TP-5D00-90260 (docs/paper/90260.pdf) Eqs.1-13 + Table 1', ...
    'provenance_doc','docs/project/IEEE14_IBR_GFM_PHASE6_PROVENANCE.md', ...
    'V0', V0, 'V0_mag', V0_mag, 'theta0', theta0, ...
    'bus_id', bus_id, 'bus_position', bus_position, ...
    'params', struct('omega0',omega0,'H',H,'D1',D1,'D2',D2,'wD',wD,'mp',mp, ...
        'mq',mq,'kpv',kpv,'kiv',kiv,'Re',Re,'XL',XL,'kpPLL',kpPLL,'kiPLL',kiPLL, ...
        'Tpf',Tpf,'TQf',TQf,'TVf',TVf,'TIf',TIf,'ImaxSS',ImaxSS,'ImaxF',ImaxF, ...
        'kf',kf,'kI',kI,'Ke',Ke,'VPLLfrz',VPLLfrz,'Mbase',Mbase,'Sbase',Sbase, ...
        'omegaFlag',omegaFlag,'VdrpFlag',VdrpFlag,'QVFlag',QVFlag,'PQFlag',PQFlag, ...
        'FFlag',FFlag,'ESFlag',ESFlag,'omega_ref',omega_ref), ...
    'param_classifications', struct( ...
        'omega0',cls('omega0'),'H',cls('H'),'D1',cls('D1'),'D2',cls('D2'), ...
        'wD',cls('wD'),'mp',cls('mp'),'mq',cls('mq'),'kpv',cls('kpv'),'kiv',cls('kiv'), ...
        'Re',cls('Re'),'XL',cls('XL'),'kpPLL',cls('kpPLL'),'kiPLL',cls('kiPLL'), ...
        'Tpf',cls('Tpf'),'TQf',cls('TQf'),'TVf',cls('TVf'),'TIf',cls('TIf'), ...
        'Mbase',cls_Mbase), ...
    'input_classifications', struct( ...
        'P_ref','SOURCE_TRANSFORMED_PROJECT_MAPPED', ...
        'V_ref','SOURCE_TRANSFORMED_PROJECT_MAPPED'), ...
    'swing_form','SOURCE_TRANSFORMED (Fig.2 block-diagram collapse, frozen under omegaFlag=0,FFlag=1,omega_ref=1 pu)', ...
    'pu_base_contract','external=system base; internal swing/filters=inverter base (kappa=Sbase/Mbase); no double conversion', ...
    'param_overridden', overridden, ...
    'readiness','STRUCTURAL_ONLY', ...
    'phase_g1_status','IMPLEMENTED_STRUCTURAL_ONLY');
end

% =========================================================================
function [I_out_sys, I_unc_sys, I_limited] = limited_current( ...
    EVSM, delta_VSM, V_bus, Re, XL, kappa, ImaxF)
%LIMITED_CURRENT  Shared Eq.13 clamp (Phase-G-1). Called by gfm_f, current_injection, pe, reconstruct.
%   REGFM_B1 Eq.13, Fig.7. ImaxF on inverter base, converted to system base.
%   Source: REGFM_B1 NREL/TP-5D00-90260 Eq.13, Fig.7, Table 1.
Z_sys = kappa * (Re + 1i*XL);           % PROJECT_DERIVED: convert impedance to system base
ImaxF_sys = ImaxF / kappa;              % PROJECT_DERIVED: convert threshold to system base
I_unc_sys = (EVSM * exp(1i*delta_VSM) - V_bus) / Z_sys;
I_mag = abs(I_unc_sys);
if I_mag < ImaxF_sys
    I_out_sys = I_unc_sys;
    I_limited = false;
else
    I_out_sys = ImaxF_sys * (I_unc_sys / I_mag);   % circular saturation
    I_limited = true;
end
end

% =========================================================================
function out = ternary(cond, val_true, val_false)
if cond, out = val_true; else, out = val_false; end
end

% =========================================================================
function [P_ref, V_ref] = refs_from_u(u_dev)
%REFS_FROM_U  Extract P_ref/V_ref from u_dev (FAIL-CLOSED, F2).
if isempty(u_dev)
    error('ibr:regfm_b1_vsg_model:missingInput', ...
        'u_dev is empty; the GFM requires u=[P_ref;V_ref] (nu=2).');
end
if numel(u_dev) ~= 2
    error('ibr:regfm_b1_vsg_model:badInput', ...
        'u_dev has %d element(s); expected exactly 2 ([P_ref;V_ref]).', numel(u_dev));
end
if ~isfinite(u_dev(1)) || ~isfinite(u_dev(2))
    error('ibr:regfm_b1_vsg_model:badInput', ...
        'u_dev has non-finite entries (P_ref=%.6g, V_ref=%.6g).', u_dev(1), u_dev(2));
end
P_ref = u_dev(1);
V_ref = u_dev(2);
end

% =========================================================================
function dx = gfm_f(x_dev, y, u_dev, bp, omega0, H, D1, D2, wD, mp, mq, kpv, kiv, ...
    Re, XL, kpPLL, kiPLL, Tpf, TQf, TVf, TIf, kappa, ImaxF, VPLLfrz)
%GFM_F  Differential RHS (11 states). Phase-G-1: shared limited current + PLL freeze.
omega_m    = x_dev(1);
delta_VSM  = x_dev(2);
x_washout  = x_dev(3);
x_Eint     = x_dev(4);
delta_PLL  = x_dev(5);
x_PLL_int  = x_dev(6);
Pinv_f     = x_dev(7);
Idinv_f    = x_dev(8);
Qinv_f     = x_dev(9);
Vinv_f     = x_dev(10);
Iqinv_f    = x_dev(11);
[P_ref_sys, V_ref] = refs_from_u(u_dev);
P_ref_inv = kappa * P_ref_sys;   % boundary mapping (no double conversion)

% Network-frame bus voltage.
V_bus = complex(y(2*bp-1), y(2*bp));
EVSM  = V_ref - mq*Qinv_f + kpv*(V_ref - Vinv_f) + kiv*x_Eint;

% G1: shared limited current (Eq.13, Fig.7).
[I_out, ~, ~] = limited_current(EVSM, delta_VSM, V_bus, Re, XL, kappa, ImaxF);

% Measured power (generator convention, SYSTEM base). Uses limited I_out.
S = V_bus * conj(I_out);
P_meas = real(S);
Q_meas = imag(S);

% dq currents via PLL angle (Eqs.6-7). Uses limited I_out.
Ix = real(I_out);  Iy = imag(I_out);
Id =  Ix*cos(delta_PLL) + Iy*sin(delta_PLL);
Iq = -Ix*sin(delta_PLL) + Iy*cos(delta_PLL);
% dq voltage (Eqs.8-9).
Vx = real(V_bus);  Vy = imag(V_bus);
Vq = -Vx*sin(delta_PLL) + Vy*cos(delta_PLL);

% VSM swing (Fig.2, SOURCE_TRANSFORMED, inverter base).
d_omega_m = (P_ref_inv - Pinv_f - (1/mp + D1)*omega_m - D2*(omega_m - x_washout)) / (2*H);
d_x_washout = wD*(omega_m - x_washout);
d_delta_VSM = omega0*omega_m;

% Voltage PI (Fig.3).
d_x_Eint = V_ref - Vinv_f;

% G1: PLL freeze at low voltage (REGFM_B1 Fig.4, Table 1 VPLLfrz=0.05 pu).
if abs(V_bus) < VPLLfrz
    d_x_PLL_int = 0;
    d_delta_PLL = 0;
else
    d_x_PLL_int = Vq;
    d_delta_PLL = omega0*(kpPLL*Vq + kiPLL*x_PLL_int);
end

% Filters (Eqs.1-5, kappa = Sbase/Mbase). Uses limited Id/Iq/P_meas.
d_Pinv_f  = (kappa*P_meas  - Pinv_f)  / Tpf;
d_Idinv_f = (kappa*Id      - Idinv_f) / TIf;
d_Qinv_f  = (kappa*Q_meas  - Qinv_f)  / TQf;
d_Vinv_f  = (abs(V_bus)    - Vinv_f)  / TVf;
d_Iqinv_f = (kappa*Iq      - Iqinv_f) / TIf;

dx = [d_omega_m; d_delta_VSM; d_x_washout; d_x_Eint; d_delta_PLL; d_x_PLL_int; ...
      d_Pinv_f; d_Idinv_f; d_Qinv_f; d_Vinv_f; d_Iqinv_f];
end

% =========================================================================
function I = gfm_current_injection_g1(x_dev, y, u_dev, bp, kpv, kiv, mq, Re, XL, kappa, ImaxF)
%GFM_CURRENT_INJECTION_G1  Phase-G-1: shared limited current (REGFM_B1 Eq.13, Fig.7).
delta_VSM = x_dev(2);
x_Eint    = x_dev(4);
Qinv_f    = x_dev(9);
Vinv_f    = x_dev(10);
[~, V_ref] = refs_from_u(u_dev);
V_bus = complex(y(2*bp-1), y(2*bp));
EVSM = V_ref - mq*Qinv_f + kpv*(V_ref - Vinv_f) + kiv*x_Eint;
[I, ~, ~] = limited_current(EVSM, delta_VSM, V_bus, Re, XL, kappa, ImaxF);
end

% =========================================================================
function Pe = gfm_pe_g1(x_dev, y, u_dev, bp, kpv, kiv, mq, Re, XL, kappa, ImaxF)
%GFM_PE_G1  Phase-G-1: electrical power from shared limited current (system base).
delta_VSM = x_dev(2);
x_Eint    = x_dev(4);
Qinv_f    = x_dev(9);
Vinv_f    = x_dev(10);
[~, V_ref] = refs_from_u(u_dev);
V_bus = complex(y(2*bp-1), y(2*bp));
EVSM = V_ref - mq*Qinv_f + kpv*(V_ref - Vinv_f) + kiv*x_Eint;
[I, ~, ~] = limited_current(EVSM, delta_VSM, V_bus, Re, XL, kappa, ImaxF);
Pe = real(V_bus * conj(I));
end

% =========================================================================
function out = gfm_reconstruct_g1(x_dev, y, u_dev, bp, omega0, H, D1, D2, wD, mp, mq, ...
    kpv, kiv, Re, XL, kpPLL, kiPLL, Tpf, TQf, TVf, TIf, kappa, Mbase, Sbase, ImaxF, VPLLfrz)
%GFM_RECONSTRUCT_G1  Phase-G-1: device outputs with limiter metadata.
omega_m    = x_dev(1);
delta_VSM  = x_dev(2);
x_washout  = x_dev(3);
x_Eint     = x_dev(4);
delta_PLL  = x_dev(5);
x_PLL_int  = x_dev(6);
Pinv_f     = x_dev(7);
Idinv_f    = x_dev(8);
Qinv_f     = x_dev(9);
Vinv_f     = x_dev(10);
Iqinv_f    = x_dev(11);
[P_ref_sys, V_ref] = refs_from_u(u_dev);
V_bus = complex(y(2*bp-1), y(2*bp));
EVSM = V_ref - mq*Qinv_f + kpv*(V_ref - Vinv_f) + kiv*x_Eint;
[I_out, I_unc, I_limited] = limited_current(EVSM, delta_VSM, V_bus, Re, XL, kappa, ImaxF);
ImaxF_sys = ImaxF / kappa;
S = V_bus * conj(I_out);
PLL_frozen = abs(V_bus) < VPLLfrz;
out = struct( ...
    'omega_m', omega_m, 'delta_VSM', delta_VSM, 'x_washout', x_washout, ...
    'x_Eint', x_Eint, 'delta_PLL', delta_PLL, 'x_PLL_int', x_PLL_int, ...
    'Pinv_f', Pinv_f, 'Idinv_f', Idinv_f, 'Qinv_f', Qinv_f, ...
    'Vinv_f', Vinv_f, 'Iqinv_f', Iqinv_f, ...
    'EVSM', EVSM, 'I_gfm', I_out, 'Vbus', abs(V_bus), ...
    'Pe', real(S), 'Qe', imag(S), ...
    'kappa', kappa, 'Mbase', Mbase, 'Sbase', Sbase, ...
    'P_ref_inv', kappa*P_ref_sys, ...
    'ImaxF_inv', ImaxF, 'ImaxF_sys', ImaxF_sys, ...
    'I_unc_sys', I_unc, 'I_abs_unc', abs(I_unc), 'I_abs_out', abs(I_out), ...
    'I_limited', I_limited, 'VPLLfrz', VPLLfrz, 'PLL_frozen', PLL_frozen);
end

% =========================================================================
function validate_param(name, val, must_be_positive)
%VALIDATE_PARAM  F4: validate a parameter is finite (and positive if physical).
if ~isfinite(val)
    error('ibr:regfm_b1_vsg_model:badParam', ...
        'parameter %s is non-finite (%.6g).', name, val);
end
if must_be_positive && val <= 0
    error('ibr:regfm_b1_vsg_model:badParam', ...
        'parameter %s must be positive (got %.6g).', name, val);
end
end
