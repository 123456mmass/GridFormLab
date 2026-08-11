function report = compare_ts_equivalence(baseline, candidate, opt)
%COMPARE_TS_EQUIVALENCE  Falsify numerical equivalence of two switched-TS runs.
%   REPORT = compare_ts_equivalence(BASELINE, CANDIDATE) compares two
%   stability.run_hybrid_case result structs (or .mat paths holding one in a
%   variable named `r`, `result`, or `res`) field by field and reports the
%   largest absolute and relative deviation of every published array plus the
%   exact agreement of every discrete/decision field.
%
%   REPORT = compare_ts_equivalence(BASELINE, CANDIDATE, OPT) accepts:
%     OPT.tol          numeric tolerance for continuous arrays (default 0,
%                      i.e. bit-identical is REQUIRED)
%     OPT.verbose      print the table (default true)
%     OPT.label        text tag used in the printed header
%
%   WHY THIS EXISTS: no test in tests/ pins absolute trajectory values from
%   stability.ts_simulate_ibr_hybrid, and the two "bit-identical" runner tests
%   compare two routes that both delegate to the SAME stability.ts_step_composite,
%   so they cannot detect a change inside that step. Newton converges to
%   newton_tol=1e-8 while acceptance uses kcl_tol=1e-6, so a Jacobian change can
%   move the trajectory silently without failing any existing gate. This script
%   is therefore the primary falsification instrument for kernel performance
%   work, not the test suite.
%
%   The comparison is deliberately asymmetric about tolerance:
%     - CONTINUOUS arrays are checked against OPT.tol.
%     - DECISION fields (converged flag, event times, mode history, statuses,
%       fingerprints) are ALWAYS required to match exactly. A performance change
%       that moves an event time or a committed mode is not an equivalent run
%       regardless of how small the trajectory deviation is.
%
%   Diagnostic counters (attempts/iterations/residual-per-step) are reported but
%   never gate, because work-hint and Jacobian-policy changes are expected to
%   move them while leaving the accepted trajectory untouched.

arguments
    baseline
    candidate
    opt struct = struct()
end

tol = local_option(opt,'tol',0);
verbose = logical(local_option(opt,'verbose',true));
label = char(local_option(opt,'label',''));

A = local_load(baseline,'baseline');
B = local_load(candidate,'candidate');

% ---- field classification (frozen lists; unknown fields are reported) -----
continuous = {'t','x_traj','y_traj','u_history','bus_voltage_magnitude', ...
    'device_currents','device_current_magnitude','device_P','device_Q', ...
    'sg_omega','sg_freq'};
counters = {'residual_per_step','accepted_residual_per_step','iter_per_step'};
decisions = {'converged','device_modes_history','actual_reclose_time', ...
    'reclose_status','actual_mode_reselection_time','reselection_status', ...
    'requested_sg_on_time','handback_status','handback_start_time', ...
    'handback_duration_s','handback_complete_time','failure_id', ...
    'committed_config_fingerprint','pre_event_input_fingerprint', ...
    'selector_table_fingerprint','sg_indices'};

report = struct('label',label,'tol',tol,'pass',true, ...
    'continuous',local_empty_row(),'counters',local_empty_row(), ...
    'decisions',local_empty_decision(),'event_times',local_empty_decision(), ...
    'missing',{{}});

% ---- continuous arrays ----------------------------------------------------
for k = 1:numel(continuous)
    row = local_compare_numeric(A,B,continuous{k},tol);
    if isempty(row), report.missing{end+1} = continuous{k}; continue; end
    report.continuous(end+1) = row;
    if ~row.pass, report.pass = false; end
end

% ---- diagnostic counters (reported, never gating) ------------------------
for k = 1:numel(counters)
    row = local_compare_numeric(A,B,counters{k},inf);
    if isempty(row), report.missing{end+1} = counters{k}; continue; end
    report.counters(end+1) = row;
end

% ---- decision fields (exact match required) ------------------------------
for k = 1:numel(decisions)
    row = local_compare_exact(A,B,decisions{k});
    if isempty(row), continue; end
    report.decisions(end+1) = row;
    if ~row.equal, report.pass = false; end
end

% ---- event times from the event log --------------------------------------
ev = local_compare_events(A,B);
for k = 1:numel(ev)
    report.event_times(end+1) = ev(k);
    if ~ev(k).equal, report.pass = false; end
end

if verbose
    local_print(report);
end
end

% =========================================================================
function value = local_option(s,name,default)
value = default;
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    value = s.(name);
end
end

% =========================================================================
function r = local_load(src,role)
%LOCAL_LOAD  Accept a result struct directly or a .mat path holding one.
if isstruct(src) && isscalar(src)
    r = src;
    return;
end
if ~(ischar(src) || (isstring(src) && isscalar(src)))
    error('compare_ts_equivalence:badInput', ...
        'The %s must be a scalar result struct or a .mat path.',role);
end
p = char(src);
if ~isfile(p)
    error('compare_ts_equivalence:missingFile','%s file not found: %s',role,p);
end
d = load(p);
for name = {'r','result','res'}
    if isfield(d,name{1}) && isstruct(d.(name{1})) && isscalar(d.(name{1}))
        r = d.(name{1});
        return;
    end
end
error('compare_ts_equivalence:noResultVariable', ...
    '%s file %s holds no scalar struct named r, result, or res.',role,p);
end

% =========================================================================
function row = local_empty_row()
row = repmat(struct('name','','shape_ok',false,'bitwise',false, ...
    'max_abs',NaN,'max_rel',NaN,'pass',false,'numel',0),0,1);
end

function row = local_empty_decision()
row = repmat(struct('name','','equal',false,'detail',''),0,1);
end

% =========================================================================
function row = local_compare_numeric(A,B,name,tol)
%LOCAL_COMPARE_NUMERIC  Deviation of one published numeric array.
%   tol == 0    -> bit-identical required (isequaln, so NaN==NaN passes)
%   tol == inf  -> reported only, never gating (diagnostic counters)
row = [];
if ~isfield(A,name) || ~isfield(B,name), return; end
a = A.(name); b = B.(name);
if ~isnumeric(a) || ~isnumeric(b), return; end
shape_ok = isequal(size(a),size(b));
bitwise = isequaln(a,b);
max_abs = NaN; max_rel = NaN;
if shape_ok && ~isempty(a)
    both_nan = isnan(a) & isnan(b);
    d = abs(a(~both_nan) - b(~both_nan));
    if isempty(d)
        max_abs = 0; max_rel = 0;
    else
        ref = abs(b(~both_nan));
        max_abs = max(d);
        max_rel = max(d ./ max(1,ref));
    end
elseif shape_ok
    max_abs = 0; max_rel = 0;
end
if isinf(tol)
    pass = true;                      % diagnostic counter: reported only
elseif tol == 0
    pass = shape_ok && bitwise;
else
    pass = shape_ok && isfinite(max_abs) && max_abs <= tol;
end
row = struct('name',name,'shape_ok',shape_ok,'bitwise',bitwise, ...
    'max_abs',max_abs,'max_rel',max_rel,'pass',pass,'numel',numel(a));
end

% =========================================================================
function row = local_compare_exact(A,B,name)
%LOCAL_COMPARE_EXACT  Discrete/decision field: exact agreement or nothing.
row = [];
has_a = isfield(A,name); has_b = isfield(B,name);
if ~has_a && ~has_b, return; end
if has_a ~= has_b
    row = struct('name',name,'equal',false,'detail','field present on one side only');
    return;
end
equal = isequaln(A.(name),B.(name));
detail = '';
if ~equal
    detail = local_describe_pair(A.(name),B.(name));
end
row = struct('name',name,'equal',equal,'detail',detail);
end

% =========================================================================
function rows = local_compare_events(A,B)
%LOCAL_COMPARE_EVENTS  Event identity, landing time, and applied flag.
%   Compares only the decision-bearing fields of each event_log entry
%   (type / t / applied / failure_id / transaction_id). The bulky diagnostic
%   payload (guard, status, reclose_diag, input snapshots) is intentionally
%   NOT compared: it is presentation evidence, not a numerical contract, and
%   comparing it would drown a real event shift in noise.
rows = local_empty_decision();
if ~isfield(A,'event_log') || ~isfield(B,'event_log'), return; end
la = A.event_log; lb = B.event_log;
if numel(la) ~= numel(lb)
    rows(end+1) = struct('name','event_log:count','equal',false, ...
        'detail',sprintf('%d vs %d events',numel(la),numel(lb)));
    return;
end
rows(end+1) = struct('name','event_log:count','equal',true, ...
    'detail',sprintf('%d events',numel(la)));
keys = {'type','t','applied','failure_id','transaction_id'};
for k = 1:numel(la)
    for j = 1:numel(keys)
        key = keys{j};
        if ~isfield(la,key) || ~isfield(lb,key), continue; end
        va = la(k).(key); vb = lb(k).(key);
        equal = isequaln(va,vb);
        detail = '';
        if ~equal, detail = local_describe_pair(va,vb); end
        rows(end+1) = struct( ...
            'name',sprintf('event(%d).%s',k,key), ...
            'equal',equal,'detail',detail); %#ok<AGROW>
    end
end
end

% =========================================================================
function s = local_describe_pair(a,b)
%LOCAL_DESCRIBE_PAIR  Short human-readable description of a mismatch.
s = sprintf('%s vs %s',local_describe(a),local_describe(b));
end

function s = local_describe(v)
if ischar(v)
    s = ['"' v '"'];
elseif isstring(v) && isscalar(v)
    s = ['"' char(v) '"'];
elseif islogical(v) && isscalar(v)
    s = local_ternary(v,'true','false');
elseif isnumeric(v) && isscalar(v)
    s = sprintf('%.17g',v);
elseif isnumeric(v)
    s = sprintf('[%s numeric]',mat2str(size(v)));
elseif iscell(v)
    s = sprintf('{%s cell}',mat2str(size(v)));
else
    s = sprintf('<%s>',class(v));
end
end

function v = local_ternary(c,a,b)
if c, v = a; else, v = b; end
end

% =========================================================================
function local_print(report)
%LOCAL_PRINT  Compact report. Powers of ten are printed with %g here because
%   this is console diagnostic output, not a report table.
head = 'TS_EQUIVALENCE';
if ~isempty(report.label), head = [head ' [' report.label ']']; end
fprintf('\n%s  tol=%g\n',head,report.tol);
fprintf('%-30s %10s %12s %12s %8s\n','continuous array','bitwise', ...
    'max|d|','max rel','verdict');
for k = 1:numel(report.continuous)
    c = report.continuous(k);
    fprintf('%-30s %10s %12.4g %12.4g %8s\n',c.name, ...
        local_ternary(c.bitwise,'yes','NO'),c.max_abs,c.max_rel, ...
        local_ternary(c.pass,'pass','FAIL'));
end
if ~isempty(report.counters)
    fprintf('-- diagnostic counters (reported, not gating) --\n');
    for k = 1:numel(report.counters)
        c = report.counters(k);
        fprintf('%-30s %10s %12.4g %12.4g\n',c.name, ...
            local_ternary(c.bitwise,'same','differs'),c.max_abs,c.max_rel);
    end
end
bad = report.decisions(~[report.decisions.equal]);
fprintf('-- decision fields: %d compared, %d mismatched --\n', ...
    numel(report.decisions),numel(bad));
for k = 1:numel(bad)
    fprintf('   MISMATCH %-28s %s\n',bad(k).name,bad(k).detail);
end
badev = report.event_times(~[report.event_times.equal]);
fprintf('-- event log: %d checks, %d mismatched --\n', ...
    numel(report.event_times),numel(badev));
for k = 1:numel(badev)
    fprintf('   MISMATCH %-28s %s\n',badev(k).name,badev(k).detail);
end
if ~isempty(report.missing)
    fprintf('-- absent on one or both sides: %s\n',strjoin(report.missing,', '));
end
fprintf('TS_EQUIVALENCE_VERDICT: %s\n\n', ...
    local_ternary(report.pass,'PASS','FAIL'));
end
