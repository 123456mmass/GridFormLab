function dev = gfl_reduced6_model(device_id, bus_id, bus_position, ...
    bus_ids, V0, params, P_ref_pu, Q_ref_pu)
%GFL_REDUCED6_MODEL  6-state positive-sequence RMS grid-following inverter,
%   reduced-order (2 states per block) following the EECON49-P4 formulation.
%
%   dev = gfl_reduced6_model(DEVICE_ID, BUS_ID, BUS_POSITION, BUS_IDS, V0,
%       PARAMS, P_REF_PU, Q_REF_PU) returns a device struct conforming to the
%       stability.composite_dae ABI (R3 Revision 2): f, current_injection,
%       electrical_power, reconstruct, equilibrium_initialize, state_names,
%       input_names, nx, nu, active_state_indices, provenance.
%
%   This is a REDUCED-ORDER companion to the 10-state GFL-RMS10 model. It keeps
%   the three functional blocks requested for the EECON49 study -- IBR (current
%   plant), GFL (PLL synchronization), PQ (outer power control) -- with exactly
%   two dynamic states per block:
%
%   State order (6, fixed):
%     1 i_d       IBR  d-axis L-filter current            [pu inverter]
%     2 i_q       IBR  q-axis L-filter current            [pu inverter]
%     3 delta_PLL GFL  SRF-PLL angle (rotor-frame)         [rad]
%     4 xi_PLL    GFL  PLL PI integrator                   [pu*s]
%     5 xi_P      PQ   active-power outer-PI integrator    [pu*s]
%     6 xi_Q      PQ   reactive-power outer-PI integrator  [pu*s]
%
%   Inputs (nu=2): u = [P_ref; Q_ref] (pu, system base).
%
%   REDUCTION vs GFL-RMS10 (documented, PROJECT_DERIVED):
%     - P/Q measurement filters (P_f,Q_f) removed -> power measured
%       algebraically (instantaneous).
%     - Current-PI integrators (xi_id,xi_iq) removed -> the inner current loop
%       is proportional + decoupling feedforward (fast first-order tracking).
%       The decoupling/feedforward cancels the cross terms so the plant reduces
%       to d(i)/dt = kp_i*(i_ref - i)*omega_b/L (a stable real current mode).
%     - No current limiter / anti-windup / LVRT in this reduced study model.
%
%   PLL (EECON49-P4 eq.9-11 form; SOURCE-CORRECT, NO spurious omega_b factor):
%     omega_PLL = omega0 + kp_PLL*v_q + ki_PLL*xi_PLL     (rad/s, added to omega0)
%     d(delta_PLL)/dt = omega_PLL - omega0 = kp_PLL*v_q + ki_PLL*xi_PLL   [rad/s]
%     d(xi_PLL)/dt    = v_q
%   Unlike the 10-state model this multiplies NOTHING by omega_b: the PI output
%   IS the rad/s frequency deviation. With the EECON49 gains (kp_PLL=1.20,
%   ki_PLL=5.00) the 2-state PLL loop is underdamped (zeta~0.27) and yields a
%   COMPLEX pole pair ~ -0.6 +/- j2.15 (f~0.34 Hz) -- the physically expected
%   oscillatory synchronization mode. (The 10-state GFL-RMS10 used a mis-scaled
%   kp = 9.2/ts^2 plus an extra omega_b factor, giving zeta~43 and an all-real,
%   ~-3.4e5 spectrum; see the PLL defect record.)
%
%   PQ outer loop (EECON49-P4 eq.12-15):
%     P = Re(V*conj(I_net)); Q = Im(V*conj(I_net))   (algebraic, no filter)
%     d(xi_P)/dt = P_ref - P ;  d(xi_Q)/dt = Q_ref - Q
%     i_d_ref = kp_P*(P_ref - P) + ki_P*xi_P
%     i_q_ref = -( kp_Q*(Q_ref - Q) + ki_Q*xi_Q )
%
%   IBR current plant (proportional current control; Yazdani L-filter form):
%     Vdq = V*exp(-1i*delta_PLL); v_d = Re, v_q = Im (Yazdani eq 8.1)
%     v_td = kp_i*(i_d_ref - i_d) + R_t*i_d - omega_PLL_pu*L*i_q + v_d
%     v_tq = kp_i*(i_q_ref - i_q) + R_t*i_q + omega_PLL_pu*L*i_d + v_q
%     (L/omega_b) d(i_d)/dt = omega_PLL_pu*L*i_q - R_t*i_d + v_td - v_d
%     (L/omega_b) d(i_q)/dt = -omega_PLL_pu*L*i_d - R_t*i_q + v_tq - v_q
%
%   Per-unit base contract (identical to GFL-RMS10): kappa = Sbase/Mbase;
%   internal states on inverter base; current_injection/electrical_power return
%   system base; L is a per-unit COUPLING REACTANCE; omega_b = 2*pi*fbase.
%
%   Sources: EECON49-P4 (KMITL) GFL formulation eq.(6)-(15),(18)-(19) and its
%   simulation parameter table; underlying current-loop/PLL equations trace to
%   Yazdani & Iravani 2010 and Teodorescu et al. 2011. Classification:
%   PROJECT_DERIVED_SOURCE_MAPPED (reduced-order assembly of sourced blocks).
%
%   STATUS: SOURCE_IMPLEMENTED_PENDING_SMIB_GATES.

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
    error('ibr:gfl_reduced6_model:badV0', ...
        'V0 must be a finite nonzero bus-voltage phasor.');
end
if ~isfinite(P_ref_pu) || ~isfinite(Q_ref_pu) || ~isreal(P_ref_pu) || ~isreal(Q_ref_pu)
    error('ibr:gfl_reduced6_model:badRef', ...
        'P_ref_pu and Q_ref_pu must be finite real system-base values.');
end

% --- Frozen numerical parameter profile (EECON49-P4 simulation table) ------
Sbase = 100.0;  if isfield(params,'Sbase') && ~isempty(params.Sbase), Sbase = params.Sbase; end
Mbase = 100.0;  if isfield(params,'Mbase') && ~isempty(params.Mbase), Mbase = params.Mbase; end
fbase = 60.0;   if isfield(params,'fbase') && ~isempty(params.fbase), fbase = params.fbase; end
omega_b = 2*pi*fbase;

g = struct();
if isfield(params,'gfl_reduced6') && isstruct(params.gfl_reduced6)
    g = params.gfl_reduced6;
end

% PLL (EECON49-P4: kp,PLL=1.20, ki,PLL=5.00; rad/s form, NO omega_b factor).
kp_PLL = 1.20;  if isfield(g,'kp_PLL') && ~isempty(g.kp_PLL), kp_PLL = g.kp_PLL; end
ki_PLL = 5.00;  if isfield(g,'ki_PLL') && ~isempty(g.ki_PLL), ki_PLL = g.ki_PLL; end

% PQ outer loop (EECON49-P4: kp_P=kp_Q=0.80, ki_P=ki_Q=2.50).
kp_P = 0.80;  if isfield(g,'kp_P') && ~isempty(g.kp_P), kp_P = g.kp_P; end
ki_P = 2.50;  if isfield(g,'ki_P') && ~isempty(g.ki_P), ki_P = g.ki_P; end
kp_Q = 0.80;  if isfield(g,'kp_Q') && ~isempty(g.kp_Q), kp_Q = g.kp_Q; end
ki_Q = 2.50;  if isfield(g,'ki_Q') && ~isempty(g.ki_Q), ki_Q = g.ki_Q; end

% Inner current loop (proportional; EECON49-P4: kp_Id=kp_Iq=0.30).
kp_i = 0.30;  if isfield(g,'kp_i') && ~isempty(g.kp_i), kp_i = g.kp_i; end

% L-filter (EECON49-P4: Lf=0.15, Rf=0.015 pu). L is a per-unit reactance.
R_t = 0.015;  if isfield(g,'R_t') && ~isempty(g.R_t), R_t = g.R_t; end
L   = 0.15;   if isfield(g,'L')   && ~isempty(g.L),   L   = g.L;   end

% Low-voltage division floor (PROJECT_DERIVED, fail-closed).
V_div_min = 1e-6; if isfield(g,'V_div_min') && ~isempty(g.V_div_min), V_div_min = g.V_div_min; end

validate_params(Sbase,Mbase,fbase,omega_b,kp_PLL,ki_PLL,kp_P,ki_P,kp_Q,ki_Q,kp_i,R_t,L,V_div_min);
reject_unsupported_options(g);

kappa = Sbase/Mbase;
bp = bus_position;

% --- Equilibrium initial state (closed form; residuals exactly zero) -------
% delta_PLL0 = angle(V0) (so v_q0=0); i_d0=P_ref_inv/|V0|, i_q0=-Q_ref_inv/|V0|
% (so P0=P_ref_inv, Q0=Q_ref_inv); xi_PLL0=0; the outer-PI integrators hold the
% current references: i_d_ref0=ki_P*xi_P0=i_d0 and i_q_ref0=-ki_Q*xi_Q0=i_q0.
[x0, ~] = equilibrium_state(V0, P_ref_pu, Q_ref_pu, kappa, ki_P, ki_Q, V_div_min);
u0 = [P_ref_pu; Q_ref_pu];

% --- Closures (generic ABI) ------------------------------------------------
f = @(t,x,y,u,ec) model_f(x,y,u,bp,kappa,omega_b,kp_PLL,ki_PLL, ...
    kp_P,ki_P,kp_Q,ki_Q,kp_i,R_t,L,V_div_min);
current_injection = @(t,x,y,u,ec) model_current(x,y,bp,kappa,V_div_min);
electrical_power  = @(t,x,y,u,ec) model_power(x,y,bp,kappa,V_div_min);
reconstruct = @(t,x,y,u,ec) model_reconstruct(x,y,u,bp,kappa,omega_b,kp_PLL,ki_PLL, ...
    kp_P,ki_P,kp_Q,ki_Q,kp_i,R_t,L,V_div_min,Sbase,Mbase);
equilibrium_initialize = @(V,P,Q,ec) first_output( ...
    @() equilibrium_state(V,P,Q,kappa,ki_P,ki_Q,V_div_min));

dev = struct();
dev.name = char(device_id);
dev.device_id = char(device_id);
dev.bus_id = bus_id;
dev.bus_position = bus_position;
dev.bus_ids = bus_ids(:).';
dev.device_type = 'ibr_gfl_reduced6';
dev.mode = 'gfl';
dev.nx = numel(x0);
dev.nu = 2;
dev.state_names = {'i_d','i_q','delta_PLL','xi_PLL','xi_P','xi_Q'};
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
    'model','GFL_REDUCED6_PROJECT_DERIVED_SOURCE_MAPPED', ...
    'source',['EECON49-P4 (KMITL) GFL formulation eq.(6)-(15),(18)-(19) + simulation ' ...
              'parameter table; underlying blocks trace to Yazdani-Iravani 2010 and ' ...
              'Teodorescu et al. 2011'], ...
    'source_classification', ...
        'PROJECT_DERIVED_SOURCE_MAPPED reduced-order (6 states, 2 per block IBR/GFL/PQ); PLL uses EECON49 rad/s form (no omega_b)', ...
    'control_option','SRF-PLL + PQ outer PI + proportional dq current control; no limiter/LVRT (reduced study model)', ...
    'pu_base_contract','internal=inverter base; external=system base; kappa=Sbase/Mbase', ...
    'angle_contract','runtime frame angle from delta_PLL PLL loop', ...
    'params',struct('Sbase',Sbase,'Mbase',Mbase,'fbase',fbase,'omega_b',omega_b, ...
        'kp_PLL',kp_PLL,'ki_PLL',ki_PLL,'kp_P',kp_P,'ki_P',ki_P,'kp_Q',kp_Q,'ki_Q',ki_Q, ...
        'kp_i',kp_i,'R_t',R_t,'L',L,'V_div_min',V_div_min,'kappa',kappa), ...
    'readiness','SOURCE_IMPLEMENTED_PENDING_SMIB_GATES');
end

% =========================================================================
function dx = model_f(x,y,u,bp,kappa,omega_b,kp_PLL,ki_PLL,kp_P,ki_P,kp_Q,ki_Q,kp_i,R_t,L,V_div_min)
check_state_input(x,u);
V = bus_voltage(y,bp,V_div_min);

i_d = x(1); i_q = x(2); delta_PLL = x(3); xi_PLL = x(4); xi_P = x(5); xi_Q = x(6);

P_ref_inv = kappa*u(1);
Q_ref_inv = kappa*u(2);

% dq voltage in the PLL frame (Yazdani eq 8.1: v_q=+Im).
Vdq = V*exp(-1i*delta_PLL);
v_d = real(Vdq);
v_q = imag(Vdq);

% Measured inverter-base power (generator convention S=V*conj(I)).
I_net = (complex(i_d,i_q)*exp(1i*delta_PLL))/kappa;
S = V*conj(I_net);
P_inv = kappa*real(S);
Q_inv = kappa*imag(S);

% --- PLL (EECON49-P4 eq.9-11; rad/s form, NO omega_b factor) ---------------
Delta_omega = kp_PLL*v_q + ki_PLL*xi_PLL;   % [rad/s] frequency deviation
d_delta_PLL = Delta_omega;                   % [rad/s]
d_xi_PLL    = v_q;
omega_PLL_pu = 1.0 + Delta_omega/omega_b;    % [pu] for decoupling term

% --- PQ outer loop (EECON49-P4 eq.12-15; algebraic power, no filter) -------
e_P = P_ref_inv - P_inv;
e_Q = Q_ref_inv - Q_inv;
d_xi_P = e_P;
d_xi_Q = e_Q;
i_d_ref = kp_P*e_P + ki_P*xi_P;
i_q_ref = -(kp_Q*e_Q + ki_Q*xi_Q);

% --- IBR current plant (proportional current control + decoupling) ---------
e_d = i_d_ref - i_d;
e_q = i_q_ref - i_q;
v_td = kp_i*e_d + R_t*i_d - omega_PLL_pu*L*i_q + v_d;
v_tq = kp_i*e_q + R_t*i_q + omega_PLL_pu*L*i_d + v_q;
d_i_d = (omega_PLL_pu*L*i_q - R_t*i_d + v_td - v_d)/(L/omega_b);
d_i_q = (-omega_PLL_pu*L*i_d - R_t*i_q + v_tq - v_q)/(L/omega_b);

dx = [d_i_d; d_i_q; d_delta_PLL; d_xi_PLL; d_xi_P; d_xi_Q];
if any(~isfinite(dx))
    error('ibr:gfl_reduced6_model:nonfiniteRhs','GFL-reduced6 RHS produced a non-finite value.');
end
end

% =========================================================================
function I = model_current(x,y,bp,kappa,V_div_min)
if numel(x) ~= 6 || any(~isfinite(x))
    error('ibr:gfl_reduced6_model:badState','Expected six finite GFL-reduced6 states.');
end
V = bus_voltage(y,bp,V_div_min); %#ok<NASGU>
i_d = x(1); i_q = x(2); delta_PLL = x(3);
I = (complex(i_d,i_q)*exp(1i*delta_PLL))/kappa;
if ~isfinite(I)
    error('ibr:gfl_reduced6_model:nonfiniteCurrent','GFL-reduced6 current injection non-finite.');
end
end

% =========================================================================
function Pe = model_power(x,y,bp,kappa,V_div_min)
V = bus_voltage(y,bp,V_div_min);
I = model_current(x,y,bp,kappa,V_div_min);
Pe = real(V*conj(I));
end

% =========================================================================
function out = model_reconstruct(x,y,u,bp,kappa,omega_b,kp_PLL,ki_PLL, ...
    kp_P,ki_P,kp_Q,ki_Q,kp_i,R_t,L,V_div_min,Sbase,Mbase)
check_state_input(x,u);
V = bus_voltage(y,bp,V_div_min);
i_d = x(1); i_q = x(2); delta_PLL = x(3); xi_PLL = x(4); xi_P = x(5); xi_Q = x(6);
Vdq = V*exp(-1i*delta_PLL); v_d = real(Vdq); v_q = imag(Vdq);
I_net = (complex(i_d,i_q)*exp(1i*delta_PLL))/kappa;
S = V*conj(I_net);
Delta_omega = kp_PLL*v_q + ki_PLL*xi_PLL;
out = struct( ...
    'i_d',i_d,'i_q',i_q,'delta_PLL',delta_PLL,'xi_PLL',xi_PLL,'xi_P',xi_P,'xi_Q',xi_Q, ...
    'v_d',v_d,'v_q',v_q,'omega_PLL',omega_b+Delta_omega,'omega_PLL_pu',1.0+Delta_omega/omega_b, ...
    'f_hz',(omega_b+Delta_omega)/(2*pi), ...
    'I_sys',I_net,'I_inv',I_net*kappa, ...
    'Pe',real(S),'Qe',imag(S),'P_inv_meas',kappa*real(S),'Q_inv_meas',kappa*imag(S), ...
    'Vbus',abs(V),'Vbus_phasor',V, ...
    'P_ref_inv',kappa*u(1),'Q_ref_inv',kappa*u(2), ...
    'kappa',kappa,'Sbase',Sbase,'Mbase',Mbase, ...
    'kp_PLL',kp_PLL,'ki_PLL',ki_PLL,'kp_P',kp_P,'ki_P',ki_P,'kp_Q',kp_Q,'ki_Q',ki_Q, ...
    'kp_i',kp_i,'R_t',R_t,'L',L, ...
    'readiness','SOURCE_IMPLEMENTED_PENDING_SMIB_GATES');
end

% =========================================================================
function [xeq, u_extra] = equilibrium_state(V,Psys,Qsys,kappa,ki_P,ki_Q,V_div_min)
if ~isscalar(V) || ~isfinite(V) || abs(V) <= 0 || ...
        ~isscalar(Psys) || ~isscalar(Qsys) || ~isfinite(Psys) || ~isfinite(Qsys)
    error('ibr:gfl_reduced6_model:equilibriumInput', ...
        'Equilibrium V/P/Q must be finite scalar values with |V|>0.');
end
Vmag = abs(V);
if Vmag < V_div_min
    error('ibr:gfl_reduced6_model:equilibriumLowVoltage', ...
        '|V|=%.6g < V_div_min=%.6g; equilibrium fail-closed.', Vmag, V_div_min);
end
P_ref_inv = kappa*Psys;
Q_ref_inv = kappa*Qsys;
i_d0 = P_ref_inv/Vmag;
i_q0 = -Q_ref_inv/Vmag;
delta_PLL0 = angle(V);
xi_PLL0 = 0.0;
xi_P0 = i_d0/ki_P;      % i_d_ref0 = ki_P*xi_P0 = i_d0
xi_Q0 = -i_q0/ki_Q;     % i_q_ref0 = -ki_Q*xi_Q0 = i_q0
xeq = [i_d0; i_q0; delta_PLL0; xi_PLL0; xi_P0; xi_Q0];
u_extra = [];
if any(~isfinite(xeq))
    error('ibr:gfl_reduced6_model:equilibriumNonfinite', ...
        'Reconstructed GFL-reduced6 equilibrium contains non-finite values.');
end
end

% =========================================================================
function y = first_output(fn)
[y,~] = fn();
end

% =========================================================================
function check_state_input(x,u)
if numel(x) ~= 6 || any(~isfinite(x))
    error('ibr:gfl_reduced6_model:badState','Expected six finite GFL-reduced6 states.');
end
if numel(u) ~= 2 || any(~isfinite(u))
    error('ibr:gfl_reduced6_model:badInput','Expected finite u=[P_ref;Q_ref].');
end
end

% =========================================================================
function V = bus_voltage(y,bp,V_div_min)
if numel(y) < 2*bp || any(~isfinite(y(2*bp-1:2*bp)))
    error('ibr:gfl_reduced6_model:badNetworkState', ...
        'Network state does not contain a finite voltage for bus position %d.',bp);
end
V = complex(y(2*bp-1),y(2*bp));
if abs(V) < V_div_min
    error('ibr:gfl_reduced6_model:lowVoltageDomain', ...
        '|V|=%.6g < V_div_min=%.6g; balanced positive-sequence domain violated.',abs(V),V_div_min);
end
end

% =========================================================================
function validate_bus_mapping(bus_id,bp,bus_ids)
if ~isfinite(bp) || bp ~= floor(bp) || bp < 1 || bp > numel(bus_ids) || bus_ids(bp) ~= bus_id
    error('ibr:gfl_reduced6_model:busMappingMismatch', ...
        'bus_position and bus_id do not identify the same network bus.');
end
end

% =========================================================================
function validate_params(Sbase,Mbase,fbase,omega_b,kp_PLL,ki_PLL,kp_P,ki_P,kp_Q,ki_Q,kp_i,R_t,L,V_div_min)
names = {'Sbase','Mbase','fbase','omega_b','kp_PLL','ki_PLL','kp_P','ki_P','kp_Q','ki_Q','kp_i','R_t','L','V_div_min'};
vals  = [Sbase,Mbase,fbase,omega_b,kp_PLL,ki_PLL,kp_P,ki_P,kp_Q,ki_Q,kp_i,R_t,L,V_div_min];
for k = 1:numel(names)
    if ~isscalar(vals(k)) || ~isfinite(vals(k))
        error('ibr:gfl_reduced6_model:badParam','Parameter %s must be a finite scalar.',names{k});
    end
end
positive = {'Sbase','Mbase','fbase','omega_b','ki_PLL','ki_P','ki_Q','kp_i','L','V_div_min'};
pvals = struct('Sbase',Sbase,'Mbase',Mbase,'fbase',fbase,'omega_b',omega_b,'ki_PLL',ki_PLL, ...
    'ki_P',ki_P,'ki_Q',ki_Q,'kp_i',kp_i,'L',L,'V_div_min',V_div_min);
for k = 1:numel(positive)
    if pvals.(positive{k}) <= 0
        error('ibr:gfl_reduced6_model:badParam','Parameter %s must be positive.',positive{k});
    end
end
if R_t < 0
    error('ibr:gfl_reduced6_model:badParam','R_t must be non-negative.');
end
end

% =========================================================================
function reject_unsupported_options(g)
forbidden = {'T_P','T_Q','ki_i','xi_id','xi_iq','Imax','Vdc0','m_max','Vdip','Kqv','ts_pll'};
for k = 1:numel(forbidden)
    if isfield(g,forbidden{k})
        error('ibr:gfl_reduced6_model:unsupportedOption', ...
            ['Parameter %s is not supported by the reduced 6-state GFL model ' ...
             '(no P/Q filter, no current-PI integrator, no limiter/LVRT).'], forbidden{k});
    end
end
end
