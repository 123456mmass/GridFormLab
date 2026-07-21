function dev = gfm_vsm_sakimoto_model(device_id, bus_id, bus_position, ...
    bus_ids, V0, params, P_ref_pu, Q_ref_pu)
%GFM_VSM_SAKIMOTO_MODEL  9-state positive-sequence RMS grid-forming VSM,
%   no PLL, no AVR, no PSS, based on Sakimoto 2015 current-controlled VSG.
%
%   dev = gfm_vsm_sakimoto_model(DEVICE_ID, BUS_ID, BUS_POSITION, BUS_IDS, V0,
%       PARAMS, P_REF_PU, Q_REF_PU) returns a device struct conforming to the
%       stability.composite_dae ABI (R3 Revision 2): f, current_injection,
%       electrical_power, reconstruct, equilibrium_initialize, state_names,
%       input_names, nx, nu, active_state_indices, provenance.
%
%   This is a SEPARATE device from the existing 4-state `ibr_gfm_vsg_no_pll`
%   (Avila-Martinez/PNNL reduced model), which remains unchanged. This model
%   realizes the whiteboard 3-block structure [IBR, GFM, VSG] as DYNAMIC
%   STATES (inner current loop is a state, not algebraic), following the
%   full Sakimoto 2015 current-controlled VSG architecture, with the AVR
%   removed per user decision (no AVR, no PSS) and replaced by a static
%   algebraic Q-V droop.
%
%   Source: Sakimoto et al., "Virtual Synchronous Generator without Phase
%   Locked Loop based on Current Controlled Inverter and its Parameter
%   Design," IEEJ Trans. PE, Vol.135 No.7, 2015
%   (docs/text/gfm_no_pll/sakimoto-2015-vsg-without-pll.pdf), Table 1/2,
%   Fig.2/6/8, Eq.(1)-(19),(22),(26). Cascaded current-PI decoupling form
%   cross-checked against D'Arco/Suul/Fosso, EPSR 122 (2015) 180-197, Eq.(21)-
%   (22),(26) (docs/text/darco-suul-2015.txt); its PLL-based damping is NOT
%   used. Design contract: docs/project/GFM_VSM_SAKIMOTO_SOURCE_CONTRACT.md.
%   Frozen numeric parameters: docs/project/GFM_VSM_SAKIMOTO_PARAMETER_MANIFEST.md.
%
%   HARD NO-PLL / NO-AVR / NO-PSS CONTRACT (enforced at construction). The
%   model contains NONE of: delta_PLL, xi_PLL/x_PLL_int, PLL PI gains, PLL
%   freeze, PLL-estimated frequency, angle(V) runtime tracking, an AVR
%   integrator/PI, a field-winding lag, or a power system stabilizer. The
%   runtime rotor angle comes ONLY from the swing/synchronizing-power
%   mechanism (Sakimoto eq 4-7); the internal EMF magnitude comes ONLY from
%   a static algebraic Q-V droop (no integral voltage regulator).
%
%   State order (9, fixed):
%     1 i_d      IBR d-axis filter/converter current    [pu inverter]
%     2 i_q      IBR q-axis filter/converter current    [pu inverter]
%     3 xi_id    IBR d-axis current-PI integrator       [pu*s]
%     4 xi_iq    IBR q-axis current-PI integrator       [pu*s]
%     5 omega_R  VSG rotor speed                        [pu]
%     6 delta    VSG load angle (rotor - grid phase)     [rad]
%     7 x_gov    VSG governor PI integrator              [pu]
%     8 T_m      VSG turbine 1st-order prime-mover torque[pu]
%     9 x_d      VSG damper washout state                [pu]
%
%   Inputs (nu=2): u = [P_ref; Q_ref] (pu, system base).
%
%   Per-unit base contract (same as GFL-RMS10/REGFM_B1/existing GFM-no-PLL):
%     kappa = Sbase/Mbase; P_ref_inv = kappa*P_ref_sys.
%     Device-internal states run on INVERTER base; current_injection and
%     electrical_power return SYSTEM base. No double conversion.
%     omega_b = 377 rad/s (60 Hz), matching Sakimoto Fig.6 "377/s" directly
%     (no 50->60 Hz retuning required).
%
%   Governing equations (frozen; see GFM_VSM_SAKIMOTO_SOURCE_CONTRACT.md):
%     Boundary: kappa = Sbase/Mbase; V_bus = complex(y(2*bp-1), y(2*bp)).
%
%     dq transform (Sakimoto Sec.2.1, orientation V_gd=-Vg*sin(delta),
%     V_gq=Vg*cos(delta), i.e. q-axis parallel to E_q):
%       V_gd = -real(V_bus*exp(-1i*delta))*(-1) ... (see model_f for exact form)
%       (implemented directly from V_bus and delta; see code for algebra)
%
%     GFM block -- algebraic Q-V droop (NO AVR, NO PSS; user decision):
%       E_q = E_0 + K_q*(Q_ref_inv - Q_inv_meas)
%
%     IBR block -- impedance-model current command (Sakimoto eq 1-2, ALGEBRAIC):
%       [Iq_cmd; Id_cmd] = (1/(r^2+x^2)) * [r x; -x r] * [E_q-V_gq; -V_gd]
%     IBR block -- current-priority limiter (PROJECT_DERIVED, P-priority):
%       if hypot(Id_cmd,Iq_cmd) > Imax: scale to Imax (P-priority as GFL-RMS10)
%     IBR block -- current PI + decoupling + L-filter plant (Sakimoto Fig.6):
%       v_d* = K_IP*(Id_cmd-i_d) + K_II*xi_id - omega_R*X_F*i_q + V_gd
%       v_q* = K_IP*(Iq_cmd-i_q) + K_II*xi_iq + omega_R*X_F*i_d + V_gq
%       d(xi_id)/dt = AW_id(Id_cmd - i_d)
%       d(xi_iq)/dt = AW_iq(Iq_cmd - i_q)
%       (X_F/omega_b) d(i_d)/dt = -R_F*i_d + omega_R*X_F*i_q + v_d* - V_gd
%       (X_F/omega_b) d(i_q)/dt = -R_F*i_q - omega_R*X_F*i_d + v_q* - V_gq
%
%     VSG block -- electrical torque, swing, damper, governor (Sakimoto eq
%     3-5,7,12-18,22,26; NO PLL):
%       T_e = E_q*i_q/omega_R
%       d(x_d)/dt = (T_e - x_d)/tau_d                    (damper washout)
%       T_d = (K/tau_d)*(T_e - x_d)                       (damping torque)
%       J*d(omega_R)/dt = T_m - T_e - T_d - D_g*omega_R
%       d(delta)/dt = omega_b*(omega_R - omega_g_pu)       (omega_g_pu=1 at SMIB)
%       P_meas = T_e*omega_R   (approx electrical power, Sakimoto Sec.3.1)
%       P_gov_err = (P_ref_inv + K_gd*(1 - omega_R)) - P_meas
%       d(x_gov)/dt = K_GI*P_gov_err
%       T_m_cmd = K_GP*P_gov_err + x_gov
%       d(T_m)/dt = (T_m_cmd - T_m)/T_tur
%
%     Network injection (generator convention S=V*conj(I), system base):
%       I_dq_inv = i_d + 1i*i_q (Sakimoto/VSM rotor dq frame)
%       I_net = (I_dq_inv*exp(1i*delta_frame))/kappa  (see code for exact
%       frame identity consistent with the V_gd/V_gq orientation above)
%
%   Current-priority limiting, anti-windup, and low-voltage fail-closed use
%   the same one-sided conditional-hold and vector-clamp PROJECT_DERIVED
%   patterns as GFL-RMS10 (docs/project/IEEE14_IBR_GFL_RMS10_PROVENANCE.md),
%   applied here to the Sakimoto current loop.
%
%   OUT-OF-SCOPE (NOT pending functionality, explicit user decision):
%     - AVR / dynamic voltage PI / field-winding lag -- REMOVED (no AVR).
%     - Power system stabilizer -- REMOVED (no PSS).
%     - LC output filter / transformer stage -- REMOVED (L-filter RMS
%       reduction only; network coupling via SMIB Z_line / composite KCL).
%     - Fault LVRT beyond the balanced positive-sequence fail-closed floor.
%
%   Classification: 9 states; impedance model + current PI + rotor swing +
%   governor + damper are SOURCE_DEFINED (Sakimoto 2015); Q-V droop
%   replacing the removed AVR, current limiter, and anti-windup are
%   PROJECT_DERIVED. See parameter manifest for the full table.
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
    error('ibr:gfm_vsm_sakimoto_model:badV0', ...
        'V0 must be a finite nonzero bus-voltage phasor.');
end
if ~isfinite(P_ref_pu) || ~isfinite(Q_ref_pu) || ...
        ~isreal(P_ref_pu) || ~isreal(Q_ref_pu)
    error('ibr:gfm_vsm_sakimoto_model:badRef', ...
        'P_ref_pu and Q_ref_pu must be finite real system-base values.');
end

% --- Frozen numerical parameter profile (SOURCE_DEFINED_STUDY_VALUE) -------
Sbase = 100.0;  if isfield(params,'Sbase') && ~isempty(params.Sbase), Sbase = params.Sbase; end
Mbase = 100.0;  if isfield(params,'Mbase') && ~isempty(params.Mbase), Mbase = params.Mbase; end
fbase = 60.0;   if isfield(params,'fbase') && ~isempty(params.fbase), fbase = params.fbase; end
omega_b = 2*pi*fbase;

% Nested overrides under params.gfm_vsm_sakimoto (never top-level, to avoid
% accidental cross-device parameter bleed).
g = struct();
if isfield(params,'gfm_vsm_sakimoto') && isstruct(params.gfm_vsm_sakimoto)
    g = params.gfm_vsm_sakimoto;
end

% Impedance model (Sakimoto Table 2).
r_imp = 0.2;    if isfield(g,'r') && ~isempty(g.r), r_imp = g.r; end
x_imp = 0.4;    if isfield(g,'x') && ~isempty(g.x), x_imp = g.x; end

% Governor (Sakimoto Table 1).
K_gd  = 0.05;   if isfield(g,'K_gd') && ~isempty(g.K_gd), K_gd = g.K_gd; end
K_GP  = 20.0;   if isfield(g,'K_GP') && ~isempty(g.K_GP), K_GP = g.K_GP; end
K_GI  = 100.0;  if isfield(g,'K_GI') && ~isempty(g.K_GI), K_GI = g.K_GI; end
T_tur = 0.12;   if isfield(g,'T_tur') && ~isempty(g.T_tur), T_tur = g.T_tur; end

% Current PI (Sakimoto Table 1).
K_IP = 1.49;    if isfield(g,'K_IP') && ~isempty(g.K_IP), K_IP = g.K_IP; end
K_II = 71.95;   if isfield(g,'K_II') && ~isempty(g.K_II), K_II = g.K_II; end

% L-filter (Sakimoto Table 2).
R_F = 0.0022;   if isfield(g,'R_F') && ~isempty(g.R_F), R_F = g.R_F; end
X_F = 0.088;    if isfield(g,'X_F') && ~isempty(g.X_F), X_F = g.X_F; end

% Damper (Sakimoto Table 1).
K_damp = 10.0;  if isfield(g,'K_damp') && ~isempty(g.K_damp), K_damp = g.K_damp; end
tau_d  = 0.01;  if isfield(g,'tau_d') && ~isempty(g.tau_d), tau_d = g.tau_d; end

% Rotor (Sakimoto Table 1).
J   = 4.0;      if isfield(g,'J') && ~isempty(g.J), J = g.J; end
D_g = 1.0;      if isfield(g,'D_g') && ~isempty(g.D_g), D_g = g.D_g; end

% Voltage-forming Q-V droop (PROJECT_DERIVED, replaces removed AVR).
K_q = 0.05;     if isfield(g,'K_q') && ~isempty(g.K_q), K_q = g.K_q; end
E_0 = 1.0;      if isfield(g,'E_0') && ~isempty(g.E_0), E_0 = g.E_0; end

% Current limiter (PROJECT_DERIVED).
Imax = 1.2;     if isfield(g,'Imax') && ~isempty(g.Imax), Imax = g.Imax; end

% Low-voltage fail-closed floor (PROJECT_DERIVED).
V_div_min = 0.1; if isfield(g,'V_div_min') && ~isempty(g.V_div_min), V_div_min = g.V_div_min; end

% Numerical-method tolerances.
eq_tol = 1e-9;  if isfield(g,'eq_tol') && ~isempty(g.eq_tol), eq_tol = g.eq_tol; end
aw_tol = 1e-9;  if isfield(g,'aw_tol') && ~isempty(g.aw_tol), aw_tol = g.aw_tol; end

validate_params(Sbase,Mbase,fbase,omega_b,r_imp,x_imp,K_gd,K_GP,K_GI,T_tur, ...
    K_IP,K_II,R_F,X_F,K_damp,tau_d,J,D_g,K_q,E_0,Imax,V_div_min,eq_tol,aw_tol);

% Reject any dormant PLL/AVR/PSS/limiter-shape option fields rather than
% storing ambiguous unsupported controls (hard no-PLL/no-AVR/no-PSS contract).
reject_unsupported_options(g);

% --- Boundary conversion ----------------------------------------------------
kappa = Sbase/Mbase;

bp = bus_position;

% --- Equilibrium initial state ----------------------------------------------
% Two-stage solve: (1) internal exact solve determines delta0 AND the Q_ref
% that makes the frozen (K_q,E_0) droop consistent with (V0,P_ref_pu,Q_ref_pu)
% -- this Q_ref becomes u0(2), the device's OPERATING reference input,
% mirroring how the existing GFM-no-PLL device solves a consistent Q0 for a
% frozen V_ref. (2) The public equilibrium_initialize ABI closure then uses
% THIS FROZEN Q_ref (not a re-solved one) for any later (V,P,Q) query, exactly
% like every other device's equilibrium_initialize uses its frozen u0.
[x0, Q_ref_pu_solved] = solve_equilibrium_and_qref(V0, P_ref_pu, Q_ref_pu, ...
    kappa, r_imp, x_imp, K_q, E_0, D_g, R_F, K_IP, K_II, eq_tol);
u0 = [P_ref_pu; Q_ref_pu_solved];

% --- Closures (generic ABI; same signature family as GFL-RMS10) -----------
f = @(t,x,y,u,ec) model_f(x,y,u,bp,kappa,omega_b,r_imp,x_imp,K_gd,K_GP,K_GI, ...
    T_tur,K_IP,K_II,R_F,X_F,K_damp,tau_d,J,D_g,K_q,E_0,Imax,V_div_min,aw_tol);
current_injection = @(t,x,y,u,ec) model_current(x,y,bp,kappa,V_div_min);
electrical_power  = @(t,x,y,u,ec) model_power(x,y,bp,kappa,V_div_min);
reconstruct = @(t,x,y,u,ec) model_reconstruct(x,y,u,bp,kappa,omega_b,r_imp, ...
    x_imp,K_gd,K_GP,K_GI,T_tur,K_IP,K_II,R_F,X_F,K_damp,tau_d,J,D_g,K_q,E_0, ...
    Imax,V_div_min,Sbase,Mbase);
equilibrium_initialize = @(V,P,Q,ec) first_output( ...
    @() solve_equilibrium_and_qref(V,P,Q,kappa,r_imp,x_imp,K_q,E_0, ...
    D_g,R_F,K_IP,K_II,eq_tol));

dev = struct();
dev.name = char(device_id);
dev.device_id = char(device_id);
dev.bus_id = bus_id;
dev.bus_position = bus_position;
dev.bus_ids = bus_ids(:).';
dev.device_type = 'ibr_gfm_vsm_sakimoto';
dev.mode = 'GFM';
dev.nx = numel(x0);
dev.nu = 2;
dev.state_names = {'i_d','i_q','xi_id','xi_iq','omega_R','delta','x_gov','T_m','x_d'};
dev.input_names = {'P_ref','Q_ref'};
dev.x0 = x0;
dev.u0 = u0;
dev.f = f;
dev.current_injection = current_injection;
dev.electrical_power = electrical_power;
dev.reconstruct = reconstruct;
dev.equilibrium_initialize = equilibrium_initialize;
dev.active_state_indices = @(ec) 1:9;
dev.provenance = struct( ...
    'model','GFM_VSM_SAKIMOTO_NO_PLL_NO_AVR_NO_PSS', ...
    'source',['Sakimoto 2015 (docs/text/gfm_no_pll/sakimoto-2015-vsg-without-pll.pdf); ' ...
              'D''Arco/Suul/Fosso 2015 cascaded-controller form only, PLL NOT adopted ' ...
              '(docs/text/darco-suul-2015.txt)'], ...
    'source_classification', ...
        'Impedance model+current PI+rotor swing+governor+damper SOURCE_DEFINED (Sakimoto); Q-V droop/limiter/anti-windup PROJECT_DERIVED; NO PLL, NO AVR, NO PSS', ...
    'design_contract','docs/project/GFM_VSM_SAKIMOTO_SOURCE_CONTRACT.md', ...
    'parameter_manifest','docs/project/GFM_VSM_SAKIMOTO_PARAMETER_MANIFEST.md', ...
    'control_option','Sakimoto current-controlled VSG; static Q-V droop replacing removed AVR; no PSS; P-priority current limiter', ...
    'pu_base_contract','internal=inverter base; external=system base; kappa=Sbase/Mbase', ...
    'low_voltage_policy','balanced positive-sequence fail-closed floor V_div_min; no PLL to freeze', ...
    'angle_contract','runtime load angle ONLY from swing/synchronizing-power mechanism (Sakimoto eq 4-7); never from angle(V)', ...
    'params',struct('Sbase',Sbase,'Mbase',Mbase,'fbase',fbase,'omega_b',omega_b, ...
        'r',r_imp,'x',x_imp,'K_gd',K_gd,'K_GP',K_GP,'K_GI',K_GI,'T_tur',T_tur, ...
        'K_IP',K_IP,'K_II',K_II,'R_F',R_F,'X_F',X_F,'K_damp',K_damp,'tau_d',tau_d, ...
        'J',J,'D_g',D_g,'K_q',K_q,'E_0',E_0,'Imax',Imax,'V_div_min',V_div_min, ...
        'kappa',kappa,'eq_tol',eq_tol,'aw_tol',aw_tol), ...
    'readiness','SOURCE_IMPLEMENTED_PENDING_SMIB_GATES');
end

% =========================================================================
function dx = model_f(x,y,u,bp,kappa,omega_b,r_imp,x_imp,K_gd,K_GP,K_GI, ...
    T_tur,K_IP,K_II,R_F,X_F,K_damp,tau_d,J,D_g,K_q,E_0,Imax,V_div_min,aw_tol)
check_state_input(x,u);
V = bus_voltage(y,bp,V_div_min);

i_d = x(1); i_q = x(2); xi_id = x(3); xi_iq = x(4);
omega_R = x(5); delta = x(6); x_gov = x(7); T_m = x(8); x_d = x(9);
P_ref_inv = kappa*u(1);
Q_ref_inv = kappa*u(2);

% --- dq transform (Sakimoto eq 8): rotor(load-angle)-oriented frame with
% q-axis parallel to E_q. A network phasor F maps to the rotor frame as
% F_rot = F*exp(-1i*delta), with q = real(F_rot), d = imag(F_rot). Thus
% V_gq = Vg*cos(delta) = real, V_gd = -Vg*sin(delta) = imag  (eq 8 exactly).
Vc = V * exp(-1i*delta);
V_gd = imag(Vc);
V_gq = real(Vc);

% --- GFM block: algebraic Q-V droop (NO AVR, NO PSS) ------------------------
% Rotor-frame current phasor I_rot = i_q + j*i_d = I_inv*exp(-1i*delta).
% Inverter-base power S_inv = V_rot*conj(I_rot):
%   P_inv = V_gq*i_q + V_gd*i_d ; Q_inv = V_gd*i_q - V_gq*i_d.
S_inv_prov = Vc*conj(complex(i_q,i_d));
P_inv_meas = real(S_inv_prov);
Q_inv_meas = imag(S_inv_prov);
E_q = E_0 + K_q*(Q_ref_inv - Q_inv_meas);

% --- IBR block: impedance-model current command (Sakimoto eq 1-2, ALGEBRAIC)
%   [Iq_cmd; Id_cmd] = (1/(r^2+x^2)) [r x; -x r] [E_q-V_gq; -V_gd]
denom = r_imp^2 + x_imp^2;
Iq_cmd_raw = ( r_imp*(E_q - V_gq) - x_imp*V_gd ) / denom;
Id_cmd_raw = ( -x_imp*(E_q - V_gq) - r_imp*V_gd ) / denom;

% --- Current-priority limiter (PROJECT_DERIVED, P-priority) -----------------
mag_cmd = hypot(Id_cmd_raw,Iq_cmd_raw);
if mag_cmd > Imax && mag_cmd > 0
    scale = Imax/mag_cmd;
    Id_cmd = Id_cmd_raw*scale;
    Iq_cmd = Iq_cmd_raw*scale;
    limiter_active = true;
else
    Id_cmd = Id_cmd_raw;
    Iq_cmd = Iq_cmd_raw;
    limiter_active = false;
end

% --- Current PI + decoupling (Sakimoto Fig.6; feedforward cancels the dq
% cross-coupling of the rotating-frame L-filter). Convention q=real,d=imag:
%   plant cross terms: d-axis -omega_R*X_F*i_q, q-axis +omega_R*X_F*i_d.
e_d = Id_cmd - i_d;
e_q = Iq_cmd - i_q;
v_td = K_IP*e_d + K_II*xi_id + V_gd + omega_R*X_F*i_q;
v_tq = K_IP*e_q + K_II*xi_iq + V_gq - omega_R*X_F*i_d;

aw_id = aw_outer_current(e_d, limiter_active, mag_cmd, Imax, aw_tol);
aw_iq = aw_outer_current(e_q, limiter_active, mag_cmd, Imax, aw_tol);
d_xi_id = aw_id;
d_xi_iq = aw_iq;

% --- L-filter current plant (rotating-frame, per-unit time-derivative form)-
d_i_d = ( v_td - V_gd - R_F*i_d - omega_R*X_F*i_q ) * (omega_b/X_F);
d_i_q = ( v_tq - V_gq - R_F*i_q + omega_R*X_F*i_d ) * (omega_b/X_F);

% --- VSG block: electrical torque, damper, swing (Sakimoto eq 3-5,12-18) ---
% Damper washout (Fig.6 block "1 + K*tau_d*s/(1+tau_d*s)" applied to T_e):
%   T_e + T_d, with T_d = K*tau_d*s/(1+tau_d*s) * T_e = K*(T_e - x_d),
%   where x_d = lowpass(T_e): d(x_d)/dt = (T_e - x_d)/tau_d.
% Hence T_d = K_damp*(T_e - x_d). This matches Sakimoto eq 12 (T_d = K_tau_d *
% dT_e/dt, K_tau_d = K*tau_d = 0.1) and eq 15/18 (D = K_tau_d*x/(r^2+x^2) =
% 0.2 for K=10), NOT (K_damp/tau_d)*(...).
T_e = E_q*i_q/omega_R;
d_x_d = (T_e - x_d)/tau_d;
T_d = K_damp*(T_e - x_d);
d_omega_R = (T_m - T_e - T_d - D_g*omega_R)/J;
d_delta = omega_b*(omega_R - 1.0);   % omega_g_pu = 1 at the ideal SMIB grid

% --- Governor (Sakimoto eq 22,26) ------------------------------------------
% Governor regulates the TERMINAL active power P_inv_meas (the power actually
% delivered) to P_ref, with speed droop K_gd. This differs from the internal
% electrical torque T_e (=E_q*i_q/omega_R) by the filter loss; using T_e here
% would leave a steady-state governor imbalance. Sakimoto Sec.3.1 approximates
% --- Governor (Sakimoto eq 19/23/26): SPEED-regulating PI with power droop.
% The governor is a frequency controller: the PI acts primarily on the speed
% error (1 - omega_R), with the active-power setpoint entering only as a weak
% droop bias K_gd (=0.05). Sakimoto eq 26: omega* - omega = -K_gd*(P* - P),
% i.e. the steady-state droop line. At equilibrium omega_R=1 forces the droop
% bias to zero, so P_inv_meas = P_ref exactly. (Regulating the power error
% directly with unit weight -- a power loop -- instead destabilizes the swing;
% the governor must be speed-primary.)
e_gov = (1.0 - omega_R) + K_gd*(P_ref_inv - P_inv_meas);
d_x_gov = K_GI*e_gov;
T_m_cmd = K_GP*e_gov + x_gov;
d_T_m = (T_m_cmd - T_m)/T_tur;

dx = [d_i_d; d_i_q; d_xi_id; d_xi_iq; d_omega_R; d_delta; d_x_gov; d_T_m; d_x_d];
if any(~isfinite(dx))
    error('ibr:gfm_vsm_sakimoto_model:nonfiniteRhs', ...
        'GFM-VSM-Sakimoto RHS produced a non-finite value.');
end
end

% =========================================================================
function I = model_current(x,y,bp,kappa,V_div_min)
if numel(x) ~= 9 || any(~isfinite(x))
    error('ibr:gfm_vsm_sakimoto_model:badState', ...
        'Expected nine finite GFM-VSM-Sakimoto states.');
end
V = bus_voltage(y,bp,V_div_min); %#ok<NASGU> (validates domain; frame below)
delta = x(6);
i_d = x(1); i_q = x(2);
% Network injection: rotor-frame current phasor is I_rot = i_q + j*i_d
% (q=real,d=imag; Sakimoto convention). Rotate back to the network xy frame
% (I_inv = I_rot*exp(1i*delta)) then convert inverter->system base.
I_inv = complex(i_q,i_d) * exp(1i*delta);
I = I_inv/kappa;
if ~isfinite(I)
    error('ibr:gfm_vsm_sakimoto_model:nonfiniteCurrent', ...
        'GFM-VSM-Sakimoto current injection produced a non-finite value.');
end
end

% =========================================================================
function Pe = model_power(x,y,bp,kappa,V_div_min)
V = bus_voltage(y,bp,V_div_min);
I = model_current(x,y,bp,kappa,V_div_min);
Pe = real(V*conj(I));
end

% =========================================================================
function out = model_reconstruct(x,y,u,bp,kappa,omega_b,r_imp,x_imp,K_gd, ...
    K_GP,K_GI,T_tur,K_IP,K_II,R_F,X_F,K_damp,tau_d,J,D_g,K_q,E_0,Imax, ...
    V_div_min,Sbase,Mbase)
check_state_input(x,u);
V = bus_voltage(y,bp,V_div_min);
i_d = x(1); i_q = x(2); xi_id = x(3); xi_iq = x(4);
omega_R = x(5); delta = x(6); x_gov = x(7); T_m = x(8); x_d = x(9);
P_ref_inv = kappa*u(1);
Q_ref_inv = kappa*u(2);
Vc = V * exp(-1i*delta);
V_gd = imag(Vc); V_gq = real(Vc);
S_inv = Vc*conj(complex(i_q,i_d));
P_inv_meas = real(S_inv); Q_inv_meas = imag(S_inv);
E_q = E_0 + K_q*(Q_ref_inv - Q_inv_meas);
I_net = model_current(x,y,bp,kappa,V_div_min);
S_sys = V*conj(I_net);
T_e = E_q*i_q/omega_R;
out = struct( ...
    'i_d',i_d,'i_q',i_q,'xi_id',xi_id,'xi_iq',xi_iq, ...
    'omega_R',omega_R,'delta',delta,'x_gov',x_gov,'T_m',T_m,'x_d',x_d, ...
    'E_q',E_q,'T_e',T_e,'V_gd',V_gd,'V_gq',V_gq, ...
    'I_sys',I_net,'I_inv',I_net*kappa, ...
    'P_inv_meas',P_inv_meas,'Q_inv_meas',Q_inv_meas, ...
    'Pe',real(S_sys),'Qe',imag(S_sys), ...
    'Vbus',abs(V),'Vbus_phasor',V, ...
    'P_ref_inv',P_ref_inv,'Q_ref_inv',Q_ref_inv, ...
    'kappa',kappa,'Sbase',Sbase,'Mbase',Mbase, ...
    'r',r_imp,'x',x_imp,'K_gd',K_gd,'K_GP',K_GP,'K_GI',K_GI,'T_tur',T_tur, ...
    'K_IP',K_IP,'K_II',K_II,'R_F',R_F,'X_F',X_F,'K_damp',K_damp,'tau_d',tau_d, ...
    'J',J,'D_g',D_g,'K_q',K_q,'E_0',E_0,'Imax',Imax, ...
    'limiter_active',hypot( ...
        ( r_imp*(E_q-V_gq)+x_imp*(-V_gd) )/(r_imp^2+x_imp^2), ...
        ( -x_imp*(E_q-V_gq)+r_imp*(-V_gd) )/(r_imp^2+x_imp^2) ) > Imax, ...
    'readiness','SOURCE_IMPLEMENTED_PENDING_SMIB_GATES');
end

% =========================================================================
function aw = aw_outer_current(e, limiter_active, mag_cmd, Imax, aw_tol)
% One-sided conditional hold (outward hold, inward release), mirroring the
% GFL-RMS10 anti-windup pattern: hold the integrator when the limiter is
% active and the error is pushing further past the bound.
if limiter_active && (mag_cmd - Imax)*e > aw_tol
    aw = 0;
else
    aw = e;
end
end

% =========================================================================
function [xeq, Q_ref_pu_solved] = solve_equilibrium_and_qref(V,Psys,Qsys, ...
    kappa,r_imp,x_imp,K_q,E_0,D_g,R_F,K_IP,K_II,eq_tol)
% Exact equilibrium construction by ROOT-FINDING on delta0 (the load angle
% is a physically meaningful synchronizing-power quantity, Sakimoto eq 7,
% not a free choice). At equilibrium: omega_R=1, all integrators/derivatives
% zero, and the current STATE (i_d0,i_q0) equals the NETWORK-required
% current (fixed exactly by V,Psys,Qsys) -- this is what the closed current
% loop enforces (e_d=e_q=0). For a trial delta0:
%   I_inv_required = kappa*conj((P+jQ)/V)         (fixed, network xy frame)
%   (i_d0,i_q0) = I_inv_required*exp(-1i*(delta0-pi/2))
%   (Vgd0,Vgq0) = V*exp(-1i*(delta0-pi/2))
%   E_q0 solved from the q-component of the impedance model (eq 2) so that
%     Iq_cmd(E_q0) == i_q0 EXACTLY (one linear equation, one unknown E_q0).
%   residual(delta0) = Id_cmd(E_q0) - i_d0   (the d-component of eq 2, which
%     is NOT automatically zero -- this is the physical constraint that pins
%     delta0; Sakimoto's synchronizing-power mechanism).
% Bisection finds the delta0 root of this residual. This mirrors the
% existing GFM-no-PLL device's solve_consistent_Q free-parameter root-find,
% but here the free parameter is the load angle delta0, and E_q is a
% by-product (its consistency with the droop pins Q_ref, which the device
% constructor must set to Qsys for equilibrium_initialize to be
% self-consistent with the same operating point -- verified by construction
% below via Q_ref_inv, and exposed for the constructor to use as u0(2)).
if ~isscalar(V) || ~isfinite(V) || abs(V) <= 0 || ...
        ~isscalar(Psys) || ~isscalar(Qsys) || ~isfinite(Psys) || ~isfinite(Qsys)
    error('ibr:gfm_vsm_sakimoto_model:equilibriumInput', ...
        'Equilibrium V/P/Q must be finite scalar values with |V|>0.');
end
if r_imp <= 0
    error('ibr:gfm_vsm_sakimoto_model:equilibriumDegenerateR', ...
        'Equilibrium construction requires r>0 to invert the impedance model.');
end
resid_fn = @(d) equilibrium_residual_droop(d,V,Psys,Qsys,kappa,r_imp,x_imp,K_q,E_0);
delta0 = bisect_angle(resid_fn, angle(V), eq_tol);

I_inv_required = kappa*conj((Psys + 1i*Qsys)/V);
i_rot0 = I_inv_required * exp(-1i*delta0);   % = i_q0 + j*i_d0
i_q0 = real(i_rot0);
i_d0 = imag(i_rot0);
Vc0 = V * exp(-1i*delta0);
V_gd0 = imag(Vc0); V_gq0 = real(Vc0);
E_q0 = V_gq0 + ((r_imp^2+x_imp^2)*i_q0 + x_imp*V_gd0)/r_imp;

% The static Q-V droop E_q = E_0 + K_q*(Q_ref_inv - Q_inv_meas) must produce
% EXACTLY this E_q0 at the equilibrium measured reactive power (which equals
% kappa*Qsys, since i_d0,i_q0 were constructed from the required network
% current). Back-solve the ONE remaining free parameter, Q_ref, so this
% holds exactly (mirrors the existing GFM-no-PLL device's solve_consistent_Q
% pattern: a free INPUT is solved for consistency, not the state).
Q_inv_meas0 = imag(Vc0*conj(complex(i_q0,i_d0)));
if K_q ~= 0
    Q_ref_inv0 = Q_inv_meas0 + (E_q0 - E_0)/K_q;
elseif abs(E_q0 - E_0) > eq_tol*max(1.0,abs(E_q0))
    error('ibr:gfm_vsm_sakimoto_model:infeasibleEquilibriumZeroDroop', ...
        ['K_q=0 (constant E_q=E_0) but the requested (V,P,Q)=(%.6g,%.6g,%.6g) ' ...
         'requires E_q=%.6g != E_0=%.6g. Infeasible; fail-closed.'], ...
        abs(V),Psys,Qsys,E_q0,E_0);
else
    Q_ref_inv0 = Q_inv_meas0;
end
Q_ref_pu_solved = Q_ref_inv0/kappa;

% At equilibrium the closed current loop drives e_d,e_q toward zero (d_xi=0).
% delta0 from bisection makes them tiny but not bit-exact. To keep the plant
% derivatives d_i_d=d_i_q=0 EXACTLY (avoiding amplification by the large
% omega_b/X_F factor), set the current-PI integrators to cancel the plant
% RHS exactly, INCLUDING the residual K_IP*e term:
%   plant bracket = -R_F*i_d + K_IP*e_d + K_II*xi_id  (decoupling & V_gd cancel)
%   => xi_id0 = (R_F*i_d0 - K_IP*e_d0)/K_II   gives d_i_d = 0 exactly.
% The tiny residual e_d0 then lives only in d_xi_id = e_d0 (unamplified,
% ~bisection tolerance), never in the fast current states.
Id_cmd0 = ( -x_imp*(E_q0 - V_gq0) - r_imp*V_gd0 ) / (r_imp^2+x_imp^2);
Iq_cmd0 = (  r_imp*(E_q0 - V_gq0) - x_imp*V_gd0 ) / (r_imp^2+x_imp^2);
e_d0 = Id_cmd0 - i_d0;
e_q0 = Iq_cmd0 - i_q0;
xi_id0 = (R_F*i_d0 - K_IP*e_d0)/K_II;
xi_iq0 = (R_F*i_q0 - K_IP*e_q0)/K_II;
omega_R0 = 1.0;
T_e0 = E_q0*i_q0/omega_R0;
x_d0 = T_e0;    % washout state equals T_e at steady state (d(x_d)/dt=0)
% Governor: at equilibrium, P_gov_err=0 (since omega_R=1 removes the droop
% term) => T_m0 = T_e0 + T_d0 + D_g*omega_R0; T_d0=0 at steady state
% (T_e-x_d=0). => T_m0 = T_e0 + D_g*omega_R0. x_gov0 solves T_m_cmd=T_m0
% with P_gov_err=0 => x_gov0 = T_m0 (K_GP term vanishes since err=0).
T_m0 = T_e0 + D_g*omega_R0;
x_gov0 = T_m0;

xeq = [i_d0; i_q0; xi_id0; xi_iq0; omega_R0; delta0; x_gov0; T_m0; x_d0];
if any(~isfinite(xeq))
    error('ibr:gfm_vsm_sakimoto_model:equilibriumNonfinite', ...
        'Reconstructed GFM-VSM-Sakimoto equilibrium contains non-finite values.');
end
end

% =========================================================================
function y = first_output(fn)
% Return only the first output of a multi-output function handle (used to
% adapt solve_equilibrium_and_qref to the equilibrium_initialize ABI, which
% returns only the state vector).
[y,~] = fn();
end

% =========================================================================
function r = equilibrium_residual_droop(delta0,V,Psys,Qsys,kappa,r_imp,x_imp,K_q,E_0) %#ok<INUSD>
% Residual for the load-angle bisection (Sakimoto convention q=real,d=imag).
% For a trial delta0: the network-required current fixes (i_q0,i_d0) via
%   i_q0 + j*i_d0 = I_inv_required*exp(-1i*delta0).
% E_q0 is solved from the q-component of the impedance model (eq 2) so that
% Iq_cmd(E_q0) == i_q0 exactly. The residual is the d-component mismatch
% Id_cmd(E_q0) - i_d0, which is NOT automatically zero and pins delta0
% (Sakimoto's synchronizing-power constraint).
Vc = V * exp(-1i*delta0);
V_gd = imag(Vc); V_gq = real(Vc);
I_inv_required = kappa*conj((Psys + 1i*Qsys)/V);
i_rot = I_inv_required * exp(-1i*delta0);   % = i_q0 + j*i_d0
i_q0 = real(i_rot); i_d0 = imag(i_rot);
% Invert eq 2 q-component for E_q (forces Iq_cmd=i_q0):
%   i_q0 = (r*(E_q-V_gq) - x*V_gd)/(r^2+x^2)
E_q0 = V_gq + ((r_imp^2+x_imp^2)*i_q0 + x_imp*V_gd)/r_imp;
% Residual: the d-component of eq 2 at this E_q0 must ALSO reproduce i_d0
% (this is the genuine physical constraint that pins delta0; it is NOT
% automatically satisfied because eq 2 is a fixed 2x2 linear map from E_q
% to (Id_cmd,Iq_cmd), and only Iq_cmd was forced above).
Id_cmd0 = ( -x_imp*(E_q0 - V_gq) - r_imp*V_gd ) / (r_imp^2+x_imp^2);
r = Id_cmd0 - i_d0;
end

% =========================================================================
function delta0 = bisect_angle(resid_fn, delta_guess, eq_tol)
% Bisection for the equilibrium load angle. Scans a bracket around the
% voltage-angle guess (the natural Sakimoto Sec.2.3 startup value) and
% widens if needed, then bisects to eq_tol. Fails closed if no sign change
% is found (infeasible operating point for the frozen device parameters).
half_widths = [0.5, 1.0, 2.0, 3.0, pi - 1e-6];
found = false;
for hw = half_widths
    lo = delta_guess - hw; hi = delta_guess + hw;
    flo = resid_fn(lo); fhi = resid_fn(hi);
    if flo == 0, delta0 = lo; return; end
    if fhi == 0, delta0 = hi; return; end
    if flo*fhi < 0
        found = true;
        break;
    end
end
if ~found
    error('ibr:gfm_vsm_sakimoto_model:infeasibleEquilibrium', ...
        ['No load angle delta found consistent with the requested operating ' ...
         'point for the frozen Sakimoto impedance model and Q-V droop. ' ...
         'Fail-closed.']);
end
for it = 1:300
    mid = 0.5*(lo+hi);
    fmid = resid_fn(mid);
    if abs(fmid) <= eq_tol
        delta0 = mid; return;
    end
    if flo*fmid < 0
        hi = mid; fhi = fmid;
    else
        lo = mid; flo = fmid;
    end
    if abs(hi-lo) <= 4*eps(max(1.0,abs(lo)))
        delta0 = 0.5*(lo+hi); return;
    end
end
delta0 = 0.5*(lo+hi);
end

% =========================================================================
function check_state_input(x,u)
if numel(x) ~= 9 || any(~isfinite(x))
    error('ibr:gfm_vsm_sakimoto_model:badState', ...
        'Expected nine finite GFM-VSM-Sakimoto states.');
end
if numel(u) ~= 2 || any(~isfinite(u))
    error('ibr:gfm_vsm_sakimoto_model:badInput', ...
        'Expected finite u=[P_ref;Q_ref].');
end
end

% =========================================================================
function V = bus_voltage(y,bp,V_div_min)
if numel(y) < 2*bp || any(~isfinite(y(2*bp-1:2*bp)))
    error('ibr:gfm_vsm_sakimoto_model:badNetworkState', ...
        'Network state does not contain a finite voltage for bus position %d.',bp);
end
V = complex(y(2*bp-1),y(2*bp));
if abs(V) < V_div_min
    error('ibr:gfm_vsm_sakimoto_model:lowVoltageDomain', ...
        '|V|=%.6g < V_div_min=%.6g; balanced positive-sequence domain violated.', ...
        abs(V),V_div_min);
end
end

% =========================================================================
function validate_bus_mapping(bus_id,bp,bus_ids)
if ~isfinite(bp) || bp ~= floor(bp) || bp < 1 || bp > numel(bus_ids) || ...
        bus_ids(bp) ~= bus_id
    error('ibr:gfm_vsm_sakimoto_model:busMappingMismatch', ...
        'bus_position and bus_id do not identify the same network bus.');
end
end

% =========================================================================
function validate_params(Sbase,Mbase,fbase,omega_b,r_imp,x_imp,K_gd,K_GP, ...
    K_GI,T_tur,K_IP,K_II,R_F,X_F,K_damp,tau_d,J,D_g,K_q,E_0,Imax,V_div_min, ...
    eq_tol,aw_tol)
names = {'Sbase','Mbase','fbase','omega_b','r_imp','x_imp','K_gd','K_GP', ...
    'K_GI','T_tur','K_IP','K_II','R_F','X_F','K_damp','tau_d','J','D_g', ...
    'K_q','E_0','Imax','V_div_min','eq_tol','aw_tol'};
vals = [Sbase,Mbase,fbase,omega_b,r_imp,x_imp,K_gd,K_GP,K_GI,T_tur,K_IP, ...
    K_II,R_F,X_F,K_damp,tau_d,J,D_g,K_q,E_0,Imax,V_div_min,eq_tol,aw_tol];
for k = 1:numel(names)
    if ~isscalar(vals(k)) || ~isfinite(vals(k))
        error('ibr:gfm_vsm_sakimoto_model:badParam', ...
            'Parameter %s must be a finite scalar.', names{k});
    end
end
positive = {'Sbase','Mbase','fbase','omega_b','x_imp','T_tur','K_IP','K_II', ...
    'X_F','tau_d','J','E_0','Imax','V_div_min','eq_tol','aw_tol'};
pvals = struct('Sbase',Sbase,'Mbase',Mbase,'fbase',fbase,'omega_b',omega_b, ...
    'x_imp',x_imp,'T_tur',T_tur,'K_IP',K_IP,'K_II',K_II,'X_F',X_F, ...
    'tau_d',tau_d,'J',J,'E_0',E_0,'Imax',Imax,'V_div_min',V_div_min, ...
    'eq_tol',eq_tol,'aw_tol',aw_tol);
for k = 1:numel(positive)
    if pvals.(positive{k}) <= 0
        error('ibr:gfm_vsm_sakimoto_model:badParam', ...
            'Parameter %s must be positive.', positive{k});
    end
end
if r_imp < 0 || D_g < 0 || K_damp < 0
    error('ibr:gfm_vsm_sakimoto_model:badParam', ...
        'Parameters r_imp, D_g, K_damp must be non-negative.');
end
end

% =========================================================================
function reject_unsupported_options(g)
% Hard no-PLL / no-AVR / no-PSS contract enforcement: reject dormant fields
% for controls this device explicitly does not implement.
forbidden = {'kp_PLL','ki_PLL','VPLLfrz','delta_PLL','xi_PLL','x_PLL_int', ...
    'K_ad','K_AI','AVR_gain','pss_gain','PSS','field_time_constant', ...
    'VFlag','QVFlag','ImaxF','Emax','Emin'};
for k = 1:numel(forbidden)
    if isfield(g,forbidden{k})
        error('ibr:gfm_vsm_sakimoto_model:unsupportedOption', ...
            ['Parameter %s is not supported: this device has NO PLL, NO AVR, ' ...
             'and NO PSS by explicit design decision. Do not store dormant ' ...
             'ambiguous controls.'], forbidden{k});
    end
end
end
