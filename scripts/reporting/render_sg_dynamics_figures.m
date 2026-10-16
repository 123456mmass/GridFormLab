function render_sg_dynamics_figures(cpp_csv, golden_csv, preview_png)
%RENDER_SG_DYNAMICS_FIGURES SG31 swing comparison: C++ run 008 vs golden.
% Presentation only: every series is read unchanged from the two trajectory
% artifacts -- the C++ stage-2 run 008 export and the canonical golden
% export -- through a column-selective textscan (the C++ CSV is 370 MB and
% is never loaded whole into memory as a table).  Pages follow the delivered
% NE39 report idiom: Times (matching the xelatex body), LaTeX interpreter,
% dashed grid, no axis box, vector PDF via exportgraphics.
%
% Honesty contract:
%   - curves are drawn from the stored artifacts only; the two runs differ
%     in their reclose instant (C++ guard close 100.499 s vs golden
%     119.5219 s), which is a policy gap, not a rendering choice -- both
%     instants are marked on the timeline panel;
%   - the printed comparison block reports drift rate and window errors
%     computed from the plotted data, never eyeballed values;
%   - no series is smoothed; only uniform stride decimation is applied to
%     keep the vector PDF small, and the decimation factor is printed.
%
% Usage:
%   render_sg_dynamics_figures                     % default artifact paths
%   render_sg_dynamics_figures(cpp_csv, golden_csv)
%   render_sg_dynamics_figures([], [], preview_png) % + a PNG preview copy

if nargin < 1 || isempty(cpp_csv)
    cpp_csv = fullfile('D:', filesep, '4-year-project', 'GridFormLab-port', ...
        'runs', 'stage2_smoke_ne39_008_gfm160s_golden', 'traj_stage2.csv');
end
if nargin < 2 || isempty(golden_csv)
    golden_csv = fullfile('D:', filesep, '4-year-project', 'GridFormLab-experiment', ...
        'output', 'diagnostics', 'canonical_parity_20261014', ...
        'ne39_reclose_baseline', 'traj_reference.csv');
end
if nargin < 3, preview_png = ''; end
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
data_dir = fullfile(root, 'docs', 'source', 'figures', 'flagship_cpp');
if ~exist(data_dir, 'dir'), mkdir(data_dir); end

% Report figures match the xelatex body font (newtx = Times).
font_name = 'Times New Roman';
col_cpp = [0 0.4470 0.7410];        % C++ engine
col_ref = [0.8500 0.3250 0.0980];   % MATLAB golden reference
col_v30 = [0 0.4470 0.7410];
col_v31 = [0.9290 0.6940 0.1250];
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

% Event instants, read from the run artifacts (events_stage2.json /
% guard_reclose.json for the C++, events_reference.json for the golden).
ev_cpp.t = [20 60 60.15 100 100.499];
ev_cpp.label = {'sg trip','fault on','fault clear','sg on request','reclose (guard close)'};
ev_ref.t = [20 60 60.15 100 119.5219];
ev_ref.label = {'sg trip','fault on','fault clear','sg on request','SG31 reclose'};

C = read_traj(cpp_csv, {'delta_SG31','omega_SG31','bus_voltage_bus30','bus_voltage_bus31'});
R = read_traj(golden_csv, {'delta_rad','omega_pu','bus_voltage_bus30','bus_voltage_bus31'});

f = report_figure([60 60 1120 860]);
tl = tiledlayout(f,2,2,'TileSpacing','compact','Padding','compact');

% --- Panel 1: SG31 rotor angle over the whole 160 s -----------------------
nexttile; hold on;
[c1, n1] = stride(C.t, C.y(:,1), 4000);
[r1, ~]  = stride(R.t, R.y(:,1), 4000);
plot(c1.x, c1.y, '-', 'Color', col_cpp, 'LineWidth', 1.1, 'DisplayName', 'C++ stage-2 (run 008)');
plot(r1.x, r1.y, '--', 'Color', col_ref, 'LineWidth', 1.1, 'DisplayName', 'MATLAB golden reference');
draw_event_marks(ev_ref);
draw_reclose_marks(ev_cpp, ev_ref, col_cpp, col_ref, false);
xlim([0 160]);
xlabel('t [s]'); ylabel('$\delta_{SG31}$ [rad]');
title(sprintf('SG31 rotor angle: 0.29 $\\rightarrow$ %.0f rad (C++) / %.0f rad (golden)', ...
    C.y(end,1), R.y(end,1)));
legend('Location','northwest','Box','off');
grid on;

% --- Panel 2: speed deviation around the event window --------------------
nexttile; hold on;
twin = [55 125];
c2 = window(C.t, C.y(:,2), twin, 8000);
r2 = window(R.t, R.y(:,2), twin, 8000);
plot(c2.x, c2.y, '-', 'Color', col_cpp, 'LineWidth', 1.1, 'DisplayName', 'C++ stage-2 (run 008)');
plot(r2.x, r2.y, '--', 'Color', col_ref, 'LineWidth', 1.1, 'DisplayName', 'MATLAB golden reference');
xlim(twin); ylim([0.995 1.025]);
draw_event_marks(ev_ref);
draw_reclose_marks(ev_cpp, ev_ref, col_cpp, col_ref, true);
yline(1.0, ':', 'Color', [.55 .55 .55], 'HandleVisibility', 'off');
xlabel('t [s]'); ylabel('$\omega_{SG31}$ [pu]');
title('SG31 speed, event window (fault 60.00--60.15 s, reclose per engine)');
legend('Location','southwest','Box','off');
grid on;

% --- Panel 3: bus voltages 30 and 31, both engines -----------------------
nexttile; hold on;
c30 = stride(C.t, C.y(:,3), 4000); c31 = stride(C.t, C.y(:,4), 4000);
r30 = stride(R.t, R.y(:,3), 4000); r31 = stride(R.t, R.y(:,4), 4000);
plot(c30.x, c30.y, '-',  'Color', col_v30, 'LineWidth', 1.1, 'DisplayName', 'V30 C++');
plot(r30.x, r30.y, '--', 'Color', col_v30, 'LineWidth', 1.1, 'DisplayName', 'V30 golden');
plot(c31.x, c31.y, '-',  'Color', col_v31, 'LineWidth', 1.1, 'DisplayName', 'V31 C++');
plot(r31.x, r31.y, '--', 'Color', col_v31, 'LineWidth', 1.1, 'DisplayName', 'V31 golden');
draw_event_marks(ev_ref);
draw_reclose_marks(ev_cpp, ev_ref, col_cpp, col_ref, false);
xlim([0 160]);
xlabel('t [s]'); ylabel('V [pu]');
title('Bus 30 / 31 voltage: fault dip and recovery, both engines');
legend('Location','southwest','NumColumns',2,'Box','off');
grid on;

% --- Panel 4: event chronology of both engines ---------------------------
nexttile; hold on;
plot_lanes(ev_cpp, 0.45, col_cpp);
plot_lanes(ev_ref, -0.45, col_ref);
yline(0, ':', 'Color', [.55 .55 .55], 'HandleVisibility', 'off');
xlim([0 160]); ylim([-1.1 1.1]);
set(gca, 'YTick', []);
xlabel('t [s]');
title(sprintf('Event chronology: identical schedule except reclose (C++ %.3f s vs golden %.4f s)', ...
    ev_cpp.t(end), ev_ref.t(end)));
text(2, 0.85, 'C++ stage-2 (run 008)', 'Color', col_cpp, 'FontSize', 8);
text(2, -0.85, 'MATLAB golden reference', 'Color', col_ref, 'FontSize', 8);
grid on;

title(tl, 'NE39 160-s GFM study: C++ stage-2 trajectory vs MATLAB golden reference');
export_report(f, data_dir, 'cpp_sg_dynamics_compare.pdf', preview_png);

print_comparison(C, R, ev_cpp, ev_ref, n1);
end

% ---------------------------------------------------------------------------
% Readers and helpers
% ---------------------------------------------------------------------------

function S = read_traj(csv, cols)
%READ_TRAJ Column-selective streaming read of a trajectory export.
% The C++ export is ~370 MB / 113 columns; only t plus the four requested
% channels are kept, everything else is skipped by the textscan format.
if ~exist(csv, 'file')
    error('render_sg_dynamics_figures:missingData', 'trajectory not found: %s', csv);
end
fid = fopen(csv, 'r');
if fid < 0
    error('render_sg_dynamics_figures:openFailed', 'cannot open: %s', csv);
end
closer = onCleanup(@() fclose(fid));
hdr = strsplit(fgetl(fid), ',');
hdr = strtrim(hdr);
want = [{'t'} cols];
fmt = '';
keep = false(1, numel(hdr));
for k = 1:numel(hdr)
    if any(strcmp(hdr{k}, want))
        fmt = [fmt '%f']; %#ok<AGROW>
        keep(k) = true;
    else
        fmt = [fmt '%*f']; %#ok<AGROW>
    end
end
raw = textscan(fid, fmt, 'Delimiter', ',', 'CollectOutput', true);
M = raw{1};
kept = find(keep);                 % kept columns arrive in file order
pos = zeros(1, numel(want));
for k = 1:numel(want)
    pos(k) = find(kept == find(strcmp(hdr, want{k}), 1), 1);
end
S.t = M(:, pos(1));
S.y = M(:, pos(2:end));
end

function [o, n] = stride(t, y, maxpts)
%STRIDE Uniform decimation (presentation only, never smoothing).
n = max(1, ceil(numel(t) / maxpts));
o.x = t(1:n:end); o.y = y(1:n:end);
end

function o = window(t, y, twin, maxpts)
in = t >= twin(1) & t <= twin(2);
tw = t(in); yw = y(in);
o = stride(tw, yw, maxpts);
end

function draw_event_marks(ev)
for k = 1:numel(ev.t)
    xline(ev.t(k), ':', 'Color', [.62 .62 .62], 'LineWidth', 0.8, ...
        'HandleVisibility', 'off');
end
end

function draw_reclose_marks(ev_cpp, ev_ref, col_cpp, col_ref, label_them)
%DRAW_RECLOSE_MARKS Both reclose instants, one line per engine, every panel.
% The two engines close at different times (C++ guard close 100.499 s vs
% golden 119.5219 s), so both are marked explicitly rather than only the
% scheduled events.  Text labels are added only where the panel has room.
xline(ev_cpp.t(end), '-.', 'Color', col_cpp, 'LineWidth', 1.1, ...
    'HandleVisibility', 'off');
xline(ev_ref.t(end), '-.', 'Color', col_ref, 'LineWidth', 1.1, ...
    'HandleVisibility', 'off');
if label_them
    yl = ylim;
    yt = yl(2) - 0.055*diff(yl);
    text(ev_cpp.t(end) - 0.6, yt, sprintf('reclose C++ %.3f s', ev_cpp.t(end)), ...
        'Rotation', 90, 'HorizontalAlignment', 'right', 'FontSize', 7, 'Color', col_cpp);
    text(ev_ref.t(end) - 0.6, yt, sprintf('reclose golden %.4f s', ev_ref.t(end)), ...
        'Rotation', 90, 'HorizontalAlignment', 'right', 'FontSize', 7, 'Color', col_ref);
end
end

function plot_lanes(ev, y0, col)
for k = 1:numel(ev.t)
    plot([ev.t(k) ev.t(k)], [y0-0.22 y0+0.22], '-', 'Color', col, ...
        'LineWidth', 1.3, 'HandleVisibility', 'off');
    plot(ev.t(k), y0, 'o', 'MarkerSize', 5, 'MarkerFaceColor', col, ...
        'MarkerEdgeColor', 'none', 'HandleVisibility', 'off');
    text(ev.t(k), y0 + 0.28*(-1)^k, ev.label{k}, 'Rotation', 0, ...
        'HorizontalAlignment', 'center', 'FontSize', 7, 'Color', col);
end
end

function print_comparison(C, R, ev_cpp, ev_ref, n1)
%PRINT_COMPARISON Numbers computed from the plotted data only.
fprintf('== SG31 C++ run 008 vs golden reference ==\n');
fprintf('stride decimation: 1 of %d samples per curve (full-span panels)\n', n1);
fprintf('reclose: C++ %.4f s | golden %.4f s | gap %.4f s\n', ...
    ev_cpp.t(end), ev_ref.t(end), ev_ref.t(end) - ev_cpp.t(end));
fprintf('delta end: C++ %.3f rad | golden %.3f rad\n', C.y(end,1), R.y(end,1));
for name = {'C++','golden'}
    if strcmp(name{1}, 'C++'), t = C.t; y = C.y(:,1); else, t = R.t; y = R.y(:,1); end
    late = t >= 120;
    p = polyfit(t(late), y(late), 1);
    fprintf('delta drift rate t>=120s (%s): %.5f rad/s\n', name{1}, p(1));
end
% omega agreement in the settled window after both recloses
w = C.t >= 130;
rw = interp_ref(R, 2, C.t(w));
fprintf('omega t>=130s: C++ mean %.7f | golden mean %.7f | max |diff| %.2e pu\n', ...
    mean(C.y(w,2)), mean(rw), max(abs(C.y(w,2) - rw)));
% voltage agreement away from the fault dip
w = C.t >= 120;
for ch = 3:4
    rw = interp_ref(R, ch, C.t(w));
    fprintf('V bus%d t>=120s: max |diff| %.2e pu\n', 27+ch, max(abs(C.y(w,ch) - rw)));
end
end

function vq = interp_ref(R, ch, tq)
%INTERP_REF Interpolate a golden channel onto query times.
% The golden export carries anchor rows that repeat the previous timestamp
% exactly, so interp1 needs unique sample points (first occurrence wins).
[tu, ia] = unique(R.t, 'first');
vq = interp1(tu, R.y(ia, ch), tq, 'linear', 'extrap');
end

function f = report_figure(position)
f = figure('Visible','off','Color','w','Position',position,'PaperPositionMode','auto');
end

function export_report(f, data_dir, name, preview_png)
drawnow;
outfile = fullfile(data_dir, name);
try
    exportgraphics(f, outfile, 'ContentType', 'vector', 'BackgroundColor', 'white');
catch e
    warning('render_sg_dynamics_figures:exportFallback', ...
        'vector export failed for %s (%s); retrying auto content', name, e.identifier);
    exportgraphics(f, outfile, 'BackgroundColor', 'white');
    disp(['Fallback (auto content) used for: ' name]);
end
fprintf('wrote %s\n', outfile);
if nargin >= 4 && ~isempty(preview_png)
    exportgraphics(f, preview_png, 'BackgroundColor', 'white', 'Resolution', 110);
    fprintf('wrote preview %s\n', preview_png);
end
close(f);
end

function restore_fonts(old)
set(groot, 'defaultAxesFontName', old.axes, 'defaultTextFontName', old.text, ...
    'defaultLegendFontName', old.legend, 'defaultTextInterpreter', old.ti, ...
    'defaultAxesTickLabelInterpreter', old.ai, 'defaultLegendInterpreter', old.li, ...
    'defaultAxesGridLineStyle', old.gl, 'defaultAxesBox', old.bx);
end
