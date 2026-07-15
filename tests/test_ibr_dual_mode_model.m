function tests = test_ibr_dual_mode_model()
%TEST_IBR_DUAL_MODE_MODEL  Source-model dual-mode fixed-layout device tests.
%   The former 15-state/shared-PLL ABI contradicted the WECC REGC_A/REEC_A
%   model, which has no PLL state.  The independent source-model oracle is
%   therefore GFM(13) + GFL(7) = 20 separate branch states.
tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

% =========================================================================
% Shared fixture: 2-bus infinite-bus + dual-mode device at bus 2.
% =========================================================================
function [mpc, dev, y0, u0, V0] = local_dual_fixture(mode, P_ref, Q_ref, V_ref)
if nargin < 2 || isempty(P_ref), P_ref = 0.4; end
if nargin < 3 || isempty(Q_ref), Q_ref = 0.0; end
if nargin < 4 || isempty(V_ref), V_ref = 1.0; end
if nargin < 1 || isempty(mode), mode = 'GFM'; end
mpc = struct();
mpc.baseMVA = 100;
mpc.bus = [ ...
    1, 3, 0, 0, 0, 0, 1, 1.06, 0, 69, 1, 1.1, 0.9; ...
    2, 1, 0, 0, 0, 0, 1, 1.00, 0, 69, 1, 1.1, 0.9];
mpc.gen = [1, 0, 0, 0, -0, 1.06, 100, 1, 0, -0];
mpc.branch = [1, 2, 0.0, 0.1, 0.0, 0, 0, 0, 1.0, 0, 1];
mpc.gencost = [];
mpc.case_name = 'dual_mode_2bus';
V0 = 1.0 + 0i;
bus_ids = [1; 2];
dev = ibr.dual_mode_ibr_model('IBR_test', 2, 2, bus_ids, V0, struct(), P_ref, Q_ref, V_ref, string(mode));
u0 = dev.u0;
y0 = [1.06; 0.0; real(V0); imag(V0)];
end

% =========================================================================
% 1. State dimension constant across modes
% =========================================================================
function test_dimension_constant(testCase)
for mode = ["gfl","GFM","tripped"]
    [~, dev, ~, ~, ~] = local_dual_fixture(mode);
    testCase.verifyEqual(dev.nx, 20, 'AbsTol', 0, [char(mode) ': nx==20.']);
    testCase.verifyEqual(dev.nu, 3, 'AbsTol', 0, [char(mode) ': nu==3.']);
    testCase.verifyEqual(numel(dev.state_names), 20, 'AbsTol', 0, [char(mode) ': 20 names.']);
end
end

% =========================================================================
% 2. GFL mode current matches standalone gfl_model
% =========================================================================
function test_gfl_mode_matches_standalone(testCase)
bus_ids = [1; 2]; V0 = 1.0+0i; P_ref = 0.4; Q_ref = 0.1; V_ref = 1.0;
gfl_only = ibr.gfl_model('T', 2, 2, bus_ids, V0, struct(), P_ref, Q_ref);
dual = ibr.dual_mode_ibr_model('T', 2, 2, bus_ids, V0, struct(), P_ref, Q_ref, V_ref, "gfl");
y = [1.06; 0; 1.0; 0];
% Map dual superset state -> GFL sub-state.
gfl_idx = 14:20;
x_gfl_from_dual = dual.x0(gfl_idx);
u_gfl = [P_ref; Q_ref];
I_dual = dual.current_injection(0, dual.x0, y, dual.u0, struct());
I_gfl = gfl_only.current_injection(0, x_gfl_from_dual, y, u_gfl, struct());
testCase.verifyEqual(I_dual, I_gfl, 'AbsTol', 1e-12, 'gfl mode current == standalone gfl.');
% f match.
f_dual = dual.f(0, dual.x0, y, dual.u0, struct());
f_gfl = gfl_only.f(0, x_gfl_from_dual, y, u_gfl, struct());
testCase.verifyEqual(f_dual(gfl_idx), f_gfl, 'AbsTol', 1e-12, 'gfl mode f(active) == standalone.');
% GFM-unique rows frozen (dx=0).
gfm_unique = 1:13;
testCase.verifyTrue(all(f_dual(gfm_unique) == 0), 'gfl mode: GFM-unique states frozen.');
xp = dual.x0;
xp(gfm_unique) = xp(gfm_unique) + (1:numel(gfm_unique))';
fp = dual.f(0, xp, y, dual.u0, struct());
testCase.verifyEqual(fp(gfm_unique),zeros(numel(gfm_unique),1),'AbsTol',0, ...
    'Inactive GFM states are exact holds away from the warm-start anchor.');
end

% =========================================================================
% 3. GFM mode current matches standalone regfm_b1_vsg_model
% =========================================================================
function test_gfm_mode_matches_standalone(testCase)
bus_ids = [1; 2]; V0 = 1.0+0i; P_ref = 0.4; Q_ref = 0.0; V_ref = 1.0;
gfm_only = ibr.regfm_b1_vsg_model('T', 2, 2, bus_ids, V0, struct(), P_ref, V_ref);
dual = ibr.dual_mode_ibr_model('T', 2, 2, bus_ids, V0, struct(), P_ref, Q_ref, V_ref, "GFM");
y = [1.06; 0; 1.0; 0];
gfm_idx = 1:13;
x_gfm_from_dual = dual.x0(gfm_idx);
u_gfm = [P_ref; V_ref];
I_dual = dual.current_injection(0, dual.x0, y, dual.u0, struct());
I_gfm = gfm_only.current_injection(0, x_gfm_from_dual, y, u_gfm, struct());
testCase.verifyEqual(I_dual, I_gfm, 'AbsTol', 1e-12, 'GFM mode current == standalone gfm.');
f_dual = dual.f(0, dual.x0, y, dual.u0, struct());
f_gfm = gfm_only.f(0, x_gfm_from_dual, y, u_gfm, struct());
testCase.verifyEqual(f_dual(gfm_idx), f_gfm, 'AbsTol', 1e-12, 'GFM mode f(active) == standalone.');
% GFL-unique rows frozen (dx=0).
gfl_unique = 14:20;
testCase.verifyTrue(all(f_dual(gfl_unique) == 0), 'GFM mode: GFL-unique states frozen.');
xp = dual.x0;
xp(gfl_unique) = xp(gfl_unique) + (1:numel(gfl_unique))';
fp = dual.f(0, xp, y, dual.u0, struct());
testCase.verifyEqual(fp(gfl_unique),zeros(numel(gfl_unique),1),'AbsTol',0, ...
    'Inactive GFL states are exact holds away from the warm-start anchor.');
end

% =========================================================================
% 4. Tripped mode: zero injection, all states frozen
% =========================================================================
function test_tripped_zero_injection(testCase)
[~, dev, y0, u0, ~] = local_dual_fixture('tripped');
I = dev.current_injection(0, dev.x0, y0, u0, struct());
testCase.verifyEqual(I, 0, 'AbsTol', 0, 'tripped: zero current injection.');
Pe = dev.electrical_power(0, dev.x0, y0, u0, struct());
testCase.verifyEqual(Pe, 0, 'AbsTol', 0, 'tripped: zero power.');
f = dev.f(0, dev.x0, y0, u0, struct());
testCase.verifyTrue(all(f == 0), 'tripped: all states frozen (dx=0).');
xp = dev.x0 + (1:dev.nx)';
fp = dev.f(0, xp, y0, u0, struct());
testCase.verifyEqual(fp,zeros(dev.nx,1),'AbsTol',0, ...
    'Tripped states are exact holds away from the warm-start anchor.');
end

% =========================================================================
% 5. Source branches are separate; no artificial shared PLL coordinates.
% =========================================================================
function test_source_branch_partition(testCase)
bus_ids = [1; 2]; V0 = 1.0+0i; P_ref = 0.4; Q_ref = 0.0; V_ref = 1.0;
dev_gfl = ibr.dual_mode_ibr_model('T', 2, 2, bus_ids, V0, struct(), P_ref, Q_ref, V_ref, "gfl");
dev_gfm = ibr.dual_mode_ibr_model('T', 2, 2, bus_ids, V0, struct(), P_ref, Q_ref, V_ref, "GFM");
testCase.verifyEqual(dev_gfl.active_state_indices,14:20,'AbsTol',0);
testCase.verifyEqual(dev_gfm.active_state_indices,1:13,'AbsTol',0);
testCase.verifyTrue(all(startsWith(string(dev_gfm.state_names(1:13)),'gfm_')));
testCase.verifyTrue(all(startsWith(string(dev_gfm.state_names(14:20)),'gfl_')));
testCase.verifyEmpty(dev_gfm.provenance.shared_states);
testCase.verifyTrue(all(isfinite(dev_gfm.x0)) && all(isfinite(dev_gfl.x0)));
end

function test_gfm_active_bound_specs_remapped(testCase)
[~,dev,y,u] = local_dual_fixture('GFM');
specs = dev.equilibrium_constraint_specs(dev.x0,y,u,struct());
testCase.verifyEqual(numel(specs),4,'AbsTol',0);
testCase.verifyEqual([specs.local_idx],[12 13 2 4],'AbsTol',0);
testCase.verifyTrue(all([specs.local_idx] >= 1 & [specs.local_idx] <= 13));
end

% =========================================================================
% 6. Fail-closed: bad mode
% =========================================================================
function test_fail_closed_modes(testCase)
bus_ids = [1; 2]; V0 = 1.0+0i;
try
    ibr.dual_mode_ibr_model('T', 2, 2, bus_ids, V0, struct(), 0.4, 0.0, 1.0, "invalid");
    testCase.verifyFail('invalid mode must error.');
catch e
    testCase.verifyTrue(contains(e.identifier, 'dual_mode_ibr_model') || ...
        contains(e.identifier, 'validators'), ['invalid mode errors: ' e.identifier]);
end
end

% =========================================================================
% 7. Fail-closed: bad V0
% =========================================================================
function test_fail_closed_v0(testCase)
bus_ids = [1; 2];
try
    ibr.dual_mode_ibr_model('T', 2, 2, bus_ids, 0, struct(), 0.4, 0.0, 1.0, "GFM");
    testCase.verifyFail('zero V0 must error.');
catch e
    testCase.verifyEqual(e.identifier, 'ibr:dual_mode_ibr_model:badV0', 'badV0 id.');
end
end

% =========================================================================
% 8. No external solver (grep guard)
% =========================================================================
function test_no_external_solver(testCase)
src_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+ibr', 'dual_mode_ibr_model.m');
src = fileread(src_path);
for fn = {'fsolve','optimoptions','fmincon','fminsearch','lsqnonlin','optimset'}
    testCase.verifyFalse(contains(src, fn{1}), ['no ' fn{1} ' in dual_mode_ibr_model.']);
end
end

% =========================================================================
% 9. Reuse single source of truth (grep guard: calls standalone models)
% =========================================================================
function test_reuses_standalone_models(testCase)
src_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+ibr', 'dual_mode_ibr_model.m');
src = fileread(src_path);
testCase.verifyTrue(contains(src, 'ibr.gfl_model('), 'constructs internal gfl_model.');
testCase.verifyTrue(contains(src, 'ibr.regfm_b1_vsg_model('), 'constructs internal gfm model.');
testCase.verifyTrue(contains(src, 'gfl_dev.f('), 'dispatches to gfl_dev.f.');
testCase.verifyTrue(contains(src, 'gfm_dev.f('), 'dispatches to gfm_dev.f.');
end
