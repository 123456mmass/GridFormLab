function dev = gfm_reduced6_model(device_id, bus_id, bus_position, ...
    bus_ids, V0, params, P_ref_pu, Q_ref_pu)
%GFM_REDUCED6_MODEL  6-state positive-sequence RMS grid-forming VSG inverter,
%   reduced-order (2 states per block) following the EECON49-P4 formulation.
%
%   dev = gfm_reduced6_model(DEVICE_ID, BUS_ID, BUS_POSITION, BUS_IDS, V0,
%       PARAMS, P_REF_PU, Q_REF_PU) returns a device struct conforming to the
%       stability.composite_dae ABI (R3 Revision 2).
%
%   Reduced-order companion to the 9-state GFM-VSM-Sakimoto model. It keeps the
%   three functional blocks for the EECON49 study -- IBR (current plant), VSG
%   (virtual swing), GFM (voltage forming) -- with two dynamic states per block:
%
%   State order (6, fixed):
%     1 i_d     IBR  d-axis L-filter current             [pu inverter]
%     2 i_q     IBR  q-axis L-filter current             [pu inverter]
%     3 omega   VSG  virtual rotor speed                 [pu]
%     4 delta   VSG  rotor angle (rotor - grid frame)    [rad]
%     5 E       GFM  internal voltage magnitude          [pu]
%     6 xi_V    GFM  d-axis voltage-PI integrator        [pu*s]
%
%   Inputs (nu=2): u = [P_ref; Q_ref] (pu, system base). NO PLL.
%
%   Governing equations (EECON49-P4 eq.22-33 form; VSG + voltage PI + current):
%     Rotor-frame projection: v_gd = Re(V*e^{-j*delta}), v_gq = Im(V*e^{-j*delta}).
%     VSG swing (eq.22-23):
%       d(omega)/dt = (P_ref - P - Dv*(omega - 1))/M
%       d(delta)/dt = omega_b*(omega - 1)
%     GFM voltage forming (eq.24-29; reactance-coupled cross pairing):
%       d(E)/dt    = (kQ*(Q_ref - Q) - kE*(E - |V|))/tau_E     (Q-V droop dynamics)
%       d(xi_V)/dt = E - v_gd                                   (d-axis volt error)
%       i_q_ref = -( kp_V*(E - v_gd) + ki_V*xi_V )   (reactive current forms |V|)
%       i_d_ref =    kp_V*(0 - v_gq)                 (active current, synchronizing)
%     (On a reactance-dominated coupling v_gd = E + X*i_q and v_gq = -X*i_d, so
%      the d-axis magnitude error must drive i_q and the q-axis error i_d; a
%      same-axis pairing makes the voltage loop unstable.)
%     IBR current plant (proportional current control + decoupling):
%       v_td = kp_i*(i_d_ref - i_d) + R_t*i_d - omega*L*i_q + v_gd
%       v_tq = kp_i*(i_q_ref - i_q) + R_t*i_q + omega*L*i_d + v_gq
%       (L/omega_b) d(i_d)/dt = omega*L*i_q - R_t*i_d + v_td - v_gd
%       (L/omega_b) d(i_q)/dt = -omega*L*i_d - R_t*i_q + v_tq - v_gq
%     Network injection: I_net = (i_d + j*i_q)*e^{j*delta}/kappa (system base);
%       P = Re(V*conj(I_net)); Q = Im(V*conj(I_net)); P_inv = kappa*P etc.
%
%   NO PLL: the rotor angle comes only from the swing integrator (synchronizing
%   power). With the EECON49 gains (M=0.08, Dv=1.50) the swing loop is
%   underdamped and yields a COMPLEX electromechanical pole pair.
%
%   Equilibrium (closed form): omega0=1; the q-axis-error active-current law
%   i_d = -kp_V*v_gq pins delta0 via (Ar+Bi)cos(delta)+(Ai-Br)sin(delta)=0 with
%   A=kappa*I_net, B=kp_V*V, I_net=conj((P_ref+jQ_ref)/V). Then E0=v_gd0,
%   xi_V0=-i_q0/ki_V, and the Q-V droop reference is back-solved so d(E)/dt=0
%   exactly (mirrors the Sakimoto device's consistent-Q back-solve).
%
%   Sources: EECON49-P4 (KMITL) GFM/VSG formulation eq.(22)-(33) + simulation
%   parameter table. Classification: PROJECT_DERIVED_SOURCE_MAPPED (reduced-order
%   assembly). STATUS: SOURCE_IMPLEMENTED_PENDING_SMIB_GATES.

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
    error('ibr:gfm_reduced6_model:badV0','V0 must be a finite nonzero bus-voltage phasor.');
end
if ~isfinite(P_ref_pu) || ~isfinite(Q_ref_pu) || ~isreal(P_ref_pu) || ~isreal(Q_ref_pu)
    error('ibr:gfm_reduced6_model:badRef','P_ref_pu and Q_ref_pu must be finite real system-base values.');
end

% --- Frozen numerical parameter profile (EECON49-P4 simulation table) ------
Sbase = 100.0;  if isfield(params,'Sbase') && ~isempty(params.Sbase), Sbase = params.Sbase; end
Mbase = 100.0;  if isfield(params,'Mbase') && ~isempty(params.Mbase), Mbase = params.Mbase; end
fbase = 60.0;   if isfield(params,'fbase') && ~isempty(params.fbase), fbase = params.fbase; end
omega_b = 2*pi*fbase;

g = struct();
if isfield(params,'gfm_reduced6') && isstruct(params.gfm_reduced6)
    g = params.gfm_reduced6;
end

% VSG swing (EECON49-P4: M=0.08 s, Dv=1.50 pu).
M   = 0.08;  if isfield(g,'M')   && ~isempty(g.M),   M   = g.M;   end
Dv  = 1.50;  if isfield(g,'Dv')  && ~isempty(g.Dv),  Dv  = g.Dv;  end

% GFM voltage forming (EECON49-P4: tau_E=0.05 s, kQ=0.25, kE=8.00).
tau_E = 0.05;  if isfield(g,'tau_E') && ~isempty(g.tau_E), tau_E = g.tau_E; end
kQ    = 0.25;  if isfield(g,'kQ')    && ~isempty(g.kQ),    kQ    = g.kQ;    end
kE    = 8.00;  if isfield(g,'kE')    && ~isempty(g.kE),    kE    = g.kE;    end

% Voltage-loop PI (EECON49-P4: kp_Vd=1.20, ki_Vd=4.50).
kp_V = 1.20;  if isfield(g,'kp_V') && ~isempty(g.kp_V), kp_V = g.kp_V; end
ki_V = 4.50;  if isfield(g,'ki_V') && ~isempty(g.ki_V), ki_V = g.ki_V; end

% Inner current loop (proportional; EECON49-P4: kp_Id=0.30).
kp_i = 0.30;  if isfield(g,'kp_i') && ~isempty(g.kp_i), kp_i = g.kp_i; end

% L-filter (EECON49-P4: Lf=0.15, Rf=0.015 pu). L is a per-unit reactance.
R_t = 0.015;  if isfield(g,'R_t') && ~isempty(g.R_t), R_t = g.R_t; end
L   = 0.15;   if isfield(g,'L')   && ~isempty(g.L),   L   = g.L;   end

V_div_min = 1e-6; if isfield(g,'V_div_min') && ~isempty(g.V_div_min), V_div_min = g.V_div_min; end

validate_params(Sbase,Mbase,fbase,omega_b,M,Dv,tau_E,kQ,kE,kp_V,ki_V,kp_i,R_t,L,V_div_min);
reject_unsupported_options(g);

kappa = Sbase/Mbase;
bp = bus_position;

% --- Equilibrium (closed form + back-solved droop reference) ---------------
[x0, Q_ref_solved] = equilibrium_state(V0, P_ref_pu, Q_ref_pu, kappa, ...
    kp_V, ki_V, kQ, kE, V_div_min);
u0 = [P_ref_pu; Q_ref_solved];

f = @(t,x,y,u,ec) model_f(x,y,u,bp,kappa,omega_b,M,Dv,tau_E,kQ,kE,kp_V,ki_V,kp_i,R_t,L,V_div_min);
current_injection = @(t,x,y,u,ec) model_current(x,y,bp,kappa,V_div_min);
electrical_power  = @(t,x,y,u,ec) model_power(x,y,bp,kappa,V_div_min);
reconstruct = @(t,x,y,u,ec) model_reconstruct(x,y,u,bp,kappa,omega_b,M,Dv,tau_E,kQ,kE,kp_V,ki_V,kp_i,R_t,L,V_div_min,Sbase,Mbase);
equilibrium_initialize = @(V,P,Q,ec) first_output( ...
    @() equilibrium_state(V,P,Q,kappa,kp_V,ki_V,kQ,kE,V_div_min));

dev = struct();
dev.name = char(device_id);
dev.device_id = char(device_id);
dev.bus_id = bus_id;
dev.bus_position = bus_position;
dev.bus_ids = bus_ids(:).';
dev.device_type = 'ibr_gfm_reduced6';
dev.mode = 'GFM';
dev.nx = numel(x0);
dev.nu = 2;
dev.state_names = {'i_d','i_q','omega','delta','E','xi_V'};
dev.input_names = {'P_ref','Q_ref'};
dev.x0 = x0;
dev.u0 = u0;
dev.f = f;
dev.current_injection = current_injection;
dev.electrical_power = electrical_power;
dev.reconstruct = reconstruct;
dev.equilibrium_initialize = equilibrium_initialize;
dev.active_state_indices = @(ec) 1:6;
dev.provenance = struct( ...
    'model','GFM_REDUCED6_PROJECT_DERIVED_SOURCE_MAPPED', ...
    'source','EECON49-P4 (KMITL) GFM/VSG formulation eq.(22)-(33) + simulation parameter table', ...
    'source_classification', ...
        'PROJECT_DERIVED_SOURCE_MAPPED reduced-order (6 states, 2 per block IBR/VSG/GFM); NO PLL', ...
    'control_option','VSG swing + Q-V droop voltage forming + d-axis voltage PI + proportional dq current control; no limiter', ...
    'pu_base_contract','internal=inverter base; external=system base; kappa=Sbase/Mbase', ...
    'angle_contract','runtime rotor angle ONLY from swing integrator; never from angle(V)', ...
    'params',struct('Sbase',Sbase,'Mbase',Mbase,'fbase',fbase,'omega_b',omega_b, ...
        'M',M,'Dv',Dv,'tau_E',tau_E,'kQ',kQ,'kE',kE,'kp_V',kp_V,'ki_V',ki_V, ...
        'kp_i',kp_i,'R_t',R_t,'L',L,'V_div_min',V_div_min,'kappa',kappa), ...
    'readiness','SOURCE_IMPLEMENTED_PENDING_SMIB_GATES');
end

% =========================================================================
function dx = model_f(x,y,u,bp,kappa,omega_b,M,Dv,tau_E,kQ,kE,kp_V,ki_V,kp_i,R_t,L,V_div_min)
check_state_input(x,u);
V = bus_voltage(y,bp,V_div_min);
Vmag = abs(V);

i_d = x(1); i_q = x(2); omega = x(3); delta = x(4); E = x(5); xi_V = x(6);

P_ref_inv = kappa*u(1);
Q_ref_inv = kappa*u(2);

% Rotor-frame terminal voltage.
Vdq = V*exp(-1i*delta);
v_gd = real(Vdq);
v_gq = imag(Vdq);

% Injected power (generator convention).
I_net = (complex(i_d,i_q)*exp(1i*delta))/kappa;
S = V*conj(I_net);
P_inv = kappa*real(S);
Q_inv = kappa*imag(S);

% --- VSG swing (EECON49-P4 eq.22-23) ---------------------------------------
d_omega = (P_ref_inv - P_inv - Dv*(omega - 1.0))/M;
d_delta = omega_b*(omega - 1.0);

% --- GFM voltage forming (EECON49-P4 eq.24-29; reactance-coupled pairing) --
% On a reactance-dominated coupling the terminal d-axis voltage v_gd is
% controlled by the q-axis (reactive) current and v_gq by the d-axis (active)
% current: v_gd = E + X*i_q, v_gq = -X*i_d (EMF-oriented). Hence the voltage
% PI must be CROSS-paired: the d-axis magnitude error drives i_q, the q-axis
% error drives i_d. (A same-axis pairing makes the voltage loop unstable.)
d_E    = (kQ*(Q_ref_inv - Q_inv) - kE*(E - Vmag))/tau_E;
e_vd = E - v_gd;        % d-axis voltage error (regulate v_gd -> E)
e_vq = 0.0 - v_gq;      % q-axis voltage error (regulate v_gq -> 0)
d_xi_V = e_vd;
i_q_ref = -(kp_V*e_vd + ki_V*xi_V);   % reactive current forms the voltage magnitude
i_d_ref = kp_V*e_vq;                   % active current from the q-axis error (synchronizing)

% --- IBR current plant (proportional current control + decoupling) ---------
e_d = i_d_ref - i_d;
e_q = i_q_ref - i_q;
v_td = kp_i*e_d + R_t*i_d - omega*L*i_q + v_gd;
v_tq = kp_i*e_q + R_t*i_q + omega*L*i_d + v_gq;
d_i_d = (omega*L*i_q - R_t*i_d + v_td - v_gd)/(L/omega_b);
d_i_q = (-omega*L*i_d - R_t*i_q + v_tq - v_gq)/(L/omega_b);

dx = [d_i_d; d_i_q; d_omega; d_delta; d_E; d_xi_V];
if any(~isfinite(dx))
    error('ibr:gfm_reduced6_model:nonfiniteRhs','GFM-reduced6 RHS produced a non-finite value.');
end
end

% =========================================================================
function I = model_current(x,y,bp,kappa,V_div_min)
if numel(x) ~= 6 || any(~isfinite(x))
    error('ibr:gfm_reduced6_model:badState','Expected six finite GFM-reduced6 states.');
end
V = bus_voltage(y,bp,V_div_min); %#ok<NASGU>
i_d = x(1); i_q = x(2); delta = x(4);
I = (complex(i_d,i_q)*exp(1i*delta))/kappa;
if ~isfinite(I)
    error('ibr:gfm_reduced6_model:nonfiniteCurrent','GFM-reduced6 current injection non-finite.');
end
end

% =========================================================================
function Pe = model_power(x,y,bp,kappa,V_div_min)
V = bus_voltage(y,bp,V_div_min);
I = model_current(x,y,bp,kappa,V_div_min);
Pe = real(V*conj(I));
end

% =========================================================================
function out = model_reconstruct(x,y,u,bp,kappa,omega_b,M,Dv,tau_E,kQ,kE,kp_V,ki_V,kp_i,R_t,L,V_div_min,Sbase,Mbase)
check_state_input(x,u);
V = bus_voltage(y,bp,V_div_min);
i_d = x(1); i_q = x(2); omega = x(3); delta = x(4); E = x(5); xi_V = x(6);
Vdq = V*exp(-1i*delta); v_gd = real(Vdq); v_gq = imag(Vdq);
I_net = (complex(i_d,i_q)*exp(1i*delta))/kappa;
S = V*conj(I_net);
out = struct( ...
    'i_d',i_d,'i_q',i_q,'omega',omega,'delta',delta,'E',E,'xi_V',xi_V, ...
    'v_gd',v_gd,'v_gq',v_gq,'omega_pu',omega, ...
    'f_hz',(omega_b/(2*pi))*omega, ...
    'I_sys',I_net,'I_inv',I_net*kappa, ...
    'Pe',real(S),'Qe',imag(S),'P_inv_meas',kappa*real(S),'Q_inv_meas',kappa*imag(S), ...
    'Vbus',abs(V),'Vbus_phasor',V, ...
    'P_ref_inv',kappa*u(1),'Q_ref_inv',kappa*u(2), ...
    'kappa',kappa,'Sbase',Sbase,'Mbase',Mbase, ...
    'M',M,'Dv',Dv,'tau_E',tau_E,'kQ',kQ,'kE',kE,'kp_V',kp_V,'ki_V',ki_V, ...
    'kp_i',kp_i,'R_t',R_t,'L',L, ...
    'readiness','SOURCE_IMPLEMENTED_PENDING_SMIB_GATES');
end

% =========================================================================
function [xeq, Q_ref_pu_solved] = equilibrium_state(V,Psys,Qsys,kappa,kp_V,ki_V,kQ,kE,V_div_min)
if ~isscalar(V) || ~isfinite(V) || abs(V) <= 0 || ...
        ~isscalar(Psys) || ~isscalar(Qsys) || ~isfinite(Psys) || ~isfinite(Qsys)
    error('ibr:gfm_reduced6_model:equilibriumInput', ...
        'Equilibrium V/P/Q must be finite scalar values with |V|>0.');
end
Vmag = abs(V);
if Vmag < V_div_min
    error('ibr:gfm_reduced6_model:equilibriumLowVoltage', ...
        '|V|=%.6g < V_div_min=%.6g; equilibrium fail-closed.', Vmag, V_div_min);
end
% Injected current (system base) required to deliver P+jQ at terminal V.
I_net = conj((Psys + 1i*Qsys)/V);
% delta pinned by the q-axis-error active-current law i_d = -kp_V*v_gq:
%   real(kappa*I_net*e^{-j*delta}) + kp_V*imag(V*e^{-j*delta}) = 0
%   -> (Ar+Bi)cos(delta) + (Ai-Br)sin(delta) = 0, A=kappa*I_net, B=kp_V*V.
A = kappa*I_net;   B = kp_V*V;
Cc = real(A) + imag(B);
Dd = imag(A) - real(B);
if abs(Cc) < 1e-300 && abs(Dd) < 1e-300
    error('ibr:gfm_reduced6_model:equilibriumDegenerate', ...
        'Degenerate equilibrium (voltage-current pinning ill-defined); fail-closed.');
end
delta0 = atan2(-Cc, Dd);
% Pick the branch giving a physical positive d-axis voltage magnitude E0>0.
if real(V*exp(-1i*delta0)) < 0
    delta0 = delta0 + pi;
end
delta0 = atan2(sin(delta0), cos(delta0));   % wrap to (-pi,pi]
Vdq0 = V*exp(-1i*delta0);
v_gd0 = real(Vdq0);
v_gq0 = imag(Vdq0);
i_rot0 = kappa*I_net*exp(-1i*delta0);   % = i_d0 + j*i_q0
i_d0 = real(i_rot0);
i_q0 = imag(i_rot0);
E0 = v_gd0;                     % d(xi_V)/dt = 0 -> E = v_gd
xi_V0 = -i_q0/ki_V;             % i_q_ref = -ki_V*xi_V0 = i_q0 (since E-v_gd=0)
omega0 = 1.0;
% Back-solve the Q-V droop reference so d(E)/dt = 0 exactly:
%   kQ*(Q_ref_inv - Q_inv) - kE*(E0 - |V|) = 0, with Q_inv = kappa*Qsys.
Q_inv0 = kappa*Qsys;
Q_ref_inv0 = Q_inv0 + kE*(E0 - Vmag)/kQ;
Q_ref_pu_solved = Q_ref_inv0/kappa;
xeq = [i_d0; i_q0; omega0; delta0; E0; xi_V0];
if any(~isfinite(xeq))
    error('ibr:gfm_reduced6_model:equilibriumNonfinite', ...
        'Reconstructed GFM-reduced6 equilibrium contains non-finite values.');
end
end

% =========================================================================
function y = first_output(fn)
[y,~] = fn();
end

% =========================================================================
function check_state_input(x,u)
if numel(x) ~= 6 || any(~isfinite(x))
    error('ibr:gfm_reduced6_model:badState','Expected six finite GFM-reduced6 states.');
end
if numel(u) ~= 2 || any(~isfinite(u))
    error('ibr:gfm_reduced6_model:badInput','Expected finite u=[P_ref;Q_ref].');
end
end

% =========================================================================
function V = bus_voltage(y,bp,V_div_min)
if numel(y) < 2*bp || any(~isfinite(y(2*bp-1:2*bp)))
    error('ibr:gfm_reduced6_model:badNetworkState', ...
        'Network state does not contain a finite voltage for bus position %d.',bp);
end
V = complex(y(2*bp-1),y(2*bp));
if abs(V) < V_div_min
    error('ibr:gfm_reduced6_model:lowVoltageDomain', ...
        '|V|=%.6g < V_div_min=%.6g; balanced positive-sequence domain violated.',abs(V),V_div_min);
end
end

% =========================================================================
function validate_bus_mapping(bus_id,bp,bus_ids)
if ~isfinite(bp) || bp ~= floor(bp) || bp < 1 || bp > numel(bus_ids) || bus_ids(bp) ~= bus_id
    error('ibr:gfm_reduced6_model:busMappingMismatch', ...
        'bus_position and bus_id do not identify the same network bus.');
end
end

% =========================================================================
function validate_params(Sbase,Mbase,fbase,omega_b,M,Dv,tau_E,kQ,kE,kp_V,ki_V,kp_i,R_t,L,V_div_min)
names = {'Sbase','Mbase','fbase','omega_b','M','Dv','tau_E','kQ','kE','kp_V','ki_V','kp_i','R_t','L','V_div_min'};
vals  = [Sbase,Mbase,fbase,omega_b,M,Dv,tau_E,kQ,kE,kp_V,ki_V,kp_i,R_t,L,V_div_min];
for k = 1:numel(names)
    if ~isscalar(vals(k)) || ~isfinite(vals(k))
        error('ibr:gfm_reduced6_model:badParam','Parameter %s must be a finite scalar.',names{k});
    end
end
positive = {'Sbase','Mbase','fbase','omega_b','M','tau_E','kQ','ki_V','kp_i','L','V_div_min'};
pvals = struct('Sbase',Sbase,'Mbase',Mbase,'fbase',fbase,'omega_b',omega_b,'M',M, ...
    'tau_E',tau_E,'kQ',kQ,'ki_V',ki_V,'kp_i',kp_i,'L',L,'V_div_min',V_div_min);
for k = 1:numel(positive)
    if pvals.(positive{k}) <= 0
        error('ibr:gfm_reduced6_model:badParam','Parameter %s must be positive.',positive{k});
    end
end
if R_t < 0 || Dv < 0 || kE < 0
    error('ibr:gfm_reduced6_model:badParam','R_t, Dv, kE must be non-negative.');
end
end

% =========================================================================
function reject_unsupported_options(g)
forbidden = {'kp_PLL','ki_PLL','delta_PLL','xi_PLL','x_gov','T_m','x_d','ki_i','Imax','ts_pll'};
for k = 1:numel(forbidden)
    if isfield(g,forbidden{k})
        error('ibr:gfm_reduced6_model:unsupportedOption', ...
            ['Parameter %s is not supported by the reduced 6-state GFM model ' ...
             '(no PLL, no governor/turbine/damper, no current-PI integrator, no limiter).'], forbidden{k});
    end
end
end
