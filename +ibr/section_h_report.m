function report = section_h_report(inputs, opt)
%SECTION_H_REPORT  IBR-owned Section H report assembler (read-only consumer).
%
%   report = ibr.section_h_report(inputs, opt) assembles the 12 mandatory
%   Section H log sections + analysis_fingerprint + execution counters from
%   PRECOMPUTED Phase 1 (ibr.state_inventory_snapshot) and Phase 2
%   (stability.modal_analysis) products plus optional PF/equilibrium/SSSA/TS
%   results. It is a PURE read-only consumer: it does NOT call eig, inv,
%   pinv, modal_analysis, state_inventory_snapshot, or any solver. It does
%   NOT edit any production struct. It invents no counters, no versions,
%   no eigenvalues, no participation.
%
%   Inputs (single named bundle):
%     inputs.case_data       (required)
%     inputs.inventory        (required, from ibr.state_inventory_snapshot)
%     inputs.resource_map    (required, struct array or empty)
%     inputs.bus_map         (optional)
%     inputs.pf              (optional, solved PF result)
%     inputs.equilibrium     (optional, mixed_equilibrium_solve result)
%     inputs.sssa            (optional, composite_sssa_model result)
%     inputs.modal_A         (optional, stability.modal_analysis(sssa))
%     inputs.modal_physical  (optional, stability.modal_analysis(sssa,'physical_A'))
%     inputs.ts_result       (optional, ts_simulate_ibr_hybrid result)
%     inputs.ts_meta         (optional, TS meta struct)
%     inputs.execution_counters (optional, explicit caller counters)
%     inputs.versions        (optional, caller-supplied version numbers)
%     inputs.full_state_ownership (optional, SG state ownership rows)
%
%   GFL_PLL_PARTICIPATION is derived from the state inventory: a production
%   WECC-only inventory reports 'NOT APPLICABLE TO CURRENT PRODUCTION MODEL'
%   (WECC GFL has no explicit PLL state); an inventory that includes an active
%   GFL-RMS10 device (delta_PLL/xi_PLL state rows present and active) reports
%   'APPLICABLE_EXPLICIT_GFL_PLL_STATES'. This is a pure read of the state
%   inventory; no production equation or Ared change.
%
%   See: docs/project/IEEE14_IBR_DYNAMIC_EQUATION_CONTRACT.md (Section H).
%   Status: SOURCE_IMPLEMENTED_PENDING_INTEGRATION_GATES. Read-only
%   consumer; no production numerical equation, Ared, or ABI change.

arguments
    inputs struct
    opt struct = struct()
end

schema_version = 'ibr.section_h_report/1';
serialization_version = 'canonical_ieee754_utf8/1';
biorthogonality_tol = 1e-6;
if isfield(opt,'biorthogonality_tol') && ~isempty(opt.biorthogonality_tol)
    biorthogonality_tol = opt.biorthogonality_tol;
end
participation_sum_tol = 1e-6;
if isfield(opt,'participation_sum_tol') && ~isempty(opt.participation_sum_tol)
    participation_sum_tol = opt.participation_sum_tol;
end

% --- Validate required inputs -------------------------------------------
if ~isfield(inputs,'case_data')
    error('ibr:section_h_report:missingCaseData', 'inputs.case_data is required.');
end
if ~isfield(inputs,'inventory') || ~isstruct(inputs.inventory)
    error('ibr:section_h_report:missingInventory', ...
        'inputs.inventory (from the Phase 1 state-inventory snapshot) is required.');
end
if ~isfield(inputs,'resource_map')
    error('ibr:section_h_report:missingResourceMap', ...
        'inputs.resource_map is required (may be empty).');
end

report = struct();
report.schema_version = schema_version;
report.status = 'AVAILABLE';
report.gfl_pll_participation = gfl_pll_applicability(inputs);

% --- Assemble 12 sections in frozen order -------------------------------
sections = repmat(section_template(), 1, 12);
sections(1)  = section_case_and_base(inputs);
sections(2)  = section_resource_device_map(inputs);
sections(3)  = section_state_inventory(inputs);
sections(4)  = section_input_inventory(inputs);
sections(5)  = section_pf_results(inputs);
sections(6)  = section_equilibrium_results(inputs);
sections(7)  = section_full_state_eigenvalues(inputs, opt);
sections(8)  = section_participation_factors(inputs, biorthogonality_tol, participation_sum_tol);
sections(9)  = section_ts_event_transactions(inputs);
sections(10) = section_ts_signal_index(inputs);
sections(11) = section_execution_counters(inputs);
sections(12) = section_convergence_summary(inputs, sections);
report.sections = sections;

% --- Spectrum tables (full + physical) ----------------------------------
report.full_state_eigenvalues = spectrum_table(inputs, 'A');
report.physical_decision_eigenvalues = spectrum_table(inputs, 'physical_A');

% --- Participation table -------------------------------------------------
report.participation = participation_table(inputs, biorthogonality_tol, participation_sum_tol);

% --- TS tables -----------------------------------------------------------
[report.ts_samples, report.ts_events, report.ts_signals] = ts_tables(inputs);

% --- Execution counters --------------------------------------------------
report.execution_counters = execution_counters_table(inputs);

% --- Convergence summary -------------------------------------------------
report.convergence_summary = convergence_summary(inputs, sections);

% --- Validation ----------------------------------------------------------
report.validation = build_validation(inputs, report, biorthogonality_tol, participation_sum_tol);

% --- analysis_fingerprint ------------------------------------------------
report.analysis_fingerprint = build_fingerprint(inputs, report, schema_version, serialization_version);

end

% =========================================================================
function s = section_template()
s = struct('section_id',0,'title','','applicability','','status','', ...
    'reason','','source_fields',{{}},'rows',{{}},'summary',struct());
end

% --- Section 1: CASE AND BASE -------------------------------------------
function s = section_case_and_base(inputs)
s = section_template();
s.section_id = 1;
s.title = 'CASE AND BASE';
s.applicability = 'ALWAYS';
s.status = 'AVAILABLE';
s.source_fields = {'case_data','bus_map','versions'};
cd = inputs.case_data;
baseMVA = NaN;
if isstruct(cd) && isfield(cd,'baseMVA') && ~isempty(cd.baseMVA)
    baseMVA = cd.baseMVA;
end
case_id = '';
if isstruct(cd) && isfield(cd,'case_id') && ~isempty(cd.case_id)
    case_id = char(cd.case_id);
end
freq = NaN;
if isstruct(cd) && isfield(cd,'fHz') && ~isempty(cd.fHz)
    freq = cd.fHz;
end
rows = {{'case_id',case_id,'baseMVA',baseMVA,'fHz',freq}};
s.rows = rows;
s.summary = struct('case_id',case_id,'baseMVA',baseMVA,'fHz',freq);
end

% --- Section 2: RESOURCE/DEVICE INDEX MAP -------------------------------
function s = section_resource_device_map(inputs)
s = section_template();
s.section_id = 2;
s.title = 'RESOURCE/DEVICE INDEX MAP';
s.applicability = 'ALWAYS';
rm = inputs.resource_map;
if isempty(rm)
    s.status = 'NOT_AVAILABLE_PRODUCER';
    s.reason = 'No explicit resource_map supplied; resource_index != device_index is not inferred.';
    return;
end
s.status = 'AVAILABLE';
s.source_fields = {'resource_map','inventory'};
rows = cell(numel(rm),1);
for k = 1:numel(rm)
    r = rm(k);
    rows{k} = struct('resource_index',r.resource_index,'device_index', ...
        safe_field(r,'device_index'),'device_id',safe_str(r,'device_id'), ...
        'bus_position',safe_field(r,'bus_position'),'bus_id',safe_field(r,'bus_id'), ...
        'device_type',safe_str(r,'device_type'),'online',safe_field(r,'online'));
end
s.rows = rows;
s.summary = struct('n_resources',numel(rm));
end

% --- Section 3: STATE INVENTORY -----------------------------------------
function s = section_state_inventory(inputs)
s = section_template();
s.section_id = 3;
s.title = 'STATE INVENTORY';
s.applicability = 'ALWAYS';
inv = inputs.inventory;
if ~isfield(inv,'state_rows')
    s.status = 'NOT_AVAILABLE_PRODUCER';
    s.reason = 'inventory.state_rows missing.';
    return;
end
s.status = 'AVAILABLE';
s.source_fields = {'inventory'};
s.rows = inv.state_rows;
c = inv.counts;
if isstruct(c)
    s.summary = c;
else
    s.summary = struct();
end
end

% --- Section 4: INPUT INVENTORY -----------------------------------------
function s = section_input_inventory(inputs)
s = section_template();
s.section_id = 4;
s.title = 'INPUT INVENTORY';
s.applicability = 'ALWAYS';
inv = inputs.inventory;
if ~isfield(inv,'input_rows')
    s.status = 'NOT_AVAILABLE_PRODUCER';
    s.reason = 'inventory.input_rows missing.';
    return;
end
s.status = 'AVAILABLE';
s.source_fields = {'inventory'};
s.rows = inv.input_rows;
s.summary = struct('n_inputs',numel(inv.input_rows));
end

% --- Section 5: PF RESULTS ---------------------------------------------
function s = section_pf_results(inputs)
s = section_template();
s.section_id = 5;
s.title = 'PF RESULTS';
s.applicability = 'ALWAYS';
if ~isfield(inputs,'pf') || isempty(inputs.pf)
    s.status = 'NOT_RUN';
    s.reason = 'No PF result supplied.';
    return;
end
s.status = 'AVAILABLE';
s.source_fields = {'pf'};
pf = inputs.pf;
s.summary = struct('converged',safe_field(pf,'converged'), ...
    'iterations',safe_field(pf,'iterations'), ...
    'mismatch',safe_field(pf,'mismatch'));
s.rows = {{'pf_summary','see producer fields'}};
end

% --- Section 6: EQUILIBRIUM RESULTS ------------------------------------
function s = section_equilibrium_results(inputs)
s = section_template();
s.section_id = 6;
s.title = 'EQUILIBRIUM RESULTS';
s.applicability = 'ALWAYS';
if ~isfield(inputs,'equilibrium') || isempty(inputs.equilibrium)
    s.status = 'NOT_RUN';
    s.reason = 'No equilibrium result supplied.';
    return;
end
s.status = 'AVAILABLE';
s.source_fields = {'equilibrium'};
eq = inputs.equilibrium;
s.summary = struct('converged',safe_field(eq,'converged'), ...
    'iterations',safe_field(eq,'iterations'), ...
    'physical_kcl_norm',safe_field(eq,'physical_kcl_norm'), ...
    'active_f_residual_norm',safe_field(eq,'active_f_residual_norm'));
end

% --- Section 7: FULL STATE EIGENVALUES ----------------------------------
function s = section_full_state_eigenvalues(inputs, ~)
s = section_template();
s.section_id = 7;
s.title = 'FULL STATE EIGENVALUES';
s.applicability = 'SSSA_ONLY';
if ~isfield(inputs,'sssa') || isempty(inputs.sssa)
    s.status = 'NOT_RUN';
    s.reason = 'No SSSA result supplied.';
    return;
end
if ~isfield(inputs,'modal_A') || isempty(inputs.modal_A)
    s.status = 'NOT_AVAILABLE_PRODUCER';
    s.reason = 'SSSA supplied but modal_A (Phase 2) missing.';
    return;
end
m = inputs.modal_A;
if ~strcmp(m.domain, 'A')
    s.status = 'INCONSISTENT_INPUT';
    s.reason = 'modal_A.domain must be ''A'' for the full-state table.';
    return;
end
nA = size(inputs.sssa.A, 1);
if numel(m.eigenvalues) ~= nA
    s.status = 'INCONSISTENT_INPUT';
    s.reason = sprintf('modal_A eigenvalue count %d != size(sssa.A,1)=%d.', numel(m.eigenvalues), nA);
    return;
end
s.status = 'AVAILABLE';
s.source_fields = {'sssa','modal_A'};
s.summary = struct('eigenvalue_count',numel(m.eigenvalues),'size_Ared',nA);
end

% --- Section 8: PARTICIPATION FACTORS -----------------------------------
function s = section_participation_factors(inputs, biorth_tol, part_sum_tol)
s = section_template();
s.section_id = 8;
s.title = 'PARTICIPATION FACTORS';
s.applicability = 'SSSA_ONLY';
if ~isfield(inputs,'modal_A') || isempty(inputs.modal_A)
    s.status = 'NOT_AVAILABLE_PRODUCER';
    s.reason = 'modal_A (Phase 2) missing.';
    return;
end
m = inputs.modal_A;
s.status = 'AVAILABLE';
s.source_fields = {'modal_A','inventory'};
% Biorthogonality + participation-sum validation summary.
bio_res = safe_field(m,'biorthogonality_residual');
part_sum = safe_field(m,'participation_sum');
avail = strcmp(m.participation_status, 'AVAILABLE_SIMPLE');
s.summary = struct('biorthogonality_residual',bio_res, ...
    'biorthogonality_tol',biorth_tol, ...
    'n_available_modes',sum(avail), ...
    'n_unavailable_modes',sum(~avail), ...
    'participation_sum_tol',part_sum_tol, ...
    'gfl_pll_participation',gfl_pll_applicability(inputs));
end

% --- Section 9: TS EVENT TRANSACTIONS -----------------------------------
function s = section_ts_event_transactions(inputs)
s = section_template();
s.section_id = 9;
s.title = 'TS EVENT TRANSACTIONS';
s.applicability = 'TS_ONLY';
if ~isfield(inputs,'ts_result') || isempty(inputs.ts_result)
    s.status = 'NOT_RUN';
    s.reason = 'No TS result supplied.';
    return;
end
s.status = 'AVAILABLE';
s.source_fields = {'ts_result'};
tr = inputs.ts_result;
n_events = 0;
if isfield(tr,'event_log') && ~isempty(tr.event_log)
    n_events = numel(tr.event_log);
end
s.summary = struct('n_events',n_events);
end

% --- Section 10: TS SIGNAL INDEX ----------------------------------------
function s = section_ts_signal_index(inputs)
s = section_template();
s.section_id = 10;
s.title = 'TS SIGNAL INDEX';
s.applicability = 'TS_ONLY';
if ~isfield(inputs,'ts_result') || isempty(inputs.ts_result)
    s.status = 'NOT_RUN';
    s.reason = 'No TS result supplied.';
    return;
end
s.status = 'AVAILABLE';
s.source_fields = {'ts_result'};
tr = inputs.ts_result;
n_samples = 0;
if isfield(tr,'t') && ~isempty(tr.t)
    n_samples = numel(tr.t);
end
s.summary = struct('n_samples',n_samples);
end

% --- Section 11: EXECUTION COUNTERS -------------------------------------
function s = section_execution_counters(inputs)
s = section_template();
s.section_id = 11;
s.title = 'EXECUTION COUNTERS';
s.applicability = 'ALWAYS';
s.status = 'AVAILABLE';
s.source_fields = {'pf','equilibrium','sssa','ts_result','execution_counters'};
s.rows = {{}};   % placeholder; full table in report.execution_counters
s.summary = struct();
end

% --- Section 12: CONVERGENCE/FAILURE SUMMARY -----------------------------
function s = section_convergence_summary(inputs, ~)
s = section_template();
s.section_id = 12;
s.title = 'CONVERGENCE/FAILURE SUMMARY';
s.applicability = 'ALWAYS';
s.status = 'AVAILABLE';
s.source_fields = {'pf','equilibrium','sssa','ts_result'};
rows = {};
if isfield(inputs,'pf') && ~isempty(inputs.pf)
    rows{end+1} = struct('analysis','PF','converged',safe_field(inputs.pf,'converged')); %#ok<AGROW>
end
if isfield(inputs,'equilibrium') && ~isempty(inputs.equilibrium)
    rows{end+1} = struct('analysis','EQUILIBRIUM','converged',safe_field(inputs.equilibrium,'converged')); %#ok<AGROW>
end
if isfield(inputs,'sssa') && ~isempty(inputs.sssa)
    rows{end+1} = struct('analysis','SSSA','converged',true); %#ok<AGROW>
end
if isfield(inputs,'ts_result') && ~isempty(inputs.ts_result)
    rows{end+1} = struct('analysis','TS','converged',safe_field(inputs.ts_result,'converged')); %#ok<AGROW>
end
s.rows = rows;
s.summary = struct('n_analyses',numel(rows));
end

% --- Spectrum table -----------------------------------------------------
function tbl = spectrum_table(inputs, domain)
tbl = struct('domain',domain,'status','NOT_RUN','reason','','rows',{{}},'summary',struct());
if ~isfield(inputs,'sssa') || isempty(inputs.sssa)
    return;
end
modal_field = 'modal_A';
if strcmp(domain,'physical_A')
    modal_field = 'modal_physical';
end
if ~isfield(inputs,modal_field) || isempty(inputs.(modal_field))
    tbl.status = 'NOT_AVAILABLE_PRODUCER';
    tbl.reason = sprintf('modal product for domain %s not supplied.', domain);
    return;
end
m = inputs.(modal_field);
if ~strcmp(m.domain, domain)
    tbl.status = 'INCONSISTENT_INPUT';
    tbl.reason = sprintf('modal domain %s != requested %s.', m.domain, domain);
    return;
end
n = numel(m.eigenvalues);
rows = cell(n,1);
for k = 1:n
    rows{k} = struct( ...
        'display_mode_number', k, ...
        'raw_eigen_index', m.raw_eigen_index(k), ...
        'conjugate_pair_id', m.conjugate_pair_id(k), ...
        'eigenvalue', m.eigenvalues(k), ...
        'formatted_eigenvalue', sprintf('%+.2e %+.2ej', real(m.eigenvalues(k)), imag(m.eigenvalues(k))), ...
        'right_residual', m.right_residual(k), ...
        'left_residual', m.left_residual(k), ...
        'participation_status', m.participation_status{k});
end
tbl.status = 'AVAILABLE';
tbl.rows = rows;
tbl.summary = struct('eigenvalue_count', n, 'size_domain_matrix', m.matrix_dimension);
end

% --- Participation table -------------------------------------------------
function tbl = participation_table(inputs, ~, part_sum_tol)
tbl = struct('status','NOT_AVAILABLE_PRODUCER','reason','','rows',{{}},'summary',struct());
if ~isfield(inputs,'modal_A') || isempty(inputs.modal_A)
    tbl.reason = 'modal_A missing.';
    return;
end
m = inputs.modal_A;
n = numel(m.eigenvalues);
rows = cell(n,1);
for k = 1:n
    rows{k} = struct( ...
        'display_mode_number', k, ...
        'raw_eigen_index', m.raw_eigen_index(k), ...
        'conjugate_pair_id', m.conjugate_pair_id(k), ...
        'participation_status', m.participation_status{k}, ...
        'participation_reason', m.participation_reason{k}, ...
        'participation_sum', m.participation_sum(k));
end
tbl.status = 'AVAILABLE';
tbl.rows = rows;
tbl.summary = struct('n_modes', n, 'participation_sum_tol', part_sum_tol, ...
    'gfl_pll_participation', gfl_pll_applicability(inputs));
end

% --- TS tables -----------------------------------------------------------
function [samples, events, signals] = ts_tables(inputs)
samples = struct('status','NOT_RUN','reason','','rows',{{}},'summary',struct());
events = struct('status','NOT_RUN','reason','','rows',{{}},'summary',struct());
signals = struct('status','NOT_RUN','reason','','rows',{{}},'summary',struct());
if ~isfield(inputs,'ts_result') || isempty(inputs.ts_result)
    return;
end
tr = inputs.ts_result;
% Samples
if isfield(tr,'t') && ~isempty(tr.t)
    nt = numel(tr.t);
    srows = cell(nt,1);
    for k = 1:nt
        srows{k} = struct('time_sample_index',k,'time',tr.t(k), ...
            'sample_side',safe_idx(tr,'sample_side',k), ...
            'transaction_id',safe_idx(tr,'transaction_id',k));
    end
    samples.status = 'AVAILABLE';
    samples.rows = srows;
    samples.summary = struct('n_samples',nt);
end
% Events
if isfield(tr,'event_log') && ~isempty(tr.event_log)
    ne = numel(tr.event_log);
    erows = cell(ne,1);
    for k = 1:ne
        ev = tr.event_log(k);
        erows{k} = struct('event_index',k,'type',safe_str(ev,'type'), ...
            't',safe_field(ev,'t'),'transaction_id',safe_field(ev,'transaction_id'), ...
            'applied',safe_field(ev,'applied'),'failure_id',safe_str(ev,'failure_id'));
    end
    events.status = 'AVAILABLE';
    events.rows = erows;
    events.summary = struct('n_events',ne);
end
signals.status = 'AVAILABLE';
signals.summary = struct('n_signals',0,'note','signal catalog: producer fields consumed as-is; metadata gaps marked NOT_AVAILABLE_PRODUCER at render time.');
end

% --- Execution counters table -------------------------------------------
function tbl = execution_counters_table(inputs)
rows = cell(14,1);
rows{1}  = struct('name','pf_invocations','value',NaN,'status',counter_status(inputs,'pf','invocations'));
rows{2}  = struct('name','pf_newton_iterations','value',safe_nested(inputs,'pf','iterations'),'status',counter_status(inputs,'pf','iterations'));
rows{3}  = struct('name','equilibrium_invocations','value',NaN,'status',counter_status(inputs,'equilibrium','invocations'));
rows{4}  = struct('name','equilibrium_newton_iterations','value',safe_nested(inputs,'equilibrium','iterations'),'status',counter_status(inputs,'equilibrium','iterations'));
rows{5}  = struct('name','sssa_invocations','value',NaN,'status','NOT_AVAILABLE_PRODUCER');
rows{6}  = struct('name','Jacobian_evaluations','value',NaN,'status','NOT_AVAILABLE_PRODUCER');
rows{7}  = struct('name','eigenvalue_decompositions','value',NaN,'status','NOT_AVAILABLE_PRODUCER');
rows{8}  = struct('name','selector_candidates_evaluated','value',NaN,'status','NOT_AVAILABLE_PRODUCER');
rows{9}  = struct('name','ts_invocations','value',NaN,'status',counter_status(inputs,'ts_result','invocations'));
rows{10} = struct('name','ts_steps_attempted','value',safe_nested(inputs,'ts_result','step_attempts'),'status',counter_status(inputs,'ts_result','step_attempts'));
rows{11} = struct('name','ts_steps_accepted','value',safe_nested(inputs,'ts_result','accepted_steps'),'status',counter_status(inputs,'ts_result','accepted_steps'));
rows{12} = struct('name','ts_Newton_iterations','value',safe_nested(inputs,'ts_meta','iterations'),'status',counter_status(inputs,'ts_meta','iterations'));
rows{13} = struct('name','event_transactions','value',NaN,'status','NOT_AVAILABLE_PRODUCER');
rows{14} = struct('name','failed_transactions','value',NaN,'status','NOT_AVAILABLE_PRODUCER');
tbl = struct('status','AVAILABLE','rows',{rows},'summary',struct('n_counters',numel(rows)));
end

function st = counter_status(inputs, field, subfield)
if ~isfield(inputs,field) || isempty(inputs.(field))
    st = 'NOT_RUN';
    return;
end
v = safe_nested(inputs, field, subfield);
if isnan(v)
    st = 'NOT_AVAILABLE_PRODUCER';
else
    st = 'AVAILABLE';
end
end

% --- Convergence summary ------------------------------------------------
function tbl = convergence_summary(inputs, ~)
rows = {};
if isfield(inputs,'pf') && ~isempty(inputs.pf)
    rows{end+1} = struct('analysis','PF','converged',safe_field(inputs.pf,'converged')); %#ok<AGROW>
end
if isfield(inputs,'equilibrium') && ~isempty(inputs.equilibrium)
    rows{end+1} = struct('analysis','EQUILIBRIUM','converged',safe_field(inputs.equilibrium,'converged')); %#ok<AGROW>
end
if isfield(inputs,'sssa') && ~isempty(inputs.sssa)
    rows{end+1} = struct('analysis','SSSA','converged',true); %#ok<AGROW>
end
if isfield(inputs,'ts_result') && ~isempty(inputs.ts_result)
    rows{end+1} = struct('analysis','TS','converged',safe_field(inputs.ts_result,'converged')); %#ok<AGROW>
end
tbl = struct('status','AVAILABLE','rows',{rows},'summary',struct('n_analyses',numel(rows)));
end

% --- Validation ----------------------------------------------------------
function v = build_validation(inputs, report, ~, part_sum_tol)
v = struct();
v.full_state_eigenvalues_count = 0;
v.size_Ared = NaN;
if isfield(inputs,'sssa') && ~isempty(inputs.sssa) && isfield(inputs.sssa,'A')
    v.size_Ared = size(inputs.sssa.A,1);
end
if isfield(report,'full_state_eigenvalues') && isfield(report.full_state_eigenvalues,'rows')
    v.full_state_eigenvalues_count = numel(report.full_state_eigenvalues.rows);
end
v.cardinality_check = (v.full_state_eigenvalues_count == v.size_Ared);
v.participation_sum_tol = part_sum_tol;
v.gfl_pll_participation = gfl_pll_applicability(inputs);
end

% --- analysis_fingerprint ----------------------------------------------
function fp = build_fingerprint(inputs, ~, schema_version, serialization_version)
fp = struct();
fp.schema_version = schema_version;
fp.serialization_version = serialization_version;
fp.hash_algorithm = 'SHA-256';
fp.case_id = '';
if isfield(inputs,'case_data') && isstruct(inputs.case_data) && isfield(inputs.case_data,'case_id')
    fp.case_id = char(inputs.case_data.case_id);
end
% Component hashes (canonical serialization + SHA-256).
fp.bus_map_hash = hash_optional(inputs, 'bus_map');
fp.resource_map_hash = hash_optional(inputs, 'resource_map');
fp.state_map_hash = hash_inventory_state(inputs);
fp.input_map_hash = hash_inventory_input(inputs);
fp.equilibrium_hash = hash_optional(inputs, 'equilibrium');
fp.topology_version = version_field(inputs, 'topology_version');
fp.topology_version_status = version_status(inputs, 'topology_version');
fp.dispatch_version = version_field(inputs, 'dispatch_version');
fp.dispatch_version_status = version_status(inputs, 'dispatch_version');
fp.matrix_domain = 'A';
fp.matrix_hash = hash_matrix(inputs, 'sssa', 'A');
fp.active_bound_regime_hash = hash_active_bound(inputs);
fp.gauge_quotient_hash = hash_gauge(inputs);
fp.transformation_maps_hash = hash_transform_maps(inputs);
fp.ordering_policy = '';
fp.conjugate_pair_policy = 'modal_conjugate_pair_ids_consumed_v1';
fp.modal_algorithm_version = '';
if isfield(inputs,'modal_A') && ~isempty(inputs.modal_A) && isfield(inputs.modal_A,'sorting_policy')
    fp.ordering_policy = inputs.modal_A.sorting_policy;
    fp.modal_algorithm_version = inputs.modal_A.algorithm_version;
end
% Aggregate hash over component hashes + statuses + policies.
agg_payload = [fp.bus_map_hash, fp.resource_map_hash, fp.state_map_hash, ...
    fp.input_map_hash, fp.equilibrium_hash, fp.matrix_hash, ...
    fp.active_bound_regime_hash, fp.gauge_quotient_hash, ...
    fp.transformation_maps_hash, fp.ordering_policy, ...
    fp.conjugate_pair_policy, fp.modal_algorithm_version];
fp.aggregate_hash = sha256_str(agg_payload);
fp.component_status = struct('bus_map',status_of(inputs,'bus_map'), ...
    'resource_map',status_of(inputs,'resource_map'), ...
    'inventory',status_of(inputs,'inventory'), ...
    'equilibrium',status_of(inputs,'equilibrium'), ...
    'sssa',status_of(inputs,'sssa'), ...
    'modal_A',status_of(inputs,'modal_A'), ...
    'ts_result',status_of(inputs,'ts_result'));
end

function h = hash_optional(inputs, field)
if ~isfield(inputs,field) || isempty(inputs.(field))
    h = 'NOT_AVAILABLE';
    return;
end
h = sha256_str(canonical_serialize(inputs.(field)));
end

function h = hash_inventory_state(inputs)
if ~isfield(inputs,'inventory') || ~isfield(inputs.inventory,'state_rows')
    h = 'NOT_AVAILABLE';
    return;
end
h = sha256_str(canonical_serialize(inputs.inventory.state_rows));
end

function h = hash_inventory_input(inputs)
if ~isfield(inputs,'inventory') || ~isfield(inputs.inventory,'input_rows')
    h = 'NOT_AVAILABLE';
    return;
end
h = sha256_str(canonical_serialize(inputs.inventory.input_rows));
end

function s = gfl_pll_applicability(inputs)
%GFL_PLL_APPLICABILITY  Derive GFL-PLL participation applicability from state inventory.
%   The production WECC GFL has no explicit PLL state (current aligns to angle(V)
%   algebraically), so GFL-PLL participation is NOT APPLICABLE. The GFL-RMS10
%   device owns explicit SRF-PLL states (delta_PLL, xi_PLL); when any active
%   state row carries such a name, applicability becomes APPLICABLE_EXPLICIT.
%   This is a pure read of inputs.inventory.state_rows; no production equation
%   or Ared change. WECC-only inventories retain the legacy NOT APPLICABLE.
not_applicable = 'NOT APPLICABLE TO CURRENT PRODUCTION MODEL';
applicable = 'APPLICABLE_EXPLICIT_GFL_PLL_STATES';
s = not_applicable;
if ~isfield(inputs,'inventory') || ~isstruct(inputs.inventory) ...
        || ~isfield(inputs.inventory,'state_rows')
    return;
end
rows = inputs.inventory.state_rows;
if isempty(rows)
    return;
end
% state_rows may be a struct array (1xN) or a cell of structs; normalize.
if iscell(rows)
    names = cellfun(@(r) char(r.state_name), rows, 'UniformOutput', false);
    statuses = cellfun(@(r) char(r.state_status), rows, 'UniformOutput', false);
else
    names = arrayfun(@(r) char(r.state_name), rows, 'UniformOutput', false);
    statuses = arrayfun(@(r) char(r.state_status), rows, 'UniformOutput', false);
end
pll_names = {'delta_PLL','xi_PLL','gfl_delta_PLL','gfl_xi_PLL'};
for k = 1:numel(names)
    if any(strcmp(names{k}, pll_names)) && ...
            (strcmp(statuses{k},'ACTIVE_IN_ARED') || ...
             strcmp(statuses{k},'ACTIVE') || ...
             strcmp(statuses{k},'ACTIVE_IN_FULL'))
        s = applicable;
        return;
    end
end
end

function h = hash_matrix(inputs, field, subfield)
if ~isfield(inputs,field) || isempty(inputs.(field)) || ~isfield(inputs.(field),subfield)
    h = 'NOT_AVAILABLE';
    return;
end
M = inputs.(field).(subfield);
h = sha256_str(canonical_serialize(M));
end

function h = hash_active_bound(inputs)
if ~isfield(inputs,'sssa') || isempty(inputs.sssa) || ...
        ~isfield(inputs.sssa,'active_bound_constraint_global_indices') || ...
        isempty(inputs.sssa.active_bound_constraint_global_indices)
    h = 'NOT_AVAILABLE';
    return;
end
h = sha256_str(canonical_serialize(inputs.sssa.active_bound_constraint_global_indices));
end

function h = hash_gauge(inputs)
if ~isfield(inputs,'sssa') || isempty(inputs.sssa) || ...
        ~isfield(inputs.sssa,'coordinate_gauge_global_index') || ...
        isempty(inputs.sssa.coordinate_gauge_global_index)
    h = 'NOT_AVAILABLE';
    return;
end
h = sha256_str(canonical_serialize(inputs.sssa.coordinate_gauge_global_index));
end

function h = hash_transform_maps(inputs)
if ~isfield(inputs,'sssa') || isempty(inputs.sssa)
    h = 'NOT_AVAILABLE';
    return;
end
payload = '';
if isfield(inputs.sssa,'active_bound_tangent_map') && ~isempty(inputs.sssa.active_bound_tangent_map)
    payload = [payload, canonical_serialize(inputs.sssa.active_bound_tangent_map)];
end
if isfield(inputs.sssa,'coordinate_quotient_left_map') && ~isempty(inputs.sssa.coordinate_quotient_left_map)
    payload = [payload, canonical_serialize(inputs.sssa.coordinate_quotient_left_map)];
end
if isfield(inputs.sssa,'coordinate_quotient_right_map') && ~isempty(inputs.sssa.coordinate_quotient_right_map)
    payload = [payload, canonical_serialize(inputs.sssa.coordinate_quotient_right_map)];
end
if isempty(payload)
    h = 'NOT_AVAILABLE';
else
    h = sha256_str(payload);
end
end

function v = version_field(inputs, name)
v = NaN;
if isfield(inputs,'versions') && isstruct(inputs.versions) && isfield(inputs.versions,name)
    v = inputs.versions.(name);
end
end

function st = version_status(inputs, name)
v = version_field(inputs, name);
if isnan(v)
    st = 'NOT_AVAILABLE_PRODUCER';
else
    st = 'AVAILABLE';
end
end

function st = status_of(inputs, field)
if ~isfield(inputs,field) || isempty(inputs.(field))
    st = 'NOT_RUN';
else
    st = 'AVAILABLE';
end
end

% --- Canonical serialization (deterministic within a MATLAB version) ----
function s = canonical_serialize(x)
% Recursive canonical serialization to a string.
% Sorts struct fields, encodes class/dims/values explicitly. Rejects
% function handles, Java objects, and any unsupported type by erroring
% fail-closed (a fingerprint that silently drops a value would be
% misleading). The caller (sha256_str) does the UTF-8 encoding.
% NOTE: this is a change-detection fingerprint, NOT a cross-version
% canonical form; mat2str/num2str formatting can vary across MATLAB
% releases. Stability is asserted only for identical input on the same
% MATLAB version (covered by test_fingerprint_stable_identical_input).
s = serialize_value(x);
end

function s = serialize_value(x)
if isstruct(x)
    fns = sort(fieldnames(x));
    s = 'S{';
    for k = 1:numel(fns)
        s = [s, fns{k}, ':', serialize_value(x.(fns{k})), ';']; %#ok<AGROW>
    end
    s = [s, '}'];
elseif iscell(x)
    s = 'C[';
    for k = 1:numel(x)
        s = [s, serialize_value(x{k}), ',']; %#ok<AGROW>
    end
    s = [s, ']'];
elseif ischar(x) || isstring(x)
    s = ['T"', char(x), '"'];
elseif isnumeric(x)
    if isempty(x)
        s = 'N[]';
    else
        s = ['N', mat2str(x, 17)];
    end
elseif islogical(x)
    s = ['L', num2str(x)];
else
    error('ibr:section_h_report:unsupportedType', ...
        'canonical_serialize: unsupported type %s; cannot compute a faithful fingerprint.', ...
        class(x));
end
end

% --- SHA-256 (Java, in-process; fail-closed if unavailable) -------------
function h = sha256_str(s)
try
    md = java.security.MessageDigest.getInstance('SHA-256');
    bytes = unicode2native(s, 'UTF-8');
    md.update(bytes);
    digest = md.digest();
    h = lower(reshape(dec2hex(typecast(digest,'uint8'),2).',1,[]));
catch
    error('ibr:section_h_report:sha256Unavailable', ...
        'Java SHA-256 unavailable; cannot compute change-detection fingerprint.');
end
end

% --- Safe field accessors ------------------------------------------------
function v = safe_field(s, f)
if isstruct(s) && isfield(s,f) && ~isempty(s.(f))
    v = s.(f);
else
    v = NaN;
end
end

function v = safe_str(s, f)
if isstruct(s) && isfield(s,f) && ~isempty(s.(f))
    v = char(s.(f));
else
    v = '';
end
end

function v = safe_idx(s, f, k)
if isstruct(s) && isfield(s,f) && numel(s.(f)) >= k
    v = s.(f)(k);
else
    v = NaN;
end
end

function v = safe_nested(inputs, field, subfield)
if ~isfield(inputs,field) || isempty(inputs.(field))
    v = NaN;
    return;
end
s = inputs.(field);
if isstruct(s) && isfield(s,subfield) && ~isempty(s.(subfield))
    v = s.(subfield);
else
    v = NaN;
end
end
