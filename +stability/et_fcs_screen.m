function candidates = et_fcs_screen(snapshot, candidates, provider, opt)
%ET_FCS_SCREEN  Apply logical and right-limit full-network hard gates.
%   PROVIDER(snapshot,candidate) must return project-owned algebraic evidence:
%     converged, kcl_norm, voltage_abs, current_abs, reserve_known,
%     delta_p_available, delta_q_available, mapped_x, mapped_y.
%   Candidates that fail any gate remain in the evidence table but cannot be
%   predicted or ranked. No candidate state is committed.

arguments
    snapshot struct
    candidates struct
    provider
    opt struct = struct()
end

allow_diagnostic = false;
if isfield(opt,'allow_diagnostic_callback')
    allow_diagnostic = opt.allow_diagnostic_callback;
end
if ~islogical(allow_diagnostic) || ~isscalar(allow_diagnostic)
    error('stability:et_fcs_screen:badCallbackClassification', ...
        'allow_diagnostic_callback must be a logical scalar.');
end
validate_provider(provider, allow_diagnostic, 'screen');
limits = validate_limits(snapshot.limits);
for i = 1:numel(candidates)
    c = candidates(i);
    ev = blank_evidence();
    [ok, reason] = logical_gate(snapshot, c);
    if ~ok
        ev.failure_id = reason;
        candidates(i).screen = ev;
        candidates(i).screen_pass = false;
        continue;
    end
    before = snapshot.fingerprint;
    try
        raw = feval(provider, snapshot, c);
    catch me
        ev.failure_id = 'stability:et_fcs_screen:providerException';
        ev.details = sprintf('%s: %s', me.identifier, me.message);
        candidates(i).screen = ev;
        candidates(i).screen_pass = false;
        continue;
    end
    if ~strcmp(snapshot.fingerprint, before)
        error('stability:et_fcs_screen:snapshotMutation', ...
            'The accepted snapshot fingerprint changed during a candidate trial.');
    end
    [ev, ok] = validate_evidence(raw, limits);
    candidates(i).screen = ev;
    candidates(i).screen_pass = ok;
end
end

function [ok, id] = logical_gate(s, c)
ok = false; id = '';
n = numel(s.resource_ids);
if ~isfield(c,'modes') || ~iscell(c.modes) || numel(c.modes) ~= n || ...
        ~isfield(c,'owner_index') || ~isscalar(c.owner_index) || ...
        c.owner_index < 1 || c.owner_index > n
    id = 'stability:et_fcs_screen:malformedCandidate'; return;
end
owner = c.owner_index;
if ~s.device_online(owner)
    id = 'stability:et_fcs_screen:ownerOffline'; return;
end
if ~s.reference_capable(owner)
    id = 'stability:et_fcs_screen:ownerNotCapable'; return;
end
if s.resource_island_ids(owner) ~= s.energized_island_ids(1)
    id = 'stability:et_fcs_screen:ownerWrongIsland'; return;
end
if strcmp(s.resource_types{owner}, 'ibr') && ~strcmpi(c.modes{owner}, 'gfm')
    id = 'stability:et_fcs_screen:ibrOwnerNotGfm'; return;
end
eligible = find(s.eligible_mask);
for k = eligible
    target = lower(strtrim(char(c.modes{k})));
    current = lower(strtrim(char(s.device_modes{k})));
    if ~any(strcmp(target, {'gfl','gfm'}))
        id = 'stability:et_fcs_screen:unsupportedMode'; return;
    end
    if strcmp(target, current), continue; end
    if ~s.device_online(k)
        id = 'stability:et_fcs_screen:offlineTransition'; return;
    end
    if s.hold_timers(k) > 0
        id = 'stability:et_fcs_screen:holdBlocksTransition'; return;
    end
    if isfinite(s.lockout_until(k)) && s.lockout_until(k) > s.t
        id = 'stability:et_fcs_screen:lockoutBlocksTransition'; return;
    end
end
ok = true;
end

function limits = validate_limits(limits)
required = {'kcl_tol','v_min','v_max','i_max','f_min','f_max','rocof_max'};
if ~isstruct(limits) || ~isscalar(limits)
    error('stability:et_fcs_screen:missingLimits', 'limits must be a scalar struct.');
end
for k = 1:numel(required)
    f = required{k};
    if ~isfield(limits,f) || isempty(limits.(f)) || ~isnumeric(limits.(f)) || ...
            any(~isfinite(limits.(f)(:)))
        error('stability:et_fcs_screen:missingLimits', ...
            'Case-defined finite limit "%s" is required.', f);
    end
end
if ~isscalar(limits.kcl_tol) || limits.kcl_tol <= 0 || ...
        ~isscalar(limits.v_min) || ~isscalar(limits.v_max) || ...
        limits.v_min <= 0 || limits.v_min >= limits.v_max || ...
        any(limits.i_max(:) <= 0) || ~isscalar(limits.f_min) || ...
        ~isscalar(limits.f_max) || limits.f_min >= limits.f_max || ...
        ~isscalar(limits.rocof_max) || limits.rocof_max <= 0
    error('stability:et_fcs_screen:badLimits', 'Case-defined limits are inconsistent.');
end
end

function [ev, ok] = validate_evidence(raw, lim)
ev = blank_evidence(); ok = false;
required = {'converged','kcl_norm','voltage_abs','current_abs','reserve_known', ...
    'delta_p_available','delta_q_available','mapped_x','mapped_y'};
if ~isstruct(raw) || ~isscalar(raw)
    ev.failure_id = 'stability:et_fcs_screen:malformedEvidence'; return;
end
for k = 1:numel(required)
    if ~isfield(raw, required{k}) || isempty(raw.(required{k}))
        ev.failure_id = 'stability:et_fcs_screen:incompleteEvidence'; return;
    end
end
ev = raw;
ev.passed = false;
ev.failure_id = '';
ev.details = '';
if ~islogical(raw.converged) || ~isscalar(raw.converged) || ~raw.converged
    ev.failure_id = 'stability:et_fcs_screen:notConverged'; return;
end
numeric_fields = {'kcl_norm','voltage_abs','current_abs','delta_p_available', ...
    'delta_q_available','mapped_x','mapped_y'};
for k = 1:numel(numeric_fields)
    v = raw.(numeric_fields{k});
    if ~isnumeric(v) || any(~isfinite(v(:)))
        ev.failure_id = 'stability:et_fcs_screen:nonFiniteEvidence'; return;
    end
end
if ~isscalar(raw.kcl_norm) || raw.kcl_norm < 0 || raw.kcl_norm > lim.kcl_tol
    ev.failure_id = 'stability:et_fcs_screen:kclViolation'; return;
end
if any(raw.voltage_abs(:) < lim.v_min) || any(raw.voltage_abs(:) > lim.v_max)
    ev.failure_id = 'stability:et_fcs_screen:voltageViolation'; return;
end
imax = expand_limit(lim.i_max, numel(raw.current_abs), 'i_max');
if any(raw.current_abs(:) < 0) || any(raw.current_abs(:) > imax(:))
    ev.failure_id = 'stability:et_fcs_screen:currentViolation'; return;
end
if ~islogical(raw.reserve_known) || ~isscalar(raw.reserve_known) || ~raw.reserve_known
    ev.failure_id = 'stability:et_fcs_screen:reserveUnknown'; return;
end
if ~isscalar(raw.delta_p_available) || ~isscalar(raw.delta_q_available) || ...
        raw.delta_p_available < 0 || raw.delta_q_available < 0
    ev.failure_id = 'stability:et_fcs_screen:reserveViolation'; return;
end
ev.passed = true; ok = true;
end

function v = expand_limit(v, n, name)
if isscalar(v), v = repmat(v, n, 1); end
if numel(v) ~= n
    error('stability:et_fcs_screen:limitAlignment', ...
        '%s must be scalar or align with the evidence vector.', name);
end
v = reshape(v, [], 1);
end

function ev = blank_evidence()
ev = struct('passed',false,'failure_id','','details','','converged',false, ...
    'kcl_norm',Inf,'voltage_abs',[],'current_abs',[],'reserve_known',false, ...
    'delta_p_available',NaN,'delta_q_available',NaN,'mapped_x',[],'mapped_y',[]);
end

function validate_provider(provider, allow_diagnostic, stage)
if ~(isa(provider,'function_handle') || ischar(provider) || ...
        (isstring(provider) && isscalar(provider)))
    error('stability:et_fcs_screen:badProvider', '%s provider must be callable.', stage);
end
if ischar(provider) || isstring(provider)
    name = char(provider);
else
    name = func2str(provider);
end
if ~startsWith(name, 'stability.') && ~allow_diagnostic
    error('stability:et_fcs_screen:nonProjectProvider', ...
        'Production %s provider must be an in-repo stability.* function.', stage);
end
end
