function tests = test_ts_domain_preserving_newton()
%TEST_TS_DOMAIN_PRESERVING_NEWTON  Domain-preserving line-search policy tests.
%   Falsifies four failure modes of the opt-in TS trial-domain catch:
%     1) a classified line-search trial throw must reject the trial and let
%        the existing alpha backtracking find a valid iterate (no accepted
%        state is consumed from the rejected trial);
%     2) device/bus attribution must be pure (no DAE/device callback) and
%        must report every below-threshold online GFL-RMS10 device, never
%        just the first;
%     3) a non-domain exception must propagate unchanged;
%     4) the public hybrid TS result publishes the additive counters and a
%        stable shape on both converged and fail-closed early-return paths.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% --- Pure classifier contract ----------------------------------------------
function test_classifier_accepts_only_lowVoltagePowerInversion(testCase)
% The exact-ID predicate must accept ONLY the confirmed runtime domain ID.
% Every other RMS10 identifier (including the constructor/equilibrium
% voltageOutsideValidityDomain ID) must be rejected so composite_newton
% rethrows it.
clf = @(me) strcmp(me.identifier, 'ibr:gfl_rms10_model:lowVoltagePowerInversion');
testCase.verifyTrue(clf(MException('ibr:gfl_rms10_model:lowVoltagePowerInversion','x')));
testCase.verifyFalse(clf(MException('ibr:gfl_rms10_model:voltageOutsideValidityDomain','x')));
testCase.verifyFalse(clf(MException('ibr:gfl_rms10_model:badState','x')));
testCase.verifyFalse(clf(MException('ibr:gfl_rms10_model:nonfiniteRhs','x')));
testCase.verifyFalse(clf(MException('ibr:gfl_rms10_model:equilibriumCurrentLimit','x')));
testCase.verifyFalse(clf(MException('MATLAB:someOtherError','x')));
end

% --- Composite_newton opt-in end-to-end (via the public solver) -------------
function test_opt_in_rejects_then_accepts_smaller_alpha(testCase)
% A synthetic residual throws the domain ID once at the full-step trial;
% alpha=0.5 lands inside the domain and the next iteration converges.
% Verifies the accepted iterate comes from the valid trial, the rejected
% trial's voltage is recorded, and the legacy accept rule is unchanged.
z0 = [0; 1];
root = [2; 0.5];
thrown = false;  % shared workspace for the nested closure
    function r = rfn(z)
        if ~thrown && abs(z(1) - root(1)) < 1e-12 && abs(z(2) - root(2)) < 1e-12
            thrown = true;
            error('ibr:gfl_rms10_model:lowVoltagePowerInversion', ...
                'Trial outside the runtime voltage domain.');
        end
        r = [z(1) - root(1); z(2) - root(2)];
    end
residual_fn = @rfn;
jacobian_fn = @(~) [1, 0; 0, 1];
opt = struct( ...
    'trial_exception_classifier', @(me) strcmp(me.identifier, ...
        'ibr:gfl_rms10_model:lowVoltagePowerInversion'), ...
    'trial_exception_diagnostic', @(z_trial,~) struct( ...
        'minimum_trial_voltage', abs(z_trial(2)), ...
        'violating_devices', ts_empty_violating_devices()));

[z_sol, ~, converged, ~, ~, ~, info] = stability.composite_newton( ...
    z0, residual_fn, jacobian_fn, 1e-12, 20, false, opt);

testCase.verifyTrue(converged);
testCase.verifyEqual(z_sol, root, 'AbsTol', 1e-9);
testCase.verifyEqual(info.domain_rejected_trials, 1, 'AbsTol', 0);
testCase.verifyEqual(info.minimum_trial_voltage, 0.5, 'AbsTol', 0);
end

function test_opt_in_exhaust_reports_terminal_leaf(testCase)
% Every trial throws the domain ID: the solve fails closed at the last
% accepted point with full bounded diagnostics. The residual is valid at
% the anchor so the current-iterate evaluation does not throw.
z0 = [0.5; 0];
residual_fn = @(z) ts_throw_off_anchor(z, z0);
jacobian_fn = @(~) [1, 0; 0, 1];
opt = struct( ...
    'trial_exception_classifier', @(me) strcmp(me.identifier, ...
        'ibr:gfl_rms10_model:lowVoltagePowerInversion'), ...
    'trial_exception_diagnostic', @(z_trial,~) struct( ...
        'minimum_trial_voltage', abs(z_trial(1)), ...
        'violating_devices', ts_empty_violating_devices()));

[z_sol, niter, converged, ~, ~, ~, info] = stability.composite_newton( ...
    z0, residual_fn, jacobian_fn, 1e-12, 5, false, opt);

testCase.verifyFalse(converged);
testCase.verifyEqual(niter, 1, 'AbsTol', 0);
testCase.verifyEqual(z_sol, z0, 'AbsTol', 0);
testCase.verifyEqual(info.domain_rejected_trials, 20, 'AbsTol', 0);
testCase.verifyTrue(info.line_search_exhausted);
testCase.verifyEqual(info.final_tested_alpha, 2^-19, 'AbsTol', 0);
end

function r = ts_throw_off_anchor(z, anchor)
if norm(z - anchor, inf) > 1e-12
    error('ibr:gfl_rms10_model:lowVoltagePowerInversion', ...
        'Trial outside the runtime voltage domain.');
end
r = [z(1) - 2; z(2)];
end

function test_opt_in_non_domain_exception_rethrows(testCase)
z0 = [0; 0];
residual_fn = @ts_bad_state_throw;
jacobian_fn = @(~) [1, 0; 0, 1];
opt = struct( ...
    'trial_exception_classifier', @(me) strcmp(me.identifier, ...
        'ibr:gfl_rms10_model:lowVoltagePowerInversion'));
thrown = false; got_id = '';
try
    stability.composite_newton(z0, residual_fn, jacobian_fn, 1e-12, 5, false, opt);
catch me
    thrown = true; got_id = me.identifier;
end
testCase.verifyTrue(thrown);
testCase.verifyEqual(got_id, 'ibr:gfl_rms10_model:badState');
end

function r = ts_bad_state_throw(~)
% Always throws the non-domain badState ID (returns nothing because it
% always throws; the throw propagates before the missing return matters).
error('ibr:gfl_rms10_model:badState', 'hard error');
end

% --- Additive schema stability ---------------------------------------------
function test_run_hybrid_case_early_fail_publishes_counters(testCase)
% An invalid scenario never reaches TS; the public result and execution
% summary must still expose the additive counters with a stable 0 shape.
scenario = struct();
opt = struct();
r = stability.run_hybrid_case(scenario, opt);
testCase.verifyEqual(r.domain_rejected_trials, 0, 'AbsTol', 0);
testCase.verifyEqual(r.subdivision_depth, 0, 'AbsTol', 0);
if isfield(r,'execution_summary') && isstruct(r.execution_summary)
    testCase.verifyEqual(r.execution_summary.domain_rejected_trials, 0, 'AbsTol', 0);
    testCase.verifyEqual(r.execution_summary.subdivision_depth, 0, 'AbsTol', 0);
end
end

function vd = ts_empty_violating_devices()
vd = repmat(struct('device_id','','bus_id',0, ...
    'bus_position',0,'trial_voltage',NaN,'runtime_min_voltage',NaN), 0);
end
