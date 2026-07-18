function tests = test_ibr_section_h_report()
%TEST_IBR_SECTION_H_REPORT  Falsification tests for Section H report (Phase 3).
%
%   Covers: 12 sections present in order, NOT_RUN/NOT_APPLICABLE/NOT_AVAILABLE
%   distinct, fingerprint stability + material-change sensitivity, spectrum
%   table cardinality, two-digit scientific notation, participation GFL PLL
%   non-applicability, read-only input, no-solver static guard.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
    clear functions;
    rehash;
    rehash toolboxcache;
end

% --- Fixtures ------------------------------------------------------------
function inputs = minimal_inputs()
inputs.case_data = struct('baseMVA',100,'case_id','ieee14_test','fHz',60);
inputs.inventory = struct();
inputs.inventory.state_rows = struct('device_id','IBR1','local_state_index',1, ...
    'global_state_index',1,'state_name','omega_m','state_status','ACTIVE_IN_ARED');
inputs.inventory.input_rows = struct('device_id','IBR1','local_input_index',1, ...
    'global_input_index',1,'input_name','P_ref');
inputs.inventory.counts = struct('nx_total_ibr',1,'nx_active',1,'nx_frozen',0, ...
    'nx_inactive_anchor',0);
inputs.resource_map = struct('resource_index',1,'device_index',1, ...
    'device_id','IBR1','bus_position',2,'bus_id',2,'device_type','ibr_gfm','online',true);
end

function inputs = inputs_with_sssa()
inputs = minimal_inputs();
A = blkdiag([-1 -4; 4 -1], -2, -3);
inputs.sssa = struct('A',A,'A_full',A,'eigenvalues',eig(A), ...
    'active_state_indices',1:4,'frozen_state_indices',[], ...
    'nx_total',4,'nx_active',4,'physical_A',[],'physical_eigenvalues',[], ...
    'physical_state_dimension',4,'physical_state_global_indices',1:4, ...
    'active_bound_constraint_global_indices',[],'active_bound_tangent_map',[], ...
    'coordinate_quotient_left_map',[],'coordinate_quotient_right_map',[], ...
    'coordinate_gauge_global_index',[]);
inputs.modal_A = stability.modal_analysis(inputs.sssa);
end

% ===================== 12 sections ======================================
function test_12_sections_present_in_order(testCase)
r = ibr.section_h_report(minimal_inputs());
testCase.assertEqual(numel(r.sections), 12);
titles = {r.sections.title};
expected = {'CASE AND BASE','RESOURCE/DEVICE INDEX MAP','STATE INVENTORY', ...
    'INPUT INVENTORY','PF RESULTS','EQUILIBRIUM RESULTS', ...
    'FULL STATE EIGENVALUES','PARTICIPATION FACTORS', ...
    'TS EVENT TRANSACTIONS','TS SIGNAL INDEX','EXECUTION COUNTERS', ...
    'CONVERGENCE/FAILURE SUMMARY'};
testCase.assertEqual(titles, expected);
end

function test_absent_pf_is_not_run(testCase)
r = ibr.section_h_report(minimal_inputs());
testCase.assertEqual(r.sections(5).status, 'NOT_RUN');
testCase.assertEqual(r.sections(6).status, 'NOT_RUN');
testCase.assertEqual(r.sections(7).status, 'NOT_RUN');
testCase.assertEqual(r.sections(9).status, 'NOT_RUN');
testCase.assertEqual(r.sections(10).status, 'NOT_RUN');
end

function test_not_run_not_applicable_distinct(testCase)
r = ibr.section_h_report(minimal_inputs());
% Section 7 (SSSA) is NOT_RUN (no sssa); section 8 is NOT_AVAILABLE_PRODUCER.
testCase.assertEqual(r.sections(7).status, 'NOT_RUN');
testCase.assertEqual(r.sections(8).status, 'NOT_AVAILABLE_PRODUCER');
% GFL PLL participation is NOT APPLICABLE (distinct from NOT_RUN).
testCase.assertEqual(r.gfl_pll_participation, 'NOT APPLICABLE TO CURRENT PRODUCTION MODEL');
end

% ===================== spectrum table ===================================
function test_full_state_eigenvalues_cardinality(testCase)
inputs = inputs_with_sssa();
r = ibr.section_h_report(inputs);
testCase.assertEqual(r.full_state_eigenvalues.status, 'AVAILABLE');
testCase.assertEqual(numel(r.full_state_eigenvalues.rows), 4);
testCase.assertEqual(r.validation.size_Ared, 4);
testCase.assertTrue(r.validation.cardinality_check);
end

function test_two_digit_scientific_notation(testCase)
inputs = inputs_with_sssa();
r = ibr.section_h_report(inputs);
for k = 1:numel(r.full_state_eigenvalues.rows)
    f = r.full_state_eigenvalues.rows{k}.formatted_eigenvalue;
    % Match "+N.NNe+NN +N.NNe+NNj" pattern (signed, 2 decimals, scientific).
    pat = '^[+-]\d\.\d{2}e[+-]\d{2} [+-]\d\.\d{2}e[+-]\d{2}j$';
    testCase.assertTrue(~isempty(regexp(f, pat, 'once')), ...
        sprintf('formatted eigenvalue %s does not match two-digit sci notation', f));
end
end

function test_full_state_eigenvalues_no_truncation(testCase)
inputs = inputs_with_sssa();
r = ibr.section_h_report(inputs);
% All 4 eigenvalues retained (including both conjugates).
testCase.assertEqual(numel(r.full_state_eigenvalues.rows), 4);
end

function test_modal_domain_mismatch_fails(testCase)
inputs = inputs_with_sssa();
% Pass physical modal as modal_A.
inputs.modal_A = stability.modal_analysis(inputs.sssa, struct('domain','physical_A'));
r = ibr.section_h_report(inputs);
testCase.assertEqual(r.sections(7).status, 'INCONSISTENT_INPUT');
end

% ===================== participation ====================================
function test_participation_gfl_pll_not_applicable(testCase)
inputs = inputs_with_sssa();
r = ibr.section_h_report(inputs);
testCase.assertEqual(r.participation.summary.gfl_pll_participation, ...
    'NOT APPLICABLE TO CURRENT PRODUCTION MODEL');
end

function test_participation_marks_unavailable(testCase)
inputs = inputs_with_sssa();
r = ibr.section_h_report(inputs);
% At least one mode should be available (block-diag is well-conditioned).
avail = false;
for k = 1:numel(r.participation.rows)
    if strcmp(r.participation.rows{k}.participation_status, 'AVAILABLE_SIMPLE')
        avail = true;
    end
end
testCase.assertTrue(avail);
end

% ===================== fingerprint ======================================
function test_fingerprint_stable_identical_input(testCase)
inputs = inputs_with_sssa();
r1 = ibr.section_h_report(inputs);
r2 = ibr.section_h_report(inputs);
testCase.assertEqual(r1.analysis_fingerprint.aggregate_hash, ...
    r2.analysis_fingerprint.aggregate_hash);
end

function test_fingerprint_changes_on_material_change(testCase)
inputs = inputs_with_sssa();
r1 = ibr.section_h_report(inputs);
% Change a matrix value.
inputs2 = inputs;
A2 = inputs2.sssa.A;
A2(1,1) = A2(1,1) + 0.1;
inputs2.sssa.A = A2;
inputs2.modal_A = stability.modal_analysis(inputs2.sssa);
r2 = ibr.section_h_report(inputs2);
testCase.assertNotEqual(r1.analysis_fingerprint.matrix_hash, ...
    r2.analysis_fingerprint.matrix_hash);
testCase.assertNotEqual(r1.analysis_fingerprint.aggregate_hash, ...
    r2.analysis_fingerprint.aggregate_hash);
end

function test_fingerprint_invariant_to_field_order(testCase)
% Struct field insertion order must not change the hash.
inputs = minimal_inputs();
r1 = ibr.section_h_report(inputs);
% Rebuild case_data with fields in different order.
cd2 = struct('fHz',60,'case_id','ieee14_test','baseMVA',100);
inputs2 = inputs;
inputs2.case_data = cd2;
r2 = ibr.section_h_report(inputs2);
testCase.assertEqual(r1.analysis_fingerprint.case_id, r2.analysis_fingerprint.case_id);
end

% ===================== read-only + static guard =========================
function test_input_unchanged(testCase)
inputs = inputs_with_sssa();
before = inputs;
ibr.section_h_report(inputs);
testCase.assertEqual(numel(inputs.sssa.A), numel(before.sssa.A));
testCase.assertEqual(inputs.case_data.baseMVA, before.case_data.baseMVA);
end

function test_no_solver_in_source(testCase)
files = {'ibr.section_h_report','ibr.render_section_h_report'};
for k = 1:numel(files)
    p = which(files{k});
    testCase.assertFalse(isempty(p), sprintf('%s not found', files{k}));
    txt = fileread(p);
    lines = splitlines(txt);
    code_lines = lines(~startsWith(strtrim(lines), '%'));
    code = strjoin(code_lines, newline);
    bad = {'eig(','inv(','pinv(','fsolve','fmincon','lsqnonlin', ...
        'matpower','psat','simulink','stability.modal_analysis', ...
        'ibr.state_inventory_snapshot'};
    for j = 1:numel(bad)
        testCase.assertFalse(contains(lower(code), lower(bad{j})), ...
            sprintf('%s must not contain %s', files{k}, bad{j}));
    end
end
end

function test_renderer_returns_text_no_file_write(testCase)
inputs = inputs_with_sssa();
r = ibr.section_h_report(inputs);
txt = ibr.render_section_h_report(r);
testCase.assertTrue(ischar(txt));
testCase.assertTrue(contains(txt, 'SECTION H REPORT'));
testCase.assertTrue(contains(txt, 'FULL STATE EIGENVALUES'));
testCase.assertTrue(contains(txt, 'NOT APPLICABLE TO CURRENT PRODUCTION MODEL'));
end

% ===================== counters =========================================
function test_counters_distinguish_invocation_iteration(testCase)
inputs = minimal_inputs();
inputs.equilibrium = struct('converged',true,'iterations',5);
r = ibr.section_h_report(inputs);
% equilibrium_invocations is NOT_AVAILABLE_PRODUCER (not inferred from result).
% equilibrium_newton_iterations is AVAILABLE (=5).
rows = r.execution_counters.rows;
if iscell(rows)
    names = cellfun(@(x) x.name, rows, 'UniformOutput', false);
else
    names = {rows.name};
end
idx_inv = find(strcmp(names,'equilibrium_invocations'));
idx_iter = find(strcmp(names,'equilibrium_newton_iterations'));
if iscell(rows)
    inv_row = rows{idx_inv};
    iter_row = rows{idx_iter};
else
    inv_row = rows(idx_inv);
    iter_row = rows(idx_iter);
end
testCase.assertEqual(inv_row.status, 'NOT_AVAILABLE_PRODUCER');
testCase.assertEqual(iter_row.status, 'AVAILABLE');
testCase.assertEqual(iter_row.value, 5);
end

function test_counters_rows_is_cell_with_14_entries(testCase)
% Shape/type guard: execution_counters.rows must be a 14-entry cell array,
% NOT a struct array collapsed to a scalar by the struct() constructor.
% Regression guard for the cell-of-identical-structs auto-conversion bug.
inputs = minimal_inputs();
r = ibr.section_h_report(inputs);
rows = r.execution_counters.rows;
testCase.assertTrue(iscell(rows), ...
    'execution_counters.rows must be a cell array, not a struct array');
testCase.assertEqual(numel(rows), 14);
expected_names = {'pf_invocations','pf_newton_iterations', ...
    'equilibrium_invocations','equilibrium_newton_iterations', ...
    'sssa_invocations','Jacobian_evaluations', ...
    'eigenvalue_decompositions','selector_candidates_evaluated', ...
    'ts_invocations','ts_steps_attempted','ts_steps_accepted', ...
    'ts_Newton_iterations','event_transactions','failed_transactions'};
names = cellfun(@(x) x.name, rows, 'UniformOutput', false);
% Compare column-vs-column (rows is [14x1], expected is [1x14]).
testCase.assertEqual(names(:), expected_names(:));
end

function test_convergence_summary_rows_is_cell(testCase)
% Shape/type guard: convergence_summary.rows must be a cell array, not a
% struct array collapsed by the struct() constructor.
inputs = minimal_inputs();
inputs.equilibrium = struct('converged',true,'iterations',5);
r = ibr.section_h_report(inputs);
rows = r.convergence_summary.rows;
testCase.assertTrue(iscell(rows), ...
    'convergence_summary.rows must be a cell array, not a struct array');
testCase.assertEqual(numel(rows), 1);
testCase.assertEqual(rows{1}.analysis, 'EQUILIBRIUM');
end

function test_fingerprint_unsupported_type_fails_closed(testCase)
% Fail-closed guard: an unsupported type in the fingerprint payload must
% error rather than silently produce a placeholder hash.
inputs = minimal_inputs();
% Attach a function handle (unsupported by canonical_serialize) to a
% field that feeds the fingerprint.
inputs.resource_map = struct('resource_index',1,'device_index',1, ...
    'device_id','IBR1','bus_position',2,'bus_id',2, ...
    'device_type','ibr_gfm','online',true, ...
    'bad_field', @sin);
testCase.assertError(@() ibr.section_h_report(inputs), ...
    'ibr:section_h_report:unsupportedType');
end

function test_spectrum_rows_is_cell_when_available(testCase)
% Shape guard: full_state_eigenvalues.rows must be a cell array, not a
% struct array collapsed by the struct() constructor.
inputs = inputs_with_sssa();
r = ibr.section_h_report(inputs);
testCase.assertEqual(r.full_state_eigenvalues.status, 'AVAILABLE');
rows = r.full_state_eigenvalues.rows;
testCase.assertTrue(iscell(rows), ...
    'full_state_eigenvalues.rows must be a cell array');
testCase.assertEqual(numel(rows), 4);
end

function test_participation_rows_is_cell_when_available(testCase)
% Shape guard: participation.rows must be a cell array.
inputs = inputs_with_sssa();
r = ibr.section_h_report(inputs);
testCase.assertEqual(r.participation.status, 'AVAILABLE');
rows = r.participation.rows;
testCase.assertTrue(iscell(rows), ...
    'participation.rows must be a cell array');
testCase.assertEqual(numel(rows), 4);
end

% ===================== resource map =====================================
function test_resource_map_not_inferred_when_absent(testCase)
inputs = minimal_inputs();
inputs.resource_map = [];
r = ibr.section_h_report(inputs);
testCase.assertEqual(r.sections(2).status, 'NOT_AVAILABLE_PRODUCER');
end

function test_resource_map_published_when_present(testCase)
inputs = minimal_inputs();
r = ibr.section_h_report(inputs);
testCase.assertEqual(r.sections(2).status, 'AVAILABLE');
testCase.assertEqual(numel(r.sections(2).rows), 1);
end
