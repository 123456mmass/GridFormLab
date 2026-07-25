function ieee14_switching_map()
%IEEE14_SWITCHING_MAP  Fault (and load-step) switching-outcome map for the
%   IEEE 14-bus 1-SG + 4-IBR AGSI++ GFL<->GFM mode-switch study.
%
%   Sweeps a TEMPORARY three-phase shunt fault over (fault reactance X_f x
%   fault bus) with NO synchronous-generator trip and classifies each grid
%   point by the outcome of the mixed SG+IBR time-domain simulation:
%
%     ride-through : no IBR switched mode; the composite stayed GFL and the
%                    network recovered after the fault was cleared.
%     index-switch : at least one IBR formed the grid (GFL->GFM) because its
%                    AGSI++ index crossed the switch-on line (Gamma_on).
%     diverge      : the governor-less, current-limited composite could not
%                    ride the disturbance -- the TDS diverged (states left the
%                    model validity domain) OR the network FAILED TO RECOVER
%                    after clearing (post-clear min|V| < 0.25 pu).
%     non-converged: the corrector did not fully converge (or the run threw).
%                    Fail-closed: no physical outcome is claimed for the point.
%
%   Classification rule (decided in this order):
%       if     out.diverged                          -> 'diverge'
%       elseif ~out.newton_all_converged             -> 'non-converged'
%       elseif min|V| for t >= fault_clear < 0.25    -> 'collapse'   (diverge class)
%       elseif sum(out.dev_n_switch) >= 1            -> 'index-switch'
%       else                                         -> 'ride-through'
%
%   The collapse test deliberately uses the POST-CLEAR minimum voltage: while a
%   low-impedance shunt fault is applied the faulted bus is pulled down by
%   construction, so the during-fault sag says nothing about whether the system
%   survives. The during-fault minimum is still reported in the table for
%   reference. Convergence is part of the verdict, so an untrustworthy
%   trajectory can never be published as a clean ride-through or switch.
%
%   Fault sweep grid:
%       fault_Zf  in  j*{0.02, 0.05, 0.10, 0.20, 0.30, 0.50}  (x-axis;
%                     smaller |X_f| = lower fault impedance = MORE severe)
%       fault_bus in  {3, 4, 5, 9}  (y-axis; IBR bus 3 + load buses 4,5,9)
%       fault_on = 1.00 s, fault_clear = 1.15 s, sg_trip_time = Inf,
%       T = 4 s, dt = 2e-3 s, index_mode = "agsi_pp".
%
%   A second, small load-step sweep (step_factor in {0.1,0.3,0.5} at bus 4,
%   no SG trip) is also run and reported.
%
%   Products written to docs/source/figures/switch_ieee14/ :
%       switching_map.png       - categorical outcome heatmap (X_f x bus),
%                                 min|V| annotated per cell, with a legend.
%       table_switching_map.tex - per grid-point outcome + min|V| + #switches
%                                 (+ the load-step sweep as a second block).
%
%   IMPORTANT: sys.devs (and the SG unit) are handle objects that a run
%   MUTATES; this script REBUILDS the system fresh for every grid point so
%   the sweep points are mutually independent.
%
%   Project-owned base-MATLAB only: ibr.build_ieee14_switch_system +
%   ibr.padiyar_switch_tds (Padiyar model-1.1 manual/no-AVR SG via
%   ibr.padiyar_sg_unit + reduced-6 ibr.SwitchableIbr6 IBRs). No external
%   solver, no reference program. Classification: ASSUMED_DIAGNOSTIC study
%   script.
%
%   Run:
%       pf_init_paths; addpath('scripts/reporting'); ieee14_switching_map

pf_init_paths();

% Keep the batch console readable: ibr.padiyar_switch_tds intentionally emits
% these two documented warnings on severe (diverging / non-converging) grid
% points -- those points are exactly what this sweep is meant to classify. Only
% those two IDs are silenced (any OTHER warning stays visible), and the state is
% restored on exit.
ws = warning('off','ibr:padiyar_switch_tds:diverged');
warning('off','ibr:padiyar_switch_tds:notConverged');
restore_w = onCleanup(@() warning(ws)); %#ok<NASGU>

outdir = fullfile('docs','source','figures','switch_ieee14');
if ~exist(outdir,'dir'); mkdir(outdir); end
fig_path = fullfile(outdir,'switching_map.png');
tex_path = fullfile(outdir,'table_switching_map.tex');

% ------------------------------------------------------------------ grid ---
Zf_list  = 1i*[0.02 0.05 0.10 0.20 0.30 0.50];   % x-axis fault impedances
Zf_mag   = imag(Zf_list);                         % reactance magnitude (pu)
bus_list = [3 4 5 9];                             % y-axis fault buses
nZ = numel(Zf_list); nB = numel(bus_list);

fault_on = 1.00; fault_clear = 1.15; Tend = 4; dt = 2e-3;

codes  = zeros(nB,nZ);      % 1 ride-through | 2 index-switch | 3 diverge/collapse | 4 non-converged/error
minVm  = nan(nB,nZ);        % min|V| over the WHOLE run (includes the during-fault sag)
minVp  = nan(nB,nZ);        % min|V| AFTER the fault is cleared (recovery test)
nswm   = zeros(nB,nZ);
convm  = false(nB,nZ);
labels = strings(nB,nZ);

fprintf('\n==== IEEE14 1-SG+4-IBR AGSI++ switching-outcome map =============\n');
fprintf('temporary 3-phase fault sweep: X_f x fault_bus\n');
fprintf('fault_on=%.2fs  fault_clear=%.2fs  sg_trip=Inf (no trip)  T=%g  dt=%g\n', ...
    fault_on, fault_clear, Tend, dt);
fprintf('collapse test uses the POST-CLEAR minimum voltage (t >= %.2fs), not the during-fault sag\n', ...
    fault_clear);
fprintf('buses %s ; X_f(pu) %s\n\n', mat2str(bus_list), mat2str(Zf_mag));

for i = 1:nB
    fb = bus_list(i);
    for j = 1:nZ
        zf = Zf_list(j);
        % REBUILD fresh -- sys.devs are handle objects mutated by a run.
        sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp");
        [code,label,minV,minV_post,nsw,conv,err] = run_point(sys, fault_clear, ...
            'T',Tend,'dt',dt,'sg_trip_time',inf, ...
            'fault_on',fault_on,'fault_clear',fault_clear, ...
            'fault_bus',fb,'fault_Zf',zf);
        codes(i,j)=code; labels(i,j)=label; minVm(i,j)=minV; minVp(i,j)=minV_post;
        nswm(i,j)=nsw; convm(i,j)=conv;
        fprintf('  bus %2d  X_f=%.2f -> %-14s  min|V|=%6.3f  min|V|post=%6.3f  switches=%d  conv=%d%s\n', ...
            fb, imag(zf), label, minV, minV_post, nsw, conv, err);
    end
end

% ------------------------------------------------ optional load-step sweep --
step_factors = [0.10 0.30 0.50];
step_bus = 4; step_on = 1.00;
nS = numel(step_factors);
scodes = zeros(1,nS); sminV = nan(1,nS); sminVp = nan(1,nS); snsw = zeros(1,nS);
sconv = false(1,nS); slabels = strings(1,nS);

fprintf('\n==== load-step sweep (permanent step @ bus %d, t=%.2fs, no SG trip) ====\n', ...
    step_bus, step_on);
for j = 1:nS
    sf = step_factors(j);
    sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp");
    % The step is PERMANENT (never cleared), so the recovery window starts a
    % short settling time after it is applied.
    [c,l,mv,mvp,ns,cv,er] = run_point(sys, step_on+0.5, ...
        'T',Tend,'dt',dt,'sg_trip_time',inf, ...
        'step_on',step_on,'step_bus',step_bus,'step_factor',sf);
    scodes(j)=c; slabels(j)=l; sminV(j)=mv; sminVp(j)=mvp; snsw(j)=ns; sconv(j)=cv;
    fprintf('  +%3.0f%% load @bus%d -> %-14s  min|V|=%6.3f  min|V|post=%6.3f  switches=%d  conv=%d%s\n', ...
        100*sf, step_bus, l, mv, mvp, ns, cv, er);
end

% ------------------------------------------------------------- products ----
make_figure(fig_path, Zf_mag, bus_list, codes, minVp);
write_table(tex_path, Zf_mag, bus_list, labels, minVm, minVp, nswm, convm, ...
    step_factors, step_bus, slabels, sminV, sminVp, snsw, sconv);

% ---------------------------------------------------- text outcome grid ----
sym = ["R" "S" "D" "X"];
fprintf('\n---- outcome grid (rows = fault bus, cols = fault X_f in pu) ----\n');
hdr = '';
for j = 1:nZ, hdr = [hdr sprintf('%9s', sprintf('X_f=%.2f', Zf_mag(j)))]; end %#ok<AGROW>
fprintf('%-10s%s\n', '', hdr);
for i = 1:nB
    row = '';
    for j = 1:nZ, row = [row sprintf('%9s', sym(codes(i,j)))]; end %#ok<AGROW>
    fprintf('%-10s%s\n', sprintf('bus %d', bus_list(i)), row);
end
fprintf(['legend: R = ride-through | S = index-switch (GFL->GFM) | ' ...
    'D = diverge/collapse | X = non-converged or error (fail-closed, no outcome claimed)\n']);

fprintf('\nload-step grid (@bus %d):\n', step_bus);
for j = 1:nS
    fprintf('  +%3.0f%% -> %s\n', 100*step_factors(j), sym(scodes(j)));
end

% tally
nR = nnz(codes==1); nSw = nnz(codes==2); nD = nnz(codes==3); nX = nnz(codes==4);
fprintf('\ntally (fault sweep, %d points): ride-through=%d  index-switch=%d  diverge/collapse=%d  non-converged=%d\n', ...
    nB*nZ, nR, nSw, nD, nX);

% ------------------------------------------------------ confirm outputs ----
fig_ok = isfile(fig_path);
tex_ok = isfile(tex_path);
fprintf('\nSWITCH_MAP_FIGURE: exists=%d  %s\n', fig_ok, fig_path);
fprintf('SWITCH_MAP_TABLE : exists=%d  %s\n', tex_ok, tex_path);
if ~(fig_ok && tex_ok)
    error('ieee14_switching_map:outputs', ...
        'expected outputs missing (fig=%d tex=%d)', fig_ok, tex_ok);
end
fprintf('IEEE14_SWITCHING_MAP_DONE\n');
end

% =========================================================================
function [code,label,minV,minV_post,nsw,conv,errtxt] = run_point(sys, t_post, varargin)
%RUN_POINT  Run one TDS grid point and classify it.
%   T_POST is the time from which the POST-EVENT (recovery) minimum voltage is
%   measured: the collapse test must not be decided by the intentional sag that
%   exists WHILE the shunt fault is applied, only by whether the network fails
%   to recover after the disturbance is removed. A non-converged trajectory, and
%   an unexpected throw, are kept in their OWN class (fail-closed) instead of
%   being reported as a clean physical outcome.
errtxt = '';
try
    out  = ibr.padiyar_switch_tds(sys, varargin{:});
    minV = min(out.Vmin);                                 % including the fault window
    keep = out.tgrid >= t_post;
    if any(keep), minV_post = min(out.Vmin(keep)); else, minV_post = minV; end
    nsw  = sum(out.dev_n_switch);
    conv = logical(out.newton_all_converged);
    if out.diverged
        code = 3; label = "diverge";                      % states left the validity domain
    elseif ~conv
        code = 4; label = "non-converged";                % untrustworthy: no outcome claimed
    elseif minV_post < 0.25
        code = 3; label = "collapse";                     % failed to recover after clearing
    elseif nsw >= 1
        code = 2; label = "index-switch";                 % AGSI++ commanded GFL->GFM
    else
        code = 1; label = "ride-through";                 % stayed GFL, recovered
    end
catch ME
    code = 4; label = "error"; minV = NaN; minV_post = NaN; nsw = 0; conv = false;
    errtxt = sprintf('  [ERROR: %s]', ME.message);
end
end

% =========================================================================
function make_figure(fig_path, Zf_mag, bus_list, codes, minVp)
nZ = numel(Zf_mag); nB = numel(bus_list);
cmap = [0.20 0.70 0.34;    % 1 ride-through        (green)
        0.00 0.45 0.74;    % 2 index-switch        (blue)
        0.85 0.20 0.20;    % 3 diverge / collapse  (red)
        0.55 0.55 0.55];   % 4 non-converged/error (grey, fail-closed)

% Figure lettering matches the report body text (Times New Roman, 12 pt) and the
% figure is sized in INCHES equal to the report text width, so the PNG is placed
% at 1:1 scale. REPORT_FIGURE_STYLE_CONTRACT.
fig = figure('Color','w','Units','inches','Position',[1 1 6.27 3.3],'Visible','off', ...
    'DefaultAxesFontName','Times New Roman','DefaultAxesFontSize',12, ...
    'DefaultTextFontName','Times New Roman','DefaultTextFontSize',12);
ax  = axes(fig); hold(ax,'on');
set(ax,'FontName','Times New Roman','FontSize',12);
imagesc(ax, 1:nZ, 1:nB, codes);
colormap(ax, cmap); clim(ax, [0.5 4.5]);
set(ax,'YDir','normal','Layer','top','TickLength',[0 0]);
ax.XTick = 1:nZ; ax.XTickLabel = arrayfun(@(x)sprintf('%.2f',x), Zf_mag, 'uni',0);
ax.YTick = 1:nB; ax.YTickLabel = arrayfun(@(x)sprintf('%d',x),  bus_list,'uni',0);
xlabel(ax,'fault reactance X_f (pu)   [ \leftarrow smaller = more severe ]');
ylabel(ax,'fault bus');
title(ax,{'IEEE 14-bus AGSI++ switching-outcome map', ...
    '3\phi fault 1.00-1.15 s, no SG trip'},'FontSize',12);

% white cell separators
for gx = 0.5:1:nZ+0.5, xline(ax,gx,'Color',[1 1 1],'LineWidth',0.75); end
for gy = 0.5:1:nB+0.5, yline(ax,gy,'Color',[1 1 1],'LineWidth',0.75); end

% annotate the POST-CLEAR min|V| per cell (the quantity the collapse test uses)
for i = 1:nB
    for j = 1:nZ
        if codes(i,j)==1, tc = [0 0 0]; else, tc = [1 1 1]; end
        if isnan(minVp(i,j)), s = 'n/a'; else, s = sprintf('%.2f', minVp(i,j)); end
        text(ax, j, i, s, 'HorizontalAlignment','center', ...
            'VerticalAlignment','middle','Color',tc, ...
            'FontName','Times New Roman','FontSize',10,'FontWeight','bold');
    end
end
axis(ax,[0.5 nZ+0.5 0.5 nB+0.5]);

% legend via off-axis dummy patches
h1 = patch(ax,NaN,NaN,cmap(1,:),'DisplayName','ride-through (stayed GFL)');
h2 = patch(ax,NaN,NaN,cmap(2,:),'DisplayName','index-switch (GFL\rightarrowGFM)');
h3 = patch(ax,NaN,NaN,cmap(3,:),'DisplayName','diverge / no post-clear recovery');
h4 = patch(ax,NaN,NaN,cmap(4,:),'DisplayName','non-converged (fail-closed)');
lg = legend(ax,[h1 h2 h3 h4],'Location','eastoutside','Box','on');
set(lg,'FontName','Times New Roman','FontSize',10);
title(lg,'annotation = min|V| after clearing');

exportgraphics(fig, fig_path, 'Resolution', 300);
close(fig);
end

% =========================================================================
function write_table(path, Zf_mag, bus_list, labels, minVm, minVp, nswm, convm, ...
        step_factors, step_bus, slabels, sminV, sminVp, snsw, sconv)
fid = fopen(path,'w');
if fid < 0, error('ieee14_switching_map:tex','cannot open %s for writing', path); end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
yn = @(b) ternary(logical(b),'yes','no');

fprintf(fid,'%% Generated by scripts/reporting/ieee14_switching_map.m. Do not edit by hand.\n');
fprintf(fid,'%% IEEE 14-bus 1-SG + 4-IBR AGSI++ switching-outcome map.\n');
fprintf(fid,'%% Temporary 3-phase fault t in [1.00,1.15] s, no SG trip, T=4 s, dt=2e-3 s.\n');
fprintf(fid,'%% Outcome is decided by the POST-CLEAR minimum voltage (t >= fault_clear);\n');
fprintf(fid,'%% the during-fault sag is reported separately and is NOT a collapse criterion.\n');

% ---- main fault sweep ----
fprintf(fid,'\\begin{tabular}{r r l r r r c}\\toprule\n');
fprintf(fid,['$X_f$ (pu) & Fault bus & Outcome & $\\min|V|$ (pu) & $\\min|V|_{\\text{post}}$ (pu) ' ...
    '& Total switches & Newton conv.\\\\\n']);
fprintf(fid,' & & & (incl.\\ fault) & (after clearing) & & \\\\\\midrule\n');
nB = numel(bus_list); nZ = numel(Zf_mag);
for i = 1:nB
    for j = 1:nZ
        fprintf(fid,'%.2f & %d & %s & %s & %s & %d & %s\\\\\n', ...
            Zf_mag(j), bus_list(i), char(labels(i,j)), fmt_v(minVm(i,j)), ...
            fmt_v(minVp(i,j)), nswm(i,j), yn(convm(i,j)));
    end
    if i < nB, fprintf(fid,'\\midrule\n'); end
end
fprintf(fid,'\\bottomrule\n\\end{tabular}\n');

% ---- load-step sweep ----
fprintf(fid,'\n\\vspace{1em}\n\n');
fprintf(fid,'\\begin{tabular}{r r l r r r c}\\toprule\n');
fprintf(fid,['Load step & Step bus & Outcome & $\\min|V|$ (pu) & $\\min|V|_{\\text{post}}$ (pu) ' ...
    '& Total switches & Newton conv.\\\\\\midrule\n']);
for j = 1:numel(step_factors)
    fprintf(fid,'$+%.0f\\%%$ & %d & %s & %s & %s & %d & %s\\\\\n', ...
        100*step_factors(j), step_bus, char(slabels(j)), fmt_v(sminV(j)), ...
        fmt_v(sminVp(j)), snsw(j), yn(sconv(j)));
end
fprintf(fid,'\\bottomrule\n\\end{tabular}\n');
end

% =========================================================================
function s = fmt_v(v)
if isnan(v), s = 'n/a'; else, s = sprintf('%.3f', v); end
end

% =========================================================================
function r = ternary(cnd,a,b)
if cnd, r = a; else, r = b; end
end
