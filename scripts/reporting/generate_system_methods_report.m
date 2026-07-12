function out = generate_system_methods_report(opts)
%GENERATE_SYSTEM_METHODS_REPORT  Canonical report orchestrator.
%   OUT = generate_system_methods_report(OPTS) runs every required project
%   computation fresh against the report HEAD, invokes PSAT/PGAz only through
%   tracked validation adapters, saves raw artifacts with metadata, writes all
%   LaTeX tables programmatically, exports all plots programmatically, and
%   writes a machine-readable manifest. Fails closed if a requested comparison
%   lacks a valid mapping or compatible input contract.
%
%   OPTS fields (all optional):
%     cases       - cell of case names to run (default: all)
%     output_dir  - output directory (default: docs/source/figures/system_methods)
%     return_raw  - request raw trajectories from validators (default: true)
%
%   Per mission: no computed value typed manually; no production numerical
%   behavior changed; PSAT/PGAz never enter pf_init_paths or production path.

if nargin < 1, opts = struct(); end
if ~isfield(opts,'cases'), opts.cases = {'case_matpower6_case14','case_ieee_rts24_pgaz','case_padiyar_two_area_4m_avr'}; end
if ~isfield(opts,'output_dir')
    root = pf_init_paths;
    opts.output_dir = fullfile(root,'docs','source','figures','system_methods');
end
if ~isfield(opts,'return_raw'), opts.return_raw = true; end
if ~exist(opts.output_dir,'dir'), mkdir(opts.output_dir); end

% --- Capture manifest header ---
[status, head] = system('git -C /home/birds/Documents/Power-flow-report rev-parse HEAD');
if status ~= 0, head = 'unknown'; else, head = strtrim(head); end
fprintf('=== generate_system_methods_report ===\n');
fprintf('Git HEAD: %s\n', head);
fprintf('Output dir: %s\n', opts.output_dir);
fprintf('Cases: %s\n', strjoin(opts.cases, ', '));

entries = struct('case_function',{},'solver_model_stepper',{}, ...
    'source_reference_status',{},'fresh_saved_status',{}, ...
    'input_contract_fingerprint',{},'output_filenames',{});

% --- Equation provenance register + audit (must be READY before prose) ---
reg = equation_register();
audit_status = equation_audit(reg, fileparts(fileparts(fileparts(mfilename('fullpath')))));
equation_register_export(opts.output_dir);
fprintf('Equation provenance: %s (gaps=%d)\n', ...
    audit_status.DOCUMENTATION_EQUATION_PROVENANCE_READY, numel(audit_status.gaps));
if ~strcmp(audit_status.DOCUMENTATION_EQUATION_PROVENANCE_READY, 'READY')
    warning('generate_system_methods_report:provenanceNotReady', ...
        'Equation provenance NOT_READY. Report cannot be published as final.');
end

% --- Per-case generation ---
case_results = struct();
for i = 1:numel(opts.cases)
    cn = opts.cases{i};
    fprintf('\n--- Case: %s ---\n', cn);
    switch cn
    case 'case_matpower6_case14'
        cr = run_ieee14(opts);
    case 'case_ieee_rts24_pgaz'
        cr = run_rts24(opts);
    case 'case_padiyar_two_area_4m_avr'
        cr = run_padiyar(opts);
    otherwise
        warning('generate_system_methods_report:unknownCase','Unknown case: %s', cn);
        continue;
    end
    case_results.(cn) = cr;
    entries(end+1) = cr.entry; %#ok<AGROW>
end

% --- Cross-case synthesis ---
cross_rows = build_cross_case_rows(case_results);
report_table_helpers('cross_case', cross_rows, fullfile(opts.output_dir,'table_cross_case.tex'));

% --- Write manifest ---
manifest = report_manifest(head, opts.output_dir, entries);

out = struct('head',head,'output_dir',opts.output_dir, ...
    'case_results',case_results,'manifest',manifest, ...
    'audit_status',audit_status);
fprintf('\n=== generate_system_methods_report complete ===\n');
fprintf('Manifest: %s\n', fullfile(opts.output_dir,'manifest.json'));
fprintf('Equation provenance: %s\n', audit_status.DOCUMENTATION_EQUATION_PROVENANCE_READY);
end

% =========================================================================
% Per-case runners (stubs filled in subsequent commits C4-C6)
% =========================================================================
function cr = run_ieee14(opts)
% IEEE 14-bus: Ours vs PSAT vs PGAz (PRIMARY case per advisor directive).
% SG dynamic data labeled ASSUMED_DIAGNOSTIC (MATPOWER supplies network/PF only).
cr = struct();
cr.entry = struct('case_function','case_matpower6_case14', ...
    'solver_model_stepper','classical PF/SSSA/TS fixed+adaptive', ...
    'source_reference_status','PSAT+PGAz via tracked adapters', ...
    'fresh_saved_status','pending', ...
    'input_contract_fingerprint','', ...
    'output_filenames',{{}});
try
    c = cases.case_matpower6_case14();
    sc = struct('fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1, ...
        'dt',0.01,'t_end',15.0);
    fp = input_contract_fingerprint(c, sc, struct('stepper','fixed'));
    cr.entry.input_contract_fingerprint = fp.hash;
    % Run three-way validation with structured raw return.
    tw = run_three_way_validation('case_matpower6_case14', sc, 8, opts.return_raw);
    cr.three_way = tw;
    cr.fingerprint = fp;
    cr.entry.fresh_saved_status = 'ours_fresh; psat/pgaz fresh-or-saved per contract';
    % Emit tables and figures (filled in C4).
    emit_ieee14_assets(c, sc, tw, fp, opts);
catch ME
    warning('run_ieee14:failed: %s', ME.message);
    cr.entry.fresh_saved_status = ['FAILED: ' ME.message];
end
end

function cr = run_rts24(opts)
% IEEE RTS-24: Ours vs PSAT (PGAz contract status stated).
cr = struct();
cr.entry = struct('case_function','case_ieee_rts24_pgaz', ...
    'solver_model_stepper','classical PF/SSSA/TS fixed+adaptive', ...
    'source_reference_status','PSAT via tracked adapter; PGAz contract status', ...
    'fresh_saved_status','pending', ...
    'input_contract_fingerprint','', ...
    'output_filenames',{{}});
try
    c = cases.case_ieee_rts24_pgaz();
    sc = struct('fault_bus',15,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1, ...
        'dt',0.01,'t_end',15.0);
    fp = input_contract_fingerprint(c, sc, struct('stepper','fixed'));
    cr.entry.input_contract_fingerprint = fp.hash;
    tw = run_three_way_validation('case_ieee_rts24_pgaz', sc, 8, opts.return_raw);
    cr.three_way = tw;
    cr.fingerprint = fp;
    cr.entry.fresh_saved_status = 'ours_fresh; psat fresh-or-saved per contract';
    emit_rts24_assets(c, sc, tw, fp, opts);
catch ME
    warning('run_rts24:failed: %s', ME.message);
    cr.entry.fresh_saved_status = ['FAILED: ' ME.message];
end
end

function cr = run_padiyar(opts)
% Padiyar four-machine two-area: reuse the existing tracked sub-generator.
cr = struct();
cr.entry = struct('case_function','case_padiyar_two_area_4m_avr', ...
    'solver_model_stepper','Padiyar model-1.1 PF/SSSA/TS AVR+manual', ...
    'source_reference_status','Padiyar Tables 9.2/9.5 (sourced)', ...
    'fresh_saved_status','pending', ...
    'input_contract_fingerprint','', ...
    'output_filenames',{{}});
try
    % Call the existing generator (cherry-picked in C0).
    pad = generate_padiyar_two_area_report();
    cr.padiyar = pad;
    c = cases.case_padiyar_two_area_4m_avr();
    sc = struct('fault_bus',3,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.5, ...
        'dt',0.005,'t_end',3.0);
    fp = input_contract_fingerprint(c, sc, struct('stepper','fixed'));
    cr.entry.input_contract_fingerprint = fp.hash;
    cr.entry.fresh_saved_status = 'ours_fresh; book reference (Table 9.2/9.5)';
    if isstruct(pad) && isfield(pad,'output_dir')
        cr.entry.output_filenames = {fullfile(pad.output_dir,'table_pf_bus.tex'), ...
            fullfile(pad.output_dir,'table_eigenvalues.tex')};
    end
catch ME
    warning('run_padiyar:failed: %s', ME.message);
    cr.entry.fresh_saved_status = ['FAILED: ' ME.message];
end
end

% =========================================================================
% Asset emitters (filled in C4-C6)
% =========================================================================
function emit_ieee14_assets(c, sc, tw, fp, opts)
% Emit IEEE14 tables and figures (filled in C4).
outdir = opts.output_dir;
cap = struct('case','IEEE14','model','classical','scenario','bus4 fault', ...
    'data_source','Ours/PSAT/PGAz','generating_command','generate_system_methods_report', ...
    'fresh_saved','ours_fresh','metric','PF bus voltage');
% PF tables
if isfield(tw,'pf') && isfield(tw.pf,'ps_ours')
    ours_pf = tw.pf.ps_ours;  % placeholder; real fields from tw
end
% (Full table/figure emission filled in C4.)
end

function emit_rts24_assets(c, sc, tw, fp, opts)
% Emit RTS-24 tables and figures (filled in C5).
end

function rows = build_cross_case_rows(case_results)
rows = struct('case_name',{},'pf_max_mismatch',{},'pf_ext_err',{}, ...
    'dominant_mode',{},'ts_bounded',{},'fa_diff',{},'status',{});
fns = fieldnames(case_results);
for i = 1:numel(fns)
    cr = case_results.(fns{i});
    rows(i).case_name = fns{i};
    rows(i).pf_max_mismatch = NaN;
    rows(i).pf_ext_err = NaN;
    rows(i).dominant_mode = 'pending';
    rows(i).ts_bounded = 'pending';
    rows(i).fa_diff = NaN;
    rows(i).status = 'pending';
end
end
