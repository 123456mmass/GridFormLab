function out = generate_ieee14_scenario_suite_figures(opts)
%GENERATE_IEEE14_SCENARIO_SUITE_FIGURES  Three slide sheets per disturbance scenario.
%
%   out = generate_ieee14_scenario_suite_figures()
%   out = generate_ieee14_scenario_suite_figures(scenarios=["former_outage"])
%
% Pure cache reader over the artifacts run_ieee14_scenario_suite wrote. Nothing
% is simulated, re-solved, smoothed, filtered, decimated, clipped, offset,
% interpolated or padded here: every plotted sample is a raw accepted value read
% from the stored trajectory.
%
% THREE SHEETS per scenario, two stacked panels each, written as
% <scenario>_pq.png, <scenario>_fv.png and <scenario>_mode.png (plus a .fig
% beside each). The grouping is by WHAT EACH SHEET ANSWERS, so one sheet is one
% slide with one subject:
%
%   _pq    (a) active power per converter     (b) reactive power per converter
%          -- what the converters delivered
%   _fv    (a) f_COI against its J_f = 1 band (b) |V| per converter bus, J_V = 1
%          -- the two signals the switching index is built from
%   _mode  (a) GFL/GFM mode, 0-1             (b) island angle-reference owner
%          -- what the framework decided
%
% Panels are STACKED, not side by side: both share the time axis, so the same
% instant sits at the same horizontal position and a reader can drop a vertical
% line through both by eye. Side by side, each axis would be half as wide and the
% 150 s span would be unreadable at slide size.
%
% The _fv sheet carries THE SIGNALS THE INDEX IS BUILT FROM, not merely a
% frequency and a voltage that look right. The supervisor consumes
%   S = min(1, max(0, 0.5*J_V + 0.5*J_f))
% with, from agsi_reference_terms.m:186-190,
%   J_V(i,q) = |V_q(i) - V_healthy(bus q)| / dV_base     dV_base   = 0.10 pu
%   J_f(i)   = |f_COI(i) - f0|             / df_base     df_base   = 0.50 Hz
% (bases frozen at ts_simulate_ibr_hybrid.m:1675-1677). Two consequences drive the
% design of that sheet and are not free choices:
%
%   * f is ONE system-wide trace, the centre-of-inertia frequency, NOT four
%     per-converter frequencies. J_f is identical across converters by
%     construction -- measured across-converter spread 0.000e+00 on 933 samples
%     where all four are online -- so drawing four frequency traces would show a
%     quantity the index never forms.
%   * V is per-converter bus voltage magnitude, measured against EACH BUS's OWN
%     healthy level from the run's power-flow reference, because J_V is a
%     deviation from that level and not from 1.0 pu.
%
% Verified by exact reconstruction rather than by reading the code: taking |V| from
% r.bus_voltage_magnitude at each converter bus and f_COI from the overlay, and
% recomputing the two sub-indices and the severity with the frozen bases,
% reproduces the run's own published values to
%   max|J_V - J_V_published| = 0.000e+00   over 9351 evaluated samples
%   max|J_f - J_f_published| = 0.000e+00
%   max|S   - S_published|   = 0.000e+00
% and the implied dV_base recovered from the published J_V is 0.100000000 with a
% spread of 1.4e-17 across all four converters. So these panels ARE the decision
% inputs, and each carries the band edge (J = 1) that made them one.
%
% The severity index S itself, which an earlier layout carried, is on none of the
% three sheets: the _fv sheet holds its two ingredients, drawn in physical units
% with their band edges, so the quantity is present in a form a reader can check
% against a measurement. S remains on the delivered deck's slide-14 figure and on
% the report's decision pages.
%
% FOUR things this generator refuses to fake, each of which a naive page would:
%
%   1. A tripped converter's mode. r.device_modes_history holds 'tripped' for a
%      converter that is out of service, and mode_gfm tests only for 'gfm', so a
%      tripped unit reads as logical false -- which on a 0-1 axis is the GFL level.
%      On former_outage that is the whole post-outage stretch of the run, drawn as
%      "IBR2 is following the grid" when IBR2 is gone. The trace is therefore
%      MASKED to NaN wherever the device is offline, leaving a visible gap, and the
%      count of masked samples goes into provenance.txt.
%   2. A tripped converter's voltage. NOT masked, and deliberately so: the bus
%      stays energised by the rest of the island, |V| there remains a measured
%      network quantity, and the index itself keeps evaluating it. Frequency needs
%      no mask at all -- f_COI is one system trace over the devices that ARE in
%      service, so a departed converter simply stops contributing to it. P and Q
%      are not masked either: a tripped converter injects no current, so its zero
%      is a measured injection and hiding it would hide the outage.
%   3. The requested horizon. The x axis spans the REQUESTED horizon and the red
%      validity rule marks where the run actually stopped, so the reader sees the
%      refusal instead of an axis quietly cropped to the data.
%   4. Frequency read from a field that does not hold it. r.device_frequency_Hz is
%      populated only on the SG and GFM branches of add_diagnostics
%      (ts_simulate_ibr_hybrid.m:4158-4166); the GFL branch records only a current
%      limit, so a GFL converter has NO frequency there -- on former_outage IBR8 is
%      finite at 0 of 2806 samples. It is not used here at all. The _fv sheet plots
%      f_COI, which the index consumes and which is finite at every sample, and
%      which the overlay and the engine publish identically (max|difference| =
%      0.000e+00 over every sample, gated inside
%      ieee14_switch_decision_signals).
%
% Lettering: the DECK typeface, Helvetica, through MATLAB's 'tex' interpreter at
% 4.65 in / 10 pt -- the owner's instruction is to use the same font as the slides,
% and presentation_pf_sssa_ts_gfm_en_v11.tex:3 sets the slide sans font to
% Helvetica. MATLAB's 'latex' interpreter typesets in Computer Modern regardless of
% FontName, so it cannot honour that instruction; the LaTeX *look* the owner asked
% for -- math italics, real Greek and proper subscripts -- is delivered by the
% 'tex' interpreter, which does letter in Helvetica. The rest of the style is the
% standing contract: no box, ticks outward, dashed major AND minor grid, each
% series identified inside its own panel or by the sheet's own shared legend.
%
% A .fig is written beside every PNG. pf_page_export's fourth argument must be
% true for that: it defaults false, and it is also what flips Visible on before
% savefig, because a .fig stored from a hidden figure reopens hidden and looks
% empty.
%
% Classification: presentation only. No value computed here feeds PF, SSSA, TS, a
% selector, a controller or an acceptance decision.

arguments
    opts.cache_dir (1,1) string = fullfile('output','diagnostics', ...
        'ieee14_scenario_suite')
    opts.out_dir (1,1) string = fullfile('docs','source','figures', ...
        'ieee14_scenario_suite')
    opts.scenarios (1,:) string = ["sg_load_step30","sg_fault_bus9", ...
        "line_fault_9_14","former_outage","sg_fault_cycle160"]
    opts.width_in (1,1) double {mustBePositive} = 4.65
    % Two stacked panels per sheet. 2.95 in gives each about 1.30 in of axis
    % height -- the same as the retired 2x2 page gave each of its four -- and the
    % whole sheet fits the ~2.9 in of usable height on a 16:9 slide at 1:1.
    opts.height_in (1,1) double {mustBePositive} = 2.95
    opts.font_size (1,1) double {mustBePositive} = 10
    opts.font_name (1,1) string = "Helvetica"
    opts.dpi (1,1) double {mustBePositive} = 300
    % Write the live MATLAB figure beside every PNG, so the artwork can be
    % reopened and adjusted without re-running the generator.
    opts.save_fig (1,1) logical = true
end

pf_init_paths();
cdir = char(opts.cache_dir);
odir = char(opts.out_dir);
if ~isfolder(odir), mkdir(odir); end

out = struct();
out.schema = 'ieee14_scenario_suite_figures/3.0';
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
    C = load_cache(cdir,id);
    page = draw_scenario(C,odir,opts);
    if isempty(out.pages), out.pages = page; else, out.pages(end+1) = page; end
    fprintf(['[%s] horizon %.6f of %.6f s | %d samples | %d mode sample(s) ' ...
             'masked offline\n'],id,page.t_last,page.t_end_requested, ...
        page.n_samples,page.n_mode_masked);
    if ~isempty(page.defining_event) && ~page.defining_event_executed
        fprintf(['[%s]   NOTE: %s never executed -- this page does NOT show ' ...
            'the disturbance the scenario exists to exercise\n'],id, ...
            page.defining_event);
    end
    if ~isempty(page.stale_arm_fields)
        fprintf(['[%s]   NOTE: this cache predates the %s declaration, so the ' ...
            'page cannot report it; re-run run_ieee14_scenario_suite to ' ...
            'refresh\n'],id,strjoin(page.stale_arm_fields,', '));
    end
end

write_provenance(odir,out);
end

% ==========================================================================
function C = load_cache(cdir,id)
%LOAD_CACHE  Read one scenario cache and everything the page needs from it.
%   The severity thresholds come from the stored option signature, not from a
%   default here. They are top-level run options and are NOT republished inside
%   result.metadata, so the signature the runner saved beside the trajectory is
%   the only record of what the supervisor actually compared S against.
f = fullfile(cdir,[id '.mat']);
if ~isfile(f)
    error('generate_ieee14_scenario_suite_figures:cacheMissing', ...
        ['No cache at %s. Run run_ieee14_scenario_suite(scenarios="%s") ' ...
         'first; this generator never simulates.'],f,id);
end
S = load(f);
for fld = {'result','arm','opt_signature'}
    if ~isfield(S,fld{1})
        error('generate_ieee14_scenario_suite_figures:cacheIncomplete', ...
            'Cache %s lacks the "%s" variable.',f,fld{1});
    end
end
C = struct();
C.id = id;
C.file = f;
C.r = S.result;
C.arm = S.arm;
C.sig = S.opt_signature;
% A cache carries the scenario declaration AS IT WAS when the run was made, which
% is the provenance this generator wants -- the page describes the run that
% happened. The hazard is a declaration that has since GAINED a field: the page
% then reports less than the current runner does, and silently, because a missing
% field and a field deliberately left empty both read as "nothing to say". They
% are distinguished here so the second stays quiet and the first is named.
C.stale_arm_fields = {};
for fld = {'defining_event'}
    if ~isfield(C.arm,fld{1})
        C.stale_arm_fields{end+1} = fld{1};
    end
end
C.gamma_on = sig_num(C.sig,'severity_gamma_on');
C.gamma_off = sig_num(C.sig,'severity_gamma_off');
C.t_end_requested = sig_num(C.sig,'t_end');
% Still required even though no panel plots S. The thresholds are what the
% supervisor compared severity against to produce the mode changes panel (e) shows,
% and provenance.txt publishes them beside that panel. Defaulting them silently
% would print a threshold pair the run may not have used, which is worse than
% refusing: the page would look explained when it was not.
if ~isfinite(C.gamma_on) || ~isfinite(C.gamma_off)
    error('generate_ieee14_scenario_suite_figures:thresholdsUnrecorded', ...
        ['Cache %s records no severity_gamma_on/off. The mode panel cannot be ' ...
         'annotated with thresholds that are not in the artifact.'],f);
end
if ~isfinite(C.t_end_requested)
    % Fall back to the validated schedule, which carries the horizon it was
    % built for. Never to the last accepted sample: on a truncated run that
    % would silently redraw the axis as though the run had finished.
    C.t_end_requested = num_or(C.r.sched,'t_end',NaN);
end
if ~isfinite(C.t_end_requested)
    error('generate_ieee14_scenario_suite_figures:horizonUnrecorded', ...
        'Cache %s records no requested horizon.',f);
end
% The index's own voltage reference and its two normalization bases. Panel (d)
% draws |V| against the HEALTHY level of each bus, because J_V is a deviation from
% that level and not from 1.0 pu, so the reference is part of the signal and not a
% cosmetic annotation. It is read from the stored signature -- the run's own
% power-flow solution -- and refused if absent rather than replaced by 1.0, which
% would draw a band no converter was ever judged against.
C.healthy_V = [];
C.healthy_bus = [];
if isstruct(C.sig) && isfield(C.sig,'healthy_pf_V') && ...
        isfield(C.sig,'healthy_pf_bus_ids')
    C.healthy_V = double(C.sig.healthy_pf_V(:));
    C.healthy_bus = double(C.sig.healthy_pf_bus_ids(:));
end
if isempty(C.healthy_V) || numel(C.healthy_V) ~= numel(C.healthy_bus)
    error('generate_ieee14_scenario_suite_figures:healthyReferenceUnrecorded', ...
        ['Cache %s records no usable healthy_pf_V / healthy_pf_bus_ids pair. ' ...
         'The voltage panel cannot show the deviation the index measures ' ...
         'without the reference the run measured it from.'],f);
end
% Frozen at ts_simulate_ibr_hybrid.m:1675-1676 and NOT caller-overridable there,
% so they are stated here as constants rather than read from an option that does
% not exist. draw_scenario verifies both against the run's own published J_V and
% J_f before drawing a single band edge, so a future change to either base is
% caught by the page instead of being silently mis-drawn.
C.dV_base = 0.10;
C.df_base_Hz = 0.50;
C.f0_Hz = 60;
end

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
function page = draw_scenario(C,odir,opts)
%DRAW_SCENARIO  The six-panel page for one scenario.
r = C.r;
d = ieee14_switch_decision_signals(r, ...
    gamma_on=C.gamma_on,gamma_off=C.gamma_off);

t   = d.t;
nt  = numel(t);
nd  = numel(d.device_ids);
col = converter_colours(nd);
fs  = opts.font_size;
FN  = char(opts.font_name);

% --- the index's own two inputs, and PROOF that they are ------------------
% f_COI as the overlay published it (already gated inside the decision bundle
% against the engine's own coi_frequency_Hz), and |V| at each converter bus from
% the raw accepted voltage solution.
f_coi = d.f_coi_Hz(:);
Vbus  = nan(nt,nd);
Vh    = nan(1,nd);
for q = 1:nd
    b = find(r.bus_ids == d.device_bus_ids(q),1);
    if isempty(b)
        error('generate_ieee14_scenario_suite_figures:busNotFound', ...
            'Converter %s sits at bus %g, which is not in r.bus_ids.', ...
            d.device_ids{q},d.device_bus_ids(q));
    end
    Vbus(:,q) = r.bus_voltage_magnitude(b,1:nt).';
    ri = find(C.healthy_bus == d.device_bus_ids(q),1);
    if isempty(ri)
        error('generate_ieee14_scenario_suite_figures:healthyBusMissing', ...
            ['The healthy power-flow reference carries no bus %g, so the ' ...
             'deviation the index measures for %s cannot be shown.'], ...
            d.device_bus_ids(q),d.device_ids{q});
    end
    Vh(q) = C.healthy_V(ri);
end

% Rebuild the two sub-indices from exactly what the panels draw and compare them
% against what the run published. This is the whole justification for these two
% panels -- that they carry the decision inputs and not merely a frequency and a
% voltage -- so it is ASSERTED on every page rather than trusted from one probe.
% A future change to a base, a reference or a bus mapping breaks the page here
% instead of producing a plausible figure annotated with the wrong band.
IDX_TOL = 1e-9;
Jf_rb = abs(f_coi - C.f0_Hz)/C.df_base_Hz;
JV_rb = abs(Vbus - repmat(Vh,nt,1))/C.dV_base;
ok = isfinite(d.terms.J_V) & isfinite(d.terms.J_f);
if ~any(ok(:))
    error('generate_ieee14_scenario_suite_figures:noIndexSamples', ...
        ['Scenario "%s" published no sample where both J_V and J_f were ' ...
         'evaluated, so the panels cannot be verified against the index.'],C.id);
end
res_JV = max(abs(JV_rb(ok) - d.terms.J_V(ok)));
Jf_mat = repmat(Jf_rb,1,nd);
res_Jf = max(abs(Jf_mat(ok) - d.terms.J_f(ok)));
S_rb = min(1,max(0,0.5*JV_rb + 0.5*Jf_mat));
res_S = max(abs(S_rb(ok) - d.S(ok)));
if res_JV > IDX_TOL || res_Jf > IDX_TOL || res_S > IDX_TOL
    error('generate_ieee14_scenario_suite_figures:indexInputMismatch', ...
        ['Scenario "%s": the signals this page plots do NOT reproduce the ' ...
         'run''s own sub-indices (max residuals J_V %.3e, J_f %.3e, S %.3e ' ...
         'over %d evaluated samples, tolerance %.1e). The panels would be ' ...
         'labelled as the decision inputs without being them.'], ...
        C.id,res_JV,res_Jf,res_S,sum(ok(:)),IDX_TOL);
end

% The x axis spans the REQUESTED horizon, not the achieved one, so a scenario
% that stopped early shows the space it did not reach instead of an axis silently
% cropped to its data.
xr = [0 max(C.t_end_requested,t(end))];

% Marks come from the validated schedule via the shared table, so every mark on
% this page is an instant READ from the run. merge_span is the visible span:
% the default tolerance is a fraction of the full horizon and would fuse
% instants a reader can separate on a 150 s axis.
M = ieee14_switch_event_marks(r,t_end=C.t_end_requested, ...
    merge_span=xr(2)-xr(1));
MARK_FAMILIES = ["disturbance","supervisor","validity"];

% --- the fault window, excluded from the AXIS but never from the data -------
% On the two faulted arms the axis is set by 99 of ~2000 samples. Measured on
% sg_fault_bus9: |V| spans [0.258 1.864] pu over the whole run but [0.551 1.138]
% pu outside the fault window -- 2.74x the span for 5 % of the samples -- and P
% spans 2.72x. The 1.86 pu peak is the 12-sample right-limit burst of the atomic
% fault-clear transaction, back inside 1.15 pu within 1.1 ms. Letting it set the
% axis compresses the islanded operating band, and the J_V = 1 envelope this panel
% exists to show, into a few percent of the tile.
%
% So the WINDOW is computed over the operating band and every channel that leaves
% it is annotated AT THE FRAME WITH ITS PEAK VALUE (mark_offscale below). This is
% the pattern the delivered report figure already uses and states its reason for
% (generate_final_report_figures_th_v2.m:1051-1068, :674-695). Nothing is dropped,
% filtered or clipped out of the data: every sample is still plotted and still
% inside the line object, and the reader is told in numbers what left the view.
%
% An arm with no scheduled fault excludes nothing -- measured span ratio exactly
% 1.00x on both such arms, so exclusion there would remove information for no
% gain.
FAULT_PAD = 0.050;      % covers the transaction decay measured at 50.1500-50.1511
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
    error('generate_ieee14_scenario_suite_figures:noOperatingBandSamples', ...
        ['Scenario "%s" has no sample outside its fault window, so no panel ' ...
         'window can be computed from the operating band.'],C.id);
end

% The service mask, applied to the one signal a departed converter cannot have:
% its mode. Shape is checked rather than assumed -- an element-by-element mask
% silently expands if either operand is transposed.
online = logical(d.online);
if ~isequal(size(online),[nt nd])
    error('generate_ieee14_scenario_suite_figures:onlineShapeMismatch', ...
        ['The online mask is %s but the page has %d samples over %d ' ...
         'converters; the mask cannot be applied element by element.'], ...
        mat2str(size(online)),nt,nd);
end

% =========================== SHEET 1: P and Q =============================
% Two stacked panels per sheet, three sheets per scenario. The six signals are
% grouped by WHAT THEY ANSWER, not to fill tiles: sheet 1 is what the converters
% delivered, sheet 2 is the pair the switching index is built from, sheet 3 is
% what the framework decided. A reader can put one sheet on one slide and the
% slide has one subject.
[f1,tl1] = new_sheet(opts);

% --- (a) active power ------------------------------------------------------
% NOT masked: a converter out of service injects no current, so its zero here is
% a measured injection and hiding it would hide the outage itself.
ax1 = nexttile(tl1); hold(ax1,'on');
h = gobjects(1,nd);
P = r.device_P_pu(d.device_result_rows,1:nt).';
for q = 1:nd
    h(q) = plot(ax1,t,P(:,q),'Color',col(q,:),'LineWidth',1.0);
end
ylP = set_panel_ylim(ax1,P(band,:),0.06);
% MARKS, on every panel of every sheet with the SAME families, so a rule at one
% instant appears at the same place on all six panels and can be read across
% sheets. No in-panel labels: a name like "line 9-14 out" spans a fifth of the
% axis, so labels would overprint one another and the traces. The three families
% are separated by LINE STYLE -- dotted for a scheduled disturbance, dash-dot for
% a supervisor commitment, solid red for the validity exit -- and every mark is
% listed by time, label and family in provenance.txt beside the sheets.
pf_draw_marks(ax1,M,labels=false,families=MARK_FAMILIES, ...
    font_name=opts.font_name,font_size=fs-2);
xlim(ax1,xr);
finish_panel(ax1,fs,FN,'{\itP} [p.u.]','','(a)');
off_P = mark_offscale(ax1,t,P,ylP,xr,col,FN,fs-2.5,'%.2f');
sheet_legend(h,d.device_ids,FN,fs);

% --- (b) reactive power ----------------------------------------------------
ax2 = nexttile(tl1); hold(ax2,'on');
Q = r.device_Q_pu(d.device_result_rows,1:nt).';
for q = 1:nd
    plot(ax2,t,Q(:,q),'Color',col(q,:),'LineWidth',1.0);
end
ylQ = set_panel_ylim(ax2,Q(band,:),0.06);
pf_draw_marks(ax2,M,labels=false,families=MARK_FAMILIES, ...
    font_name=opts.font_name,font_size=fs-2);
xlim(ax2,xr);
finish_panel(ax2,fs,FN,'{\itQ} [p.u.]','{\itt} [s]','(b)');
off_Q = mark_offscale(ax2,t,Q,ylQ,xr,col,FN,fs-2.5,'%.2f');

% ==================== SHEET 2: the index's own two inputs =================
[f2,tl2] = new_sheet(opts);

% --- (a) f_COI against the band edge that makes J_f = 1 --------------------
% ONE trace. J_f depends only on f_COI, so it is identical across converters by
% construction; four per-converter frequency traces would show a quantity the
% index never forms. The two dashed rules at f0 +/- df_base are the J_f = 1 edges:
% a reader can see how much of the severity came from frequency by eye.
ax3 = nexttile(tl2); hold(ax3,'on');
% The SYSTEM colour, deliberately NOT one of the four converter colours. The
% converter palette ends in black, and f_COI drawn in near-black next to a legend
% naming a black IBR8 reads as "this is IBR8's frequency" -- the exact
% misattribution this panel exists to prevent. Violet is the same colour sheet 3
% gives the island reference owner, so across the sheets one convention holds:
% converter palette = per-converter quantity, violet = system-wide quantity.
COI_COL = [0.25 0.10 0.55];
BAND_COL = [0.75 0.10 0.10];
plot(ax3,t,f_coi,'Color',COI_COL,'LineWidth',1.2);
yline(ax3,C.f0_Hz,'-','Color',[0.55 0.55 0.55],'LineWidth',0.6, ...
    'HandleVisibility','off');
yline(ax3,C.f0_Hz+C.df_base_Hz,'--','Color',BAND_COL,'LineWidth',0.7, ...
    'HandleVisibility','off');
yline(ax3,C.f0_Hz-C.df_base_Hz,'--','Color',BAND_COL,'LineWidth',0.7, ...
    'HandleVisibility','off');
% Named INSIDE the panel, because this sheet's legend belongs to panel (b)'s four
% converter traces and a fifth entry there would imply f_COI is a fifth converter.
% Top left is the free corner on every arm: f_COI starts at f0, a full half-band
% below the upper rule, and the first event is at t = 20 s.
text(ax3,xr(1)+0.010*(xr(2)-xr(1)),C.f0_Hz+C.df_base_Hz, ...
    ' {\itf}_{COI}: one system trace ', ...
    'Color',COI_COL,'FontName',FN,'FontSize',fs-2.5,'Interpreter','tex', ...
    'HorizontalAlignment','left','VerticalAlignment','top','Clipping','on');
% The band edges are part of the panel, so they must be INSIDE the view even on a
% scenario whose frequency never approaches them -- otherwise the same page would
% sometimes show its own reference and sometimes not.
ylF = set_panel_ylim(ax3, ...
    [f_coi(band); C.f0_Hz+C.df_base_Hz; C.f0_Hz-C.df_base_Hz],0.08);
pf_draw_marks(ax3,M,labels=false,families=MARK_FAMILIES, ...
    font_name=opts.font_name,font_size=fs-2);
xlim(ax3,xr);
finish_panel(ax3,fs,FN,'{\itf}_{COI} [Hz]','','(a)');
off_f = mark_offscale(ax3,t,f_coi,ylF,xr,COI_COL,FN,fs-2.5,'%.2f');
% The edge is named by what it MEANS, not by its number: "J_f = 1" tells the
% reader why the dashed rules are there, and the numbers are on the y axis at
% those heights.
%
% ONE label for BOTH rules, because both ARE the same contour: J_f = 1 holds at
% f0 - df_base and at f0 + df_base alike, so naming each would print the same fact
% twice.
%
% Anchored under the LOWER rule at the RIGHT edge. Every other corner is taken or
% unusable:
%   * the left half carries the event rules (20-25.3 s on every arm), and an
%     opaque background does NOT save a label there -- MATLAB draws xline through
%     a ConstantLine layer that renders above every other axes child, so the rule
%     crosses the glyphs whatever their background. That is what made an earlier
%     left-edge version read as "J_f -= 1".
%   * the top right is where mark_offscale puts its up-arrow, and on a faulted arm
%     the upper rule sits close to the top frame, so the two would overlap.
% The bottom right is free on every arm: the last scheduled instant is t = 106.3 s
% at the latest, and f_COI has settled onto f0 -- a full band above this rule --
% long before the axis ends.
text(ax3,xr(1)+0.99*(xr(2)-xr(1)),C.f0_Hz-C.df_base_Hz,'{\itJ_f} = 1 ', ...
    'Color',BAND_COL,'FontName',FN,'FontSize',fs-2.5,'Interpreter','tex', ...
    'HorizontalAlignment','right','VerticalAlignment','top','Clipping','on');

% --- (b) |V| per converter bus against the J_V = 1 band --------------------
% Each converter's OWN healthy level is the reference the index deviates from, so
% four references are drawn, one per trace, in the trace's own colour. The +/-
% dV_base envelope is shown for each as well: a converter is at J_V = 1 when it
% leaves its own envelope, not when it leaves a shared one.
ax4 = nexttile(tl2); hold(ax4,'on');
hV = gobjects(1,nd);
for q = 1:nd
    hV(q) = plot(ax4,t,Vbus(:,q),'Color',col(q,:),'LineWidth',1.0);
end
for q = 1:nd
    faint = 1 - 0.45*(1-col(q,:));      % same hue, lighter, so data stays on top
    yline(ax4,Vh(q),'-','Color',faint,'LineWidth',0.5,'HandleVisibility','off');
    yline(ax4,Vh(q)-C.dV_base,'--','Color',faint,'LineWidth',0.5, ...
        'HandleVisibility','off');
    yline(ax4,Vh(q)+C.dV_base,'--','Color',faint,'LineWidth',0.5, ...
        'HandleVisibility','off');
end
ylV = set_panel_ylim(ax4, ...
    [reshape(Vbus(band,:),[],1); (Vh(:)-C.dV_base); (Vh(:)+C.dV_base)],0.06);
pf_draw_marks(ax4,M,labels=false,families=MARK_FAMILIES, ...
    font_name=opts.font_name,font_size=fs-2);
xlim(ax4,xr);
finish_panel(ax4,fs,FN,'|{\itV_i}| [p.u.]','{\itt} [s]','(b)');
off_V = mark_offscale(ax4,t,Vbus,ylV,xr,col,FN,fs-2.5,'%.2f');
% Under the LOWEST lower envelope at the RIGHT edge, for the reasons given on
% panel (a): the left half is crossed by event rules that render above any
% background, and the top right is where the off-scale up-arrow goes. Below the
% lowest envelope no converter runs after its disturbance settles, and the run's
% deepest excursion -- inside the fault window -- is annotated at the frame instead.
text(ax4,xr(1)+0.99*(xr(2)-xr(1)),min(Vh)-C.dV_base,'{\itJ_V} = 1 ', ...
    'Color',[0.40 0.40 0.40],'FontName',FN,'FontSize',fs-2.5, ...
    'Interpreter','tex','HorizontalAlignment','right', ...
    'VerticalAlignment','top','Clipping','on');
sheet_legend(hV,d.device_ids,FN,fs);

% ================= SHEET 3: what the framework decided ====================
[f3,tl3] = new_sheet(opts);

% --- (a) GFL/GFM mode, 0-1 -------------------------------------------------
% NO display offset between converters. Where several share a mode the traces
% coincide, and that coincidence IS the fact -- a synchronous mode change; a nudge
% would invent a difference that is not there
% (generate_ieee14_mode_pq_figure.m:24-26). Line style separates them instead.
%
% MASKED where a converter is out of service. mode_gfm tests only for 'gfm', so
% the 'tripped' mode reads as logical false, which on this axis is the GFL level:
% an unmasked trace would draw a departed converter as one that is following the
% grid. The gap is the honest picture and the masked count is in provenance.txt.
ax5 = nexttile(tl3); hold(ax5,'on');
mode01 = double(d.mode_gfm);
mode01(~online) = NaN;
n_mode_masked = sum(~online(:));
MODE_LS = {'-','--',':','-.'};
hM = gobjects(1,nd);
for q = 1:nd
    hM(q) = stairs(ax5,t,mode01(:,q),MODE_LS{1+mod(q-1,numel(MODE_LS))}, ...
        'Color',col(q,:),'LineWidth',1.0);
end
ylim(ax5,[-0.25 1.25]);
pf_draw_marks(ax5,M,labels=false,families=MARK_FAMILIES, ...
    font_name=opts.font_name,font_size=fs-2);
xlim(ax5,xr);
finish_panel(ax5,fs,FN,'mode','','(a)');
set(ax5,'YTick',[0 1],'YTickLabel',{'GFL','GFM'});
% The legend is drawn from the MODE handles, so its line styles are the ones on
% this panel. Reusing sheet 1's solid-line handles would show four solid samples
% against four differently dashed traces.
sheet_legend(hM,d.device_ids,FN,fs);

% --- (b) island angle-reference owner --------------------------------------
% The FULL resource ladder is on the axis -- the machine plus every converter --
% so a reader sees which owners were AVAILABLE and not only the ones used. A
% ladder that showed only the owners taken would hide the fact that the framework
% had a choice.
ax6 = nexttile(tl3); hold(ax6,'on');
code = d.ref_code;                      % 0 = SG, 1..nd = converter j, -1 = none
lbls = [{'SG'} d.device_ids(:).'];
OWN_COL = [0.25 0.10 0.55];
% A sample with no owner is left as a GAP, not drawn at zero: zero is the
% machine, and plotting "no reference at all" on the machine's row would state
% the opposite of what happened.
plot_code = code;
plot_code(code < 0) = NaN;
stairs(ax6,t,plot_code,'Color',OWN_COL,'LineWidth',1.0);
ylim(ax6,[-0.4 nd+0.4]);
label_owner_segments(ax6,t,code,lbls,OWN_COL,FN,fs-2.5,xr);
pf_draw_marks(ax6,M,labels=false,families=MARK_FAMILIES, ...
    font_name=opts.font_name,font_size=fs-2);
xlim(ax6,xr);
finish_panel(ax6,fs,FN,'reference owner','{\itt} [s]','(b)');
set(ax6,'YTick',0:nd,'YTickLabel',lbls);

% --- export, one file pair per sheet ---------------------------------------
SHEETS = { ...
    'pq',   f1, 'converter active and reactive power'; ...
    'fv',   f2, 'the switching index inputs: f_COI and per-bus |V|'; ...
    'mode', f3, 'GFL/GFM mode and island angle-reference owner'};
pngs = cell(1,size(SHEETS,1));
figs = cell(1,size(SHEETS,1));
for s = 1:size(SHEETS,1)
    pngs{s} = fullfile(odir,sprintf('%s_%s.png',C.id,SHEETS{s,1}));
    pf_page_export(SHEETS{s,2},pngs{s},opts.dpi,opts.save_fig);
    if opts.save_fig
        figs{s} = fullfile(odir,sprintf('%s_%s.fig',C.id,SHEETS{s,1}));
    else
        figs{s} = '';
    end
end

page = struct();
page.id = C.id;
page.label = char(string(C.arm.label));
page.question = char(string(C.arm.question));
page.cache = C.file;
page.sheet_ids = SHEETS(:,1).';
page.sheet_subjects = SHEETS(:,3).';
page.pngs = pngs;
page.figs = figs;
page.n_samples = nt;
page.n_devices = nd;
page.t_last = t(end);
page.t_end_requested = C.t_end_requested;
page.reached_horizon = t(end) >= C.t_end_requested - 1e-9;
page.gamma_on = C.gamma_on;
page.gamma_off = C.gamma_off;
page.n_mode_masked = n_mode_masked;
% The index verification, recorded per page rather than only enforced: a reader of
% provenance.txt can see that the plotted f and |V| reproduced the run's own
% sub-indices, and to what residual, without re-deriving it.
page.index_check = struct( ...
    'f0_Hz',C.f0_Hz,'df_base_Hz',C.df_base_Hz,'dV_base_pu',C.dV_base, ...
    'healthy_V_at_converter_bus',Vh, ...
    'n_evaluated_samples',sum(ok(:)), ...
    'max_residual_J_V',res_JV,'max_residual_J_f',res_Jf, ...
    'max_residual_S',res_S,'tolerance',IDX_TOL);
page.f_coi_range_Hz = [min(f_coi) max(f_coi)];
page.V_range_pu = [min(Vbus(:)) max(Vbus(:))];
% What the WINDOW was computed over, and what left it. The axis on a faulted arm
% is set by the operating band, so the page must say so and must name every value
% that fell outside -- otherwise a reader could take the frame for the extent of
% the data. On an unfaulted arm the window is the whole run and every list here is
% empty, which is itself the record that nothing was excluded.
page.fault_window = fault_window;
page.n_band_samples = sum(band);
page.panel_windows = struct('P',ylP,'Q',ylQ,'f_COI',ylF,'V',ylV);
page.offscale = struct('P',off_P,'Q',off_Q,'f_COI',off_f,'V',off_V);
page.device_ids = d.device_ids;
page.n_no_owner_samples = sum(code < 0);
page.owner_codes_seen = unique(code(:)).';
page.failure_id = char_field(r,'failure_id');
page.n_marks = numel(M.marks);
page.marks = mark_table(M,MARK_FAMILIES);
% Which SCHEDULED events the run carried out, from the same helper the runner
% uses. A page can show a full-width axis and a red validity rule and still not
% tell the reader that the disturbance the scenario exists to exercise never
% happened -- "stopped at 50.08 s" and "the clearing at 50.15 s never occurred"
% are different facts, and only the second one answers what the page is for.
[page.events_executed,page.events_not_executed,page.defining_event, ...
    page.defining_event_executed] = ieee14_event_execution(r,C.arm);
page.stale_arm_fields = C.stale_arm_fields;
end

% ==========================================================================
function T = mark_table(M,families)
%MARK_TABLE  The drawn marks, as plain records for the provenance file.
%   The page carries no in-panel labels, so this table IS the legend for its
%   vertical rules. Only the families actually drawn are listed: a record of a
%   mark the page does not show would be misleading.
T = struct('t',{},'label',{},'family',{},'source',{});
for k = 1:numel(M.marks)
    m = M.marks(k);
    if ~any(strcmp(m.family,families)), continue; end
    T(end+1) = struct('t',m.t,'label',m.label,'family',m.family, ...
        'source',m.source); %#ok<AGROW>
end
end

% ==========================================================================
function finish_panel(ax,fs,FN,ylab,xlab,tag)
%FINISH_PANEL  The standing style contract: no box, ticks outward, dashed major
%   AND minor grid, deck typeface through the 'tex' interpreter.
%
%   xlim is NOT set here. The caller sets it AFTER pf_draw_marks, because
%   pf_draw_marks freezes the y limits it restores and reversing the two is the
%   defect that squashed an earlier zoom column.
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
% Panel tag at the TOP-right, unframed: the caption under the figure names each
% panel, and on these pages the traces settle into the lower half.
text(ax,0.975,0.94,tag,'Units','normalized','Interpreter','tex', ...
    'HorizontalAlignment','right','VerticalAlignment','top', ...
    'FontName',FN,'FontSize',fs);
end

% ==========================================================================
function [f,tl] = new_sheet(opts)
%NEW_SHEET  One two-panel canvas, stacked, sized for a slide.
%   Two rows and ONE column: the panels share the time axis, so stacking them puts
%   the same instant at the same horizontal position and a reader can drop a
%   vertical line through both by eye. Side by side, the axis would be half as
%   wide and the two panels would be read separately.
f = pf_page_figure(opts.width_in,opts.height_in,opts.font_size,opts.font_name);
tl = tiledlayout(f,2,1,'TileSpacing','compact','Padding','compact');
end

% ==========================================================================
function sheet_legend(h,ids,FN,fs)
%SHEET_LEGEND  One horizontal converter legend above a sheet's panels.
%   On every sheet, because each sheet is a standalone slide: a legend that
%   appeared only on the first would leave the other two unreadable when shown by
%   themselves. Layout.Tile = 'north' resolves against the legend's own parent
%   layout, which MATLAB sets from the axes the handles belong to, so the tiled
%   layout does not have to be passed in.
lg = legend(h,ids,'Orientation','horizontal','Box','off', ...
    'FontName',FN,'FontSize',fs-2,'Interpreter','tex');
lg.Layout.Tile = 'north';
end

% ==========================================================================
function yl = set_panel_ylim(ax,Y,headroom)
%SET_PANEL_YLIM  Limits from the data, with headroom, applied BEFORE the marks.
%   Every finite sample of Y must be inside the returned range. The CALLER decides
%   what Y is: passing the operating-band subset deliberately leaves a fault
%   excursion outside the window, which is only admissible because mark_offscale
%   then annotates it at the frame with its peak. Set before pf_draw_marks so the
%   marks are what get restored, not what set the range.
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
function info = mark_offscale(ax,t,Y,yl,xr,col,FN,fs,fmt)
%MARK_OFFSCALE  Flag data that leaves the panel window, with its peak value.
%   A view that silently cut an excursion would misrepresent the run, so an
%   excursion past either frame is annotated AT THE FRAME with the value it
%   reached. Same contract as the delivered report figure's helper
%   (generate_final_report_figures_th_v2.m:674-695), with two changes forced by
%   what is on these tiles:
%
%   1. ONE label per direction, carrying the extreme over ALL channels, in the
%      colour of the channel that reached it. Per-channel labels were tried and
%      were unreadable: on the faulted arms all four converters leave the window
%      within the same 1.5 ms, so four labels landed in one pixel column and
%      printed over one another. Every channel that left is still listed
%      individually in provenance.txt -- nothing is lost, only un-stacked.
%   2. Placed at the RIGHT EDGE of the axis rather than at the peak's own instant.
%      At 7.5 pt the string is about 0.4 in wide on a 2.2 in tile, which is 27 s of
%      a 150 s axis; anchored at the peak it spanned 50-77 s and printed straight
%      through the event rules at 80, 81.9 and 95 s, which is what made "2.17"
%      read as "2. 7". Every arm's last scheduled instant is before t = 100 s and
%      every trace has settled far from both frames by then, so the right quarter
%      of the axis is the one region no rule and no trace occupies. The exact
%      instant of each excursion is in provenance.txt, and the page still shows
%      WHERE it happened: the trace itself exits the window there.
%
%   Returns one record per channel that left the window, for provenance. An empty
%   return means nothing left it -- the case on every unfaulted arm.
info = struct('channel',{},'peak',{},'t_peak',{},'direction',{});
if isvector(Y), Y = Y(:); end
n = size(Y,2);
if size(col,1) < n, col = repmat(col(1,:),n,1); end

hi_v = -inf; hi_c = NaN;
lo_v =  inf; lo_c = NaN;
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
function label_owner_segments(ax,t,code,lbls,col,FN,fs,xr)
%LABEL_OWNER_SEGMENTS  One inline name per held segment of the owner trace.
%   Segments shorter than 4 % of the axis are left unlettered: the name would be
%   wider than the segment and would print over its neighbours. The ladder on the
%   y axis already names every row, so nothing is unreadable when a label is
%   skipped -- only less convenient.
span = xr(2) - xr(1);
min_seg = 0.04*span;
x_cap = xr(1) + 0.97*span;
n = numel(code);
seg0 = 1;
for i = 2:n+1
    if i > n || code(i) ~= code(seg0)
        i_end = min(i-1,n);
        if code(seg0) >= 0 && t(i_end) - t(seg0) >= min_seg
            tm = min(0.5*(t(seg0)+t(i_end)),x_cap);
            text(ax,tm,code(seg0),lbls{code(seg0)+1},'Color',col, ...
                'FontName',FN,'FontSize',fs,'Interpreter','tex', ...
                'HorizontalAlignment','center','VerticalAlignment','bottom');
        end
        seg0 = i;
    end
end
end

% ==========================================================================
function C = converter_colours(n)
%CONVERTER_COLOURS  The owner's own legend colours, in the deck's converter order.
%   Taken from the supplied reference legend (2026-09-04):
%     IBR_1 blue, IBR_2 dark grey, IBR_3 red, IBR_4 black,
%   which is bus order 2, 3, 6, 8. The retired palette
%   ([0 0.45 0.74; 0.85 0.33 0.10; 0.93 0.69 0.13; 0 0 0]) is gone from this file,
%   so these sheets and the 3-D pages of generate_ieee14_agsi_mode_3d now carry ONE
%   hue per converter across every figure of the report.
base = [0.00 0.16 0.70;   % IBR_1  blue
        0.32 0.32 0.32;   % IBR_2  dark grey
        0.84 0.10 0.11;   % IBR_3  red
        0.00 0.00 0.00];  % IBR_4  black
C = base(1:min(n,size(base,1)),:);
if n > size(base,1), C = [C; lines(n-size(base,1))]; end
end

function s = char_field(r,name)
s = '';
if isfield(r,name) && ~isempty(r.(name)), s = char(string(r.(name))); end
end

function s = iif(c,a,b)
if c, s = a; else, s = b; end
end

% ==========================================================================
function write_provenance(odir,out)
%WRITE_PROVENANCE  Plain-text manifest beside the sheets.
%   Same shape as the runner's: a key/value header, then one block per scenario
%   listing each of its three sheets with the sheet's SHA-256, its mtime and the
%   cache it came from, so a later reader holding one slide can tell WHICH
%   trajectory produced it and whether either has changed.
p = fullfile(odir,'provenance.txt');
fid = fopen(p,'w');
if fid < 0
    warning('generate_ieee14_scenario_suite_figures:provenanceUnwritable', ...
        'Could not write %s; the figures are still valid.',p);
    return;
end
fprintf(fid,'generator: scripts/reporting/generate_ieee14_scenario_suite_figures.m\n');
fprintf(fid,'schema:    %s\n',out.schema);
fprintf(fid,'generated: %s\n',out.generated_utc);
fprintf(fid,'caches:    %s\n',out.cache_dir);
fprintf(fid,'style:     %g in x %g in, %s %g pt, tex interpreter, %s grid, box off, ticks out\n', ...
    out.style.width_in,out.style.height_in,out.style.font_name, ...
    out.style.font_size,out.style.grid);
fprintf(fid,'\n');
fprintf(fid,['THREE SHEETS per scenario, two stacked panels each, so one sheet ' ...
    'is one slide with one\n  subject:\n' ...
    '    _pq    (a) active power per converter      (b) reactive power per converter\n' ...
    '    _fv    (a) f_COI vs its J_f = 1 band       (b) |V| per converter bus, J_V = 1\n' ...
    '    _mode  (a) GFL/GFM mode 0-1               (b) island angle-reference owner\n' ...
    '  Panels are stacked, not side by side: both share the time axis, so the ' ...
    'same instant\n  sits at the same horizontal position on both.\n\n']);
fprintf(fid,['Pure cache reader. Nothing is simulated, re-solved, smoothed, ' ...
    'filtered, decimated,\n  clipped, offset, interpolated or padded: every ' ...
    'plotted sample is a raw accepted\n  value from the stored trajectory.\n\n']);
fprintf(fid,['The _fv SHEET CARRIES THE SIGNALS THE SWITCHING INDEX IS ' ...
    'BUILT FROM.\n  The supervisor consumes S = min(1,max(0,0.5*J_V+0.5*J_f)) ' ...
    'with\n    J_V = |V_i - V_healthy(bus i)| / dV_base   (dV_base = 0.10 pu)\n' ...
    '    J_f = |f_COI - f0|                / df_base   (df_base = 0.50 Hz)\n' ...
    '  so f is ONE system centre-of-inertia trace, not a per-converter ' ...
    'frequency (J_f is\n  identical across converters by construction), and V ' ...
    'is each converter bus''s own\n  magnitude measured against THAT BUS''s ' ...
    'healthy power-flow level, not against 1.0 pu.\n  The dashed rules on both ' ...
    'panels are the J = 1 band edges. Every sheet set RE-DERIVES\n  J_V, J_f and ' ...
    'S from exactly what it plots and refuses to draw if they do not match\n' ...
    '  the run''s published values; the residuals are listed per scenario below.\n\n']);
fprintf(fid,['The GFL/GFM trace is MASKED to NaN wherever a converter is out ' ...
    'of service.\n  device_modes_history holds "tripped" for such a device and ' ...
    'the 0-1 trace tests only\n  for "gfm", so an unmasked panel would draw a ' ...
    'departed converter on the GFL level --\n  i.e. as one that is following ' ...
    'the grid. P, Q and |V| are NOT masked: a tripped\n  converter injects no ' ...
    'current, so its zero is measured, and its bus stays energised\n  by the ' ...
    'rest of the island, so |V| there remains a network measurement.\n\n']);
fprintf(fid,['The mode traces carry NO display offset. Where several ' ...
    'converters share a mode the\n  traces coincide, and that coincidence IS ' ...
    'the fact -- a synchronous mode change; a\n  nudge would invent a ' ...
    'difference that is not there. Line style separates them.\n\n']);
fprintf(fid,['The x axis spans the REQUESTED horizon on every sheet. A run ' ...
    'that stopped early is\n  marked with a red validity rule at its last ' ...
    'accepted sample instead of having the\n  axis cropped to its data.\n\n']);
fprintf(fid,['Y WINDOWS on a FAULTED arm are computed over the OPERATING BAND ' ...
    '-- the run minus its\n  fault window plus 50 ms -- and anything that ' ...
    'leaves the window is annotated AT THE\n  FRAME with its peak value. ' ...
    'Measured reason, on sg_fault_bus9: |V| spans\n  [0.258 1.864] pu over the ' ...
    'whole run but [0.551 1.138] pu outside the fault window --\n  2.74x the ' ...
    'span for 5 %% of the samples -- and P spans 2.72x. The 1.86 pu peak is the\n' ...
    '  12-sample right-limit burst of the atomic fault-clear transaction, back ' ...
    'inside 1.15 pu\n  within 1.1 ms. Letting it set the axis compresses the ' ...
    'islanded operating band, and the\n  J_V = 1 envelope the _fv sheet exists ' ...
    'to show, into a few percent of the panel.\n  NOTHING is dropped, filtered ' ...
    'or clipped from the data: every sample is plotted, and\n  every value ' ...
    'outside a window is listed per scenario below. An arm with no scheduled\n' ...
    '  fault excludes nothing -- measured span ratio exactly 1.00x -- so its ' ...
    'window is the\n  whole run and its off-scale list is empty.\n\n']);
fprintf(fid,['Gamma_on / Gamma_off are read per scenario from the option ' ...
    'signature stored in the cache,\n  not defaulted in the generator: they ' ...
    'are top-level run options and are not\n  republished inside the result. ' ...
    'No panel plots S, but they are what the supervisor\n  compared it against ' ...
    'to produce the mode changes the _mode sheet shows.\n\n']);
fprintf(fid,['Vertical rules are unlabelled ON the sheets -- the panels leave ' ...
    'no room for event\n  names without overprinting -- and are distinguished ' ...
    'by line style:\n  dotted = scheduled disturbance, dash-dot = supervisor ' ...
    'commitment (dotted grey when\n  refused), solid red = validity exit. Every ' ...
    'rule is listed under its scenario below,\n  with its time, its name and the ' ...
    'result field it was read from. The same rules appear\n  at the same instants ' ...
    'on all three sheets, so they can be read across them.\n\n']);
for k = 1:numel(out.pages)
    g = out.pages(k);
    fprintf(fid,'%-16s %s\n',g.id,g.label);
    fprintf(fid,'  question   %s\n',g.question);
    fprintf(fid,'  cache      %s\n',g.cache);
    if isfile(g.cache)
        fprintf(fid,'  cache_sha  %s\n',sha256_of(g.cache));
    end
    % One block per SHEET, each with its subject line, so a reader who has only
    % one slide in front of them can find which file it is and which trajectory
    % it came from.
    for s = 1:numel(g.sheet_ids)
        fprintf(fid,'  sheet      %-5s %s\n',g.sheet_ids{s},g.sheet_subjects{s});
        for a = {g.pngs{s},g.figs{s}}
            if isempty(a{1}), continue; end
            if isfile(a{1})
                dd = dir(a{1});
                fprintf(fid,'    file     %s\n',a{1});
                fprintf(fid,'      sha256 %s\n',sha256_of(a{1}));
                fprintf(fid,'      mtime  %s\n',char(datetime(dd.datenum, ...
                    'ConvertFrom','datenum','Format','yyyy-MM-dd HH:mm:ss')));
                fprintf(fid,'      bytes  %d\n',dd.bytes);
            else
                fprintf(fid,'    file     %s (MISSING)\n',a{1});
            end
        end
    end
    fprintf(fid,'  horizon    %.6f s of %.6f s requested (reached=%d)\n', ...
        g.t_last,g.t_end_requested,g.reached_horizon);
    if ~isempty(g.failure_id)
        fprintf(fid,'  failure    %s\n',g.failure_id);
    end
    if ~isempty(g.defining_event)
        fprintf(fid,'  defining   %s -> %s\n',g.defining_event, ...
            iif(g.defining_event_executed,'EXECUTED', ...
                'NOT EXECUTED, the run stopped first'));
    end
    if ~isempty(g.events_not_executed)
        fprintf(fid,'  unreached  %s\n',strjoin(g.events_not_executed,', '));
    end
    if ~isempty(g.stale_arm_fields)
        fprintf(fid,['  stale      this cache predates the %s declaration; ' ...
            're-run the suite to refresh\n'],strjoin(g.stale_arm_fields,', '));
    end
    fprintf(fid,'  thresholds Gamma_on=%.4f Gamma_off=%.4f\n',g.gamma_on,g.gamma_off);
    fprintf(fid,'  samples    %d over %d converter(s)\n',g.n_samples,g.n_devices);
    fprintf(fid,'  masked     %d mode sample(s) (converter offline)\n',g.n_mode_masked);
    ic = g.index_check;
    fprintf(fid,['  index      f0=%.4f Hz  df_base=%.4f Hz  dV_base=%.4f pu  ' ...
        'healthy |V| at converter buses %s\n'],ic.f0_Hz,ic.df_base_Hz, ...
        ic.dV_base_pu,mat2str(ic.healthy_V_at_converter_bus,6));
    fprintf(fid,['             re-derived from the plotted signals over %d ' ...
        'evaluated sample(s):\n'],ic.n_evaluated_samples);
    fprintf(fid,['             max|J_V-published|=%.3e  max|J_f-published|=' ...
        '%.3e  max|S-published|=%.3e  (tol %.1e)\n'],ic.max_residual_J_V, ...
        ic.max_residual_J_f,ic.max_residual_S,ic.tolerance);
    fprintf(fid,'  ranges     f_COI [%.6f %.6f] Hz   |V| [%.6f %.6f] pu\n', ...
        g.f_coi_range_Hz(1),g.f_coi_range_Hz(2),g.V_range_pu(1),g.V_range_pu(2));
    if all(isfinite(g.fault_window))
        fprintf(fid,['  window     y limits from the operating band: run minus ' ...
            '[%.4f %.4f] s (%d of %d samples kept)\n'],g.fault_window(1), ...
            g.fault_window(2),g.n_band_samples,g.n_samples);
    else
        fprintf(fid,['  window     y limits from the WHOLE run (no scheduled ' ...
            'fault, nothing excluded)\n']);
    end
    pw = g.panel_windows;
    fprintf(fid,'             _pq P %s  Q %s   _fv f_COI %s  |V| %s\n', ...
        mat2str(pw.P,6),mat2str(pw.Q,6),mat2str(pw.f_COI,6), ...
        mat2str(pw.V,6));
    off_names = {'P','Q','f_COI','V'};
    n_off = 0;
    for j = 1:numel(off_names)
        oo = g.offscale.(off_names{j});
        for q = 1:numel(oo)
            if n_off == 0
                fprintf(fid,['  offscale   value(s) outside a panel window, ' ...
                    'each annotated at the frame ON the sheet:\n']);
            end
            n_off = n_off + 1;
            if strcmp(off_names{j},'f_COI')
                who = 'f_COI';
            else
                who = g.device_ids{oo(q).channel};
            end
            fprintf(fid,'    %-6s %-6s %-5s %12.6f at t = %.6f s\n', ...
                off_names{j},who,oo(q).direction,oo(q).peak,oo(q).t_peak);
        end
    end
    if n_off == 0
        fprintf(fid,'  offscale   none: every sample of every panel is inside its window\n');
    end
    fprintf(fid,'  owner      codes seen %s (0 = SG), %d sample(s) with no owner\n', ...
        mat2str(g.owner_codes_seen),g.n_no_owner_samples);
    fprintf(fid,['  marks      %d (this table IS the legend for the vertical ' ...
        'rules on all three sheets)\n'],g.n_marks);
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
%   Same implementation as run_ieee14_scenario_suite.m, which is a local function
%   there and therefore not callable across files.
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
sha = sprintf('%02x', reshape(typecast(h.digest(),'uint8'),1,[]));
end
