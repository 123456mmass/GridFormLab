function tests = test_composite_vcon()
%TEST_COMPOSITE_VCON  B4 composite explicit vcon input contract tests.
%   Verifies composite_dae accepts an optional vcon struct (vars/rows/eq),
%   requires equal cardinality (index values may differ), replaces each
%   declared KCL row exactly once with the vcon_eq component, exposes
%   serializable ownership metadata (no handle), and fails closed on
%   malformed input.
%
%   Source: project B4 design (docs/project/plans/ibr_interface_foundation.md).
%   Uses SYNTHETIC fixtures over IEEE14 MATPOWER; no +ibr. Device params
%   are ASSUMED_DIAGNOSTIC (excluded from production acceptance).

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_no_vcon_unchanged(testCase)
% When vcon absent, composite_g is pure KCL at every bus (unchanged).
[dae, ~] = fixtures.synthetic_vcon_composite('one_constraint');
% Rebuild without vcon to compare.
c = cases.case_matpower6_case14();
gbus = c.mpc.gen(1,1);
dev = trivial_dev(gbus);
dae_novcon = stability.composite_dae(c, dev, struct());
% g at y0 should be identical (no replacement).
g_vcon = dae.dae_g(0, dae.x0, dae.y0, dae.Ynet, dae.u0, []);
g_novcon = dae_novcon.dae_g(0, dae_novcon.x0, dae_novcon.y0, dae_novcon.Ynet, dae_novcon.u0, []);
% With vcon, rows [1,2] are replaced (different); rows 3:end should match.
testCase.verifyEqual(g_vcon(3:end), g_novcon(3:end), 'AbsTol', 0, ...
    'non-vcon rows unchanged.');
testCase.verifyEmpty(dae_novcon.vcon.vars, 'no-vcon dae.vcon.vars empty.');
end

function test_disjoint_vars_rows_pass(testCase)
% vars=[1,2], rows=[3,4] (equal cardinality, different indices) => PASS.
[dae, vcon_opt] = fixtures.synthetic_vcon_composite('disjoint');
testCase.verifyEqual(numel(dae.vcon.vars), 2, 'two vars.');
testCase.verifyEqual(numel(dae.vcon.rows), 2, 'two rows.');
testCase.verifyEqual(dae.vcon.vars, [1,2], 'vars=[1,2].');
testCase.verifyEqual(dae.vcon.rows, [3,4], 'rows=[3,4].');
testCase.verifyEqual(dae.vcon.kind, 'fixed_y_only', 'kind label.');
end

function test_cardinality_bad_fail_closed(testCase)
% vars=[1,2], rows=[3] (unequal cardinality) => fail closed.
testCase.verifyError(@() fixtures.synthetic_vcon_composite('cardinality_bad'), ...
    'composite_dae:vconCardinality');
end

function test_duplicate_row_fail_closed(testCase)
% rows=[1,1] (duplicate) => fail closed.
testCase.verifyError(@() fixtures.synthetic_vcon_composite('duplicate_row'), ...
    'composite_dae:badVconIndex');
end

function test_bad_index_fail_closed(testCase)
% vars out of range => fail closed.
testCase.verifyError(@() fixtures.synthetic_vcon_composite('bad_index'), ...
    'composite_dae:badVconIndex');
end

function test_bad_eq_dim_fail_closed(testCase)
% eq returns scalar but rows has 2 => fail at g evaluation.
[dae, ~] = fixtures.synthetic_vcon_composite('bad_eq_dim');
testCase.verifyError(@() dae.dae_g(0, dae.x0, dae.y0, dae.Ynet, dae.u0, []), ...
    'composite_dae:vconEqDim');
end

function test_replace_rows_exactly_once(testCase)
% Each declared KCL row is replaced exactly once with the vcon_eq value.
[dae, vcon_opt] = fixtures.synthetic_vcon_composite('one_constraint');
g = dae.dae_g(0, dae.x0, dae.y0, dae.Ynet, dae.u0, []);
% The replaced rows [1,2] should equal vcon_eq(x0,y0).
gcon = vcon_opt.eq(dae.y0, vcon_opt.ref);
testCase.verifyEqual(g(1), gcon(1), 'AbsTol', 0, 'row 1 replaced with vcon.');
testCase.verifyEqual(g(2), gcon(2), 'AbsTol', 0, 'row 2 replaced with vcon.');
% Row 3 should be KCL (not vcon) — compare against a KCL-only build.
c = cases.case_matpower6_case14();
gbus = c.mpc.gen(1,1);
dev = trivial_dev(gbus);
dae_novcon = stability.composite_dae(c, dev, struct());
g_novcon = dae_novcon.dae_g(0, dae_novcon.x0, dae_novcon.y0, dae_novcon.Ynet, dae_novcon.u0, []);
% Rows 3:end identical (KCL unchanged); rows 1:2 differ (replaced).
testCase.verifyEqual(g(3:end), g_novcon(3:end), 'AbsTol', 0, ...
    'non-vcon rows are KCL (unchanged).');
testCase.verifyNotEqual(abs(g(1)-g_novcon(1)), 0, 'row 1 differs from KCL.');
end

function test_runtime_vcon_eq_abi(testCase)
% The runtime dae.vcon_eq handle has the (x,y) ABI (B4/B6 contract).
[dae, vcon_opt] = fixtures.synthetic_vcon_composite('one_constraint');
% vcon_eq(x, y) must work (drops x, binds ref).
gcon = dae.vcon_eq(dae.x0, dae.y0);
testCase.verifyEqual(numel(gcon), 2, 'vcon_eq returns 2 components.');
testCase.verifyEqual(gcon, vcon_opt.eq(dae.y0, vcon_opt.ref), 'AbsTol', 0, ...
    'runtime adapter matches user-facing eq(y,ref).');
end

function test_vcon_metadata_no_handle(testCase)
% dae.vcon metadata has NO function handle (serializable).
[dae, ~] = fixtures.synthetic_vcon_composite('one_constraint');
testCase.verifyTrue(isfield(dae.vcon,'vars'), 'vcon.vars present.');
testCase.verifyTrue(isfield(dae.vcon,'rows'), 'vcon.rows present.');
testCase.verifyTrue(isfield(dae.vcon,'kind'), 'vcon.kind present.');
% dae.vcon itself must not contain a function_handle field.
fns = fieldnames(dae.vcon);
for k = 1:numel(fns)
    testCase.verifyFalse(isa(dae.vcon.(fns{k}),'function_handle'), ...
        sprintf('dae.vcon.%s must not be a handle.', fns{k}));
end
end

function test_two_constraints(testCase)
% Two constrained buses: vars/rows length 4.
[dae, ~] = fixtures.synthetic_vcon_composite('two_constraints');
testCase.verifyEqual(numel(dae.vcon.vars), 4, 'four vars.');
testCase.verifyEqual(numel(dae.vcon.rows), 4, 'four rows.');
end

function dev = trivial_dev(bus_id)
dev = struct( ...
    'name','trivial', 'device_id','g1', 'bus_id',bus_id, ...
    'nx',1, 'nu',1, ...
    'f',@(t,x,y,u,ec) -x, ...
    'current_injection',@(t,x,y,u,ec) complex(0,0), ...
    'electrical_power',@(t,x,y,u,ec) 0, ...
    'x0',0, 'u0',0, ...
    'state_names',{{'delta'}}, ...
    'reconstruct',@(t,x,y,u,ec) struct('delta',x,'omega',0,'Pe',0,'Vbus',abs(y(1))));
end
