function out = generate_ieee14_decision_figure(opts)
%GENERATE_IEEE14_DECISION_FIGURE  One-page switching-decision evidence.
%
%   generate_ieee14_decision_figure()
%   generate_ieee14_decision_figure(result_file="...", output="...")
%
% Nine panels on one page, one shared time axis, identical event markers on every
% panel, so the reader can read every index at the instants the supervisor
% commanded a mode change:
%
%   (a) S = sat[0,1](0.5 J_V + 0.5 J_f) with the Gamma_on / Gamma_off thresholds
%   (b) J_V     (d) J_R  [system]   (f) J_lock    (h) GFL/GFM mode
%   (c) J_f     (e) J_P             (g) J_SCR     (i) reference owner
%
% DECISION CONTRACT, carried on the page itself: the supervisor consumes S, J_V
% and J_f ONLY. J_R, J_P, J_lock and J_SCR are reference-only, entered no gate,
% and are ASSUMED_DIAGNOSTIC. No aggregate index is formed
% (agsi_reference_terms.m:11-16, :49-56).
%
% One tile per index with four device traces, NOT one tile per device with six
% index traces. Each J is normalised so 1.0 is its own band edge, but the ranges
% differ by orders of magnitude (a bolted fault drives J_R far above 1 while
% J_SCR is a topology step and J_lock is identically zero on a GFM branch).
% Sharing one axis between six such signals would force either a log axis, which
% destroys the "is it above 1?" reading that is the point, or clipping, which
% AGENTS.md forbids outright.
%
% Two marker families are drawn, because the chronology instants are NOT the
% switching instants: on the delivered run not one supervisor commitment
% coincides with a scheduled disturbance. Markers are achromatic and separated by
% line style so colour stays reserved for data.
%
% Nothing is smoothed, filtered, decimated, clipped, offset or interpolated. The
% only presentation shift anywhere on the page is a disclosed vertical offset
% between the four mode traces in panel (h), without which they would coincide.
%
% Classification: ASSUMED_DIAGNOSTIC presentation. No value here feeds a solver,
% selector, controller or acceptance decision.

arguments
    opts.result_file (1,1) string = fullfile('output','diagnostics', ...
        'ieee14_gfm_lock_compare','adaptive_250s.mat')
    opts.output (1,1) string = fullfile('docs','source','figures', ...
        'switch_ieee14_decision','decision_indices.png')
    opts.gamma_on (1,1) double = 0.65
    opts.gamma_off (1,1) double = 0.35
    opts.window (1,2) double = [-Inf Inf]
    opts.label_families (1,:) string = ["disturbance"]
    opts.width_in (1,1) double = 6.20
    opts.height_in (1,1) double = 8.10
    opts.font_size (1,1) double = 11
    opts.dpi (1,1) double = 300
    opts.title (1,1) logical = true
    opts.title_suffix (1,1) string = ""
end

pf_init_paths();
r = load_result(opts.result_file);
d = ieee14_switch_decision_signals(r, ...
    gamma_on=opts.gamma_on,gamma_off=opts.gamma_off);
M = ieee14_switch_event_marks(r,t_end=requested_horizon(r));

win = opts.window;
if ~isfinite(win(1)), win(1) = M.t_range(1); end
if ~isfinite(win(2)), win(2) = M.t_range(2); end

FS = opts.font_size;
FN = 'Times New Roman';
nd = numel(d.device_ids);
col = lines(nd);
lbl = cell(1,nd);
for q = 1:nd
    lbl{q} = sprintf('%s (bus %g)',d.device_ids{q},d.device_bus_ids(q));
end

f = pf_page_figure(opts.width_in,opts.height_in,FS);
tl = tiledlayout(f,5,2,'TileSpacing','compact','Padding','compact');

% --- (a) the decision variable, full width -------------------------------
ax = nexttile(tl,[1 2]); hold(ax,'on');
h = gobjects(1,nd);
for q = 1:nd
    h(q) = plot(ax,d.t,d.S(:,q),'-','Color',col(q,:),'LineWidth',1.0);
end
yline(ax,opts.gamma_on ,'k-' ,'\Gamma_{on}' , ...
    'LineWidth',0.9,'FontName',FN,'FontSize',FS-2,'HandleVisibility','off');
yline(ax,opts.gamma_off,'k--','\Gamma_{off}', ...
    'LineWidth',0.9,'FontName',FN,'FontSize',FS-2,'HandleVisibility','off');
ylim(ax,[-0.03 1.03]);
finish_panel(ax,'(a) severity index S', ...
    '{\itS} [-]',FN,FS,true,false);
pf_draw_marks(ax,M,labels=true,label_families=opts.label_families, ...
    font_size=FS-3,window=win);

lg = legend(ax,h,lbl,'Orientation','horizontal','NumColumns',nd,'Box','off');
lg.Layout.Tile = 'north';
set(lg,'FontName',FN,'FontSize',FS-2);

% --- (b)-(g) the six sub-indices ----------------------------------------
spec = { ...
  'J_V',   '(b) J_V: decision term',             '{\itJ_V} [-]',     false; ...
  'J_f',   '(c) J_f: decision term, system COI', '{\itJ_f} [-]',     true ; ...
  'J_R',   '(d) J_R: reference only, ROCOF',     '{\itJ_R} [-]',     true ; ...
  'J_P',   '(e) J_P: reference only',            '{\itJ_P} [-]',     false; ...
  'J_lock','(f) J_{lock}: reference only',       '{\itJ}_{lock} [-]',false; ...
  'J_SCR', '(g) J_{SCR}: reference only',        '{\itJ}_{SCR} [-]', false};

in_win = d.t >= win(1) & d.t <= win(2);
for k = 1:size(spec,1)
    name = spec{k,1};
    T = d.terms.(name);
    ax = nexttile(tl); hold(ax,'on');
    if spec{k,4}
        plot(ax,d.t,T(:,1),'-','Color',[0.15 0.15 0.15],'LineWidth',1.0);
    else
        for q = 1:nd
            plot(ax,d.t,T(:,q),'-','Color',col(q,:),'LineWidth',0.9);
        end
    end
    yline(ax,1,'k:','LineWidth',0.8,'HandleVisibility','off');
    % Autoscale to the WINDOW, not to the whole trajectory: on a zoom page the
    % out-of-window fault needle would otherwise flatten everything shown.
    % Nothing is clipped -- the data outside the window is simply off-screen and
    % the in-window peak is printed in the title.
    Tw = T(in_win,:); Tw = Tw(isfinite(Tw));
    if ~isempty(Tw)
        lo = min([0;Tw(:)]); hi = max([1.05;Tw(:)]);
        pad = 0.05*max(hi-lo,eps);
        ylim(ax,[lo-pad hi+pad]);
    end
    ttl = spec{k,2};
    if ~isempty(Tw) && max(Tw) > 3
        ttl = sprintf('%s, peak %.3g',ttl,max(Tw));
    end
    finish_panel(ax,ttl,spec{k,3},FN,FS,true,false);
    pf_draw_marks(ax,M,labels=false,window=win);
end
% --- (h) GFL/GFM mode ----------------------------------------------------
OFFSET = 0.035;   % disclosed: without it the four traces coincide exactly
ax = nexttile(tl); hold(ax,'on');
for q = 1:nd
    stairs(ax,d.t,double(d.mode_gfm(:,q)) + (q-1)*OFFSET, ...
        '-','Color',col(q,:),'LineWidth',1.0);
end
ylim(ax,[-0.15 1.15+(nd-1)*OFFSET]);
set(ax,'YTick',[0 1],'YTickLabel',{'GFL','GFM'});
finish_panel(ax,sprintf('(h) mode, traces offset %.3f',OFFSET), ...
    '',FN,FS,false,true);
pf_draw_marks(ax,M,labels=false,window=win);

% --- (i) reference owner -------------------------------------------------
ax = nexttile(tl); hold(ax,'on');
stairs(ax,d.t,d.ref_code,'-','Color',[0.35 0.15 0.55],'LineWidth',1.1);
ylim(ax,[-1.4 nd+0.4]);
ticks = -1:nd;
names = cell(1,numel(ticks));
names{1} = 'none'; names{2} = 'SG';
for q = 1:nd, names{q+2} = d.device_ids{q}; end
set(ax,'YTick',ticks,'YTickLabel',names);
finish_panel(ax,'(i) reference owner','',FN,FS,false,true);
pf_draw_marks(ax,M,labels=false,window=win);

% --- shared axis range, set ONCE for every panel -------------------------
axall = findall(f,'Type','axes');
linkaxes(axall,'x');
xlim(axall(1),win);
% Re-apply the tick-label suppression AFTER xlim: changing the limits re-ticks
% the axes and would otherwise restore the labels on every row.
for k = 1:numel(axall)
    if ~isempty(get(axall(k),'XLabel')) && ...
            isempty(get(get(axall(k),'XLabel'),'String'))
        set(axall(k),'XTickLabel',[]);
    end
end

if opts.title
    ttl = sprintf('Switching decision --- IEEE 14-bus, 1 SG + 4 converters%s', ...
        char(opts.title_suffix));
    sub = sprintf(['\\rm\\fontsize{%d}{}%s   |   decision terms S, J_V, J_f' ...
        '   |   J_R, J_P, J_{lock}, J_{SCR} reference-only ' ...
        '(ASSUMED\\_DIAGNOSTIC, entered no gate)'],FS-4,run_label(r));
    sgtitle(f,sprintf('%s\n%s',ttl,sub), ...
        'FontName',FN,'FontSize',FS-1,'FontWeight','bold','Interpreter','tex');
end

pf_page_export(f,opts.output,opts.dpi);

out = struct();
out.output = char(opts.output);
out.result_file = char(opts.result_file);
out.n_samples = numel(d.t);
out.n_devices = nd;
out.diagnostics = d.diagnostics;
out.decision_contract = d.decision_contract;
out.n_marks = numel(M.marks);
out.n_mark_groups = M.n_groups;
out.supervisor_marks = sum(strcmp({M.marks.family},'supervisor'));
out.term_peaks = struct();
for k = 1:numel(d.term_names)
    T = d.terms.(d.term_names{k});
    out.term_peaks.(d.term_names{k}) = max(T(isfinite(T)));
end
out.presentation_offset_mode_panel = OFFSET;
out.window = win;
end

% ==========================================================================
function finish_panel(ax,ttl,ylab,FN,FS,want_ylabel,want_xlabel)
grid(ax,'on'); box(ax,'on');
set(ax,'FontName',FN,'FontSize',FS-1,'GridAlpha',0.12);
title(ax,ttl,'FontName',FN,'FontSize',FS-2,'FontWeight','normal');
if want_ylabel && ~isempty(ylab)
    ylabel(ax,ylab,'FontName',FN,'FontSize',FS-1);
end
if want_xlabel
    xlabel(ax,'{\itt} [s]','FontName',FN,'FontSize',FS-1);
else
    set(ax,'XTickLabel',[]);
end
end

% ==========================================================================
function r = load_result(file)
p = char(file);
if ~isfile(p)
    error('generate_ieee14_decision_figure:missingResult', ...
        ['No stored result at %s. Produce one with ' ...
         'run_ieee14_gfm_lock_comparison.'],p);
end
S = load(p);
if isfield(S,'result'), r = S.result;
elseif isfield(S,'r'), r = S.r;
else
    error('generate_ieee14_decision_figure:badResultFile', ...
        '%s contains neither "result" nor "r".',p);
end
end

function t_end = requested_horizon(r)
t_end = NaN;
if isfield(r,'sched') && isstruct(r.sched) && isfield(r.sched,'t_end')
    t_end = r.sched.t_end;
end
end

function s = run_label(r)
s = 'adaptive arm';
if isfield(r,'t') && ~isempty(r.t)
    s = sprintf('%s, %.4g s horizon',s,r.t(end));
end
end
