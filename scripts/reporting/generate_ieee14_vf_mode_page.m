function out = generate_ieee14_vf_mode_page(opts)
%GENERATE_IEEE14_VF_MODE_PAGE  Voltage and frequency, under a GFM-mode-active band.
%
%   out = generate_ieee14_vf_mode_page()
%   out = generate_ieee14_vf_mode_page(scenarios="sg_fault_cycle160")
%
% The owner's reference layout: two panels side by side under one converter
% legend, each with a "GFM Mode Active" band of horizontal bars in ITS OWN STRIP
% ABOVE the panel showing WHICH converter was grid-forming and WHEN. The strip is
% a separate axes, not an overlay inside the data area, so a bar can never sit on
% a trace and the traces keep the whole panel height.
%
%   (a) |V_i| at each converter bus, against that bus's own healthy level
%   (b) f_i, the frequency of each converter itself, with the nominal
%
% Pure cache reader over the artifacts run_ieee14_scenario_suite wrote. No step is
% taken, no equation is solved and no sample is smoothed, decimated, interpolated
% or padded: every plotted value is either a raw accepted sample from the stored
% trajectory or the run's OWN output map evaluated on that stored state -- see
% below, where that path is gated.
%
% PANEL (b) IS THE CONVERTERS' OWN FREQUENCY, not the centre-of-inertia frequency.
% That takes one step beyond reading a field, because the run publishes only half
% of it. add_diagnostics fills device_frequency_Hz from the SG branch and the GFM
% branch (ts_simulate_ibr_hybrid.m:4158-4166); the grid-following branch records a
% current limit instead, so on this arm the published field is finite at
%   IBR_1 2130 of 2288 samples    IBR_2 0    IBR_3 94    IBR_4 0
% and a page drawn from it alone would show two converters with no frequency at
% all. The grid-following controller does have one -- its phase-locked loop tracks
% it, and gfl_eecon49_full_model.m:165 publishes it as f_hz -- so the missing
% stretches are recovered by calling the RUN'S OWN stored device closures
% (r.equilibrium.devices) on the RUN'S OWN stored state at each accepted sample.
% That is the same call add_diagnostics makes, on the same inputs.
%
% THREE GATES make that admissible, all enforced in converter_frequency below:
%   1. Every sample the run DID publish must be reproduced EXACTLY by the same
%      closures -- measured max|difference| = 0.000e+00 over 2673 samples. A
%      re-evaluation that disagreed anywhere would not be the run's.
%   2. Every ONLINE sample of every converter must end up with a frequency. A
%      remaining gap would mean the recovery is incomplete and the trace would
%      break for a reason the page does not state.
%   3. The two halves must be in one convention: f_hz is checked against
%      f0*omega_PLL_pu, the form the GFM/SG half uses (residual 2.1e-14, floating
%      point only). Mixing conventions would put a step in the trace at every mode
%      change.
% If any gate fails the page refuses with a named identifier rather than drawing a
% partial trace.
%
% NO J = 1 RULES ON EITHER PANEL, at the owner's instruction (2026-09-04): the
% dashed band edges are off the sheet. The switching index measures its frequency
% term on f_COI -- one system trace, not these four -- and its voltage term against
% each bus's healthy level; both bands belong to the severity page, which shows S
% itself. What stays on each panel is the reference every trace is a deviation FROM:
% the healthy |V| per bus, and the nominal frequency.
%
% Y WINDOWS on a faulted arm are computed over the OPERATING BAND -- the run minus
% its fault window plus 50 ms -- and anything that leaves the window is annotated
% AT THE FRAME with its peak value, the pattern the delivered report figures
% already use (generate_final_report_figures_th_v2.m:674-695). Measured reason on
% this arm: |V| spans [0.258 1.864] pu over the whole run but [0.551 1.138] pu
% outside the fault window, 2.735x the span for 4.3 % of the samples. Nothing is
% dropped, filtered or clipped: every sample is plotted and every excursion is
% listed in provenance.txt.
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
    % One figure on one slide, so the canvas is the deck's own text width and the
    % page is included at 1:1 -- lettering set at 10 pt arrives at 10 pt.
    opts.width_in (1,1) double {mustBePositive} = 4.65
    % Tall enough that the two mode strips, the shared legend, the axis lettering
    % and the panel tags all have their own room and the data panels still get
    % about 1.4 in each. draw_page refuses rather than squeezing if this is cut.
    opts.height_in (1,1) double {mustBePositive} = 2.90
    opts.font_size (1,1) double {mustBePositive} = 10
    opts.font_name (1,1) string = "Helvetica"
    opts.dpi (1,1) double {mustBePositive} = 300
    opts.save_fig (1,1) logical = true
end

pf_init_paths();
cdir = char(opts.cache_dir);
odir = char(opts.out_dir);
if ~isfolder(odir), mkdir(odir); end

out = struct();
out.schema = 'ieee14_vf_mode_page/1.0';
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
        '|V| window %.4f..%.4f pu | f window %.4f..%.4f Hz | f: %d published, ' ...
        '%d from the PLL\n'], ...
        id,page.n_samples,page.t_last,page.t_end_requested, ...
        page.n_gfm_intervals,page.V_window(1),page.V_window(2), ...
        page.f_window(1),page.f_window(2), ...
        page.f_source.n_published_by_run,page.f_source.n_from_following_pll);
end

write_provenance(odir,out);
end

% ==========================================================================
function C = read_cache(cdir,id)
%READ_CACHE  One scenario cache plus the references the panels measure against.
%   The severity thresholds and the healthy power-flow voltages come from the
%   stored option signature, never from a default here: they are top-level run
%   options and are NOT republished in result.metadata, so the signature saved
%   beside the trajectory is the only record of what the run actually used. A page
%   annotated with a reference the run did not use looks explained when it is not.
f = fullfile(cdir,[id '.mat']);
if ~isfile(f)
    error('generate_ieee14_vf_mode_page:cacheMissing', ...
        ['No cache at %s. Run run_ieee14_scenario_suite(scenarios="%s") ' ...
         'first; this generator never simulates.'],f,id);
end
S = load(f);
for fld = {'result','arm','opt_signature'}
    if ~isfield(S,fld{1})
        error('generate_ieee14_vf_mode_page:cacheIncomplete', ...
            'Cache %s lacks the "%s" variable.',f,fld{1});
    end
end
C = struct('id',id,'file',f,'r',S.result,'arm',S.arm,'sig',S.opt_signature);
C.gamma_on = sig_num(C.sig,'severity_gamma_on');
C.gamma_off = sig_num(C.sig,'severity_gamma_off');
C.t_end_requested = sig_num(C.sig,'t_end');
if ~isfinite(C.gamma_on) || ~isfinite(C.gamma_off)
    error('generate_ieee14_vf_mode_page:thresholdsUnrecorded', ...
        ['Cache %s records no severity_gamma_on/off. The mode band on this page ' ...
         'is the OUTCOME of comparing S against them, so the page must not be ' ...
         'drawn without the pair the run used.'],f);
end
if ~isfinite(C.t_end_requested)
    C.t_end_requested = num_or(C.r.sched,'t_end',NaN);
end
if ~isfinite(C.t_end_requested)
    error('generate_ieee14_vf_mode_page:horizonUnrecorded', ...
        'Cache %s records no requested horizon.',f);
end
% The voltage panel draws each bus against ITS OWN healthy level, because J_V is a
% deviation from that level and not from 1.0 pu. Refused rather than replaced by
% 1.0, which would draw an envelope no converter was ever judged against.
C.healthy_V = [];
C.healthy_bus = [];
if isstruct(C.sig) && isfield(C.sig,'healthy_pf_V') && ...
        isfield(C.sig,'healthy_pf_bus_ids')
    C.healthy_V = double(C.sig.healthy_pf_V(:));
    C.healthy_bus = double(C.sig.healthy_pf_bus_ids(:));
end
if isempty(C.healthy_V) || numel(C.healthy_V) ~= numel(C.healthy_bus)
    error('generate_ieee14_vf_mode_page:healthyReferenceUnrecorded', ...
        ['Cache %s records no usable healthy_pf_V / healthy_pf_bus_ids pair. ' ...
         'The voltage panel cannot show the deviation the index measures ' ...
         'without the reference the run measured it from.'],f);
end
% Frozen at ts_simulate_ibr_hybrid.m:1675-1677 and not caller-overridable there,
% so the two normalization bases are stated as constants and then VERIFIED against
% the run's own published J_V and J_f before a single envelope is drawn.
C.dV_base = 0.10;
C.df_base_Hz = 0.50;
% The nominal frequency is READ from the run, not assumed: the overlay publishes
% its own base set, and f0 is what every frequency on panel (b) is a deviation
% from. Refused rather than defaulted to 60 -- a nominal line at a frequency the
% run did not use would mislabel every trace on the panel.
C.f0_Hz = NaN;
if isfield(C.r,'agsi_reference') && isstruct(C.r.agsi_reference) && ...
        isfield(C.r.agsi_reference,'bases')
    C.f0_Hz = num_or(C.r.agsi_reference.bases,'f0_Hz',NaN);
end
if ~isfinite(C.f0_Hz)
    error('generate_ieee14_vf_mode_page:nominalFrequencyUnrecorded', ...
        ['Cache %s records no agsi_reference.bases.f0_Hz. Every frequency on ' ...
         'panel (b) is a deviation from the nominal, so the page must not draw ' ...
         'one the run did not use.'],f);
end
end

% ==========================================================================
function page = draw_page(C,odir,opts)
%DRAW_PAGE  The two panels, their mode bands, and the shared legend.
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

% --- the two signals, and PROOF that they are the index's own -------------
f_coi = d.f_coi_Hz(:);
Vbus = nan(nt,nd);
Vh = nan(1,nd);
for q = 1:nd
    b = find(r.bus_ids == d.device_bus_ids(q),1);
    if isempty(b)
        error('generate_ieee14_vf_mode_page:busNotFound', ...
            'Converter %s sits at bus %g, which is not in r.bus_ids.', ...
            d.device_ids{q},d.device_bus_ids(q));
    end
    Vbus(:,q) = r.bus_voltage_magnitude(b,1:nt).';
    ri = find(C.healthy_bus == d.device_bus_ids(q),1);
    if isempty(ri)
        error('generate_ieee14_vf_mode_page:healthyBusMissing', ...
            ['The healthy power-flow reference carries no bus %g, so the ' ...
             'deviation the index measures for %s cannot be shown.'], ...
            d.device_bus_ids(q),d.device_ids{q});
    end
    Vh(q) = C.healthy_V(ri);
end

% Rebuild both sub-indices from exactly what the panels draw and compare them
% against what the run published. This is the whole justification for calling these
% panels the decision inputs, so it is ASSERTED on every page rather than trusted
% from one probe: a future change to a base, a reference or a bus mapping breaks
% the page here instead of producing a plausible figure with the wrong envelope.
IDX_TOL = 1e-9;
Jf_rb = abs(f_coi - C.f0_Hz)/C.df_base_Hz;
JV_rb = abs(Vbus - repmat(Vh,nt,1))/C.dV_base;
okm = isfinite(d.terms.J_V) & isfinite(d.terms.J_f);
if ~any(okm(:))
    error('generate_ieee14_vf_mode_page:noIndexSamples', ...
        ['Scenario "%s" published no sample where both J_V and J_f were ' ...
         'evaluated, so the panels cannot be verified against the index.'],C.id);
end
Jf_mat = repmat(Jf_rb,1,nd);
res_JV = max(abs(JV_rb(okm) - d.terms.J_V(okm)));
res_Jf = max(abs(Jf_mat(okm) - d.terms.J_f(okm)));
if res_JV > IDX_TOL || res_Jf > IDX_TOL
    error('generate_ieee14_vf_mode_page:indexInputMismatch', ...
        ['Scenario "%s": the signals this page plots do NOT reproduce the ' ...
         'run''s own sub-indices (max residuals J_V %.3e, J_f %.3e over %d ' ...
         'evaluated samples, tolerance %.1e). The panels would be labelled as ' ...
         'the decision inputs without being them.'], ...
        C.id,res_JV,res_Jf,sum(okm(:)),IDX_TOL);
end

% --- the converters' own frequency, all four, over the whole run ----------
online = logical(d.online);
if ~isequal(size(online),[nt nd])
    error('generate_ieee14_vf_mode_page:onlineShapeMismatch', ...
        ['The online mask is %s but the page has %d samples over %d ' ...
         'converters; the mask cannot be applied element by element.'], ...
        mat2str(size(online)),nt,nd);
end
gfm = d.mode_gfm & online;
FQ = converter_frequency(C,d,nt,nd);

% --- the axis, the marks, and the operating band --------------------------
xr = [0 max(C.t_end_requested,t(end))];
M = ieee14_switch_event_marks(r,t_end=C.t_end_requested, ...
    merge_span=xr(2)-xr(1));
MARK_FAMILIES = ["disturbance","supervisor","validity"];

% The fault window is excluded from the Y WINDOW, never from the data. See the
% header for the measured ratio on this arm; every sample is still plotted and
% every excursion is annotated at the frame and listed in provenance.txt.
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
    error('generate_ieee14_vf_mode_page:noOperatingBandSamples', ...
        ['Scenario "%s" has no sample outside its fault window, so no panel ' ...
         'window can be computed from the operating band.'],C.id);
end

% --- the canvas: two columns, each a mode strip above a data panel --------
% Laid out with EXPLICIT axes rectangles in INCHES rather than with a tiled
% layout, because the mode strip and its panel must have different heights and
% share one x range exactly. A tiled layout gives its rows equal height, which
% would spend a third of the slide on four bars.
%
% Side by side rather than stacked, per the owner's reference layout. Both columns
% carry the same time axis and the same limits, so an instant sits at the same
% fraction of each column's width.
W = opts.width_in; H = opts.height_in;
LEFT = 0.60; RIGHT = 0.06; GAPX = 0.62;      % GAPX holds column 2's y lettering
% BOT carries the time ticks, the x label AND the panel tag under it, in that
% order down the canvas -- the tag is outside the axes, as the reference has it.
BOT = 0.74; TOPLEG = 0.26; CAPH = 0.17; STRIPH = 0.075*nd + 0.05; GAPY = 0.04;
COLW = (W - LEFT - RIGHT - GAPX)/2;
PANH = H - BOT - TOPLEG - CAPH - STRIPH - GAPY;
if PANH <= 0.35
    error('generate_ieee14_vf_mode_page:canvasTooShort', ...
        ['The canvas is %.2f in tall, which leaves %.2f in for the data panels ' ...
         'after the legend, the mode strip and the axis lettering. Raise ' ...
         'height_in.'],H,PANH);
end
f1 = pf_page_figure(W,H,fs,opts.font_name);
x_col = [LEFT, LEFT+COLW+GAPX];
y_pan = BOT;
y_strip = BOT + PANH + GAPY;

% =============================== (a) |V| ==================================
ax1 = axes_in(f1,[x_col(1) y_pan COLW PANH],W,H); hold(ax1,'on');
hV = gobjects(1,nd);
% Each bus's own healthy level, in the converter's own hue but lighter, drawn FIRST
% so the data sits on top of its own reference. NO J_V = 1 envelope: the owner took
% the dashed band edges off this page (2026-09-04), so what remains is the level
% every trace is a deviation from, and nothing else.
for q = 1:nd
    faint = 1 - 0.45*(1-col(q,:));
    yline(ax1,Vh(q),'-','Color',faint,'LineWidth',0.5,'HandleVisibility','off');
end
for q = 1:nd
    hV(q) = plot(ax1,t,Vbus(:,q),'Color',col(q,:),'LineWidth',1.0);
end
% The window is computed over the operating band and the healthy levels, which are
% the only references left on the panel. No room is reserved for the mode band: it
% has its own strip, so the traces keep the whole panel.
ylV = panel_window(ax1,[reshape(Vbus(band,:),[],1); Vh(:)],0.06);
xlim(ax1,xr);
finish_panel(ax1,fs,FN,'|{\itV_i}| [p.u.]','{\itt} [s]','(a)');
off_V = mark_offscale(ax1,t,Vbus,ylV,xr,col,FN,fs-2.5,'%.2f');
n_gfm_intervals = mode_strip(f1,[x_col(1) y_strip COLW STRIPH],W,H, ...
    t,gfm,col,xr);
strip_caption(f1,[x_col(1) y_strip+STRIPH COLW CAPH],W,H,FN,fs-2.5);

% =============================== (b) f ====================================
% THE CONVERTERS' OWN FREQUENCY, all four, over the whole run -- not the
% centre-of-inertia frequency. See the header for how the grid-following stretches
% are recovered and for the three gates that recovery has to pass.
%
% NO J_f = 1 rules here: the switching index measures its frequency term on f_COI,
% one system trace, so those edges would bound a quantity this panel does not show
% -- and the owner took the dashed band edges off this page outright.
ax2 = axes_in(f1,[x_col(2) y_pan COLW PANH],W,H); hold(ax2,'on');
% The nominal, as a faint rule. NOT lettered: the y axis already carries a tick at
% f_0 on this arm, so a name beside the rule would repeat the tick, and the right
% edge at that height is where the off-scale annotation goes -- the two printed
% over each other when both were drawn.
yline(ax2,C.f0_Hz,'-','Color',[0.55 0.55 0.55],'LineWidth',0.6, ...
    'HandleVisibility','off');
for q = 1:nd
    plot(ax2,t,FQ.f(:,q),'Color',col(q,:),'LineWidth',1.0, ...
        'HandleVisibility','off');
end
ylf = panel_window(ax2,[reshape(FQ.f(band,:),[],1); C.f0_Hz],0.08);
xlim(ax2,xr);
finish_panel(ax2,fs,FN,'{\itf_i} [Hz]','{\itt} [s]','(b)');
off_f = mark_offscale(ax2,t,FQ.f,ylf,xr,col,FN,fs-2.5,'%.2f');
mode_strip(f1,[x_col(2) y_strip COLW STRIPH],W,H,t,gfm,col,xr);
strip_caption(f1,[x_col(2) y_strip+STRIPH COLW CAPH],W,H,FN,fs-2.5);

% One legend for both columns, along the top, so each converter's hue is named
% once. Positioned explicitly: there is no tiled layout to hand it a tile.
lg = legend(ax1,hV,deck_ids,'Orientation','horizontal','Box','off', ...
    'FontName',FN,'FontSize',fs-2,'Interpreter','tex');
lg.Units = 'inches';
lg.Position = [LEFT + (W-LEFT-RIGHT-lg.Position(3))/2, ...
    H - TOPLEG + 0.02, lg.Position(3), lg.Position(4)];

% ------------------------------- export -----------------------------------
png = fullfile(odir,sprintf('%s_vf.png',C.id));
pf_page_export(f1,png,opts.dpi,opts.save_fig);
if opts.save_fig
    figf = fullfile(odir,sprintf('%s_vf.fig',C.id));
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
page.healthy_V = Vh;
page.V_window = ylV;
page.f_window = ylf;
page.V_range_pu = [min(Vbus(:)) max(Vbus(:))];
page.f_coi_range_Hz = [min(f_coi) max(f_coi)];
page.fault_window = fault_window;
page.n_band_samples = sum(band);
page.offscale_V = off_V;
page.offscale_f = off_f;
page.n_gfm_intervals = n_gfm_intervals;
page.f_source = FQ.diagnostics;
page.index_check = struct('f0_Hz',C.f0_Hz,'df_base_Hz',C.df_base_Hz, ...
    'dV_base_pu',C.dV_base,'n_evaluated_samples',sum(okm(:)), ...
    'max_residual_J_V',res_JV,'max_residual_J_f',res_Jf,'tolerance',IDX_TOL);
page.marks = mark_table(M,MARK_FAMILIES);
page.n_marks = numel(page.marks);
[page.events_executed,page.events_not_executed,page.defining_event, ...
    page.defining_event_executed] = ieee14_event_execution(r,C.arm);
end

% ==========================================================================
function ax = axes_in(f,rect_in,W,H)
%AXES_IN  One axes at an explicit rectangle given in INCHES on the canvas.
%   Converted to normalized units rather than left in inches, because a figure
%   whose axes carry absolute units does not survive being resized -- and the .fig
%   written beside the PNG is meant to be reopened and adjusted.
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
%   The strip shares the panel's x limits exactly, so a bar's left edge sits at the
%   same horizontal position as the instant below it.
%
%   Bars are drawn at their TRUE extent. No minimum width is applied: on this arm
%   the shorter interval is 3.21 s, 2.0 % of a 160 s axis, and widening it to look
%   better would draw a grid-forming stretch that did not happen. A converter with
%   no bar was never grid-forming, and that absence is the fact.
%
%   Lanes run TOP-DOWN in converter order, so the top lane is IBR_1 -- the same
%   order the legend above reads left to right.
nd = size(gfm,2);
ax = axes_in(f,rect_in,W,H); hold(ax,'on');
% Lane centres at 1..nd with the FIRST converter at the top: the axis is reversed
% rather than the indices, so a bar's lane is its converter's index everywhere in
% this function.
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
% NO event rules on the strip either, for the same reason they are off the panels:
% the owner took the vertical dashed rules off this page. A bar's own left edge
% already dates the mode change, and provenance.txt lists every scheduled instant.
xlim(ax,xr);
ylim(ax,[0.5 nd+0.5]);
% No frame, no ticks, no grid: the strip is a legend for the panel below, not a
% second plot. Its x axis is the panel's, already labelled there, and a duplicate
% set of time ticks would say the same thing twice on a 0.4 in strip.
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
function FQ = converter_frequency(C,d,nt,nd)
%CONVERTER_FREQUENCY  Each converter's OWN frequency, at every accepted sample.
%
%   The run publishes only half of this. device_frequency_Hz is filled from the SG
%   branch and the grid-forming branch (ts_simulate_ibr_hybrid.m:4158-4166); the
%   grid-following branch records a current limit instead, so a converter that is
%   following the grid has no entry there. The grid-following controller does have
%   a frequency -- its phase-locked loop tracks it, published as f_hz by
%   gfl_eecon49_full_model.m:165 -- so the gaps are filled by calling the RUN'S OWN
%   stored device closures on the RUN'S OWN stored state, which is the same call
%   add_diagnostics makes on the same inputs. No equation is solved and no step is
%   taken: this is the model's output map evaluated at states that were already
%   accepted.
%
%   THREE GATES, each of which refuses the page rather than drawing a partial or
%   mixed trace:
%     1. reproduction -- every sample the run DID publish must come back EXACTLY
%        from the same closures. A single disagreement means these are not the
%        run's closures and nothing derived from them may be plotted.
%     2. completeness -- every ONLINE sample of every converter must end up with a
%        frequency. A remaining gap would break the trace for a reason the page
%        does not state.
%     3. one convention -- f_hz is checked against f0*omega_PLL_pu, the form the
%        published half uses. Mixing the two would put a step in the trace at every
%        mode change.
r = C.r;
FQ = struct();
if ~isfield(r,'equilibrium') || ~isstruct(r.equilibrium) || ...
        ~isfield(r.equilibrium,'devices') || isempty(r.equilibrium.devices)
    error('generate_ieee14_vf_mode_page:devicesUnrecorded', ...
        ['Cache %s carries no r.equilibrium.devices, so the converters'' own ' ...
         'output map cannot be evaluated and the grid-following stretches of ' ...
         'their frequency cannot be recovered.'],C.file);
end
for fld = {'x_traj','y_traj','u_history','event_context_history'}
    if ~isfield(r,fld{1}) || isempty(r.(fld{1}))
        error('generate_ieee14_vf_mode_page:trajectoryIncomplete', ...
            ['Cache %s lacks r.%s, which the output map needs. Nothing may be ' ...
             're-solved to replace it.'],C.file,fld{1});
    end
end
dv = r.equilibrium.devices;
xoff = cumsum([0 arrayfun(@(z)z.nx,dv(:).')]);
uoff = cumsum([0 arrayfun(@(z)z.nu,dv(:).')]);
if xoff(end) ~= size(r.x_traj,1) || uoff(end) ~= size(r.u_history,1)
    error('generate_ieee14_vf_mode_page:stateLayoutMismatch', ...
        ['The stored devices declare %d states and %d inputs but the trajectory ' ...
         'holds %d and %d. The state slices would not belong to the devices ' ...
         'they are read for.'],xoff(end),uoff(end),size(r.x_traj,1), ...
        size(r.u_history,1));
end

Fpub = nan(numel(dv),nt);
if isfield(r,'device_frequency_Hz') && ~isempty(r.device_frequency_Hz)
    Fpub = r.device_frequency_Hz(:,1:nt);
end
ON = true(numel(dv),nt);
if isfield(r,'device_online_history') && ~isempty(r.device_online_history)
    ON = logical(r.device_online_history(:,1:nt));
end

F = nan(numel(dv),nt);
src = zeros(numel(dv),nt);          % 0 none, 1 machine/forming, 2 following PLL
conv_resid = 0;
for j = 1:nt
    x = r.x_traj(:,j); y = r.y_traj(:,j); u = r.u_history(:,j);
    ec = r.event_context_history{j};
    for k = 1:numel(dv)
        if ~ON(k,j), continue; end
        z = dv(k);
        o = z.reconstruct(r.t(j),x(xoff(k)+(1:z.nx)),y,u(uoff(k)+(1:z.nu)),ec);
        if ~o.online, continue; end
        if strcmpi(o.mode,'sg')
            F(k,j) = C.f0_Hz*(1+o.omega); src(k,j) = 1;
        elseif isfield(o,'gfm')
            F(k,j) = C.f0_Hz*(1+o.gfm.omega_m); src(k,j) = 1;
        elseif isfield(o,'gfl')
            g = o.gfl;
            if isfield(g,'f_hz') && isfield(g,'omega_PLL_pu')
                conv_resid = max(conv_resid, ...
                    abs(g.f_hz - C.f0_Hz*g.omega_PLL_pu));
                F(k,j) = g.f_hz; src(k,j) = 2;
            elseif isfield(g,'omega_PLL_pu')
                F(k,j) = C.f0_Hz*g.omega_PLL_pu; src(k,j) = 2;
            end
        end
    end
end

% GATE 1 -- reproduction of what the run itself published.
REP_TOL = 0;
pubm = isfinite(Fpub);
rep_resid = 0;
if any(pubm(:))
    rep_resid = max(abs(F(pubm) - Fpub(pubm)));
end
if ~(rep_resid <= REP_TOL)
    error('generate_ieee14_vf_mode_page:frequencyReproductionFailed', ...
        ['Scenario "%s": re-evaluating the stored device closures does NOT ' ...
         'reproduce the run''s own device_frequency_Hz (max difference %.3e ' ...
         'over %d published sample(s), tolerance %g). These are not the ' ...
         'closures that produced the trajectory, so no frequency derived from ' ...
         'them may be drawn.'],C.id,rep_resid,sum(pubm(:)),REP_TOL);
end

% GATE 3 -- one convention across the two halves. Floating-point only: the two
% expressions are algebraically identical, so anything above a few ulp of 60 means
% the grid-following branch has changed its definition.
CONV_TOL = 1e-9;
if conv_resid > CONV_TOL
    error('generate_ieee14_vf_mode_page:frequencyConventionMismatch', ...
        ['Scenario "%s": the grid-following branch''s f_hz and its own ' ...
         'f_0*omega_PLL_pu differ by %.3e (> %.1e). The two halves of each ' ...
         'trace would be in different conventions and every mode change would ' ...
         'show a step that is not in the run.'],C.id,conv_resid,CONV_TOL);
end

% The four converters, in the deck's own order, as the decision bundle maps them.
rows = d.device_result_rows;
if numel(rows) ~= nd
    error('generate_ieee14_vf_mode_page:deviceRowCountMismatch', ...
        ['The decision bundle maps %d device row(s) but the page draws %d ' ...
         'converters. A trace would be attributed to the wrong converter.'], ...
        numel(rows),nd);
end
Fc = F(rows,:).';
ONc = ON(rows,:).';
srcc = src(rows,:).';

% GATE 2 -- completeness over the samples a converter was in service.
n_gap = sum(sum(ONc & ~isfinite(Fc)));
if n_gap > 0
    error('generate_ieee14_vf_mode_page:frequencyIncomplete', ...
        ['Scenario "%s": %d sample(s) leave a converter in service with no ' ...
         'frequency. The panel would break its trace for a reason the page ' ...
         'does not state.'],C.id,n_gap);
end

FQ.f = Fc;
FQ.source = srcc;
FQ.diagnostics = struct( ...
    'n_published_by_run',sum(sum(isfinite(Fpub(rows,:)))), ...
    'n_from_forming_branch',sum(sum(srcc == 1)), ...
    'n_from_following_pll',sum(sum(srcc == 2)), ...
    'n_offline_samples',sum(sum(~ONc)), ...
    'reproduction_residual_Hz',rep_resid, ...
    'reproduction_tolerance_Hz',REP_TOL, ...
    'convention_residual_Hz',conv_resid, ...
    'convention_tolerance_Hz',CONV_TOL, ...
    'range_per_converter_Hz',[min(Fc,[],1); max(Fc,[],1)]);
end

% ==========================================================================
function iv = true_intervals(mask,t)
%TRUE_INTERVALS  Contiguous [t_start t_end] runs of a logical mask.
%   A single-sample run is given the width of one step to its neighbour, because a
%   zero-width patch draws nothing at all -- the interval would vanish rather than
%   be small. Nothing wider is ever widened.
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
%   excursion outside the window, which is only admissible because mark_offscale
%   then annotates it at the frame with its peak.
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
%FINISH_PANEL  No box, ticks outward, dashed major and minor grid, deck typeface
%   through the 'tex' interpreter.
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
% Panel tag BELOW the x label, centred, outside the axes -- the placement the
% owner's reference figure uses. Inside the panel it had nowhere to go: the top is
% under the mode strip, and the bottom right is where mark_offscale prints the
% down-arrow annotation, which it collided with.
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
%   ONE label per direction, carrying the extreme over all channels in the colour
%   of the channel that reached it, and placed at the RIGHT EDGE rather than at the
%   peak's own instant: on this arm all four converters leave the window within the
%   same 1.5 ms, so per-channel labels landed in one pixel column and printed over
%   one another. Every channel that left is still listed individually in
%   provenance.txt -- nothing is lost, only un-stacked.
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
%   The sheet draws NO vertical rules at all (the owner took them off, 2026-09-04),
%   so this table is the page's ONLY record of when each event fell -- kept for that
%   reason rather than as a legend for something the reader can see.
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
%   grey, IBR_3 red, IBR_4 black -- the same palette the 3-D pages of this deck
%   use (generate_ieee14_agsi_mode_3d.m), so a converter keeps one hue across the
%   result slides.
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

function s = iif(c,a,b)
if c, s = a; else, s = b; end
end

% ==========================================================================
function write_provenance(odir,out)
%WRITE_PROVENANCE  Plain-text manifest beside the page.
%   Same shape as the other suite generators': a key/value header, then one block
%   per scenario naming the page with its SHA-256, mtime and the cache it came
%   from, so a reader holding one slide can tell which trajectory produced it.
p = fullfile(odir,'provenance_vf_mode.txt');
fid = fopen(p,'w');
if fid < 0
    warning('generate_ieee14_vf_mode_page:provenanceUnwritable', ...
        'Could not write %s; the figure is still valid.',p);
    return;
end
fprintf(fid,'generator: scripts/reporting/generate_ieee14_vf_mode_page.m\n');
fprintf(fid,'schema:    %s\n',out.schema);
fprintf(fid,'generated: %s\n',out.generated_utc);
fprintf(fid,'caches:    %s\n',out.cache_dir);
fprintf(fid,['style:     %g in x %g in, %s %g pt, tex interpreter, %s, box ' ...
    'off, ticks out\n'],out.style.width_in,out.style.height_in, ...
    out.style.font_name,out.style.font_size,out.style.grid);
fprintf(fid,'\n');
fprintf(fid,['ONE SHEET per scenario, two columns side by side under one ' ...
    'converter legend. Each column\n  is a "GFM Mode Active" STRIP above a data ' ...
    'panel:\n' ...
    '    (a) |V_i| at each converter bus, against THAT BUS''s own healthy ' ...
    'power-flow level\n' ...
    '    (b) f_i, the frequency of each converter ITSELF, with the nominal\n' ...
    '  The strip is a separate axes, not an overlay inside the data area, so a ' ...
    'bar can never\n  sit on a trace and the traces keep the whole panel ' ...
    'height.\n\n']);
fprintf(fid,['Cache reader. No step is taken, no equation is solved, and ' ...
    'nothing is smoothed,\n  filtered, decimated, clipped, offset, interpolated ' ...
    'or padded. Every plotted value is\n  either a raw accepted sample from the ' ...
    'stored trajectory or the RUN''S OWN output map\n  evaluated on that stored ' ...
    'state -- see the frequency note below, where that path is\n  gated.\n\n']);
fprintf(fid,['THE MODE STRIP is the outcome of the supervisor comparing S ' ...
    'against Gamma_on/Gamma_off,\n  which is why this page refuses to draw ' ...
    'without the threshold pair the run used. Each\n  bar spans one CONTIGUOUS ' ...
    'grid-forming interval at its TRUE extent -- no minimum width\n  is applied, ' ...
    'because widening a short interval to make it visible would draw a\n' ...
    '  grid-forming stretch that did not happen. A converter with no bar was ' ...
    'never\n  grid-forming on this arm, and that absence is the fact.\n\n']);
fprintf(fid,['PANEL (b) IS THE CONVERTERS'' OWN FREQUENCY, not the ' ...
    'centre-of-inertia frequency.\n  The run publishes only half of it: ' ...
    'add_diagnostics fills device_frequency_Hz from the\n  SG branch and the ' ...
    'grid-forming branch (ts_simulate_ibr_hybrid.m:4158-4166), while the\n' ...
    '  grid-following branch records a current limit instead. The grid-following ' ...
    'controller\n  DOES have a frequency -- its phase-locked loop tracks it, ' ...
    'published as f_hz by\n  gfl_eecon49_full_model.m:165 -- so the missing ' ...
    'stretches are recovered by calling the\n  run''s OWN stored device closures ' ...
    '(r.equilibrium.devices) on the run''s OWN stored state\n  at each accepted ' ...
    'sample: the same call add_diagnostics makes, on the same inputs.\n' ...
    '  THREE GATES make that admissible, and each refuses the page rather than ' ...
    'drawing a\n  partial or mixed trace:\n' ...
    '    1. reproduction -- every sample the run DID publish must come back ' ...
    'EXACTLY from the\n       same closures (tolerance 0)\n' ...
    '    2. completeness -- every ONLINE sample of every converter must end up ' ...
    'with a\n       frequency, so no trace breaks for an unstated reason\n' ...
    '    3. one convention -- f_hz is checked against f_0*omega_PLL_pu, the form ' ...
    'the published\n       half uses, so no mode change shows a step that is not ' ...
    'in the run\n  All three residuals and counts are reported per scenario ' ...
    'below.\n\n']);
fprintf(fid,['NO J = 1 RULES ON EITHER PANEL, at the owner''s instruction ' ...
    '(2026-09-04): the dashed\n  band edges are off the sheet. The index measures ' ...
    'its frequency term on f_COI -- ONE\n  system trace, not these four -- and its ' ...
    'voltage term against each bus''s healthy level;\n  both bands belong to the ' ...
    'severity page, which shows S itself. What stays on each panel\n  is the ' ...
    'reference every trace is a deviation FROM: the healthy |V| per bus, and the\n' ...
    '  nominal f_0, which is READ from the run''s own overlay bases rather than ' ...
    'assumed.\n  The two bases are still re-derived and checked against the run''s ' ...
    'published J_V and J_f\n  below, so the page is still verified against the ' ...
    'index it no longer draws.\n\n']);
fprintf(fid,['Y WINDOWS on a faulted arm are computed over the OPERATING BAND ' ...
    '-- the run minus its\n  fault window plus 50 ms -- and anything outside is ' ...
    'annotated AT THE FRAME with its\n  peak value. NOTHING is dropped, filtered ' ...
    'or clipped: every sample is plotted and every\n  value outside a window is ' ...
    'listed below.\n\n']);
fprintf(fid,['The x axis spans the REQUESTED horizon, not the last accepted ' ...
    'sample: cropping to\n  the data would draw a truncated run as a finished ' ...
    'one.\n\n']);
fprintf(fid,['NO VERTICAL EVENT RULES on the sheet, at the owner''s instruction ' ...
    '(2026-09-04): the\n  dashed and dotted rules are off both panels and off the ' ...
    'mode strips. A bar''s own left\n  edge already dates the mode change, and ' ...
    'every scheduled instant the run carried is\n  listed by time, name and source ' ...
    'below -- that table is now the ONLY record of them on\n  this page.\n\n']);
fprintf(fid,'--------------------------------------------------------------\n');
for k = 1:numel(out.pages)
    g = out.pages(k);
    fprintf(fid,'%-16s %s\n',g.id,g.label);
    fprintf(fid,'  cache      %s\n',g.cache);
    if isfile(g.cache)
        fprintf(fid,'  cache_sha  %s\n',sha256_of(g.cache));
    end
    for a = {g.png,g.fig}
        if isempty(a{1}), continue; end
        if isfile(a{1})
            dd = dir(a{1});
            fprintf(fid,'  file       %s\n',a{1});
            fprintf(fid,'    sha256   %s\n',sha256_of(a{1}));
            fprintf(fid,'    mtime    %s\n',char(datetime(dd.datenum, ...
                'ConvertFrom','datenum','Format','yyyy-MM-dd HH:mm:ss')));
            fprintf(fid,'    bytes    %d\n',dd.bytes);
        else
            fprintf(fid,'  file       %s (MISSING)\n',a{1});
        end
    end
    fprintf(fid,'  horizon    %.6f s of %.6f s requested (reached=%d)\n', ...
        g.t_last,g.t_end_requested,g.reached_horizon);
    if ~isempty(g.defining_event)
        fprintf(fid,'  defining   %s -> %s\n',g.defining_event, ...
            iif(g.defining_event_executed,'EXECUTED', ...
                'NOT EXECUTED, the run stopped first'));
    end
    if ~isempty(g.events_not_executed)
        fprintf(fid,'  unreached  %s\n',strjoin(g.events_not_executed,', '));
    end
    fprintf(fid,'  thresholds Gamma_on=%.4f Gamma_off=%.4f\n', ...
        g.gamma_on,g.gamma_off);
    fprintf(fid,'  samples    %d over %d converter(s)\n',g.n_samples,g.n_devices);
    fprintf(fid,'  labels     deck IBR_1..IBR_%d = code %s at buses %s\n', ...
        g.n_devices,strjoin(g.device_ids_code{1},', '),mat2str(g.device_bus_ids));
    fprintf(fid,['  healthy    |V| at converter buses %s pu (NOT drawn as a ' ...
        'J_V = 1 envelope: +/-%.4f)\n'], ...
        mat2str(g.healthy_V,6),g.index_check.dV_base_pu);
    ic = g.index_check;
    fprintf(fid,['  index      re-derived from the plotted signals over %d ' ...
        'evaluated sample(s):\n'],ic.n_evaluated_samples);
    fprintf(fid,['             max|J_V-published|=%.3e  max|J_f-published|=' ...
        '%.3e  (tol %.1e)\n'],ic.max_residual_J_V,ic.max_residual_J_f, ...
        ic.tolerance);
    fprintf(fid,'             f0=%.4f Hz  df_base=%.4f Hz  dV_base=%.4f pu\n', ...
        ic.f0_Hz,ic.df_base_Hz,ic.dV_base_pu);
    fprintf(fid,'  band       %d grid-forming interval(s) drawn\n',g.n_gfm_intervals);
    fq = g.f_source;
    fprintf(fid,['  frequency  %d sample(s) the run published (SG/grid-forming), ' ...
        '%d recovered from the\n             grid-following PLL, %d offline; ' ...
        'per-converter ranges %s Hz\n'],fq.n_published_by_run, ...
        fq.n_from_following_pll,fq.n_offline_samples, ...
        mat2str(fq.range_per_converter_Hz,6));
    fprintf(fid,['             reproduction residual %.3e Hz (tol %g) -- the ' ...
        'closures reproduce what the\n             run published; convention ' ...
        'residual %.3e Hz (tol %.1e) -- f_hz agrees with\n             ' ...
        'f_0*omega_PLL_pu\n'],fq.reproduction_residual_Hz, ...
        fq.reproduction_tolerance_Hz,fq.convention_residual_Hz, ...
        fq.convention_tolerance_Hz);
    fprintf(fid,'  ranges     |V| [%.6f %.6f] pu   f_COI [%.6f %.6f] Hz\n', ...
        g.V_range_pu(1),g.V_range_pu(2),g.f_coi_range_Hz(1),g.f_coi_range_Hz(2));
    if all(isfinite(g.fault_window))
        fprintf(fid,['  window     y limits from the operating band: run minus ' ...
            '[%.4f %.4f] s (%d of %d samples kept)\n'],g.fault_window(1), ...
            g.fault_window(2),g.n_band_samples,g.n_samples);
    else
        fprintf(fid,['  window     y limits from the WHOLE run (no scheduled ' ...
            'fault, nothing excluded)\n']);
    end
    fprintf(fid,'             (a) |V| %s   (b) f %s\n', ...
        mat2str(g.V_window,6),mat2str(g.f_window,6));
    n_off = 0;
    for j = {'offscale_V','offscale_f'}
        oo = g.(j{1});
        for q = 1:numel(oo)
            if n_off == 0
                fprintf(fid,['  offscale   value(s) outside a panel window, ' ...
                    'each annotated at the frame ON the sheet:\n']);
            end
            n_off = n_off + 1;
            if strcmp(j{1},'offscale_V')
                who = g.device_ids_code{1}{oo(q).channel};
                unit = 'pu';
            else
                who = g.device_ids_code{1}{oo(q).channel};
                unit = 'Hz';
            end
            fprintf(fid,'    %-6s %-6s %12.6f %-3s at t = %.6f s\n', ...
                oo(q).direction,who,oo(q).peak,unit,oo(q).t_peak);
        end
    end
    if n_off == 0
        fprintf(fid,['  offscale   none: every sample of both panels is inside ' ...
            'its window\n']);
    end
    fprintf(fid,['  events     %d scheduled instant(s) the run carried, NOT drawn ' ...
        'on the sheet:\n'],g.n_marks);
    for j = 1:numel(g.marks)
        mk = g.marks(j);
        fprintf(fid,'    %10.4f s  %-11s %-30s %s\n', ...
            mk.t,mk.family,mk.label,mk.source);
    end
    fprintf(fid,'\n');
end
fclose(fid);
fprintf('wrote %s\n',p);
end

% ==========================================================================
function sha = sha256_of(f)
%SHA256_OF  Hex SHA-256 of a file via Java, on an absolute path.
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
