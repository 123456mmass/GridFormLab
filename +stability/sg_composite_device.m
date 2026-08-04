function dev = sg_composite_device(case_data, device_id, bus_id, bus_position, bus_ids, V0, params)
%SG_COMPOSITE_DEVICE  EMF6 synchronous machine as a composite_dae 5-arg device.
%   dev = sg_composite_device(CASE_DATA, DEVICE_ID, BUS_ID, BUS_POSITION,
%       BUS_IDS, V0, PARAMS) builds a single-machine EMF6 synchronous generator
%   device conforming to the stability.composite_dae ABI (R3 Rev 2, 5-arg
%   closures f/current_injection/electrical_power/reconstruct @(t,x_dev,y,u_dev,event_context)).
%
%   This wraps the EXISTING audited EMF6 equations (synchronous_emf6_ssa:
%   6th-order Kundur/GENTPJ) as a single-machine composite device, so the mixed
%   SG1 + 4-IBR network can be simulated through one composite DAE. The stator
%   current comes from the EMF6 stator Id/Iq equations via sg_stator_current
%   (NOT reverse-derived from Pe/V — correction 2).
%
%   State (6, EMF6): x = [delta; omega; Eqp; Edp; Eqpp; Edpp].
%   Inputs: u=[Tm;Efd]. At a physical REF-bus equilibrium,
%   mixed_equilibrium_solve determines these two constant control inputs while
%   enforcing the specified |V|/angle and every KCL row. TS holds the solved
%   inputs constant; they are not re-solved each step.
%
%   Breaker-open physics (clarification 4), read from event_context.hybrid_state:
%     - online  -> connected stator: full EMF6 stator current into network, Te from
%                  stator, swing 2H*domega/dt = (Tm - Te - D*omega).
%     - offline -> ZERO network injection (Id=Iq=0, Te=0); open-circuit flux decay
%                  (Eqp,Edp,Eqpp,Edpp evolve with I=0); swing coasts on a FROZEN
%                  CASE_DEFINED mechanical-power policy (Tm held at pre-trip value).
%                  delta and omega still evolve (swing coasts; synchronism
%                  compares generator-side open-breaker EMF vs network bus V).
%   The online/offline flag is read from event_context.hybrid_state.device_online.(id);
%   if event_context is empty (equilibrium path), defaults to online=true.
%
%   STATUS: equilibrium/TS/SSSA structural contracts verified. Mission-level
%   IBR production readiness remains NOT_READY until all deferred phases close.
%
%   Source: synchronous_emf6_ssa (Kundur/GENTPJ 6th-order, in repo); IEEE 1110-2002
%   Model 2.2 structure. Kodsi 60Hz SG data (CASE_DEFINED, decision ledger item 7).

arguments
    case_data struct
    device_id (1,1) string
    bus_id (1,1) double
    bus_position (1,1) double
    bus_ids (1,:) double
    V0 (1,1) double
    params struct
end

if ~isfinite(V0) || abs(V0) <= 0
    error('stability:sg_composite_device:badV0', ...
        'V0 must be finite with |V0|>0 (PF warm-start required); got %.6g.', V0);
end

% --- Build the EMF6 machine model (single machine, base-converted) -------------
% The normal route reuses synchronous_emf6_ssa machine_parameters and
% initialize_equilibrium.  A mixed IEEE14 driver may provide an audited
% coefficient override when its tap-aware network is not representable by the
% standalone SSSA network_model; this still enters the SAME local EMF6 equations
% below and never imports an external solution.
if isfield(params,'emf6_machine') && isfield(params,'emf6_units') && isfield(params,'emf6_init')
    machine = params.emf6_machine;
    units = params.emf6_units;
    init = params.emf6_init;
else
    emf_opt = struct('fd_eps', 3e-6, 'equilibrium_tolerance', 1e-10, ...
        'newton_max_iterations', 300, 'load_model', 'cz_p_cz_q');
    emf = stability.synchronous_emf6_ssa(case_data, emf_opt);
    machine = emf.machine;
    units = emf.units;
    init = emf.init;
end
if ~isfield(machine,'ng'), machine.ng=1; end
ng = machine.ng;
if ng ~= 1
    error('stability:sg_composite_device:singleMachineOnly', ...
        'sg_composite_device expects a single-machine case (ng=1); got ng=%d.', ng);
end

% SG1 must be at the requested bus.
if units.bus_idx(1) ~= bus_position
    error('stability:sg_composite_device:busMismatch', ...
        'EMF6 machine 1 bus_idx=%d but requested bus_position=%d.', ...
        units.bus_idx(1), bus_position);
end

nx = 6;
nu = 2;
state_names = {'delta','omega','Eqp','Edp','Eqpp','Edpp'};
x0 = init.x0(1:6);     % single-machine state slice
% PF-derived defaults are the a-priori warm start. The physical mixed REF
% equilibrium may solve different constant Tm/Efd values.
Tm_eq = init.Tm(1);
Efd_eq = init.Efd(1);
u0 = [Tm_eq; Efd_eq];

% --- Tpq0=0 singular-limit frozen-state detection ---------------------------
% When Tpq0==0 exactly (Kodsi round-rotor, no q-axis transient), Edp is
% algebraically eliminated: 0 = c_q*Edpp - d_q*Edp.
% For Kodsi: c_q=0, d_q=1 => Edp=0.
% Ref: IEEE14_GENERIC_IBR_MACHINE_TRANSFER.md §9; execution plan §Tpq0=0.
Tpq0_val = machine.Tpq0(1);
has_frozen_edp = (Tpq0_val == 0);
frozen_state_indices = [];
frozen_state_values  = [];
frozen_state_source  = '';
active_state_indices = 1:nx;   % default: all active
if has_frozen_edp
    frozen_state_indices = 4;   % Edp is state index 4
    frozen_state_values  = 0;   % algebraic value Edp=0
    frozen_state_source  = 'Tpq0=0 singular limit: Edp=c_q*Edpp/d_q; Kodsi round-rotor c_q=0,d_q=1 => Edp=0';
    active_state_indices = [1 2 3 5 6];  % exclude Edp
    % Enforce Edp=0 in initial state
    x0(4) = 0;
end

bp = bus_position;

% --- Differential RHS (5-arg ABI) ---------------------------------------------
%   online: full EMF6 differential_residual (single-machine slice).
%   offline: open-circuit flux decay (I=0) + coast swing (Te=0, Tm frozen).
f = @(t, x_dev, y, u_dev, event_context) sg_f( ...
    x_dev, y, u_dev, bp, machine, units, event_context, device_id);

% --- current_injection (5-arg): stator Id/Iq -> network frame (correction 2) ---
current_injection = @(t, x_dev, y, u_dev, event_context) sg_current( ...
    x_dev, y, bp, machine, units, event_context, device_id);

% --- electrical_power (5-arg): direct air-gap Te (not reverse from Pe/V) ------
electrical_power = @(t, x_dev, y, u_dev, event_context) sg_pe( ...
    x_dev, y, bp, machine, units, event_context, device_id);

% --- reconstruct (5-arg) -------------------------------------------------------
reconstruct = @(t, x_dev, y, u_dev, event_context) sg_reconstruct( ...
    x_dev, y, u_dev, bp, machine, units, event_context, device_id);

dev = struct();
dev.name = char(device_id);
dev.device_id = char(device_id);
dev.bus_id = bus_id;
dev.bus_position = bus_position;
dev.bus_ids = bus_ids(:).';
dev.device_type = 'sg_emf6_composite';
dev.mode = 'sg';
dev.initial_mode = 'sg';
dev.initial_online = true;
dev.nx = nx;
dev.nu = nu;
dev.state_names = state_names;
dev.input_names = {'Tm','Efd'};
dev.x0 = x0;
dev.u0 = u0;
dev.f = f;
dev.current_injection = current_injection;
dev.electrical_power = electrical_power;
dev.reconstruct = reconstruct;
% Exact stationary seed used only by the mixed-equilibrium warm-start.
% It applies the same EMF6 stator/frame equations as sg_f/sg_current to a
% supplied terminal V and P+jQ; the coupled DAE remains the acceptance gate.
dev.equilibrium_initialize = @(V_bus,P_terminal_pu,Q_terminal_pu,~) ...
    sg_equilibrium_initialize(V_bus,P_terminal_pu,Q_terminal_pu,machine,units);
dev.provenance = struct( ...
    'model','sg_emf6_composite_phaseB_structural_only', ...
    'source','synchronous_emf6_ssa (Kundur/GENTPJ 6th-order) wrapped to 5-arg ABI', ...
    'nx', nx, 'nu', nu, ...
    'sg_data','Kodsi 60Hz Table A.2 (CASE_DEFINED, decision ledger item 7)', ...
    'stator_current','sg_stator_current (EMF6 stator Id/Iq -> network frame; correction 2)', ...
    'breaker_open_physics','offline: Id=Iq=0, Te=0, open-circuit flux decay, Tm frozen (clarification 4)', ...
    'equilibrium_controls','u=[Tm;Efd] solved only for selected online SG REF, then held constant', ...
    'readiness','STRUCTURAL_ONLY');
dev.frozen_state_indices = frozen_state_indices;
dev.frozen_state_values  = frozen_state_values;
dev.frozen_state_source  = frozen_state_source;
dev.active_state_indices = active_state_indices;
% Equilibrium excludes a breaker-open SG because retained Tm generally has no
% stationary root, but TS integrates these states through the open-circuit
% flux/coast equations implemented by dev.f.
dev.dynamic_state_indices_for_context = @(~) active_state_indices;
dev.frozen_state_classification = 'SOURCE_DEFINED singular limit';
end

% =========================================================================
function x_eq = sg_equilibrium_initialize(V, P, Q, machine, units)
%SG_EQUILIBRIUM_INITIALIZE Construct the EMF6 stationary state at one port.
% The angle condition is the source-model stator constraint Vd+Ra Id-Xq Iq=0.
% This is the single-machine form of synchronous_emf6_ssa.initialize_equilibrium.
if ~isscalar(V) || ~isfinite(real(V)) || ~isfinite(imag(V)) || abs(V)<=0 || ...
        ~isscalar(P) || ~isscalar(Q) || ~isfinite(P) || ~isfinite(Q)
    error('stability:sg_composite_device:badEquilibriumPort', ...
        'SG equilibrium initialization requires finite nonzero V and finite P,Q.');
end
I = conj((P + 1i*Q)/V);
delta = angle(V + (machine.Ra(1) + 1i*machine.Xq(1))*I);
for it = 1:30
    r0 = angle_constraint(delta,V,I,machine);
    if abs(r0) <= 1e-12, break; end
    h = 1e-6;
    dr = (angle_constraint(delta+h,V,I,machine) - ...
          angle_constraint(delta-h,V,I,machine))/(2*h);
    if ~isfinite(dr) || abs(dr) < 1e-12
        error('stability:sg_composite_device:equilibriumAngleJacobian', ...
            'SG equilibrium angle constraint has a singular derivative.');
    end
    delta = delta - r0/dr;
end
if abs(angle_constraint(delta,V,I,machine)) > 1e-9
    error('stability:sg_composite_device:equilibriumAngle', ...
        'SG equilibrium angle initialization did not converge.');
end
[Id,Iq] = stability.kundur_book_dq(I,delta);
[Vd,Vq] = stability.kundur_book_dq(V,delta);
Eqpp = Vq + machine.Ra(1)*Iq + machine.Xdpp(1)*Id;
Edpp = Vd + machine.Ra(1)*Id - machine.Xqpp(1)*Iq;
Eqp = Eqpp + (machine.Xdp(1)-machine.Xdpp(1))*Id;
Edp = Edpp - (machine.Xqp(1)-machine.Xqpp(1))*Iq;
if machine.Tpq0(1) == 0, Edp = 0; end
x_eq = [delta; 0; Eqp; Edp; Eqpp; Edpp];
end

function r = angle_constraint(delta,V,I,machine)
[Id,Iq] = stability.kundur_book_dq(I,delta);
[Vd,~] = stability.kundur_book_dq(V,delta);
r = Vd + machine.Ra(1)*Id - machine.Xq(1)*Iq;
end

% =========================================================================
function online = resolve_online(event_context, device_id)
% Read online flag from hybrid_state snapshot; default online when ec empty.
if isempty(event_context) || ~isstruct(event_context) || ...
        ~isfield(event_context, 'hybrid_state') || isempty(event_context.hybrid_state)
    online = true; return;
end
hs = event_context.hybrid_state;
if isfield(hs, 'device_online') && isstruct(hs.device_online)
    key = matlab.lang.makeValidName(char(device_id), 'ReplacementStyle', 'underscore');
    if isfield(hs.device_online, key)
        online = logical(hs.device_online.(key));
    else
        online = true;
    end
else
    online = true;
end
end

% =========================================================================
function dx = sg_f(x_dev, y, u_dev, bp, machine, units, event_context, device_id)
online = resolve_online(event_context, device_id);
[Tm, Efd] = resolve_controls(u_dev);
k = 1;
delta = x_dev(1); w = x_dev(2);
Eqp = x_dev(3); Edp = x_dev(4); Eqpp = x_dev(5); Edpp = x_dev(6);
if online
    % Connected stator: full EMF6 stator solve for Id, Iq, Vd, Vq.
    [Id, Iq, Vd, Vq] = sg_machine_algebraic(x_dev, y, bp, machine, k);
    Te = Vd*Id + Vq*Iq + machine.Ra(k)*(Id^2 + Iq^2);
    dx1 = machine.w0 * w;
    dx2 = (Tm - Te - units.D_system(k)*w) / (2*units.H_system(k));
    dx3 = (Efd + machine.c_d(k)*Eqpp - machine.d_d(k)*Eqp) / machine.Tpd0(k);
    if machine.Tpq0(k) == 0
        dx4 = 0;   % Tpq0=0 singular limit: Edp algebraically eliminated (frozen at 0)
    else
        dx4 = (machine.c_q(k)*Edpp - machine.d_q(k)*Edp) / machine.Tpq0(k);
    end
    dx5 = (Eqp - Eqpp - (machine.Xdp(k) - machine.Xdpp(k))*Id) / machine.Tppd0(k);
    dx6 = (Edp - Edpp + (machine.Xqp(k) - machine.Xqpp(k))*Iq) / machine.Tppq0(k);
else
    % Breaker OPEN (clarification 4): Id=Iq=0, Te=0. Open-circuit flux decay:
    %   dEqp/dt  = (Efd + c_d*Eqpp - d_d*Eqp)/Tpd0   (I=0 path)
    %   dEdp/dt  = (c_q*Edpp - d_q*Edp)/Tpq0  (or 0 if Tpq0==0 frozen)
    %   dEqpp/dt = (Eqp - Eqpp)/Tppd0   (no (Xdp-Xdpp)*Id term)
    %   dEdpp/dt = (Edp - Edpp)/Tppq0   (no (Xqp-Xqpp)*Iq term)
    % Swing coasts: 2H*dw/dt = Tm_frozen - 0 - D*w  (Tm held at pre-trip value).
    dx1 = machine.w0 * w;
    dx2 = (Tm - units.D_system(k)*w) / (2*units.H_system(k));
    dx3 = (Efd + machine.c_d(k)*Eqpp - machine.d_d(k)*Eqp) / machine.Tpd0(k);
    if machine.Tpq0(k) == 0
        dx4 = 0;   % Tpq0=0 singular limit: Edp frozen at 0
    else
        dx4 = (machine.c_q(k)*Edpp - machine.d_q(k)*Edp) / machine.Tpq0(k);
    end
    dx5 = (Eqp - Eqpp) / machine.Tppd0(k);
    dx6 = (Edp - Edpp) / machine.Tppq0(k);
end
dx = [dx1; dx2; dx3; dx4; dx5; dx6];
end

% =========================================================================
function Ig = sg_current(x_dev, y, bp, machine, units, event_context, device_id)
online = resolve_online(event_context, device_id);
if online
    Ig = stability.sg_stator_current(x_dev, y, bp, machine, units, 1);
else
    Ig = 0;   % breaker open: zero network injection (clarification 4)
end
end

% =========================================================================
function Pe = sg_pe(x_dev, y, bp, machine, units, event_context, device_id)
online = resolve_online(event_context, device_id);
if online
    [Id, Iq, Vd, Vq] = sg_machine_algebraic(x_dev, y, bp, machine, 1);
    Te = Vd*Id + Vq*Iq + machine.Ra(1)*(Id^2 + Iq^2);
    Pe = Te;   % electrical torque (pu, air-gap); equals electrical power at synchronous speed
else
    Pe = 0;    % breaker open: Te=0
end
end

% =========================================================================
function out = sg_reconstruct(x_dev, y, u_dev, bp, machine, units, event_context, device_id)
online = resolve_online(event_context, device_id);
[Tm, Efd] = resolve_controls(u_dev);
out = struct('mode','sg','online',online,'bus_position',bp, ...
    'delta',x_dev(1),'omega',x_dev(2),'Eqp',x_dev(3),'Edp',x_dev(4), ...
    'Eqpp',x_dev(5),'Edpp',x_dev(6),'Tm',Tm,'Efd',Efd, ...
    'H_system',units.H_system(1), ...
    'V_open_circuit',(x_dev(5)-1i*x_dev(6))*exp(1i*x_dev(1)));
if online
    [Id, Iq, Vd, Vq] = sg_machine_algebraic(x_dev, y, bp, machine, 1);
    out.Id = Id; out.Iq = Iq; out.Vd = Vd; out.Vq = Vq;
else
    out.Id = 0; out.Iq = 0; out.Vd = NaN; out.Vq = NaN;   % open breaker
end
end


% =========================================================================
function [Tm,Efd] = resolve_controls(u_dev)
%RESOLVE_CONTROLS  Fail-closed constant SG control-input contract.
if ~isnumeric(u_dev) || ~isreal(u_dev) || numel(u_dev) ~= 2 || ...
        any(~isfinite(u_dev(:)))
    error('stability:sg_composite_device:badInput', ...
        'SG input must be exactly two finite real values [Tm;Efd].');
end
Tm = u_dev(1);
Efd = u_dev(2);
end

% =========================================================================
function [Id, Iq, Vd, Vq] = sg_machine_algebraic(x_dev, y, bp, machine, k)
% Single-machine slice of synchronous_emf6_ssa.machine_algebraic (audited, reused).
delta = x_dev(1); Eqpp = x_dev(5); Edpp = x_dev(6);
V = complex(y(2*bp-1), y(2*bp));
[Vd, Vq] = stability.kundur_book_dq(V, delta);
rhs_d = Vd - Edpp;
rhs_q = Vq - Eqpp;
det = machine.Xdpp(k)*machine.Xqpp(k) + machine.Ra(k)^2;
Id = (-machine.Ra(k)*rhs_d - machine.Xqpp(k)*rhs_q) / det;
Iq = ( machine.Xdpp(k)*rhs_d - machine.Ra(k)*rhs_q) / det;
end
