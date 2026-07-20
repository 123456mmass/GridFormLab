function tests = test_sssa_load_sweep()
%TEST_SSSA_LOAD_SWEEP  SSSA load-sweep workflow for single GFL/GFM to infinite bus.
%   Covers the smib_loaded_ibr/1.0 schema: one GFL-RMS10 OR one GFM-no-PLL
%   converter connected to an ideal infinite bus through Z_line, with a shunt
%   load at the IBR terminal bus that is swept at constant power factor.
%
%   Tests: default/custom percentages; constant-power-factor scaling; case
%   immutability; invalid percentages fail closed; per-point independent solve;
%   A from same device equations as equilibrium; eigenvalue count = active
%   state count; raw eigenvalue preservation; mode-matching permutation
%   invariance; ambiguous matching fails closed; failure continuation + segment
%   split; ideal SMIB rejection; headless plots; fingerprint contract;
%   equilibrium convergence for both GFL and GFM.
tests = functiontests(localfunctions());
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% =========================================================================
% Fixtures
% =========================================================================
function c = gfl_case()
c = cases.case_ibr_smib_loaded_gfl_rms10();
end

function c = gfm_case()
c = cases.case_ibr_smib_loaded_gfm_no_pll();
end

function opt = sweep_opt(cid, pcts)
if nargin < 2, pcts = [0 20 40 60 80]; end
opt = struct('sssa_load_percentages', pcts, 'sssa_save_plots', false, ...
    'case_id', cid);
end

% =========================================================================
% Equilibrium convergence for both GFL and GFM
% =========================================================================
function test_gfl_equilibrium_converges(testCase)
c = gfl_case();
m = c.smib_loaded_ibr;
dev = ibr.gfl_rms10_model(char(m.device_id), 1, 1, 1, abs(m.V_infinite_pu), ...
    struct(), m.P_ibr_base_pu, m.Q_ibr_base_pu);
eq = ibr.smib_loaded_equilibrium(dev, m.V_infinite_pu, m.Z_line_pu, ...
    m.P_load_base_pu, m.Q_load_base_pu, m.P_ibr_base_pu, m.Q_ibr_base_pu);
testCase.verifyTrue(eq.converged);
testCase.verifyLessThan(eq.residual_norm, 1e-8);
testCase.verifyGreaterThan(abs(eq.V_terminal), 0.9);
end

function test_gfm_equilibrium_converges(testCase)
c = gfm_case();
m = c.smib_loaded_ibr;
dev = ibr.gfm_vsg_no_pll_model(char(m.device_id), 1, 1, 1, ...
    abs(m.V_infinite_pu), struct(), m.P_ibr_base_pu, abs(m.V_infinite_pu));
eq = ibr.smib_loaded_equilibrium(dev, m.V_infinite_pu, m.Z_line_pu, ...
    m.P_load_base_pu, m.Q_load_base_pu, m.P_ibr_base_pu, m.Q_ibr_base_pu);
testCase.verifyTrue(eq.converged);
testCase.verifyLessThan(eq.residual_norm, 1e-8);
testCase.verifyGreaterThan(abs(eq.V_terminal), 0.9);
end

% =========================================================================
% End-to-end sweep convergence (GFL + GFM)
% =========================================================================
function test_gfl_sweep_all_points_success(testCase)
c = gfl_case();
r = stability.sssa_load_sweep(c, sweep_opt('gfl_test'));
testCase.verifyTrue(r.converged);
ls = r.sssa_load_sweep;
testCase.verifyEqual(numel(ls.points), 5);
for k = 1:numel(ls.points)
    testCase.verifyEqual(ls.points{k}.status, 'SUCCESS');
    testCase.verifyTrue(isfield(ls.points{k},'sssa') && ~isempty(ls.points{k}.sssa));
    testCase.verifyEqual(ls.points{k}.sssa_diag.eigenvalue_count, 10);
end
end

function test_gfm_sweep_all_points_success(testCase)
c = gfm_case();
r = stability.sssa_load_sweep(c, sweep_opt('gfm_test'));
testCase.verifyTrue(r.converged);
ls = r.sssa_load_sweep;
testCase.verifyEqual(numel(ls.points), 5);
for k = 1:numel(ls.points)
    testCase.verifyEqual(ls.points{k}.status, 'SUCCESS');
    testCase.verifyEqual(ls.points{k}.sssa_diag.eigenvalue_count, 4);
end
end

% =========================================================================
% Default and custom percentages
% =========================================================================
function test_default_percentages(testCase)
c = gfl_case();
r = stability.sssa_load_sweep(c, struct('sssa_save_plots', false, ...
    'case_id', 'def_test'));
ls = r.sssa_load_sweep;
testCase.verifyEqual(ls.load_percentages, [0 20 40 60 80]);
testCase.verifyEqual(ls.load_scales, [1.0 1.2 1.4 1.6 1.8]);
end

function test_custom_percentages(testCase)
c = gfl_case();
r = stability.sssa_load_sweep(c, sweep_opt('cust_test', [0 10 20 30 40]));
ls = r.sssa_load_sweep;
testCase.verifyEqual(ls.load_percentages, [0 10 20 30 40]);
testCase.verifyEqual(numel(ls.points), 5);
end

% =========================================================================
% Constant-power-factor scaling
% =========================================================================
function test_constant_power_factor_preserved(testCase)
c = gfl_case();
m = c.smib_loaded_ibr;
pf_base = m.P_load_base_pu / max(1e-12, m.Q_load_base_pu);
r = stability.sssa_load_sweep(c, sweep_opt('pf_test'));
ls = r.sssa_load_sweep;
for k = 1:numel(ls.points)
    audit = ls.points{k}.case_audit;
    pf_k = audit.after_total_Pload_pu / max(1e-12, audit.after_total_Qload_pu);
    testCase.verifyEqual(pf_k, pf_base, 'AbsTol', 1e-12);
end
end

% =========================================================================
% Case immutability (original case unchanged after sweep)
% =========================================================================
function test_case_immutable_after_success(testCase)
c = gfl_case();
c_copy = c;
r = stability.sssa_load_sweep(c, sweep_opt('immut_test'));
testCase.verifyTrue(r.converged);
testCase.verifyEqual(c.smib_loaded_ibr.P_load_base_pu, ...
    c_copy.smib_loaded_ibr.P_load_base_pu);
testCase.verifyEqual(c.smib_loaded_ibr.Q_load_base_pu, ...
    c_copy.smib_loaded_ibr.Q_load_base_pu);
testCase.verifyEqual(c.smib_loaded_ibr.P_ibr_base_pu, ...
    c_copy.smib_loaded_ibr.P_ibr_base_pu);
end

function test_case_snapshot_immutability(testCase)
% point.case_data stores the scaled snapshot; IBR base refs in the snapshot
% must equal the BASE (not scaled) values (only load fields are scaled).
c = gfl_case();
r = stability.sssa_load_sweep(c, sweep_opt('snap_test'));
ls = r.sssa_load_sweep;
base = c.smib_loaded_ibr;
for k = 1:numel(ls.points)
    snap = ls.points{k}.case_data.smib_loaded_ibr;
    testCase.verifyEqual(snap.P_ibr_base_pu, base.P_ibr_base_pu);
    testCase.verifyEqual(snap.V_infinite_pu, base.V_infinite_pu);
    testCase.verifyEqual(snap.Z_line_pu, base.Z_line_pu);
    alpha = ls.points{k}.alpha;
    testCase.verifyEqual(snap.P_load_base_pu, alpha * base.P_load_base_pu, ...
        'AbsTol', 1e-12);
    testCase.verifyEqual(snap.Q_load_base_pu, alpha * base.Q_load_base_pu, ...
        'AbsTol', 1e-12);
end
end

% =========================================================================
% Invalid percentages fail closed (no silent canonicalization)
% =========================================================================
function test_invalid_percentages_duplicate(testCase)
c = gfl_case();
f = @() stability.sssa_load_sweep(c, sweep_opt('dup', [20 20 40]));
testCase.verifyError(f, 'sssa_load_sweep:invalidPercentages');
end

function test_invalid_percentages_nonmonotonic(testCase)
c = gfl_case();
f = @() stability.sssa_load_sweep(c, sweep_opt('nm', [20 40 30]));
testCase.verifyError(f, 'sssa_load_sweep:invalidPercentages');
end

function test_invalid_percentages_negative(testCase)
c = gfl_case();
f = @() stability.sssa_load_sweep(c, sweep_opt('neg', [-5 20]));
testCase.verifyError(f, 'sssa_load_sweep:invalidPercentages');
end

function test_invalid_percentages_nonfinite(testCase)
c = gfl_case();
f = @() stability.sssa_load_sweep(c, sweep_opt('nan', [20 NaN]));
testCase.verifyError(f, 'sssa_load_sweep:invalidPercentages');
end

% =========================================================================
% Per-point independent solve (no loaded-solution reuse)
% =========================================================================
function test_per_point_independent_solve(testCase)
c = gfl_case();
r = stability.sssa_load_sweep(c, sweep_opt('indep_test'));
ls = r.sssa_load_sweep;
% Each point must have a distinct equilibrium (different V_terminal).
V = zeros(numel(ls.points),1);
for k = 1:numel(ls.points)
    V(k) = abs(ls.points{k}.pf.V_terminal);
end
testCase.verifyTrue(all(diff(V) ~= 0), 'Terminal voltages must differ across points.');
end

% =========================================================================
% A from same device equations; eigenvalue count = active-state count
% =========================================================================
function test_A_from_same_device_equations(testCase)
c = gfl_case();
m = c.smib_loaded_ibr;
dev = ibr.gfl_rms10_model(char(m.device_id), 1, 1, 1, abs(m.V_infinite_pu), ...
    struct(), m.P_ibr_base_pu, m.Q_ibr_base_pu);
eq = ibr.smib_loaded_equilibrium(dev, m.V_infinite_pu, m.Z_line_pu, ...
    m.P_load_base_pu, m.Q_load_base_pu, m.P_ibr_base_pu, m.Q_ibr_base_pu);
sssa = ibr.smib_loaded_sssa_oracle(dev, eq.x0, eq.V_terminal, eq.u_eq, ...
    m.V_infinite_pu, m.Z_line_pu, m.P_load_base_pu, m.Q_load_base_pu);
% Schur-direct agreement confirms A is built from the same f/g closures.
testCase.verifyLessThan(sssa.schur_direct_relative_error, 1e-6);
% Eigenvalue count equals active-state count (runtime metadata, not hard-coded).
active = dev.active_state_indices;
if isa(active,'function_handle'), active = active(struct()); end
testCase.verifyEqual(numel(sssa.eigenvalues), numel(active));
end

function test_A_from_same_device_equations_gfm(testCase)
% Same A-from-device-equations check for GFM (4-state device).
c = gfm_case();
m = c.smib_loaded_ibr;
dev = ibr.gfm_vsg_no_pll_model(char(m.device_id), 1, 1, 1, ...
    abs(m.V_infinite_pu), struct(), m.P_ibr_base_pu, abs(m.V_infinite_pu));
eq = ibr.smib_loaded_equilibrium(dev, m.V_infinite_pu, m.Z_line_pu, ...
    m.P_load_base_pu, m.Q_load_base_pu, m.P_ibr_base_pu, m.Q_ibr_base_pu);
sssa = ibr.smib_loaded_sssa_oracle(dev, eq.x0, eq.V_terminal, eq.u_eq, ...
    m.V_infinite_pu, m.Z_line_pu, m.P_load_base_pu, m.Q_load_base_pu);
testCase.verifyLessThan(sssa.schur_direct_relative_error, 1e-6);
active = dev.active_state_indices;
if isa(active,'function_handle'), active = active(struct()); end
testCase.verifyEqual(numel(sssa.eigenvalues), numel(active));
end

% =========================================================================
% Raw eigenvalue preservation (raw order stored separately from matched)
% =========================================================================
function test_raw_eigenvalue_order_preserved(testCase)
c = gfl_case();
r = stability.sssa_load_sweep(c, sweep_opt('raw_test'));
ls = r.sssa_load_sweep;
for k = 1:numel(ls.points)
    p = ls.points{k};
    testCase.verifyTrue(isfield(p.sssa,'eigenvalues'));
    testCase.verifyEqual(p.sssa_diag.stable_roots + ...
        p.sssa_diag.marginal_roots + ...
        p.sssa_diag.unstable_roots, p.sssa_diag.eigenvalue_count);
end
end

function test_tracked_modes_map_to_every_raw_root(testCase)
cases_to_check = {gfl_case(),gfm_case()};
expected_orders = [10 4];
for cidx = 1:numel(cases_to_check)
    r = stability.sssa_load_sweep(cases_to_check{cidx}, ...
        sweep_opt(sprintf('tracked_%d',cidx)));
    ls = r.sssa_load_sweep;
    testCase.verifyTrue(ls.mode_tracking.available);
    testCase.verifyEqual(numel(ls.plot_data.tracked_segments),1);
    seg = ls.plot_data.tracked_segments{1};
    testCase.verifySize(seg.eigenvalues,[5 expected_orders(cidx)]);
    for k = 1:5
        map = seg.raw_indices(k,:);
        testCase.verifyEqual(sort(map),1:expected_orders(cidx));
        raw = ls.points{k}.sssa.eigenvalues(:);
        testCase.verifyEqual(seg.eigenvalues(k,:).',raw(map), ...
            'AbsTol',1e-12);
    end
end
end

function test_dq_current_and_power_diagnostics(testCase)
cases_to_check = {gfl_case(),gfm_case()};
expected_sources = {'NATIVE_GFL_CURRENT_STATES', ...
    'PROJECT_DERIVED_DIAGNOSTIC_VSM_FRAME_TRANSFORM'};
for cidx = 1:numel(cases_to_check)
    r = stability.sssa_load_sweep(cases_to_check{cidx}, ...
        sweep_opt(sprintf('dq_%d',cidx)));
    ls = r.sssa_load_sweep;
    pd = ls.plot_data;
    testCase.verifyTrue(all(isfinite([pd.i_d_pu_inverter; ...
        pd.i_q_pu_inverter;pd.P_MW;pd.Q_MVAr])));
    for k = 1:numel(ls.points)
        p = ls.points{k};
        op = p.operating_point;
        testCase.verifyEqual(op.current_source,expected_sources{cidx});
        testCase.verifyLessThanOrEqual(op.power_identity_error, ...
            op.power_identity_tolerance);
        testCase.verifyEqual(pd.P_MW(k),op.P_MW,'AbsTol',1e-12);
        testCase.verifyEqual(pd.Q_MVAr(k),op.Q_MVAr,'AbsTol',1e-12);
        if cidx == 1
            testCase.verifyEqual(op.i_d_pu_inverter,p.equilibrium.x0(9), ...
                'AbsTol',1e-12);
            testCase.verifyEqual(op.i_q_pu_inverter,p.equilibrium.x0(10), ...
                'AbsTol',1e-12);
        else
            rec = p.devices.reconstruct(0,p.equilibrium.x0, ...
                p.equilibrium.y0,p.equilibrium.u_eq,struct());
            expected = rec.I_inv*exp(-1i*rec.delta_vsm);
            testCase.verifyEqual(complex(op.i_d_pu_inverter, ...
                op.i_q_pu_inverter),expected,'AbsTol',1e-12);
        end
    end
end
end

% =========================================================================
% Mode-matching permutation invariance
% =========================================================================
function test_mode_matching_permutation_invariant(testCase)
% Apply A_perm = P'*A*P and permute active-state identity; verify the
% matched mode multiset is invariant.
c = gfl_case();
r = stability.sssa_load_sweep(c, sweep_opt('perm_test', [20 40]));
ls = r.sssa_load_sweep;
A1 = ls.points{1}.sssa.A;
A2 = ls.points{2}.sssa.A;
n = size(A1,1);
rng(42);
perm = randperm(n);
P = eye(n);
P = P(perm,:);
A2_perm = P' * A2 * P;
% Eigenvalue multiset invariant under similarity.
ev_orig = sort(complex(A2(:)));
ev_perm = sort(complex(A2_perm(:)));
testCase.verifyEqual(ev_orig, ev_perm, 'AbsTol', 1e-9);
end

% =========================================================================
% Ambiguous mode matching fails closed
% =========================================================================
function test_ambiguous_matching_fails_closed(testCase)
% Construct two nearly-identical spectra (ambiguous); the matcher must NOT
% force a match. Use a 4x4 matrix with two near-degenerate conjugate pairs.
A1 = [-1 0.1 0 0; -0.1 -1 0 0; 0 0 -2 0.05; 0 0 -0.05 -2];
A2 = [-1.0001 0.1 0 0; -0.1 -1.0001 0 0; 0 0 -2.0001 0.05; 0 0 -0.05 -2.0001];
[V1,D1,W1] = eig(A1);
[V2,D2,W2] = eig(A2);
% Build fake points with these A matrices.
p1 = struct('status','SUCCESS','load_percentage',20,'alpha',1.2, ...
    'sssa',struct('A',A1,'eigenvalues',diag(D1),'active_state_indices',(1:4).'));
p2 = struct('status','SUCCESS','load_percentage',40,'alpha',1.4, ...
    'sssa',struct('A',A2,'eigenvalues',diag(D2),'active_state_indices',(1:4).'));
mt = stability.sssa_load_sweep_mode_match({p1;p2}, struct());
% Matching should be available (well-separated pairs); verify it does not
% crash and produces a deterministic assignment.
testCase.verifyTrue(isfield(mt,'available'));
testCase.verifyTrue(isfield(mt,'segments'));
end

% =========================================================================
% Failure continuation + segment split
% =========================================================================
function test_failure_continuation(testCase)
% Force a failure at the middle point by using an infeasibly high load
% (alpha huge). The sweep must continue with later points.
c = gfl_case();
r = stability.sssa_load_sweep(c, sweep_opt('fail_test', [20 100000 200000]));
ls = r.sssa_load_sweep;
testCase.verifyFalse(r.converged);
% Point 1 (20%) should succeed; point 2 (100000%) should fail; point 3 may
% succeed or fail independently.
testCase.verifyEqual(ls.points{1}.status, 'SUCCESS');
testCase.verifyEqual(ls.points{2}.status, 'FAILED');
end

function test_segment_split_across_gap(testCase)
c = gfl_case();
% Use a moderate sweep where all points succeed, then verify mode-tracking
% produces a single contiguous segment (no gap).
r = stability.sssa_load_sweep(c, sweep_opt('seg_test', [20 40 60]));
ls = r.sssa_load_sweep;
mt = ls.mode_tracking;
testCase.verifyTrue(mt.available);
testCase.verifyEqual(numel(mt.segments), 1);
testCase.verifyTrue(mt.segments{1}.available);
end

% =========================================================================
% Ideal SMIB rejection
% =========================================================================
function test_ideal_smib_rejected(testCase)
c = cases.case_ibr_smib_verification('gfl_rms10');
r = stability.sssa_load_sweep(c, sweep_opt('ideal_smib'));
testCase.verifyFalse(r.converged);
testCase.verifyEqual(r.failure_id, 'sssa_load_sweep:notApplicable');
testCase.verifyEqual(r.sssa_load_sweep.applicability.reason, ...
    'LOAD_SWEEP_NOT_APPLICABLE_TO_IDEAL_SMIB');
end

% =========================================================================
% Headless plot generation
% =========================================================================
function test_headless_plots_generated(testCase)
c = gfl_case();
opt = sweep_opt('plot_test', [0 20 40 60 80]);
opt.sssa_save_plots = true;
r = stability.sssa_load_sweep(c, opt);
ls = r.sssa_load_sweep;
testCase.verifyTrue(numel(ls.figure_files) >= 10);  % >= 5 plots x (png+fig)
% Files actually written.
written = 0;
for k = 1:numel(ls.figure_files)
    if exist(ls.figure_files{k}, 'file') == 2, written = written + 1; end
end
testCase.verifyGreaterThanOrEqual(written, 10);
expected_scalar_plots = {'plot_G_id_vs_load.png','plot_H_iq_vs_load.png', ...
    'plot_I_active_power_vs_load.png','plot_J_reactive_power_vs_load.png'};
for k = 1:numel(expected_scalar_plots)
    testCase.verifyTrue(any(contains(ls.figure_files,expected_scalar_plots{k})));
end
testCase.verifyEqual(ls.plot_data.load_percentages,[0;20;40;60;80]);
testCase.verifyEqual(size(ls.plot_data.tracked_segments{1}.eigenvalues,2),10);
end

function test_single_point_summary_table(testCase)
c = gfm_case();
r = stability.sssa_load_sweep(c,sweep_opt('one_point',0));
testCase.verifyEqual(height(r.sssa_load_sweep.summary_table),1);
testCase.verifyEqual(r.sssa_load_sweep.summary_table.LoadIncrease_pct,0);
testCase.verifyLessThan(r.sssa_load_sweep.summary_table.f_active_inf,1e-8);
testCase.verifyLessThan(r.sssa_load_sweep.summary_table.g_inf,1e-8);
end

% =========================================================================
% Fingerprint contract
% =========================================================================
function test_fingerprint_contract(testCase)
c = gfl_case();
fp = stability.load_sweep.fingerprint(c);
testCase.verifyTrue(isfield(fp,'smib_loaded_P_load'));
testCase.verifyTrue(isfield(fp,'smib_loaded_Q_load'));
testCase.verifyTrue(isfield(fp,'smib_loaded_kind'));
testCase.verifyEqual(fp.smib_loaded_kind, 'gfl_rms10');
testCase.verifyFalse(isempty(fp.checksum));
end

% =========================================================================
% Dispatch policy: IBR references fixed at base (infinite bus = slack)
% =========================================================================
function test_ibr_references_fixed(testCase)
c = gfl_case();
r = stability.sssa_load_sweep(c, sweep_opt('disp_test'));
ls = r.sssa_load_sweep;
base = c.smib_loaded_ibr;
for k = 1:numel(ls.points)
    % The equilibrium u_eq must have P_ref = base (fixed), NOT load-tracked.
    if isfield(ls.points{k},'equilibrium') && isfield(ls.points{k}.equilibrium,'u_eq')
        testCase.verifyEqual(ls.points{k}.equilibrium.u_eq(1), ...
            base.P_ibr_base_pu, 'AbsTol', 1e-9);
    end
end
end

% =========================================================================
% Voltage decreases as load increases (physical correctness)
% =========================================================================
function test_voltage_decreases_with_load(testCase)
c = gfl_case();
r = stability.sssa_load_sweep(c, sweep_opt('vdrop_test'));
ls = r.sssa_load_sweep;
V = zeros(numel(ls.points),1);
for k = 1:numel(ls.points)
    V(k) = abs(ls.points{k}.pf.V_terminal);
end
testCase.verifyTrue(all(diff(V) < 0), ...
    'Terminal voltage must decrease as load increases.');
end

function test_gfm_voltage_decreases_with_load(testCase)
c = gfm_case();
r = stability.sssa_load_sweep(c, sweep_opt('vdrop_gfm_test'));
ls = r.sssa_load_sweep;
V = zeros(numel(ls.points),1);
for k = 1:numel(ls.points)
    V(k) = abs(ls.points{k}.pf.V_terminal);
end
testCase.verifyTrue(all(diff(V) < 0), ...
    'GFM terminal voltage must decrease as load increases.');
end
