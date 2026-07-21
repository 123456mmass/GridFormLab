function dev = gfl_rms10_model(device_id, bus_id, bus_position, ...
    bus_ids, V0, params, P_ref_pu, Q_ref_pu)
%GFL_RMS10_MODEL  10-state positive-sequence RMS grid-following inverter.
%
%   dev = gfl_rms10_model(DEVICE_ID, BUS_ID, BUS_POSITION, BUS_IDS, V0, PARAMS,
%       P_REF_PU, Q_REF_PU) returns a device struct conforming to the
%       stability.composite_dae ABI (R3 Revision 2): f, current_injection,
%       electrical_power, reconstruct, equilibrium_initialize, state_names,
%       input_names, nx, nu, active_state_indices, provenance.
%
%   This is an opt-in PROJECT_DERIVED composite that reopens Phase 0B by user
%   authorization. It is NOT a complete source-defined GFL model. The nonlinear
%   PLL/current-controller/L-filter core (6 of 10 states) is SOURCE_DEFINED from
%   Yazdani 2010 + Teodorescu 2011; the P/Q filters, outer-loop realization,
%   limiters, anti-windup directional logic, base mapping and failure semantics
%   are PROJECT_DERIVED (see docs/project/IEEE14_IBR_GFL_RMS10_PROVENANCE.md).
%
%   State order (10, fixed):
%     1 delta_PLL  SRF-PLL angle                            [rad]
%     2 xi_PLL     SRF-PLL PI integrator                    [pu*s]
%     3 P_f        filtered active power (REGFM_B1 pattern) [pu inverter]
%     4 Q_f        filtered reactive power (REGFM_B1)       [pu inverter]
%     5 xi_P       active-power PI integrator               [pu*s]
%     6 xi_Q       reactive-power PI integrator             [pu*s]
%     7 xi_id      d-axis current PI integrator             [pu*s]
%     8 xi_iq      q-axis current PI integrator             [pu*s]
%     9 i_d        d-axis current plant state               [pu inverter]
%    10 i_q        q-axis current plant state                [pu inverter]
%
%   Inputs (nu=2): u = [P_ref; Q_ref] (pu, system base).
%
%   Per-unit base contract (same as WECC + REGFM_B1):
%     kappa = Sbase/Mbase; P_inv = kappa*P_sys; I_inv = kappa*I_sys.
%     Device-internal states run on inverter base; current_injection and
%     electrical_power return system-base quantities. No double conversion.
%
%   Governing equations (frozen; see PROVENANCE + PARAMETER_MANIFEST):
%     Boundary: kappa = Sbase/Mbase; P_ref_inv = kappa*P_ref_sys.
%     V_bus = complex(y(2*bp-1), y(2*bp))   (network common xy frame)
%     dq via delta_PLL (Yazdani eq 8.18-8.19, locked PLL: v_q=0):
%       v_d =  Re(V_bus*exp(-1i*delta_PLL)) = |V|*cos(angle(V)-delta_PLL)
%       v_q =  Im(V_bus*exp(-1i*delta_PLL)) = |V|*sin(angle(V)-delta_PLL)
%       (Yazdani eq 8.1: f_d+j*f_q=f*e^{-j*rho} => f_q=+Im; v_q>0 when V leads
%        delta_PLL, and the PLL PI drives v_q->0. A prior '-Im' transcription
%        inverted the phase-detector polarity, giving det(J_PLL)<0 -> saddle;
%        see defect 2026-07-21-gfl-rms10-smib-unstable-mode.)
%     PLL (Teodorescu eq 4.38, simple-PI ODE form; NO freeze):
%       dot(xi_PLL)   = v_q
%       dot(delta_PLL)= omega_b*(kp_PLL*v_q + ki_PLL*xi_PLL)
%     P/Q filters (REGFM_B1 Eq.1/3 pattern):
%       T_P*dot(P_f) = P_inv - P_f
%       T_Q*dot(Q_f) = Q_inv - Q_f
%     Outer loops (user §5.4; feedforward makes zero integrator exact at eq):
%       i_d_ref_raw = kp_P*(P_ref_inv - P_f) + ki_P*xi_P + P_ref_inv/|V|
%       i_q_ref_raw = -(kp_Q*(Q_ref_inv - Q_f) + ki_Q*xi_Q + Q_ref_inv/|V|)
%       dot(xi_P)   = AW_P(P_ref_inv - P_f)
%       dot(xi_Q)   = AW_Q(Q_ref_inv - Q_f)
%     Current-priority limit (user §5.5, P-priority default; WECC PQFlag=1 analog):
%       if hypot(i_d_ref_raw, i_q_ref_raw) > Imax:
%           i_d_ref = Imax (P-priority) ; i_q_ref = sign(i_q_ref_raw)*sqrt(Imax^2-i_d_ref^2)
%       else: i_d_ref = i_d_ref_raw ; i_q_ref = i_q_ref_raw
%       current_limiter_active = (limited)
%     Current PI + decoupling feedforward (Yazdani eq 8.49-8.50, 8.53):
%       e_d = i_d_ref - i_d ; e_q = i_q_ref - i_q
%       v_td_raw = kp_i*e_d + ki_i*xi_id - omega_PLL*L*i_q + v_d
%       v_tq_raw = kp_i*e_q + ki_i*xi_iq + omega_PLL*L*i_d + v_q
%       dot(xi_id) = AW_id(e_d) ; dot(xi_iq) = AW_iq(e_q)
%     v_t modulation clamp (Yazdani eq 8.47-8.48; factor 1/2 from App.B Table B.2):
%       V_t_max = m_max*Vdc0/2
%       if hypot(v_td_raw, v_tq_raw) > V_t_max: scale radially; voltage_clamped=true
%       else: voltage_clamped=false
%     Current plant (Yazdani eq 8.45-8.46):
%       omega_PLL = omega_b + dot(delta_PLL)   [rad/s]
%       L*dot(i_d) = L*omega_PLL*i_q - R_t*i_d + v_td - v_d
%       L*dot(i_q) = -L*omega_PLL*i_d - R_t*i_q + v_tq - v_q
%     Network injection (generator convention S=V*conj(I), system base):
%       I_dq_inv = i_d + 1i*i_q   (inverter base, dq frame)
%       I_net = (I_dq_inv * exp(1i*delta_PLL)) / kappa   (system base, xy frame)
%       P = real(V_bus*conj(I_net)); Q = imag(V_bus*conj(I_net))
%
%   Balanced positive-sequence LVRT policy (FROZEN; NO PLL freeze):
%     V_valid_min applies to equilibrium initialization. During a balanced
%     positive-sequence fault, the SRF-PLL continues while |V|>=V_div_min;
%     the current command switches below Vdip to voltage-dependent active
%     current and reactive-current priority (Teodorescu Ch.7 pp.162-163,
%     mapped to the WECC REGC_A/REEC_A example parameters). At or below the
%     division floor the model fails closed with
%     ibr:gfl_rms10_model:lowVoltagePowerInversion. Unbalanced-fault and
%     zero-voltage behavior remain outside this positive-sequence slice.
%
%   Classification: see IEEE14_IBR_GFL_RMS10_PROVENANCE.md (6 SOURCE_DEFINED +
%   4 PROJECT_DERIVED states) and IEEE14_IBR_GFL_RMS10_PARAMETER_MANIFEST.md.
%
%   STATUS: SOURCE_IMPLEMENTED_PENDING_INTEGRATION_GATES.
%
%   Sources: A=docs/text/6739364.pdf (Yazdani 2010);
%            B=docs/text/grid-converters-for-photovoltaic-and-wind-power-systems.pdf
%              (Teodorescu 2011);
%            C=docs/text/978-1-4471-5478-5.pdf (Bacha 2014).

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

validate_bus_mapping(bus_id, bus_position, bus_ids);
if ~isfinite(V0) || abs(V0) <= 0
    error('ibr:gfl_rms10_model:badV0', ...
        'V0 must be a finite nonzero bus-voltage phasor.');
end
if ~isfinite(P_ref_pu) || ~isfinite(Q_ref_pu) || ...
        ~isreal(P_ref_pu) || ~isreal(Q_ref_pu)
    error('ibr:gfl_rms10_model:badRef', ...
        'P_ref_pu and Q_ref_pu must be finite real system-base values.');
end

% --- Frozen numerical parameter profile (PARAMETER_MANIFEST) ----------------
% Bases (CASE_DEFINED, overridable via params).
Sbase  = 100.0;   if isfield(params,'Sbase')  && ~isempty(params.Sbase),  Sbase  = params.Sbase;  end
Mbase  = 100.0;   if isfield(params,'Mbase')  && ~isempty(params.Mbase),  Mbase  = params.Mbase;  end
fbase  = 60.0;    if isfield(params,'fbase')  && ~isempty(params.fbase),  fbase  = params.fbase;  end
omega_b = 2*pi*fbase;

% RMS10-specific overrides under params.gfl_rms10 (nested; never top-level, to
% avoid accidental REGFM_B1 override).
rms = struct();
if isfield(params,'gfl_rms10') && isstruct(params.gfl_rms10)
    rms = params.gfl_rms10;
end

% PLL (SOURCE_DEFINED, Teodorescu eq 4.38 simple-PI ODE form).
ts_pll = 0.1;     if isfield(rms,'ts_pll')  && ~isempty(rms.ts_pll),  ts_pll  = rms.ts_pll;  end
kp_PLL = 9.2/(ts_pll^2);
Ti_pll = ts_pll/4.6;
ki_PLL = kp_PLL/Ti_pll;

% P/Q filters (PROJECT_DERIVED, REGFM_B1 Eq.1/3 pattern).
T_P = 0.02;  if isfield(rms,'T_P')  && ~isempty(rms.T_P),  T_P = rms.T_P;  end
T_Q = 0.02;  if isfield(rms,'T_Q')  && ~isempty(rms.T_Q),  T_Q = rms.T_Q;  end

% Outer-loop PI (PROJECT_DERIVED, user §5.4).
kp_P = 1.0;   if isfield(rms,'kp_P')  && ~isempty(rms.kp_P),  kp_P = rms.kp_P;  end
ki_P = 20.0;  if isfield(rms,'ki_P')  && ~isempty(rms.ki_P),  ki_P = rms.ki_P;  end
kp_Q = 1.0;   if isfield(rms,'kp_Q')  && ~isempty(rms.kp_Q),  kp_Q = rms.kp_Q;  end
ki_Q = 20.0;  if isfield(rms,'ki_Q')  && ~isempty(rms.ki_Q),  ki_Q = rms.ki_Q;  end

% Current loop PI (SOURCE_DEFINED, Yazdani eq 8.56/8.57). tau_i = 2 ms (Ex.8.2).
tau_i = 2.0e-3;  if isfield(rms,'tau_i')  && ~isempty(rms.tau_i),  tau_i = rms.tau_i;  end

% Plant R_t, L (SOURCE_DEFINED, Yazdani Ex.8.2). Per-unit on inverter base.
% L is the per-unit COUPLING REACTANCE X = omega_b*L_SI (NOT inductance in s).
% This matches the PF/WECC convention where impedances are per-unit reactances.
% Yazdani Ex.8.2 L=100uH on a 2.5MVA/391Vpeak base gives X ~ 0.10-0.15 pu.
R_t = 0.02;    if isfield(rms,'R_t')  && ~isempty(rms.R_t),  R_t = rms.R_t;  end
X_l = 0.15;    if isfield(rms,'L')    && ~isempty(rms.L),    X_l = rms.L;    end
L = X_l;   % per-unit reactance; the ODE uses L as omega_b-normalized reactance.

% Current-controller gains derived from eq 8.56/8.57 (SOURCE_DEFINED equation).
% In per-unit form with L as reactance: the per-unit inductance is L/omega_b,
% so kp_i = (L/omega_b)/tau_i and ki_i = R_t/tau_i (Yazdani eq 8.56/8.57).
kp_i = (L/omega_b)/tau_i;
ki_i = R_t/tau_i;

% Limits (Imax SOURCE_DEFINED A p.371; m_max PROJECT_DERIVED).
% Vdc0 is stored in per-unit AC-voltage base (Yazdani App.B: DC base = 2*AC base,
% so 1.0 pu DC corresponds to 1.0 pu AC at unity modulation after the /2 in
% eq 8.47). Therefore v_t_max = m_max*Vdc0 (the /2 is already absorbed by the
% base convention; Vdc0=1.0 pu AC means v_td can reach 1.0 pu AC at m=1).
% m_max=1.30 provides overmodulation headroom so the clamp is inactive in
% normal operation (v_td = v_d + R_t*i_d + omega*L*i_q must fit when |V|~1.09
% and i_d is at rated; verified inactive across IEEE14 buses 2/3/6/8).
Imax = 1.20;   if isfield(rms,'Imax')  && ~isempty(rms.Imax),  Imax = rms.Imax;  end
Vdc0 = 1.0;    if isfield(rms,'Vdc0')  && ~isempty(rms.Vdc0),  Vdc0 = rms.Vdc0;  end
m_max = 1.30;  if isfield(rms,'m_max')  && ~isempty(rms.m_max),  m_max = rms.m_max;  end
V_t_max = m_max*Vdc0;   % Yazdani eq 8.47 with App.B base convention

% Low-voltage thresholds (CASE_DEFINED).
V_valid_min = 0.50;  if isfield(rms,'V_valid_min')  && ~isempty(rms.V_valid_min),  V_valid_min = rms.V_valid_min;  end
V_div_min   = 0.10;  if isfield(rms,'V_div_min')    && ~isempty(rms.V_div_min),    V_div_min   = rms.V_div_min;    end

% Balanced positive-sequence LVRT mapping.  Vdip/Kqv/deadband/current limits
% are the official WECC REGC_A/REEC_A conversion-example values already
% source-frozen in wecc_regca_reeca_model.m.  The voltage-dependent active
% current and reactive-priority policy follow Teodorescu Ch.7 pp.162-163.
Vdip=0.90;  Kqv=2.0;  dbd=0.10;  Iqh1=1.0;
Zerox=0.40; Brkpt=0.90; Lvpl1=1.22;
if isfield(rms,'Vdip')&&~isempty(rms.Vdip), Vdip=rms.Vdip; end
if isfield(rms,'Kqv')&&~isempty(rms.Kqv), Kqv=rms.Kqv; end
if isfield(rms,'lvrt_deadband')&&~isempty(rms.lvrt_deadband), dbd=rms.lvrt_deadband; end
if isfield(rms,'Iqh1')&&~isempty(rms.Iqh1), Iqh1=rms.Iqh1; end
if isfield(rms,'Zerox')&&~isempty(rms.Zerox), Zerox=rms.Zerox; end
if isfield(rms,'Brkpt')&&~isempty(rms.Brkpt), Brkpt=rms.Brkpt; end
if isfield(rms,'Lvpl1')&&~isempty(rms.Lvpl1), Lvpl1=rms.Lvpl1; end
validate_lvrt_params(Vdip,Kqv,dbd,Iqh1,Zerox,Brkpt,Lvpl1,V_div_min);

% Anti-windup tolerance (NUMERICAL_METHOD).
aw_tol = 1.0e-6;  if isfield(rms,'aw_tol')  && ~isempty(rms.aw_tol),  aw_tol = rms.aw_tol;  end

validate_params(Sbase,Mbase,fbase,omega_b,T_P,T_Q,kp_P,ki_P,kp_Q,ki_Q, ...
    R_t,L,Imax,Vdc0,m_max,V_valid_min,V_div_min,aw_tol,kp_PLL,ki_PLL,kp_i,ki_i);

% --- Boundary conversion ---------------------------------------------------
kappa = Sbase/Mbase;
V0_mag = abs(V0);
theta0 = angle(V0);
P_ref_inv = kappa*P_ref_pu;
Q_ref_inv = kappa*Q_ref_pu;

% --- Equilibrium initial state (§6) ----------------------------------------
% delta_PLL0 = angle(V0); xi_PLL0 = 0; v_d0 = |V0|; v_q0 = 0;
% P_f0 = P_ref_inv; Q_f0 = Q_ref_inv; xi_P0 = xi_Q0 = 0;
% i_d0 = P_ref_inv/v_d0; i_q0 = -Q_ref_inv/v_d0; xi_id0 = xi_iq0 = 0.
if V0_mag < V_valid_min
    error('ibr:gfl_rms10_model:voltageOutsideValidityDomain', ...
        'Equilibrium |V0|=%.6g < V_valid_min=%.6g; fail-closed (no PLL freeze).', ...
        V0_mag, V_valid_min);
end
i_d0 = P_ref_inv/V0_mag;
i_q0 = -Q_ref_inv/V0_mag;
if hypot(i_d0, i_q0) > Imax + 64*eps(max(1.0,Imax))
    error('ibr:gfl_rms10_model:equilibriumCurrentLimit', ...
        'Equilibrium current %.15g exceeds Imax=%.15g.', hypot(i_d0,i_q0), Imax);
end
x0 = [theta0; 0.0; P_ref_inv; Q_ref_inv; 0.0; 0.0; 0.0; 0.0; i_d0; i_q0];
u0 = [P_ref_pu; Q_ref_pu];

bp = bus_position;

% --- Closures (generic ABI; same signature as WECC + REGFM_B1) -------------
f = @(t,x,y,u,ec) model_f(x,y,u,bp,kappa,omega_b,kp_PLL,ki_PLL,T_P,T_Q, ...
    kp_P,ki_P,kp_Q,ki_Q,kp_i,ki_i,R_t,L,Imax,V_t_max,V_valid_min,V_div_min,aw_tol,Vdc0, ...
    V0_mag,Vdip,Kqv,dbd,Iqh1,Zerox,Brkpt,Lvpl1);
current_injection = @(t,x,y,u,ec) model_current(x,y,bp,kappa,V_valid_min,V_div_min);
electrical_power  = @(t,x,y,u,ec) model_power(x,y,bp,kappa,V_valid_min,V_div_min);
reconstruct = @(t,x,y,u,ec) model_reconstruct(x,y,u,bp,kappa,omega_b,kp_PLL,ki_PLL, ...
    T_P,T_Q,kp_P,ki_P,kp_Q,ki_Q,kp_i,ki_i,R_t,L,Imax,V_t_max,Vdc0,m_max, ...
    V_valid_min,V_div_min,aw_tol,Sbase,Mbase,V0_mag,Vdip,Kqv,dbd,Iqh1,Zerox,Brkpt,Lvpl1);
equilibrium_initialize = @(V,P,Q,ec) initialize_equilibrium(V,P,Q,kappa, ...
    V_valid_min,Imax);

dev = struct();
dev.name = char(device_id);
dev.device_id = char(device_id);
dev.bus_id = bus_id;
dev.bus_position = bus_position;
dev.bus_ids = bus_ids(:).';
dev.device_type = 'ibr_gfl_rms10';
dev.mode = 'gfl';
dev.nx = numel(x0);
dev.nu = 2;
dev.state_names = {'delta_PLL','xi_PLL','P_f','Q_f','xi_P','xi_Q', ...
    'xi_id','xi_iq','i_d','i_q'};
dev.input_names = {'P_ref','Q_ref'};
dev.x0 = x0;
dev.u0 = u0;
dev.f = f;
dev.current_injection = current_injection;
dev.electrical_power = electrical_power;
dev.reconstruct = reconstruct;
dev.equilibrium_initialize = equilibrium_initialize;
dev.active_state_indices = @(ec) active_state_indices_fn(ec);
dev.provenance = struct( ...
    'model','GFL_RMS10_PROJECT_DERIVED_COMPOSITE', ...
    'source',['A=docs/text/6739364.pdf (Yazdani 2010); ' ...
              'B=docs/text/grid-converters-for-photovoltaic-and-wind-power-systems.pdf (Teodorescu 2011); ' ...
              'C=docs/text/978-1-4471-5478-5.pdf (Bacha 2014)'], ...
    'source_classification', ...
        'SOURCE_DEFINED_NONLINEAR_CORE_CLOSED=YES 6of10 states; FULL_SOURCE_DEFINED_GFL_MODEL=NO; APPROVED_PROJECT_DERIVED_RMS10_SLICE=YES', ...
    'state_register','see docs/project/IEEE14_IBR_GFL_RMS10_PROVENANCE.md', ...
    'parameter_manifest','see docs/project/IEEE14_IBR_GFL_RMS10_PARAMETER_MANIFEST.md', ...
    'control_option','SRF-PLL + dq current control + P/Q outer loops; normal P-priority; balanced-fault LVRT Q-priority', ...
    'pu_base_contract','internal=inverter base; external=system base; kappa=Sbase/Mbase', ...
    'low_voltage_policy','BALANCED_POSITIVE_SEQUENCE_LVRT for V_div_min<=|V|<Vdip; zero/near-zero and unbalanced faults remain fail-closed', ...
    'params',struct('Sbase',Sbase,'Mbase',Mbase,'fbase',fbase,'omega_b',omega_b, ...
        'kp_PLL',kp_PLL,'ki_PLL',ki_PLL,'ts_pll',ts_pll, ...
        'T_P',T_P,'T_Q',T_Q,'kp_P',kp_P,'ki_P',ki_P,'kp_Q',kp_Q,'ki_Q',ki_Q, ...
        'kp_i',kp_i,'ki_i',ki_i,'tau_i',tau_i, ...
        'R_t',R_t,'L',L,'Imax',Imax,'Vdc0',Vdc0,'m_max',m_max, ...
        'V_t_max',V_t_max,'V_valid_min',V_valid_min,'V_div_min',V_div_min, ...
        'Vdip',Vdip,'Kqv',Kqv,'lvrt_deadband',dbd,'Iqh1',Iqh1, ...
        'Zerox',Zerox,'Brkpt',Brkpt,'Lvpl1',Lvpl1, ...
        'aw_tol',aw_tol,'kappa',kappa), ...
    'readiness','SOURCE_IMPLEMENTED_PENDING_INTEGRATION_GATES');
end

% =========================================================================
function idx = active_state_indices_fn(~)
% All 10 states are active for an online GFL-RMS10 device. No frozen subset.
idx = 1:10;
end

% =========================================================================
function dx = model_f(x,y,u,bp,kappa,omega_b,kp_PLL,ki_PLL,T_P,T_Q, ...
    kp_P,ki_P,kp_Q,ki_Q,kp_i,ki_i,R_t,L,Imax,V_t_max,V_valid_min,V_div_min,aw_tol,Vdc0, ...
    Vref0,Vdip,Kqv,dbd,Iqh1,Zerox,Brkpt,Lvpl1)
check_state_input(x,u);
V = bus_voltage(y,bp);
Vmag = abs(V);

% Runtime LVRT is valid for balanced positive-sequence voltage down to the
% frozen division floor. Equilibrium initialization still requires
% V_valid_min. No PLL freeze or stale-state continuation is introduced.
if Vmag < V_div_min
    error('ibr:gfl_rms10_model:lowVoltagePowerInversion', ...
        '|V|=%.6g < V_div_min=%.6g; balanced LVRT cannot define the PLL frame.', ...
        Vmag,V_div_min);
end

delta_PLL = x(1);
xi_PLL    = x(2);
P_f       = x(3);
Q_f       = x(4);
xi_P      = x(5);
xi_Q      = x(6);
xi_id     = x(7);
xi_iq     = x(8);
i_d       = x(9);
i_q       = x(10);

% dq voltage via delta_PLL (Yazdani eq 8.18-8.19; locked PLL -> v_q=0).
Vdq = V * exp(-1i*delta_PLL);
v_d =  real(Vdq);
v_q =  imag(Vdq);    % Yazdani eq 8.1: v_q=+Im=|V|sin(angle(V)-delta_PLL); >0 when V leads
D_V = v_d^2 + v_q^2;
if D_V < V_div_min^2
    error('ibr:gfl_rms10_model:lowVoltagePowerInversion', ...
        'D_V=v_d^2+v_q^2=%.6g < V_div_min^2=%.6g; fail-closed power inversion.', ...
        D_V, V_div_min^2);
end

% --- Measured inverter-base power (generator convention) -------------------
% I_net = (i_d + 1i*i_q)*exp(1i*delta_PLL)/kappa ; S = V*conj(I_net).
I_dq_inv = complex(i_d, i_q);
I_net = (I_dq_inv * exp(1i*delta_PLL)) / kappa;
S = V*conj(I_net);
P_inv_meas = kappa*real(S);   % inverter base
Q_inv_meas = kappa*imag(S);

% --- Boundary refs ---------------------------------------------------------
P_ref_inv = kappa*u(1);
Q_ref_inv = kappa*u(2);

% --- PLL (Teodorescu eq 4.38; simple-PI ODE; NO freeze) --------------------
d_xi_PLL    = v_q;
Delta_omega = kp_PLL*v_q + ki_PLL*xi_PLL;     % [pu frequency deviation]
d_delta_PLL = omega_b*Delta_omega;            % [rad/s]
omega_PLL_pu = 1.0 + Delta_omega;             % [pu frequency]; L is pu reactance

% --- P/Q filters (REGFM_B1 Eq.1/3 pattern) ---------------------------------
d_P_f = (P_inv_meas - P_f)/T_P;
d_Q_f = (Q_inv_meas - Q_f)/T_Q;

% --- Outer loops (user §5.4; feedforward P_ref/|V| makes zero eq exact) ---
e_P = P_ref_inv - P_f;
e_Q = Q_ref_inv - Q_f;
i_d_ff=(v_d*P_ref_inv+v_q*Q_ref_inv)/D_V;
i_q_ff=(v_q*P_ref_inv-v_d*Q_ref_inv)/D_V;
i_d_ref_raw = kp_P*e_P + ki_P*xi_P + i_d_ff;
i_q_ref_raw = -(kp_Q*e_Q + ki_Q*xi_Q) + i_q_ff;

% --- Current-priority limit (user §5.5; P-priority default) ---------------
[i_d_ref,i_q_ref,limiter_active,~] = lvrt_or_normal_limit( ...
    i_d_ref_raw,i_q_ref_raw,Vmag,Vref0,Vdip,Kqv,dbd,Iqh1, ...
    Zerox,Brkpt,Lvpl1,Imax);

% P/Q limiter P/Q outputs at the limit (for anti-windup directional test).
P_lim = v_d*i_d_ref + v_q*i_q_ref;
Q_lim = v_q*i_d_ref - v_d*i_q_ref;
P_cmd = P_ref_inv;
Q_cmd = Q_ref_inv;

% --- Anti-windup AW_P, AW_Q (one-sided conditional hold) -------------------
% Outward hold, inward release. AW_P(e_P)=0 when limiter active AND
% (P_cmd - P_lim)*e_P > aw_tol (i.e. integrator pushing further into limit).
aw_P = aw_outer(e_P, P_cmd, P_lim, limiter_active, aw_tol);
aw_Q = aw_outer(e_Q, Q_cmd, Q_lim, limiter_active, aw_tol);
d_xi_P = aw_P;
d_xi_Q = aw_Q;

% --- Current PI + decoupling feedforward (Yazdani eq 8.49-8.50, 8.53) ------
e_d = i_d_ref - i_d;
e_q = i_q_ref - i_q;
v_td_raw = kp_i*e_d + ki_i*xi_id + R_t*i_d - omega_PLL_pu*L*i_q + v_d;
v_tq_raw = kp_i*e_q + ki_i*xi_iq + R_t*i_q + omega_PLL_pu*L*i_d + v_q;

% --- v_t modulation clamp (Yazdani eq 8.47-8.48; vector/radial) -----------
[v_td, v_tq, voltage_clamped] = vector_clamp(v_td_raw, v_tq_raw, V_t_max);

% --- Current-loop anti-windup AW_id, AW_iq ---------------------------------
% r_v = [v_td_raw; v_tq_raw] - [v_td; v_tq]; AW_id(e_d)=0 when clamped AND
% dot(r_v,[ki_i*e_d;0]) > aw_tol (outward hold, inward release).
r_v = [v_td_raw - v_td; v_tq_raw - v_tq];
aw_id = aw_current(e_d, ki_i, r_v(1), r_v(2), aw_tol, voltage_clamped, 'd');
aw_iq = aw_current(e_q, ki_i, r_v(1), r_v(2), aw_tol, voltage_clamped, 'q');
d_xi_id = aw_id;
d_xi_iq = aw_iq;

% --- Current plant (Yazdani eq 8.45-8.46) ---------------------------------
% L is the per-unit coupling reactance; omega_PLL_pu is the per-unit frequency.
% The (1/omega_b) factor converts the reactance form to the time-derivative form.
d_i_d = (omega_PLL_pu*L*i_q - R_t*i_d + v_td - v_d)/(L/omega_b);
d_i_q = (-omega_PLL_pu*L*i_d - R_t*i_q + v_tq - v_q)/(L/omega_b);

dx = [d_delta_PLL; d_xi_PLL; d_P_f; d_Q_f; d_xi_P; d_xi_Q; ...
      d_xi_id; d_xi_iq; d_i_d; d_i_q];
if any(~isfinite(dx))
    error('ibr:gfl_rms10_model:nonfiniteRhs', ...
        'GFL-RMS10 RHS produced a non-finite value.');
end
end

% =========================================================================
function I = model_current(x,y,bp,kappa,V_valid_min,V_div_min)
if numel(x) ~= 10 || any(~isfinite(x))
    error('ibr:gfl_rms10_model:badState', ...
        'Expected ten finite GFL-RMS10 states.');
end
V = bus_voltage(y,bp);
Vmag = abs(V);
if Vmag < V_div_min
    error('ibr:gfl_rms10_model:lowVoltagePowerInversion', ...
        '|V|=%.6g < V_div_min=%.6g; current injection outside balanced-LVRT domain.', ...
        Vmag,V_div_min);
end
delta_PLL = x(1);
i_d = x(9);
i_q = x(10);
Vdq = V * exp(-1i*delta_PLL);
v_d =  real(Vdq);
v_q =  imag(Vdq);    % Yazdani eq 8.1 convention (v_q=+Im); D_V=v_d^2+v_q^2 sign-invariant
D_V = v_d^2 + v_q^2;
if D_V < V_div_min^2
    error('ibr:gfl_rms10_model:lowVoltagePowerInversion', ...
        'D_V=%.6g < V_div_min^2=%.6g; current injection fail-closed.', D_V, V_div_min^2);
end
I_dq_inv = complex(i_d, i_q);
I = (I_dq_inv * exp(1i*delta_PLL)) / kappa;
end

% =========================================================================
function Pe = model_power(x,y,bp,kappa,V_valid_min,V_div_min)
V = bus_voltage(y,bp);
I = model_current(x,y,bp,kappa,V_valid_min,V_div_min);
Pe = real(V*conj(I));
end

% =========================================================================
function out = model_reconstruct(x,y,u,bp,kappa,omega_b,kp_PLL,ki_PLL, ...
    T_P,T_Q,kp_P,ki_P,kp_Q,ki_Q,kp_i,ki_i,R_t,L,Imax,V_t_max,Vdc0,m_max, ...
    V_valid_min,V_div_min,aw_tol,Sbase,Mbase,Vref0,Vdip,Kqv,dbd,Iqh1,Zerox,Brkpt,Lvpl1)
check_state_input(x,u);
V = bus_voltage(y,bp);
Vmag = abs(V);
if Vmag < V_div_min
    error('ibr:gfl_rms10_model:lowVoltagePowerInversion', ...
        '|V|=%.6g < V_div_min=%.6g; reconstruction outside balanced-LVRT domain.', ...
        Vmag,V_div_min);
end
delta_PLL = x(1);  xi_PLL = x(2);
P_f = x(3);  Q_f = x(4);  xi_P = x(5);  xi_Q = x(6);
xi_id = x(7);  xi_iq = x(8);  i_d = x(9);  i_q = x(10);
Vdq = V * exp(-1i*delta_PLL);
v_d =  real(Vdq);  v_q =  imag(Vdq);   % Yazdani eq 8.1: v_q=+Im
D_V = v_d^2 + v_q^2;
if D_V < V_div_min^2
    error('ibr:gfl_rms10_model:lowVoltagePowerInversion', ...
        'D_V=%.6g < V_div_min^2=%.6g; reconstruction fail-closed.', ...
        D_V,V_div_min^2);
end
I_dq_inv = complex(i_d, i_q);
I = (I_dq_inv * exp(1i*delta_PLL)) / kappa;
S = V*conj(I);
P_ref_inv = kappa*u(1);
Q_ref_inv = kappa*u(2);
e_P = P_ref_inv - P_f;
e_Q = Q_ref_inv - Q_f;
i_d_ff=(v_d*P_ref_inv+v_q*Q_ref_inv)/D_V;
i_q_ff=(v_q*P_ref_inv-v_d*Q_ref_inv)/D_V;
i_d_ref_raw = kp_P*e_P + ki_P*xi_P + i_d_ff;
i_q_ref_raw = -(kp_Q*e_Q + ki_Q*xi_Q) + i_q_ff;
[i_d_ref,i_q_ref,limiter_active,lvrt_active] = lvrt_or_normal_limit( ...
    i_d_ref_raw,i_q_ref_raw,Vmag,Vref0,Vdip,Kqv,dbd,Iqh1, ...
    Zerox,Brkpt,Lvpl1,Imax);
e_d = i_d_ref - i_d;
e_q = i_q_ref - i_q;
omega_PLL_pu = 1.0 + (kp_PLL*v_q + ki_PLL*xi_PLL);
omega_PLL = omega_b*omega_PLL_pu;
v_td_raw = kp_i*e_d + ki_i*xi_id + R_t*i_d - omega_PLL_pu*L*i_q + v_d;
v_tq_raw = kp_i*e_q + ki_i*xi_iq + R_t*i_q + omega_PLL_pu*L*i_d + v_q;
[v_td, v_tq, voltage_clamped] = vector_clamp(v_td_raw, v_tq_raw, V_t_max);
out = struct( ...
    'delta_PLL', delta_PLL, 'xi_PLL', xi_PLL, ...
    'P_f', P_f, 'Q_f', Q_f, 'xi_P', xi_P, 'xi_Q', xi_Q, ...
    'xi_id', xi_id, 'xi_iq', xi_iq, 'i_d', i_d, 'i_q', i_q, ...
    'v_d', v_d, 'v_q', v_q, 'v_td', v_td, 'v_tq', v_tq, ...
    'v_td_raw', v_td_raw, 'v_tq_raw', v_tq_raw, ...
    'I_gfl', I, 'Vbus', Vmag, ...
    'Pe', real(S), 'Qe', imag(S), ...
    'kappa', kappa, 'Mbase', Mbase, 'Sbase', Sbase, ...
    'P_ref_inv', P_ref_inv, 'Q_ref_inv', Q_ref_inv, ...
    'P_inv_meas', kappa*real(S), 'Q_inv_meas', kappa*imag(S), ...
    'i_d_ref', i_d_ref, 'i_q_ref', i_q_ref, ...
    'i_d_ref_raw', i_d_ref_raw, 'i_q_ref_raw', i_q_ref_raw, ...
    'Imax', Imax, 'Imax_inv', Imax, ...
    'Iabs_inv', kappa*abs(I), 'limiter_active', limiter_active, ...
    'lvrt_active',lvrt_active,'lvrt_profile','BALANCED_POSITIVE_SEQUENCE', ...
    'voltage_clamped', voltage_clamped, ...
    'V_t_max', V_t_max, 'Vdc0', Vdc0, 'm_max', m_max, ...
    'omega_PLL', omega_PLL, 'D_V', D_V, ...
    'V_valid_min', V_valid_min, 'V_div_min', V_div_min, 'aw_tol', aw_tol, ...
    'in_valid_domain', D_V >= V_div_min^2, ...
    'normal_equilibrium_domain',Vmag>=V_valid_min);
end

% =========================================================================
function xeq = initialize_equilibrium(V,Psys,Qsys,kappa,V_valid_min,Imax)
if ~isscalar(V) || ~isfinite(V) || abs(V) <= 0 || ...
        ~isscalar(Psys) || ~isscalar(Qsys) || ...
        ~isfinite(Psys) || ~isfinite(Qsys)
    error('ibr:gfl_rms10_model:equilibriumInput', ...
        'Equilibrium V/P/Q must be finite scalar values with |V|>0.');
end
Vmag = abs(V);
if Vmag < V_valid_min
    error('ibr:gfl_rms10_model:voltageOutsideValidityDomain', ...
        'Equilibrium |V|=%.6g < V_valid_min=%.6g; fail-closed.', Vmag, V_valid_min);
end
Pinv = kappa*Psys;
Qinv = kappa*Qsys;
i_d0 = Pinv/Vmag;
i_q0 = -Qinv/Vmag;
if hypot(i_d0, i_q0) > Imax + 64*eps(max(1.0,Imax))
    error('ibr:gfl_rms10_model:equilibriumCurrentLimit', ...
        'Equilibrium current %.15g exceeds Imax=%.15g.', hypot(i_d0,i_q0), Imax);
end
xeq = [angle(V); 0.0; Pinv; Qinv; 0.0; 0.0; 0.0; 0.0; i_d0; i_q0];
if any(~isfinite(xeq))
    error('ibr:gfl_rms10_model:equilibriumNonfinite', ...
        'Reconstructed GFL-RMS10 equilibrium contains non-finite values.');
end
end

% =========================================================================
function [i_d_ref, i_q_ref, active] = current_priority_limit(i_d_raw, i_q_raw, Imax)
% P-priority default (user §5.5; WECC PQFlag=1 analog).
mag = hypot(i_d_raw, i_q_raw);
if mag > Imax
    active = true;
    i_d_ref = min(max(i_d_raw, -Imax), Imax);
    iq_room = sqrt(max(Imax^2 - i_d_ref^2, 0));
    if i_q_raw >= 0
        i_q_ref = iq_room;
    else
        i_q_ref = -iq_room;
    end
else
    active = false;
    i_d_ref = i_d_raw;
    i_q_ref = i_q_raw;
end
end

function [id,iq,active,lvrt] = lvrt_or_normal_limit(id_raw,iq_raw,V,Vref, ...
        Vdip,Kqv,dbd,Iqh1,Zerox,Brkpt,Lvpl1,Imax)
lvrt=V<Vdip;
if ~lvrt
    [id,iq,active]=current_priority_limit(id_raw,iq_raw,Imax);
    return;
end
% Teodorescu Ch.7: voltage-triggered positive-sequence reactive-current
% support with reactive-current priority. Sign is converted to this model's
% generator convention Q=v_q*i_d-v_d*i_q (positive injection => negative iq).
verr=max(Vref-V-dbd,0);
iq_support=min(Kqv*verr,Iqh1);
iq_cmd=iq_raw-iq_support;
iq=min(max(iq_cmd,-Imax),Imax);
id_room=sqrt(max(Imax^2-iq^2,0));
id_lvpl=piecewise_lvpl(V,Zerox,Brkpt,Lvpl1);
id_cap=min(id_room,id_lvpl);
id=min(max(id_raw,-id_cap),id_cap);
active=hypot(id-id_raw,iq-iq_raw)>64*eps(max(1,Imax));
end

function value=piecewise_lvpl(V,zero_x,breakpoint,lvpl1)
if V<=zero_x
    value=0;
elseif V>=breakpoint
    value=lvpl1;
else
    value=lvpl1*(V-zero_x)/(breakpoint-zero_x);
end
end

% =========================================================================
function [v_td, v_tq, clamped] = vector_clamp(v_td_raw, v_tq_raw, V_t_max)
% Radial (vector) clamp on [v_td; v_tq] to m_max*Vdc0/2 (user §5.6; eq 8.47).
mag = hypot(v_td_raw, v_tq_raw);
if mag > V_t_max && mag > 0
    scale = V_t_max/mag;
    v_td = v_td_raw*scale;
    v_tq = v_tq_raw*scale;
    clamped = true;
else
    v_td = v_td_raw;
    v_tq = v_tq_raw;
    clamped = mag > V_t_max;   % catches mag==0 with V_t_max<0 (should not occur)
end
end

% =========================================================================
function aw = aw_outer(e, P_cmd, P_lim, limiter_active, aw_tol)
% One-sided conditional hold (outward hold, inward release).
% AW(e)=0 when limiter active AND (P_cmd-P_lim)*e > aw_tol.
if limiter_active && (P_cmd - P_lim)*e > aw_tol
    aw = 0;
else
    aw = e;
end
end

% =========================================================================
function aw = aw_current(e, ki_i, r_v_d, r_v_q, aw_tol, voltage_clamped, axis)
% One-sided conditional hold for the current-loop integrators.
% AW_id(e_d)=0 when voltage clamped AND dot(r_v,[ki_i*e_d;0]) > aw_tol.
% AW_iq(e_q)=0 when voltage clamped AND dot(r_v,[0;ki_i*e_q]) > aw_tol.
% (outward hold, inward release; Bacha p.286 concept, REGFM_B1 conditional_hold form).
if strcmp(axis,'d')
    directional = ki_i*e*r_v_d;
else
    directional = ki_i*e*r_v_q;
end
if voltage_clamped && directional > aw_tol
    aw = 0;
else
    aw = e;
end
end

% =========================================================================
function V = bus_voltage(y,bp)
if numel(y) < 2*bp || any(~isfinite(y(2*bp-1:2*bp)))
    error('ibr:gfl_rms10_model:badNetworkState', ...
        'Network state does not contain a finite voltage for bus position %d.',bp);
end
V = complex(y(2*bp-1),y(2*bp));
end

% =========================================================================
function check_state_input(x,u)
if numel(x) ~= 10 || any(~isfinite(x))
    error('ibr:gfl_rms10_model:badState', ...
        'Expected ten finite GFL-RMS10 states.');
end
if numel(u) ~= 2 || any(~isfinite(u))
    error('ibr:gfl_rms10_model:badInput', ...
        'Expected finite u=[P_ref;Q_ref].');
end
end

% =========================================================================
function validate_bus_mapping(bus_id,bp,bus_ids)
if ~isfinite(bp) || bp ~= floor(bp) || bp < 1 || bp > numel(bus_ids) || ...
        bus_ids(bp) ~= bus_id
    error('ibr:gfl_rms10_model:busMappingMismatch', ...
        'bus_position and bus_id do not identify the same network bus.');
end
end

% =========================================================================
function validate_params(Sbase,Mbase,fbase,omega_b,T_P,T_Q,kp_P,ki_P,kp_Q,ki_Q, ...
    R_t,L,Imax,Vdc0,m_max,V_valid_min,V_div_min,aw_tol,kp_PLL,ki_PLL,kp_i,ki_i)
names = {'Sbase','Mbase','fbase','omega_b','T_P','T_Q','kp_P','ki_P','kp_Q', ...
    'ki_Q','R_t','L','Imax','Vdc0','m_max','V_valid_min','V_div_min','aw_tol', ...
    'kp_PLL','ki_PLL','kp_i','ki_i'};
vals = [Sbase,Mbase,fbase,omega_b,T_P,T_Q,kp_P,ki_P,kp_Q,ki_Q,R_t,L,Imax, ...
    Vdc0,m_max,V_valid_min,V_div_min,aw_tol,kp_PLL,ki_PLL,kp_i,ki_i];
for k = 1:numel(names)
    if ~isscalar(vals(k)) || ~isfinite(vals(k))
        error('ibr:gfl_rms10_model:badParam', ...
            'Parameter %s must be a finite scalar.', names{k});
    end
end

positive = {'Sbase','Mbase','fbase','omega_b','T_P','T_Q','R_t','L','Imax', ...
    'Vdc0','m_max','V_valid_min','V_div_min','kp_PLL','ki_PLL','kp_i','ki_i'};
pvals = struct('Sbase',Sbase,'Mbase',Mbase,'fbase',fbase,'omega_b',omega_b, ...
    'T_P',T_P,'T_Q',T_Q,'R_t',R_t,'L',L,'Imax',Imax,'Vdc0',Vdc0,'m_max',m_max, ...
    'V_valid_min',V_valid_min,'V_div_min',V_div_min, ...
    'kp_PLL',kp_PLL,'ki_PLL',ki_PLL,'kp_i',kp_i,'ki_i',ki_i);
for k = 1:numel(positive)
    if pvals.(positive{k}) <= 0
        error('ibr:gfl_rms10_model:badParam', ...
            'Parameter %s must be positive.', positive{k});
    end
end
end

% =========================================================================
function validate_lvrt_params(Vdip,Kqv,dbd,Iqh1,Zerox,Brkpt,Lvpl1,V_div_min)
names = {'Vdip','Kqv','lvrt_deadband','Iqh1','Zerox','Brkpt','Lvpl1','V_div_min'};
vals = [Vdip,Kqv,dbd,Iqh1,Zerox,Brkpt,Lvpl1,V_div_min];
if any(~isfinite(vals)) || any(~isreal(vals))
    error('ibr:gfl_rms10_model:badLvrtParam', ...
        'All balanced-LVRT parameters must be finite real scalars.');
end
if Vdip <= V_div_min || Vdip > 1.5 || Kqv < 0 || dbd < 0 || ...
        Iqh1 <= 0 || Zerox < V_div_min || Brkpt <= Zerox || ...
        Lvpl1 <= 0
    error('ibr:gfl_rms10_model:badLvrtParam', ...
        ['Invalid balanced-LVRT parameter ordering/value. Require ' ...
         'V_div_min<Vdip<=1.5, Kqv>=0, deadband>=0, Iqh1>0, ' ...
         'V_div_min<=Zerox<Brkpt, and Lvpl1>0.']);
end
for k = 1:numel(names)
    if ~isscalar(vals(k))
        error('ibr:gfl_rms10_model:badLvrtParam', ...
            'Parameter %s must be scalar.',names{k});
    end
end
end
