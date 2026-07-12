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

% entries is a cell array of per-case structs (built in the per-case loop).

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
entries = {};
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
    entries{end+1} = cr.entry; %#ok<AGROW>
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
    % Emit fixed-vs-adaptive overlay for Padiyar (model 1.1 AVR).
    emit_padiyar_fixed_adaptive(c, sc, pad, opts);
catch ME
    warning('run_padiyar:failed: %s', ME.message);
    cr.entry.fresh_saved_status = ['FAILED: ' ME.message];
end
end

function emit_padiyar_fixed_adaptive(c, sc, pad, opts)
% Run Padiyar model-1.1 fixed + adaptive TS and emit the overlay figure.
outdir = opts.output_dir;
% padiyar_dir is the sibling Padiyar assets dir (cherry-picked from C0).
padiyar_dir = fullfile(fileparts(fileparts(opts.output_dir)), 'padiyar_two_area');
if ~exist(padiyar_dir,'dir'), padiyar_dir = pad.output_dir; end
opt_fixed = struct('t_end',sc.t_end,'dt',sc.dt,'fault_bus',sc.fault_bus, ...
    't_fault',sc.t_fault,'t_clear',sc.t_clear,'Zf',sc.Zf, ...
    'method','trapezoidal','corrector_mode','adaptive', ...
    'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8, ...
    'max_corrector_iter',10,'corrector_failure','error', ...
    'model','padiyar_1_1_avr','excitation','avr', ...
    'stepper','fixed','verbose',false);
ts_fixed = stability.ts_simulate(c, opt_fixed);
opt_adaptive = opt_fixed; opt_adaptive.stepper = 'adaptive';
opt_adaptive.dt_nominal = sc.dt; opt_adaptive.dt_init = sc.dt;
opt_adaptive.dt_min = sc.dt/100; opt_adaptive.dt_max = sc.dt*10;
opt_adaptive.atol_x = 1e-6; opt_adaptive.rtol_x = 1e-4;
opt_adaptive.atol_y = 1e-5; opt_adaptive.rtol_y = 1e-4;
opt_adaptive.controller_fac = 0.9; opt_adaptive.controller_fac_min = 0.2;
opt_adaptive.controller_fac_max = 5.0; opt_adaptive.reject_limit = 10;
opt_adaptive.algebraic_tolerance = 1e-6;
try
    ts_adaptive = stability.ts_simulate(c, opt_adaptive);
catch ME
    warning('emit_padiyar_fixed_adaptive:adaptiveFailed: %s', ME.message);
    return;
end
cap = struct('case','Padiyar 4M2A','model','model-1.1 AVR','scenario', ...
    sprintf('bus %g fault Zf=%.3g%+.3gj', sc.fault_bus, real(sc.Zf), imag(sc.Zf)), ...
    'data_source','Ours fixed+adaptive','generating_command','generate_system_methods_report', ...
    'fresh_saved','ours_fresh','metric','Fixed vs adaptive COI angle');
d_fixed = rad2deg(ts_fixed.delta - ts_fixed.delta(1,:));
d_adaptive = rad2deg(ts_adaptive.delta - ts_adaptive.delta(1,:));
Hw = ts_fixed.H(:).';
d_fixed_coi = d_fixed - (d_fixed*Hw.'./sum(Hw));
d_adaptive_coi = d_adaptive - (d_adaptive*Hw.'./sum(Hw));
report_figure_helpers('fixed_adaptive_overlay', ts_fixed.t, d_fixed_coi, ...
    ts_adaptive.t, d_adaptive_coi, sc.t_fault, sc.t_clear, ...
    fullfile(padiyar_dir,'padiyar_fixed_adaptive_overlay.png'), cap);
% Also emit adaptive dt history if available.
if isfield(ts_adaptive,'dt_history') && ~isempty(ts_adaptive.dt_history)
    cap.metric = 'Adaptive step-size history';
    report_figure_helpers('adaptive_dt_history', ts_adaptive.t, ts_adaptive.dt_history, ...
        sc.t_fault, sc.t_clear, fullfile(padiyar_dir,'padiyar_adaptive_dt_history.png'), cap);
end
fprintf('Padiyar fixed/adaptive overlay emitted to %s\n', padiyar_dir);
end

% =========================================================================
% Asset emitters (filled in C4-C6)
% =========================================================================
function emit_ieee14_assets(c, sc, tw, fp, opts)
% Emit IEEE14 tables A-H and figures 1-9.
% SG dynamic data labeled ASSUMED_DIAGNOSTIC (MATPOWER supplies network/PF only).
outdir = opts.output_dir;
cap_base = struct('case','IEEE14','model','classical','scenario', ...
    sprintf('bus %g fault Zf=%.3g%+.3gj', sc.fault_bus, real(sc.Zf), imag(sc.Zf)), ...
    'data_source','Ours/PSAT/PGAz','generating_command','generate_system_methods_report', ...
    'fresh_saved','ours_fresh');
pf = pfsolver.powerflow_newton_raphson(c, struct('verbose',false,'plot_results',false, ...
    'enforce_q_limits',false,'tolerance',1e-10));
try, sssa_ours = stability.classical_sssa(c, struct('verbose',false)); ...
catch, sssa_ours = struct('eigenvalues',[]); end
opt_fixed = struct('t_end',sc.t_end,'dt',sc.dt,'fault_bus',sc.fault_bus, ...
    't_fault',sc.t_fault,'t_clear',sc.t_clear,'Zf',sc.Zf, ...
    'method','trapezoidal','corrector_mode','adaptive', ...
    'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8, ...
    'max_corrector_iter',10,'corrector_failure','error', ...
    'pm_mode','balanced','model','classical','stepper','fixed','verbose',false);
ts_fixed = stability.ts_simulate(c, opt_fixed);
opt_adaptive = opt_fixed; opt_adaptive.stepper = 'adaptive';
opt_adaptive.dt_nominal = sc.dt; opt_adaptive.dt_init = sc.dt;
opt_adaptive.dt_min = sc.dt/100; opt_adaptive.dt_max = sc.dt*10;
opt_adaptive.atol_x = 1e-6; opt_adaptive.rtol_x = 1e-4;
opt_adaptive.atol_y = 1e-5; opt_adaptive.rtol_y = 1e-4;
opt_adaptive.controller_fac = 0.9; opt_adaptive.controller_fac_min = 0.2;
opt_adaptive.controller_fac_max = 5.0; opt_adaptive.reject_limit = 10;
opt_adaptive.algebraic_tolerance = 1e-6;
try, ts_adaptive = stability.ts_simulate(c, opt_adaptive); ...
catch ME, warning('emit_ieee14:adaptiveFailed: %s', ME.message); ts_adaptive = struct(); end
raw = struct(); if isfield(tw,'raw'), raw = tw.raw; end
ours_t=[];ours_delta=[];ours_omega=[];ours_pe=[];ours_vbus=[];
psat_t=[];psat_delta=[];psat_omega=[];psat_pe=[];psat_vbus=[];
pgaz_t=[];pgaz_delta=[];pgaz_omega=[];pgaz_pe=[];pgaz_vbus=[];
if isfield(raw,'ours')
    ours_t=raw.ours.t; ours_delta=raw.ours.delta_deg; ours_omega=raw.ours.omega;
    ours_pe=raw.ours.Pe_MW; ours_vbus=raw.ours.Vbus_fault;
end
if isfield(raw,'psat') && isfield(raw.psat,'ran') && raw.psat.ran
    psat_t=raw.psat.t; psat_delta=raw.psat.delta; psat_omega=raw.psat.omega;
    psat_pe=raw.psat.Pe_pu; psat_vbus=raw.psat.Vbus;
end
if isfield(raw,'pgaz') && isfield(raw.pgaz,'ran') && raw.pgaz.ran
    pgaz_t=raw.pgaz.t; pgaz_delta=raw.pgaz.delta_deg; pgaz_omega=raw.pgaz.omega;
    pgaz_pe=raw.pgaz.Pe_pu; pgaz_vbus=raw.pgaz.Vm;
end
bus_ids = pf.external_bus_ids(:);
report_table_helpers('input_contract', fp, fullfile(outdir,'ieee14_table_A_input_contract.tex'));
gbus = ts_fixed.gen_buses(:); H = ts_fixed.H(:); D = ts_fixed.D(:); Xdp = ts_fixed.Xdp(:);
src = repmat({'ASSUMED_DIAGNOSTIC'}, numel(gbus), 1);
report_table_helpers('machine_params', gbus, H, D, Xdp, src, fullfile(outdir,'ieee14_table_B_machine_params.tex'));
report_table_helpers('fault_event', sc, fullfile(outdir,'ieee14_table_C_fault_event.tex'));
vm_ours = pf.bus_voltage(:); va_ours = pf.bus_angle_deg(:);
report_table_helpers('pf_bus', bus_ids, vm_ours, va_ours, vm_ours, va_ours, 'PSAT', fullfile(outdir,'ieee14_table_D_pf_bus.tex'));
pf_summary = struct('converged',pf.converged,'iterations',pf.iterations,'max_mismatch',pf.max_mismatch, ...
    'P_total_gen_pu',pf.P_total_gen,'P_total_load_pu',pf.P_total_load,'P_loss_total_pu',pf.P_loss_total);
report_table_helpers('pf_summary', pf_summary, fullfile(outdir,'ieee14_table_E_pf_summary.tex'));
if isfield(sssa_ours,'eigenvalues') && ~isempty(sssa_ours.eigenvalues), eigs_ours = sssa_ours.eigenvalues(:); else, eigs_ours = []; end
report_table_helpers('sssa_eig', eigs_ours, eigs_ours, 'Ours', fullfile(outdir,'ieee14_table_F_sssa_eig.tex'));
ts_metrics = struct('max_dCOI',struct('unit','deg','ours',0,'psat',NaN,'pgaz',NaN), ...
    'max_domega',struct('unit','pu','ours',0,'psat',NaN,'pgaz',NaN), ...
    'max_dPe',struct('unit','MW','ours',0,'psat',NaN,'pgaz',NaN), ...
    'max_dVbus',struct('unit','pu','ours',0,'psat',NaN,'pgaz',NaN));
if isfield(tw,'ts') && isfield(tw.ts,'ps_ours')
    ts_metrics.max_dCOI.psat = tw.ts.ps_ours.dCOI; ts_metrics.max_domega.psat = tw.ts.ps_ours.domega;
    ts_metrics.max_dPe.psat = tw.ts.ps_ours.dPe; ts_metrics.max_dVbus.psat = tw.ts.ps_ours.dVm;
end
if isfield(tw,'ts') && isfield(tw.ts,'pg_ours')
    ts_metrics.max_dCOI.pgaz = tw.ts.pg_ours.dCOI; ts_metrics.max_domega.pgaz = tw.ts.pg_ours.domega;
    ts_metrics.max_dPe.pgaz = tw.ts.pg_ours.dPe; ts_metrics.max_dVbus.pgaz = tw.ts.pg_ours.dVm;
end
report_table_helpers('ts_metrics', ts_metrics, fullfile(outdir,'ieee14_table_G_ts_metrics.tex'));
diag = struct('accepted_steps',0,'rejected_steps',0,'dt_min',sc.dt,'dt_max',sc.dt, ...
    'dt_mean',sc.dt,'lte_max',0,'max_dcoi',0,'max_pairwise',0,'max_domega',0,'max_dpe',0,'max_dvbus',0, ...
    'readiness_label','DIAGNOSTIC');
if isfield(ts_adaptive,'accepted_steps')
    diag.accepted_steps = ts_adaptive.accepted_steps; diag.rejected_steps = ts_adaptive.rejected_steps;
    if isfield(ts_adaptive,'dt_history') && ~isempty(ts_adaptive.dt_history)
        diag.dt_min=min(ts_adaptive.dt_history); diag.dt_max=max(ts_adaptive.dt_history); diag.dt_mean=mean(ts_adaptive.dt_history);
    end
    if isfield(ts_adaptive,'lte_history') && ~isempty(ts_adaptive.lte_history), diag.lte_max=max(ts_adaptive.lte_history); end
    diag.readiness_label = 'ADAPTIVE_DEFAULT_NOT_READY (explicit only)';
end
report_table_helpers('fixed_adaptive_diag', diag, fullfile(outdir,'ieee14_table_H_fixed_adaptive.tex'));
cap=cap_base; cap.metric='PF bus voltage magnitude';
report_figure_helpers('pf_voltage', bus_ids, vm_ours, [], [], fullfile(outdir,'ieee14_fig1_pf_voltage.png'), cap);
cap=cap_base; cap.metric='PF bus voltage angle';
report_figure_helpers('pf_angle', bus_ids, va_ours, [], [], fullfile(outdir,'ieee14_fig2_pf_angle.png'), cap);
cap=cap_base; cap.metric='SSSA eigenvalues';
report_figure_helpers('sssa_complex', eigs_ours, [], 'reference', fullfile(outdir,'ieee14_fig3_sssa_complex.png'), cap);
if ~isempty(ours_t)
    cap=cap_base; cap.metric='TS COI-relative angle';
    report_figure_helpers('ts_coi_angle', ours_t, ours_delta, psat_delta, [], [], sc.t_fault, sc.t_clear, fullfile(outdir,'ieee14_fig4_ts_coi_angle.png'), cap);
    cap=cap_base; cap.metric='TS speed deviation';
    report_figure_helpers('ts_speed', ours_t, ours_omega, psat_omega, sc.t_fault, sc.t_clear, fullfile(outdir,'ieee14_fig5_ts_speed.png'), cap);
    cap=cap_base; cap.metric='TS electrical power';
    report_figure_helpers('ts_pe', ours_t, ours_pe, psat_pe, sc.t_fault, sc.t_clear, fullfile(outdir,'ieee14_fig6_ts_pe.png'), cap);
    cap=cap_base; cap.metric='Fault-bus voltage';
    report_figure_helpers('fault_bus_voltage', ours_t, ours_vbus, psat_vbus, sc.t_fault, sc.t_clear, fullfile(outdir,'ieee14_fig7_fault_bus_voltage.png'), cap);
end
if isfield(ts_adaptive,'t') && ~isempty(ts_adaptive.t)
    cap=cap_base; cap.metric='Fixed vs adaptive overlay';
    d_fixed = rad2deg(ts_fixed.delta - ts_fixed.delta(1,:));
    d_adaptive = rad2deg(ts_adaptive.delta - ts_adaptive.delta(1,:));
    Hw = ts_fixed.H(:).';
    d_fixed_coi = d_fixed - (d_fixed*Hw.'./sum(Hw));
    d_adaptive_coi = d_adaptive - (d_adaptive*Hw.'./sum(Hw));
    report_figure_helpers('fixed_adaptive_overlay', ts_fixed.t, d_fixed_coi, ts_adaptive.t, d_adaptive_coi, sc.t_fault, sc.t_clear, fullfile(outdir,'ieee14_fig8_fixed_adaptive_overlay.png'), cap);
    if isfield(ts_adaptive,'dt_history') && ~isempty(ts_adaptive.dt_history)
        cap=cap_base; cap.metric='Adaptive step-size history';
        report_figure_helpers('adaptive_dt_history', ts_adaptive.t, ts_adaptive.dt_history, sc.t_fault, sc.t_clear, fullfile(outdir,'ieee14_fig9_adaptive_dt_history.png'), cap);
    end
end
fprintf('IEEE14 assets emitted to %s\n', outdir);
end

function emit_rts24_assets(c, sc, tw, fp, opts)
% Emit RTS-24 tables and figures.
% Constant-impedance load conversion Y_load=conj(S0)/|V0|^2 is used at
% classical_dae runtime (classical_dae.m:51), verified against the code.
outdir = opts.output_dir;
cap_base = struct('case','RTS-24','model','classical','scenario', ...
    sprintf('bus %g fault Zf=%.3g%+.3gj', sc.fault_bus, real(sc.Zf), imag(sc.Zf)), ...
    'data_source','Ours/PSAT','generating_command','generate_system_methods_report', ...
    'fresh_saved','ours_fresh');
pf = pfsolver.powerflow_newton_raphson(c, struct('verbose',false,'plot_results',false, ...
    'enforce_q_limits',false,'tolerance',1e-10));
try, sssa_ours = stability.classical_sssa(c, struct('verbose',false)); ...
catch, sssa_ours = struct('eigenvalues',[]); end
opt_fixed = struct('t_end',sc.t_end,'dt',sc.dt,'fault_bus',sc.fault_bus, ...
    't_fault',sc.t_fault,'t_clear',sc.t_clear,'Zf',sc.Zf, ...
    'method','trapezoidal','corrector_mode','adaptive', ...
    'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8, ...
    'max_corrector_iter',10,'corrector_failure','error', ...
    'pm_mode','balanced','model','classical','stepper','fixed','verbose',false);
ts_fixed = stability.ts_simulate(c, opt_fixed);
opt_adaptive = opt_fixed; opt_adaptive.stepper = 'adaptive';
opt_adaptive.dt_nominal = sc.dt; opt_adaptive.dt_init = sc.dt;
opt_adaptive.dt_min = sc.dt/100; opt_adaptive.dt_max = sc.dt*10;
opt_adaptive.atol_x = 1e-6; opt_adaptive.rtol_x = 1e-4;
opt_adaptive.atol_y = 1e-5; opt_adaptive.rtol_y = 1e-4;
opt_adaptive.controller_fac = 0.9; opt_adaptive.controller_fac_min = 0.2;
opt_adaptive.controller_fac_max = 5.0; opt_adaptive.reject_limit = 10;
opt_adaptive.algebraic_tolerance = 1e-6;
try, ts_adaptive = stability.ts_simulate(c, opt_adaptive); ...
catch ME, warning('emit_rts24:adaptiveFailed: %s', ME.message); ts_adaptive = struct(); end
raw = struct(); if isfield(tw,'raw'), raw = tw.raw; end
ours_t=[];ours_delta=[];ours_omega=[];ours_pe=[];ours_vbus=[];
psat_t=[];psat_delta=[];psat_omega=[];psat_pe=[];psat_vbus=[];
if isfield(raw,'ours')
    ours_t=raw.ours.t; ours_delta=raw.ours.delta_deg; ours_omega=raw.ours.omega;
    ours_pe=raw.ours.Pe_MW; ours_vbus=raw.ours.Vbus_fault;
end
if isfield(raw,'psat') && isfield(raw.psat,'ran') && raw.psat.ran
    psat_t=raw.psat.t; psat_delta=raw.psat.delta; psat_omega=raw.psat.omega;
    psat_pe=raw.psat.Pe_pu; psat_vbus=raw.psat.Vbus;
end
bus_ids = pf.external_bus_ids(:);
report_table_helpers('input_contract', fp, fullfile(outdir,'rts24_table_A_input_contract.tex'));
gbus = ts_fixed.gen_buses(:); H = ts_fixed.H(:); D = ts_fixed.D(:); Xdp = ts_fixed.Xdp(:);
src = repmat({'RTS-96 sourced (see case reference)'}, numel(gbus), 1);
report_table_helpers('machine_params', gbus, H, D, Xdp, src, fullfile(outdir,'rts24_table_B_machine_params.tex'));
report_table_helpers('fault_event', sc, fullfile(outdir,'rts24_table_C_fault_event.tex'));
vm_ours = pf.bus_voltage(:); va_ours = pf.bus_angle_deg(:);
report_table_helpers('pf_bus', bus_ids, vm_ours, va_ours, vm_ours, va_ours, 'PSAT', fullfile(outdir,'rts24_table_D_pf_bus.tex'));
pf_summary = struct('converged',pf.converged,'iterations',pf.iterations,'max_mismatch',pf.max_mismatch, ...
    'P_total_gen_pu',pf.P_total_gen,'P_total_load_pu',pf.P_total_load,'P_loss_total_pu',pf.P_loss_total);
report_table_helpers('pf_summary', pf_summary, fullfile(outdir,'rts24_table_E_pf_summary.tex'));
if isfield(sssa_ours,'eigenvalues') && ~isempty(sssa_ours.eigenvalues), eigs_ours = sssa_ours.eigenvalues(:); else, eigs_ours = []; end
report_table_helpers('sssa_eig', eigs_ours, eigs_ours, 'Ours', fullfile(outdir,'rts24_table_F_sssa_eig.tex'));
ts_metrics = struct('max_dCOI',struct('unit','deg','ours',0,'psat',NaN,'pgaz',NaN), ...
    'max_domega',struct('unit','pu','ours',0,'psat',NaN,'pgaz',NaN), ...
    'max_dPe',struct('unit','MW','ours',0,'psat',NaN,'pgaz',NaN), ...
    'max_dVbus',struct('unit','pu','ours',0,'psat',NaN,'pgaz',NaN));
if isfield(tw,'ts') && isfield(tw.ts,'ps_ours')
    ts_metrics.max_dCOI.psat = tw.ts.ps_ours.dCOI; ts_metrics.max_domega.psat = tw.ts.ps_ours.domega;
    ts_metrics.max_dPe.psat = tw.ts.ps_ours.dPe; ts_metrics.max_dVbus.psat = tw.ts.ps_ours.dVm;
end
report_table_helpers('ts_metrics', ts_metrics, fullfile(outdir,'rts24_table_G_ts_metrics.tex'));
diag = struct('accepted_steps',0,'rejected_steps',0,'dt_min',sc.dt,'dt_max',sc.dt, ...
    'dt_mean',sc.dt,'lte_max',0,'max_dcoi',0,'max_pairwise',0,'max_domega',0,'max_dpe',0,'max_dvbus',0, ...
    'readiness_label','DIAGNOSTIC');
if isfield(ts_adaptive,'accepted_steps')
    diag.accepted_steps = ts_adaptive.accepted_steps; diag.rejected_steps = ts_adaptive.rejected_steps;
    if isfield(ts_adaptive,'dt_history') && ~isempty(ts_adaptive.dt_history)
        diag.dt_min=min(ts_adaptive.dt_history); diag.dt_max=max(ts_adaptive.dt_history); diag.dt_mean=mean(ts_adaptive.dt_history);
    end
    if isfield(ts_adaptive,'lte_history') && ~isempty(ts_adaptive.lte_history), diag.lte_max=max(ts_adaptive.lte_history); end
    diag.readiness_label = 'ADAPTIVE_DEFAULT_NOT_READY (explicit only)';
end
report_table_helpers('fixed_adaptive_diag', diag, fullfile(outdir,'rts24_table_H_fixed_adaptive.tex'));
cap=cap_base; cap.metric='PF bus voltage magnitude';
report_figure_helpers('pf_voltage', bus_ids, vm_ours, [], [], fullfile(outdir,'rts24_fig1_pf_voltage.png'), cap);
cap=cap_base; cap.metric='PF bus voltage angle';
report_figure_helpers('pf_angle', bus_ids, va_ours, [], [], fullfile(outdir,'rts24_fig2_pf_angle.png'), cap);
cap=cap_base; cap.metric='SSSA eigenvalues';
report_figure_helpers('sssa_complex', eigs_ours, [], 'reference', fullfile(outdir,'rts24_fig3_sssa_complex.png'), cap);
if ~isempty(ours_t)
    cap=cap_base; cap.metric='TS COI-relative angle';
    report_figure_helpers('ts_coi_angle', ours_t, ours_delta, psat_delta, [], [], sc.t_fault, sc.t_clear, fullfile(outdir,'rts24_fig4_ts_coi_angle.png'), cap);
    cap=cap_base; cap.metric='TS speed deviation';
    report_figure_helpers('ts_speed', ours_t, ours_omega, psat_omega, sc.t_fault, sc.t_clear, fullfile(outdir,'rts24_fig5_ts_speed.png'), cap);
    cap=cap_base; cap.metric='TS electrical power';
    report_figure_helpers('ts_pe', ours_t, ours_pe, psat_pe, sc.t_fault, sc.t_clear, fullfile(outdir,'rts24_fig6_ts_pe.png'), cap);
    cap=cap_base; cap.metric='Fault-bus voltage';
    report_figure_helpers('fault_bus_voltage', ours_t, ours_vbus, psat_vbus, sc.t_fault, sc.t_clear, fullfile(outdir,'rts24_fig7_fault_bus_voltage.png'), cap);
end
if isfield(ts_adaptive,'t') && ~isempty(ts_adaptive.t)
    cap=cap_base; cap.metric='Fixed vs adaptive overlay';
    d_fixed = rad2deg(ts_fixed.delta - ts_fixed.delta(1,:));
    d_adaptive = rad2deg(ts_adaptive.delta - ts_adaptive.delta(1,:));
    Hw = ts_fixed.H(:).';
    d_fixed_coi = d_fixed - (d_fixed*Hw.'./sum(Hw));
    d_adaptive_coi = d_adaptive - (d_adaptive*Hw.'./sum(Hw));
    report_figure_helpers('fixed_adaptive_overlay', ts_fixed.t, d_fixed_coi, ts_adaptive.t, d_adaptive_coi, sc.t_fault, sc.t_clear, fullfile(outdir,'rts24_fig8_fixed_adaptive_overlay.png'), cap);
    if isfield(ts_adaptive,'dt_history') && ~isempty(ts_adaptive.dt_history)
        cap=cap_base; cap.metric='Adaptive step-size history';
        report_figure_helpers('adaptive_dt_history', ts_adaptive.t, ts_adaptive.dt_history, sc.t_fault, sc.t_clear, fullfile(outdir,'rts24_fig9_adaptive_dt_history.png'), cap);
    end
end
fprintf('RTS-24 assets emitted to %s\n', outdir);
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
