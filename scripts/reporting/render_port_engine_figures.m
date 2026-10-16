function render_port_engine_figures(only)
%RENDER_PORT_ENGINE_FIGURES Render the port-engine optimization report plots.
% Presentation only: every series is read unchanged from artifacts -- the
% frozen baseline compact artifact (baseline_compact_20261013/baseline_compact.mat,
% 21 variables, 18852 samples) and, for same-tree A/B overlays, the completed
% Arm A run artifact (bench_160s_armA_20261014_113418_825/raw.mat, read via
% HDF5 flat datasets only).  Pages follow the delivered NE39 report idiom:
% Times (matching the xelatex body), LaTeX interpreter, dashed grid, no axis
% box, vector PDF via exportgraphics.
%
% Honesty contract (mirrors report_port_engine_en.tex):
%   - candidate overlay / counter-comparison figures are SKIPPED (with a
%     console note) until a completed candidate artifact exists; no
%     placeholder data is ever drawn;
%   - the speedup-bars figure draws ONLY the numbers that have artifacts
%     behind them, each annotated with its measurement window; the NE39
%     160-s bar is drawn as an empty slot labelled "pending" — never a
%     guessed value;
%   - event marks are drawn at the stored event times read from the artifact
%     scalars, not from schedule constants.
%
% Optional: render_port_engine_figures('speedup') renders only the speedup
% figure; no argument renders all currently renderable figures.

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
exp_tree = fullfile(fileparts(root), 'GridFormLab-experiment');
data_dir = fullfile(root, 'docs', 'source', 'figures', 'port_engine');
base_mat = fullfile(exp_tree, 'output', 'diagnostics', ...
    'baseline_compact_20261013', 'baseline_compact.mat');
if ~exist(base_mat, 'file')
    error('render_port_engine_figures:missingBaseline', ...
        'baseline_compact.mat not found: %s', base_mat);
end

if ~exist(data_dir, 'dir'), mkdir(data_dir); end

% Arm A same-tree artifact (the re-measured baseline of today's A/B design).
% Its raw.mat is a nested-HDF5 mat; opening it costs minutes and hits extractor
% landmines (matfile nested = error, h5info = multi-minute hang per the
% baseline extraction notes), so when the reader has not been proven in this
% MATLAB session yet, event times come from bench_summary.txt instead (plain
% text, same artifact) and the trajectory reader stays OFF until verified.
armA_dir = fullfile(exp_tree, 'output', 'diagnostics', ...
    'bench_160s_armA_20261014_113418_825');
armA_mat = fullfile(armA_dir, 'raw.mat');
armA_summary = fullfile(armA_dir, 'bench_summary.txt');

% Report figures match the xelatex body font (newtx = Times).
font_name = 'Times New Roman';
colors = [0 0.4470 0.7410; 0.8500 0.3250 0.0980; 0.9290 0.6940 0.1250; ...
          0.4940 0.1840 0.5560; 0.4660 0.6740 0.1880];
old = struct('axes',get(groot,'defaultAxesFontName'), ...
             'text',get(groot,'defaultTextFontName'), ...
             'legend',get(groot,'defaultLegendFontName'), ...
             'ti',get(groot,'defaultTextInterpreter'), ...
             'ai',get(groot,'defaultAxesTickLabelInterpreter'), ...
             'li',get(groot,'defaultLegendInterpreter'), ...
             'gl',get(groot,'defaultAxesGridLineStyle'), ...
             'bx',get(groot,'defaultAxesBox'));
cleanup = onCleanup(@() restore_fonts(old)); %#ok<NASGU>
set(groot,'defaultTextInterpreter','latex', ...
    'defaultAxesTickLabelInterpreter','latex', ...
    'defaultLegendInterpreter','latex', ...
    'defaultLegendFontSize',9,'defaultAxesFontSize',9,'defaultTextFontSize',9, ...
    'defaultAxesGridLineStyle','--','defaultAxesBox','off', ...
    'defaultAxesFontName',font_name,'defaultTextFontName',font_name, ...
    'defaultLegendFontName',font_name);

B = load(base_mat);   % read-only use of the compact artifact
marks = event_marks_from_scalars(B.scalars);
armA_events = parse_armA_events(armA_summary);   % plain-text artifact only

mode = 'all';
if nargin >= 1
    mode = char(only);
end

switch lower(mode)
    case 'timeline'
        render_timeline(data_dir, marks, colors, armA_events);
    case 'voltage'
        render_voltage(data_dir, B, marks, colors);
    case 'frequency'
        render_frequency(data_dir, B, marks, colors);
    case 'power'
        render_power(data_dir, B, marks, colors);
    case 'dtnewton'
        render_dt_newton(data_dir, B, marks, colors);
    case 'speedup'
        render_speedup(data_dir, colors);
    case 'overlay'
        render_overlay(data_dir, B, marks);
    case 'counters'
        render_counters(data_dir, B, marks);
    otherwise
        render_timeline(data_dir, marks, colors, armA_events);
        render_voltage(data_dir, B, marks, colors);
        render_frequency(data_dir, B, marks, colors);
        render_power(data_dir, B, marks, colors);
        render_dt_newton(data_dir, B, marks, colors);
        render_speedup(data_dir, colors);
        render_overlay(data_dir, B, marks);
        render_counters(data_dir, B, marks);
end
end

% ---------------------------------------------------------------------------
% Figures from the baseline artifact (measured now)
% ---------------------------------------------------------------------------

function render_timeline(data_dir, marks, colors, armA_events)
f = report_figure([60 60 1150 300]);
hold on;
% One horizontal lane per event: stem at the stored event time.  Labels are
% normalized first (strip pre-escapes) then escaped exactly once --- double
% escaping produces '\_' sequences the latex interpreter can reject.
cols = [0 0.4470 0.7410; 0.8500 0.3250 0.0980; 0.9290 0.6940 0.1250; ...
        0.4940 0.1840 0.5560; 0.4660 0.6740 0.1880; 0.2 0.2 0.2];
for k = 1:numel(marks)
    lab = strrep(marks(k).label, '\_', '_');      % strip any pre-escape
    lab = strrep(lab, '_', '\_');                 % single escape, once
    plot([marks(k).t marks(k).t],[-0.35 0.35],'-','Color',cols(mod(k-1,6)+1,:), ...
        'LineWidth',1.4,'DisplayName',lab);
    plot(marks(k).t,0,'o','MarkerSize',7, ...
        'MarkerFaceColor',cols(mod(k-1,6)+1,:),'MarkerEdgeColor','none', ...
        'HandleVisibility','off');
    text(marks(k).t, 0.42*(-1)^k, sprintf('%.6f s', marks(k).t), ...
        'Rotation',0,'HorizontalAlignment','center','FontSize',8);
end
% Same-tree Arm A events (measured today), lower lane, diamonds.
for k = 1:numel(armA_events)
    ae = armA_events(k);
    plot([ae.t ae.t],[-0.7 -0.45],'-','Color',cols(mod(k-1,6)+1,:), ...
        'LineWidth',1.2,'DisplayName',[ae.label ' (' sprintf('%.6f',ae.t) ' s)']);
    plot(ae.t,-0.575,'d','MarkerSize',6, ...
        'MarkerFaceColor',cols(mod(k-1,6)+1,:),'MarkerEdgeColor','none', ...
        'HandleVisibility','off');
end
yline(0,':','Color',[.55 .55 .55],'HandleVisibility','off');
xlim([0 160]); ylim([-0.8 0.8]);
xlabel('t [s]');
title('NE39 160-s event chronology: baseline run (top) vs same-tree Arm A (bottom)');
lg = legend('Orientation','horizontal','Location','northoutside', ...
    'NumColumns',min(6,max(numel(marks),1)),'Box','off','FontSize',9); %#ok<NASGU>
grid on;
export_report(f,data_dir,'fig_event_timeline.pdf');
end

function render_voltage(data_dir, B, marks, colors)
f = report_figure([80 80 1150 480]);
tiledlayout(f,2,1,'TileSpacing','compact','Padding','compact');
nexttile; hold on;
plot(B.t(:), B.Vmag_sg_bus31(:),'Color',colors(1,:),'LineWidth',1.0);
yline(1.0,':','Color',[.45 .45 .45],'HandleVisibility','off');
draw_event_marks(marks);
grid on; ylabel('$|V|$ (pu)');
title('SG31 bus-31 voltage magnitude (raw accepted samples)');
xlim([0 160]);
nexttile; hold on;
plot(B.t(:), B.Vmag_ibr_bus30(:),'Color',colors(2,:),'LineWidth',1.0);
yline(1.0,':','Color',[.45 .45 .45],'HandleVisibility','off');
draw_event_marks(marks);
grid on; ylabel('$|V|$ (pu)'); xlabel('t [s]');
title('IBR bus 30 terminal voltage magnitude (raw accepted samples)');
xlim([0 160]);
sgtitle('Baseline voltage reference series','FontWeight','bold');
export_report(f,data_dir,'fig_baseline_voltage.pdf');
end

function render_frequency(data_dir, B, marks, colors)
f = report_figure([100 100 1150 480]);
hold on;
plot(B.t, B.coi_frequency_Hz,'Color',colors(1,:),'LineWidth',1.1);
yline(60,':','Color',[.45 .45 .45],'HandleVisibility','off');
draw_event_marks(marks);
grid on; xlabel('Time (s)'); ylabel('f (Hz)');
title(sprintf('Baseline centre-of-inertia frequency (%d raw samples)', numel(B.t)));
xlim([0 160]);
export_report(f,data_dir,'fig_baseline_frequency.pdf');
end

function render_power(data_dir, B, marks, colors)
% Device column 1 = SG31 (documented column order of the compact dump).
f = report_figure([120 120 1150 640]);
tiledlayout(f,2,1,'TileSpacing','compact','Padding','compact');
nexttile; hold on;
plot(B.t, B.P_MW(:,1),'Color',colors(1,:),'LineWidth',1.0);
draw_event_marks(marks);
grid on; ylabel('P (MW)');
title('SG31 device active power through trip and reclose');
xlim([0 160]);
nexttile; hold on;
plot(B.t, B.Q_MVAr(:,1),'Color',colors(2,:),'LineWidth',1.0);
draw_event_marks(marks);
grid on; ylabel('Q (MVAr)'); xlabel('t [s]');
title('SG31 device reactive power');
xlim([0 160]);
sgtitle('Baseline SG31 power transfer (column 1 of the 10-device panels)', ...
    'FontWeight','bold');
export_report(f,data_dir,'fig_baseline_power.pdf');
end

function render_dt_newton(data_dir, B, marks, colors)
f = report_figure([140 70 1150 720]);
tiledlayout(f,2,1,'TileSpacing','compact','Padding','compact');
nexttile; hold on;
semilogy((1:numel(B.dt_history))', B.dt_history,'Color',colors(1,:), ...
    'LineWidth',0.9);
draw_event_marks(marks);
grid on; ylabel('dt (s, log)');
title('Accepted step size per accepted step (dt\_history, as stored)');
xlim([0 numel(B.dt_history)]);
nexttile; hold on;
stem((1:numel(B.iter_per_step))', B.iter_per_step,'Marker','none', ...
    'Color',colors(2,:),'LineWidth',0.5);
grid on; ylabel('Newton iters'); xlabel('accepted step index');
title('Newton iterations per accepted step (iter\_per\_step, as stored)');
xlim([0 numel(B.iter_per_step)]);
sgtitle('Where the 6708.7 s baseline spends its steps','FontWeight','bold');
export_report(f,data_dir,'fig_dt_newton.pdf');
end

% ---------------------------------------------------------------------------
% Micro-bench figure (only artifact-backed numbers; one pending slot)
% ---------------------------------------------------------------------------

function render_speedup(data_dir, colors)
% Measured, artifact-cited micro-benchmarks (see report Table 5 and its
% provenance column).  Each entry: [speedup, label, window].  These numbers
% are the report's, not independent input data.
meas = { ...
    2.2,  'Lane A residual reuse',  'composite arm $t_{end}=2.0$\,s'; ...
    2.53, 'parfor FD groups',       'IEEE14, 33 groups, 4 workers'; ...
    3.33, 'parfor FD groups',       'NE39, 88 groups, 4 workers'};
target = 2.0;   % D5 phase target on NE39 160 s -- a target, not a result

f = report_figure([160 90 1150 500]);
hold on;
yline(target,'--','Color',colors(4,:),'LineWidth',1.2, ...
    'Label','{\color{purple}phase target $2\times$ (NE39 160 s)}', ...
    'HandleVisibility','off');
nb = size(meas,1);
xs = 1:nb+2;   % leave two slots: NE39 160 s (pending) and MEX (parity only)
for k = 1:nb
    bar(xs(k), meas{k,1},0.55,'FaceColor',colors(1,:),'EdgeColor','none');
    text(xs(k), meas{k,1}+0.07, sprintf('%.2f$\\times$', meas{k,1}), ...
        'HorizontalAlignment','center','FontSize',10);
end
% Pending slot: the full-window 160-s measurement.  An empty dashed frame at
% the target height -- never a guessed bar.
plot(xs(nb+1)+[-1 1 1 -1 -1]*0.30, [0 0 target target 0],'--', ...
    'Color',colors(3,:),'LineWidth',1.3,'HandleVisibility','off');
text(xs(nb+1), target/2, {'pending';'measurement'}, 'HorizontalAlignment', ...
    'center','FontSize',10,'Color',colors(3,:),'Rotation',90);
% MEX slot: no timing number exists (parity tests only) -- also pending.
plot(xs(nb+2)+[-0.30 0.30], [0 0],'-','Color',colors(5,:),'LineWidth',2.0);
text(xs(nb+2), 0.16, {'MEX kernel:';'parity 4/4, no';'timing claim'}, ...
    'HorizontalAlignment','center','FontSize',9,'Color',[.3 .3 .3]);
set(gca,'XTick',xs, ...
    'XTickLabel',{[meas{1,2} '\newline{\fontsize{7}' meas{1,3} '}'], ...
                  [meas{2,2} '\newline{\fontsize{7}' meas{2,3} '}'], ...
                  [meas{3,2} '\newline{\fontsize{7}' meas{3,3} '}'], ...
                  'NE39 160 s candidate\newline{\fontsize{7}full window}', ...
                  'MEX+OpenMP kernel\newline{\fontsize{7}not integrated}'}, ...
    'XTickLabelRotation',20);
ylabel('measured speedup ($\times$)');
ylim([0 4.0]); grid on;
title('Measured speedups by mechanism (windows differ --- bars are never summed)');
export_report(f,data_dir,'fig_speedup_microbenches.pdf');
end

% ---------------------------------------------------------------------------
% Candidate figures: SKIP with a console note until a completed artifact
% exists.  No placeholder data is ever drawn.
% ---------------------------------------------------------------------------

function [ok, cand] = find_candidate_artifact()
% Returns true only for a bench folder with convergence proven: a
% bench_summary.txt whose converged field is 1.  This is the gate that keeps
% failed runs (like the 2026-10-14 05:32 attempt) out of the report.
candidate_root = fullfile(fileparts(fileparts(fileparts( ...
    mfilename('fullpath')))), 'GridFormLab-experiment', 'output', ...
    'diagnostics');
ok = false;
cand = struct('folder','', 'summary','', 't',[], 'V_sgbus31',[], ...
    'V_ibrbus30',[], 'coi_Hz',[], 'P_MW',[], 'Q_MVAr',[], 'scalars',[]);
d = dir(candidate_root);
for k = 1:numel(d)
    if ~d(k).isdir, continue; end
    s = fullfile(d(k).folder, d(k).name, 'bench_summary.txt');
    if exist(s,'file') ~= 2, continue; end
    txt = fileread(s);
    tok = regexp(txt, 'converged=(\d+)', 'tokens', 'once');
    if isempty(tok), continue; end
    if str2double(tok{1}) == 1
        ok = true;
        cand.folder = fullfile(d(k).folder, d(k).name);
        cand.summary = txt;
        return;
    end
end
end

function render_overlay(data_dir, ~, ~) %#ok<INUSD>
[have, cand] = find_candidate_artifact();
if ~have
    note_skip('trajectory overlay', ...
        'no bench folder with converged=1 exists; overlay needs the full-window candidate artifact');
    export_pending_stub(data_dir,'fig_overlay_voltage.pdf', ...
        'Same-tree A/B trajectory overlay', ...
        'requires Arm A trajectory array extraction (raw.mat 738 MB HDF5) plus a completed companion arm.\\ Arm A headline is measured and stands (1972.52 s, SUCCESS @ 119.521920776).\\ Raw-array extraction deliberately OFF in this render, per evidence contract.');
    return;
end
% Once a candidate exists, its raw.mat must be read through the same
% read-only path used for the baseline before any panel is drawn --- that
% reader is written when the first completed candidate lands.
error('render_port_engine_figures:candidateReaderNotWritten', ...
    'candidate artifact found at %s but the read-only overlay reader is not implemented yet; write it before drawing', ...
    cand.folder);
end

function render_counters(data_dir, ~, ~) %#ok<INUSD>
[have, cand] = find_candidate_artifact();
if ~have
    note_skip('counter comparison', ...
        'no completed candidate artifact (Run 1 counters are NaN)');
    export_pending_stub(data_dir,'fig_counters.pdf', ...
        'Counter comparison', ...
        'requires completed counter extraction per arm.\\ Arm A measured and stands (1972.52 s, SUCCESS); companion-arm counters are the pending piece.');
    return;
end
error('render_port_engine_figures:candidateReaderNotWritten', ...
    'candidate artifact found at %s but the counter reader is not implemented yet', ...
    cand.folder);
end

function export_pending_stub(data_dir,name,title_txt,lines)
% A figure-sized page that states the figure is pending -- rendered as a
% vector PDF so the LaTeX \IfFileExists branch shows the honest placeholder
% in the built report instead of silently dropping the figure.
f = report_figure([120 200 1000 360]);
ax = axes(f); axis(ax,'off');
text(0.5,0.62,[title_txt],'HorizontalAlignment','center','FontSize',13);
text(0.5,0.36,lines,'HorizontalAlignment','center','FontSize',10, ...
    'Color',[0.75 0.13 0.13],'Interpreter','tex');
text(0.5,0.12,'(placeholder page --- this figure carries no data until the measurement exists)', ...
    'HorizontalAlignment','center','FontSize',9,'Color',[.4 .4 .4]);
export_report(f,data_dir,name);
end

function note_skip(what, why)
fprintf('render_port_engine_figures: skipping %s -- %s\n', what, why);
end

% ---------------------------------------------------------------------------
% Helpers
% ---------------------------------------------------------------------------

function marks = event_marks_from_scalars(s)
% Event times read from the stored run scalars -- never from schedule
% constants.  Only events whose scalar exists and is finite become marks.
marks = struct('t',{},'label',{},'applied',{});
marks = add_mark(marks, s.t_sg_trip, 'sg trip');
marks = add_mark(marks, s.requested_sg_on_time, 'sg on request');
marks = add_mark(marks, s.actual_reclose_time, 'SG31 reclose');
% Horizon end is the sample-grid length, not a scalar event: it is implied
% by the x-limit and deliberately not drawn.
end

function marks = add_mark(marks,t,lab)
if isscalar(t) && isfinite(t)
    marks(end+1) = struct('t',double(t),'label',lab,'applied',true); %#ok<AGROW>
end
end

function draw_event_marks(marks)
for k = 1:numel(marks)
    xline(marks(k).t,':','Color',[.55 .55 .55],'HandleVisibility','off', ...
        'LineWidth',0.8);
end
end

function f = report_figure(position)
f = figure('Visible','off','Color','w','Position',position,'PaperPositionMode','auto');
end

function export_report(f,data_dir,name)
drawnow;
outfile = fullfile(data_dir,name);
try
    exportgraphics(f,outfile,'ContentType','vector','BackgroundColor','white');
catch e
    % Fail-honest fallback: one retry with automatic content, then one with
    % an interactive-visible figure (some batch pipelines fail vectorization
    % on hidden figures).  Every fallback is reported on stdout, never silent.
    warning('render_port_engine_figures:exportFallback', ...
        'vector export failed for %s (%s); retrying auto content', name, e.identifier);
    try
        exportgraphics(f,outfile,'BackgroundColor','white');
        disp(['Fallback (auto content) used for: ' name]);
    catch
        warning('render_port_engine_figures:exportFallback2', ...
            'auto export failed too; retrying with visible figure');
        set(f,'Visible','on');
        drawnow;
        exportgraphics(f,outfile,'ContentType','vector','BackgroundColor','white');
        disp(['Fallback (visible+vector) used for: ' name]);
    end
end
close(f);
end


function armA_events = parse_armA_events(armA_summary)
% Parse the EVENT lines from the Arm A bench_summary.txt (plain text artifact).
armA_events = struct('t',{},'label',{},'applied',{});
if exist(armA_summary,'file')~=2, return; end
txt = fileread(armA_summary);
tok = regexp(txt, 'EVENT\s+t=([0-9.]+)\s+type=(\w+)\s+applied=([01])', 'tokens');
names = containers.Map({'sg_trip','fault_on','fault_clear','sg_on','sg_reclose'}, ...
    {'Arm A sg_trip','Arm A fault_on','Arm A fault_clear','Arm A sg_on','Arm A reclose'});
for k = 1:numel(tok)
    t = str2double(tok{k}{1}); a = str2double(tok{k}{3});
    nm = 'Arm A event';
    if isKey(names, tok{k}{2}), nm = names(tok{k}{2}); end
    if isfinite(t) && a==1
        armA_events(end+1) = struct('t',t,'label',nm,'applied',true); %#ok<AGROW>
    end
end
end

function restore_fonts(old)
set(groot,'defaultAxesFontName',old.axes,'defaultTextFontName',old.text, ...
    'defaultLegendFontName',old.legend, ...
    'defaultTextInterpreter',old.ti, ...
    'defaultAxesTickLabelInterpreter',old.ai, ...
    'defaultLegendInterpreter',old.li, ...
    'defaultAxesGridLineStyle',old.gl, ...
    'defaultAxesBox',old.bx);
end
