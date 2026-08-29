function out = generate_final_report_figures_th(opts)
%GENERATE_FINAL_REPORT_FIGURES_TH  Thai-report figures for the final project report.
%
%   out = generate_final_report_figures_th()
%
% Generates the three MATLAB data figures of
% docs/source/report_power_system_project_final_th.tex from the pinned
% six-arm cache set of the IEEE-14 1-SG + 4-IBR switching study:
%
%   figures/final_report_th/fig_electrical.png   (2x2: P, Q, f_COI, min|V|)
%   figures/final_report_th/fig_supervisor.png   (3x1: severity S, modes, ref owner)
%   figures/final_report_th/fig_policy.png       (f_COI, arms that reach 250 s)
%
% INPUT ARTIFACT (single source of truth for this report):
%   output/diagnostics/ieee14_gfm_lock_compare_zeta/<arm>_250s.mat
%   committed snapshot c56ff9f (2026-08-28), produced by
%   run_ieee14_gfm_lock_comparison at dt=0.05, adaptive stepper.
%   Every printed number of the report comes from the macros committed in
%   that snapshot (docs/source/figures/switch_ieee14_decision/*.tex); this
%   script parses those macros, reads the same cache to draw, and asserts the
%   cache and summary.mat still match them so the figures can never drift from
%   the tables.
%
% CONTRACT
%   - Pure cache reader: no simulation, no write-back to any cache, no
%     extension/interpolation/padding/decimation of any arm's samples.
%     Classification: ASSUMED_DIAGNOSTIC presentation over production runs.
%   - Font: every text-bearing object (axes, labels, ticks, legends,
%     annotations) must be 'TH SarabunPSK' at exactly 12 pt, matching the
%     report body (AGENTS.md lettering contract; the 11 pt dense-tile
%     allowance is NOT used). Audited by walking findall(f) before export.
%   - Fail-closed: any assert error aborts before writing.
%   - No noise, smoothing, filtering, clipping, offset or resampling is
%     applied to any plotted value; only visual styling (colour, line width,
%     grid, event markers, shaded windows) is presentation.
%
% Regenerate with:
%   pf_init_paths; generate_final_report_figures_th()
%
% Reviewed under plan jolly-beaming-wilkinson.md (v2).

arguments
    opts.cache_dir (1,1) string = "output/diagnostics/ieee14_gfm_lock_compare_zeta"
    opts.out_dir (1,1) string = "docs/source/figures/final_report_th"
    opts.dpi (1,1) double {mustBePositive} = 300
    opts.width_in (1,1) double {mustBePositive} = 7.10
    opts.font_size (1,1) double {mustBePositive} = 16
    opts.font_name (1,1) string = "TH SarabunPSK"
    opts.height_electrical (1,1) double {mustBePositive} = 3.90
    opts.height_supervisor (1,1) double {mustBePositive} = 4.20
    opts.height_policy (1,1) double {mustBePositive} = 2.55
end

% ---------------------------------------------------------------------------
% Level-1 font gate: the font MUST be visible to MATLAB, else abort.
% pf_page_figure only warns; the report contract requires fail-closed here.
% ---------------------------------------------------------------------------
if ~any(strcmp(listfonts,char(opts.font_name)))
    error('generate_final_report_figures_th:fontMissing', ...
        ['Font "%s" is not visible to MATLAB (listfonts). Install it ' ...
         'system-wide before generating report figures; a substituted ' ...
         'font would violate the lettering contract.'],char(opts.font_name));
end

cache_dir = char(opts.cache_dir);
out_dir = char(opts.out_dir);
if ~isfolder(out_dir), mkdir(out_dir); end

% The report consumes two generated macro files and one generated summary.
% Parse the macros instead of duplicating their values here.  Hash guards on
% every source and cache make a concurrent writer fail closed rather than
% silently mixing generations.
macro_dir = fullfile('docs','source','figures','switch_ieee14_decision');
comparison_file = fullfile(macro_dir,'comparison_macros.tex');
run_file = fullfile(macro_dir,'run_summary_v2.tex');
summary_file = fullfile(cache_dir,'summary.mat');
assert(isfile(comparison_file),'generate_final_report_figures_th:missingMacros', ...
    'Comparison macro file not found: %s',comparison_file);
assert(isfile(run_file),'generate_final_report_figures_th:missingMacros', ...
    'Run-summary macro file not found: %s',run_file);
assert(isfile(summary_file),'generate_final_report_figures_th:missingSummary', ...
    'Comparison summary file not found: %s',summary_file);
[comparison, comparison_hash] = read_macro_file(comparison_file);
[run_summary, run_hash] = read_macro_file(run_file);
[summary, summary_hash] = read_summary_file(summary_file);
assert(strcmp(comparison_hash,sha256_of(comparison_file)), ...
    'generate_final_report_figures_th:comparisonMacroChanged', ...
    'Comparison macros changed during the read.');
assert(strcmp(run_hash,sha256_of(run_file)), ...
    'generate_final_report_figures_th:runMacroChanged', ...
    'Run-summary macros changed during the read.');
assert(strcmp(summary_hash,sha256_of(summary_file)), ...
    'generate_final_report_figures_th:summaryChanged', ...
    'summary.mat changed during the read.');

% Expected values are read from the generated macros committed in c56ff9f.
% SOURCE: docs/source/figures/switch_ieee14_decision/comparison_macros.tex
%         and run_summary_v2.tex at commit c56ff9f (2026-08-28).
arms = {'adaptive','pinned_gfm1','pinned_gfm2','pinned_gfm4','locked_gfl','no_adaptation'};
macro_prefix = {'ArmAdaptive','ArmPinnedgfmOne','ArmPinnedgfmTwo', ...
    'ArmPinnedgfmFour','ArmLockedgfl','ArmNoadaptation'};
exp_samples = zeros(1,numel(arms));
exp_horizon = zeros(1,numel(arms));
exp_converged = false(1,numel(arms));
exp_reclose = NaN(1,numel(arms));
exp_failure = cell(1,numel(arms));
for k = 1:numel(arms)
    p = macro_prefix{k};
    exp_samples(k) = macro_num(comparison,[p 'Samples']);
    exp_horizon(k) = macro_num(comparison,[p 'Horizon']);
    exp_converged(k) = logical(macro_num(comparison,[p 'Converged']));
    exp_reclose(k) = macro_num(comparison,[p 'Reclose']);
    exp_failure{k} = macro_text(comparison,[p 'Failure']);
end

% CASE_DEFINED event schedule comes from the loaded adaptive result below;
% these are checked against the published case schedule before any figure is
% drawn. Reclose and mode-return times are PROJECT_RESULT macro values.
t_reclose = macro_num(comparison,'ArmAdaptiveReclose');
t_modeend = macro_num(run_summary,'NewRunModeReselectionTime');

% Load all six arms with hash-stability guards (no reading mid-write).
R = struct();
prov = cell(0,4);  % arm, file, sha256, mtime
for k = 1:numel(arms)
    f = fullfile(cache_dir,[arms{k} '_250s.mat']);
    assert(isfile(f),'generate_final_report_figures_th:missingCache', ...
        'Arm cache not found: %s',f);
    sha_before = sha256_of(f);
    S = load(f);
    r = S.result;
    sha_after = sha256_of(f);
    assert(strcmp(sha_before,sha_after), ...
        'generate_final_report_figures_th:cacheChangedWhileReading', ...
        'Cache %s changed during the read; a concurrent writer is active.',f);
    % Outcome-level agreement with the committed macros and summary snapshot.
    assert(numel(r.t)==exp_samples(k), ...
        'generate_final_report_figures_th:samplesMismatch', ...
        'Arm %s has %d samples; committed macro says %d. Snapshot mismatch.', ...
        arms{k},numel(r.t),exp_samples(k));
    assert(abs(r.t(end)-exp_horizon(k))<5e-4, ...
        'generate_final_report_figures_th:horizonMismatch', ...
        'Arm %s ends at %.6f s; committed macro says %.3f s.', ...
        arms{k},r.t(end),exp_horizon(k));
    if ~isnan(exp_reclose(k))
        rec = r.actual_reclose_time;
        assert(~isempty(rec) && abs(rec-exp_reclose(k))<5e-4, ...
            'generate_final_report_figures_th:recloseMismatch', ...
            'Arm %s reclose %.6f vs committed macro %.4f.',arms{k},rec,exp_reclose(k));
    end
    assert(logical(r.converged)==exp_converged(k), ...
        'generate_final_report_figures_th:convergenceMismatch', ...
        'Arm %s convergence differs from committed macro.',arms{k});
    if isempty(exp_failure{k}) || strcmp(exp_failure{k},'--')
        assert(isempty(r.failure_id) || strcmpi(char(string(r.failure_id)),'') || ...
            (logical(r.converged) && k==1), ...
            'generate_final_report_figures_th:failureMismatch', ...
            'Arm %s has failure_id %s but committed macro is --.',arms{k},char(string(r.failure_id)));
    else
        assert(contains(char(string(r.failure_id)),exp_failure{k}), ...
            'generate_final_report_figures_th:failureMismatch', ...
            'Arm %s failure %s does not contain committed %s.', ...
            arms{k},char(string(r.failure_id)),exp_failure{k});
    end
    sm = find_summary_arm(summary,arms{k});
    assert(sm.n_accepted_samples==exp_samples(k) && abs(sm.t_end_s-exp_horizon(k))<5e-4 && ...
        logical(sm.converged)==exp_converged(k), ...
        'generate_final_report_figures_th:summaryArmMismatch', ...
        'summary.mat arm %s disagrees with comparison macros.',arms{k});
    if isfinite(exp_reclose(k))
        assert(isfinite(sm.actual_reclose_time) && abs(sm.actual_reclose_time-exp_reclose(k))<5e-4, ...
            'generate_final_report_figures_th:summaryRecloseMismatch', ...
            'summary.mat arm %s reclose disagrees with comparison macros.',arms{k});
    end
    assert(strcmpi(char(string(sm.failure_id)),char(string(r.failure_id))), ...
        'generate_final_report_figures_th:summaryFailureMismatch', ...
        'summary.mat arm %s failure_id differs from its cache.',arms{k});
    R.(arms{k}) = r;
    d = dir(f);
    prov(end+1,:) = {arms{k},f,sha_before,datestr_web(d(1).datenum)}; %#ok<AGROW>
end
% Derive the CASE_DEFINED event marks from the adaptive schedule and verify the
% frozen scenario values.  No event time is invented by the figure generator.
sched = R.adaptive.sched;
required_sched = {'sg_trip','load_step','fault_on','line_trip','restore_time'};
for k = 1:numel(required_sched)
    assert(isfield(sched,required_sched{k}) && isscalar(sched.(required_sched{k})) && ...
        isfinite(sched.(required_sched{k})), ...
        'generate_final_report_figures_th:missingSchedule', ...
        'Adaptive schedule lacks scalar %s.',required_sched{k});
end
t_events = [sched.sg_trip sched.load_step sched.fault_on sched.line_trip sched.restore_time];
assert(max(abs(t_events-[20 50 85 110 145]))<1e-10, ...
    'generate_final_report_figures_th:scheduleMismatch', ...
    'CASE_DEFINED event schedule differs from [20 50 85 110 145] s.');
% Adaptive terminal frequency (\NewRunTerminalF), plus the remaining scalar
% and event certificates emitted by generate_ieee14_report_scalars.
assert(abs(R.adaptive.coi_frequency_Hz(end)-macro_num(run_summary,'NewRunTerminalF'))<1e-5, ...
    'generate_final_report_figures_th:terminalFMismatch', ...
    'Adaptive terminal f %.9f vs committed macro.',R.adaptive.coi_frequency_Hz(end));
assert(abs(R.adaptive.t(end)-macro_num(run_summary,'NewRunEnd'))<5e-4 && ...
    numel(R.adaptive.t)==macro_num(run_summary,'NewRunSamples'), ...
    'generate_final_report_figures_th:runSummaryMismatch', ...
    'Adaptive horizon/sample count disagrees with run-summary macros.');
assert(logical(R.adaptive.converged)==true && ...
    strcmpi(char(string(R.adaptive.reclose_status)),macro_text(run_summary,'NewRunRecloseStatus')), ...
    'generate_final_report_figures_th:runOutcomeMismatch', ...
    'Adaptive convergence/reclose status disagrees with run-summary macros.');
assert(R.adaptive.subdivision_depth==macro_num(run_summary,'NewRunSubdivision'), ...
    'generate_final_report_figures_th:subdivisionMismatch', ...
    'Adaptive subdivision depth disagrees with run-summary macro.');
assert(R.adaptive.rejected_steps==macro_num(run_summary,'NewRunRejectedSteps'), ...
    'generate_final_report_figures_th:rejectedMismatch', ...
    'Adaptive rejected-step count disagrees with run-summary macro.');
acc = R.adaptive.accepted_residual_per_step;
acc = acc(isfinite(acc));
assert(abs(max(acc)-macro_num(run_summary,'NewRunResidual'))<5e-13, ...
    'generate_final_report_figures_th:residualMismatch', ...
    'Adaptive accepted residual disagrees with run-summary macro.');
guard = R.adaptive.last_synchronism_guard;
assert(isstruct(guard) && isscalar(guard), ...
    'generate_final_report_figures_th:syncGuardMissing', ...
    'Adaptive synchronism guard is not a scalar struct.');
sync_fields = {'dV','df','dtheta'};
sync_macros = {'NewRunSyncDV','NewRunSyncDF','NewRunSyncDTheta'};
for k = 1:numel(sync_fields)
    field = sync_fields{k}; name = sync_macros{k};
    assert(isfield(guard,field) && isscalar(guard.(field)) && ...
        abs(guard.(field)-macro_num(run_summary,name)) < 1e-6, ...
        'generate_final_report_figures_th:syncMismatch', ...
        'Adaptive synchronism field %s disagrees with run-summary macro.',field);
end
rel = applied_times(R.adaptive,'gfm_support_release');
aug = applied_times(R.adaptive,'gfm_support_augment');
resel = applied_times(R.adaptive,'sg_reselection');
assert(numel(rel)==macro_num(run_summary,'NewRunNRelease') && ...
    numel(aug)==macro_num(run_summary,'NewRunNAugment') && ...
    numel(resel)==macro_num(run_summary,'NewRunNReselection'), ...
    'generate_final_report_figures_th:eventCountMismatch', ...
    'Augment/release/reselection counts disagree with run-summary macros.');
assert_times(rel,run_summary,'NewRunRelease', 'release');
assert_times(aug,run_summary,'NewRunAugment', 'augment');
assert_times(resel,run_summary,'NewRunReselection','reselection');
assert(abs(R.adaptive.actual_mode_reselection_time-macro_num(run_summary,'NewRunModeReselectionTime'))<5e-4 && ...
    abs(R.adaptive.handback_duration_s-macro_num(run_summary,'NewRunHandback'))<5e-4, ...
    'generate_final_report_figures_th:handbackMismatch', ...
    'Adaptive post-reclose handback values disagree with run-summary macros.');
assert(gfm_max(R.adaptive)==macro_num(run_summary,'NewRunGfmMax'), ...
    'generate_final_report_figures_th:gfmMaxMismatch', ...
    'Adaptive maximum GFM count disagrees with run-summary macro.');
% Resource order is a numerical contract, not a display convention.  The
% four IBR resource indices [1 2 3 4] must map to external buses [2 3 6 8]
% in every arm; a reordered device list would invalidate every per-converter
% curve and policy comparison.
for k = 1:numel(arms)
    ibr_k = findconverterrows(R.(arms{k}));
    assert(isequal(R.(arms{k}).device_bus_ids(ibr_k),[2 3 6 8]), ...
        'generate_final_report_figures_th:ibrMappingMismatch', ...
        'Arm %s does not map IBR resource order [1 2 3 4] to buses [2 3 6 8].',arms{k});
end

% ---------------------------------------------------------------------------
% Shared drawing helpers (visual styling only; data are raw accepted samples).
% ---------------------------------------------------------------------------
FC = [0.00 0.30 0.70;   % converter blue    (bus 2)
      0.85 0.45 0.05;   % converter orange  (bus 3)
      0.00 0.55 0.35;   % converter green   (bus 6)
      0.60 0.15 0.55];  % converter violet  (bus 8)
ev_col = [0.55 0.55 0.55];

out = struct();
out.electrical = draw_electrical(R.adaptive,opts,FC,ev_col,t_events,t_reclose,t_modeend,out_dir);
out.supervisor = draw_supervisor(R.adaptive,opts,FC,ev_col,t_events,t_reclose,t_modeend,out_dir);
out.policy     = draw_policy(R,opts,ev_col,t_events,out_dir);

% ---------------------------------------------------------------------------
% Provenance record.
% ---------------------------------------------------------------------------
fid = fopen(fullfile(out_dir,'provenance.txt'),'w');
fprintf(fid,'Generated by generate_final_report_figures_th.m\n');
fprintf(fid,'Date: %s\n',datestr_web(datetime('now')));
fprintf(fid,'Report source commit: c56ff9f (2026-08-28) - six-arm snapshot\n');
fprintf(fid,'Cache directory: %s\n',cache_dir);
fprintf(fid,'Comparison macros sha256: %s\n',comparison_hash);
fprintf(fid,'Run-summary macros sha256: %s\n',run_hash);
fprintf(fid,'summary.mat sha256: %s\n',summary_hash);
fprintf(fid,'Event times (CASE_DEFINED, s): %s\n',mat2str(t_events));
fprintf(fid,'Reclose (PROJECT_RESULT, s): %.4f ; mode return: %.4f\n',t_reclose,t_modeend);
fprintf(fid,'Fonts: %s at %g pt on every text object (audited before export)\n', ...
    char(opts.font_name),opts.font_size);
fprintf(fid,'No smoothing, filtering, clipping, offset, padding or resampling applied.\n\n');
for k = 1:size(prov,1)
    fprintf(fid,'%-14s %s\n  sha256 %s\n  mtime  %s\n',prov{k,:});
end
fclose(fid);
fprintf('wrote %s\n',fullfile(out_dir,'provenance.txt'));
out.provenance = fullfile(out_dir,'provenance.txt');
end

% ===========================================================================
function png = draw_electrical(r,opts,FC,ev_col,t_events,t_reclose,t_modeend,out_dir)
%DRAW_ELECTRICAL  2x2: per-device P, Q; system f_COI; network min|V|.
w = opts.width_in; h = opts.height_electrical;
f = pf_page_figure(w,h,opts.font_size,opts.font_name);
tl = tiledlayout(f,2,2,'TileSpacing','compact','Padding','compact');

t = r.t(:);
ibr = findconverterrows(r);
nd = numel(ibr);
sg = setdiff(1:size(r.device_P_pu,1),ibr);
bus = r.device_bus_ids(ibr(:));

ax = nexttile(tl); % (a) active power
hold(ax,'on');
for k = 1:nd
    plot(ax,t,r.device_P_pu(ibr(k),:),'Color',FC(k,:),'LineWidth',1.1);
end
if ~isempty(sg)
    plot(ax,t,r.device_P_pu(sg(1),:),'k--','LineWidth',1.1);
end
mark_events(ax,ev_col,t_events,t_reclose,t_modeend,opts);
ylabel(ax,'$P$ [pu]','Interpreter','latex');
title(ax,'(a) Device active power','FontWeight','normal','FontSize',opts.font_size);
set(ax,'XTickLabel',[],'xlim',[0 250],'box','on');
grid(ax,'on');
lg = legend(ax,[arrayfun(@(b) sprintf('Bus %d',b),bus,'UniformOutput',false),{'SG'}], ...
    'Orientation','horizontal','Box','off');
lg.Layout.Tile = 'north';

ax = nexttile(tl); % (b) reactive power
hold(ax,'on');
for k = 1:nd
    plot(ax,t,r.device_Q_pu(ibr(k),:),'Color',FC(k,:),'LineWidth',1.1);
end
if ~isempty(sg)
    plot(ax,t,r.device_Q_pu(sg(1),:),'k--','LineWidth',1.1);
end
mark_events(ax,ev_col,t_events,t_reclose,t_modeend,opts);
ylabel(ax,'$Q$ [pu]','Interpreter','latex');
title(ax,'(b) Device reactive power','FontWeight','normal','FontSize',opts.font_size);
set(ax,'XTickLabel',[],'xlim',[0 250],'box','on');
grid(ax,'on');

ax = nexttile(tl); % (c) COI frequency
plot(ax,t,r.coi_frequency_Hz(:),'Color',[0.00 0.24 0.75],'LineWidth',1.1);
mark_events(ax,ev_col,t_events,t_reclose,t_modeend,opts);
yline(ax,60,':','Color',[0.45 0.45 0.45],'LineWidth',0.8,'HandleVisibility','off', ...
    'FontName',char(opts.font_name),'FontSize',opts.font_size);
ylabel(ax,'$f_{\mathrm{COI}}$ [Hz]','Interpreter','latex');
xlabel(ax,'$t$ [s]','Interpreter','latex');
title(ax,'(c) System COI frequency','FontWeight','normal','FontSize',opts.font_size);
set(ax,'xlim',[0 250],'box','on');
grid(ax,'on');

ax = nexttile(tl); % (d) network minimum voltage
plot(ax,t,min(r.bus_voltage_magnitude,[],1),'Color',[0.18 0.55 0.34],'LineWidth',1.1);
mark_events(ax,ev_col,t_events,t_reclose,t_modeend,opts);
ylabel(ax,'$\min|V|$ [pu]','Interpreter','latex');
xlabel(ax,'$t$ [s]','Interpreter','latex');
title(ax,'(d) Network minimum voltage','FontWeight','normal','FontSize',opts.font_size);
set(ax,'xlim',[0 250],'box','on');
grid(ax,'on');

audit_fonts(f,opts);
png = fullfile(out_dir,'fig_electrical.png');
pf_page_export(f,png,opts.dpi);
end

% ===========================================================================
function png = draw_supervisor(r,opts,FC,ev_col,t_events,t_reclose,t_modeend,out_dir)
%DRAW_SUPERVISOR  3x1: severity index, committed modes, reference owner.
w = opts.width_in; h = opts.height_supervisor;
f = pf_page_figure(w,h,opts.font_size,opts.font_name);
tl = tiledlayout(f,3,1,'TileSpacing','compact','Padding','compact');

t = r.t(:);
ibr = findconverterrows(r);
nd = numel(ibr);
sev = severity_index(r);           % [n x nd]
bus = r.device_bus_ids(ibr(:));

ax = nexttile(tl); % (a) severity
hold(ax,'on');
for k = 1:nd
    plot(ax,t,sev(:,k),'Color',FC(k,:),'LineWidth',1.0);
end
mark_events(ax,ev_col,t_events,t_reclose,t_modeend,opts);
yline(ax,0.65,'-','Color',[0.75 0.10 0.10],'LineWidth',0.8,'HandleVisibility','off', ...
    'FontName',char(opts.font_name),'FontSize',opts.font_size);
yline(ax,0.35,'-','Color',[0.10 0.35 0.75],'LineWidth',0.8,'HandleVisibility','off', ...
    'FontName',char(opts.font_name),'FontSize',opts.font_size);
text(ax,247,0.70,'$\Gamma_{on}=0.65$','Color',[0.75 0.10 0.10], ...
    'HorizontalAlignment','right','Interpreter','latex');
text(ax,247,0.30,'$\Gamma_{off}=0.35$','Color',[0.10 0.35 0.75], ...
    'HorizontalAlignment','right','Interpreter','latex');
ylim(ax,[0 1.12]); set(ax,'YTick',[0 0.35 0.65 1]);
ylabel(ax,'$S$','Interpreter','latex');
title(ax,'(a) Per-device severity index','FontWeight','normal','FontSize',opts.font_size);
set(ax,'XTickLabel',[],'xlim',[0 250],'box','on');
grid(ax,'on');
lg = legend(ax,arrayfun(@(b) sprintf('Bus %d',b),bus,'UniformOutput',false), ...
    'Orientation','horizontal','Box','off');
lg.Layout.Tile = 'north';

ax = nexttile(tl); % (b) modes
hold(ax,'on');
modes = r.device_modes_history;
for k = 1:nd
    m = double(strcmpi(modes(ibr(k),:),'gfm')).';
    stairs(ax,t,m,'Color',FC(k,:),'LineWidth',1.0);
end
mark_events(ax,ev_col,t_events,t_reclose,t_modeend,opts);
ylim(ax,[-0.25 1.25]);
set(ax,'YTick',[0 1],'YTickLabel',{'GFL','GFM'});
ylabel(ax,'Mode');
title(ax,'(b) Committed mode per device','FontWeight','normal','FontSize',opts.font_size);
set(ax,'XTickLabel',[],'xlim',[0 250],'box','on');
grid(ax,'on');

ax = nexttile(tl); % (c) reference owner
code = owner_code(r);
stairs(ax,t,code,'Color',[0.25 0.10 0.55],'LineWidth',1.1);
mark_events(ax,ev_col,t_events,t_reclose,t_modeend,opts);
nvis = max(1,max(code));
ylim(ax,[-0.4 nvis+0.4]);
lbls = owner_labels(r,nvis);
set(ax,'YTick',0:nvis,'YTickLabel',lbls);
ylabel(ax,'Owner');
xlabel(ax,'$t$ [s]','Interpreter','latex');
title(ax,'(c) Network reference-angle owner','FontWeight','normal','FontSize',opts.font_size);
set(ax,'xlim',[0 250],'box','on');
grid(ax,'on');

audit_fonts(f,opts);
png = fullfile(out_dir,'fig_supervisor.png');
pf_page_export(f,png,opts.dpi);
end

% ===========================================================================
function png = draw_policy(R,opts,ev_col,t_events,out_dir)
%DRAW_POLICY  f_COI of every arm that reaches the horizon, one axis.
w = opts.width_in; h = opts.height_policy;
f = pf_page_figure(w,h,opts.font_size,opts.font_name);
ax = axes(f); hold(ax,'on');
styles = {'-','--','-.',':',':'};
cols   = {[0.00 0.24 0.75],[0.80 0.30 0.10],[0.00 0.55 0.35], ...
          [0.55 0.20 0.55],[0.30 0.30 0.30]};
names  = {'Adaptive switching','Pinned 1 GFM','Pinned 2 GFM', ...
          'Pinned 4 GFM','No adaptation'};
keys = {'adaptive','pinned_gfm1','pinned_gfm2','pinned_gfm4','no_adaptation'};
drew = 0;
for k = 1:numel(keys)
    r = R.(keys{k});
    if abs(r.t(end)-250)>5e-4, continue; end  % draw horizon-reaching arms only
    plot(ax,r.t(:),r.coi_frequency_Hz(:),'Color',cols{k}, ...
        'LineStyle',styles{k},'LineWidth',1.1,'DisplayName',names{k});
    drew = drew+1;
end
assert(drew>=2,'generate_final_report_figures_th:policyArms', ...
    'Expected at least two horizon-reaching arms, drew %d.',drew);
for e = t_events
    xline(ax,e,':','Color',ev_col,'LineWidth',0.8,'HandleVisibility','off', ...
        'FontName',char(opts.font_name),'FontSize',opts.font_size);
end
yline(ax,60,':','Color',[0.45 0.45 0.45],'LineWidth',0.8,'HandleVisibility','off', ...
    'FontName',char(opts.font_name),'FontSize',opts.font_size);
ylabel(ax,'$f_{\mathrm{COI}}$ [Hz]','Interpreter','latex');
xlabel(ax,'$t$ [s]','Interpreter','latex');
title(ax,'System COI frequency by control policy (arms reaching 250 s)','FontWeight','normal','FontSize',opts.font_size);
set(ax,'xlim',[0 250],'box','on');
grid(ax,'on');
lg = legend(ax,'Orientation','horizontal','Box','off','NumColumns',2);
assert(~isempty(lg) && isgraphics(lg,'legend'), ...
    'generate_final_report_figures_th:policyLegend', ...
    'Legend object was not created.');

audit_fonts(f,opts);
png = fullfile(out_dir,'fig_policy.png');
pf_page_export(f,png,opts.dpi);
end

% ===========================================================================
function mark_events(ax,ev_col,t_events,t_reclose,t_modeend,~)
%MARK_EVENTS  Vertical markers at the scheduled events and the two run
% results (presentation only; positions carry no data change).
for e = t_events
    xline(ax,e,':','Color',ev_col,'LineWidth',0.7,'HandleVisibility','off', ...
        'FontName',char(opts_font_name()),'FontSize',opts_font_size());
end
xline(ax,t_reclose,'-','Color',[0.75 0.10 0.10],'LineWidth',0.7,'HandleVisibility','off', ...
    'FontName',char(opts_font_name()),'FontSize',opts_font_size());
xline(ax,t_modeend,'-.','Color',[0.10 0.35 0.75],'LineWidth',0.7,'HandleVisibility','off', ...
    'FontName',char(opts_font_name()),'FontSize',opts_font_size());
end

% ===========================================================================
function fn = opts_font_name()
fn = 'TH SarabunPSK';
end

% ===========================================================================
function fs = opts_font_size()
fs = 12;
end

% ===========================================================================
function audit_fonts(f,opts)
%AUDIT_FONTS  Enforce then verify the lettering contract: every
% text-bearing object must be the contract font at exactly 12 pt.
% tiledlayout and legends rescale fonts after the figure defaults are set,
% so the whole object tree is walked and pinned once, then re-read to
% verify. This pins the FONT, never the data.
want = char(opts.font_name); fs = opts.font_size;
objs = findall(f,'-property','FontSize');
for k = 1:numel(objs)
    o = objs(k);
    if isprop(o,'FontName') && ~strcmpi(o.FontName,want)
        o.FontName = want;
    end
    if abs(o.FontSize-fs) > 1e-9
        o.FontSize = fs;
    end
end
% verification pass: re-read only; any remaining mismatch aborts
bad = {};
objs = findall(f,'-property','FontSize');
for k = 1:numel(objs)
    o = objs(k);
    fn = '';
    if isprop(o,'FontName'), fn = o.FontName; end
    if ~strcmpi(fn,want) || abs(o.FontSize-fs)>1e-9
        bad{end+1} = sprintf('%s (FontName="%s", FontSize=%g)', ...
            class(o),fn,o.FontSize); %#ok<AGROW>
    end
end
assert(isempty(bad),'generate_final_report_figures_th:fontAudit', ...
    'Font audit failed. These objects are not "%s" at %g pt:\n  %s', ...
    want,fs,strjoin(bad,'\n  '));
end

% ===========================================================================
function sha = sha256_of(f)
%SHA256_OF  Hex SHA-256 of a file via Java, on an absolute path.
fj = char(java.io.File(f).getCanonicalPath());
h = java.security.MessageDigest.getInstance('SHA-256');
fis = java.io.FileInputStream(fj);
try
    buf = zeros(1,65536,'int8'); buf = typecast(buf,'uint8');
    while true
        n = fis.read(buf);
        if n < 0, break; end
        h.update(buf(1:n));
    end
catch err
    fis.close();
    rethrow(err);
end
fis.close();
sha = sprintf('%02x', reshape(typecast(h.digest(),'uint8'),1,[]));
end

% ===========================================================================
function s = datestr_web(dn)
%S = datestr_web  Fixed-format timestamp for the provenance record.
% dn is a datenum (from dir) or a datetime.
if isa(dn,'datetime')
    s = char(datetime(dn,'Format','yyyy-MM-dd HH:mm:ss'));
else
    s = char(datetime(double(dn),'ConvertFrom','datenum', ...
        'Format','yyyy-MM-dd HH:mm:ss'));
end
end

% ===========================================================================
function ibr = findconverterrows(r)
%FINDCONVERTERROWS  Row indices of the IBR devices (complement of the SG,
% whose row carries the literal mode 'sg' at every sample).
modes = r.device_modes_history;
issg = strcmpi(modes(1,:),'sg');
ibr = [];
for k = 1:size(modes,1)
    if ~any(strcmpi(modes(k,:),'sg')), ibr(end+1) = k; end %#ok<AGROW>
end
ibr = ibr(:).';
assert(~isempty(issg) && isempty(ibr)==false, 'no converter rows found');
end


% ===========================================================================
function [m,sha] = read_macro_file(file)
%READ_MACRO_FILE Parse one generated \newcommand macro per line.
% Values may contain nested TeX braces (for example \times10^{-9}); the
% greedy end-of-line capture intentionally keeps the complete macro body.
sha = sha256_of(file);
txt = fileread(file);
tok = regexp(txt,'(?m)^\\newcommand\{\\([A-Za-z0-9]+)\}\{([^\r\n]*)\}\s*$','tokens');
assert(~isempty(tok),'generate_final_report_figures_th:badMacros', ...
    'No generated macros found in %s.',file);
m = struct();
for k = 1:numel(tok)
    name = tok{k}{1}; value = tok{k}{2};
    m.(name) = value;
end
end

% ===========================================================================
function [summary,sha] = read_summary_file(file)
%READ_SUMMARY_FILE Load the reporting summary without allowing a mid-write read.
sha = sha256_of(file);
S = load(file,'summary');
assert(isfield(S,'summary') && isstruct(S.summary) && ...
    isfield(S.summary,'arms'),'generate_final_report_figures_th:badSummary', ...
    'summary.mat lacks the expected summary.arms struct array.');
summary = S.summary;
assert(strcmp(sha,sha256_of(file)), ...
    'generate_final_report_figures_th:summaryChanged', ...
    'summary.mat changed while loading.');
end

% ===========================================================================
function value = macro_text(m,name)
assert(isfield(m,name),'generate_final_report_figures_th:missingMacro', ...
    'Macro %s is missing.',name);
value = char(m.(name));
value = regexprep(value,'\\texttt\{([^{}]*)\}','$1');
value = strrep(value,'\_','_');
value = strrep(value,'$','');
value = strtrim(value);
end

% ===========================================================================
function value = macro_num(m,name)
%MACRO_NUM Convert a generated scalar, including a TeX power of ten, to double.
s = macro_text(m,name);
if isempty(s) || strcmp(s,'--') || strcmpi(s,'nan')
    value = NaN;
    return;
end
tok = regexp(s,'^([+-]?(?:\d+\.?\d*|\.\d+))\s*\\times10\^\{([+-]?\d+)\}$', ...
    'tokens','once');
if ~isempty(tok)
    value = str2double(tok{1}) * 10^str2double(tok{2});
else
    value = str2double(s);
end
assert(isscalar(value) && isfinite(value), ...
    'generate_final_report_figures_th:badMacroNumber', ...
    'Macro %s is not a finite scalar: %s.',name,s);
end

% ===========================================================================
function sm = find_summary_arm(summary,id)
sm = [];
for k = 1:numel(summary.arms)
    if strcmp(char(string(summary.arms(k).id)),id)
        sm = summary.arms(k);
        break;
    end
end
assert(~isempty(sm),'generate_final_report_figures_th:missingSummaryArm', ...
    'summary.mat has no arm named %s.',id);
end

% ===========================================================================
function t = applied_times(r,type)
t = [];
if ~isfield(r,'event_log') || isempty(r.event_log), return; end
for k = 1:numel(r.event_log)
    e = r.event_log(k);
    typ = e.type;
    if iscell(typ), typ = typ{1}; end
    if isstruct(typ), typ = ''; end
    applied = isfield(e,'applied') && ~isempty(e.applied) && logical(e.applied);
    if applied && strcmpi(char(string(typ)),type)
        t(end+1) = double(e.t); %#ok<AGROW>
    end
end
t = sort(t);
end

% ===========================================================================
function assert_times(times,m,prefix,label)
suffix = {'One','Two','Three','Four','Five'};
for k = 1:numel(times)
    if k > numel(suffix), break; end
    want = macro_num(m,[prefix suffix{k}]);
    assert(isfinite(want) && abs(times(k)-want)<5e-4, ...
        'generate_final_report_figures_th:eventTimeMismatch', ...
        'Adaptive %s time %d differs from run-summary macro.',label,k);
end
end

% ===========================================================================
function n = gfm_max(r)
n = 0;
if isfield(r,'device_modes_history') && ~isempty(r.device_modes_history)
    n = max(sum(strcmpi(r.device_modes_history,'gfm'),1));
end
end

% ===========================================================================
function sev = severity_index(r)
%SEVERITY_INDEX  Per-device two-term severity from the published overlay
% terms J_V and J_f (same construction as the deck generator: equal weights,
% saturated to [0,1]). Presentation-only recomputation from published terms.
JV = r.agsi_reference.terms.J_V;
Jf = r.agsi_reference.terms.J_f;
if size(JV,1) ~= numel(r.t), JV = JV.'; end
if size(Jf,1) ~= numel(r.t), Jf = Jf.'; end
sev = min(1,max(0,0.5*JV+0.5*Jf));
if size(sev,1) ~= numel(r.t), sev = sev.'; end
end

% ===========================================================================
function code = owner_code(r)
%OWNER_CODE  Numeric reference-owner trace, 0 = SG, k = k-th IBR.
% event_context_history carries one entry per accepted sample (verified:
% numel(ec) == numel(r.t)); entry i's hybrid_state holds the committed
% reference_owner_indices at that sample. Empty set = the SG holds it.
n = numel(r.t);
ec = r.event_context_history;
assert(numel(ec)==n, ...
    'generate_final_report_figures_th:ecLength', ...
    'event_context_history has %d entries for %d samples.',numel(ec),n);
code = zeros(n,1);
for i = 1:n
    assert(isstruct(ec{i}) && isfield(ec{i},'hybrid_state') && ...
        isstruct(ec{i}.hybrid_state) && ...
        isfield(ec{i}.hybrid_state,'reference_owner_indices'), ...
        'generate_final_report_figures_th:ownerMissing', ...
        'Sample %d has no canonical reference-owner field.',i);
    own = ec{i}.hybrid_state.reference_owner_indices;
    assert(isempty(own) || (isnumeric(own) && isscalar(own) && ...
        isfinite(own) && own==fix(own)), ...
        'generate_final_report_figures_th:ownerShape', ...
        'Reference owner at sample %d must be empty or one scalar index.',i);
    if isempty(own), continue; end
    assert(own>=1 && own<=numel(r.device_bus_ids), ...
        'generate_final_report_figures_th:ownerRange', ...
        'Reference owner index %d is outside the device list.',own);
    if own == 1
        code(i) = 0;                % resource 1 is SG1
    else
        code(i) = own - 1;          % resources 2..5 map to IBR 1..4
    end
end
end

% ===========================================================================
function lbls = owner_labels(r,nvis)
%OWNER_LABELS  Y-tick labels for the reference-owner trace.
lbls = cell(1,nvis+1);
lbls{1} = 'SG (bus 1)';
ibr = findconverterrows(r);
for k = 1:nvis
    if k<=numel(ibr)
        lbls{k+1} = sprintf('Bus %d',r.device_bus_ids(ibr(k)));
    else
        lbls{k+1} = sprintf('%d',k);
    end
end
end
