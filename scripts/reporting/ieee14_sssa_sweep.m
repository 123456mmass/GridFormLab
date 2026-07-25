function out = ieee14_sssa_sweep(opts)
%IEEE14_SSSA_SWEEP  SSSA stability sweep for the IEEE 14-bus 1-SG + 4-IBR
%   AGSI/AGSI++ GFL<->GFM switch study (project-owned base MATLAB only; NO
%   external solver).
%
%   out = ieee14_sssa_sweep(Name=Value) sweeps grid-strength knobs of the
%   composite IEEE14 1-SG (bus 1) + 4-IBR (buses 2,3,6,8) small-signal model
%   and records, at each swept point, the composite spectral abscissa
%   max(real(eig)) [1/s], the least-damped oscillatory damping ratio min_zeta
%   [-] and its frequency [Hz], and the number of right-half-plane eigenvalues
%   n_unstable (Re > 1e-6). It also computes the Padiyar two-area 1-SG + 3-IBR
%   contrast point (known small-signal UNSTABLE), writes a PNG figure and a
%   LaTeX table under docs/source/figures/switch_ieee14, and prints a concise
%   boundary summary.
%
%   Two knobs (each rebuilds and re-equilibrates the system consistently):
%     (1) sg_H_scale in opts.H_scales -- SG inertia/damping scale. Proxy for
%         effective IBR penetration / reduced system inertia.
%     (2) sg_X_scale in opts.X_scales -- SG internal-reactance scale (Xd, Xd',
%         Xq, Xq'). Proxy for effective electrical distance / grid-coupling
%         strength: kX > 1 weakens the SG's synchronising coupling. Terminal
%         V,I,P,Q are fixed by the audited power flow, so the equilibrium is
%         re-derived consistently (Te = P is invariant at Ra = 0).
%
%   Models (same as the Padiyar 4-machine study): Padiyar model-1.1 manual SG
%   (constant field, NO AVR/PSS) via ibr.padiyar_sg_unit + reduced-6
%   ibr.SwitchableIbr6 IBRs. Linearisation is a central-difference Jacobian of
%   the SAME differential/algebraic RHS integrated by ibr.padiyar_switch_tds
%   (single source of truth): A = f_x - f_y*(g_y\g_x).
%
%   Classification: ASSUMED_DIAGNOSTIC study. This is a diagnostic sweep, not a
%   production stability acceptance gate. No parameter, tolerance, event, or
%   result is tuned to obtain any particular verdict.
%
%   Name=Value:
%     H_scales    (1,:) double  sg_H_scale sweep values
%     X_scales    (1,:) double  sg_X_scale sweep values
%     index_mode  (1,1) string  AGSI index mode ("agsi_pp" default)
%     save        (1,1) logical  write figure + table (default true)
%     fig_dir     (1,1) string  output dir (default docs/source/figures/switch_ieee14)
%
%   Returns struct OUT with the full numeric sweep, the Padiyar contrast, the
%   boundary finding, and the written artifact paths.

arguments
    opts.H_scales (1,:) double  = [2 1.5 1 0.7 0.5 0.3 0.2 0.1 0.05 0.02]
    opts.X_scales (1,:) double  = [1 1.5 2 3 5 8 12 16 20]
    opts.index_mode (1,1) string = "agsi_pp"
    opts.save (1,1) logical = true
    opts.fig_dir (1,1) string = ""
end

pf_init_paths();
here = fileparts(mfilename('fullpath'));            % scripts/reporting
repo = fileparts(fileparts(here));                  % repository root
if strlength(opts.fig_dir) == 0
    fig_dir = fullfile(repo, 'docs', 'source', 'figures', 'switch_ieee14');
else
    fig_dir = char(opts.fig_dir);
end
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

TOL_UNSTABLE = 1e-6;   % Re > TOL_UNSTABLE counts as an RHP mode (matches padiyar_switch_pf_sssa)

% ---------------------------------------------------------------------------
% Sweep 1: SG inertia/damping (sg_H_scale) -- penetration / low-inertia proxy
% ---------------------------------------------------------------------------
Hs = opts.H_scales(:).';
nH = numel(Hs);
H_maxRe = nan(1,nH); H_zeta = nan(1,nH); H_freq = nan(1,nH); H_nun = nan(1,nH);
fprintf('\n=== IEEE14 1-SG + 4-IBR SSSA sweep (index_mode=%s) ===\n', opts.index_mode);
fprintf('\n[Sweep 1] SG inertia/damping knob sg_H_scale\n');
fprintf('  %-10s %-14s %-12s %-12s %-10s\n','H_scale','max Re [1/s]','min zeta','f [Hz]','n_unstbl');
for i = 1:nH
    try
        sys = ibr.build_ieee14_switch_system(index_mode=opts.index_mode, sg_H_scale=Hs(i));
        r   = ibr.padiyar_switch_pf_sssa(sys);
        H_maxRe(i) = max(real(r.eig));
        H_zeta(i)  = r.min_zeta;
        H_freq(i)  = r.min_zeta_freq;
        H_nun(i)   = r.n_unstable;
    catch ME
        fprintf(2, '  H_scale=%.3g FAILED: %s (recorded NaN, continuing)\n', Hs(i), ME.message);
        continue;
    end
    fprintf('  %-10.3g %-+14.4e %-12.4f %-12.4f %-10d\n', ...
        Hs(i), H_maxRe(i), H_zeta(i), H_freq(i), H_nun(i));
end

% ---------------------------------------------------------------------------
% Sweep 2: SG internal reactance (sg_X_scale) -- grid-coupling strength knob
% ---------------------------------------------------------------------------
Xs = opts.X_scales(:).';
nX = numel(Xs);
X_maxRe = nan(1,nX); X_zeta = nan(1,nX); X_freq = nan(1,nX); X_nun = nan(1,nX);
fprintf('\n[Sweep 2] SG internal-reactance (coupling-strength) knob sg_X_scale\n');
fprintf('  %-10s %-14s %-12s %-12s %-10s\n','X_scale','max Re [1/s]','min zeta','f [Hz]','n_unstbl');
for i = 1:nX
    try
        sys = ibr.build_ieee14_switch_system(index_mode=opts.index_mode, sg_X_scale=Xs(i));
        r   = ibr.padiyar_switch_pf_sssa(sys);
        X_maxRe(i) = max(real(r.eig));
        X_zeta(i)  = r.min_zeta;
        X_freq(i)  = r.min_zeta_freq;
        X_nun(i)   = r.n_unstable;
    catch ME
        fprintf(2, '  X_scale=%.3g FAILED: %s (recorded NaN, continuing)\n', Xs(i), ME.message);
        continue;
    end
    fprintf('  %-10.3g %-+14.4e %-12.4f %-12.4f %-10d\n', ...
        Xs(i), X_maxRe(i), X_zeta(i), X_freq(i), X_nun(i));
end

% ---------------------------------------------------------------------------
% Contrast: Padiyar two-area 1-SG + 3-IBR composite (known UNSTABLE)
% ---------------------------------------------------------------------------
P = struct('maxRe',NaN,'zeta',NaN,'freq',NaN,'n_unstable',NaN);
try
    sysP = ibr.build_padiyar_switch_system(index_mode=opts.index_mode);
    rP   = ibr.padiyar_switch_pf_sssa(sysP);
    P.maxRe = max(real(rP.eig));
    P.zeta  = rP.min_zeta;
    P.freq  = rP.min_zeta_freq;
    P.n_unstable = rP.n_unstable;
catch ME
    fprintf(2, '  Padiyar contrast FAILED: %s\n', ME.message);
end
fprintf('\n[Contrast] Padiyar two-area 1-SG+3-IBR: max Re=%+.4e 1/s, n_unstable=%d\n', ...
    P.maxRe, P.n_unstable);

% ---------------------------------------------------------------------------
% Boundary finding
% ---------------------------------------------------------------------------
[H_bnd, H_has] = first_unstable(Hs, H_nun, 'descend');   % inertia lowered => scan 2 -> 0.02
[X_bnd, X_has] = first_unstable(Xs, X_nun, 'ascend');    % coupling weakened => scan 1 -> large
boundary_found = H_has || X_has;
if H_has
    H_desc = sprintf('inertia sweep: n_unstable>0 first at sg_H_scale=%.3g', H_bnd);
else
    H_desc = 'inertia sweep: robustly stable (n_unstable=0 across the sweep)';
end
if X_has
    X_desc = sprintf('coupling sweep: n_unstable>0 first at sg_X_scale=%.3g', X_bnd);
else
    X_desc = 'coupling sweep: robustly stable (n_unstable=0 across the sweep)';
end

fprintf('\n---- SUMMARY ----\n');
fprintf('  IEEE14 %s\n', H_desc);
fprintf('  IEEE14 %s\n', X_desc);
if boundary_found
    fprintf('  BOUNDARY FOUND on at least one IEEE14 knob (see above).\n');
else
    fprintf('  IEEE14: robustly stable across the sweep (no boundary found on either knob).\n');
end
fprintf('  Padiyar two-area contrast: max Re=%+.4e 1/s, %s.\n', P.maxRe, ...
    ternary(P.n_unstable>0, sprintf('UNSTABLE (%d RHP)', P.n_unstable), 'stable'));

% ---------------------------------------------------------------------------
% Assemble output struct
% ---------------------------------------------------------------------------
out = struct();
out.index_mode = char(opts.index_mode);
out.tol_unstable = TOL_UNSTABLE;
out.H_scales = Hs; out.H_maxRe = H_maxRe; out.H_minzeta = H_zeta; out.H_freq = H_freq; out.H_nun = H_nun;
out.X_scales = Xs; out.X_maxRe = X_maxRe; out.X_minzeta = X_zeta; out.X_freq = X_freq; out.X_nun = X_nun;
out.padiyar = P;
out.boundary_found = boundary_found;
out.summary = sprintf('%s; %s', H_desc, X_desc);
out.fig_path = '';
out.tex_path = '';

% ---------------------------------------------------------------------------
% Figure + table
% ---------------------------------------------------------------------------
if opts.save
    out.fig_path = fullfile(fig_dir, 'sssa_sweep.png');
    make_figure(out, out.fig_path);
    out.tex_path = fullfile(fig_dir, 'table_sssa_sweep.tex');
    write_table(out, out.tex_path);
    fprintf('\n  figure: %s\n  table : %s\n', out.fig_path, out.tex_path);
end
end

% =========================================================================
function [bnd, has] = first_unstable(param, nun, order)
% First swept parameter value (in the given scan order) with n_unstable > 0.
has = any(nun > 0);
bnd = NaN;
if ~has, return; end
[~, ord] = sort(param, order);
for k = ord
    if nun(k) > 0, bnd = param(k); return; end
end
end

function y = ternary(c, a, b)
if c, y = a; else, y = b; end
end

% =========================================================================
function make_figure(out, path)
% Figure lettering matches the report body text (Times New Roman, 12 pt); the
% figure is sized in INCHES equal to the report text width so the PNG is placed
% at 1:1 scale. Axis labels use subscript notation (H_x, k_X), not the raw code
% option names. REPORT_FIGURE_STYLE_CONTRACT.
fig = figure('Visible','off','Color','w','Units','inches','Position',[1 1 6.27 6.4], ...
    'DefaultAxesFontName','Times New Roman','DefaultAxesFontSize',11, ...
    'DefaultTextFontName','Times New Roman','DefaultTextFontSize',11);
tl = tiledlayout(fig, 2, 2, 'Padding','compact','TileSpacing','loose');
title(tl, {'IEEE 14-bus 1-SG + 4-IBR SSSA sweep (AGSI++ switch study)', ...
    'Padiyar model-1.1 manual SG + reduced-6 SwitchableIbr6 IBRs'}, ...
    'Interpreter','tex','FontName','Times New Roman','FontSize',12,'FontWeight','bold');

% The Padiyar two-area contrast is drawn as a plain reference line and named in
% ONE legend only: an in-axes text label would overprint the panel titles.
pad_lbl = sprintf('Padiyar two-area: %+.3f (UNSTABLE)', out.padiyar.maxRe);

% (a) max Re vs inertia scale H_x
ax = nexttile(tl); hold(ax,'on'); grid(ax,'on'); style_ax(ax);
hI = plot(ax, out.H_scales, out.H_maxRe, '-o', 'LineWidth',1.5, 'MarkerFaceColor','w', ...
    'DisplayName','IEEE 14-bus');
yline(ax, 0, 'k-', 'LineWidth',1.0);
hP = plot(ax, NaN, NaN, 'r--', 'LineWidth',1.2, 'DisplayName',pad_lbl);
if isfinite(out.padiyar.maxRe)
    yline(ax, out.padiyar.maxRe, 'r--', 'LineWidth',1.2);
    ylim(ax, [min(0,1.2*min(out.H_maxRe)) 1.25*out.padiyar.maxRe]);
end
set(ax,'XScale','log'); xlabel(ax,'inertia scale H_{\times}');
ylabel(ax,'max Re(\lambda) [1/s]');
title(ax,'(a) max Re vs inertia','FontSize',11);
lg = legend(ax,[hI hP],'Orientation','horizontal','Box','off');
set(lg,'FontName','Times New Roman','FontSize',10);
lg.Layout.Tile = 'south';   % one shared legend under the whole layout

% (b) min zeta vs inertia scale
ax = nexttile(tl); hold(ax,'on'); grid(ax,'on'); style_ax(ax);
plot(ax, out.H_scales, out.H_minzeta, '-o', 'LineWidth',1.5, 'MarkerFaceColor','w');
yline(ax, 0, 'k-', 'LineWidth',1.0);
set(ax,'XScale','log'); xlabel(ax,'inertia scale H_{\times}');
ylabel(ax,'min damping ratio \zeta [-]');
title(ax,'(b) min \zeta vs inertia','FontSize',11);

% (c) max Re vs coupling scale k_X
ax = nexttile(tl); hold(ax,'on'); grid(ax,'on'); style_ax(ax);
plot(ax, out.X_scales, out.X_maxRe, '-s', 'LineWidth',1.5, 'MarkerFaceColor','w', 'Color',[0.85 0.33 0.10]);
yline(ax, 0, 'k-', 'LineWidth',1.0);
if isfinite(out.padiyar.maxRe)
    yline(ax, out.padiyar.maxRe, 'r--', 'LineWidth',1.2);
    ylim(ax, [min(0,1.2*min(out.X_maxRe)) 1.25*out.padiyar.maxRe]);
end
set(ax,'XScale','log'); xlabel(ax,'reactance scale k_X (weaker coupling \rightarrow)');
ylabel(ax,'max Re(\lambda) [1/s]');
title(ax,'(c) max Re vs coupling','FontSize',11);

% (d) min zeta vs coupling scale k_X
ax = nexttile(tl); hold(ax,'on'); grid(ax,'on'); style_ax(ax);
plot(ax, out.X_scales, out.X_minzeta, '-s', 'LineWidth',1.5, 'MarkerFaceColor','w', 'Color',[0.85 0.33 0.10]);
yline(ax, 0, 'k-', 'LineWidth',1.0);
set(ax,'XScale','log'); xlabel(ax,'reactance scale k_X (weaker coupling \rightarrow)');
ylabel(ax,'min damping ratio \zeta [-]');
title(ax,'(d) min \zeta vs coupling','FontSize',11);

exportgraphics(fig, path, 'Resolution', 300);
close(fig);
end

function style_ax(ax)
set(ax,'FontName','Times New Roman','FontSize',11);
end

% =========================================================================
function write_table(out, path)
fid = fopen(path,'w'); z = onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid, '%% Generated by scripts/reporting/ieee14_sssa_sweep.m. Do not edit by hand.\n');
fprintf(fid, '%% IEEE 14-bus 1-SG + 4-IBR AGSI++ switch study -- SSSA stability sweep.\n');
fprintf(fid, '%% Classification: ASSUMED_DIAGNOSTIC (project-owned base MATLAB; no external solver).\n');
fprintf(fid, '\\begin{tabular}{l r r r r l}\n\\toprule\n');
fprintf(fid, 'Sweep & Param & $\\max\\,\\mathrm{Re}(\\lambda)$ & $\\zeta_{\\min}$ & $f$ & Verdict \\\\\n');
fprintf(fid, ' & & (1/s) & (--) & (Hz) & ($n_{\\mathrm{unstable}}$) \\\\ \\midrule\n');

% Sweep 1: inertia
fprintf(fid, '\\multicolumn{6}{l}{\\emph{IEEE14 inertia sweep} ($H_{\\times}$ scales SG $H$ and $D$; $k_X=1$)} \\\\\n');
for i = 1:numel(out.H_scales)
    fprintf(fid, '$H_{\\times}=%.2f$ & %.3g & %s & %s & %s & %s \\\\\n', ...
        out.H_scales(i), out.H_scales(i), fmt_e(out.H_maxRe(i)), fmt_f(out.H_minzeta(i)), ...
        fmt_f(out.H_freq(i)), verdict(out.H_nun(i)));
end
fprintf(fid, '\\midrule\n');

% Sweep 2: coupling
fprintf(fid, '\\multicolumn{6}{l}{\\emph{IEEE14 grid-coupling sweep} ($k_X$ scales $X_d,X_d'',X_q,X_q''$; $H_{\\times}=1$)} \\\\\n');
for i = 1:numel(out.X_scales)
    fprintf(fid, '$k_X=%.2f$ & %.3g & %s & %s & %s & %s \\\\\n', ...
        out.X_scales(i), out.X_scales(i), fmt_e(out.X_maxRe(i)), fmt_f(out.X_minzeta(i)), ...
        fmt_f(out.X_freq(i)), verdict(out.X_nun(i)));
end
fprintf(fid, '\\midrule\n');

% Contrast
fprintf(fid, '\\multicolumn{6}{l}{\\emph{Contrast: Padiyar two-area} 1-SG+3-IBR (weak-tie topology)} \\\\\n');
fprintf(fid, 'Padiyar & --- & %s & %s & %s & %s \\\\\n', ...
    fmt_e(out.padiyar.maxRe), fmt_f(out.padiyar.zeta), fmt_f(out.padiyar.freq), verdict(out.padiyar.n_unstable));
fprintf(fid, '\\bottomrule\n\\end{tabular}\n');
end

function s = fmt_e(v)
%FMT_E  Scientific value as a*10^n (REPORT rule: never print MATLAB's "e-08"
%   exponent form in a report table; always typeset $a\times10^{n}$).
if isnan(v)
    s = '---'; return;
end
if v == 0
    s = '$0$'; return;
end
n = floor(log10(abs(v)));
a = v/10^n;
if abs(a) >= 9.9995   % rounding carried the mantissa up to 10.000
    a = a/10; n = n + 1;
end
s = sprintf('$%+.3f\\times10^{%d}$', a, n);
end
function s = fmt_f(v)
if isnan(v), s = '---'; else, s = sprintf('%.4f', v); end
end
function s = verdict(n)
if isnan(n), s = '---';
elseif n > 0, s = sprintf('\\textbf{UNSTABLE} (%d)', n);
else, s = 'stable (0)';
end
end
