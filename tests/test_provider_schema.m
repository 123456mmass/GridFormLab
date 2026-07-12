function tests = test_provider_schema()
%TEST_PROVIDER_SCHEMA  B7 typed provider schema tests.
%   Verifies construction-validated schema + per-eval validation + no-
%   mutation caller contract (documented, not enforced). Stable error IDs.
%
%   Source: project B7 design (docs/project/plans/ibr_interface_foundation.md).
%   Uses SYNTHETIC fixtures; no +ibr.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_constant_validates_u0_at_construction(testCase)
% constant provider with a valid u0 builds and evaluates identically.
p = stability.make_input_provider('constant', [1; 2]);
u = stability.eval_input_provider(p, 0, struct());
testCase.verifyEqual(u, [1; 2], 'AbsTol', 0, 'constant returns u0.');
end

function test_constant_nonfinite_u0_fail_construction(testCase)
% Non-finite constant u0 must fail at construction (B7).
testCase.verifyError(@() stability.make_input_provider('constant', [1; NaN]), ...
    'eval_input_provider:nonFinite');
end

function test_callback_changing_shape_fail_eval(testCase)
% Callback changing shape across evals must fail closed (B7 schemaShape).
schema = struct('class','numeric','shape',[2 1],'fields',{{}},'real_only',false);
fn = @(t,~) [t; t+1];   % always 2x1 — consistent
p = stability.make_input_provider('callback', fn, schema);
u0 = stability.eval_input_provider(p, 0, struct());
testCase.verifyEqual(u0, [0; 1], 'AbsTol', 0, 'callback eval consistent.');
% Now a callback that changes shape mid-stream.
fn_bad = @(t,~) [t; t+1; t+2];   % 3x1, not 2x1
p_bad = stability.make_input_provider('callback', fn_bad, schema);
testCase.verifyError(@() stability.eval_input_provider(p_bad, 0, struct()), ...
    'eval_input_provider:schemaShape');
end

function test_callback_changing_type_fail_eval(testCase)
% Callback returning non-numeric must fail closed (B7 schemaClass).
schema = struct('class','numeric','shape',[],'fields',{{}},'real_only',false);
fn = @(t,~) 'not numeric';
p = stability.make_input_provider('callback', fn, schema);
testCase.verifyError(@() stability.eval_input_provider(p, 0, struct()), ...
    'eval_input_provider:schemaClass');
end

function test_callback_nonfinite_fail_eval(testCase)
% Callback returning non-finite must fail closed (B7 nonFinite).
fn = @(t,~) [1; Inf];
p = stability.make_input_provider('callback', fn);
testCase.verifyError(@() stability.eval_input_provider(p, 0, struct()), ...
    'eval_input_provider:nonFinite');
end

function test_callback_real_only_fail_complex(testCase)
% real_only schema rejects complex values (B7 schemaComplex).
schema = struct('class','numeric','shape',[1 1],'fields',{{}},'real_only',true);
fn = @(t,~) complex(t, 1);
p = stability.make_input_provider('callback', fn, schema);
testCase.verifyError(@() stability.eval_input_provider(p, 1, struct()), ...
    'eval_input_provider:schemaComplex');
end

function test_callback_struct_fields_mismatch_fail(testCase)
% Struct provider: missing/extra field must fail closed (B7 schemaFields).
schema = struct('class','struct','shape','scalar', ...
    'fields',{{'a','b'}},'real_only',false);
fn = @(t,~) struct('a',1);   % missing 'b'
p = stability.make_input_provider('callback', fn, schema);
testCase.verifyError(@() stability.eval_input_provider(p, 0, struct()), ...
    'eval_input_provider:schemaFields');
end

function test_callback_struct_valid_passes(testCase)
% Struct provider with the declared field set passes.
schema = struct('class','struct','shape','scalar', ...
    'fields',{{'a','b'}},'real_only',false);
fn = @(t,~) struct('a',t,'b',2*t);
p = stability.make_input_provider('callback', fn, schema);
u = stability.eval_input_provider(p, 3, struct());
testCase.verifyEqual(u.a, 3, 'AbsTol', 0, 'field a correct.');
testCase.verifyEqual(u.b, 6, 'AbsTol', 0, 'field b correct.');
end

function test_malformed_schema_fail_construction(testCase)
% Schema missing a required field must fail at construction.
schema = struct('class','numeric');   % missing shape, fields, real_only
testCase.verifyError(@() stability.make_input_provider('callback', @(t,~)t, schema), ...
    'make_input_provider:badSchema');
end

function test_absent_provider_returns_empty(testCase)
% Absent provider ([] ) => legacy path, returns [].
u = stability.eval_input_provider([], 0, struct());
testCase.verifyEmpty(u, 'absent provider returns empty.');
end

function test_constant_schema_derived_from_u0(testCase)
% When schema omitted for constant, it is derived from u0 (numeric, shape).
p = stability.make_input_provider('constant', [1 2 3]);
testCase.verifyEqual(p.schema.class, 'numeric', 'derived class numeric.');
testCase.verifyEqual(p.schema.shape, [1 3], 'derived shape [1 3].');
testCase.verifyTrue(p.schema.real_only, 'real u0 => real_only.');
end
