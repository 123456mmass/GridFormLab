function [case_data, devices] = synthetic_composite_cases(variant)
%SYNTHETIC_COMPOSITE_CASES  Test-only composite fixtures (R3).
%   Returns a case_data + devices list for R3 composite tests. TEST-ONLY
%   (tests/+fixtures, called as fixtures.synthetic_composite_cases). No +ibr.
%
%   Variants:
%     'two_device'   - two synthetic 2-state generators at buses 1, 2.
%     'shuffled'     - non-contiguous bus IDs (buses 6, 8).
%     'multi_at_bus' - two devices at the same bus (bus 1).
%
%   Each device is a synthetic 2-state classical-style generator (delta,
%   omega) with positive current injection Ig = (E - V)/(j*Xdp). Devices are
%   initialized from the PF solution so the composite equilibrium is ~0.
%
%   Source: project classical_dae (synthetic, no +ibr).

if nargin < 1, variant = 'two_device'; end
case_data = cases.case_matpower6_case14();
% Run PF to initialize device x0 from the PF solution.
pf = pfsolver.powerflow_newton_raphson(case_data, struct('verbose',false, ...
    'plot_results',false,'max_iter',50,'tolerance',1e-10,'enforce_q_limits',false));
V0 = pf.bus_voltage(:).*exp(1i*deg2rad(pf.bus_angle_deg(:)));
switch lower(variant)
case 'two_device'
    devices = [mk_dev('G1','G1',1,V0,pf), mk_dev('G2','G2',2,V0,pf)];
case 'shuffled'
    devices = [mk_dev('G1','G1',6,V0,pf), mk_dev('G2','G2',8,V0,pf)];
case 'multi_at_bus'
    devices = [mk_dev('G1','G1',1,V0,pf), mk_dev('G2','G2',1,V0,pf)];
otherwise
    error('synthetic_composite_cases:badVariant', 'Unknown variant "%s".', variant);
end
end

function dev = mk_dev(name, did, bus_id, V0, pf)
% Build a synthetic 2-state generator device initialized from PF.
% State: x = [delta; omega]. Ig = (E - V)/(j*Xdp), E = Eqmag*exp(j*delta).
Eqmag = 1.05; Xdp = 0.3; H = 5; D = 0; ws = 2*pi*60;
% Find the bus in the PF external_bus_ids.
bidx = find(pf.external_bus_ids == bus_id, 1);
Vb = V0(bidx);
% Initialize delta so that E = Vb + j*Xdp*Ig matches PF. Use delta = angle(Vb).
delta0 = angle(Vb);
% Pm = Pe at equilibrium (Pe from PF generation if available, else Re(V*conj(Ig)).
gen_row = find(pf.external_bus_ids == bus_id, 1);
if gen_row <= numel(pf.P_generation) && pf.P_generation(gen_row) ~= 0
    Pm = real(pf.P_generation(gen_row));
else
    Pm = 0.5;
end
dev.name = name;
dev.device_id = did;
dev.bus_id = bus_id;
dev.nx = 2; dev.nu = 0;
dev.x0 = [delta0; 1.0];
dev.u0 = zeros(0,1);
dev.state_names = {'delta','omega'};
dev.device_type = 'synthetic_2state';
dev.f = @(t,x_dev,y,u_dev,event_context) swing_rhs(x_dev, y, bus_id, ...
    Eqmag, Xdp, H, D, Pm, ws);
dev.current_injection = @(t,x_dev,y,u_dev,event_context) ...
    gen_current(x_dev, y, bus_id, Eqmag, Xdp);
dev.electrical_power = @(t,x_dev,y,u_dev,event_context) ...
    gen_pe(x_dev, y, bus_id, Eqmag, Xdp);
dev.reconstruct = @(t,x_dev,y,u_dev,event_context) ...
    struct('delta',x_dev(1),'omega',x_dev(2),'Pe',gen_pe(x_dev,y,bus_id,Eqmag,Xdp), ...
           'Vbus',abs(get_V(y,bus_id)));
end

function dx = swing_rhs(x_dev, y, bus_id, Eqmag, Xdp, H, D, Pm, ws)
delta = x_dev(1); omega = x_dev(2);
V = get_V(y, bus_id);
Ig = (Eqmag*exp(1i*delta) - V)/(1i*Xdp);
Pe = real(V*conj(Ig));
dx = [ws*(omega-1); (Pm - Pe - D*(omega-1))/(2*H)];
end

function Ig = gen_current(x_dev, y, bus_id, Eqmag, Xdp)
delta = x_dev(1);
V = get_V(y, bus_id);
Ig = (Eqmag*exp(1i*delta) - V)/(1i*Xdp);
end

function Pe = gen_pe(x_dev, y, bus_id, Eqmag, Xdp)
delta = x_dev(1);
V = get_V(y, bus_id);
Ig = (Eqmag*exp(1i*delta) - V)/(1i*Xdp);
Pe = real(V*conj(Ig));
end

function V = get_V(y, bus_id)
% y is the shared interleaved vector indexed by internal bus position.
% case14 buses are 1..14, so internal index == external bus_id.
b = bus_id;
V = complex(y(2*b-1), y(2*b));
end
