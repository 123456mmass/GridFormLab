function M = ieee14_switch_event_marks(r,opts)
%IEEE14_SWITCH_EVENT_MARKS  Event markers for the IEEE 14-bus chronology figures.
%
%   M = ieee14_switch_event_marks(r)
%   M = ieee14_switch_event_marks(r, t_end=250)
%
% Builds ONE marker table that every panel of every figure consumes, so marker
% identity across panels is structural rather than a convention someone has to
% remember. Nothing is drawn here and no axis limit is touched: this is a pure
% function over the result struct, callable from a test without a display.
%
% Two marker families, because they answer different questions:
%
%   disturbance  The scheduled exogenous events, read from r.sched (plus the
%                achieved reclose instant from r.actual_reclose_time). Read from
%                r.sched rather than r.event_log on purpose: r.sched holds the
%                COMMANDED times and stays fully populated even on an arm that
%                failed closed at the first event, so every arm of a comparison
%                gets the same markers.
%   supervisor   The instants the severity supervisor actually committed or was
%                refused a mode change: gfm_support_augment, gfm_support_release
%                and sg_reselection entries in r.event_log. These are NOT the
%                chronology instants -- on the delivered 250 s run not one of
%                them coincides with a scheduled disturbance -- so a figure that
%                marks only the chronology cannot show when switching happened.
%
% A third single-member family, validity, marks where a truncated arm stopped.
%
% Near-coincident marks are merged into one labelled group (the 85.00/85.15 s
% fault pair is 0.06 % of a 250 s axis), and label rows are staggered by GROUP
% index, not by mark index, so adding or removing one event cannot flip a parity
% and create a new collision.
%
% Classification: presentation only. Times are read from the result; none is
% written here. Any hard-coded instant would be a defect, and
% tests/test_ieee14_switch_event_marks.m falsifies that by moving the fixture's
% times and requiring the marks to move with them.

arguments
    r struct
    opts.t_end (1,1) double = NaN
    opts.merge_tol_frac (1,1) double = 0.01
    opts.stagger_rows (1,1) double = 3
    opts.merge_span (1,1) double = NaN
end

COL_DIST = [0.45 0.45 0.45];
COL_SUP  = [0.30 0.30 0.30];
COL_SUP_REJ = [0.62 0.62 0.62];
COL_EXIT = [0.75 0.10 0.10];

sched = struct();
if isfield(r,'sched') && isstruct(r.sched), sched = r.sched; end

t_end = opts.t_end;
if ~isfinite(t_end)
    t_end = num_or(sched,'t_end',NaN);
end
t_last = NaN;
if isfield(r,'t') && ~isempty(r.t), t_last = r.t(end); end

marks = empty_marks();

% --- family A: scheduled disturbances, from r.sched ------------------------
marks = add(marks,num_or(sched,'sg_trip',NaN),'SG trip', ...
    'disturbance',':',COL_DIST,'r.sched.sg_trip');
marks = add(marks,num_or(sched,'load_step',NaN),load_label(sched), ...
    'disturbance',':',COL_DIST,'r.sched.load_step');
marks = add(marks,num_or(sched,'fault_on',NaN),'fault', ...
    'disturbance',':',COL_DIST,'r.sched.fault_on');
marks = add(marks,num_or(sched,'fault_clear',NaN),'clear', ...
    'disturbance',':',COL_DIST,'r.sched.fault_clear');
marks = add(marks,num_or(sched,'line_trip',NaN),line_label(sched), ...
    'disturbance',':',COL_DIST,'r.sched.line_trip');
marks = add(marks,num_or(sched,'restore_time',NaN),'restore', ...
    'disturbance',':',COL_DIST,'r.sched.restore_time');
marks = add(marks,num_or(r,'actual_reclose_time',NaN),'SG close', ...
    'disturbance',':',COL_DIST,'r.actual_reclose_time');

% --- family B: supervisor commitments, from r.event_log --------------------
sup = supervisor_marks(r,COL_SUP,COL_SUP_REJ);
for k = 1:numel(sup), marks(end+1) = sup(k); end %#ok<AGROW>

% --- family C: validity exit for a truncated arm --------------------------
if isfinite(t_end) && isfinite(t_last) && t_last < t_end - 1e-9
    fid = '';
    if isfield(r,'failure_id') && ~isempty(r.failure_id)
        fid = char(string(r.failure_id));
    end
    lbl = 'validity exit';
    if ~isempty(fid)
        parts = strsplit(fid,':');
        lbl = sprintf('refused (%s)',parts{end});
    end
    marks = add(marks,t_last,lbl,'validity','-',COL_EXIT,'r.t(end)');
end

M = finalize(marks,sched,t_end,t_last,opts);
end

% ==========================================================================
function M = finalize(marks,sched,t_end,t_last,opts)
%FINALIZE  Sort, drop coincident supervisor duplicates, group, stagger.
if isempty(marks)
    M = struct('marks',marks,'regions',empty_regions(), ...
        't_range',[0 1],'tau',0,'merge_span',1,'n_groups',0, ...
        'provenance',provenance(sched));
    return;
end
[~,ord] = sort([marks.t]);
marks = marks(ord);

t0 = 0;
t1 = max([t_end,t_last,max([marks.t])]);
if ~isfinite(t1) || t1 <= t0, t1 = t0 + 1; end
% Merge tolerance. By default it is a fraction of the FULL horizon, which is the
% right reference for a page that shows the whole horizon. A zoom page must pass
% its own visible span through merge_span, because a tolerance sized for 250 s
% would merge marks a reader can plainly separate on a 40 s axis. Omitting
% merge_span reproduces the previous grouping exactly, so pages already delivered
% are unaffected.
merge_span = opts.merge_span;
if ~isfinite(merge_span) || merge_span <= 0
    merge_span = t1 - t0;
end
tau = opts.merge_tol_frac*merge_span;

% A supervisor commitment at the same instant as a scheduled disturbance is
% recorded ON the disturbance mark instead of drawing a second line on top of
% it. Nothing is discarded: the flag keeps the fact visible.
keep = true(1,numel(marks));
for k = 1:numel(marks)
    if ~strcmp(marks(k).family,'supervisor'), continue; end
    j = find(strcmp({marks.family},'disturbance') & ...
        abs([marks.t]-marks(k).t) <= 1e-9,1);
    if ~isempty(j)
        marks(j).has_supervisor_commit = true;
        keep(k) = false;
    end
end
marks = marks(keep);

% Group near-coincident marks so each group emits exactly one label.
g = 1; marks(1).group = 1;
for k = 2:numel(marks)
    if marks(k).t - marks(k-1).t > tau, g = g + 1; end
    marks(k).group = g;
end
n_groups = g;

% One label per group, formed from its members; stagger by GROUP index.
rows = max(1,round(opts.stagger_rows));
for gg = 1:n_groups
    idx = find([marks.group]==gg);
    lbl = strjoin(unique({marks(idx).label},'stable'),' / ');
    row = mod(gg-1,rows)+1;
    for k = idx
        marks(k).group_label = lbl;
        marks(k).row = row;
        marks(k).is_group_label = false;
    end
    marks(idx(1)).is_group_label = true;
end

M = struct();
M.marks = marks;
M.regions = fault_region(sched);
M.t_range = [t0 t1];
M.tau = tau;
M.merge_span = merge_span;
M.n_groups = n_groups;
M.provenance = provenance(sched);
end

% ==========================================================================
function R = fault_region(sched)
%FAULT_REGION  The fault is a DURATION, not two instants. Shading it is both
%   prettier and more truthful than two lines 0.15 s apart on a 250 s axis.
R = empty_regions();
a = num_or(sched,'fault_on',NaN);
b = num_or(sched,'fault_clear',NaN);
if isfinite(a) && isfinite(b) && b > a
    R(1) = struct('t0',a,'t1',b,'label','fault', ...
        'source','r.sched.fault_on..fault_clear');
end
end

% ==========================================================================
function sup = supervisor_marks(r,col_ok,col_rej)
sup = empty_marks();
if ~isfield(r,'event_log') || isempty(r.event_log), return; end
wanted = {'gfm_support_augment','gfm_support_release','sg_reselection'};
short  = {'GFM+','GFM-','reselect'};
for k = 1:numel(r.event_log)
    e = r.event_log(k);
    if ~isfield(e,'type') || isempty(e.type), continue; end
    j = find(strcmp(char(string(e.type)),wanted),1);
    if isempty(j), continue; end
    ap = false;
    if isfield(e,'applied') && ~isempty(e.applied), ap = logical(e.applied); end
    lbl = short{j};
    if ~ap, lbl = [short{j} ' refused']; end %#ok<AGROW>
    if ap, sty = '-.'; col = col_ok; else, sty = ':'; col = col_rej; end
    m = one_mark(num_or(e,'t',NaN),lbl,'supervisor',sty,col, ...
        sprintf('r.event_log(%d).%s',k,char(string(e.type))));
    m.applied = ap;
    if isfinite(m.t), sup(end+1) = m; end %#ok<AGROW>
end
end

% ==========================================================================
function s = load_label(sched)
f = num_or(sched,'load_step_factor',NaN);
if isfinite(f)
    s = sprintf('load %+.0f%%',100*f);
else
    s = 'load step';
end
end

function s = line_label(sched)
a = num_or(sched,'line_from_bus',NaN);
b = num_or(sched,'line_to_bus',NaN);
if isfinite(a) && isfinite(b)
    s = sprintf('line %d-%d trip',a,b);
else
    s = 'line trip';
end
end

function p = provenance(sched)
p = struct( ...
    'disturbance_source','r.sched + r.actual_reclose_time', ...
    'supervisor_source','r.event_log (gfm_support_augment/release, sg_reselection)', ...
    'validity_source','r.t(end) vs requested horizon', ...
    'classification','PRESENTATION_ONLY', ...
    'has_chronology',isfield(sched,'load_step'));
end

% ==========================================================================
function marks = add(marks,t,label,family,style,color,source)
if ~isfinite(t), return; end
marks(end+1) = one_mark(t,label,family,style,color,source);
end

function m = one_mark(t,label,family,style,color,source)
m = struct('t',t,'label',label,'family',family,'style',style, ...
    'color',color,'source',source,'applied',true, ...
    'has_supervisor_commit',false,'group',0,'group_label','', ...
    'row',1,'is_group_label',false);
end

function marks = empty_marks()
marks = repmat(one_mark(0,'','','',[0 0 0],''),1,0);
end

function R = empty_regions()
R = repmat(struct('t0',0,'t1',0,'label','','source',''),1,0);
end

function v = num_or(s,name,default)
v = default;
if isstruct(s) && isfield(s,name) && ~isempty(s.(name)) && ...
        isnumeric(s.(name)) && isscalar(s.(name))
    v = double(s.(name));
end
end
