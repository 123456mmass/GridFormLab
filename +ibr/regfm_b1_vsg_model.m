function dev = regfm_b1_vsg_model(device_id, bus_id, bus_position, bus_ids, V0, params, P_ref_pu, V_ref_pu)
%REGFM_B1_VSG_MODEL  REGFM_B1 G2 grid-forming VSM inverter.
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
%   freeze (Fig.4). Phase-G-2 implements Fig.5 steady-state PQ priority,
%   Eqs.10-11 Emin/Emax, the Fig.6 upper/lower delta_IT bound controllers,
%   and PROJECT_DERIVED conditional-integration anti-windup.
%   The optional equilibrium initializer has the uniform device signature
%     x_eq = equilibrium_initialize(V_bus, P_terminal_pu, ...
%                                  Q_terminal_pu, event_context)
%   and algebraically inverts the sourced equations for an exact device
%   equilibrium. It does not solve network KCL or prescribe the GFM's final Q.
%
%   Per-unit base contract (user-confirmed, FROZEN before results):
%     External ABI: u(1)=P_ref on SYSTEM base (Sbase=100 MVA).
%     Internal REGFM: kappa = Sbase/Mbase; P_ref_inv = kappa*P_ref_sys.
%     Swing + filters run on INVERTER base (REGFM_B1 Eq.1 semantics).
%     current_injection and reconstructed P/Q return on SYSTEM base (composite KCL).
%     NO double conversion: P_ref converted once at the boundary.
%     Mbase = CASE_DEFINED unity-PF nameplate proxy (NOT Pmax-MW proven).
%
%   State vector (13, fixed order, PROJECT_DERIVED interface contract):
%     x_gfm = [omega_m; delta_IT; x_washout; x_Eint; delta_PLL; x_PLL_int;
%              Pinv_f; Idinv_f; Qinv_f; Vinv_f; Iqinv_f;
%              delta_ITmax; delta_ITmin]
%       omega_m    - VSM speed deviation (inverter base)              [pu]
%       delta_IT   - PLL-relative VSM angle                          [rad]
%       x_washout   - transient damping washout (Fig.2 D2*s/(s+wD))  [pu]
%       x_Eint      - voltage PI integral (Fig.3)                    [pu*s]
%       delta_PLL   - PLL angle (Fig.4)                              [rad]
%       x_PLL_int   - PLL PI integrator (Fig.4)                      [pu*s]
%       Pinv_f      - filtered active power (Eq.1, inv base)         [pu]
%       Idinv_f     - filtered active current (Eq.2, inv base)       [pu]
%       Qinv_f      - filtered reactive power (Eq.3, inv base)        [pu]
%       Vinv_f      - filtered voltage magnitude (Eq.4)              [pu]
%       Iqinv_f     - filtered reactive current (Eq.5, inv base)      [pu]
%       delta_ITmax - Fig.6 positive active-current angle bound      [rad]
%       delta_ITmin - Fig.6 negative active-current angle bound      [rad]
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
%     Angle identity and output stage (Fig.2/Fig.6 + Eq.13):
%       delta_VSM = delta_PLL + clamp(delta_IT,delta_ITmin,delta_ITmax)
%       Iunc = (EVSM*exp(1i*delta_VSM) - V_bus)/(kappa*(Re + 1i*XL))
%       I = Iunc when |Iunc|<ImaxF/kappa; otherwise circularly limited
%     Measured power (generator convention S = V*conj(I), SYSTEM base):
%       P_meas = Re(V_bus*conj(I));  Q_meas = Im(V_bus*conj(I))
%     Filters (Eqs.1-5, kappa = Sbase/Mbase):
%       Tpf*dPinv_f/dt  = kappa*P_meas  - Pinv_f    (Eq.1)
%       TIf*dIdinv_f/dt = kappa*Id     - Idinv_f   (Eq.2)
%       TQf*dQinv_f/dt  = kappa*Q_meas - Qinv_f    (Eq.3)
%       TVf*dVinv_f/dt  = |V_bus|      - Vinv_f    (Eq.4)
%       TIf*dIqinv_f/dt = kappa*Iq     - Iqinv_f   (Eq.5)
%     PLL (Fig.4; Delta-omegaPLL limits deferred; VPLLfrz implemented):
%       dx_PLL_int/dt = Vq
%       d(delta_PLL)/dt = omega0*(kpPLL*Vq + kiPLL*x_PLL_int)
%     VSM swing (Fig.2, SOURCE_TRANSFORMED, FROZEN under flag profile
%       omegaFlag=0, FFlag=1, omega_ref=1 pu; INVERTER base):
%       2H*d(omega_m)/dt = P_ref_inv - Pinv_f ...
%                          - (1/mp + D1)*omega_m - D2*(omega_m - x_washout)
%       d(x_washout)/dt  = wD*(omega_m - x_washout)
%       d(delta_IT)/dt    = omega0*omega_m, with conditional bound hold
%     Voltage PI and G2 limits (Fig.3, Fig.5, Eqs.10-12):
%       d(x_Eint)/dt = V_ref - Vinv_f
%       EVSM_raw = V_ref - mq*Qinv_f + kpv*(V_ref - Vinv_f) + kiv*x_Eint
%       EVSM = clamp(EVSM_raw,Emin_iq_lim,Emax_iq_lim)
%       d(delta_ITmax)/dt = kI*(IdmaxSS-Idinv_f)
%       d(delta_ITmin)/dt = kI*(-Ke*IdmaxSS-Idinv_f), when ESFlag=1
%
%   Equilibrium (PROJECT_DERIVED): omega_m=0, x_washout=0, Pinv_f=P_ref_inv,
%     P_meas=P_ref_sys (system base), Vinv_f=|V|, delta_PLL=angle(V_bus),
%     delta_IT=angle(E_terminal)-delta_PLL and delta_VSM=delta_PLL+delta_IT,
%     with Fig.6 bounds initialized at +/-asin(XL*ImaxSS).
%
%   Classification:
%     - All REGFM_B1 Table 1 example values: SOURCE_VERBATIM (CASE_DEFINED
%       application to IEEE14 IBR converters). NO ASSUMED_DIAGNOSTIC (unlike
%       the independently sourced WECC GFL branch).
%     - VSM swing ODE form (Fig.2 block-diagram collapse): SOURCE_TRANSFORMED.
%     - u=[P_ref;V_ref] mapping: SOURCE_TRANSFORMED/PROJECT_MAPPED.
%     - Mbase: CASE_DEFINED unity-PF nameplate proxy.
%
%   STATUS: SOURCE_IMPLEMENTED_PENDING_INTEGRATION_GATES.
%   G1 Eq.13 clamp/VPLL freeze and G2 PQ priority, Eqs.10-11, Fig.6
%   dynamic bounds, and PROJECT_DERIVED conditional anti-windup are active.
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
ImaxSS   = 1.0;                % pu, SOURCE_VERBATIM (Table 1)
ImaxF    = 1.5;                % pu, SOURCE_VERBATIM (Table 1) [G1 implemented]
kf       = 0.9;                % NA, SOURCE_VERBATIM (Table 1)
kI       = 2.0;                % pu/s, SOURCE_VERBATIM (Table 1)
Ke       = 1.0;                % NA, SOURCE_VERBATIM (Table 1)
VPLLfrz  = 0.05;               % pu, SOURCE_VERBATIM (Table 1) [G1 implemented]
% Frozen flag profile (Phase 6, before results)
omegaFlag = 0;  VdrpFlag = 0;  QVFlag = 1;  PQFlag = 1;  FFlag = 1;  ESFlag = 1;
omega_ref = 1.0; % pu (frozen)
Sbase    = 100.0;              % MVA, SOURCE_VERBATIM (system base)
Mbase    = 100.0;              % MVA, CASE_DEFINED unity-PF nameplate proxy (default; per-IBR override)

% Track which parameters were overridden (F4 provenance reclassification).
overridden = struct('omega0',false,'H',false,'D1',false,'D2',false,'wD',false, ...
    'mp',false,'mq',false,'kpv',false,'kiv',false,'Re',false,'XL',false, ...
    'kpPLL',false,'kiPLL',false,'Tpf',false,'TQf',false,'TVf',false,'TIf',false, ...
    'ImaxSS',false,'ImaxF',false,'kf',false,'kI',false,'Ke',false, ...
    'VPLLfrz',false,'PQFlag',false,'ESFlag',false,'Mbase',false);
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
validate_param('ImaxSS', ImaxSS, true);
validate_param('ImaxF', ImaxF, true);
validate_param('kI', kI, true);
validate_param('Ke', Ke, false);
validate_param('VPLLfrz', VPLLfrz, false);
validate_param('Mbase', Mbase, true);   % nameplate proxy must be positive finite
if kf == 0
    warning('ibr:regfm_b1_vsg_model:kfReset', ...
        'kf=0 reset to 1 per REGFM_B1 parameter contract.');
    kf = 1;
elseif ~isfinite(kf) || kf < 0
    error('ibr:regfm_b1_vsg_model:badParam', ...
        'parameter kf must be finite and nonnegative.');
end
if ~(PQFlag==0 || PQFlag==1) || ~(ESFlag==0 || ESFlag==1) || ...
        Ke < 0 || Ke > 1 || VPLLfrz < 0
    error('ibr:regfm_b1_vsg_model:badParam', ...
        'PQFlag/ESFlag must be binary, 0<=Ke<=1, and VPLLfrz>=0.');
end
delta_arg = XL*ImaxSS;
if abs(delta_arg) > 1
    error('ibr:regfm_b1_vsg_model:deltaMaxDomain', ...
        'Eq.12 requires |XL*ImaxSS|<=1 (got %.15g).',delta_arg);
end
delta_max = asin(delta_arg);

% Boundary mapping: system base -> inverter base (NO double conversion).
kappa = Sbase / Mbase;
P_ref_inv = kappa * P_ref_pu;   % inverter base (REGFM_B1 Eq.1 semantics)

% --- Initial state (from PF warm-start; V_bus = V0 = V0_mag*exp(j*theta0)) --
% Constructor warm-start: active-power filter starts at the scheduled dispatch;
% Q/current filters start at zero and are replaced by equilibrium_initialize
% when the reduced network initializer supplies terminal P/Q. With the
% corrected Z_sys = kappa*(Re+jXL), no old-Z base mismatch is retained.
omega_m0   = 0.0;
delta_IT0  = 0.0;               % PLL-relative VSM angle; refined by initializer
x_washout0 = 0.0;
x_Eint0    = 0.0;
delta_PLL0 = theta0;            % PLL locked to bus angle
x_PLL_int0 = 0.0;
Pinv_f0    = P_ref_inv;          % inverter-base active-power setpoint
Idinv_f0   = 0.0;               % refined by Newton from measured current
Qinv_f0    = 0.0;               % Qref=0 dispatch
Vinv_f0    = V0_mag;            % warm-start |V_bus|
Iqinv_f0   = 0.0;               % refined by Newton from measured current
delta_ITmax0 = delta_max;
delta_ITmin0 = ternary(ESFlag==1,-delta_max,0.0);
x0 = [omega_m0; delta_IT0; x_washout0; x_Eint0; delta_PLL0; x_PLL_int0; ...
      Pinv_f0; Idinv_f0; Qinv_f0; Vinv_f0; Iqinv_f0; ...
      delta_ITmax0; delta_ITmin0];
u0 = [P_ref_pu; V_ref_pu];

% --- Captured constants for closures ----------------------------------------
bp = bus_position;   % 1-based index into y for this device's bus

% --- Differential RHS f(t, x_dev, y, u_dev, event_context) -----------------
f = @(t, x_dev, y, u_dev, event_context) gfm_f( ...
    x_dev, y, u_dev, bp, omega0, H, D1, D2, wD, mp, mq, kpv, kiv, Re, XL, ...
    kpPLL, kiPLL, Tpf, TQf, TVf, TIf, kappa, ImaxSS, ImaxF, kf, kI, Ke, ...
    PQFlag, ESFlag, delta_max, VPLLfrz);

% --- current_injection(t, x_dev, y, u_dev, event_context): complex, INTO net
current_injection = @(t, x_dev, y, u_dev, event_context) ...
    gfm_current_injection_g2( ...
    x_dev, y, u_dev, bp, kpv, kiv, mq, Re, XL, kappa, ImaxSS, ImaxF, ...
    kf, PQFlag, ESFlag);

% --- electrical_power(t, x_dev, y, u_dev, event_context): Pe (pu, system base)
electrical_power = @(t, x_dev, y, u_dev, event_context) gfm_pe_g2( ...
    x_dev, y, u_dev, bp, kpv, kiv, mq, Re, XL, kappa, ImaxSS, ImaxF, ...
    kf, PQFlag, ESFlag);

% --- reconstruct(t, x_dev, y, u_dev, event_context): struct -----------------
reconstruct = @(t, x_dev, y, u_dev, event_context) gfm_reconstruct_g2( ...
    x_dev, y, u_dev, bp, omega0, H, D1, D2, wD, mp, mq, kpv, kiv, Re, XL, ...
    kpPLL, kiPLL, Tpf, TQf, TVf, TIf, kappa, Mbase, Sbase, ImaxSS, ImaxF, ...
    kf, kI, Ke, PQFlag, ESFlag, delta_max, VPLLfrz);

% --- Optional exact device-equilibrium initializer -------------------------
% PROJECT_DERIVED inversion of REGFM_B1 Eqs.1-9, 13 and Figs.2-4. Q_terminal
% is an initialization estimate for the network-solved GFM reactive output;
% it is not a new Q-reference input. Network KCL remains composite-owned.
equilibrium_initialize = @(V_bus, P_terminal_pu, Q_terminal_pu, event_context) ...
    gfm_equilibrium_initialize(V_bus, P_terminal_pu, Q_terminal_pu, ...
        event_context, V_ref_pu, kappa, Re, XL, mq, kpv, kiv, ImaxSS, ImaxF, ...
        kf, PQFlag, ESFlag, delta_max, VPLLfrz);
% Runtime mode transfer is not a stationary-equilibrium solve: terminal
% voltage may differ from V_ref immediately after a disturbance. It uses the
% same sourced inversion but does not impose the stationary |V|=V_ref row.
transfer_initialize = @(V_bus, P_terminal_pu, Q_terminal_pu, event_context) ...
    gfm_transfer_initialize(V_bus, P_terminal_pu, Q_terminal_pu, ...
        event_context, V_ref_pu, kappa, Re, XL, mq, kpv, kiv, ImaxSS, ImaxF, ...
        kf, PQFlag, ESFlag, delta_max, VPLLfrz);
equilibrium_constraint_specs = @(x_dev,y,u_dev,event_context) ...
    g2_constraint_specs(x_dev,y,u_dev,event_context,bp,omega0,V_ref_pu, ...
        mq,kpv,kiv,XL,ImaxSS,kf,kI,Ke,PQFlag,ESFlag,delta_max);

% --- Assemble device struct (composite_dae ABI, R3 Revision 2) --------------
dev = struct();
dev.name = char(device_id);
dev.device_id = char(device_id);
dev.bus_id = bus_id;
dev.bus_position = bus_position;
dev.bus_ids = bus_ids(:).';
dev.device_type = 'ibr_gfm';
dev.mode = 'GFM';
dev.nx = 13;
dev.nu = 2;
dev.state_names = {'omega_m','delta_IT','x_washout','x_Eint','delta_PLL', ...
    'x_PLL_int','Pinv_f','Idinv_f','Qinv_f','Vinv_f','Iqinv_f', ...
    'delta_ITmax','delta_ITmin'};
dev.input_names = {'P_ref','V_ref'};
dev.x0 = x0;
dev.u0 = u0;
dev.f = f;
dev.current_injection = current_injection;
dev.electrical_power = electrical_power;
dev.reconstruct = reconstruct;
dev.equilibrium_initialize = equilibrium_initialize;
dev.transfer_initialize = transfer_initialize;
dev.equilibrium_constraint_specs = equilibrium_constraint_specs;
dev.active_state_indices = 1:13;
if ESFlag == 0
    dev.active_state_indices = 1:12;
end
% F4: parameter classifications — frozen defaults keep their original label;
% any overridden parameter is reclassified DIAGNOSTIC_ONLY. Mbase is a
% CASE_DEFINED nameplate proxy (not a REGFM_B1 Table 1 value), so it keeps
% CASE_DEFINED unless overridden.
cls = @(nm) ternary(overridden.(nm), 'DIAGNOSTIC_ONLY', 'SOURCE_VERBATIM');
cls_Mbase = ternary(overridden.Mbase, 'DIAGNOSTIC_ONLY', 'CASE_DEFINED');
dev.provenance = struct( ...
    'model','gfm_regfm_b1_phase_g2', ...
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
    'angle_contract','delta_VSM=delta_PLL+delta_IT (SOURCE_TRANSFORMED)', ...
    'g2_antiwindup','conditional integration (PROJECT_DERIVED)', ...
    'readiness','SOURCE_IMPLEMENTED_PENDING_INTEGRATION_GATES', ...
    'phase_g1_status','IMPLEMENTED_STRUCTURAL_ONLY', ...
    'phase_g2_status','SOURCE_IMPLEMENTED_PENDING_INTEGRATION_GATES');
end

% =========================================================================
function x_eq = gfm_equilibrium_initialize(V_bus, P_terminal_pu, ...
    Q_terminal_pu, event_context, V_ref, kappa, Re, XL, mq, kpv, kiv, ...
    ImaxSS, ImaxF, kf, PQFlag, ESFlag, delta_max, VPLLfrz) %#ok<INUSD>
%GFM_EQUILIBRIUM_INITIALIZE  Exact regular REGFM_B1 device equilibrium.
%   Terminal P/Q are system-base injections under S=V*conj(I), positive INTO
%   the network. The returned state is device-consistent only; the caller must
%   still solve/check the composite network KCL.
x_eq = gfm_state_initialize(V_bus,P_terminal_pu,Q_terminal_pu,event_context, ...
    V_ref,kappa,Re,XL,mq,kpv,kiv,ImaxSS,ImaxF,kf,PQFlag,ESFlag, ...
    delta_max,VPLLfrz,true);
end

function x_eq = gfm_transfer_initialize(V_bus, P_terminal_pu, ...
    Q_terminal_pu, event_context, V_ref, kappa, Re, XL, mq, kpv, kiv, ...
    ImaxSS, ImaxF, kf, PQFlag, ESFlag, delta_max, VPLLfrz)
%GFM_TRANSFER_INITIALIZE Physical left-limit state map for GFL->GFM.
% Unlike a stationary root, a runtime transfer permits |V_bus|~=V_ref. The
% voltage-integrator state is reconstructed so EVSM equals |V+Z_sys*I|,
% preserving terminal current while all source current/angle limits remain
% fail-closed.
x_eq = gfm_state_initialize(V_bus,P_terminal_pu,Q_terminal_pu,event_context, ...
    V_ref,kappa,Re,XL,mq,kpv,kiv,ImaxSS,ImaxF,kf,PQFlag,ESFlag, ...
    delta_max,VPLLfrz,false);
end

function x_eq = gfm_state_initialize(V_bus, P_terminal_pu, ...
    Q_terminal_pu, event_context, V_ref, kappa, Re, XL, mq, kpv, kiv, ...
    ImaxSS, ImaxF, kf, PQFlag, ESFlag, delta_max, VPLLfrz,require_stationary_voltage) %#ok<INUSD>
%GFM_STATE_INITIALIZE Shared sourced inversion for equilibrium and transfer.
if ~isscalar(V_bus) || ~isfinite(V_bus) || abs(V_bus) <= 0
    error('ibr:regfm_b1_vsg_model:equilibriumBadVoltage', ...
        'Equilibrium V_bus must be a finite nonzero scalar phasor.');
end
if ~isscalar(P_terminal_pu) || ~isscalar(Q_terminal_pu) || ...
        ~isreal(P_terminal_pu) || ~isreal(Q_terminal_pu) || ...
        ~isfinite(P_terminal_pu) || ~isfinite(Q_terminal_pu)
    error('ibr:regfm_b1_vsg_model:equilibriumBadPower', ...
        'Equilibrium terminal P/Q must be finite real scalars on system base.');
end

Vmag = abs(V_bus);
if Vmag < VPLLfrz
    error('ibr:regfm_b1_vsg_model:equilibriumPLLFreezeNonunique', ...
        ['|V_bus|=%.15g is below VPLLfrz=%.15g; the sourced PLL freeze ' ...
         'makes delta_PLL/x_PLL_int non-unique in a regular equilibrium.'], ...
        Vmag, VPLLfrz);
end
vscale = max([1.0, Vmag, abs(V_ref)]);
% The reduced network initializer is solved by finite-difference Newton and
% then handed to the full coupled Newton.  sqrt(eps) is the standard
% perturbation-scale consistency gate; a machine-epsilon-only gate rejects a
% mathematically converged warm start before the full residual can refine it.
vtol = sqrt(eps)*vscale;   % NUMERICAL_METHOD, not an acceptance relaxation
if require_stationary_voltage && abs(Vmag - V_ref) > vtol
    error('ibr:regfm_b1_vsg_model:equilibriumVoltageReferenceMismatch', ...
        ['Exact equilibrium at the supplied V_bus requires |V_bus|=V_ref; ' ...
         '|V_bus|=%.15g, V_ref=%.15g.'], Vmag, V_ref);
end

S_terminal = complex(P_terminal_pu, Q_terminal_pu);
I_terminal_sys = conj(S_terminal / V_bus);
ImaxF_sys = ImaxF / kappa;
Iabs = abs(I_terminal_sys);
itol = 64*eps(max(1.0, ImaxF_sys));
if Iabs > ImaxF_sys + itol
    error('ibr:regfm_b1_vsg_model:equilibriumCurrentLimit', ...
        ['Requested |I|=%.15g exceeds ImaxF_sys=%.15g; algebraic clamping ' ...
         'would change the requested terminal P/Q.'], Iabs, ImaxF_sys);
end
if abs(Iabs - ImaxF_sys) <= itol
    error('ibr:regfm_b1_vsg_model:equilibriumClampBoundary', ...
        ['Requested |I|=%.15g lies on the nondifferentiable Eq.13 clamp ' ...
         'boundary ImaxF_sys=%.15g.'], Iabs, ImaxF_sys);
end

Z_sys = kappa * complex(Re, XL);
E_terminal = V_bus + Z_sys*I_terminal_sys;
if ~isfinite(E_terminal) || abs(E_terminal) <= 64*eps(max(1.0, Vmag))
    error('ibr:regfm_b1_vsg_model:equilibriumInternalVoltage', ...
        'The reconstructed internal-voltage phasor is non-finite or angle-degenerate.');
end

delta_PLL = angle(V_bus);              % positive-d-axis PLL lock
I_dq_sys = I_terminal_sys*exp(-1i*delta_PLL);
P_f = kappa*P_terminal_pu;
Q_f = kappa*Q_terminal_pu;
V_f = Vmag;
EVSM = abs(E_terminal);
[IdmaxSS,IqmaxSS] = pq_limits(ImaxSS,kf,PQFlag, ...
    kappa*real(I_dq_sys),kappa*imag(I_dq_sys));
[Emin_iq_lim,Emax_iq_lim] = voltage_limits(V_f,kappa*real(I_dq_sys), ...
    IqmaxSS,XL);
elim_tol = 64*eps(max([1,abs(EVSM),abs(Emin_iq_lim),abs(Emax_iq_lim)]));
if EVSM < Emin_iq_lim-elim_tol || EVSM > Emax_iq_lim+elim_tol
    error('ibr:regfm_b1_vsg_model:equilibriumSteadyCurrentLimit', ...
        ['Requested internal voltage %.15g is outside the sourced G2 ' ...
         'range [%.15g,%.15g] (IdmaxSS=%.15g,IqmaxSS=%.15g).'], ...
        EVSM,Emin_iq_lim,Emax_iq_lim,IdmaxSS,IqmaxSS);
end
if kiv <= 0
    error('ibr:regfm_b1_vsg_model:equilibriumVoltageIntegrator', ...
        'Exact GFM equilibrium inversion requires finite kiv>0.');
end
x_Eint = (EVSM - V_ref + mq*Q_f - kpv*(V_ref - V_f)) / kiv;
if ~isfinite(x_Eint)
    error('ibr:regfm_b1_vsg_model:equilibriumNonfinite', ...
        'The reconstructed voltage-PI integrator state is non-finite.');
end

delta_IT = wrap_pi(angle(E_terminal)-delta_PLL);
used_lb = ternary(ESFlag==1,-delta_max,0.0);
if delta_IT < used_lb-elim_tol || delta_IT > delta_max+elim_tol
    error('ibr:regfm_b1_vsg_model:equilibriumAngleLimit', ...
        'delta_IT=%.15g is outside [%.15g,%.15g].',delta_IT,used_lb,delta_max);
end
x_eq = [0.0; delta_IT; 0.0; x_Eint; delta_PLL; 0.0; ...
        P_f; kappa*real(I_dq_sys); Q_f; V_f; kappa*imag(I_dq_sys); ...
        delta_max; ternary(ESFlag==1,-delta_max,0.0)];
if any(~isfinite(x_eq))
    error('ibr:regfm_b1_vsg_model:equilibriumNonfinite', ...
        'The reconstructed GFM equilibrium state contains non-finite values.');
end
end

% =========================================================================
function [I_out_sys, I_unc_sys, I_limited] = limited_current( ...
    EVSM, delta_VSM, V_bus, Re, XL, kappa, ImaxF)
%LIMITED_CURRENT  Shared Eq.13 clamp (Phase-G-1). Called by gfm_f, current_injection, pe, reconstruct.
%   REGFM_B1 Eq.13, Fig.7. ImaxF on inverter base, converted to system base.
%   Source: REGFM_B1 NREL/TP-5D00-90260 Eq.13, Fig.7, Table 1.
%   Fails closed on non-finite inputs (Phase-G-1 contract: no silent NaN).
if ~isfinite(EVSM) || ~isfinite(delta_VSM) || ~isfinite(V_bus)
    error('ibr:regfm_b1_vsg_model:nonfiniteBus', ...
        'Non-finite input to limited_current: EVSM=%.6g, delta_VSM=%.6g, V_bus=%.6g%+.6gj.', ...
        EVSM, delta_VSM, real(V_bus), imag(V_bus));
end
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
    Re, XL, kpPLL, kiPLL, Tpf, TQf, TVf, TIf, kappa, ImaxSS, ImaxF, ...
    kf, kI, Ke, PQFlag, ESFlag, delta_max, VPLLfrz)
%GFM_F  REGFM_B1 G2 RHS (13 states), including conditional anti-windup.
omega_m    = x_dev(1);
delta_IT   = x_dev(2);
x_washout  = x_dev(3);
x_Eint     = x_dev(4);
delta_PLL  = x_dev(5);
x_PLL_int  = x_dev(6);
Pinv_f     = x_dev(7);
Idinv_f    = x_dev(8);
Qinv_f     = x_dev(9);
Vinv_f     = x_dev(10);
Iqinv_f    = x_dev(11);
delta_ITmax = x_dev(12);
delta_ITmin = x_dev(13);
[P_ref_sys, V_ref] = refs_from_u(u_dev);
P_ref_inv = kappa * P_ref_sys;   % boundary mapping (no double conversion)

% Network-frame bus voltage.
V_bus = complex(y(2*bp-1), y(2*bp));
[~,IqmaxSS] = pq_limits(ImaxSS,kf,PQFlag,Idinv_f,Iqinv_f);
[Emin_iq_lim,Emax_iq_lim] = voltage_limits(Vinv_f,Idinv_f,IqmaxSS,XL);
EVSM_raw = V_ref - mq*Qinv_f + kpv*(V_ref - Vinv_f) + kiv*x_Eint;
EVSM = clamp_value(EVSM_raw,Emin_iq_lim,Emax_iq_lim);
used_lb = ternary(ESFlag==1,delta_ITmin,0.0);
delta_IT_used = clamp_value(delta_IT,used_lb,delta_ITmax);
delta_VSM = delta_PLL+delta_IT_used;

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
d_delta_IT_raw = omega0*omega_m;
d_delta_IT = conditional_hold(delta_IT,d_delta_IT_raw,used_lb,delta_ITmax);

% Voltage PI (Fig.3).
d_x_Eint_raw = V_ref - Vinv_f;
d_x_Eint = d_x_Eint_raw;
if (EVSM_raw >= Emax_iq_lim && d_x_Eint_raw > 0) || ...
        (EVSM_raw <= Emin_iq_lim && d_x_Eint_raw < 0)
    d_x_Eint = 0;
end

% Fig.6 dynamic upper/lower bounds and PROJECT_DERIVED conditional hold.
[IdmaxSS,~] = pq_limits(ImaxSS,kf,PQFlag,Idinv_f,Iqinv_f);
d_delta_ITmax_raw = kI*(IdmaxSS-Idinv_f);
d_delta_ITmax = conditional_hold(delta_ITmax,d_delta_ITmax_raw,0,delta_max);
if ESFlag == 1
    d_delta_ITmin_raw = kI*((-Ke*IdmaxSS)-Idinv_f);
    d_delta_ITmin = conditional_hold(delta_ITmin,d_delta_ITmin_raw,-delta_max,0);
else
    d_delta_ITmin = 0;
end

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

dx = [d_omega_m; d_delta_IT; d_x_washout; d_x_Eint; d_delta_PLL; d_x_PLL_int; ...
      d_Pinv_f; d_Idinv_f; d_Qinv_f; d_Vinv_f; d_Iqinv_f; ...
      d_delta_ITmax; d_delta_ITmin];
end

% =========================================================================
function I = gfm_current_injection_g2(x_dev, y, u_dev, bp, kpv, kiv, mq, Re, XL, ...
    kappa, ImaxSS, ImaxF, kf, PQFlag, ESFlag)
%GFM_CURRENT_INJECTION_G2  G2 voltage/angle limits followed by Eq.13 clamp.
delta_IT   = x_dev(2);
x_Eint    = x_dev(4);
delta_PLL = x_dev(5);
Qinv_f    = x_dev(9);
Vinv_f    = x_dev(10);
Idinv_f   = x_dev(8);
Iqinv_f   = x_dev(11);
delta_ITmax = x_dev(12);
delta_ITmin = x_dev(13);
[~, V_ref] = refs_from_u(u_dev);
V_bus = complex(y(2*bp-1), y(2*bp));
[~,IqmaxSS] = pq_limits(ImaxSS,kf,PQFlag,Idinv_f,Iqinv_f);
[Emin_iq_lim,Emax_iq_lim] = voltage_limits(Vinv_f,Idinv_f,IqmaxSS,XL);
EVSM_raw = V_ref - mq*Qinv_f + kpv*(V_ref - Vinv_f) + kiv*x_Eint;
EVSM = clamp_value(EVSM_raw,Emin_iq_lim,Emax_iq_lim);
used_lb = ternary(ESFlag==1,delta_ITmin,0.0);
delta_VSM = delta_PLL+clamp_value(delta_IT,used_lb,delta_ITmax);
[I, ~, ~] = limited_current(EVSM, delta_VSM, V_bus, Re, XL, kappa, ImaxF);
end

% =========================================================================
function Pe = gfm_pe_g2(x_dev, y, u_dev, bp, kpv, kiv, mq, Re, XL, kappa, ...
    ImaxSS, ImaxF, kf, PQFlag, ESFlag)
%GFM_PE_G2  Electrical power from the exact shared G2 current path.
I = gfm_current_injection_g2(x_dev,y,u_dev,bp,kpv,kiv,mq,Re,XL,kappa, ...
    ImaxSS,ImaxF,kf,PQFlag,ESFlag);
V_bus = complex(y(2*bp-1), y(2*bp));
Pe = real(V_bus * conj(I));
end

% =========================================================================
function out = gfm_reconstruct_g2(x_dev, y, u_dev, bp, omega0, H, D1, D2, wD, mp, mq, ...
    kpv, kiv, Re, XL, kpPLL, kiPLL, Tpf, TQf, TVf, TIf, kappa, Mbase, Sbase, ...
    ImaxSS, ImaxF, kf, kI, Ke, PQFlag, ESFlag, delta_max, VPLLfrz)
%GFM_RECONSTRUCT_G2  Device outputs with sourced G2 limiter metadata.
omega_m    = x_dev(1);
delta_IT   = x_dev(2);
x_washout  = x_dev(3);
x_Eint     = x_dev(4);
delta_PLL  = x_dev(5);
x_PLL_int  = x_dev(6);
Pinv_f     = x_dev(7);
Idinv_f    = x_dev(8);
Qinv_f     = x_dev(9);
Vinv_f     = x_dev(10);
Iqinv_f    = x_dev(11);
delta_ITmax = x_dev(12);
delta_ITmin = x_dev(13);
[P_ref_sys, V_ref] = refs_from_u(u_dev);
V_bus = complex(y(2*bp-1), y(2*bp));
[IdmaxSS,IqmaxSS] = pq_limits(ImaxSS,kf,PQFlag,Idinv_f,Iqinv_f);
[Emin_iq_lim,Emax_iq_lim] = voltage_limits(Vinv_f,Idinv_f,IqmaxSS,XL);
EVSM_raw = V_ref - mq*Qinv_f + kpv*(V_ref - Vinv_f) + kiv*x_Eint;
EVSM = clamp_value(EVSM_raw,Emin_iq_lim,Emax_iq_lim);
used_delta_ITmin = ternary(ESFlag==1,delta_ITmin,0.0);
delta_IT_used = clamp_value(delta_IT,used_delta_ITmin,delta_ITmax);
delta_VSM = delta_PLL+delta_IT_used;
[I_out, I_unc, I_limited] = limited_current(EVSM, delta_VSM, V_bus, Re, XL, kappa, ImaxF);
ImaxF_sys = ImaxF / kappa;
S = V_bus * conj(I_out);
PLL_frozen = abs(V_bus) < VPLLfrz;
out = struct( ...
    'omega_m', omega_m, 'delta_IT', delta_IT, 'delta_IT_used',delta_IT_used, ...
    'delta_VSM', delta_VSM, 'x_washout', x_washout, ...
    'x_Eint', x_Eint, 'delta_PLL', delta_PLL, 'x_PLL_int', x_PLL_int, ...
    'Pinv_f', Pinv_f, 'Idinv_f', Idinv_f, 'Qinv_f', Qinv_f, ...
    'Vinv_f', Vinv_f, 'Iqinv_f', Iqinv_f, ...
    'EVSM', EVSM, 'I_gfm', I_out, 'Vbus', abs(V_bus), ...
    'Pe', real(S), 'Qe', imag(S), ...
    'kappa', kappa, 'Mbase', Mbase, 'Sbase', Sbase, ...
    'H',H,'H_system',H/kappa,'frequency_deviation_pu',omega_m, ...
    'P_ref_inv', kappa*P_ref_sys, ...
    'ImaxF_inv', ImaxF, 'ImaxF_sys', ImaxF_sys, ...
    'I_unc_sys', I_unc, 'I_abs_unc', abs(I_unc), 'I_abs_out', abs(I_out), ...
    'I_limited', I_limited, 'VPLLfrz', VPLLfrz, 'PLL_frozen', PLL_frozen, ...
    'ImaxSS',ImaxSS,'kf',kf,'kI',kI,'Ke',Ke,'PQFlag',PQFlag,'ESFlag',ESFlag, ...
    'IdmaxSS',IdmaxSS,'IqmaxSS',IqmaxSS, ...
    'Emin_iq_lim',Emin_iq_lim,'Emax_iq_lim',Emax_iq_lim, ...
    'EVSM_raw',EVSM_raw,'EVSM_clamped',EVSM, ...
    'delta_max',delta_max,'delta_ITmax',delta_ITmax, ...
    'delta_ITmin',delta_ITmin,'used_delta_ITmin',used_delta_ITmin, ...
    'x_Eint_saturated',EVSM_raw<Emin_iq_lim || EVSM_raw>Emax_iq_lim);
end

% =========================================================================
function specs = g2_constraint_specs(~,~,~,~,bp,omega0,V_ref_default,mq,kpv,kiv, ...
    XL,ImaxSS,kf,kI,Ke,PQFlag,ESFlag,delta_max)
%G2_CONSTRAINT_SPECS  Equality/complementarity rows for equilibrium Newton.
% Classification is evaluated only between Newton solves by the generic
% active-bound layer.  residual_fn is evaluated with the locked regime.

smax = bound_spec(12,'delta_ITmax', ...
    @(x,y,u,ec) 0.0, @(x,y,u,ec) delta_max, ...
    @(x,y,u,ec) kI*(first_pq_limit(x,ImaxSS,kf,PQFlag)-x(8)));

sdelta = bound_spec(2,'delta_IT', ...
    @(x,y,u,ec) ternary(ESFlag==1,x(13),0.0), ...
    @(x,y,u,ec) x(12), ...
    @(x,y,u,ec) omega0*x(1));

svolt.local_idx = 4;
svolt.classify_fn = @(x,y,u,ec) classify_voltage_constraint( ...
    x,y,u,bp,V_ref_default,mq,kpv,kiv,XL,ImaxSS,kf,PQFlag);
svolt.residual_fn = @(x,y,u,ec,reg) residual_voltage_constraint( ...
    x,y,u,reg,bp,V_ref_default,mq,kpv,kiv,XL,ImaxSS,kf,PQFlag);
svolt.raw_dot_fn = @(x,y,u,ec) voltage_raw_dot(x,u,V_ref_default);
svolt.admissible_fn = @(x,y,u,ec,reg) admissible_voltage_constraint( ...
    x,y,u,reg,bp,V_ref_default,mq,kpv,kiv,XL,ImaxSS,kf,PQFlag);
svolt.description = 'x_Eint / EVSM G2 voltage limiter';

if ESFlag == 1
    smin = bound_spec(13,'delta_ITmin', ...
        @(x,y,u,ec) -delta_max, @(x,y,u,ec) 0.0, ...
        @(x,y,u,ec) kI*((-Ke*first_pq_limit(x,ImaxSS,kf,PQFlag))-x(8)));
    specs = [smax;smin;sdelta;svolt];
else
    specs = [smax;sdelta;svolt];
end
end

function spec = bound_spec(local_idx,label,lo_fn,hi_fn,raw_fn)
spec.local_idx = local_idx;
spec.classify_fn = @(x,y,u,ec) classify_bound_value( ...
    x(local_idx),lo_fn(x,y,u,ec),hi_fn(x,y,u,ec),raw_fn(x,y,u,ec));
spec.residual_fn = @(x,y,u,ec,reg) residual_bound_value( ...
    x(local_idx),lo_fn(x,y,u,ec),hi_fn(x,y,u,ec),raw_fn(x,y,u,ec),reg);
spec.raw_dot_fn = @(x,y,u,ec) raw_fn(x,y,u,ec);
spec.admissible_fn = @(x,y,u,ec,reg) admissible_bound_value( ...
    x(local_idx),lo_fn(x,y,u,ec),hi_fn(x,y,u,ec),raw_fn(x,y,u,ec),reg);
spec.description = label;
end

function regime = classify_bound_value(x,lo,hi,raw)
btol=1e-8; stol=1e-6;
if ~all(isfinite([x,lo,hi,raw])) || lo>hi
    error('ibr:regfm_b1_vsg_model:nonfiniteActiveBound', ...
        'Invalid G2 active-bound value.');
elseif x>hi+btol
    regime='upper';
elseif x<lo-btol
    regime='lower';
elseif x>=hi-btol && raw>=-stol
    regime='upper';
elseif x<=lo+btol && raw<=stol
    regime='lower';
else
    regime='interior';
end
end

function r = residual_bound_value(x,lo,hi,raw,regime)
switch regime
    case 'upper', r=x-hi;
    case 'lower', r=x-lo;
    case 'interior', r=raw;
    otherwise
        error('ibr:regfm_b1_vsg_model:badActiveBoundRegime', ...
            'Unknown active-bound regime %s.',regime);
end
end

function ok = admissible_bound_value(x,lo,hi,raw,regime)
switch regime
    case 'upper', ok=raw>=-1e-6 && abs(x-hi)<=1e-7;
    case 'lower', ok=raw<=1e-6 && abs(x-lo)<=1e-7;
    case 'interior', ok=x>lo+1e-8 && x<hi-1e-8 && abs(raw)<=1e-6;
    otherwise, ok=false;
end
end

function regime = classify_voltage_constraint(x,~,u,bp,Vref0,mq,kpv,kiv,XL,ImaxSS,kf,PQFlag)
[EVraw,Emin,Emax,raw] = voltage_constraint_values(x,u,bp,Vref0,mq,kpv,kiv,XL,ImaxSS,kf,PQFlag);
regime=classify_bound_value(EVraw,Emin,Emax,kiv*raw);
end

function r = residual_voltage_constraint(x,~,u,reg,bp,Vref0,mq,kpv,kiv,XL,ImaxSS,kf,PQFlag)
[EVraw,Emin,Emax,raw] = voltage_constraint_values(x,u,bp,Vref0,mq,kpv,kiv,XL,ImaxSS,kf,PQFlag);
r=residual_bound_value(EVraw,Emin,Emax,raw,reg);
end

function ok = admissible_voltage_constraint(x,~,u,reg,bp,Vref0,mq,kpv,kiv,XL,ImaxSS,kf,PQFlag)
[EVraw,Emin,Emax,raw] = voltage_constraint_values(x,u,bp,Vref0,mq,kpv,kiv,XL,ImaxSS,kf,PQFlag);
ok=admissible_bound_value(EVraw,Emin,Emax,raw,reg);
end

function [EVraw,Emin,Emax,raw] = voltage_constraint_values(x,u,~,Vref0,mq,kpv,kiv,XL,ImaxSS,kf,PQFlag)
if isempty(u), Vref=Vref0; else, [~,Vref]=refs_from_u(u); end
[~,Iqmax] = pq_limits(ImaxSS,kf,PQFlag,x(8),x(11));
[Emin,Emax] = voltage_limits(x(10),x(8),Iqmax,XL);
EVraw=Vref-mq*x(9)+kpv*(Vref-x(10))+kiv*x(4);
raw=Vref-x(10);
end

function raw = voltage_raw_dot(x,u,Vref0)
if isempty(u), Vref=Vref0; else, [~,Vref]=refs_from_u(u); end
raw=Vref-x(10);
end

function Idmax = first_pq_limit(x,ImaxSS,kf,PQFlag)
[Idmax,~]=pq_limits(ImaxSS,kf,PQFlag,x(8),x(11));
end

function [IdmaxSS,IqmaxSS] = pq_limits(ImaxSS,kf,PQFlag,Idinv_f,Iqinv_f)
if PQFlag==1
    IdmaxSS=kf*ImaxSS;
    IqmaxSS=sqrt(max(ImaxSS^2-Idinv_f^2,0));
else
    IqmaxSS=kf*ImaxSS;
    IdmaxSS=sqrt(max(ImaxSS^2-Iqinv_f^2,0));
end
end

function [Emin,Emax] = voltage_limits(Vinv_f,Idinv_f,IqmaxSS,XL)
Emin=sqrt((Vinv_f-IqmaxSS*XL)^2+(Idinv_f*XL)^2);
Emax=sqrt((Vinv_f+IqmaxSS*XL)^2+(Idinv_f*XL)^2);
if Emin>Emax
    tmp=Emin; Emin=Emax; Emax=tmp;
end
end

function dx = conditional_hold(x,raw,lo,hi)
if (x>=hi && raw>0) || (x<=lo && raw<0)
    dx=0;
else
    dx=raw;
end
end

function value = clamp_value(value,lo,hi)
value=min(max(value,lo),hi);
end

function a = wrap_pi(a)
a=mod(a+pi,2*pi)-pi;
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
