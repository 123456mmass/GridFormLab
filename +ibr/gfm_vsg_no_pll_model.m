function dev = gfm_vsg_no_pll_model(device_id, bus_id, bus_position, ...
    bus_ids, V0, params, P_ref_pu, V_ref_pu)
%GFM_VSG_NO_PLL_MODEL  4-state positive-sequence RMS grid-forming VSG, no PLL.
%
%   dev = gfm_vsg_no_pll_model(DEVICE_ID, BUS_ID, BUS_POSITION, BUS_IDS, V0,
%       PARAMS, P_REF_PU, V_REF_PU) returns a device struct conforming to the
%       stability.composite_dae ABI (R3 Revision 2): f, current_injection,
%       electrical_power, reconstruct, equilibrium_initialize, state_names,
%       input_names, nx, nu, active_state_indices, provenance.
%
%   This is an opt-in PROJECT_DERIVED_SOURCE_MAPPED composite. The virtual-
%   rotor swing/angle equations are SOURCE_DEFINED from Sakimoto 2015
%   (Eq.4/5) and Avila-Martinez 2025 (VSM-noPLL 2H form, Eq.9/10). The P/Q
%   measurement filters and the algebraic Q-V droop voltage law are
%   SOURCE_DEFINED from PNNL-35110 REGFM_A1 (Eq.4/5, Fig.3(b) VFlag=0).
%   The cross-source assembly is classified PROJECT_DERIVED_SOURCE_MAPPED.
%
%   HARD NO-PLL CONTRACT. The model contains NONE of: delta_PLL, xi_PLL /
%   x_PLL_int, PLL PI gains, PLL freeze/reset, PLL-estimated frequency, a
%   runtime angle obtained by tracking angle(V), or any state relabelled to
%   hide a PLL state. The runtime rotor angle is obtained ONLY from
%       dot(delta_vsm) = omega_base * delta_omega_vsm.
%   Using angle(V0) during equilibrium initialization is allowed (Sakimoto
%   Sec.5.1 startup procedure); using terminal-voltage angle as a runtime
%   PLL substitute is not allowed.
%
%   State order (4, fixed):
%     1 delta_vsm        virtual-rotor angle                          [rad]
%     2 delta_omega_vsm  virtual-rotor speed deviation                [pu]
%     3 P_f              filtered active power (PNNL Eq.4)            [pu inv]
%     4 Q_f              filtered reactive power (PNNL Eq.5)          [pu inv]
%
%   Inputs (nu=2): u = [P_ref; V_ref] (pu, system base).
%
%   Per-unit base contract (same as GFL-RMS10 + REGFM_B1):
%     kappa = Sbase/Mbase; P_ref_inv = kappa*P_ref_sys; I_sys = I_inv/kappa.
%     Device-internal states run on inverter base; current_injection and
%     electrical_power return system-base quantities. No double conversion.
%
%   Governing equations (frozen; see GFM_NO_PLL_SOURCE_CONTRACT.md):
%     Boundary: kappa = Sbase/Mbase; P_ref_inv = kappa*P_ref_sys.
%     V_bus = complex(y(2*bp-1), y(2*bp))   (network common xy frame)
%     Virtual-rotor swing (Avila-Martinez 2025 Eq.9/10; Sakimoto Eq.4):
%       dot(delta_omega_vsm) = (P_ref_inv - P_f - D_GFM*delta_omega_vsm)/(2*H_GFM)
%       dot(delta_vsm)       = omega_base * delta_omega_vsm     (NO PLL)
%     P/Q measurement filters (PNNL Eq.4/5):
%       T_P*dot(P_f) = kappa*P_meas - P_f
%       T_Q*dot(Q_f) = kappa*Q_meas - Q_f
%     Algebraic Q-V droop voltage law (PNNL Fig.3(b), VFlag=0):
%       E_vsm = V_ref - m_q*(Q_f - Q_ref),  Q_ref = 0 (QVFlag=1 init)
%     Output stage (Thevenin behind pure jX_L; PNNL Eqs.8-9, Du Eqs.14-15):
%       E_internal = E_vsm * exp(1i*delta_vsm)
%       I_inv = (E_internal - V_bus)/(1i*X_L)        (inverter base)
%       I_sys = I_inv / kappa                          (system base)
%     Measured power (generator convention S = V*conj(I), SYSTEM base):
%       P_meas = Re(V_bus*conj(I_sys));  Q_meas = Im(V_bus*conj(I_sys))
%
%   No dq transform is used in the RHS; the Thevenin current is evaluated
%   directly in the network xy frame. dq components are exposed only as
%   diagnostic reconstruction.
%
%   OUT-OF-SCOPE future model extensions (NOT pending functionality):
%     - AVR / dynamic voltage PI (Sakimoto K_AI integral; PNNL VFlag=1 with
%       k_pv, k_iv, xi_E, V_f from Eq.6). This model uses VFlag=0 algebraic
%       Q-V droop only.
%     - Current limiter / anti-windup / fault LVRT (NOT_READY).
%     - Sakimoto governor/turbine and damper lead.
%
%   Classification: see docs/project/GFM_NO_PLL_SOURCE_CONTRACT.md.
%   4 of 4 states sourced; cross-source assembly PROJECT_DERIVED_SOURCE_MAPPED.
%
%   STATUS: SOURCE_IMPLEMENTED_PENDING_SMIB_GATES.
%
%   Sources: Sakimoto 2015 (docs/text/gfm_no_pll/sakimoto-2015-vsg-without-pll.pdf);
%            PNNL-35110 REGFM_A1 (docs/text/gfm_no_pll/pnnl-35110-regfm-a1.pdf);
%            Du 2024 (docs/text/gfm_no_pll/du-2024-positive-sequence-gfm.pdf);
%            Avila-Martinez 2025 (docs/text/gfm_no_pll/avila-martinez-2025-self-synchronisation-gfm.pdf).

arguments
    device_id (1,1) string
    bus_id (1,1) double
    bus_position (1,1) double
    bus_ids (1,:) double
    V0 (1,1) {mustBeFinite}
    params struct
    P_ref_pu (1,1) double
    V_ref_pu (1,1) double
end

validate_bus_mapping(bus_id, bus_position, bus_ids);
if ~isfinite(V0) || abs(V0) <= 0
    error('ibr:gfm_vsg_no_pll_model:badV0', ...
        'V0 must be a finite nonzero bus-voltage phasor.');
end
if ~isfinite(P_ref_pu) || ~isfinite(V_ref_pu) || ...
        ~isreal(P_ref_pu) || ~isreal(V_ref_pu)
    error('ibr:gfm_vsg_no_pll_model:badRef', ...
        'P_ref_pu and V_ref_pu must be finite real system-base values.');
end

% --- Frozen numerical parameter profile (SOURCE_DEFINED_STUDY_VALUE) ---------
% Bases (CASE_DEFINED, overridable via params). The source-reproduction SMIB
% gate runs on Avila-Martinez 2025's 50 Hz / 100 MVA study base.
Sbase  = 100.0;   if isfield(params,'Sbase')  && ~isempty(params.Sbase),  Sbase  = params.Sbase;  end
Mbase  = 100.0;   if isfield(params,'Mbase')  && ~isempty(params.Mbase),  Mbase  = params.Mbase;  end
fbase  = 50.0;    if isfield(params,'fbase')  && ~isempty(params.fbase),  fbase  = params.fbase;  end
omega_base = 2*pi*fbase;

% GFM-no-PLL-specific overrides under params.gfm_no_pll (nested; never top-level,
% to avoid accidental REGFM_B1 / GFL-RMS10 override).
g = struct();
if isfield(params,'gfm_no_pll') && isstruct(params.gfm_no_pll)
    g = params.gfm_no_pll;
end

% Virtual-rotor swing (Avila-Martinez 2025 Table, Strategy 1 VSM-noPLL).
H_GFM  = 5.0;     if isfield(g,'H_GFM')  && ~isempty(g.H_GFM),  H_GFM  = g.H_GFM;  end   % [s]
D_GFM  = 20.0;    if isfield(g,'D_GFM')  && ~isempty(g.D_GFM),  D_GFM  = g.D_GFM;  end   % [pu]

% P/Q measurement filters (PNNL Eq.4/5).
T_P    = 0.01;    if isfield(g,'T_P')    && ~isempty(g.T_P),    T_P    = g.T_P;    end   % [s]
T_Q    = 0.01;    if isfield(g,'T_Q')    && ~isempty(g.T_Q),    T_Q    = g.T_Q;    end   % [s]

% Algebraic Q-V droop (PNNL Fig.3(b), VFlag=0).
m_q    = 0.05;    if isfield(g,'m_q')    && ~isempty(g.m_q),    m_q    = g.m_q;    end   % [pu]
Q_ref  = 0.0;     if isfield(g,'Q_ref')  && ~isempty(g.Q_ref),  Q_ref  = g.Q_ref;  end   % [pu inv]

% Output stage coupling reactance (PNNL Table 1).
X_L    = 0.15;    if isfield(g,'X_L')    && ~isempty(g.X_L),    X_L    = g.X_L;    end   % [pu inv]

% Equilibrium initialization tolerance for the voltage-law feasibility check.
eq_tol = 1e-9;    if isfield(g,'eq_tol') && ~isempty(g.eq_tol), eq_tol = g.eq_tol;  end

validate_params(Sbase,Mbase,fbase,omega_base,H_GFM,D_GFM,T_P,T_Q,m_q,Q_ref,X_L,eq_tol);

% Reject any dormant PLL/limiter/voltage-PI parameter fields rather than
% storing ambiguous unsupported controls.
reject_unsupported_options(g);

% --- Boundary conversion ---------------------------------------------------
kappa = Sbase/Mbase;
V0_mag = abs(V0);
theta0 = angle(V0);
P_ref_inv = kappa*P_ref_pu;

% --- Equilibrium initial state ---------------------------------------------
% The constructor warm-start solves for the reactive power Q0 that makes the
% algebraic Q-V droop voltage law consistent with the user-supplied V_ref at
% the terminal voltage V0 and active power P_ref. This is a scalar nonlinear
% equation in Q:
%   V_ref - m_q*(kappa*Q - Q_ref) = |V0 + jX_L*kappa*conj((P_ref+jQ)/V0)|
% solved by bisection on a frozen interval. The exact equilibrium_initializer
% below performs the same output-stage inversion for an arbitrary (V,P,Q,V_ref)
% and fails closed when the voltage law is infeasible.
Q0 = solve_consistent_Q(V0, P_ref_pu, kappa, X_L, m_q, Q_ref, V_ref_pu, eq_tol);
x0 = initialize_equilibrium(V0, P_ref_pu, Q0, kappa, X_L, m_q, Q_ref, V_ref_pu, eq_tol);
u0 = [P_ref_pu; V_ref_pu];

bp = bus_position;

% --- Closures (generic ABI; same signature as GFL-RMS10 + REGFM_B1) --------
% current_injection / electrical_power need u(2)=V_ref to evaluate the
% algebraic Q-V droop voltage law E_vsm = V_ref - m_q*(Q_f - Q_ref). The
% composite DAE passes the device input slice u_dev to every closure, so V_ref
% is available at runtime through the standard (t,x,y,u,ec) signature.
f = @(t,x,y,u,ec) model_f(x,y,u,bp,kappa,omega_base,H_GFM,D_GFM,T_P,T_Q, ...
    m_q,Q_ref,X_L);
current_injection = @(t,x,y,u,ec) model_current(x,y,u,bp,kappa,m_q,Q_ref,X_L);
electrical_power  = @(t,x,y,u,ec) model_power(x,y,u,bp,kappa,m_q,Q_ref,X_L);
reconstruct = @(t,x,y,u,ec) model_reconstruct(x,y,u,bp,kappa,omega_base, ...
    H_GFM,D_GFM,T_P,T_Q,m_q,Q_ref,X_L,Sbase,Mbase);
equilibrium_initialize = @(V,P,Q,ec) initialize_equilibrium(V,P,Q,kappa, ...
    X_L,m_q,Q_ref,V_ref_pu,eq_tol);

dev = struct();
dev.name = char(device_id);
dev.device_id = char(device_id);
dev.bus_id = bus_id;
dev.bus_position = bus_position;
dev.bus_ids = bus_ids(:).';
dev.device_type = 'ibr_gfm_vsg_no_pll';
dev.mode = 'GFM';
dev.nx = numel(x0);
dev.nu = 2;
dev.state_names = {'delta_vsm','delta_omega_vsm','P_f','Q_f'};
dev.input_names = {'P_ref','V_ref'};
dev.x0 = x0;
dev.u0 = u0;
dev.f = f;
dev.current_injection = current_injection;
dev.electrical_power = electrical_power;
dev.reconstruct = reconstruct;
dev.equilibrium_initialize = equilibrium_initialize;
dev.active_state_indices = @(ec) active_state_indices_fn(ec);
dev.provenance = struct( ...
    'model','GFM_VSG_NO_PLL_PROJECT_DERIVED_SOURCE_MAPPED', ...
    'source',['Sakimoto 2015 (docs/text/gfm_no_pll/sakimoto-2015-vsg-without-pll.pdf); ' ...
              'PNNL-35110 REGFM_A1 (docs/text/gfm_no_pll/pnnl-35110-regfm-a1.pdf); ' ...
              'Du 2024 (docs/text/gfm_no_pll/du-2024-positive-sequence-gfm.pdf); ' ...
              'Avila-Martinez 2025 (docs/text/gfm_no_pll/avila-martinez-2025-self-synchronisation-gfm.pdf)'], ...
    'source_classification', ...
        'PROJECT_DERIVED_SOURCE_MAPPED; 4of4 states sourced; cross-source assembly Sakimoto+PNNL+Avila; NO PLL', ...
    'state_register','see docs/project/GFM_NO_PLL_SOURCE_CONTRACT.md', ...
    'parameter_manifest','see docs/project/GFM_NO_PLL_SOURCE_CONTRACT.md', ...
    'control_option','VSM-noPLL swing + PNNL P/Q filters + PNNL VFlag=0 algebraic Q-V droop; no limiter; no AVR', ...
    'pu_base_contract','internal=inverter base; external=system base; kappa=Sbase/Mbase', ...
    'low_voltage_policy','NO_LVRT_NO_CURRENT_LIMITER; fault/LVRT readiness NOT_READY; no PLL freeze (no PLL exists)', ...
    'angle_contract','runtime rotor angle ONLY from dot(delta_vsm)=omega_base*delta_omega_vsm; never from angle(V)', ...
    'params',struct('Sbase',Sbase,'Mbase',Mbase,'fbase',fbase,'omega_base',omega_base, ...
        'H_GFM',H_GFM,'D_GFM',D_GFM,'T_P',T_P,'T_Q',T_Q, ...
        'm_q',m_q,'Q_ref',Q_ref,'X_L',X_L,'kappa',kappa,'eq_tol',eq_tol), ...
    'readiness','SOURCE_IMPLEMENTED_PENDING_SMIB_GATES');
end

% =========================================================================
function idx = active_state_indices_fn(~)
% All 4 states are active for an online GFM-no-PLL device. No frozen subset.
idx = 1:4;
end

% =========================================================================
function dx = model_f(x,y,u,bp,kappa,omega_base,H_GFM,D_GFM,T_P,T_Q,m_q,Q_ref,X_L)
check_state_input(x,u);
V = bus_voltage(y,bp);

% --- Output stage (Thevenin behind pure jX_L; generator convention) --------
delta_vsm = x(1);
delta_omega_vsm = x(2);
P_f = x(3);
Q_f = x(4);
P_ref_inv = kappa*u(1);
V_ref = u(2);

E_vsm = V_ref - m_q*(Q_f - Q_ref);
E_internal = E_vsm * exp(1i*delta_vsm);
I_inv = (E_internal - V)/(1i*X_L);
I_sys = I_inv/kappa;
S = V*conj(I_sys);
P_meas = real(S);   % system base
Q_meas = imag(S);   % system base
P_inv_meas = kappa*P_meas;   % inverter base
Q_inv_meas = kappa*Q_meas;   % inverter base

% --- Virtual-rotor swing (Avila Eq.9/10; Sakimoto Eq.4; NO PLL) ------------
d_delta_omega_vsm = (P_ref_inv - P_f - D_GFM*delta_omega_vsm)/(2*H_GFM);
d_delta_vsm = omega_base*delta_omega_vsm;

% --- P/Q measurement filters (PNNL Eq.4/5) ----------------------------------
d_P_f = (P_inv_meas - P_f)/T_P;
d_Q_f = (Q_inv_meas - Q_f)/T_Q;

dx = [d_delta_vsm; d_delta_omega_vsm; d_P_f; d_Q_f];
if any(~isfinite(dx))
    error('ibr:gfm_vsg_no_pll_model:nonfiniteRhs', ...
        'GFM-no-PLL RHS produced a non-finite value.');
end
end

% =========================================================================
function I = model_current(x,y,u,bp,kappa,m_q,Q_ref,X_L)
if numel(x) ~= 4 || any(~isfinite(x))
    error('ibr:gfm_vsg_no_pll_model:badState', ...
        'Expected four finite GFM-no-PLL states.');
end
if numel(u) ~= 2 || any(~isfinite(u))
    error('ibr:gfm_vsg_no_pll_model:badInput', ...
        'Expected finite u=[P_ref;V_ref].');
end
V = bus_voltage(y,bp);
delta_vsm = x(1);
Q_f = x(4);
V_ref = u(2);
E_vsm = V_ref - m_q*(Q_f - Q_ref);
E_internal = E_vsm * exp(1i*delta_vsm);
I_inv = (E_internal - V)/(1i*X_L);
I = I_inv/kappa;
if ~isfinite(I)
    error('ibr:gfm_vsg_no_pll_model:nonfiniteCurrent', ...
        'GFM-no-PLL current injection produced a non-finite value.');
end
end

% =========================================================================
function Pe = model_power(x,y,u,bp,kappa,m_q,Q_ref,X_L)
V = bus_voltage(y,bp);
I = model_current(x,y,u,bp,kappa,m_q,Q_ref,X_L);
Pe = real(V*conj(I));
end

% =========================================================================
function out = model_reconstruct(x,y,u,bp,kappa,omega_base, ...
    H_GFM,D_GFM,T_P,T_Q,m_q,Q_ref,X_L,Sbase,Mbase)
check_state_input(x,u);
V = bus_voltage(y,bp);
delta_vsm = x(1);
delta_omega_vsm = x(2);
P_f = x(3);
Q_f = x(4);
P_ref_inv = kappa*u(1);
V_ref = u(2);
E_vsm = V_ref - m_q*(Q_f - Q_ref);
E_internal = E_vsm * exp(1i*delta_vsm);
I_inv = (E_internal - V)/(1i*X_L);
I_sys = I_inv/kappa;
S = V*conj(I_sys);
P_meas = real(S);
Q_meas = imag(S);
P_inv_meas = kappa*P_meas;
Q_inv_meas = kappa*Q_meas;
omega_vsm_pu = 1.0 + delta_omega_vsm;
omega_vsm = omega_base*omega_vsm_pu;
% Diagnostic dq decomposition (network xy -> VSM rotor frame). Not used in RHS.
Vdq = V * exp(-1i*delta_vsm);
v_d =  real(Vdq);
v_q = -imag(Vdq);
out = struct( ...
    'delta_vsm', delta_vsm, 'delta_omega_vsm', delta_omega_vsm, ...
    'P_f', P_f, 'Q_f', Q_f, ...
    'E_vsm', E_vsm, 'E_internal', E_internal, ...
    'I_inv', I_inv, 'I_sys', I_sys, ...
    'Vbus', abs(V), 'Vbus_phasor', V, ...
    'Pe', P_meas, 'Qe', Q_meas, ...
    'P_inv_meas', P_inv_meas, 'Q_inv_meas', Q_inv_meas, ...
    'P_ref_inv', P_ref_inv, 'V_ref', V_ref, ...
    'omega_vsm_pu', omega_vsm_pu, 'omega_vsm', omega_vsm, ...
    'v_d', v_d, 'v_q', v_q, ...
    'kappa', kappa, 'Mbase', Mbase, 'Sbase', Sbase, ...
    'H_GFM', H_GFM, 'D_GFM', D_GFM, ...
    'T_P', T_P, 'T_Q', T_Q, 'm_q', m_q, 'Q_ref', Q_ref, 'X_L', X_L, ...
    'limiter_active', false, 'voltage_clamped', false, ...
    'readiness', 'SOURCE_IMPLEMENTED_PENDING_SMIB_GATES');
end

% =========================================================================
function xeq = initialize_equilibrium(V,Psys,Qsys,kappa,X_L,m_q,Q_ref,V_ref,eq_tol)
% Exact output-stage inversion. Given terminal (V,P,Q) on system base:
%   I_sys = conj((P+jQ)/V);  I_inv = kappa*I_sys;
%   E_internal = V + jX_L*I_inv;  delta_vsm = angle(E_internal);
%   delta_omega_vsm = 0;  P_f = kappa*P;  Q_f = kappa*Q.
% The algebraic voltage law E_vsm = V_ref - m_q*(Q_f - Q_ref) must reproduce
% |E_internal| within eq_tol; otherwise the requested (V,P,Q,V_ref) is
% infeasible and the initializer fails closed.
if ~isscalar(V) || ~isfinite(V) || abs(V) <= 0 || ...
        ~isscalar(Psys) || ~isscalar(Qsys) || ...
        ~isfinite(Psys) || ~isfinite(Qsys)
    error('ibr:gfm_vsg_no_pll_model:equilibriumInput', ...
        'Equilibrium V/P/Q must be finite scalar values with |V|>0.');
end
if ~isfinite(V_ref) || ~isreal(V_ref)
    error('ibr:gfm_vsg_no_pll_model:equilibriumInput', ...
        'Equilibrium V_ref must be a finite real scalar.');
end
I_sys = conj((Psys + 1i*Qsys)/V);
I_inv = kappa*I_sys;
E_internal = V + 1i*X_L*I_inv;
E_vsm_required = abs(E_internal);
E_vsm_law = V_ref - m_q*(kappa*Qsys - Q_ref);
if abs(E_vsm_law - E_vsm_required) > eq_tol*max(1.0,abs(E_vsm_required))
    error('ibr:gfm_vsg_no_pll_model:infeasibleEquilibriumVoltageLaw', ...
        ['Algebraic Q-V droop E_vsm=%.15g does not reproduce output-stage ' ...
         '|E_internal|=%.15g (residual=%.15g). The requested (V,P,Q,V_ref) ' ...
         'is infeasible for the frozen voltage law; fail-closed.'], ...
        E_vsm_law,E_vsm_required,abs(E_vsm_law-E_vsm_required));
end
xeq = [angle(E_internal); 0.0; kappa*Psys; kappa*Qsys];
if any(~isfinite(xeq))
    error('ibr:gfm_vsg_no_pll_model:equilibriumNonfinite', ...
        'Reconstructed GFM-no-PLL equilibrium contains non-finite values.');
end
end

% =========================================================================
function check_state_input(x,u)
if numel(x) ~= 4 || any(~isfinite(x))
    error('ibr:gfm_vsg_no_pll_model:badState', ...
        'Expected four finite GFM-no-PLL states.');
end
if numel(u) ~= 2 || any(~isfinite(u))
    error('ibr:gfm_vsg_no_pll_model:badInput', ...
        'Expected finite u=[P_ref;V_ref].');
end
end

% =========================================================================
function V = bus_voltage(y,bp)
if numel(y) < 2*bp || any(~isfinite(y(2*bp-1:2*bp)))
    error('ibr:gfm_vsg_no_pll_model:badNetworkState', ...
        'Network state does not contain a finite voltage for bus position %d.',bp);
end
V = complex(y(2*bp-1),y(2*bp));
end

% =========================================================================
function validate_bus_mapping(bus_id,bp,bus_ids)
if ~isfinite(bp) || bp ~= floor(bp) || bp < 1 || bp > numel(bus_ids) || ...
        bus_ids(bp) ~= bus_id
    error('ibr:gfm_vsg_no_pll_model:busMappingMismatch', ...
        'bus_position and bus_id do not identify the same network bus.');
end
end

% =========================================================================
function Q0 = solve_consistent_Q(V,P,kappa,X_L,m_q,Q_ref,V_ref,eq_tol)
% Solve the scalar nonlinear equation in Q:
%   V_ref - m_q*(kappa*Q - Q_ref) = |V + jX_L*kappa*conj((P+jQ)/V)|
% by bisection on a frozen interval [-Qspan, Qspan]. Returns the Q that makes
% the algebraic Q-V droop voltage law consistent with V_ref at (V,P). If no
% sign change is found on the interval, fail closed (infeasible V_ref).
Qspan = 2.0;   % pu reactive power search half-width (frozen, generous)
Qlo = -Qspan; Qhi = Qspan;
flo = voltage_law_residual(Qlo,V,P,kappa,X_L,m_q,Q_ref,V_ref);
fhi = voltage_law_residual(Qhi,V,P,kappa,X_L,m_q,Q_ref,V_ref);
if flo == 0
    Q0 = Qlo; return;
end
if fhi == 0
    Q0 = Qhi; return;
end
if flo*fhi > 0
    error('ibr:gfm_vsg_no_pll_model:infeasibleVref', ...
        ['No consistent Q found on [%g,%g] pu for the requested V_ref=%.6g. ' ...
         'The voltage law residual has the same sign at both ends ' ...
         '(f(%g)=%.6g, f(%g)=%.6g). The (V0,P_ref,V_ref) triple is infeasible ' ...
         'for the frozen Q-V droop; fail-closed.'], ...
        Qlo,Qhi,V_ref,Qlo,flo,Qhi,fhi);
end
for it = 1:200
    Qmid = 0.5*(Qlo+Qhi);
    fmid = voltage_law_residual(Qmid,V,P,kappa,X_L,m_q,Q_ref,V_ref);
    if abs(fmid) <= eq_tol*max(1.0,abs(V_ref))
        Q0 = Qmid; return;
    end
    if flo*fmid < 0
        Qhi = Qmid; fhi = fmid;
    else
        Qlo = Qmid; flo = fmid;
    end
    if abs(Qhi-Qlo) <= eq_tol*max(1.0,abs(Qlo))
        Q0 = 0.5*(Qlo+Qhi); return;
    end
end
Q0 = 0.5*(Qlo+Qhi);
end

% =========================================================================
function r = voltage_law_residual(Q,V,P,kappa,X_L,m_q,Q_ref,V_ref)
I_sys = conj((P+1i*Q)/V);
I_inv = kappa*I_sys;
E_internal = V + 1i*X_L*I_inv;
E_vsm_law = V_ref - m_q*(kappa*Q - Q_ref);
r = E_vsm_law - abs(E_internal);
end

% =========================================================================
function validate_params(Sbase,Mbase,fbase,omega_base,H_GFM,D_GFM, ...
    T_P,T_Q,m_q,Q_ref,X_L,eq_tol)
names = {'Sbase','Mbase','fbase','omega_base','H_GFM','D_GFM', ...
    'T_P','T_Q','m_q','Q_ref','X_L','eq_tol'};
vals = [Sbase,Mbase,fbase,omega_base,H_GFM,D_GFM,T_P,T_Q,m_q,Q_ref,X_L,eq_tol];
for k = 1:numel(names)
    if ~isscalar(vals(k)) || ~isfinite(vals(k))
        error('ibr:gfm_vsg_no_pll_model:badParam', ...
            'Parameter %s must be a finite scalar.', names{k});
    end
end
positive = {'Sbase','Mbase','fbase','omega_base','H_GFM','T_P','T_Q','X_L','eq_tol'};
pvals = struct('Sbase',Sbase,'Mbase',Mbase,'fbase',fbase,'omega_base',omega_base, ...
    'H_GFM',H_GFM,'T_P',T_P,'T_Q',T_Q,'X_L',X_L,'eq_tol',eq_tol);
for k = 1:numel(positive)
    if pvals.(positive{k}) <= 0
        error('ibr:gfm_vsg_no_pll_model:badParam', ...
            'Parameter %s must be positive.', positive{k});
    end
end
if D_GFM < 0
    error('ibr:gfm_vsg_no_pll_model:badParam', ...
        'Parameter D_GFM must be non-negative.');
end
end

% =========================================================================
function reject_unsupported_options(g)
% Reject dormant PLL / limiter / voltage-PI parameter fields rather than
% storing ambiguous unsupported controls. This enforces the no-PLL contract
% at construction time.
forbidden = {'kp_PLL','ki_PLL','VPLLfrz','delta_PLL','xi_PLL','x_PLL_int', ...
    'k_pv','k_iv','xi_E','V_f','VFlag','QVFlag','ImaxF','Emax','Emin', ...
    'kpqmax','Kiqmax','Pmax','Pmin','Qmax','Qmin'};
for k = 1:numel(forbidden)
    if isfield(g,forbidden{k})
        error('ibr:gfm_vsg_no_pll_model:unsupportedOption', ...
            ['Parameter %s is not supported by the GFM-no-PLL VFlag=0 ' ...
             'first slice. AVR/voltage-PI/limiter/PLL options are out-of-scope ' ...
             'future extensions; do not store dormant ambiguous controls.'], ...
            forbidden{k});
    end
end
end
