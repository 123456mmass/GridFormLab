function tests = test_r2_model_dispatch()
%TEST_R2_MODEL_DISPATCH  R2 model-bundle dispatch, validation, mutual-exclusion.
%   Verifies the model_bundle > model_fn > built-in string dispatch precedence,
%   mutual-exclusion fail-closed, capability-specific validators, provenance
%   metadata, and absence of any +ibr call-graph reference. Uses a SYNTHETIC
%   plugin (fixtures.synthetic_linear_generator); no +ibr code is referenced.
%
%   Source: project R2 design (docs/project/plans/ibr_interface_foundation.md).

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function testCase = base_opt()
testCase = struct('t_end',1,'dt',0.02,'fault_bus',4,'t_fault',1.0, ...
    't_clear',1.1,'Zf',1i*0.1,'pm_mode','pgaz','corrector_mode','adaptive', ...
    'corrector_iter',10,'max_corrector_iter',10,'verbose',false, ...
    'fault_enabled',true);
end

function test_string_dispatch_unchanged(testCase)
% Built-in SG string dispatch must remain bit-identical (legacy path).
c = cases.case_matpower6_case14();
opt = base_opt();
r = stability.ts_simulate(c, opt);
testCase.verifyEqual(r.model, 'classical', 'string dispatch produces classical.');
testCase.verifyTrue(all(isfinite(r.delta(:))), 'finite trajectory.');
testCase.verifyEqual(r.metadata.dispatch, 'built_in_string', ...
    'provenance = built_in_string for string dispatch.');
end

function test_model_fn_dispatch(testCase)
% opt.model_fn takes precedence over the string default and produces a bundle run.
c = cases.case_matpower6_case14();
opt = base_opt();
opt.model_fn = @fixtures.synthetic_linear_generator;
r = stability.ts_simulate(c, opt);
testCase.verifyTrue(all(isfinite(r.delta(:))), 'model_fn run finite.');
testCase.verifyEqual(r.metadata.dispatch, 'explicit_model_fn', ...
    'provenance = explicit_model_fn.');
end

function test_model_bundle_dispatch(testCase)
% opt.model_bundle (pre-built) takes precedence and bypasses factory.
c = cases.case_matpower6_case14();
opt = base_opt();
bundle = fixtures.synthetic_linear_generator(c, opt);
opt.model_bundle = bundle;
r = stability.ts_simulate(c, opt);
testCase.verifyTrue(all(isfinite(r.delta(:))), 'model_bundle run finite.');
testCase.verifyEqual(r.metadata.dispatch, 'explicit_model_bundle', ...
    'provenance = explicit_model_bundle.');
end

function test_mutual_exclusion_fail_closed(testCase)
% Both model_bundle and model_fn supplied => fail closed.
c = cases.case_matpower6_case14();
opt = base_opt();
bundle = fixtures.synthetic_linear_generator(c, opt);
opt.model_bundle = bundle;
opt.model_fn = @fixtures.synthetic_linear_generator;
testCase.verifyError(@() stability.ts_simulate(c, opt), ...
    'ts_simulate:exclusiveDispatch');
end

function test_validate_ts_strategy_missing_field(testCase)
% Missing required field => error.
s = struct('model','x');
testCase.verifyError(@() stability.validate_ts_strategy(s), ...
    'validate_ts_strategy:missingField');
end

function test_validate_ts_strategy_linear_mismatch(testCase)
% Linear model with non-empty dae_g => error.
s = struct('model','x','dae_f',@(x,y) x,'dae_g',@(x,y,Y) y, ...
    'jac_y',[],'needs_jyy',false,'needs_algebraic_solve',false, ...
    'electrical_power',@(x,y) 0, ...
    'state_split',struct('ng',1,'delta_idx',1,'omega_idx',2), ...
    'reconstruct',@(x,y,Y) struct('delta',0,'omega',0,'Pe',0,'Vbus',0));
testCase.verifyError(@() stability.validate_ts_strategy(s), ...
    'validate_ts_strategy:linearMismatch');
end

function test_validate_ts_bundle_missing_ts(testCase)
testCase.verifyError(@() stability.validate_ts_bundle(struct()), ...
    'validate_ts_bundle:missingTs');
end

function test_validate_sssa_model_missing_field(testCase)
testCase.verifyError(@() stability.validate_sssa_model(struct()), ...
    'validate_sssa_model:missingField');
end

function test_validate_sssa_model_free_y_vcon_exclusive(testCase)
% free_y + vcon => fail closed (R4 mutual exclusivity, checked at SSSA too).
m = struct('x0',[0;0],'y0',[0;0],'f',@(x,y) x,'g',@(x,y) y, ...
    'free_y',1,'vcon_vars',2);
testCase.verifyError(@() stability.validate_sssa_model(m), ...
    'validate_sssa_model:exclusiveOwnership');
end

function test_no_ibr_reference(testCase)
% Grep guard: no +ibr CALL-GRAPH reference in any new +stability file or test
% fixture. We scan only non-comment, non-blank code lines for actual call-graph
% tokens (@ibr., ibr.vsg_model, import +ibr). Comments mentioning "+ibr" as a
% fence description are allowed.
projroot = fileparts(fileparts(mfilename('fullpath')));
dirs = {fullfile(projroot,'+stability'), fullfile(projroot,'tests','+fixtures')};
hits = {};
for d = dirs
    if ~exist(d{1},'dir'), continue; end
    f = dir(fullfile(d{1},'**','*.m'));
    for k = 1:numel(f)
        fp = fullfile(f(k).folder, f(k).name);
        lines = readlines(fp);
        for li = 1:numel(lines)
            ln = strtrim(lines{li});
            if isempty(ln) || ln(1) == '%', continue; end   % skip comments
            % Strip trailing comment.
            cidx = find(ln == '%', 1);
            if ~isempty(cidx), ln = strtrim(ln(1:cidx-1)); end
            if contains(ln,'@ibr.') || contains(ln,'ibr.vsg_model') || ...
               contains(ln,'import +ibr') || contains(ln,'addpath.*ibr')
                hits = [hits; {sprintf('%s:%d: %s', fp, li, ln)}]; %#ok<AGROW>
            end
        end
    end
end
testCase.verifyTrue(isempty(hits), ...
    sprintf('Forbidden +ibr call-graph reference found: %s', strjoin(hits, '; ')));
end
