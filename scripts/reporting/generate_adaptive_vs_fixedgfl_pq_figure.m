function out = generate_adaptive_vs_fixedgfl_pq_figure()
%GENERATE_ADAPTIVE_VS_FIXEDGFL_PQ_FIGURE  Two-panel P/Q comparison figure in
% the EECON49 style: the delivered adaptive switching policy (thick blue)
% against EVERY non-switching policy arm (thin grey cloud), for the Thai
% final report.
%
%   (a) per-converter active power, full 0-250 s horizon
%   (b) per-converter reactive power, full horizon
%
%   Grey cloud arms (each frozen at its initial GFM commitment -- the
%   "non-switching" family):
%     locked_gfl_diag  all-four-GFL diagnostic continuation
%                      (ASSUMED_DIAGNOSTIC: allow_no_vf_island=true +
%                      angle_gauge_bus=1 slack-gauge pin + ideal-DC device
%                      clone; see scripts/diagnostics/run_locked_gfl_diag_250s.m.
%                      The production noVoltageFormingSource refusal is
%                      unchanged. Reached 250 s converged.)
%     pinned_gfm1/2    delivered PROJECT_RESULT arms (reach 250 s)
%     pinned_gfm4      delivered PROJECT_RESULT arm (hard-stops at 25.485 s;
%                      its grey traces simply end there)
%     no_adaptation    delivered PROJECT_RESULT control arm (reach 250 s)
%   Blue:
%     adaptive         delivered PROJECT_RESULT arm (reach 250 s)
%
%   Signals are the SAME accepted-trajectory fields the report's
%   fig_electrical uses (result.device_P_pu / device_Q_pu rows of the four IBR
%   resources mapping to buses [2 3 6 8]); no smoothing, filtering or
%   resampling.
%
%   Output: docs/source/figures/final_report_th/fig_pq_adaptive_vs_fixedgfl.png
%   (300 dpi, TH Sarabun PSK 16 pt, same contract as fig_electrical).

pf_init_paths();

zeta_dir = fullfile('output','diagnostics','ieee14_gfm_lock_compare_zeta');
adaptive_cache = fullfile(zeta_dir,'adaptive_250s.mat');
grey_caches = { ...
    fullfile('output','diagnostics','ieee14_locked_gfl_diag', ...
             'locked_gfl_diag_gauge_250s.mat'), 'locked GFL x4 (diag)'; ...
    fullfile(zeta_dir,'pinned_gfm1_250s.mat'), 'pinned 1 GFM'; ...
    fullfile(zeta_dir,'pinned_gfm2_250s.mat'), 'pinned 2 GFM'; ...
    fullfile(zeta_dir,'pinned_gfm4_250s.mat'), 'pinned 4 GFM'; ...
    fullfile(zeta_dir,'no_adaptation_250s.mat'), 'no adaptation'};
assert(isfile(adaptive_cache),'generate_adaptive_vs_fixedgfl_pq_figure:missingAdaptive', ...
    'Adaptive cache not found: %s',adaptive_cache);
for k = 1:size(grey_caches,1)
    assert(isfile(grey_caches{k,1}), ...
        'generate_adaptive_vs_fixedgfl_pq_figure:missingGrey', ...
        'Grey cache not found: %s',grey_caches{k,1});
end

ra = load(adaptive_cache);  ra = ra.result;
ta = ra.t(:);
ibr_a = find(ismember(ra.device_bus_ids,[2 3 6 8]));
assert(isequal(ra.device_bus_ids(ibr_a),[2 3 6 8]), ...
    'generate_adaptive_vs_fixedgfl_pq_figure:ibrMapping', ...
    'Adaptive converter-to-bus mapping differs from [2 3 6 8].');
Pa = ra.device_P_pu(ibr_a,:);  Qa = ra.device_Q_pu(ibr_a,:);

sched = ra.sched;
t_events = [sched.sg_trip sched.load_step sched.fault_on sched.line_trip ...
            sched.restore_time];
assert(max(abs(t_events-[20 50 85 110 145]))<1e-10, ...
    'generate_adaptive_vs_fixedgfl_pq_figure:schedule', ...
    'Event schedule differs from the frozen [20 50 85 110 145] s.');

% ---------------------------------------------------------------- drawing --
% HOST ADAPTATION: "TH Sarabun New" is the Sarabun family actually installed
% on this host (the bundled TH Sarabun PSK is not system-installed here; see
% generate_final_report_figures_th.m). Same-designer successor family.
font_name = 'TH Sarabun New';
font_size = 16;
w = 6.30; h = 2.80;
blue = [0.00 0.24 0.75];
grey = [0.45 0.45 0.45];

f = figure('Units','inches','Position',[0 0 w h],'Color','w');
tl = tiledlayout(f,1,2,'TileSpacing','compact','Padding','compact');

% (a) P, full horizon
ax = nexttile(tl); hold(ax,'on');
for k = 1:size(grey_caches,1)
    rf = load(grey_caches{k,1});  rf = rf.result;
    ibr_f = find(ismember(rf.device_bus_ids,[2 3 6 8]));
    assert(isequal(rf.device_bus_ids(ibr_f),[2 3 6 8]), ...
        'generate_adaptive_vs_fixedgfl_pq_figure:greyMapping', ...
        'Arm %s converter mapping differs from [2 3 6 8].',grey_caches{k,2});
    plot(ax,rf.t(:),rf.device_P_pu(ibr_f,:).','Color',[grey 0.5], ...
        'LineWidth',0.55,'HandleVisibility','off');
end
plot(ax,ta,Pa.','Color',blue,'LineWidth',1.3);
for te = t_events
    plot(ax,[te te],ylim(ax),':','Color',[0.65 0.65 0.65],'LineWidth',0.6, ...
        'HandleVisibility','off');
end
ylabel(ax,'$P$ [pu]','Interpreter','latex');
title(ax,'(a) กำลังจริง (0--250 s)','FontWeight','normal','FontSize',font_size-2);
set(ax,'xlim',[0 250],'box','on','XTickLabel',[]);
grid(ax,'on');

% (b) Q, full horizon
ax = nexttile(tl); hold(ax,'on');
for k = 1:size(grey_caches,1)
    rf = load(grey_caches{k,1});  rf = rf.result;
    ibr_f = find(ismember(rf.device_bus_ids,[2 3 6 8]));
    plot(ax,rf.t(:),rf.device_Q_pu(ibr_f,:).','Color',[grey 0.5], ...
        'LineWidth',0.55,'HandleVisibility','off');
end
plot(ax,ta,Qa.','Color',blue,'LineWidth',1.3);
for te = t_events
    plot(ax,[te te],ylim(ax),':','Color',[0.65 0.65 0.65],'LineWidth',0.6, ...
        'HandleVisibility','off');
end
xlabel(ax,'$t$ [s]','Interpreter','latex');
title(ax,'(b) กำลังรีแอกทีฟ (0--250 s)','FontWeight','normal','FontSize',font_size-2);
set(ax,'xlim',[0 250],'box','on');
grid(ax,'on');
lg = legend(ax,{'Adaptive GFL/GFM','Fixed (ไม่สลับโหมด)'}, ...
    'Orientation','horizontal','Box','off');
lg.Layout.Tile = 'north';
set(lg,'FontSize',font_size-3);

set(findall(f,'-property','FontName'),'FontName',font_name);
set(findall(f,'-property','FontSize'),'FontSize',font_size-2);
set(lg,'FontSize',font_size-3);
% NOTE: only the axis labels use the latex interpreter (set at creation);
% Thai titles/legend keep the default tex interpreter.

outdir = fullfile('docs','source','figures','final_report_th');
if ~isfolder(outdir), mkdir(outdir); end
png = fullfile(outdir,'fig_pq_adaptive_vs_fixedgfl.png');
exportgraphics(f,png,'Resolution',300);

prov = fullfile(outdir,'fig_pq_adaptive_vs_fixedgfl.provenance.txt');
fid = fopen(prov,'w');
fprintf(fid,['Generated by scripts/reporting/' ...
             'generate_adaptive_vs_fixedgfl_pq_figure.m\n']);
fprintf(fid,'Date: %s\n',char(datetime('now')));
fprintf(fid,['Adaptive arm (blue): %s  -- PROJECT_RESULT\n'],adaptive_cache);
fprintf(fid,['Grey cloud (per-converter P/Q of the four IBRs, one thin line\n' ...
             'per device per arm) -- the non-switching policy family:\n']);
for k = 1:size(grey_caches,1)
    fprintf(fid,'  %s\n',grey_caches{k,1});
end
fprintf(fid,['  locked_gfl_diag is ASSUMED_DIAGNOSTIC (allow_no_vf_island=true,\n' ...
             '  angle_gauge_bus=1 slack-gauge pin from t=20.25 s, ideal-DC\n' ...
             '  device clone ibr.eecon49_dual_mode_ideal_dc; the production\n' ...
             '  noVoltageFormingSource refusal is unchanged; run reached 250 s\n' ...
             '  converged). pinned_gfm4 hard-stops at 25.485 s (delivered\n' ...
             '  PROJECT_RESULT); the other grey arms are delivered\n' ...
             '  PROJECT_RESULT runs.\n']);
fprintf(fid,'Event times (CASE_DEFINED, s): %s\n',mat2str(t_events));
fprintf(fid,['Signal: result.device_P_pu / device_Q_pu rows of the four IBR ' ...
             'resources\n(buses [2 3 6 8]) -- raw accepted samples; no ' ...
             'smoothing, filtering,\nclipping, offset or resampling applied.\n']);
fprintf(fid,'Fonts: %s at %g pt\n',font_name,font_size);
fclose(fid);
fprintf('wrote %s\n',png);
out = struct('png',png,'provenance',prov);
end
