function out = generate_ieee14_pq_mode_page(opts)
%GENERATE_IEEE14_PQ_MODE_PAGE  Converter power, under a GFM-mode-active band.
%
%   out = generate_ieee14_pq_mode_page()
%   out = generate_ieee14_pq_mode_page(scenarios="sg_fault_cycle160")
%
% The owner's reference layout, the same one generate_ieee14_vf_mode_page draws for
% voltage and frequency: two panels side by side under one converter legend, each
% with a "GFM Mode Active" strip of horizontal bars above it showing WHICH converter
% was grid-forming and WHEN. The strip is what lets a reader attribute a step in a
% power trace to a mode change without looking at another figure.
%
%   (a) P_i, the active power each converter delivered
%   (b) Q_i, the reactive power each converter delivered
%
% Pure cache reader over the artifacts run_ieee14_scenario_suite wrote. Nothing is
% simulated, re-solved, smoothed, filtered, decimated, interpolated or padded: every
% plotted sample is a raw accepted value from the stored trajectory.
%
% NEITHER PANEL IS MASKED FOR SERVICE. The mode strip is masked -- a converter out
% of service has no mode -- but P and Q are not: a departed converter injects no
% current, so its zero is a MEASURED injection, and hiding it would hide the outage.
% That asymmetry is deliberate and is the same one the suite sheets carry.
%
% Y WINDOWS on a faulted arm are computed over the OPERATING BAND -- the run minus
% its fault window plus 50 ms -- and anything that leaves the window is annotated AT
% THE FRAME with its peak value, the pattern the delivered report figures already use
% (generate_final_report_figures_th_v2.m:674-695). Measured reason on the 160 s arm:
% P spans [0.041 2.173] pu over the whole run but [0.167 0.951] pu over the island
% window outside the fault -- the 2.17 pu peak is the right-limit burst of the atomic
% fault-clear transaction. Letting it set the axis compresses the whole islanded band
% into a few percent of the panel. Nothing is dropped, filtered or clipped: every
% sample is plotted and every excursion is listed in provenance.txt.
%
% NO VERTICAL EVENT RULES, and the panel tag sits BELOW the x label, centred: this
% page matches its sibling exactly, on the owner's instruction (2026-09-05, "the same
% as the V/f graph"). The rules came off the V/f page the day before, so leaving them
% here would put two pages of one arm side by side in different styles. Every
% scheduled instant is still listed by time, name and source in provenance_pq_mode.txt.
%
% Lettering follows the standing contract: Helvetica through the 'tex' interpreter,
% no box, ticks outward, dashed major and minor grid, and a .fig beside every PNG
% (pf_page_export's fourth argument must be true -- it defaults false).
%
% Classification: presentation only. No value computed here feeds PF, SSSA, TS, a
% selector, a controller or an acceptance decision.

arguments
    opts.cache_dir (1,1) string = fullfile('output','diagnostics', ...
        'ieee14_scenario_suite')
    opts.out_dir (1,1) string = fullfile('docs','source','figures', ...
        'ieee14_scenario_suite')
    opts.scenarios (1,:) string = "sg_fault_cycle160"
    opts.width_in (1,1) double {mustBePositive} = 4.65
    % The sibling V/f page's canvas exactly (4.65 x 2.90 in): the tag now sits below
    % the x label as it does there, which needs the same BOT allowance, and two pages
    % of one arm included at 1:1 must occupy the same rectangle on a slide.
    opts.height_in (1,1) double {mustBePositive} = 2.90
    opts.font_size (1,1) double {mustBePositive} = 10
    opts.font_name (1,1) string = "Helvetica"
    opts.dpi (1,1) double {mustBePositive} = 300
    opts.save_fig (1,1) logical = true
end
% __TAIL__

pf_init_paths();
cdir = char(opts.cache_dir);
odir = char(opts.out_dir);
if ~isfolder(odir), mkdir(odir); end

out = struct();
out.schema = 'ieee14_pq_mode_page/1.0';
out.classification = 'PRESENTATION_ONLY';
out.cache_dir = cdir;
out.out_dir = odir;
out.generated_utc = char(datetime('now','TimeZone','UTC', ...
    'Format','yyyy-MM-dd''T''HH:mm:ssXXX'));
out.style = struct('width_in',opts.width_in,'height_in',opts.height_in, ...
    'font_size',opts.font_size,'font_name',char(opts.font_name), ...
    'interpreter','tex','box','off','tick_dir','out', ...
    'grid','dashed major and minor');
out.pages = struct([]);

for k = 1:numel(opts.scenarios)
    id = char(opts.scenarios(k));
    C = read_cache(cdir,id);
    page = draw_page(C,odir,opts);
    if isempty(out.pages), out.pages = page; else, out.pages(end+1) = page; end
    fprintf(['[%s] %d samples | horizon %.6f of %.6f s | %d GFM interval(s) | ' ...
        'P window %.4f..%.4f | Q window %.4f..%.4f pu\n'], ...
        id,page.n_samples,page.t_last,page.t_end_requested, ...
        page.n_gfm_intervals,page.P_window(1),page.P_window(2), ...
        page.Q_window(1),page.Q_window(2));
end

write_provenance(odir,out);
end

% ==========================================================================
function C = read_cache(cdir,id)
%READ_CACHE  One scenario cache plus the thresholds the mode strip depends on.
%   The severity thresholds come from the stored option signature, never from a
%   default here: they are top-level run options and are NOT republished in
%   result.metadata, so the signature saved beside the trajectory is the only record
%   of what the run actually used. A strip annotated with a threshold pair the run
%   did not use looks explained when it is not.
f = fullfile(cdir,[id '.mat']);
if ~isfile(f)
    error('generate_ieee14_pq_mode_page:cacheMissing', ...
        ['No cache at %s. Run run_ieee14_scenario_suite(scenarios="%s") ' ...
         'first; this generator never simulates.'],f,id);
end
S = load(f);
for fld = {'result','arm','opt_signature'}
    if ~isfield(S,fld{1})
        error('generate_ieee14_pq_mode_page:cacheIncomplete', ...
            'Cache %s lacks the "%s" variable.',f,fld{1});
    end
end
C = struct('id',id,'file',f,'r',S.result,'arm',S.arm,'sig',S.opt_signature);
C.gamma_on = sig_num(C.sig,'severity_gamma_on');
C.gamma_off = sig_num(C.sig,'severity_gamma_off');
C.t_end_requested = sig_num(C.sig,'t_end');
if ~isfinite(C.gamma_on) || ~isfinite(C.gamma_off)
    error('generate_ieee14_pq_mode_page:thresholdsUnrecorded', ...
        ['Cache %s records no severity_gamma_on/off. The mode strip on this page ' ...
         'is the OUTCOME of comparing S against them, so the page must not be ' ...
         'drawn without the pair the run used.'],f);
end
if ~isfinite(C.t_end_requested)
    C.t_end_requested = num_or(C.r.sched,'t_end',NaN);
end
if ~isfinite(C.t_end_requested)
    error('generate_ieee14_pq_mode_page:horizonUnrecorded', ...
        'Cache %s records no requested horizon.',f);
end
end

% ==========================================================================
function page = draw_page(C,odir,opts)
%DRAW_PAGE  The two power panels, their mode strips, and the shared legend.
r = C.r;
d = ieee14_switch_decision_signals(r, ...
    gamma_on=C.gamma_on,gamma_off=C.gamma_off);

t = d.t(:);
nt = numel(t);
nd = numel(d.device_ids);
fs = opts.font_size;
FN = char(opts.font_name);
col = converter_colours(nd);
deck_ids = arrayfun(@(q)sprintf('{\\itIBR}_{%d}',q),1:nd,'UniformOutput',false);

% --- the two signals, in the deck's converter order -----------------------
P = r.device_P_pu(d.device_result_rows,1:nt).';
Q = r.device_Q_pu(d.device_result_rows,1:nt).';
if ~isequal(size(P),[nt nd]) || ~isequal(size(Q),[nt nd])
    error('generate_ieee14_pq_mode_page:powerShapeMismatch', ...
        ['The power matrices are %s and %s but the page has %d samples over %d ' ...
         'converters.'],mat2str(size(P)),mat2str(size(Q)),nt,nd);
end

online = logical(d.online);
if ~isequal(size(online),[nt nd])
    error('generate_ieee14_pq_mode_page:onlineShapeMismatch', ...
        ['The online mask is %s but the page has %d samples over %d ' ...
         'converters; the mask cannot be applied element by element.'], ...
        mat2str(size(online)),nt,nd);
end
gfm = d.mode_gfm & online;

% --- the axis, the marks, and the operating band --------------------------
% The marks are still READ, because provenance_pq_mode.txt lists every scheduled
% instant -- they are simply not DRAWN any more, exactly as on the sibling V/f page.
xr = [0 max(C.t_end_requested,t(end))];
M = ieee14_switch_event_marks(r,t_end=C.t_end_requested, ...
    merge_span=xr(2)-xr(1));
MARK_FAMILIES = ["disturbance","supervisor","validity"];

FAULT_PAD = 0.050;
t_f_on = num_or(r.sched,'fault_on',NaN);
t_f_off = num_or(r.sched,'fault_clear',NaN);
if ~isfinite(t_f_off), t_f_off = num_or(r.sched,'line_fault_clear',NaN); end
if isfinite(t_f_on) && isfinite(t_f_off)
    band = ~(t >= t_f_on - 1e-9 & t <= t_f_off + FAULT_PAD);
    fault_window = [t_f_on t_f_off + FAULT_PAD];
else
    band = true(nt,1);
    fault_window = [NaN NaN];
end
if ~any(band)
    error('generate_ieee14_pq_mode_page:noOperatingBandSamples', ...
        ['Scenario "%s" has no sample outside its fault window, so no panel ' ...
         'window can be computed from the operating band.'],C.id);
end

% --- the canvas: two columns, each a mode strip above a data panel --------
% Identical geometry to generate_ieee14_vf_mode_page, so the two pages of one arm
% stack on a slide with their time axes at the same fractions of the width. BOT
% carries the time ticks, the x label AND the panel tag under it, in that order down
% the canvas -- the tag is outside the axes, as the sibling page has it.
W = opts.width_in; H = opts.height_in;
LEFT = 0.60; RIGHT = 0.06; GAPX = 0.62;      % GAPX holds column 2's y lettering
BOT = 0.74; TOPLEG = 0.26; CAPH = 0.17; STRIPH = 0.075*nd + 0.05; GAPY = 0.04;
COLW = (W - LEFT - RIGHT - GAPX)/2;
PANH = H - BOT - TOPLEG - CAPH - STRIPH - GAPY;
if PANH <= 0.35
    error('generate_ieee14_pq_mode_page:canvasTooShort', ...
        ['The canvas is %.2f in tall, which leaves %.2f in for the data panels ' ...
         'after the legend, the mode strip and the axis lettering. Raise ' ...
         'height_in.'],H,PANH);
end
f1 = pf_page_figure(W,H,fs,opts.font_name);
x_col = [LEFT, LEFT+COLW+GAPX];
y_pan = BOT;
y_strip = BOT + PANH + GAPY;

% =============================== (a) P ====================================
ax1 = axes_in(f1,[x_col(1) y_pan COLW PANH],W,H); hold(ax1,'on');
hP = gobjects(1,nd);
for q = 1:nd
    hP(q) = plot(ax1,t,P(:,q),'Color',col(q,:),'LineWidth',1.0);
end
ylP = panel_window(ax1,P(band,:),0.06);
xlim(ax1,xr);
finish_panel(ax1,fs,FN,'{\itP_i} [p.u.]','{\itt} [s]','(a)');
off_P = mark_offscale(ax1,t,P,ylP,xr,col,FN,fs-2.5,'%.2f');
n_gfm_intervals = mode_strip(f1,[x_col(1) y_strip COLW STRIPH],W,H, ...
    t,gfm,col,xr);
strip_caption(f1,[x_col(1) y_strip+STRIPH COLW CAPH],W,H,FN,fs-2.5);

% =============================== (b) Q ====================================
ax2 = axes_in(f1,[x_col(2) y_pan COLW PANH],W,H); hold(ax2,'on');
% Zero is a meaningful level for Q -- it separates absorbing from supplying -- so it
% is drawn as a reference rule, the way panel (b) of the vf page draws f_0.
yline(ax2,0,'-','Color',[0.55 0.55 0.55],'LineWidth',0.6, ...
    'HandleVisibility','off');
for q = 1:nd
    plot(ax2,t,Q(:,q),'Color',col(q,:),'LineWidth',1.0, ...
        'HandleVisibility','off');
end
ylQ = panel_window(ax2,[reshape(Q(band,:),[],1); 0],0.06);
xlim(ax2,xr);
finish_panel(ax2,fs,FN,'{\itQ_i} [p.u.]','{\itt} [s]','(b)');
off_Q = mark_offscale(ax2,t,Q,ylQ,xr,col,FN,fs-2.5,'%.2f');
mode_strip(f1,[x_col(2) y_strip COLW STRIPH],W,H,t,gfm,col,xr);
strip_caption(f1,[x_col(2) y_strip+STRIPH COLW CAPH],W,H,FN,fs-2.5);

% One legend for both columns, along the top, so each converter's hue is named once.
lg = legend(ax1,hP,deck_ids,'Orientation','horizontal','Box','off', ...
    'FontName',FN,'FontSize',fs-2,'Interpreter','tex');
lg.Units = 'inches';
lg.Position = [LEFT + (W-LEFT-RIGHT-lg.Position(3))/2, ...
    H - TOPLEG + 0.02, lg.Position(3), lg.Position(4)];

% ------------------------------- export -----------------------------------
% Named _pq_mode, NOT _pq: generate_ieee14_scenario_suite_figures writes
% <scenario>_pq.png for its own two-panel sheet, and this page would silently
% overwrite it. The suffix matches this generator's manifest, provenance_pq_mode.txt,
% so a page and its manifest are found by the same name.
png = fullfile(odir,sprintf('%s_pq_mode.png',C.id));
pf_page_export(f1,png,opts.dpi,opts.save_fig);
if opts.save_fig
    figf = fullfile(odir,sprintf('%s_pq_mode.fig',C.id));
else
    figf = '';
end

page = struct();
page.id = C.id;
page.label = char(string(C.arm.label));
page.cache = C.file;
page.png = png;
page.fig = figf;
page.n_samples = nt;
page.n_devices = nd;
page.t_last = t(end);
page.t_end_requested = C.t_end_requested;
page.reached_horizon = t(end) >= C.t_end_requested - 1e-9;
page.gamma_on = C.gamma_on;
page.gamma_off = C.gamma_off;
page.device_ids_code = {d.device_ids(:).'};
page.device_bus_ids = d.device_bus_ids;
page.P_window = ylP;
page.Q_window = ylQ;
page.P_range_pu = [min(P(:)) max(P(:))];
page.Q_range_pu = [min(Q(:)) max(Q(:))];
page.P_band_range_pu = [min(P(band,:),[],'all') max(P(band,:),[],'all')];
page.Q_band_range_pu = [min(Q(band,:),[],'all') max(Q(band,:),[],'all')];
page.fault_window = fault_window;
page.n_band_samples = sum(band);
page.offscale_P = off_P;
page.offscale_Q = off_Q;
page.n_gfm_intervals = n_gfm_intervals;
page.n_offline_samples = sum(sum(~online));
page.marks = mark_table(M,MARK_FAMILIES);
page.n_marks = numel(page.marks);
[page.events_executed,page.events_not_executed,page.defining_event, ...
    page.defining_event_executed] = ieee14_event_execution(r,C.arm);
end

% ==========================================================================
% Panel and strip helpers.
%
% These are LOCAL COPIES of the ones in generate_ieee14_vf_mode_page, deliberately:
% the two pages are siblings that must look identical, and every generator in this
% folder already carries its own copy of this set (the suite sheets do too). Sharing
% them through scripts/reporting/private would change the delivered vf page and the
% suite sheets at the same time, which is a larger edit than this page justifies.
% ==========================================================================
function ax = axes_in(f,rect_in,W,H)
%AXES_IN  One axes at an explicit rectangle given in INCHES on the canvas.
%   Converted to normalized units rather than left in inches, because a figure whose
%   axes carry absolute units does not survive being resized -- and the .fig written
%   beside the PNG is meant to be reopened and adjusted.
ax = axes(f,'Units','normalized', ...
    'Position',[rect_in(1)/W rect_in(2)/H rect_in(3)/W rect_in(4)/H]);
end

% ==========================================================================
function n_iv = mode_strip(f,rect_in,W,H,t,gfm,col,xr)
%MODE_STRIP  The "GFM Mode Active" bars, in their own axes above a data panel.
%   One lane per converter, one bar per contiguous grid-forming interval, in the
%   converter's own colour. A SEPARATE axes rather than an overlay inside the data
%   panel: an overlay has to steal range from the traces, and a bar drawn in data
%   units lands on top of a trace as soon as a signal comes near the top of its
%   window.
%
%   Bars are drawn at their TRUE extent. No minimum width is applied: widening a
%   short interval to make it visible would draw a grid-forming stretch that did not
%   happen. A converter with no bar was never grid-forming, and that absence is the
%   fact.
%
%   Lanes run TOP-DOWN in converter order, so the top lane is IBR_1 -- the same order
%   the legend above reads left to right.
nd = size(gfm,2);
ax = axes_in(f,rect_in,W,H); hold(ax,'on');
ylim(ax,[0.5 nd+0.5]);
set(ax,'YDir','reverse');
n_iv = 0;
h_bar = 0.62;                       % lane fraction, leaving a gutter between lanes
for q = 1:nd
    iv = true_intervals(gfm(:,q),t);
    for j = 1:size(iv,1)
        % A patch, not a line: a line's thickness is in points and would not scale
        % with the strip, so the same figure at another size would show bars of a
        % different weight.
        patch(ax,'XData',[iv(j,1) iv(j,2) iv(j,2) iv(j,1)], ...
            'YData',[q-h_bar/2 q-h_bar/2 q+h_bar/2 q+h_bar/2], ...
            'FaceColor',col(q,:),'FaceAlpha',1,'EdgeColor','none', ...
            'HandleVisibility','off','Clipping','on');
        n_iv = n_iv + 1;
    end
end
% NO event rules on the strip either, matching the sibling V/f page: a bar's own left
% edge already dates the mode change, and provenance lists every scheduled instant.
xlim(ax,xr);
ylim(ax,[0.5 nd+0.5]);
% No frame, no ticks, no grid: the strip is a legend for the panel below, not a
% second plot. Its x axis is the panel's, already labelled there.
set(ax,'Box','off','XTick',[],'YTick',[],'XColor','none','YColor','none', ...
    'Color','none','Layer','top');
end

% ==========================================================================
function strip_caption(f,rect_in,W,H,FN,fs)
%STRIP_CAPTION  The "GFM Mode Active" line above one mode strip.
%   Its own invisible axes, so the text sits at a known place on the canvas instead
%   of inside a data panel where a trace could reach it.
ax = axes_in(f,rect_in,W,H);
set(ax,'Visible','off','XLim',[0 1],'YLim',[0 1]);
text(ax,0,0.30,'{\itGFM Mode Active:}','FontName',FN,'FontSize',fs, ...
    'Interpreter','tex','HorizontalAlignment','left', ...
    'VerticalAlignment','bottom','Color',[0.15 0.15 0.15]);
end

% ==========================================================================
function iv = true_intervals(mask,t)
%TRUE_INTERVALS  Contiguous [t_start t_end] runs of a logical mask.
%   A single-sample run is given the width of one step to its neighbour, because a
%   zero-width patch draws nothing at all -- the interval would vanish rather than be
%   small. Nothing wider is ever widened.
mask = logical(mask(:));
iv = zeros(0,2);
if ~any(mask), return; end
dm = diff([false; mask; false]);
a = find(dm == 1);
b = find(dm == -1) - 1;
for j = 1:numel(a)
    t0 = t(a(j)); t1 = t(b(j));
    if t1 <= t0
        nx = min(b(j)+1,numel(t));
        if nx > b(j), t1 = t(nx); else, t1 = t0 + eps(t0); end
    end
    iv(end+1,:) = [t0 t1]; %#ok<AGROW>
end
end

% ==========================================================================
function yl = panel_window(ax,Y,headroom)
%PANEL_WINDOW  Y limits from the data, with headroom, applied BEFORE the marks.
%   Every finite sample of Y must be inside the returned range. The CALLER decides
%   what Y is: passing the operating-band subset deliberately leaves a fault
%   excursion outside the window, which is only admissible because mark_offscale then
%   annotates it at the frame with its peak.
%
%   Set BEFORE pf_draw_marks so the marks are what get restored, not what set the
%   range.
yl = ylim(ax);
y = Y(isfinite(Y));
if isempty(y), return; end
lo = min(y); hi = max(y);
if hi - lo < 1e-9
    pad = max(0.05,abs(hi)*0.05);
    lo = lo - pad; hi = hi + pad;
else
    pad = headroom*(hi-lo);
    lo = lo - pad; hi = hi + pad;
end
yl = [lo hi];
ylim(ax,yl);
end

% ==========================================================================
function finish_panel(ax,fs,FN,ylab,xlab,tag)
%FINISH_PANEL  The standing style contract: no box, ticks outward, dashed major AND
%   minor grid, deck typeface through the 'tex' interpreter.
%
%   xlim is NOT set here. The caller sets it AFTER pf_draw_marks, because
%   pf_draw_marks freezes and restores the y limits, and reversing the two is the
%   defect that squashed an earlier page.
set(ax,'Box','off','TickDir','out','Layer','bottom', ...
    'XMinorGrid','on','YMinorGrid','on','MinorGridLineStyle','--', ...
    'MinorGridColor',[0.65 0.65 0.65],'GridLineStyle','--', ...
    'GridColor',[0.85 0.85 0.85],'TickLabelInterpreter','tex', ...
    'FontName',FN,'FontSize',fs);
grid(ax,'on');
ylabel(ax,ylab,'FontName',FN,'FontSize',fs,'Interpreter','tex');
if ~isempty(xlab)
    xlabel(ax,xlab,'FontName',FN,'FontSize',fs,'Interpreter','tex');
else
    set(ax,'XTickLabel',[]);
end
% Panel tag BELOW the x label, centred, outside the axes -- the sibling V/f page's
% placement, adopted here so the two pages of one arm are identical. Inside the panel
% it had nowhere to go: the top is under the mode strip, and the bottom right is where
% mark_offscale prints the down-arrow annotation (P dips to 0.04 pu at the fault
% instant on the 160 s arm), which it collided with.
text(ax,0.5,-0.32,tag,'Units','normalized','Interpreter','tex', ...
    'HorizontalAlignment','center','VerticalAlignment','top', ...
    'FontName',FN,'FontSize',fs,'Clipping','off');
end

% ==========================================================================
function info = mark_offscale(ax,t,Y,yl,xr,col,FN,fs,fmt)
%MARK_OFFSCALE  Flag data that leaves the panel window, with its peak value.
%   Same contract as the delivered report figure's helper
%   (generate_final_report_figures_th_v2.m:674-695): a view that silently cut an
%   excursion would misrepresent the run, so an excursion past either frame is
%   annotated AT THE FRAME with the value it reached.
%
%   ONE label per direction, carrying the extreme over all channels in the colour of
%   the channel that reached it, and placed at the RIGHT EDGE rather than at the
%   peak's own instant: on this arm all four converters leave the window within the
%   same 1.5 ms, so per-channel labels landed in one pixel column and printed over one
%   another. Every channel that left is still listed individually in provenance.txt --
%   nothing is lost, only un-stacked.
info = struct('channel',{},'peak',{},'t_peak',{},'direction',{});
if isvector(Y), Y = Y(:); end
n = size(Y,2);
if size(col,1) < n, col = repmat(col(1,:),n,1); end
hi_v = -inf; hi_c = NaN;
lo_v = inf; lo_c = NaN;
for q = 1:n
    y = Y(:,q);
    [h,ih] = max(y);
    [l,il] = min(y);
    if isfinite(h) && h > yl(2)
        info(end+1) = struct('channel',q,'peak',h,'t_peak',t(ih), ...
            'direction','above'); %#ok<AGROW>
        if h > hi_v, hi_v = h; hi_c = q; end
    end
    if isfinite(l) && l < yl(1)
        info(end+1) = struct('channel',q,'peak',l,'t_peak',t(il), ...
            'direction','below'); %#ok<AGROW>
        if l < lo_v, lo_v = l; lo_c = q; end
    end
end
x_lab = xr(1) + 0.99*(xr(2)-xr(1));
if isfinite(hi_v)
    text(ax,x_lab,yl(2),sprintf('\\uparrow %s ',sprintf(fmt,hi_v)), ...
        'Interpreter','tex','Color',col(hi_c,:),'FontName',FN,'FontSize',fs, ...
        'HorizontalAlignment','right','VerticalAlignment','top', ...
        'BackgroundColor',[1 1 1],'Margin',0.5,'Clipping','on');
end
if isfinite(lo_v)
    text(ax,x_lab,yl(1),sprintf('\\downarrow %s ',sprintf(fmt,lo_v)), ...
        'Interpreter','tex','Color',col(lo_c,:),'FontName',FN,'FontSize',fs, ...
        'HorizontalAlignment','right','VerticalAlignment','bottom', ...
        'BackgroundColor',[1 1 1],'Margin',0.5,'Clipping','on');
end
end

% ==========================================================================
function T = mark_table(M,families)
%MARK_TABLE  The run's scheduled instants, as plain records for the provenance file.
%   The sheet draws NO vertical rules at all (they came off with the sibling V/f
%   page's, 2026-09-05), so this table is the page's ONLY record of when each event
%   fell -- kept for that reason rather than as a legend for something the reader can
%   see.
T = struct('t',{},'label',{},'family',{},'source',{});
for k = 1:numel(M.marks)
    m = M.marks(k);
    if ~any(strcmp(m.family,families)), continue; end
    T(end+1) = struct('t',m.t,'label',m.label,'family',m.family, ...
        'source',m.source); %#ok<AGROW>
end
end

% ==========================================================================
function C = converter_colours(n)
%CONVERTER_COLOURS  The owner's own legend colours, in the deck's converter order.
%   Taken from the supplied reference legend (2026-09-04): IBR_1 blue, IBR_2 dark
%   grey, IBR_3 red, IBR_4 black -- the same palette every other figure of this
%   result set now uses (generate_ieee14_vf_mode_page.m,
%   generate_ieee14_agsi_mode_3d.m, generate_ieee14_scenario_suite_figures.m), so a
%   converter keeps one hue across the report.
base = [0.00 0.16 0.70;   % IBR_1  blue
        0.32 0.32 0.32;   % IBR_2  dark grey
        0.84 0.10 0.11;   % IBR_3  red
        0.00 0.00 0.00];  % IBR_4  black
if n <= size(base,1), C = base(1:n,:); else, C = [base; lines(n-size(base,1))]; end
end

% ==========================================================================
function v = sig_num(sig,name)
v = NaN;
if isstruct(sig) && isfield(sig,name) && ~isempty(sig.(name)) && ...
        isnumeric(sig.(name)) && isscalar(sig.(name))
    v = double(sig.(name));
end
end

function v = num_or(s,name,default)
v = default;
if isstruct(s) && isfield(s,name) && ~isempty(s.(name)) && ...
        isnumeric(s.(name)) && isscalar(s.(name))
    v = double(s.(name));
end
end

% ==========================================================================
function write_provenance(odir,out)
%WRITE_PROVENANCE  Plain-text manifest beside the page.
%   Same shape as the other suite generators': a key/value header, then one block per
%   scenario naming the page with its SHA-256, mtime and the cache it came from, so a
%   reader holding one slide can tell which trajectory produced it.
p = fullfile(odir,'provenance_pq_mode.txt');
fid = fopen(p,'w');
if fid < 0
    warning('generate_ieee14_pq_mode_page:provenanceUnwritable', ...
        'Could not write %s; the figure is still valid.',p);
    return;
end
fprintf(fid,'generator: scripts/reporting/generate_ieee14_pq_mode_page.m\n');
fprintf(fid,'schema:    %s\n',out.schema);
fprintf(fid,'generated: %s\n',out.generated_utc);
fprintf(fid,'caches:    %s\n',out.cache_dir);
fprintf(fid,['style:     %g in x %g in, %s %g pt, tex interpreter, %s, box ' ...
    'off, ticks out\n'],out.style.width_in,out.style.height_in, ...
    out.style.font_name,out.style.font_size,out.style.grid);
fprintf(fid,'\n');
fprintf(fid,['ONE SHEET per scenario, two columns side by side under one ' ...
    'converter legend. Each\n  column is a "GFM Mode Active" STRIP above a data ' ...
    'panel:\n' ...
    '    (a) P_i, the active power each converter delivered\n' ...
    '    (b) Q_i, the reactive power each converter delivered, against zero\n' ...
    '  The strip is a separate axes, not an overlay inside the data area, so a bar ' ...
    'can never\n  sit on a trace and the traces keep the whole panel height.\n\n']);
fprintf(fid,['Pure cache reader. Nothing is simulated, re-solved, smoothed, ' ...
    'filtered, decimated,\n  clipped, offset, interpolated or padded: every ' ...
    'plotted sample is a raw accepted\n  value from the stored trajectory.\n\n']);
fprintf(fid,['NEITHER PANEL IS MASKED FOR SERVICE. The mode strip is masked -- a ' ...
    'converter out of\n  service has no mode -- but P and Q are not: a departed ' ...
    'converter injects no current,\n  so its zero is a MEASURED injection and ' ...
    'hiding it would hide the outage. The masked\n  sample count is listed per ' ...
    'scenario below.\n\n']);
fprintf(fid,['THE MODE STRIP is the outcome of the supervisor comparing S against ' ...
    'Gamma_on/Gamma_off,\n  which is why this page refuses to draw without the ' ...
    'threshold pair the run used. Each\n  bar spans one CONTIGUOUS grid-forming ' ...
    'interval at its TRUE extent -- no minimum width\n  is applied, because ' ...
    'widening a short interval to make it visible would draw a\n  grid-forming ' ...
    'stretch that did not happen. A converter with no bar was never\n  ' ...
    'grid-forming on this arm, and that absence is the fact.\n\n']);
fprintf(fid,['Y WINDOWS on a faulted arm are computed over the OPERATING BAND -- ' ...
    'the run minus its\n  fault window plus 50 ms -- and anything outside is ' ...
    'annotated AT THE FRAME with its\n  peak value. NOTHING is dropped, filtered ' ...
    'or clipped: every sample is plotted and every\n  value outside a window is ' ...
    'listed below.\n\n']);
fprintf(fid,['The x axis spans the REQUESTED horizon, not the last accepted ' ...
    'sample: cropping to\n  the data would draw a truncated run as a finished ' ...
    'one.\n\n']);
fprintf(fid,['NO VERTICAL EVENT RULES on the sheet, matching the sibling V/f page ' ...
    '(the owner took\n  them off both, 2026-09-04/05): the dashed and dotted rules ' ...
    'are off both panels and off\n  the mode strips. A bar''s own left edge already ' ...
    'dates the mode change, and every\n  scheduled instant the run carried is ' ...
    'listed by time, name and source below -- that\n  table is now the ONLY record ' ...
    'of them on this page.\n']);
for k = 1:numel(out.pages)
    q = out.pages(k);
    fprintf(fid,'\n%s\n','--------------------------------------------------------------');
    fprintf(fid,'%s %s\n',q.id,q.label);
    fprintf(fid,'  cache      %s\n',q.cache);
    fprintf(fid,'  cache_sha  %s\n',file_sha(q.cache));
    for ff = {q.png,q.fig}
        if isempty(ff{1}), continue; end
        fprintf(fid,'  file       %s\n',ff{1});
        fprintf(fid,'    sha256   %s\n',file_sha(ff{1}));
        dd = dir(ff{1});
        if ~isempty(dd)
            fprintf(fid,'    mtime    %s\n', ...
                char(datetime(dd.datenum,'ConvertFrom','datenum', ...
                'Format','yyyy-MM-dd HH:mm:ss')));
            fprintf(fid,'    bytes    %d\n',dd.bytes);
        end
    end
    fprintf(fid,'  horizon    %.6f s of %.6f s requested (reached=%d)\n', ...
        q.t_last,q.t_end_requested,q.reached_horizon);
    fprintf(fid,'  thresholds Gamma_on=%.4f Gamma_off=%.4f\n', ...
        q.gamma_on,q.gamma_off);
    fprintf(fid,'  samples    %d over %d converter(s)\n',q.n_samples,q.n_devices);
    fprintf(fid,'  labels     deck IBR_1..IBR_%d = code %s\n', ...
        q.n_devices,strjoin(q.device_ids_code{1},', '));
    fprintf(fid,'  ranges     P [%.6f %.6f]  Q [%.6f %.6f] pu (whole run)\n', ...
        q.P_range_pu(1),q.P_range_pu(2),q.Q_range_pu(1),q.Q_range_pu(2));
    if all(isfinite(q.fault_window))
        fprintf(fid,['  window     y limits from the operating band: run minus ' ...
            '[%.4f %.4f] s (%d of %d samples kept)\n'], ...
            q.fault_window(1),q.fault_window(2),q.n_band_samples,q.n_samples);
    else
        fprintf(fid,['  window     y limits from the WHOLE run (no scheduled ' ...
            'fault, nothing excluded)\n']);
    end
    fprintf(fid,'             P [%.6g %.6g]  Q [%.6g %.6g]\n', ...
        q.P_window(1),q.P_window(2),q.Q_window(1),q.Q_window(2));
    write_offscale(fid,'P',q.offscale_P,q.device_ids_code{1});
    write_offscale(fid,'Q',q.offscale_Q,q.device_ids_code{1});
    fprintf(fid,'  gfm        %d contiguous interval(s) drawn\n',q.n_gfm_intervals);
    fprintf(fid,'  offline    %d converter-sample(s) out of service ', ...
        q.n_offline_samples);
    fprintf(fid,'(P and Q still plotted there)\n');
    fprintf(fid,'  defining   %s -> %s\n',q.defining_event, ...
        iif(q.defining_event_executed,'EXECUTED','NOT EXECUTED'));
    fprintf(fid,['  events     %d scheduled instant(s) the run carried, NOT drawn ' ...
        'on the sheet:\n'],q.n_marks);
    for j = 1:numel(q.marks)
        m = q.marks(j);
        fprintf(fid,'    %10.4f s  %-11s %-28s %s\n',m.t,m.family,m.label,m.source);
    end
end
fclose(fid);
fprintf('wrote %s\n',p);
end

% ==========================================================================
function write_offscale(fid,name,info,ids)
if isempty(info)
    fprintf(fid,'  offscale_%s none: every sample is inside the window\n',name);
    return;
end
fprintf(fid,['  offscale_%s value(s) outside the window, each annotated at the ' ...
    'frame:\n'],name);
for j = 1:numel(info)
    q = info(j).channel;
    lbl = sprintf('ch%d',q);
    if q >= 1 && q <= numel(ids), lbl = ids{q}; end
    fprintf(fid,'    %-6s %-8s %12.6f at t = %.6f s\n', ...
        lbl,info(j).direction,info(j).peak,info(j).t_peak);
end
end

% ==========================================================================
function sha = file_sha(f)
%FILE_SHA  Hex SHA-256 of a file via Java, on an absolute path.
%   Same helper the sibling page uses (generate_ieee14_vf_mode_page.m:1050), so the
%   two manifests carry hashes computed the same way. Streamed rather than read whole:
%   the caches are tens of megabytes.
sha = '(unavailable)';
if ~isfile(f), return; end
fj = char(java.io.File(f).getCanonicalPath());
h = java.security.MessageDigest.getInstance('SHA-256');
fis = java.io.FileInputStream(fj);
try
    buf = typecast(zeros(1,65536,'int8'),'uint8');
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
sha = sprintf('%02x',reshape(typecast(h.digest(),'uint8'),1,[]));
end

function s = iif(c,a,b)
if c, s = a; else, s = b; end
end
