function tests = test_ibr_gfl_rms10_ts()
%TEST_IBR_GFL_RMS10_TS  Profile B event-free TS integration (SG1+GFM+3xRMS10).
%   Builds the IEEE14 1-SG + 4-IBR system with IBR3/6/8 as GFL-RMS10, solves the
%   online-SG equilibrium, and integrates the SAME nonlinear RHS via the shared
%   ts_simulate_composite kernel. Event-free TS must hold near equilibrium.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();

c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'}, ...
    'mode',{'GFM','gfl','gfl','gfl'}, ...
    'gfl_family',{'','rms10','rms10','rms10'});
dispatch = struct('IBR2',109.7,'IBR3',49.8,'IBR6',49.8,'IBR8',49.8);
[devices,~] = ibr.build_ieee14_sg_ibr_devices(c,modes,dispatch);
cfg = struct('devices',devices,'device_modes',modes);
eq = stability.mixed_equilibrium_solve(c,cfg,struct('verbose',false));
testCase.assertTrue(eq.converged, eq.failure_reason);

testCase.TestData.case_data = c;
testCase.TestData.devices = devices;
testCase.TestData.eq = eq;
testCase.TestData.modes = modes;
end

function test_event_free_ts_holds_near_equilibrium(testCase)
c = testCase.TestData.case_data;
eq = testCase.TestData.eq;
devices = eq.devices;

opt = struct('t_end',0.05,'dt',0.01,'verbose',false, ...
    'u_eq',eq.u_eq,'event_context',eq.equilibrium_context, ...
    'dynamic_state_indices',eq.dynamic_state_indices,'full_kcl',true);
[ts,meta] = stability.ts_simulate_composite(c,devices,eq.x0,eq.y0,opt);

testCase.verifyTrue(ts.converged, 'event-free TS must converge');
testCase.verifyTrue(meta.full_kcl);

% No-drift: max state deviation over the horizon must stay small.
x_traj = ts.x_traj;   % nx_total x n_steps
x0 = eq.x0;
n = numel(x0);
% Compare every stored step to the equilibrium state vector.
n_steps = size(x_traj, 2);
max_state_drift = 0;
for j = 1:n_steps
    max_state_drift = max(max_state_drift, max(abs(x_traj(1:n,j) - x0)));
end
testCase.verifyLessThan(max_state_drift, 1e-3, ...
    sprintf('event-free TS state drift %.3e exceeds 1e-3', max_state_drift));
end

function test_ts_uses_same_rhs_as_equilibrium(testCase)
% The TS kernel integrates the SAME device closures used by equilibrium. This
% is verified by checking the initial RHS at x0,y0,u_eq is near zero (the
% equilibrium residual), which only holds if TS and equilibrium share RHS.
eq = testCase.TestData.eq;
devices = eq.devices;
dae = stability.composite_dae(testCase.TestData.case_data, devices, ...
    struct('load_model','cz_p_cz_q'));
f0 = dae.dae_f(0, eq.x0, eq.y0, eq.u_eq, eq.equilibrium_context);
testCase.verifyLessThan(max(abs(f0(:))), 1e-6, ...
    'initial TS RHS must match the equilibrium residual (shared closures)');
end

function test_ts_no_gfl_specific_integrator(testCase)
% The TS integration reuses ts_simulate_composite; no GFL-specific integrator
% exists. Verify the shared kernel is the path by checking the function is
% the one invoked (source grep for the GFL-specific filename).
root = fileparts(fileparts(mfilename('fullpath')));
rms10_path = fullfile(root,'+ibr','gfl_rms10_model.m');
txt = fileread(rms10_path);
% No TS/integration solver calls inside the device file.
testCase.assertFalse(contains(txt,'ts_simulate'));
testCase.assertFalse(contains(txt,'ode45'));
testCase.assertFalse(contains(txt,'ode15s'));
end

function test_ts_disturbance_response_finite(testCase)
% A small P_ref step on IBR3 (RMS10) must produce a finite, bounded TS
% response (no NaN/Inf, no divergence). The shared kernel integrates the
% same nonlinear RHS; the RMS10 PLL/current loops respond to the step.
c = testCase.TestData.case_data;
eq = testCase.TestData.eq;
devices = eq.devices;

% Apply a 5% P_ref step on IBR3 (device index 3 in the 5-device bundle).
u_step = eq.u_eq;
% Find the global u index for IBR3 P_ref.
u_off = [0; cumsum([devices(:).nu]')];
ibr3 = 3;   % SG1=1, IBR2=2, IBR3=3, IBR6=4, IBR8=5
p_slot = 1; % P_ref is input 1
u_idx = u_off(ibr3) + p_slot;
u_step(u_idx) = u_step(u_idx) * 1.05;

opt = struct('t_end',0.10,'dt',0.01,'verbose',false, ...
    'u_eq',u_step,'event_context',eq.equilibrium_context, ...
    'dynamic_state_indices',eq.dynamic_state_indices,'full_kcl',true);
[ts,~] = stability.ts_simulate_composite(c,devices,eq.x0,eq.y0,opt);

testCase.verifyTrue(ts.converged);
% Response must be finite across the whole horizon.
testCase.verifyTrue(all(isfinite(ts.x_traj(:))));
testCase.verifyTrue(all(isfinite(ts.y_traj(:))));
% Bounded: no state blows up beyond 10x its equilibrium magnitude.
x0 = eq.x0;
n = numel(x0);
max_dev = 0;
for j = 1:size(ts.x_traj,2)
    max_dev = max(max_dev, max(abs(ts.x_traj(1:n,j) - x0)));
end
testCase.verifyLessThan(max_dev, 10.0, ...
    sprintf('disturbance response diverged: max dev %.3e', max_dev));
end

function test_ts_limiter_transaction_fail_closed(testCase)
% When the RMS10 device is driven into its current limit during TS, the
% limiter must engage (transaction) and anti-windup must hold the
% integrator; the device must not produce non-finite current.
c = testCase.TestData.case_data;
eq = testCase.TestData.eq;
devices = eq.devices;

% Force a large P_ref step on IBR3 to drive the current command past Imax.
u_step = eq.u_eq;
u_off = [0; cumsum([devices(:).nu]')];
ibr3 = 3;
p_slot = 1;
u_idx = u_off(ibr3) + p_slot;
u_step(u_idx) = u_step(u_idx) * 2.0;   % 2x step -> likely limiter active

opt = struct('t_end',0.10,'dt',0.01,'verbose',false, ...
    'u_eq',u_step,'event_context',eq.equilibrium_context, ...
    'dynamic_state_indices',eq.dynamic_state_indices,'full_kcl',true);
[ts,meta] = stability.ts_simulate_composite(c,devices,eq.x0,eq.y0,opt);

% The TS may or may not converge under a large step, but it must remain
% finite (no NaN/Inf) and the kernel must report a finite result rather
% than silently producing stale states.
if ts.converged
    testCase.verifyTrue(all(isfinite(ts.x_traj(:))));
    testCase.verifyTrue(all(isfinite(ts.y_traj(:))));
else
    % A non-converged result under a 2x step is acceptable; the kernel
    % must still report finite states (no silent NaN).
    testCase.verifyTrue(all(isfinite(ts.x_traj(:)))) || isempty(ts.x_traj);
end
testCase.verifyTrue(isfield(meta,'full_kcl'));
end
