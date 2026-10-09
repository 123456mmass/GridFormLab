function dev = sg_classical_device(case_data, device_id, bus_id, bus_position, bus_ids, V0, params)
%SG_CLASSICAL_DEVICE  Classical (2nd-order) synchronous machine as a composite device.
%   dev = stability.sg_classical_device(CASE_DATA, DEVICE_ID, BUS_ID,
%       BUS_POSITION, BUS_IDS, V0, PARAMS) builds ONE classical synchronous
%   machine (constant EMF |E| behind X'd, swing equation) conforming to the
%   stability.composite_dae ABI (5-arg closures
%       f / current_injection / electrical_power / reconstruct
%       @(t, x_dev, y, u_dev, event_context)).
%
%   WHY THIS EXISTS.  stability.sg_composite_device is the EMF6 (6th-order
%   Kundur/GENTPJ) machine and its local initializer supports exactly one SG.
%   The New England 39-bus hybrid study keeps FIVE SGs, and no published
%   New England EMF6 parameter set (Xd', Xd'', Td0', Td0''...) exists in this
%   repository, in the MATLAB/Python installs, or in docs/ (see
%   +cases/ne39_machine_parameters.m header).  Inventing EMF6 time constants
%   would be fabricating data.  This device instead wraps the SAME classical
%   equations the case already owns (+stability/classical_dae.m) so the mixed
%   SG+IBR engine can drive them through one composite DAE.
%
%   EQUATIONS (bit-compatible with +stability/classical_dae.m solve_network_linear):
%     E   = |E|_u * exp(1i*delta)                 (|E| behind X'd, rad)
%     I_b = (E - V_bus) / (1i*X'd)                (positive INTO the network)
%     Pe  = real(V_bus * conj(I_b))               (air-gap electrical power)
%     d(delta)/dt = w_s * (omega - 1)
%     d(omega)/dt = ( Pm - Pe - D*(omega - 1) ) / (2 H)
%   with x = [delta; omega] (rad, pu, omega=1 at nominal) and u = [Pm; Emag]
%   where Emag = |E| (pu).  X'd and H, D are on the SYSTEM base (100 MVA);
%   |E| is pu.
%
%   INPUT NAMES ARE DELIBERATELY 'Pm' and 'Emag', NOT 'Tm'/'Efd'.  Tm/Efd are
%   the EMF6 mechanical-torque / field-voltage pair (u=[Tm;Efd] drives the
%   flux-state equations dx3..dx6).  The classical model has no field-flux
%   state and its second equilibrium control is the internal EMF MAGNITUDE
%   |E|, which is NOT the EMF6 field voltage Efd.  mixed_equilibrium_solve
%   discovers the reference SG's two equilibrium inputs by NAME, so the
%   classical pair is found generically without relabelling |E| as Efd.
%
%   BREAKER-OPEN PHYSICS (matches sg_composite_device clarification 4):
%     - online  -> full stator current into the network; swing uses Pe.
%     - offline -> ZERO network injection (I_b = 0, Pe = 0); the swing coasts on
%                  the FROZEN mechanical power Pm (no re-dispatch), so delta and
%                  omega still evolve for a later synchronism check.
%   The online/offline flag is read from
%   event_context.hybrid_state.device_online.(id); an empty event_context (the
%   equilibrium path) means online.
%
%   PARAMS fields (all on the SYSTEM base unless stated):
%     H    scalar   inertia constant, seconds
%     D    scalar   damping, pu
%     Xdp  scalar   X'd, pu
%   PARAMS may also carry Pm_pu / Emag_pu overrides (tests); absent, both are
%   derived from the case's own power flow at this bus, exactly as
%   +stability/classical_dae.m derives delta0/|E|0 from the PF.
%
%   Classification: equations = the case's own classical model (see
%   +stability/classical_dae.m); H/D/X'd = CASE_DEFINED (see
%   +cases/ne39_machine_parameters.m, PROJECT_DERIVED).  This device adds no
%   fitted parameter of its own.
%
%   See also stability.classical_dae, stability.expand_machines_classical,
%   stability.sg_composite_device, stability.build_mixed_resource_devices.

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
    error('stability:sg_classical_device:badV0', ...
        'V0 must be finite with |V0|>0 (PF warm-start required); got %.6g.', V0);
end

% H/D/X'd may be passed directly (tests) or read from case_data.machines.units
% (the generic engine path: the SG factory reads dynamics from the case, exactly
% as the EMF6 sg_composite_device does).  The case-owned values are already on
% the SYSTEM base (see cases.case_ne39 / cases.case_ne39_5sg_5ibr).
params = local_fill_from_machines(case_data, bus_id, params);
H = local_scalar(params, 'H');
D = local_scalar(params, 'D');
Xdp = local_scalar(params, 'Xdp');
if ~(isfinite(H) && H > 0)
    error('stability:sg_classical_device:badH', 'params.H must be finite and > 0 (got %.6g).', H);
end
if ~(isfinite(D) && D >= 0)
    error('stability:sg_classical_device:badD', 'params.D must be finite and >= 0 (got %.6g).', D);
end
if ~(isfinite(Xdp) && Xdp > 0)
    error('stability:sg_classical_device:badXdp', 'params.Xdp must be finite and > 0 (got %.6g).', Xdp);
end

% --- Power flow at this bus: the case's own operating point -----------------
pf = pfsolver.powerflow_newton_raphson(case_data, struct('verbose',false, ...
    'plot_results',false,'max_iter',50,'tolerance',1e-10,'enforce_q_limits',false));
if ~pf.converged
    error('stability:sg_classical_device:powerFlow', ...
        'In-house Newton PF did not converge for SG %s.', device_id);
end
bp = find(pf.external_bus_ids == bus_id, 1);
if isempty(bp)
    error('stability:sg_classical_device:busMap', ...
        'SG %s bus %d is absent from the PF bus list.', device_id, bus_id);
end
V0c = pf.bus_voltage(bp) .* exp(1i*deg2rad(pf.bus_angle_deg(bp)));
Sg  = pf.P_generation(bp) + 1i*pf.Q_generation(bp);
Ig0 = conj(Sg / V0c);
E0  = V0c + 1i*Xdp*Ig0;

delta0 = angle(E0);
if isfield(params,'Emag_pu') && ~isempty(params.Emag_pu)
    Emag0 = double(params.Emag_pu);
else
    Emag0 = abs(E0);
end
if isfield(params,'Pm_pu') && ~isempty(params.Pm_pu)
    Pm0 = double(params.Pm_pu);
else
    Pm0 = real(V0c * conj(Ig0));   % = P_generation at the PF port (see header)
end
if ~(isfinite(Emag0) && Emag0 > 0)
    error('stability:sg_classical_device:badEmag', ...
        'SG %s solved a non-positive internal EMF magnitude (%.6g).', device_id, Emag0);
end
if ~isfinite(Pm0)
    error('stability:sg_classical_device:badPm', ...
        'SG %s solved a non-finite mechanical power.', device_id);
end

ws = 2*pi*local_freq(case_data);

nx = 2;
nu = 2;
state_names = {'delta','omega'};
input_names = {'Pm','Emag'};
x0 = [delta0; 1.0];
u0 = [Pm0; Emag0];

bp_pos = bus_position;
status_key = matlab.lang.makeValidName(char(device_id), ...
    'ReplacementStyle', 'underscore');

dev = struct();
dev.name = char(device_id);
dev.device_id = char(device_id);
dev.bus_id = bus_id;
dev.bus_position = bus_position;
dev.bus_ids = bus_ids(:).';
dev.device_type = 'sg_classical';
dev.mode = 'synchronous';
dev.initial_mode = 'synchronous';
dev.initial_online = true;
dev.nx = nx;
dev.nu = nu;
dev.state_names = state_names;
dev.input_names = input_names;
dev.x0 = x0;
dev.u0 = u0;

dev.f = @(t, x_dev, y, u_dev, event_context) sc_f( ...
    x_dev, y, u_dev, bp_pos, H, D, Xdp, ws, event_context, status_key);
dev.current_injection = @(t, x_dev, y, u_dev, event_context) sc_current( ...
    x_dev, y, u_dev, bp_pos, Xdp, event_context, status_key);
dev.electrical_power = @(t, x_dev, y, u_dev, event_context) sc_pe( ...
    x_dev, y, u_dev, bp_pos, Xdp, event_context, status_key);
dev.reconstruct = @(t, x_dev, y, u_dev, event_context) sc_reconstruct( ...
    x_dev, y, u_dev, bp_pos, H, Xdp, event_context, status_key);

% Exact stationary seed used by the mixed-equilibrium warm start.  Applies the
% same classical port equation as the closures above to a supplied terminal V
% and P+jQ; the coupled DAE/KCL residual remains the acceptance gate.
dev.equilibrium_initialize = @(V_bus,P_terminal_pu,Q_terminal_pu,~) ...
    sc_equilibrium_initialize(V_bus,P_terminal_pu,Q_terminal_pu,Xdp);

% The classical machine has NO field-flux state and NO frozen algebraic state.
% The field set below is DELIBERATELY the same 27 fields stability.sg_composite_
% device (EMF6) emits: build_mixed_resource_devices stacks SG and IBR devices by
% vertcat, which requires identical field names.  In particular the device does
% NOT carry H/D/X'd/ws as top-level fields -- those live only inside the closures
% above -- and it declares its equilibrium-control layout by its INPUT NAMES
% ([Pm, Emag]), which is the ABI's own semantic declaration, rather than by an
% extra field that would break heterogeneous concatenation.
dev.frozen_state_indices = [];
dev.frozen_state_values  = [];
dev.frozen_state_source  = '';
dev.active_state_indices = 1:nx;
dev.dynamic_state_indices_for_context = @(~) (1:nx);
dev.frozen_state_classification = '';
dev.provenance = struct( ...
    'model', 'sg_classical_composite', ...
    'source', ['classical (2nd-order) equations reused from ' ...
               '+stability/classical_dae.m; base conversion per ' ...
               '+stability/expand_machines_classical.m'], ...
    'classification', 'equations CASE_DEFINED (classical model); H/D/X''d CASE_DEFINED', ...
    'details', ['nx=2 [delta,omega]; u=[Pm,Emag]; Emag is |E| behind X''d, ' ...
                'NOT the EMF6 field voltage Efd']);
end

function v = local_scalar(s, name)
if ~isfield(s, name) || isempty(s.(name))
    error('stability:sg_classical_device:missingParam', ...
        'params.%s is required for the classical SG device.', name);
end
v = double(s.(name));
if ~isscalar(v)
    error('stability:sg_classical_device:nonScalarParam', ...
        'params.%s must be a scalar.', name);
end
end

function f = local_freq(case_data)
f = 60;
if isfield(case_data,'base_values') && isfield(case_data.base_values,'frequency_Hz') && ...
        ~isempty(case_data.base_values.frequency_Hz)
    f = double(case_data.base_values.frequency_Hz);
end
end

% =========================================================================
function online = resolve_online(event_context, status_key)
if isempty(event_context) || ~isstruct(event_context) || ...
        ~isfield(event_context, 'hybrid_state') || isempty(event_context.hybrid_state)
    online = true; return;
end
hs = event_context.hybrid_state;
if isfield(hs, 'device_online') && isstruct(hs.device_online) && ...
        isfield(hs.device_online, status_key)
    online = logical(hs.device_online.(status_key));
else
    online = true;
end
end

function [Pm, Emag] = resolve_controls(u_dev)
if ~isnumeric(u_dev) || ~isreal(u_dev) || numel(u_dev) ~= 2 || any(~isfinite(u_dev(:)))
    error('stability:sg_classical_device:badInput', ...
        'SG classical input must be exactly two finite real values [Pm; Emag].');
end
Pm = u_dev(1);
Emag = u_dev(2);
if ~(Emag > 0)
    error('stability:sg_classical_device:badEmagInput', ...
        'SG classical Emag input must be > 0 (got %.6g).', Emag);
end
end

% =========================================================================
function dx = sc_f(x_dev, y, u_dev, bp, H, D, Xdp, ws, event_context, status_key)
online = resolve_online(event_context, status_key);
[Pm, Emag] = resolve_controls(u_dev);
delta = x_dev(1); w = x_dev(2);
if online
    V = complex(y(2*bp-1), y(2*bp));
    E = Emag*exp(1i*delta);
    Ib = (E - V) / (1i*Xdp);
    Pe = real(V * conj(Ib));
else
    Pe = 0;   % breaker open: zero network injection
end
dx = [ws*(w - 1); (Pm - Pe - D*(w - 1)) / (2*H)];
end

function Ib = sc_current(x_dev, y, u_dev, bp, Xdp, event_context, status_key)
online = resolve_online(event_context, status_key);
if ~online
    Ib = complex(0, 0);
    return;
end
[~, Emag] = resolve_controls(u_dev);
delta = x_dev(1);
V = complex(y(2*bp-1), y(2*bp));
E = Emag*exp(1i*delta);
Ib = (E - V) / (1i*Xdp);
end

function Pe = sc_pe(x_dev, y, u_dev, bp, Xdp, event_context, status_key)
online = resolve_online(event_context, status_key);
if ~online
    Pe = 0; return;
end
[~, Emag] = resolve_controls(u_dev);
delta = x_dev(1);
V = complex(y(2*bp-1), y(2*bp));
E = Emag*exp(1i*delta);
Ib = (E - V) / (1i*Xdp);
Pe = real(V * conj(Ib));
end

function out = sc_reconstruct(x_dev, y, u_dev, bp, H, Xdp, event_context, status_key)
online = resolve_online(event_context, status_key);
[Pm, Emag] = resolve_controls(u_dev);
delta = x_dev(1); w = x_dev(2);
V = complex(y(2*bp-1), y(2*bp));
out = struct('mode','synchronous','online',online,'bus_position',bp, ...
    'delta',delta,'omega',w,'Pm',Pm,'Emag',Emag,'H_system',H,'Xdp',Xdp, ...
    'Vbus',V,'V_open_circuit',Emag*exp(1i*delta));
if online
    E = Emag*exp(1i*delta);
    Ib = (E - V) / (1i*Xdp);
    out.Iinj = Ib;
    out.P = real(V*conj(Ib));
    out.Q = imag(V*conj(Ib));
    out.Imax = abs(Ib);
else
    out.Iinj = complex(0,0);
    out.P = 0; out.Q = 0; out.Imax = 0;
end
out.ImaxF_sys = Inf;   % a synchronous machine has no inverter transient limit
end

% =========================================================================
function x_eq = sc_equilibrium_initialize(V, P, Q, Xdp)
%SC_EQUILIBRIUM_INITIALIZE  Stationary classical state at one terminal port.
%   Given the terminal complex V and P+jQ (pu, system base), the internal EMF
%   that produces that current is E = V + 1i*X'd*conj(S/V); the rotor angle is
%   angle(E) and omega = 1.  |E| (the Emag input) is derived by the caller from
%   the PF; this returns only the two classical STATES [delta; omega].
if ~isscalar(V) || ~isfinite(real(V)) || ~isfinite(imag(V)) || abs(V) <= 0 || ...
        ~isscalar(P) || ~isscalar(Q) || ~isfinite(P) || ~isfinite(Q)
    error('stability:sg_classical_device:badEquilibriumPort', ...
        'SG classical equilibrium initialization requires finite nonzero V and finite P,Q.');
end
I = conj((P + 1i*Q)/V);
E = V + 1i*Xdp*I;
x_eq = [angle(E); 1.0];
end

% =========================================================================
function params = local_fill_from_machines(case_data, bus_id, params)
%LOCAL_FILL_FROM_MACHINES  Fill H/D/Xdp from case_data.machines.units if absent.
%   The generic engine builds every SG device from the resource table, whose SG
%   dynamic_params carries NO machine data (uniform with the EMF6 factory, which
%   reads case_data.machines).  So H/D/Xdp are read from the case's own machine
%   units, matched by bus, when the caller did not pass them directly (tests do).
%   The machine units must already be on the SYSTEM base; the declared
%   machines.base.S_MVA is checked so a machine-base table cannot be misread.
need = {'H','D','Xdp'};
missing = false;
for k = 1:numel(need)
    if ~isfield(params,need{k}) || isempty(params.(need{k})), missing = true; end
end
if ~missing
    return;
end
if ~isfield(case_data,'machines') || ~isstruct(case_data.machines) || ...
        ~isfield(case_data.machines,'units') || isempty(case_data.machines.units)
    return;   % leave absent: the per-field validation below fails loudly
end
if isfield(case_data.machines,'base') && isstruct(case_data.machines.base) && ...
        isfield(case_data.machines.base,'S_MVA') && ...
        isfinite(case_data.machines.base.S_MVA) && case_data.machines.base.S_MVA ~= 100
    error('stability:sg_classical_device:badMachineBase', ...
        ['case_data.machines.units must be on the 100 MVA system base; declared ' ...
         'S_MVA = %.6g.'], case_data.machines.base.S_MVA);
end
u = case_data.machines.units;
buses = arrayfun(@(s) s.bus, u);
j = find(buses == bus_id, 1);
if isempty(j)
    return;   % no machine at this bus: validation below fails loudly
end
if ~isfield(params,'H') || isempty(params.H), params.H = u(j).H; end
if ~isfield(params,'D') || isempty(params.D), params.D = u(j).D; end
if ~isfield(params,'Xdp') || isempty(params.Xdp), params.Xdp = u(j).Xdp; end
end
