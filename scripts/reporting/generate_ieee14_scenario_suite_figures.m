function out = generate_ieee14_scenario_suite_figures(opts)
%GENERATE_IEEE14_SCENARIO_SUITE_FIGURES  One page per added disturbance scenario.
%
%   out = generate_ieee14_scenario_suite_figures()
%   out = generate_ieee14_scenario_suite_figures(scenarios=["former_outage"])
%
% Pure cache reader over the artifacts run_ieee14_scenario_suite wrote. Nothing
% is simulated, re-solved, smoothed, filtered, decimated, clipped, offset,
% interpolated or padded here: every plotted sample is a raw accepted value read
% from the stored trajectory.
%
% Four panels per scenario, the same four the deck's slide 14 carries, so a new
% scenario can be read against the delivered chronology page without learning a
% second layout:
%
%   (a) active power per converter          (b) reactive power per converter
%   (c) severity index S vs Gamma_on/off    (d) island angle-reference owner
%
% THREE things this generator refuses to fake, each of which a naive page would:
%
%   1. A tripped converter's severity. ieee14_switch_decision_signals forms
%      S = min(1,max(0,0.5*J_V+0.5*J_f)), and the reference overlay publishes
%      J_V = J_f = NaN for a device that is out of service. max(0,NaN) is 0 in
%      MATLAB, so that clamp turns "this converter no longer has a severity" into
%      a hard zero, which on a page reads as "its disturbance ended". The
%      severity trace is therefore MASKED to NaN wherever the device is offline,
%      leaving a visible gap. P and Q are NOT masked: a tripped converter injects
%      no current, so its zero is a measured value, not an artifact of a clamp.
%   2. The requested horizon. Three of the four scenarios stop short of the 120 s
%      they were asked for. The x axis spans the REQUESTED horizon and the red
%      validity rule marks where the run actually stopped, so the reader sees the
%      refusal instead of an axis quietly cropped to the data.
%   3. The severity thresholds. Gamma_on and Gamma_off are read from the option
%      signature the runner stored beside each cache, not defaulted here: a page
%      drawn against the wrong threshold pair would misstate every switching
%      decision on it.
%
% Deck lettering, not report lettering: Helvetica through MATLAB's 'tex'
% interpreter at 4.65 in / 10 pt, matching presentation_pf_sssa_ts_gfm_en_v11.tex.
% MATLAB's 'latex' interpreter typesets in Computer Modern regardless of
% FontName, so a latex label could never match the Helvetica slide body. The rest
% of the style is the standing contract: no box, ticks outward, dashed major AND
% minor grid, each series identified inside its own panel or by one shared legend.
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
        "line_fault_9_14","former_outage"]
    opts.width_in (1,1) double {mustBePositive} = 4.65
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
out.schema = 'ieee14_scenario_suite_figures/1.0';
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
    fprintf(['[%s] horizon %.6f of %.6f s | %d samples | %d severity ' ...
             'sample(s) masked offline\n'],id,page.t_last,page.t_end_requested, ...
        page.n_samples,page.n_severity_masked);
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
if ~isfinite(C.gamma_on) || ~isfinite(C.gamma_off)
    error('generate_ieee14_scenario_suite_figures:thresholdsUnrecorded', ...
        ['Cache %s records no severity_gamma_on/off. The severity panel cannot ' ...
         'be drawn against thresholds that are not in the artifact.'],f);
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
%DRAW_SCENARIO  The four-panel page for one scenario.
r = C.r;
d = ieee14_switch_decision_signals(r, ...
    gamma_on=C.gamma_on,gamma_off=C.gamma_off);

t   = d.t;
nt  = numel(t);
nd  = numel(d.device_ids);
col = converter_colours(nd);
fs  = opts.font_size;
FN  = char(opts.font_name);

% The x axis spans the REQUESTED horizon, not the achieved one, so a scenario
% that stopped early shows the space it did not reach instead of an axis silently
% cropped to its data.
xr = [0 max(C.t_end_requested,t(end))];

% Marks come from the validated schedule via the shared table, so every mark on
% this page is an instant READ from the run. merge_span is the visible span:
% the default tolerance is a fraction of the full horizon and would fuse
% instants a reader can separate on a 120 s axis.
M = ieee14_switch_event_marks(r,t_end=C.t_end_requested, ...
    merge_span=xr(2)-xr(1));
MARK_FAMILIES = ["disturbance","supervisor","validity"];

% Severity, masked wherever a device is out of service. See the header: the
% engine's clamp maps the overlay's NaN to a hard 0, and an unmasked page would
% draw a tripped converter as the calmest device in the island.
S = d.S;
online = logical(d.online);
if ~isequal(size(online),size(S))
    error('generate_ieee14_scenario_suite_figures:onlineShapeMismatch', ...
        ['The online mask is %s but the severity array is %s; the mask cannot ' ...
         'be applied element by element.'],mat2str(size(online)),mat2str(size(S)));
end
S(~online) = NaN;
n_masked = sum(~online(:));

f = pf_page_figure(opts.width_in,opts.height_in,fs,opts.font_name);
tl = tiledlayout(f,2,2,'TileSpacing','compact','Padding','compact');

% --- (a) active power ------------------------------------------------------
% NOT masked: a converter out of service injects no current, so its zero here is
% a measured injection and hiding it would hide the outage itself.
ax1 = nexttile(tl); hold(ax1,'on');
h = gobjects(1,nd);
P = r.device_P_pu(d.device_result_rows,1:nt).';
for q = 1:nd
    h(q) = plot(ax1,t,P(:,q),'Color',col(q,:),'LineWidth',1.0);
end
set_panel_ylim(ax1,P,0.06);
% MARKS, on all four panels with the SAME families, so a rule at one instant
% appears at the same place on every panel and can be read across the page.
% No in-panel labels: each tile is about 2.2 in wide for a 120 s axis, and a
% name like "line 9-14 out" spans a fifth of that, so labels would overprint one
% another and the traces. The three families are separated by LINE STYLE --
% dotted for a scheduled disturbance, dash-dot for a supervisor commitment,
% solid red for the validity exit -- and every mark is listed by time, label and
% family in provenance.txt beside the page, so the figure stays decodable.
pf_draw_marks(ax1,M,labels=false,families=MARK_FAMILIES, ...
    font_name=opts.font_name,font_size=fs-2);
xlim(ax1,xr);
finish_panel(ax1,fs,FN,'{\itP} [p.u.]','','(a)');
% One shared legend rather than inline text: the four converters share the
% island load closely for long stretches, so inline names would overprint. It
% carries the CONVERTERS ONLY. Adding the two severity thresholds to it was
% tried and reverted: six horizontal entries are wider than a 4.65 in page and
% the last one was cut off. The thresholds are named inside panel (c) instead,
% where their own rules are.
lg = legend(h,d.device_ids,'Orientation','horizontal','Box','off', ...
    'FontName',FN,'FontSize',fs-2,'Interpreter','tex');
lg.Layout.Tile = 'north';

% --- (b) reactive power ----------------------------------------------------
ax2 = nexttile(tl); hold(ax2,'on');
Q = r.device_Q_pu(d.device_result_rows,1:nt).';
for q = 1:nd
    plot(ax2,t,Q(:,q),'Color',col(q,:),'LineWidth',1.0);
end
set_panel_ylim(ax2,Q,0.06);
pf_draw_marks(ax2,M,labels=false,families=MARK_FAMILIES, ...
    font_name=opts.font_name,font_size=fs-2);
xlim(ax2,xr);
finish_panel(ax2,fs,FN,'{\itQ} [p.u.]','','(b)');

% --- (c) severity index against its two thresholds -------------------------
% The y range is FIXED to [0 1.12] rather than fitted: S is a saturated index on
% [0,1] by construction and the two thresholds are the whole point of the panel,
% so a fitted axis would make the same threshold sit at a different height on
% every page and defeat comparison between scenarios.
ax3 = nexttile(tl); hold(ax3,'on');
for q = 1:nd
    plot(ax3,t,S(:,q),'Color',col(q,:),'LineWidth',0.9);
end
yline(ax3,C.gamma_on,'-','Color',[0.75 0.10 0.10],'LineWidth',0.7, ...
    'HandleVisibility','off');
yline(ax3,C.gamma_off,'-','Color',[0.10 0.35 0.75],'LineWidth',0.7, ...
    'HandleVisibility','off');
S_YLIM = [0 1.12];
% The severity range is the only FIXED one on the page, so it is the only one a
% sample could fall outside of. Refuse rather than clip: an axis window is a
% presentation choice, hiding a sample is not. S is saturated onto [0,1] at
% ts_simulate_ibr_hybrid.m:2973 and reconstructed the same way, so a violation
% here means the reconstruction no longer matches the engine.
s_fin = S(isfinite(S));
if ~isempty(s_fin) && (min(s_fin) < S_YLIM(1)-1e-9 || max(s_fin) > S_YLIM(2)+1e-9)
    error('generate_ieee14_scenario_suite_figures:severityOutsidePanel', ...
        ['Scenario "%s" has severity samples spanning [%.6f %.6f], outside the ' ...
         'panel window [%.6f %.6f]; the view would hide samples without ' ...
         'annotating them.'],C.id,min(s_fin),max(s_fin),S_YLIM(1),S_YLIM(2));
end
ylim(ax3,S_YLIM);
% Each rule is named by its SYMBOL only, at the left edge, above its own line.
% The numeric value is the y tick at that same height (set below), so symbol and
% number are read off one position and no page has to fit "\Gamma_{on} = 0.65"
% between its traces -- the level those traces settle at is scenario-dependent
% (on the load-step page it holds near 0.52, between the two rules), so any fixed
% in-panel position for a long name collides on some page.
%
% The chosen window is the pre-disturbance one: nothing has happened before the
% machine trips, so severity is flat near zero there on every page. That is
% ASSERTED rather than assumed, immediately below.
x_lab = xr(1) + 0.010*(xr(2)-xr(1));
t_first = num_or(r.sched,'sg_trip',NaN);
if isfinite(t_first)
    pre = t < t_first;
    s_pre = S(pre,:);
    s_pre = s_pre(isfinite(s_pre));
    if ~isempty(s_pre) && max(s_pre) > C.gamma_off - 0.02
        error('generate_ieee14_scenario_suite_figures:thresholdLabelWouldOverlap', ...
            ['Scenario "%s" reaches severity %.4f before its first scheduled ' ...
             'event, so the threshold names at the left edge would print over ' ...
             'a trace. Move them rather than letting them cover data.'], ...
            C.id,max(s_pre));
    end
end
text(ax3,x_lab,C.gamma_on+0.025,'\Gamma_{on}', ...
    'Color',[0.75 0.10 0.10],'FontName',FN,'FontSize',fs-2, ...
    'HorizontalAlignment','left','VerticalAlignment','bottom','Interpreter','tex');
text(ax3,x_lab,C.gamma_off+0.025,'\Gamma_{off}', ...
    'Color',[0.10 0.35 0.75],'FontName',FN,'FontSize',fs-2, ...
    'HorizontalAlignment','left','VerticalAlignment','bottom','Interpreter','tex');
%
pf_draw_marks(ax3,M,labels=false,families=MARK_FAMILIES, ...
    font_name=opts.font_name,font_size=fs-2);
xlim(ax3,xr);
finish_panel(ax3,fs,FN,'{\itS}','{\itt} [s]','(c)');
set(ax3,'YTick',unique([0 C.gamma_off C.gamma_on 1]));

% --- (d) island angle-reference owner --------------------------------------
% The FULL resource ladder is on the axis -- the machine plus every converter --
% so a reader sees which owners were AVAILABLE and not only the ones used. A
% ladder that showed only the owners taken would hide the fact that the framework
% had a choice.
ax4 = nexttile(tl); hold(ax4,'on');
code = d.ref_code;                      % 0 = SG, 1..nd = converter j, -1 = none
lbls = [{'SG'} d.device_ids(:).'];
OWN_COL = [0.25 0.10 0.55];
% A sample with no owner is left as a GAP, not drawn at zero: zero is the
% machine, and plotting "no reference at all" on the machine's row would state
% the opposite of what happened.
plot_code = code;
plot_code(code < 0) = NaN;
stairs(ax4,t,plot_code,'Color',OWN_COL,'LineWidth',1.0);
ylim(ax4,[-0.4 nd+0.4]);
label_owner_segments(ax4,t,code,lbls,OWN_COL,FN,fs-2.5,xr);
pf_draw_marks(ax4,M,labels=false,families=MARK_FAMILIES, ...
    font_name=opts.font_name,font_size=fs-2);
xlim(ax4,xr);
finish_panel(ax4,fs,FN,'reference owner','{\itt} [s]','(d)');
set(ax4,'YTick',0:nd,'YTickLabel',lbls);

png = fullfile(odir,[C.id '.png']);
pf_page_export(f,png,opts.dpi,opts.save_fig);

page = struct();
page.id = C.id;
page.label = char(string(C.arm.label));
page.question = char(string(C.arm.question));
page.cache = C.file;
page.png = png;
page.fig = '';
if opts.save_fig
    page.fig = fullfile(odir,[C.id '.fig']);
end
page.n_samples = nt;
page.n_devices = nd;
page.t_last = t(end);
page.t_end_requested = C.t_end_requested;
page.reached_horizon = t(end) >= C.t_end_requested - 1e-9;
page.gamma_on = C.gamma_on;
page.gamma_off = C.gamma_off;
page.n_severity_masked = n_masked;
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
function set_panel_ylim(ax,Y,headroom)
%SET_PANEL_YLIM  Limits from the data, with headroom, applied BEFORE the marks.
%   Every finite sample must be inside the returned range: an axis that clipped
%   a sample would hide a value without annotating it. Set before pf_draw_marks
%   so the marks are what get restored, not what set the range.
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
ylim(ax,[lo hi]);
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
%CONVERTER_COLOURS  The delivered deck palette, extended if a case has more.
base = [0.00 0.45 0.74; 0.85 0.33 0.10; 0.93 0.69 0.13; 0.00 0.00 0.00];
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
%WRITE_PROVENANCE  Plain-text manifest beside the pages.
%   Same shape as the runner's: a key/value header, then one block per artifact
%   with its SHA-256, its mtime and the cache it came from, so a later reader can
%   tell WHICH trajectory produced a figure and whether either has changed.
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
fprintf(fid,['Pure cache reader. Nothing is simulated, re-solved, smoothed, ' ...
    'filtered, decimated,\n  clipped, offset, interpolated or padded: every ' ...
    'plotted sample is a raw accepted\n  value from the stored trajectory.\n\n']);
fprintf(fid,['Severity is MASKED to NaN wherever a converter is out of ' ...
    'service. The engine forms\n  S = min(1,max(0,0.5*J_V+0.5*J_f)) and the ' ...
    'overlay publishes J_V = J_f = NaN for an\n  offline device; because ' ...
    'max(0,NaN) is 0 in MATLAB, an unmasked panel would draw a\n  tripped ' ...
    'converter as the calmest device in the island. P and Q are NOT masked: a\n' ...
    '  converter out of service injects no current, so its zero is measured.\n\n']);
fprintf(fid,['The x axis spans the REQUESTED horizon on every page. A run ' ...
    'that stopped early is\n  marked with a red validity rule at its last ' ...
    'accepted sample instead of having the\n  axis cropped to its data.\n\n']);
fprintf(fid,['Gamma_on / Gamma_off are read per page from the option ' ...
    'signature stored in the cache,\n  not defaulted in the generator: they ' ...
    'are top-level run options and are not\n  republished inside the result.\n\n']);
fprintf(fid,['Vertical rules are unlabelled ON the page -- four tiles about ' ...
    '2.2 in wide leave no\n  room for event names without overprinting -- and ' ...
    'are distinguished by line style:\n  dotted = scheduled disturbance, ' ...
    'dash-dot = supervisor commitment (dotted grey when\n  refused), solid red ' ...
    '= validity exit. Every rule is listed under its page below, with its\n' ...
    '  time, its name and the result field it was read from.\n\n']);
for k = 1:numel(out.pages)
    g = out.pages(k);
    fprintf(fid,'%-16s %s\n',g.id,g.label);
    fprintf(fid,'  question   %s\n',g.question);
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
    fprintf(fid,'  masked     %d severity sample(s) (device offline)\n',g.n_severity_masked);
    fprintf(fid,'  owner      codes seen %s (0 = SG), %d sample(s) with no owner\n', ...
        mat2str(g.owner_codes_seen),g.n_no_owner_samples);
    fprintf(fid,'  marks      %d (this table IS the legend for the page''s vertical rules)\n', ...
        g.n_marks);
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
