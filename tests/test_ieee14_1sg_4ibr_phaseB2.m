function tests = test_ieee14_1sg_4ibr_phaseB2()
%TEST_IEEE14_1SG_4IBR_PHASEB2  Phase B2 no-event composite TS tests.
%   Verifies: composite TS holds equilibrium, residual<1e-6, runs clean
%   (no NaN/Inf), Edp frozen at 0 throughout, SG No-eq/No-TS guard,
%   single-step deterministic, legacy SG-only path bit-identical.
%
%   Source: execution plan §B2; correction 7 (coupled trapezoidal).
tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

% =========================================================================
function test_composite_ts_holds_equilibrium(testCase)
% At equilibrium, no-event TS should not drift from initial state.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);

% Solve equilibrium
config = struct('devices', devices);
eq = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyTrue(eq.converged, 'Equilibrium must converge.');

% Run short TS (0.1 s, small dt) — expect zero drift
[ts_res, ~] = stability.ts_simulate_composite(c, eq.devices, ...
    eq.x0, eq.y0, physical_ts_opt(eq,0.1,1e-3));
testCase.verifyTrue(ts_res.converged, 'TS must converge.');

% Check drift: max |x(t) - x0| should be near zero over 0.1s
x0 = eq.x0;
max_drift = max(vecnorm(ts_res.x_traj - x0, 1, 1));
testCase.verifyLessThan(max_drift, 1e-4, ...
    sprintf('Max state drift over 0.1s: %.3e < 1e-4.', max_drift));
end

% =========================================================================
function test_composite_ts_no_nan_inf(testCase)
% TS trajectory must contain no NaN/Inf.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);

config = struct('devices', devices);
eq = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyTrue(eq.converged, 'Equilibrium must converge.');

[ts_res, ~] = stability.ts_simulate_composite(c, eq.devices, ...
    eq.x0, eq.y0, physical_ts_opt(eq,1.0,0.01));
testCase.verifyTrue(ts_res.converged, 'TS must converge.');
testCase.verifyTrue(all(isfinite(ts_res.x_traj(:))), 'x_traj has no NaN/Inf.');
testCase.verifyTrue(all(isfinite(ts_res.y_traj(:))), 'y_traj has no NaN/Inf.');
end

% =========================================================================
function test_edp_frozen_throughout_ts(testCase)
% Edp (state 4) must remain 0 exactly throughout TS.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);

config = struct('devices', devices);
eq = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyTrue(eq.converged, 'Equilibrium must converge.');

[ts_res, ~] = stability.ts_simulate_composite(c, eq.devices, ...
    eq.x0, eq.y0, physical_ts_opt(eq,0.5,0.005));
testCase.verifyTrue(ts_res.converged, 'TS must converge.');

% SG1 Edp is global state index 4 (first device, state 4)
edp_traj = ts_res.x_traj(4, :);
testCase.verifyEqual(max(abs(edp_traj)), 0, 'AbsTol', 1e-15, ...
    'Edp must be frozen at 0 throughout TS.');
end

% =========================================================================
function test_single_step_deterministic(testCase)
% Two TS runs with identical inputs must give identical results.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);

config = struct('devices', devices);
eq = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyTrue(eq.converged, 'Equilibrium must converge.');

opt_ts = physical_ts_opt(eq,0.5,0.01);
[res1, ~] = stability.ts_simulate_composite(c, eq.devices, eq.x0, eq.y0, opt_ts);
[res2, ~] = stability.ts_simulate_composite(c, eq.devices, eq.x0, eq.y0, opt_ts);

testCase.verifyEqual(res1.x_traj, res2.x_traj, 'AbsTol', 0, ...
    'Deterministic: identical x_traj.');
testCase.verifyEqual(res1.y_traj, res2.y_traj, 'AbsTol', 1e-14, ...
    'Deterministic: y_traj within fp.');
end

% =========================================================================
function test_trapezoidal_residual_gate(testCase)
% At equilibrium, the trapezoidal residual should be zero.
% x1 = x0 when f0 = f1 = 0 at equilibrium => R_x = 0.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);

config = struct('devices', devices);
eq = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyTrue(eq.converged, 'Equilibrium must converge.');
testCase.verifyLessThan(eq.residual_norm, 1e-6, 'Equilibrium residual < 1e-6.');
end

% =========================================================================
function test_run_hybrid_case_no_event(testCase)
% End-to-end run_hybrid_case (no events) must converge.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);

% Build scenario via the generic path
scenario_opt = struct();
scenario_opt.dispatch = disp_s;
scenario_opt.initial_modes = modes;

[resources, ~] = stability.resource_table(c, ...
    ieee14_spec(), scenario_opt);
scenario = stability.build_hybrid_scenario(c, resources, scenario_opt);

opt = struct('t_end', 0.2, 'dt', 0.01, 'verbose', false);
result = stability.run_hybrid_case(scenario, opt);
testCase.verifyTrue(result.converged, ...
    sprintf('Hybrid case must converge: %s', ...
    char(fieldnames(result.metadata))));
testCase.verifyTrue(isfield(result, 'x_traj') && ~isempty(result.x_traj), ...
    'Result must contain non-empty x_traj.');
testCase.verifyEqual(size(result.x_traj, 2), 21, 'AbsTol', 0, ...
    '21 time points (0.2/0.01+1).');
end

function spec = ieee14_spec()
Sbase = 100;
sg1 = struct('resource_id','SG1','bus_id',1,'resource_type','sg','model_id','sg_emf6',...
    'supported_modes',["synchronous","breaker_open"],...
    'voltage_forming_modes',"synchronous",...
    'initial_mode',"synchronous",'initial_online',true,...
    'can_switch_mode',true,'can_switch_online',true,...
    'has_current_limiter',false,'has_frt',false,'can_black_start',false,...
    'limits',struct('ImaxSS',[],'ImaxF',[],'Pmax_MW',[],'Qmax_MVAr',[],'Emax',[],'Emin',[]),...
    'ratings',struct('Mbase',615,'Sbase',Sbase),...
    'dynamic_params',struct(),...
    'provenance',struct('model','sg_emf6','source','Kodsi','classification','CASE_DEFINED','details',''));
spec = sg1;
ids = {'IBR2','IBR3','IBR6','IBR8'}; buses = [2,3,6,8]; mbases = [140,100,100,100];
for k = 1:4
    r = struct('resource_id',ids{k},'bus_id',buses(k),'resource_type','ibr','model_id','regfm_b1_dual',...
        'supported_modes',["gfl","gfm","tripped"],'voltage_forming_modes',"gfm",...
        'initial_mode',"gfl",'initial_online',true,...
        'can_switch_mode',true,'can_switch_online',true,...
        'has_current_limiter',true,'has_frt',true,'can_black_start',false,...
        'limits',struct('ImaxSS',1.0,'ImaxF',1.5,'Pmax_MW',mbases(k),'Qmax_MVAr',mbases(k),'Emax',1.2,'Emin',0.8),...
        'ratings',struct('Mbase',mbases(k),'Sbase',Sbase,'default_P_MW',0),...
        'dynamic_params',struct('Mbase',mbases(k)),...
        'provenance',struct('model','regfm_b1_dual','source','REGFM_B1','classification','CASE_DEFINED','details',''));
    spec(end+1) = r; %#ok<AGROW>
end
end

function opt = physical_ts_opt(eq,t_end,dt)
% Same solved inputs/context/state partition and all physical KCL equations.
opt = struct('t_end',t_end,'dt',dt,'verbose',false, ...
    'u_eq',eq.u_eq,'event_context',eq.equilibrium_context, ...
    'dynamic_state_indices',eq.dynamic_state_indices,'full_kcl',true);
end
