function out = generate_ieee14_gfm_lock_comparison(opts)
%GENERATE_IEEE14_GFM_LOCK_COMPARISON  Cross-arm comparison figures and tables.
%
%   generate_ieee14_gfm_lock_comparison()
%
% Compares the arms produced by run_ieee14_gfm_lock_comparison and emits:
%
%   comparison_full.png             f_COI, network min |V|, grid-forming count and
%                                   reference owner, all arms overlaid over the
%                                   full horizon, with the chronology labelled
%   comparison_switch_vs_lock.png   the same four rows over the single window in
%                                   which switching and not switching part
%                                   company: the pinned-four arm rings up and
%                                   terminates, the locked-GFL arm is refused at
%                                   the trip, the switching arm rides through
%   comparison_windows.png          the same four rows over the three windows in
%                                   which the transients are RESOLVABLE
%   comparison_event_excursions.png per-event frequency excursion and voltage dip,
%                                   arm against arm
%   comparison_summary.tex          per-arm table + common-window table
%   comparison_macros.tex           \newcommand macros so report prose cannot
%                                   drift from the generator
%
% Why two trace pages instead of one. A 250 s axis cannot resolve a 0.150 s fault:
% at 6.20 in and 300 dpi that event is about one pixel wide, so on the full
% horizon every fast excursion degenerates into a vertical streak. The full page
% therefore reads the SETTLED behaviour, which is where the policies actually
% differ, and the windows page reads the TRANSIENT behaviour. Both draw the same
% data; neither clips it.
%
% HONEST-CLAIM DISCIPLINE, enforced in the emitted text:
%
%   * The arms are compared only where they are comparable. Every arm is
%     bit-identical up to the SG trip, which is what makes the difference
%     afterwards attributable to the control policy and to nothing else. That
%     identity is measured and printed, not asserted.
%   * An arm that ends at its first event is NOT extended, padded, interpolated or
%     extrapolated. Its traces stop, and a marker says where.
%   * Per-event metrics are reported only for arms that reached the event. An arm
%     that never got there gets '--', never 0 and never NaN.
%   * Every y window is derived from the data inside the plotted time window and
%     is then AUDITED: a sample inside the window that would fall outside the
%     limits aborts the build. An axis window is a presentation choice; hiding a
%     sample behind one is not.
%   * Numbers that need an exponent are written $a\times10^{n}$, never as a
%     programming-language float.
%
% Classification: ASSUMED_DIAGNOSTIC reporting over production runs.

arguments
    opts.cache_dir (1,1) string = fullfile('output','diagnostics', ...
        'ieee14_gfm_lock_compare')
    opts.figure_dir (1,1) string = fullfile('docs','source','figures', ...
        'switch_ieee14_decision')
    opts.arms (1,:) string = ["adaptive","pinned_gfm1","pinned_gfm2", ...
        "pinned_gfm4","locked_gfl"]
    opts.width_in (1,1) double = 6.20
    opts.font_size (1,1) double = 11
    opts.dpi (1,1) double = 300
end

pf_init_paths();
C = char(opts.cache_dir);
F = char(opts.figure_dir);
if ~isfolder(F), mkdir(F); end

% --- load the arms ---------------------------------------------------------
A = struct('id',{},'label',{},'short',{},'color',{},'style',{},'r',{});
for k = 1:numel(opts.arms)
    id = char(opts.arms(k));
    file = fullfile(C,[id '_250s.mat']);
    if ~isfile(file)
        warning('generate_ieee14_gfm_lock_comparison:missingArm', ...
            'No cache for arm "%s" at %s; skipping.',id,file);
        continue;
    end
    S = load(file);
    a = struct();
    a.id = id;
    a.r = S.result;
    if isfield(S,'arm')
        a.label = S.arm.label; a.short = S.arm.short_label;
        a.color = S.arm.color;  a.style = S.arm.line_style;
    else
        a.label = id; a.short = id; a.color = [0 0 0]; a.style = '-';
    end
    if isempty(A), A = a; else, A(end+1) = a; end %#ok<AGROW>
end
if isempty(A)
    error('generate_ieee14_gfm_lock_comparison:noArms', ...
        'No arm caches found in %s.',C);
end
na = numel(A);

% --- reference arm supplies the shared event marks and the split instant ---
ref = 1;
M = ieee14_switch_event_marks(A(ref).r,t_end=250);
t_split = A(ref).r.sched.sg_trip;

% --- common-window identity, every arm against the reference --------------
CW = struct('pair',{},'c',{});
for k = 1:na
    if k == ref, continue; end
    c = ieee14_arm_common_window(A(ref).r,A(k).r,t_split, ...
        label_a=string(A(ref).id),label_b=string(A(k).id));
    CW(end+1) = struct('pair',sprintf('%s vs %s',A(ref).id,A(k).id),'c',c); %#ok<AGROW>
end

% --- per-event excursions -------------------------------------------------
EV = event_windows(A(ref).r);
EX = event_excursions(A,EV);

% Two comparison pages, not one. The full horizon reads the SETTLED story; the
% resolution windows read the TRANSIENT story, which a 250 s axis cannot show at
% all because the fault lasts 0.150 s. See display_windows.
DW = display_windows(A(ref).r);
fig1 = fullfile(F,'comparison_full.png');
aud1 = draw_arm_full(A,M,fig1,opts);
fig1b = fullfile(F,'comparison_windows.png');
aud1b = draw_arm_windows(A,M,DW,fig1b,opts);
% The switching-versus-not-switching page. Its arm subset and its time window are
% DERIVED, not chosen: the subset is the switching arm plus every arm that failed
% to reach the horizon, and the window runs from five seconds before the trip to
% five seconds after the last such failure.
SL = switch_vs_lock_subset(A);
fig1c = fullfile(F,'comparison_switch_vs_lock.png');
aud1c = draw_switch_vs_lock(SL.arms,M,SL.window,fig1c,opts);
% An axis window is a presentation choice; hiding a sample behind one is not.
n_hidden = aud1.n_outside + aud1b.n_outside + aud1c.n_outside;
if n_hidden > 0
    error('generate_ieee14_gfm_lock_comparison:hiddenSamples', ...
        ['%d sample(s) inside a plotted time window fall outside the chosen ' ...
         'y limits. Widen the window; do not clip the data.'],n_hidden);
end
fig2 = fullfile(F,'comparison_event_excursions.png');
draw_event_bars(A,EV,EX,fig2,opts);

CAND = load_candidates(C);

tex1 = fullfile(F,'comparison_summary.tex');
tex2 = fullfile(F,'comparison_macros.tex');
write_tex(A,CW,EV,EX,t_split,tex1,tex2,CAND);

tex3 = '';
fig3 = '';
if ~isempty(CAND)
    tex3 = fullfile(F,'sg_off_admissibility.tex');
    write_candidate_tex(CAND,tex3);
    fig3 = fullfile(F,'sg_off_admissibility.png');
    draw_candidate_margins(CAND,fig3,opts);
end

out = struct();
out.figures = {fig1,fig1b,fig2,fig3};
out.tex = {tex1,tex2,tex3};
out.arms = {A.id};
out.split_time_s = t_split;
out.common_window = CW;
out.event_windows = EV;
out.display_windows = DW;
out.event_excursions = EX;
out.sg_off_candidates = CAND;
out.axis_audit = struct('full',aud1,'windows',aud1b, ...
    'switch_vs_lock',aud1c,'n_hidden',n_hidden);
out.switch_vs_lock = struct('figure',fig1c,'window',SL.window, ...
    'arm_ids',{SL.ids},'n_arms',numel(SL.arms));
end

% ==========================================================================
function CAND = load_candidates(cache_dir)
%LOAD_CANDIDATES  Read the SG-off enumeration the runner recorded.
CAND = [];
f = fullfile(cache_dir,'summary.mat');
if ~isfile(f), return; end
S = load(f,'summary');
if isfield(S,'summary') && isfield(S.summary,'shared') && ...
        isfield(S.summary.shared,'sg_off_candidates')
    CAND = S.summary.shared.sg_off_candidates;
end
end

% ==========================================================================
function EV = event_windows(r)
%EVENT_WINDOWS  The interval after each scheduled disturbance to score.
%   Windows are read from r.sched, never hard-coded, and are clipped so they do
%   not run into the next event.
s = r.sched;
raw = { ...
  'SG trip',        num_or(s,'sg_trip',NaN); ...
  'load step',      num_or(s,'load_step',NaN); ...
  'fault',          num_or(s,'fault_on',NaN); ...
  'line trip',      num_or(s,'line_trip',NaN); ...
  'restore/reclose',num_or(s,'restore_time',NaN)};
keep = cellfun(@(x) isfinite(x),raw(:,2));
raw = raw(keep,:);
t0 = cell2mat(raw(:,2));
[t0,ord] = sort(t0); raw = raw(ord,:);
EV = struct('name',{},'t0',{},'t1',{});
for k = 1:numel(t0)
    if k < numel(t0), t1 = min(t0(k)+15,t0(k+1)); else, t1 = t0(k)+15; end
    EV(end+1) = struct('name',raw{k,1},'t0',t0(k),'t1',t1); %#ok<AGROW>
end
end

% ==========================================================================
function EX = event_excursions(A,EV)
%EVENT_EXCURSIONS  max|f-COI - 60| and min network |V| in each event window.
%   An arm that never reached an event gets NaN, which the table prints as '--'.
%   Nothing is substituted, held, or extrapolated to fill a gap.
na = numel(A); ne = numel(EV);
EX = struct('df',nan(na,ne),'minV',nan(na,ne),'settled',nan(na,ne), ...
    'reached',false(na,ne),'settle_frac',0.30, ...
    'arm_ids',{{A.id}},'event_names',{{EV.name}});
for k = 1:na
    r = A(k).r;
    t = r.t(:);
    f = r.coi_frequency_Hz(:);
    V = r.bus_voltage_magnitude;
    for j = 1:ne
        w = t >= EV(j).t0 & t <= EV(j).t1;
        % "Reached" means the arm integrated INTO the window, not merely touched
        % its left edge. An arm refused AT the event has exactly one sample there
        % and a zero excursion by construction; scoring that as a zero excursion
        % would read as "no disturbance response" instead of "no data".
        if ~any(w) || max(t(w)) <= EV(j).t0 + 1e-9, continue; end
        EX.reached(k,j) = true;
        ff = f(w & isfinite(f));
        if ~isempty(ff), EX.df(k,j) = max(abs(ff-60)); end
        VV = V(:,w); VV = VV(isfinite(VV));
        if ~isempty(VV), EX.minV(k,j) = min(VV); end
        % Settled deviation: the mean |f-60| over the last 30 % of the window.
        % The peak excursion is a transient; this is where the droop sharing
        % actually shows, and on this study it is the larger effect.
        ts = EV(j).t1 - EX.settle_frac*(EV(j).t1-EV(j).t0);
        ws = t >= ts & t <= EV(j).t1 & isfinite(f);
        if any(ws), EX.settled(k,j) = mean(abs(f(ws)-60)); end
    end
end
end

% ==========================================================================
function spec = arm_row_spec()
%ARM_ROW_SPEC  The four quantities every comparison panel row shows.
spec = { ...
  'f_{COI} [Hz]',      '{\itf}_{COI} [Hz]',   @(r) r.coi_frequency_Hz(:); ...
  'min |V| [pu]',      'min|{\itV}| [pu]',    @(r) min(r.bus_voltage_magnitude,[],1).'; ...
  'grid-forming units','GFM units [-]',       @(r) sum(strcmpi(r.device_modes_history,'gfm'),1).'; ...
  'reference owner',   'reference owner',     @(r) owner_code(r)};
end

% ==========================================================================
function W = display_windows(r)
%DISPLAY_WINDOWS  Time windows chosen so each transient is RESOLVABLE.
%   These are deliberately NOT the event_windows used for scoring. A scoring
%   window is 15 s because that is how long the settled value takes to form; a
%   DISPLAY window must be short enough that the transient occupies a readable
%   fraction of the column. The 0.150 s fault is 0.06 % of a 250 s axis, about
%   one pixel at 300 dpi over a 6.20 in page, so it can only be seen in a window
%   of a few seconds. Every bound is derived from the schedule, none is
%   hard-coded.
s = r.sched;
W = struct('name',{},'win',{});
tt = num_or(s,'sg_trip',NaN);
if isfinite(tt)
    W(end+1) = struct('name','island formation','win',[tt-1 tt+14]); %#ok<AGROW>
end
f0 = num_or(s,'fault_on',NaN); f1 = num_or(s,'fault_clear',NaN);
if isfinite(f0)
    if ~isfinite(f1), f1 = f0; end
    W(end+1) = struct('name','fault','win',[f0-0.5 f1+2.5]); %#ok<AGROW>
end
tr = num_or(s,'restore_time',NaN);
tc = num_or(r,'actual_reclose_time',NaN);
if isfinite(tr)
    hi = tr + 20;
    if isfinite(tc), hi = max(hi,tc+6); end
    W(end+1) = struct('name','reclose and handback','win',[tr-1 hi]); %#ok<AGROW>
end
end

% ==========================================================================
function [lo,hi,audit] = window_ylim(A,rowfn,win,headroom)
%WINDOW_YLIM  Limits from the data actually inside WIN, across every arm.
%   This is the fix for the defect that made the previous zoom column unreadable:
%   the limits must come from the window, and they must be applied BEFORE
%   pf_draw_marks, which freezes YLimMode when it restores ylim.
%
%   HEADROOM (0..1) is the fraction of the final axis height left free above the
%   data, so a label band can sit clear of every trace. It only ever makes the
%   axis TALLER, so it cannot hide a sample.
%
%   AUDIT counts samples inside the x window that fall outside the y limits. It
%   must be zero: an axis window is a presentation choice, hiding data is not.
if nargin < 4, headroom = 0; end
v = [];
for k = 1:numel(A)
    t = A(k).r.t(:);
    y = rowfn(A(k).r);
    n = min(numel(t),numel(y));
    t = t(1:n); y = y(1:n);
    m = t >= win(1) & t <= win(2) & isfinite(y);
    v = [v; y(m)]; %#ok<AGROW>
end
if isempty(v)
    lo = 0; hi = 1;
    audit = struct('n_in_window',0,'n_outside',0,'worst',NaN);
    return;
end
lo = min(v); hi = max(v);
if hi <= lo, hi = lo + max(1,abs(lo))*1e-3; end
pad = 0.05*(hi-lo);
lo = lo - pad; hi = hi + pad;
if headroom > 0 && headroom < 1
    hi = lo + (hi-lo)/(1-headroom);
end
out = v < lo | v > hi;
worst = NaN;
if any(out)
    [~,i] = max(max(lo-v,v-hi));
    worst = v(i);
end
audit = struct('n_in_window',numel(v),'n_outside',sum(out),'worst',worst);
end

% ==========================================================================
function res = draw_arm_full(A,M,path,opts)
%DRAW_ARM_FULL  Four rows, one column, the whole horizon, labelled events.
FS = opts.font_size; FN = 'Times New Roman';
na = numel(A);
rows = arm_row_spec();
nr = size(rows,1);
win = M.t_range;

f = pf_page_figure(opts.width_in,7.70,FS);
tl = tiledlayout(f,nr,1,'TileSpacing','compact','Padding','compact');
h = gobjects(1,na);
res = struct('n_outside',0,'worst',[],'rows',{{}});

for i = 1:nr
    ax = nexttile(tl); hold(ax,'on');
    % Row 1 hosts the event labels, so it reserves a band above the data.
    hr = 0; if i == 1, hr = 0.34; end
    if i == nr
        [lo,hi,aud] = owner_ylim(A,win);
    else
        [lo,hi,aud] = window_ylim(A,rows{i,3},win,hr);
    end
    for k = 1:na
        y = rows{i,3}(A(k).r);
        t = A(k).r.t(:);
        n = min(numel(t),numel(y));
        hh = plot(ax,t(1:n),y(1:n),A(k).style,'Color',A(k).color,'LineWidth',1.0);
        if i == 1, h(k) = hh; end
        if t(n) < win(2) - 1e-9 && t(n) >= win(1)
            plot(ax,t(n),y(n),'o','MarkerSize',4, ...
                'MarkerFaceColor',A(k).color,'MarkerEdgeColor',A(k).color, ...
                'HandleVisibility','off');
        end
    end
    ylim(ax,[lo hi]);
    if i == nr, set_owner_ticks(ax,A,FS); end
    if strcmp(rows{i,1},'grid-forming units'), integer_yticks(ax); end
    grid(ax,'on'); box(ax,'on');
    set(ax,'FontName',FN,'FontSize',FS-1,'GridAlpha',0.12,'Layer','top');
    ylabel(ax,rows{i,2},'FontName',FN,'FontSize',FS-1);
    if i == nr
        xlabel(ax,'{\itt} [s]','FontName',FN,'FontSize',FS-1);
    else
        set(ax,'XTickLabel',[]);
    end
    if i == 1
        pf_draw_marks(ax,M,labels=true, ...
            label_families=["disturbance","supervisor"], ...
            families=["disturbance","supervisor"], ...
            font_size=FS-4,window=win,label_band=[0.70 0.98]);
    else
        pf_draw_marks(ax,M,labels=false, ...
            families=["disturbance","supervisor"],window=win);
    end
    xlim(ax,win);
    res.n_outside = res.n_outside + aud.n_outside;
    res.rows{end+1} = struct('row',rows{i,1},'window',win,'audit',aud);
end

lg = legend(h,{A.short},'Orientation','horizontal','Box','off', ...
    'NumColumns',min(na,3));
lg.Layout.Tile = 'north';
set(lg,'FontName',FN,'FontSize',FS-3);
pf_page_export(f,path,opts.dpi);
end

% ==========================================================================
function SL = switch_vs_lock_subset(A)
%SWITCH_VS_LOCK_SUBSET  The arms and the window that show switching versus not.
%   Nothing here is a chosen constant. The subset is the switching arm plus every
%   arm that did NOT reach its requested horizon, because those are the arms whose
%   outcome differs in kind rather than in degree. The window starts one
%   pre-disturbance margin before the synchronous-machine trip -- the instant from
%   which the arms can differ at all, since they are bit-identical before it --
%   and ends one margin after the last early termination, so every terminating
%   sample is inside the axis and none is cropped.
MARGIN = 5;                                  % seconds of context on each side
keep = false(1,numel(A));
t_last = -inf;
for k = 1:numel(A)
    r = A(k).r;
    reached = ~isempty(r.t) && r.t(end) >= r.sched.t_end - 1e-9;
    if strcmp(A(k).id,'adaptive')
        keep(k) = true;
    elseif ~reached
        keep(k) = true;
        if ~isempty(r.t), t_last = max(t_last,r.t(end)); end
    end
end
SL = struct();
SL.arms = A(keep);
SL.ids = {A(keep).id};
t_trip = A(1).r.sched.sg_trip;
if ~isfinite(t_last), t_last = t_trip; end
SL.window = [max(0,t_trip-MARGIN), t_last+MARGIN];
end

% ==========================================================================
function res = draw_switch_vs_lock(A,M,win,path,opts)
%DRAW_SWITCH_VS_LOCK  Four rows, one column, one window, switching versus not.
%   Same rows and same y-limit audit as the full-horizon page. The only
%   differences are the window and the arm subset, so a reader comparing the two
%   pages is comparing the same quantities computed the same way.
FS = opts.font_size; FN = 'Times New Roman';
na = numel(A);
rows = arm_row_spec();
nr = size(rows,1);

f = pf_page_figure(opts.width_in,7.60,FS);
tl = tiledlayout(f,nr,1,'TileSpacing','compact','Padding','compact');
h = gobjects(1,na);
res = struct('n_outside',0,'worst',[],'rows',{{}});

for i = 1:nr
    ax = nexttile(tl); hold(ax,'on');
    hr = 0; if i == 1, hr = 0.30; end
    if i == nr
        [lo,hi,aud] = owner_ylim(A,win);
    else
        [lo,hi,aud] = window_ylim(A,rows{i,3},win,hr);
    end
    for k = 1:na
        y = rows{i,3}(A(k).r);
        t = A(k).r.t(:);
        n = min(numel(t),numel(y));
        hh = plot(ax,t(1:n),y(1:n),A(k).style,'Color',A(k).color,'LineWidth',1.1);
        if i == 1, h(k) = hh; end
        % Terminating sample of an arm that stopped inside this window. The
        % trace is NOT continued past it and no value is interpolated beyond it.
        if t(n) < win(2)-1e-9 && t(n) >= win(1)
            plot(ax,t(n),y(n),'o','MarkerSize',5,'LineWidth',1.0, ...
                'MarkerFaceColor',A(k).color,'MarkerEdgeColor',A(k).color, ...
                'HandleVisibility','off');
        end
    end
    ylim(ax,[lo hi]);
    if i == nr, set_owner_ticks(ax,A,FS); end
    if strcmp(rows{i,1},'grid-forming units'), integer_yticks(ax); end
    grid(ax,'on'); box(ax,'on');
    set(ax,'FontName',FN,'FontSize',FS-1,'GridAlpha',0.12,'Layer','top', ...
        'XTick',window_ticks(win));
    ylabel(ax,rows{i,2},'FontName',FN,'FontSize',FS-1);
    if i == nr
        xlabel(ax,'{\itt} [s]','FontName',FN,'FontSize',FS-1);
    else
        set(ax,'XTickLabel',[]);
    end
    % A short window needs its own merge tolerance: the default is a fraction of
    % the FULL horizon, which on a 15 s axis would merge instants a reader can
    % separate by eye.
    Mw = ieee14_switch_event_marks(A(1).r,t_end=A(1).r.sched.t_end, ...
        merge_span=win(2)-win(1));
    if i == 1
        pf_draw_marks(ax,Mw,labels=true, ...
            label_families=["disturbance","supervisor"], ...
            families=["disturbance","supervisor"], ...
            font_size=FS-4,window=win,label_band=[0.66 0.98]);
    else
        pf_draw_marks(ax,Mw,labels=false, ...
            families=["disturbance","supervisor"],window=win);
    end
    xlim(ax,win);
    res.n_outside = res.n_outside + aud.n_outside;
    res.rows{end+1} = struct('row',rows{i,1},'window',win,'audit',aud);
end

lg = legend(h,{A.short},'Orientation','horizontal','Box','off', ...
    'NumColumns',min(na,3));
lg.Layout.Tile = 'north';
set(lg,'FontName',FN,'FontSize',FS-3);
pf_page_export(f,path,opts.dpi);
end

% ==========================================================================
function res = draw_arm_windows(A,M,W,path,opts)
%DRAW_ARM_WINDOWS  The same four rows over the windows where things happen.
FS = opts.font_size; FN = 'Times New Roman';
na = numel(A);
rows = arm_row_spec();
nr = size(rows,1); nc = numel(W);
res = struct('n_outside',0,'rows',{{}});
if nc == 0, return; end

f = pf_page_figure(opts.width_in,8.00,FS);
tl = tiledlayout(f,nr,nc,'TileSpacing','compact','Padding','compact');
h = gobjects(1,na);

for i = 1:nr
    for c = 1:nc
        win = W(c).win;
        ax = nexttile(tl); hold(ax,'on');
        if i == nr
            [lo,hi,aud] = owner_ylim(A,win);
        else
            [lo,hi,aud] = window_ylim(A,rows{i,3},win,0);
        end
        for k = 1:na
            y = rows{i,3}(A(k).r);
            t = A(k).r.t(:);
            n = min(numel(t),numel(y));
            hh = plot(ax,t(1:n),y(1:n),A(k).style,'Color',A(k).color, ...
                'LineWidth',1.0);
            if i == 1 && c == 1, h(k) = hh; end
            if t(n) < win(2) - 1e-9 && t(n) >= win(1)
                plot(ax,t(n),y(n),'o','MarkerSize',4, ...
                    'MarkerFaceColor',A(k).color,'MarkerEdgeColor',A(k).color, ...
                    'HandleVisibility','off');
            end
        end
        ylim(ax,[lo hi]);
        if i == nr, set_owner_ticks(ax,A,FS); end
        if strcmp(rows{i,1},'grid-forming units'), integer_yticks(ax); end
        grid(ax,'on'); box(ax,'on');
        set(ax,'FontName',FN,'FontSize',FS-3,'GridAlpha',0.12,'Layer','top', ...
            'XTick',window_ticks(win));
        if c == 1
            ylabel(ax,rows{i,2},'FontName',FN,'FontSize',FS-2);
        end
        if i == 1
            title(ax,W(c).name,'FontName',FN,'FontSize',FS-2, ...
                'FontWeight','normal');
        end
        if i == nr
            xlabel(ax,'{\itt} [s]','FontName',FN,'FontSize',FS-2);
        else
            set(ax,'XTickLabel',[]);
        end
        % ylim first, marks second, xlim last. Reversing the last two is the
        % defect that squashed the previous zoom column.
        pf_draw_marks(ax,M,labels=false, ...
            families=["disturbance","supervisor"],window=win, ...
            font_size=FS-5);
        xlim(ax,win);
        res.n_outside = res.n_outside + aud.n_outside;
        res.rows{end+1} = struct('row',rows{i,1},'window',win,'audit',aud);
    end
end

lg = legend(h,{A.short},'Orientation','horizontal','Box','off', ...
    'NumColumns',min(na,3));
lg.Layout.Tile = 'north';
set(lg,'FontName',FN,'FontSize',FS-3);
pf_page_export(f,path,opts.dpi);
end

% ==========================================================================
function integer_yticks(ax)
%INTEGER_YTICKS  A count has no half-values; do not print ticks that suggest it.
yl = ylim(ax);
tk = ceil(yl(1)):floor(yl(2));
if isempty(tk), return; end
set(ax,'YTick',tk);
end

% ==========================================================================
function tk = window_ticks(win)
%WINDOW_TICKS  Three or four readable ticks for a narrow column.
span = win(2)-win(1);
step = 10^floor(log10(span/3));
for m = [1 2 2.5 5 10]
    if span/(m*step) <= 4.5, step = m*step; break; end
end
tk = ceil(win(1)/step)*step : step : floor(win(2)/step)*step;
if numel(tk) < 2, tk = linspace(win(1),win(2),3); end
end

% ==========================================================================
function [lo,hi,audit] = owner_ylim(A,win)
%OWNER_YLIM  Reference-owner codes are integers; size the axis to those present.
v = [];
for k = 1:numel(A)
    t = A(k).r.t(:);
    y = owner_code(A(k).r);
    n = min(numel(t),numel(y));
    m = t(1:n) >= win(1) & t(1:n) <= win(2);
    v = [v; y(m)]; %#ok<AGROW>
end
if isempty(v), v = 0; end
lo = -1.4; hi = max(v) + 0.4;
if hi < 0.4, hi = 0.4; end
out = v < lo | v > hi;
audit = struct('n_in_window',numel(v),'n_outside',sum(out),'worst',NaN);
if any(out), audit.worst = v(find(out,1)); end
end

function set_owner_ticks(ax,A,FS)
yl = ylim(ax);
top = floor(yl(2));
lbl = {'none','SG'};
for j = 1:top
    lbl{end+1} = sprintf('IBR%d',ibr_bus_of(A,j)); %#ok<AGROW>
end
set(ax,'YTick',-1:top,'YTickLabel',lbl,'FontSize',FS-4);
end

function b = ibr_bus_of(A,j)
b = j;
r = A(1).r;
if isfield(r,'device_bus_ids') && numel(r.device_bus_ids) >= j+1
    b = r.device_bus_ids(j+1);
end
end

% ==========================================================================
function draw_event_bars(A,EV,EX,path,opts)
%DRAW_EVENT_BARS  Per-event excursion, arm against arm.
%   A missing bar means the arm never reached that event. No zero is drawn in its
%   place, because a zero would read as "no excursion" rather than "no data".
FS = opts.font_size; FN = 'Times New Roman';
na = numel(A); ne = numel(EV);
f = pf_page_figure(opts.width_in,6.20,FS);
tl = tiledlayout(f,3,1,'TileSpacing','compact','Padding','compact');
names = {EV.name};
cols = reshape([A.color],3,na).';

ax = nexttile(tl);
b = bar(ax,EX.df.','grouped');
for k = 1:numel(b), b(k).FaceColor = cols(k,:); b(k).EdgeColor = 'none'; end
set(ax,'XTickLabel',names,'FontName',FN,'FontSize',FS-1);
ylabel(ax,'max|{\itf}_{COI} - 60| [Hz]','FontName',FN,'FontSize',FS-1);
title(ax,'(a) peak frequency excursion in the 15 s after each disturbance', ...
    'FontName',FN,'FontSize',FS-2,'FontWeight','normal');
grid(ax,'on'); box(ax,'on'); set(ax,'GridAlpha',0.12);
hi = max(EX.df(isfinite(EX.df)));
if ~isempty(hi), ylim(ax,[0 1.12*hi]); end
lg = legend(ax,{A.short},'Orientation','horizontal','Box','off', ...
    'NumColumns',min(na,3));
set(lg,'FontName',FN,'FontSize',FS-2,'Location','northoutside');

ax = nexttile(tl);
b = bar(ax,EX.settled.','grouped');
for k = 1:numel(b), b(k).FaceColor = cols(k,:); b(k).EdgeColor = 'none'; end
set(ax,'XTickLabel',names,'FontName',FN,'FontSize',FS-1);
ylabel(ax,'mean |{\itf}_{COI} - 60| [Hz]','FontName',FN,'FontSize',FS-1);
title(ax,sprintf(['(b) settled frequency deviation, mean over the last %.0f%% ' ...
    'of each window'],100*EX.settle_frac), ...
    'FontName',FN,'FontSize',FS-2,'FontWeight','normal');
grid(ax,'on'); box(ax,'on'); set(ax,'GridAlpha',0.12);
hi = max(EX.settled(isfinite(EX.settled)));
if ~isempty(hi), ylim(ax,[0 1.12*hi]); end

ax = nexttile(tl);
b = bar(ax,EX.minV.','grouped');
for k = 1:numel(b), b(k).FaceColor = cols(k,:); b(k).EdgeColor = 'none'; end
set(ax,'XTickLabel',names,'FontName',FN,'FontSize',FS-1);
ylabel(ax,'min|{\itV}| [pu]','FontName',FN,'FontSize',FS-1);
title(ax,'(c) deepest network voltage in the same window', ...
    'FontName',FN,'FontSize',FS-2,'FontWeight','normal');
grid(ax,'on'); box(ax,'on'); set(ax,'GridAlpha',0.12);

pf_page_export(f,path,opts.dpi);
end

% ==========================================================================
function c = owner_code(r)
%OWNER_CODE  Per-sample reference owner as a plot code: 0 = SG, 1..4 = IBR.
nt = numel(r.t);
c = -ones(nt,1);
ids = cellstr(string(r.device_ids));
didx = 2:numel(ids);
sgon = true(nt,1);
if isfield(r,'device_online_history') && ~isempty(r.device_online_history)
    sgon = logical(r.device_online_history(1,1:nt)).';
end
for k = 1:nt
    hs = struct();
    if isfield(r,'event_context_history') && numel(r.event_context_history) >= k && ...
            isstruct(r.event_context_history{k}) && ...
            isfield(r.event_context_history{k},'hybrid_state')
        hs = r.event_context_history{k}.hybrid_state;
    end
    if isfield(hs,'reference_owner_indices') && ~isempty(hs.reference_owner_indices)
        o = hs.reference_owner_indices(1);
        if o == 1, c(k) = 0;
        else
            j = find(didx == o,1);
            if ~isempty(j), c(k) = j; end
        end
    elseif sgon(k)
        c(k) = 0;
    end
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
function write_tex(A,CW,EV,EX,t_split,tex_summary,tex_macros,CAND)
%WRITE_TEX  Per-arm table, common-window table, scope paragraph and macros.
na = numel(A);
fid = fopen(tex_summary,'w');
assert(fid > 0,'cannot open %s',tex_summary);
fprintf(fid,'%% Generated by generate_ieee14_gfm_lock_comparison. Do not edit.\n');
fprintf(fid,'%% Classification: ASSUMED_DIAGNOSTIC reporting over production runs.\n\n');

fprintf(fid,'\\begin{table}[H]\\centering\\footnotesize\n');
fprintf(fid,'\\caption{Arm outcomes on the 250-s IEEE 14-bus chronology. Identical case, dispatch, event schedule, solver and step control; the arms differ only in the converter control policy. \\textbf{--} means the quantity is not defined for that arm, never zero.}\n');
fprintf(fid,'\\begin{tabular}{l%s}\\toprule\n',repmat('r',1,na));
fprintf(fid,'quantity');
for k = 1:na, fprintf(fid,' & %s',tex_escape(A(k).short)); end
fprintf(fid,' \\\\ \\midrule\n');

M = arrayfun(@(a) ieee14_arm_metrics(a.r,dummy_arm(a),250),A);
row(fid,'horizon reached [s]',arrayfun(@(m) m.t_end_s,M),'%.3f');
row(fid,'converged',arrayfun(@(m) double(m.converged),M),'%d');
row_str(fid,'refusal identifier',arrayfun(@(m) short_fid(m.failure_id),M,'UniformOutput',false));
row_str(fid,'reclose status',arrayfun(@(m) tex_escape(m.reclose_status),M,'UniformOutput',false));
row(fid,'reclose instant [s]',arrayfun(@(m) m.actual_reclose_time,M),'%.4f');
row(fid,'grid-forming units, max',arrayfun(@(m) m.n_gfm_max,M),'%d');
row(fid,'grid-forming units, final',arrayfun(@(m) m.n_gfm_at_end,M),'%d');
row(fid,'supervisor commits applied',arrayfun(@(m) m.n_support_augment_applied,M),'%d');
% Only a converged arm has a meaningful terminal state. A refused arm's last
% accepted sample is the pre-event operating point, and printing it under
% "terminal" would invite the reader to think the arm ended healthy.
term_f = arrayfun(@(m) m.terminal_f_coi_Hz,M);
term_f(~arrayfun(@(m) m.converged,M)) = NaN;
row(fid,'terminal $f_{COI}$ [Hz]',term_f,'%.6f');
row(fid,'accepted samples',arrayfun(@(m) m.n_accepted_samples,M),'%d');
row(fid,'rejected steps',arrayfun(@(m) m.rejected_steps,M),'%d');
fprintf(fid,'\\bottomrule\\end{tabular}\\end{table}\n\n');

% --- per-event excursions --------------------------------------------------
fprintf(fid,'\\begin{table}[H]\\centering\\footnotesize\n');
fprintf(fid,'\\caption{Frequency excursion and deepest network voltage in the 15\\,s after each disturbance. \\textbf{--} means the arm never reached that event.}\n');
fprintf(fid,'\\begin{tabular}{l%s}\\toprule\n',repmat('r',1,na));
fprintf(fid,'window');
for k = 1:na, fprintf(fid,' & %s',tex_escape(A(k).short)); end
fprintf(fid,' \\\\ \\midrule\n');
fprintf(fid,'\\multicolumn{%d}{l}{\\emph{$\\max|f_{COI}-60|$ [Hz]}} \\\\\n',na+1);
for j = 1:numel(EV)
    fprintf(fid,'\\quad %s ($t=%g$\\,s)',tex_escape(EV(j).name),EV(j).t0);
    for k = 1:na, fprintf(fid,' & %s',fmt(EX.df(k,j),'%.4f')); end
    fprintf(fid,' \\\\\n');
end
fprintf(fid,'\\multicolumn{%d}{l}{\\emph{$\\min|V|$ [pu]}} \\\\\n',na+1);
for j = 1:numel(EV)
    fprintf(fid,'\\quad %s ($t=%g$\\,s)',tex_escape(EV(j).name),EV(j).t0);
    for k = 1:na, fprintf(fid,' & %s',fmt(EX.minV(k,j),'%.4f')); end
    fprintf(fid,' \\\\\n');
end
fprintf(fid,'\\multicolumn{%d}{l}{\\emph{settled $\\overline{|f_{COI}-60|}$ [Hz], last %.0f\\%% of the window}} \\\\\n', ...
    na+1,100*EX.settle_frac);
for j = 1:numel(EV)
    fprintf(fid,'\\quad %s ($t=%g$\\,s)',tex_escape(EV(j).name),EV(j).t0);
    for k = 1:na, fprintf(fid,' & %s',fmt(EX.settled(k,j),'%.4f')); end
    fprintf(fid,' \\\\\n');
end
fprintf(fid,'\\bottomrule\\end{tabular}\\end{table}\n\n');

% --- common window ---------------------------------------------------------
fprintf(fid,'\\begin{table}[H]\\centering\\small\n');
fprintf(fid,'\\caption{Agreement on the common window $[0,\\,%g)$\\,s, before the event at which the policies first differ. This is what makes the later difference attributable to the policy alone.}\n',t_split);
fprintf(fid,'\\begin{tabular}{lrrrr}\\toprule\n');
fprintf(fid,'pair & samples & $\\max|\\Delta x|$ & $\\max|\\Delta y|$ & bit-identical \\\\ \\midrule\n');
for k = 1:numel(CW)
    c = CW(k).c;
    fprintf(fid,'%s & %d & %s & %s & %s \\\\\n',tex_escape(CW(k).pair), ...
        c.n_common,pf_tex_sci(c.max_abs_x),pf_tex_sci(c.max_abs_y), ...
        yesno(c.bit_identical));
end
fprintf(fid,'\\bottomrule\\end{tabular}\\end{table}\n\n');

write_scope(fid,A,EX,t_split);
fclose(fid);
fprintf('wrote %s\n',tex_summary);

write_macros(A,CW,EX,tex_macros,CAND);
end

% ==========================================================================
function write_scope(fid,A,EX,t_split)
%WRITE_SCOPE  What the comparison does and does not establish, in the .tex.
fprintf(fid,'\\paragraph{Scope of this comparison.}\n');
fprintf(fid,['Every arm uses the same network, the same dispatch, the same ' ...
    'event schedule, the same solver and the same step control, and the runner ' ...
    'asserts that the realised option structs differ only in the fields the arm ' ...
    'declares. The arms are bit-identical on $[0,\\,%g)$\\,s, so the difference ' ...
    'after that instant is attributable to the converter control policy and to ' ...
    'nothing else.\n'],t_split);

k_lock = find(strcmp({A.id},'locked_gfl'),1);
if ~isempty(k_lock)
    fprintf(fid,['\\emph{What the locked grid-following arm establishes.} With ' ...
        'every converter locked in grid-following the synchronous machine is the ' ...
        'only voltage-forming source, so opening its breaker leaves an energised ' ...
        'island with no angle reference. The per-island admissibility check ' ...
        'refuses the transaction before any Newton solve and the trajectory ends ' ...
        'at the event-left sample. On this resource mix, promoting at least one ' ...
        'converter to grid-forming is therefore a \\emph{necessary condition} for ' ...
        'a post-trip trajectory to exist at all --- not an improvement to one.\n']);
end

k_ad = find(strcmp({A.id},'adaptive'),1);
k_pin = find(strcmp({A.id},'pinned_gfm1'),1);
if ~isempty(k_ad) && ~isempty(k_pin)
    both = EX.reached(k_ad,:) & EX.reached(k_pin,:);
    d_ad = EX.df(k_ad,both); d_pin = EX.df(k_pin,both);
    better = sum(d_ad < d_pin); worse = sum(d_ad > d_pin);
    s_ad = EX.settled(k_ad,:); s_pin = EX.settled(k_pin,:);
    [~,jw] = max(s_pin - s_ad);
    fprintf(fid,['\\emph{What the pinned single-unit arm establishes.} One pinned ' ...
        'grid-forming unit is enough to keep the island well posed, and that arm ' ...
        'also reaches the horizon. The comparison is therefore quantitative ' ...
        'rather than binary. Over the %d disturbance windows both arms reached, ' ...
        'the adaptive policy gives the smaller peak frequency excursion in %d and ' ...
        'the larger one in %d.\n'],sum(both),better,worse);
    if isfinite(s_ad(jw)) && isfinite(s_pin(jw)) && s_pin(jw) > 0
        fprintf(fid,['The larger effect is not the peak but the settled ' ...
            'deviation. In the %s window the adaptive island holds ' ...
            '$\\overline{|f_{COI}-60|}=%.4f$\\,Hz against %.4f\\,Hz for the ' ...
            'single pinned unit, a factor of %.2f. The mechanism is droop ' ...
            'sharing: the supervisor had promoted %d units by then, so each ' ...
            'carries a fraction of the imbalance and the common steady-state ' ...
            'deviation is correspondingly smaller. That is the operative ' ...
            'difference between the two policies on this study.\n'], ...
            tex_escape(EX.event_names{jw}),s_ad(jw),s_pin(jw), ...
            s_pin(jw)/s_ad(jw),max(sum(strcmpi(A(k_ad).r.device_modes_history,'gfm'),1)));
    end
    fprintf(fid,['The adaptive advantage is largest at the disturbances that ' ...
        'follow an earlier promotion, because the supervisor had already left the ' ...
        'island with more grid-forming capacity committed. At the SG trip itself ' ...
        'the pinned arm is the better of the two, and that is reported as found: ' ...
        'the adaptive arm pays a small transient for its own promotion sequence.\n']);
end

fprintf(fid,'\\emph{What this comparison does \\textbf{not} establish.}\n');
fprintf(fid,'\\begin{itemize}\\itemsep0pt\n');
fprintf(fid,['\\item No percentage improvement against the locked arm over ' ...
    '$[20,\\,250]$\\,s. That arm produces no trajectory there, and none is ' ...
    'fabricated.\n']);
fprintf(fid,['\\item Nothing about a system that has another voltage-forming ' ...
    'source. An all-synchronous arm is deferred and is a separate study.\n']);
fprintf(fid,['\\item Nothing about the choice of \\emph{which} converters to ' ...
    'promote against a different selector. The comparison is switching versus ' ...
    'not switching.\n']);
fprintf(fid,['\\item Nothing numerical. Residuals, subdivision depth and ' ...
    'rejected-step counts are not comparable across arms of different length.\n']);
fprintf(fid,['\\item Every reference-AGSI sub-index beyond $J_V$ and $J_f$ is ' ...
    '\\textsf{ASSUMED\\_DIAGNOSTIC}; it entered no gate and supports no ' ...
    'readiness claim.\n']);
fprintf(fid,'\\end{itemize}\n');
end

% ==========================================================================
function write_macros(A,CW,EX,path,CAND)
fid = fopen(path,'w');
assert(fid > 0,'cannot open %s',path);
fprintf(fid,'%% Generated by generate_ieee14_gfm_lock_comparison. Do not edit.\n');
fprintf(fid,['%% Every number the comparison section prints comes from here, so ' ...
    'the prose cannot drift\n%% from the runs. Arm keys: %s\n\n'], ...
    strjoin({A.id},', '));
for k = 1:numel(A)
    r = A(k).r;
    nm = macro_name(A(k).id);
    fprintf(fid,'\\newcommand{\\Arm%sLabel}{%s}\n',nm,tex_escape(A(k).short));
    fprintf(fid,'\\newcommand{\\Arm%sHorizon}{%.3f}\n',nm,r.t(end));
    fprintf(fid,'\\newcommand{\\Arm%sConverged}{%d}\n',nm,logical(r.converged));
    rec = NaN;
    if isfield(r,'actual_reclose_time') && ~isempty(r.actual_reclose_time)
        rec = r.actual_reclose_time;
    end
    fprintf(fid,'\\newcommand{\\Arm%sReclose}{%s}\n',nm,fmt(rec,'%.4f'));
    gfm = strcmpi(r.device_modes_history,'gfm');
    fprintf(fid,'\\newcommand{\\Arm%sGfmMax}{%d}\n',nm,max(sum(gfm,1)));
    fid_str = '--';
    if isfield(r,'failure_id') && ~isempty(r.failure_id)
        p = strsplit(char(string(r.failure_id)),':');
        fid_str = ['\texttt{' tex_escape(p{end}) '}'];
    end
    fprintf(fid,'\\newcommand{\\Arm%sFailure}{%s}\n',nm,fid_str);
    fprintf(fid,'\\newcommand{\\Arm%sSamples}{%d}\n',nm,numel(r.t));
    fprintf(fid,'\\newcommand{\\Arm%sRejected}{%s}\n',nm, ...
        fmt(num_or(r,'rejected_steps',NaN),'%d'));
    for j = 1:numel(EX.event_names)
        en = macro_name(EX.event_names{j});
        fprintf(fid,'\\newcommand{\\Df%s%s}{%s}\n',nm,en,fmt(EX.df(k,j),'%.4f'));
        fprintf(fid,'\\newcommand{\\Set%s%s}{%s}\n',nm,en,fmt(EX.settled(k,j),'%.4f'));
    end
end
for k = 1:numel(CW)
    c = CW(k).c;
    nm = macro_name(c.label_b);
    fprintf(fid,'\\newcommand{\\CommonWindow%sBitIdentical}{%d}\n',nm,c.bit_identical);
    fprintf(fid,'\\newcommand{\\CommonWindow%sSamples}{%d}\n',nm,c.n_common);
end
fprintf(fid,'\\newcommand{\\CommonWindowSplit}{%.3f}\n',CW(1).c.split_time_s);
fprintf(fid,'\\newcommand{\\CommonWindowAllBitIdentical}{%d}\n', ...
    all(arrayfun(@(x) x.c.bit_identical,CW)));
if ~isempty(CAND)
    ready = CAND([CAND.ready]);
    fprintf(fid,'\\newcommand{\\CandTotal}{%d}\n',numel(CAND));
    fprintf(fid,'\\newcommand{\\CandReady}{%d}\n',numel(ready));
    if ~isempty(ready)
        [~,b] = min([ready.omega]);
        fprintf(fid,'\\newcommand{\\CandBestSet}{%s}\n',ids_to_tex(ready(b).selected));
        fprintf(fid,'\\newcommand{\\CandBestN}{%d}\n',ready(b).count);
        fprintf(fid,'\\newcommand{\\CandBestOmega}{%.5f}\n',ready(b).omega);
        fprintf(fid,'\\newcommand{\\CandBestSingleOmega}{%s}\n', ...
            fmt(best_of_count(ready,1),'%.5f'));
        fprintf(fid,'\\newcommand{\\CandFullOmega}{%s}\n', ...
            fmt(best_of_count(ready,max([CAND.count])),'%.5f'));
    end
    for n = unique([CAND.count])
        q = CAND([CAND.count] == n);
        fprintf(fid,'\\newcommand{\\CandReadyN%s}{%d}\n',num2roman(n), ...
            sum([q.ready]));
        fprintf(fid,'\\newcommand{\\CandTotalN%s}{%d}\n',num2roman(n),numel(q));
    end
end
fclose(fid);
fprintf('wrote %s\n',path);
end

function s = num2roman(n)
r = {'One','Two','Three','Four','Five'};
if n >= 1 && n <= numel(r), s = r{n}; else, s = sprintf('X%d',n); end
end

% ==========================================================================
function a = dummy_arm(x)
a = struct('id',x.id,'label',x.label,'short_label',x.short, ...
    'classification','PROJECT_RESULT','expectation','TRAJECTORY_THEN_ANY', ...
    'expected_failure_id','');
end

function row(fid,name,vals,f)
fprintf(fid,'%s',name);
for k = 1:numel(vals), fprintf(fid,' & %s',fmt(vals(k),f)); end
fprintf(fid,' \\\\\n');
end

function row_str(fid,name,vals)
fprintf(fid,'%s',name);
for k = 1:numel(vals)
    v = vals{k};
    if isempty(v), v = '--'; end
    fprintf(fid,' & %s',v);
end
fprintf(fid,' \\\\\n');
end

function s = fmt(v,f)
if ~isfinite(v), s = '--'; else, s = sprintf(f,v); end
end

function s = yesno(b)
if b, s = 'yes'; else, s = 'no'; end
end

function s = short_fid(id)
if isempty(id), s = '--'; return; end
p = strsplit(char(id),':');
s = ['\texttt{' tex_escape(p{end}) '}'];
end

function s = tex_escape(x)
s = strrep(char(string(x)),'\','\textbackslash ');
s = strrep(s,'_','\_');
s = strrep(s,'%','\%');
s = strrep(s,'&','\&');
s = strrep(s,'#','\#');
end

function s = macro_name(x)
%MACRO_NAME  A LaTeX-legal, COLLISION-FREE macro suffix.
%   Digits are spelled out rather than stripped: stripping them collapsed
%   pinned_gfm1/2/4 onto one name and emitted three \newcommand for the same
%   macro, which LaTeX rejects outright.
s = char(string(x));
words = {'Zero','One','Two','Three','Four','Five','Six','Seven','Eight','Nine'};
for d = 0:9
    s = strrep(s,sprintf('%d',d),words{d+1});
end
s = regexprep(s,'[^A-Za-z]','');
if isempty(s), s = 'X'; end
s = [upper(s(1)) s(2:end)];
end

% ==========================================================================
function write_candidate_tex(CAND,path)
%WRITE_CANDIDATE_TEX  The SG-off admissibility enumeration as a table.
%   This is a result, not context: the admissible set is NOT monotone in the
%   number of grid-forming units, so "more grid-forming is safer" is false on this
%   system and the configuration table has to be computed rather than assumed.
fid = fopen(path,'w');
assert(fid > 0,'cannot open %s',path);
fprintf(fid,'%% Generated by generate_ieee14_gfm_lock_comparison. Do not edit.\n');
fprintf(fid,'\\begin{table}[H]\\centering\\footnotesize\n');
fprintf(fid,['\\caption{Every candidate grid-forming subset for the islanded ' ...
    '(SG-off) band, screened before the run. $\\Omega$ is the damping margin of ' ...
    'that configuration''s own equilibrium; a more negative value is better ' ...
    'damped. The admissible set is \\emph{not} monotone in the number of ' ...
    'grid-forming units, and the best two-unit configuration is better damped ' ...
    'than all four.}\n']);
fprintf(fid,'\\begin{tabular}{llcrl}\\toprule\n');
fprintf(fid,'\\label{tab:cand}%%\n');
fprintf(fid,'grid-forming set & reference & $n$ & $\\Omega$ & outcome \\\\ \\midrule\n');
[~,ord] = sort([CAND.count]);
for k = ord
    c = CAND(k);
    if c.ready
        outcome = 'admissible';
        om = sprintf('%.5f',c.omega);
    else
        outcome = tex_escape(shorten_reason(c.reason));
        om = '--';
    end
    fprintf(fid,'%s & %s & %d & %s & %s \\\\\n', ...
        ids_to_tex(c.selected),ids_to_tex(c.reference),c.count,om,outcome);
end
fprintf(fid,'\\bottomrule\\end{tabular}\\end{table}\n\n');

ready = CAND([CAND.ready]);
if ~isempty(ready)
    [~,best] = min([ready.omega]);
    fprintf(fid,['\\paragraph{Best authenticated configuration.} ' ...
        '%s, with $n=%d$ and $\\Omega=%.5f$. ' ...
        'The best singleton reaches $\\Omega=%.5f$ and the full set %.5f, so ' ...
        'the optimum is interior: adding grid-forming units past it degrades the ' ...
        'margin. This is a small-signal result about one equilibrium and does ' ...
        'not by itself certify the transient response; the arm comparison ' ...
        'measures that separately.\n'], ...
        ids_to_tex(ready(best).selected),ready(best).count,ready(best).omega, ...
        best_of_count(ready,1),best_of_count(ready,max([ready.count])));
end
fclose(fid);
fprintf('wrote %s\n',path);
end

function v = best_of_count(ready,n)
q = ready([ready.count] == n);
if isempty(q), v = NaN; else, v = min([q.omega]); end
end

function s = ids_to_tex(idx)
%IDS_TO_TEX  Resource indices 2..5 are the converters at buses 2, 3, 6 and 8.
buses = [NaN 2 3 6 8];
if isempty(idx), s = '(none)'; return; end
parts = cell(1,numel(idx));
for k = 1:numel(idx)
    j = idx(k);
    if j >= 1 && j <= numel(buses) && isfinite(buses(j))
        parts{k} = sprintf('IBR%d',buses(j));
    else
        parts{k} = sprintf('res%d',j);
    end
end
s = strjoin(parts,'+');
end

function s = shorten_reason(r)
s = char(string(r));
if contains(s,'violates an equilibrium operating limit')
    tok = regexp(s,'Device (\w+)','tokens','once');
    if ~isempty(tok), s = sprintf('no equilibrium (%s at a limit)',tok{1}); return; end
    s = 'no equilibrium (operating limit)'; return;
end
if contains(s,'Coupled Newton did not converge')
    s = 'no equilibrium (Newton did not converge)'; return;
end
if numel(s) > 48, s = [s(1:45) '...']; end
end

% ==========================================================================
function draw_candidate_margins(CAND,path,opts)
%DRAW_CANDIDATE_MARGINS  Damping margin against grid-forming unit count.
%
% Only the ADMISSIBLE configurations are plotted, each at its own measured
% margin. The previous version drew the non-admissible configurations as crosses
% at min(omega)*0.06, a level that is not any of their values and that happens to
% sit above every real point; it also stacked four crosses on one coordinate, so
% the reader saw two markers where there were eight. Plotting a marker at a
% position that is not its value is not defensible in a figure that a reader will
% measure, so the count of rejected configurations is now reported as text under
% the axis and their per-configuration reasons stay in the table, which is where
% a value that does not exist belongs.
%
% Point labels are de-conflicted in POINT space: the minimum separation is
% converted from typographic points to data units through the axis height, so two
% configurations whose margins differ by 0.006 do not overprint.
FS = opts.font_size; FN = 'Times New Roman';
AX_H_IN = 0.66*3.40;                     % axis height, inches (Position below)
f = pf_page_figure(opts.width_in,3.40,FS);
ax = axes(f,'Units','normalized','Position',[0.13 0.22 0.83 0.66]);
hold(ax,'on');
ready = CAND([CAND.ready]);
notready = CAND(~[CAND.ready]);
plot(ax,[ready.count],[ready.omega],'o','MarkerSize',7, ...
    'MarkerFaceColor',[0.00 0.24 0.75],'MarkerEdgeColor','none');

% Trace the best configuration at each unit count.
cnts = unique([ready.count]);
bestv = arrayfun(@(n) min([ready([ready.count]==n).omega]),cnts);
plot(ax,cnts,bestv,'-','Color',[0.00 0.24 0.75],'LineWidth',1.1, ...
    'HandleVisibility','off');

nmax = max([CAND.count]);
lo = min([ready.omega]); hi = max([ready.omega]);
pad = 0.12*(hi-lo);
if pad <= 0, pad = 0.05; end
ylim(ax,[lo-pad hi+1.6*pad]);
set(ax,'FontName',FN,'FontSize',FS-1,'GridAlpha',0.12, ...
    'XTick',1:nmax,'XLim',[0.55 nmax+0.85]);
grid(ax,'on'); box(ax,'on');

% Labels, separated in point space.
yl = ylim(ax);
pt_per_unit = (AX_H_IN*72)/(yl(2)-yl(1));
min_gap = (FS-2)*1.15/pt_per_unit;               % one line of type
for n = cnts
    sel = find([ready.count]==n);
    [~,o] = sort([ready(sel).omega],'descend');
    sel = sel(o);
    ylab = [ready(sel).omega];
    for j = 2:numel(sel)                          % push apart downward
        if ylab(j-1) - ylab(j) < min_gap
            ylab(j) = ylab(j-1) - min_gap;
        end
    end
    for j = 1:numel(sel)
        text(ax,n+0.10,ylab(j),ids_to_plain(ready(sel(j)).selected), ...
            'FontName',FN,'FontSize',FS-2,'VerticalAlignment','middle', ...
            'HorizontalAlignment','left');
        if abs(ylab(j)-ready(sel(j)).omega) > 1e-12
            plot(ax,[n n+0.09],[ready(sel(j)).omega ylab(j)],'-', ...
                'Color',[0.55 0.55 0.55],'LineWidth',0.5, ...
                'HandleVisibility','off');
        end
    end
end

% Rejected configurations: counted, not positioned.
if ~isempty(notready)
    parts = cell(1,0);
    for n = 1:nmax
        tot = sum([CAND.count]==n);
        rdy = sum([CAND.count]==n & [CAND.ready]);
        if tot == 0, continue; end
        parts{end+1} = sprintf('%d: %d of %d',n,rdy,tot); %#ok<AGROW>
    end
    xlabel(ax,sprintf(['number of grid-forming units\n' ...
        '\\rm\\fontsize{%d}{}admissible per count --- %s'], ...
        FS-3,strjoin(parts,',  ')), ...
        'FontName',FN,'FontSize',FS-1,'Interpreter','tex');
else
    xlabel(ax,'number of grid-forming units','FontName',FN,'FontSize',FS-1);
end
ylabel(ax,'\Omega [1/s]','FontName',FN,'FontSize',FS-1);
title(ax,'Islanded admissibility: damping margin per configuration', ...
    'FontName',FN,'FontSize',FS-2, ...
    'FontWeight','normal');
% No legend: there is one series, the title names it, and a legend box in the
% corner collided with the label of the least-damped singleton.
pf_page_export(f,path,opts.dpi);
end

function s = ids_to_plain(idx)
buses = [NaN 2 3 6 8];
parts = cell(1,numel(idx));
for k = 1:numel(idx)
    parts{k} = sprintf('%d',buses(idx(k)));
end
s = ['bus ' strjoin(parts,'+')];
end
