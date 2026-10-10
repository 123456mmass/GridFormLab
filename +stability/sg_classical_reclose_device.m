function dev = sg_classical_reclose_device(case_data,device_id,bus_id,bus_position,bus_ids,V0,params)
%SG_CLASSICAL_RECLOSE_DEVICE Opt-in 7-state PROJECT_DERIVED SG31 reclose plant.
%   DEV = stability.sg_classical_reclose_device(CASE_DATA,DEVICE_ID,BUS_ID,
%       BUS_POSITION,BUS_IDS,V0,PARAMS) wraps the existing classical port
%   equation with actual DAE states for prime-mover valve/chest, reduced
%   excitation, and a terminal-voltage type-II phase/frequency estimator.
%
%   This factory is intentionally opt-in and currently supports only SG31 of
%   the TAMU NE39 1-SG+9-IBR composition. It is NOT GENROU/EXST1/IEEEST, not a
%   sourced governor or excitation system, and not a certified synchronizer.
%   H, D, X'd and the electrical injection equations are taken unchanged from
%   the legacy case-owned classical device. Every added loss, actuator,
%   excitation and PLL parameter is PROJECT_DERIVED and exposed in provenance.
%   The legacy stability.sg_classical_device is not modified.
%
%   State order: [delta,omega,Psv,Pm,Emag,theta_hat,nu_hat], with omega absolute
%   pu, Psv/Pm actual nonnegative mechanical powers on the system base, Emag
%   the reduced classical internal-emf magnitude, theta_hat the local terminal
%   phase estimate, and nu_hat estimated frequency deviation in rad/s. All
%   seven are genuine RHS states and therefore belong to a future TS LTE/SSSA
%   calculation. Inputs are reference commands [P_ref,Emag_ref], NOT the actual
%   Pm/Emag states and NOT EMF6 [Tm,Efd].
%
%   Rotor power balance (omega>0):
%       2*H*omega*domega = Pm - Pe - L0*omega^2 - D*omega*(omega-1).
%   Source D remains as declared (zero for SG31); L0 is separate, explicitly
%   PROJECT_DERIVED no-load shaft loss. The actuator equations are
%       Tsv*dPsv = Pc-Psv; Tch*dPm = Psv-Pm,
%   and Pc/Psv/Pm are constrained to [0,Pmax]. There is no negative mechanical
%   power, rotor reset, or state jump at a breaker transition.
%
%   Offline, a same-bus voltage phase/frequency PLL estimates the recovered
%   island reference. The bounded nonnegative power command uses its estimated
%   frequency plus rotor speed/phase error. This was chosen over a nominal-
%   frequency-only law because the latter fails modest +/-0.1-Hz offset probes.
%   The PLL is itself a PROJECT_DERIVED reduced subsystem, not an authenticated
%   relay. Its gains are not a replacement for the unchanged synchronism guard.
%   The Emag state uses a first-order PROJECT_DERIVED field-magnitude tracker:
%   online it follows Emag_ref; offline it tracks the local |V| within declared
%   bounds. This is NOT an AVR/GENROU field model. The existing strict
%   prospective current/MVA, dV/df/dtheta, dwell, timeout, and right-limit KCL
%   checks remain mandatory; this factory alone does not authorize a close.
%
%   PARAMS must come from stability.ne39_sg_reclose_plant_params(CASE_DATA).
%   The new semantic equilibrium layout is declared inside params as
%   'classical_reclose_pref_emag_ref'; parent mixed-equilibrium ABI integration
%   must add explicit support rather than relabel P_ref as actual Pm.
arguments
    case_data (1,1) struct
    device_id (1,1) string
    bus_id (1,1) double
    bus_position (1,1) double
    bus_ids (1,:) double
    V0 (1,1) double
    params (1,1) struct
end

if ~isfinite(real(V0)) || ~isfinite(imag(V0)) || abs(V0)<=0
    error('stability:sg_classical_reclose_device:badV0', ...
        'V0 must be one finite nonzero complex PF warm-start.');
end
if bus_id~=31 || ~isfield(params,'schema_id') || ...
        ~strcmp(params.schema_id,'ne39_sg31_classical_reclose_v1')
    error('stability:sg_classical_reclose_device:unsupportedPlant', ...
        'This factory accepts only the frozen opt-in NE39 SG31 design record.');
end
required={'H_system_s','D_system_pu','Xdp_system_pu','system_base_MVA', ...
    'frequency_Hz','P_ref0_pu','Emag0_pu','Pmax_pu','Pmax_MW', ...
    'no_load_loss_pu','S_rated_MVA','Emag_min_pu','Emag_max_pu', ...
    'Tsv_s','Tch_s','T_emag_s','Komega','Ktheta','pll_Kp_rad_s', ...
    'pll_Ki_rad_s2','pll_frequency_limit_pu','pll_phase_limit_rad', ...
    'omega_min_pu'};
for k=1:numel(required)
    name=required{k};
    if ~isfield(params,name) || ~isscalar(params.(name)) || ~isfinite(params.(name))
        error('stability:sg_classical_reclose_device:badParams', ...
            'params.%s must be one finite scalar.',name);
    end
end
if ~isfield(case_data,'machines') || ~isfield(case_data.machines,'units') || ...
        numel(case_data.machines.units)~=1 || case_data.machines.units(1).bus~=31
    error('stability:sg_classical_reclose_device:unsupportedComposition', ...
        'The case must contain exactly one SG31 machine.');
end
m=case_data.machines.units(1);
if abs(m.H-params.H_system_s)>1e-12*max(1,abs(m.H)) || ...
        abs(m.D-params.D_system_pu)>1e-12*max(1,abs(m.D)) || ...
        abs(m.Xdp-params.Xdp_system_pu)>1e-12*max(1,abs(m.Xdp))
    error('stability:sg_classical_reclose_device:sourceParameterMismatch', ...
        'The frozen plant record must preserve case H/D/Xdp exactly.');
end
if ~(params.H_system_s>0 && params.D_system_pu>=0 && ...
        params.Xdp_system_pu>0 && params.Pmax_pu>params.P_ref0_pu+params.no_load_loss_pu && ...
        params.no_load_loss_pu>0 && params.S_rated_MVA>0 && ...
        params.Tsv_s>0 && params.Tch_s>0 && params.T_emag_s>0 && ...
        params.pll_Kp_rad_s>0 && params.pll_Ki_rad_s2>0 && ...
        params.pll_frequency_limit_pu>0 && params.pll_phase_limit_rad>0 && ...
        params.Emag_min_pu>0 && params.Emag_max_pu>params.Emag_min_pu && ...
        params.omega_min_pu>0 && params.Komega>=0 && params.Ktheta>0)
    error('stability:sg_classical_reclose_device:parameterRange', ...
        'The frozen plant parameters do not define positive finite bounded dynamics.');
end

% Reuse the legacy constructor only for its audited uniform device ABI and
% parameter/base checks. The returned object is copied then its opt-in closures
% and state/input layout are replaced; no legacy closure or file is edited.
base=stability.sg_classical_device(case_data,device_id,bus_id, ...
    bus_position,bus_ids,V0,struct());
Pmax=params.Pmax_pu;
Emin=params.Emag_min_pu; Emax=params.Emag_max_pu;
L0=params.no_load_loss_pu;
Xdp=params.Xdp_system_pu;
key=matlab.lang.makeValidName(char(device_id),'ReplacementStyle','underscore');

% The healthy seed is built from the same PF operating point used by the frozen
% design. Actual shaft input includes declared no-load loss; reference input
% remains electrical scheduled P. No state is inferred from MBASE.
pf=pfsolver.powerflow_newton_raphson(case_data,struct('verbose',false, ...
    'plot_results',false,'max_iter',100,'tolerance',1e-10, ...
    'enforce_q_limits',false));
if ~pf.converged
    error('stability:sg_classical_reclose_device:powerFlow', ...
        'The in-house PF must converge before constructing the opt-in SG.');
end
bp=find(pf.external_bus_ids==bus_id,1);
if isempty(bp) || bp~=bus_position
    error('stability:sg_classical_reclose_device:busMap', ...
        'SG bus id and internal bus position do not match the PF mapping.');
end
Veq=pf.bus_voltage(bp)*exp(1i*deg2rad(pf.bus_angle_deg(bp)));
P0=pf.P_generation(bp); Q0=pf.Q_generation(bp);
I0=conj((P0+1i*Q0)/Veq);
E0=Veq+1i*Xdp*I0;
Emag0=abs(E0); delta0=angle(E0);
if abs(P0-params.P_ref0_pu)>1e-8 || abs(Emag0-params.Emag0_pu)>1e-8 || ...
        ~isfinite(Emag0) || Emag0<Emin || Emag0>Emax
    error('stability:sg_classical_reclose_device:designOperatingPointMismatch', ...
        'Frozen design record and factory PF operating point differ or exceed Emag limits.');
end
if P0+L0>=Pmax
    error('stability:sg_classical_reclose_device:primeMoverHeadroom', ...
        'The actual PF shaft power plus loss exceeds the declared positive Pmax.');
end

nx=7; nu=2;
state_names={'delta','omega','Psv','Pm','Emag','theta_hat','nu_hat'};
input_names={'P_ref','Emag_ref'};
x0=[delta0;1.0;P0+L0;P0+L0;Emag0;angle(Veq);0.0];
u0=[P0;Emag0];

dev=base;
dev.device_type='sg_classical';
dev.mode='synchronous';
dev.initial_mode='synchronous';
dev.initial_online=true;
dev.nx=nx; dev.nu=nu;
dev.state_names=state_names;
dev.input_names=input_names;
dev.x0=x0; dev.u0=u0;
dev.f=@(t,x,y,u,ec) reclose_f(x,y,u,bus_position,params,ec,key);
dev.current_injection=@(t,x,y,u,ec) reclose_current(x,y,u,bus_position,Xdp,params,ec,key);
dev.electrical_power=@(t,x,y,u,ec) reclose_power(x,y,u,bus_position,params,ec,key);
dev.reconstruct=@(t,x,y,u,ec) reclose_reconstruct(x,y,u,bus_position,params,ec,key);
dev.equilibrium_initialize=@(V,P,Q,ec) reclose_equilibrium_initialize(V,P,Q,Xdp,L0, ...
    Emin,Emax,params);
dev.active_state_indices=1:nx;
dev.dynamic_state_indices_for_context=@(~) 1:nx;
dev.frozen_state_indices=[]; dev.frozen_state_values=[];
dev.frozen_state_source=''; dev.frozen_state_classification='';
% Keep model-layout metadata inside params/provenance. Do not add an unnormalized
% top-level field that would break mixed SG/IBR struct-array concatenation.
params.equilibrium_control_layout='classical_reclose_pref_emag_ref';
params.input_semantics=struct('P_ref','electrical active-power reference pu', ...
    'Emag_ref','internal emf magnitude reference pu');
dev.provenance=struct('model','sg_classical_reclose_project_derived', ...
    'source','TAMU SG31 H/D/Xdp passed through; classical port equations reused; added plant PROJECT_DERIVED', ...
    'classification','PROJECT_DERIVED', ...
    'details',['7-state opt-in [delta,omega,Psv,Pm,Emag,theta_hat,nu_hat]; ' ...
    'u=[P_ref,Emag_ref] are references, not actual Pm/Emag or EMF6 Tm/Efd'], ...
    'params',params);
end

function dx=reclose_f(x,y,u,bp,p,ec,key)
online=resolve_online(ec,key);
[P_ref,Emag_ref]=resolve_refs(u,p);
[omega,Psv,Pm,Emag,theta_hat,nu_hat]=resolve_states(x,p);
V=complex(y(2*bp-1),y(2*bp));
if ~isfinite(real(V)) || ~isfinite(imag(V))
    error('stability:sg_classical_reclose_device:badVoltage', ...
        'Terminal voltage used by SG31 must be finite.');
end
Pe=0;
if online
    E=Emag*exp(1i*x(1));
    I=(E-V)/(1i*p.Xdp_system_pu);
    Pe=real(V*conj(I));
end
w0=2*pi*p.frequency_Hz;
nu_lim=p.pll_frequency_limit_pu*w0;
phase_bus=angle(V);
e_pll=wrap_angle(phase_bus-theta_hat);
e_pll=min(max(e_pll,-p.pll_phase_limit_rad),p.pll_phase_limit_rad);
nu_dot=p.pll_Ki_rad_s2*e_pll;
if (nu_hat>=nu_lim && nu_dot>0) || (nu_hat<=-nu_lim && nu_dot<0)
    nu_dot=0; % bounded frequency-estimator integrator, not a speed-state reset
end

theta_hat_dot=nu_hat+p.pll_Kp_rad_s*e_pll;
omega_hat=1+nu_hat/w0;
phase_error=wrap_angle(theta_hat-x(1));
if online
    raw=P_ref+p.no_load_loss_pu-p.Komega*(omega-1);
    Emag_cmd=Emag_ref;
else
    raw=p.no_load_loss_pu*omega_hat^2+ ...
        p.Komega*(omega_hat-omega)+p.Ktheta*phase_error;
    Emag_cmd=min(p.Emag_max_pu,max(p.Emag_min_pu,abs(V)));
end
Pc=min(p.Pmax_pu,max(0,raw));
Emag_cmd=min(p.Emag_max_pu,max(p.Emag_min_pu,Emag_cmd));
loss=p.no_load_loss_pu*omega^2;
rotor_damping=p.D_system_pu*omega*(omega-1);
omega_dot=(Pm-Pe-loss-rotor_damping)/(2*p.H_system_s*omega);

dx=[w0*(omega-1); omega_dot; (Pc-Psv)/p.Tsv_s; ...
    (Psv-Pm)/p.Tch_s; (Emag_cmd-Emag)/p.T_emag_s; ...
    theta_hat_dot; nu_dot];
if any(~isfinite(dx))
    error('stability:sg_classical_reclose_device:nonfiniteDerivative', ...
        'The opt-in SG31 plant produced a non-finite derivative.');
end
end

function I=reclose_current(x,y,u,bp,~,p,ec,key)
[P_ref,Emag_ref]=resolve_refs(u,p); %#ok<ASGLU>
[~,~,~,Emag]=resolve_states(x,p);
if ~resolve_online(ec,key), I=complex(0,0); return; end
V=complex(y(2*bp-1),y(2*bp));
E=Emag*exp(1i*x(1));
I=(E-V)/(1i*p.Xdp_system_pu);
end

function Pe=reclose_power(x,y,u,bp,p,ec,key)
I=reclose_current(x,y,u,bp,p.Xdp_system_pu,p,ec,key);
if ~resolve_online(ec,key), Pe=0; return; end
V=complex(y(2*bp-1),y(2*bp));
Pe=real(V*conj(I));
end

function out=reclose_reconstruct(x,y,u,bp,p,ec,key)
[Pref,Emagref]=resolve_refs(u,p);
[omega,Psv,Pm,Emag,theta_hat,nu_hat]=resolve_states(x,p);
V=complex(y(2*bp-1),y(2*bp));
online=resolve_online(ec,key);
if online
    I=(Emag*exp(1i*x(1))-V)/(1i*p.Xdp_system_pu);
    Pe=real(V*conj(I)); Qe=imag(V*conj(I));
else
    I=complex(0,0); Pe=0; Qe=0;
end
out=struct('mode','synchronous','online',online,'bus_position',bp, ...
    'delta',x(1),'omega',omega,'Psv',Psv,'Pm',Pm,'Tm',Pm, ...
    'P_ref',Pref,'Emag',Emag,'Emag_ref',Emagref, ...
    'theta_hat',theta_hat,'nu_hat_rad_s',nu_hat, ...
    'omega_grid_hat',1+nu_hat/(2*pi*p.frequency_Hz), ...
    'H_system',p.H_system_s,'D_system',p.D_system_pu, ...
    'Xdp',p.Xdp_system_pu,'Vbus',V,'V_open_circuit',Emag*exp(1i*x(1)), ...
    'Iinj',I,'P',Pe,'Q',Qe,'Imax',abs(I),'ImaxF_sys',Inf);
end

function xeq=reclose_equilibrium_initialize(V,P,Q,Xdp,L0,Emin,Emax,p)
if ~isscalar(V) || ~isfinite(real(V)) || ~isfinite(imag(V)) || abs(V)<=0 || ...
        ~isscalar(P) || ~isfinite(P) || ~isscalar(Q) || ~isfinite(Q) || P<=0
    error('stability:sg_classical_reclose_device:badEquilibriumPort', ...
        'Online equilibrium seed requires finite nonzero V and positive P, finite Q.');
end
I=conj((P+1i*Q)/V);
E=V+1i*Xdp*I;
Emag=abs(E);
if ~isfinite(Emag) || Emag<Emin || Emag>Emax || P+L0>=p.Pmax_pu
    error('stability:sg_classical_reclose_device:equilibriumOutsideDesign', ...
        'Online equilibrium port exceeds frozen Emag or shaft-power design limits.');
end
% theta_hat tracks terminal V phase, so PLL phase error is zero at the seed.
xeq=[angle(E);1.0;P+L0;P+L0;Emag;angle(V);0.0];
end

function [Pref,Eref]=resolve_refs(u,p)
if ~isnumeric(u) || ~isreal(u) || numel(u)~=2 || any(~isfinite(u(:)))
    error('stability:sg_classical_reclose_device:badInput', ...
        'Input must be [P_ref;Emag_ref] with two finite real references.');
end
Pref=u(1); Eref=u(2);
if Pref<0 || Pref>p.Pmax_pu || Eref<p.Emag_min_pu || Eref>p.Emag_max_pu
    error('stability:sg_classical_reclose_device:referenceOutsideDesign', ...
        'P_ref/Emag_ref exceed the explicit opt-in design envelope.');
end
end

function [omega,Psv,Pm,Emag,theta_hat,nu_hat]=resolve_states(x,p)
if ~isnumeric(x) || ~isreal(x) || numel(x)~=7 || any(~isfinite(x(:)))
    error('stability:sg_classical_reclose_device:badState', ...
        'Opt-in SG31 state must be seven finite real values.');
end
omega=x(2); Psv=x(3); Pm=x(4); Emag=x(5); theta_hat=x(6); nu_hat=x(7);
if omega<=p.omega_min_pu
    error('stability:sg_classical_reclose_device:lowSpeed', ...
        'The energy-form rotor model is undefined below its declared positive-speed domain.');
end
tol=1e-10*max(1,p.Pmax_pu);
if Psv < -tol || Psv>p.Pmax_pu+tol || Pm < -tol || Pm>p.Pmax_pu+tol
    error('stability:sg_classical_reclose_device:shaftPowerDomain', ...
        'Actual valve and shaft powers must remain in [0,Pmax].');
end
if Emag<p.Emag_min_pu-1e-10 || Emag>p.Emag_max_pu+1e-10
    error('stability:sg_classical_reclose_device:emagDomain', ...
        'Actual reduced field magnitude must stay inside its declared bounds.');
end
if abs(nu_hat)>p.pll_frequency_limit_pu*2*pi*p.frequency_Hz+1e-9
    error('stability:sg_classical_reclose_device:pllFrequencyDomain', ...
        'Estimated terminal-frequency deviation exceeds its declared PLL domain.');
end
end

function online=resolve_online(ec,key)
online=true;
if isempty(ec) || ~isstruct(ec) || ~isfield(ec,'hybrid_state') || ...
        ~isstruct(ec.hybrid_state) || ~isfield(ec.hybrid_state,'device_online')
    return;
end
if isfield(ec.hybrid_state.device_online,key)
    online=logical(ec.hybrid_state.device_online.(key));
end
end

function e=wrap_angle(a)
e=mod(a+pi,2*pi)-pi;
end
