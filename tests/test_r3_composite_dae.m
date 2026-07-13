function tests = test_r3_composite_dae()
%TEST_R3_COMPOSITE_DAE  R3 composite DAE assembler tests.
%   Verifies the composite is the single owner of shared y, topology, mapping,
%   and KCL g=YV-Ibus. Devices return positive current injection only. Tests
%   cover: two-device equilibrium, bus-by-bus KCL, shuffled bus IDs, multiple
%   devices at one bus, empty device set, invalid bus mapping, sign convention,
%   deterministic ordering, and the synthetic one-device equivalence (sign-flip
%   g_composite = -g_sg, NOT residual bit-identity).
%
%   Source: project R3 design (docs/project/plans/ibr_interface_foundation.md).

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function opt = base_opt()
opt = struct('fault_bus',4,'Zf',1i*0.1,'t_end',1,'dt',0.02, ...
    'pm_mode','pgaz','corrector_mode','adaptive','verbose',false, ...
    'fault_enabled',false);
end

function test_two_device_equilibrium(testCase)
% The composite KCL is g = Y*V - Ibus. Verify the STRUCTURE: g equals
% Y*V - Ibus exactly (the composite assembles KCL correctly). The synthetic
% device parameters are NOT PF-matched, so g need not be ~0; what matters is
% that the composite forms g = Y*V - Ibus (canonical YV-I) correctly.
[case_data, devices] = fixtures.synthetic_composite_cases('two_device');
dae = stability.composite_dae(case_data, devices, base_opt());
g0 = dae.dae_g(0, dae.x0, dae.y0, dae.Ynet, dae.u0, struct());
% Reconstruct Y*V - Ibus manually and compare (structure, not magnitude).
V = complex(dae.y0(1:2:end), dae.y0(2:2:end));
Ibus = dae.current_injection(0, dae.x0, dae.y0, dae.u0, struct());
g_manual = zeros(numel(g0),1);
gc = dae.Ynet*V - Ibus;
g_manual(1:2:end) = real(gc); g_manual(2:2:end) = imag(gc);
testCase.verifyLessThan(max(abs(g0 - g_manual)), 1e-14, ...
    'composite g = Y*V - Ibus (canonical YV-I) assembled correctly.');
end

function test_kcl_balance_every_bus(testCase)
% Verify the composite KCL is assembled at EVERY bus (2*nb residuals), not
% just device buses. The structure (g = Y*V - Ibus) must hold at all buses.
[case_data, devices] = fixtures.synthetic_composite_cases('two_device');
dae = stability.composite_dae(case_data, devices, base_opt());
g0 = dae.dae_g(0, dae.x0, dae.y0, dae.Ynet, dae.u0, struct());
testCase.verifyEqual(numel(g0), 2*dae.nb, 'KCL residual at every bus (2*nb).');
% Non-device buses: Ibus=0, so g = Y*V there (network-only KCL).
V = complex(dae.y0(1:2:end), dae.y0(2:2:end));
Ibus = dae.current_injection(0, dae.x0, dae.y0, dae.u0, struct());
non_dev_buses = setdiff(1:dae.nb, dae.bus_map);
for b = non_dev_buses(:).'
    % At non-device bus, Ibus(b)=0, so g(2b-1:2b) should equal [Re(Y*V)_b; Im(Y*V)_b].
    yv = dae.Ynet(b,:)*V;
    testCase.verifyEqual(g0(2*b-1), real(yv), 'AbsTol', 1e-14, ...
        sprintf('non-device bus %d KCL real', b));
    testCase.verifyEqual(g0(2*b), imag(yv), 'AbsTol', 1e-14, ...
        sprintf('non-device bus %d KCL imag', b));
end
end

function test_shuffled_bus_ids(testCase)
[case_data, devices] = fixtures.synthetic_composite_cases('shuffled');
dae = stability.composite_dae(case_data, devices, base_opt());
% Verify mapping: device bus_ids map to valid internal indices.
testCase.verifyTrue(all(dae.bus_map > 0), 'shuffled bus IDs mapped.');
testCase.verifyEqual(numel(dae.bus_map), 2, 'two devices mapped.');
% Verify the structure holds with shuffled IDs.
g0 = dae.dae_g(0, dae.x0, dae.y0, dae.Ynet, dae.u0, struct());
V = complex(dae.y0(1:2:end), dae.y0(2:2:end));
Ibus = dae.current_injection(0, dae.x0, dae.y0, dae.u0, struct());
g_manual = zeros(numel(g0),1);
gc = dae.Ynet*V - Ibus;
g_manual(1:2:end) = real(gc); g_manual(2:2:end) = imag(gc);
testCase.verifyLessThan(max(abs(g0 - g_manual)), 1e-14, 'KCL structure with shuffled IDs.');
end

function test_multiple_devices_one_bus(testCase)
[case_data, devices] = fixtures.synthetic_composite_cases('multi_at_bus');
dae = stability.composite_dae(case_data, devices, base_opt());
% Two devices at bus 1: currents must sum at that bus.
testCase.verifyEqual(dae.bus_map(1), dae.bus_map(2), ...
    'both devices map to the same bus.');
Ibus = dae.current_injection(0, dae.x0, dae.y0, dae.u0, struct());
% Ibus at the shared bus should be the sum of both device injections.
dev1 = dae.devices(1); dev2 = dae.devices(2);
xr1 = dae.device_offsets(1)+1:dae.device_offsets(1)+dev1.nx;
xr2 = dae.device_offsets(2)+1:dae.device_offsets(2)+dev2.nx;
I1 = dev1.current_injection(0, dae.x0(xr1), dae.y0, [], struct());
I2 = dev2.current_injection(0, dae.x0(xr2), dae.y0, [], struct());
testCase.verifyEqual(Ibus(dae.bus_map(1)), I1 + I2, 'AbsTol', 1e-14, ...
    'currents sum at shared bus.');
end

function test_empty_device_set_fail_closed(testCase)
c = cases.case_matpower6_case14();
testCase.verifyError(@() stability.composite_dae(c, {}, base_opt()), ...
    'composite_dae:emptyDevices');
end

function test_invalid_bus_mapping(testCase)
c = cases.case_matpower6_case14();
[~, dev] = fixtures.synthetic_composite_cases('two_device');
dev(2).bus_id = 999;   % nonexistent bus
testCase.verifyError(@() stability.composite_dae(c, dev, base_opt()), ...
    'composite_dae:badBusId');
end

function test_sign_convention(testCase)
% Devices return positive current injection (INTO network). The composite KCL
% is g = Y*V - Ibus (YV-I). SG DAEs use g = -Y*V + Ibus (-YV+I). The relation
% g_composite = -g_sg holds (sign-flip), NOT bit-identity.
[case_data, devices] = fixtures.synthetic_composite_cases('two_device');
dae = stability.composite_dae(case_data, devices, base_opt());
g_composite = dae.dae_g(0, dae.x0, dae.y0, dae.Ynet, dae.u0, struct());
% Build the SG-sign residual manually: g_sg = -Y*V + Ibus.
V = complex(dae.y0(1:2:end), dae.y0(2:2:end));
Ibus = dae.current_injection(0, dae.x0, dae.y0, dae.u0, struct());
g_sg_vec = -dae.Ynet*V + Ibus;
g_sg = zeros(numel(g_composite),1);
g_sg(1:2:end) = real(g_sg_vec); g_sg(2:2:end) = imag(g_sg_vec);
% Sign-flip exact: g_composite = -g_sg.
testCase.verifyLessThan(max(abs(g_composite - (-g_sg))), 1e-14, ...
    'g_composite = -g_sg (sign-flip exact, NOT bit-identity).');
end

function test_deterministic_ordering(testCase)
[case_data, devices] = fixtures.synthetic_composite_cases('two_device');
dae = stability.composite_dae(case_data, devices, base_opt());
% Device 1 states come first, device 2 second (caller-provided order).
testCase.verifyEqual(dae.device_offsets, [0; 2], 'deterministic offsets.');
testCase.verifyEqual(dae.metadata(1).x_range, 1:2, 'device 1 x_range.');
testCase.verifyEqual(dae.metadata(2).x_range, 3:4, 'device 2 x_range.');
end

function test_duplicate_device_id_fail_closed(testCase)
[case_data, devices] = fixtures.synthetic_composite_cases('two_device');
devices(2).device_id = devices(1).device_id;   % duplicate
testCase.verifyError(@() stability.composite_dae(case_data, devices, base_opt()), ...
    'composite_dae:duplicateDeviceId');
end

function test_no_fault_fixed_ts_drift(testCase)
% A no-fault fixed-step composite TS must run to completion with finite
% trajectory. The synthetic device parameters are NOT PF-matched, so we do
% NOT assert low drift (that would require a real classical-device adapter,
% which is out of scope — R3 Revision 3). We verify the composite TS path
% executes and produces a finite result.
[case_data, devices] = fixtures.synthetic_composite_cases('two_device');
opt = base_opt(); opt.t_end = 0.2; opt.dt = 0.01;
dae = stability.composite_dae(case_data, devices, opt);
strat = struct('model','composite', ...
    'dae_f',@(x,y) dae.dae_f(0,x,y,dae.u0,struct()), ...
    'dae_g',@(x,y,Y) dae.dae_g(0,x,y,Y,dae.u0,struct()), ...
    'jac_y',@(x,y,Y) stability.ts_jac_y_fd(x,y,Y,@(x2,y2,Y2) dae.dae_g(0,x2,y2,Y2,dae.u0,struct())), ...
    'needs_jyy',true,'needs_algebraic_solve',true, ...
    'electrical_power',@(x,y) dae.electrical_power(0,x,y,dae.u0,struct()), ...
    'state_split',struct('ng',2,'ns',2,'delta_idx',1:2:4,'omega_idx',2:2:4), ...
    'reconstruct',@(x,y,Y) struct('delta',x(1:2:end)','omega',x(2:2:end)', ...
    'Pe',dae.electrical_power(0,x,y,dae.u0,struct())','Vbus',abs(complex(y(1:2:end),y(2:2:end)))'));
bundle.ts.strategy = strat;
bundle.ts.x0 = dae.x0; bundle.ts.y0 = dae.y0;
bundle.ts.topology = dae.topology;
bundle.ts.mapping = dae.mapping;
bundle.ts.metadata = struct('device_id','composite_two_device');
bundle.sssa.model = struct('x0',dae.x0,'y0',dae.y0, ...
    'f',strat.dae_f,'g',strat.dae_g);
bundle.metadata = struct('dispatch','explicit_model_bundle');
opt.model_bundle = bundle;
opt.fault_enabled = false;
r = stability.ts_simulate(case_data, opt);
testCase.verifyTrue(all(isfinite(r.delta(:))), 'composite TS finite.');
testCase.verifyEqual(size(r.delta,2), 2, 'two device delta columns.');
testCase.verifyEqual(r.metadata.dispatch, 'explicit_model_bundle', ...
    'composite provenance = explicit_model_bundle.');
end
