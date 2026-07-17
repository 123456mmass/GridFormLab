function [ranked, order_key, reject_reasons] = runtime_rerank_candidates(configurations, runtime_context)
%RUNTIME_RERANK_CANDIDATES  Runtime authenticated rerank over cached evidence.
%
%   [RANKED, ORDER_KEY, REJECT_REASONS] = runtime_rerank_candidates( ...
%   CONFIGURATIONS, RUNTIME_CONTEXT) recomputes runtime transition counts
%   against the committed event-left hybrid_state modes, filters out
%   runtime-incompatible candidates, then ranks the survivors by the frozen
%   numeric policy. This is RUNTIME COMMIT AUTHORITY for the automatic path
%   (distinct from build_audit_order, which is build-time audit only).
%
%   NO physical re-evaluation (hard rule: no equilibrium/SSSA in the TS loop).
%   Pure function of cached evidence + runtime predicates.
%
%   RUNTIME_CONTEXT must be COMPLETE and IDENTITY-ALIGNED by the caller
%   (validate_runtime_candidate_compatibility builds it via identity-first
%   materialization). If runtime_context is empty/incomplete this function
%   FAILS CLOSED -- it NEVER falls back to build-time audit behavior
%   (advisor finding #1: the empty-context overload was a hidden trap).
%
%   RUNTIME_CONTEXT fields (positional, length N, identity-aligned to the
%   candidate resource_ids order by the caller):
%     event_time      scalar wall-clock of the event (lockout-expiry semantics)
%     device_modes    cell(1,N) committed event-left mode strings
%     device_online   logical(1,N)
%     hold_timers     double(1,N) modal hold (T_down) remaining
%     lockout_timers  double(1,N) lockout-until absolute time
%     eligible_mask   logical(1,N) true for eligible dual-mode IBRs
%
%   Hold/lockout (advisor finding #8): a candidate is runtime-incompatible
%   ONLY if it requires a transition on an eligible IBR that is held or
%   locked-out against that transition at event_time. A held/locked device
%   ALREADY in the candidate's desired mode does NOT reject the candidate.
%
%   Classification: NUMERICAL_METHOD. No external solver.

arguments
    configurations struct
    runtime_context struct
end

n = numel(configurations);
reject_reasons = cell(1, n);
if n == 0
    ranked = configurations;
    order_key = {};
    return;
end
% Fail closed: incomplete runtime context never falls back to build-time.
[rctxt_ok, rctxt_reason] = runtime_context_complete(runtime_context, n);
if ~rctxt_ok
    for i = 1:n
        reject_reasons{i} = rctxt_reason;
    end
    ranked = configurations;
    order_key = {};
    return;
end

baseline_modes = runtime_context.device_modes;
device_online = runtime_context.device_online;
hold_timers = runtime_context.hold_timers;
lockout_timers = runtime_context.lockout_timers;
event_time = runtime_context.event_time;
eligible_mask = runtime_context.eligible_mask;

nchanges = zeros(n, 1);
incompat = false(n, 1);
keep = true(n, 1);
for i = 1:n
    c = configurations(i);
    if ~candidate_consistent(c)
        keep(i) = false;
        reject_reasons{i} = 'candidateInternalInconsistent';
        continue;
    end
    cm = c.modes;
    [nc, icm] = count_gfl_gfm_transitions(baseline_modes, cm, eligible_mask);
    nchanges(i) = nc;
    incompat(i) = any(icm);
    if incompat(i)
        keep(i) = false;
        reject_reasons{i} = 'unexpectedMode';
        continue;
    end
    [rt_ok, rt_reason] = runtime_transition_ok(c, baseline_modes, device_online, ...
        hold_timers, lockout_timers, eligible_mask, event_time);
    if ~rt_ok
        keep(i) = false;
        reject_reasons{i} = rt_reason;
        continue;
    end
end
[M, ~] = candidate_order_matrix(configurations, nchanges, incompat');
[~, order] = sortrows(M, [1 2 3 4 5]);
ranked = configurations(order);
order_key = arrayfun(@(k) sprintf('feas=%d|nc=%d|ngfm=%d|m=%g|idx=%d|keep=%d', ...
    M(order(k), 1), M(order(k), 2), M(order(k), 3), -M(order(k), 4), ...
    M(order(k), 5), keep(order(k))), 1:n, 'UniformOutput', false);
end

% ---------------------------------------------------------------------
function [ok, reason] = runtime_context_complete(rc, n)
ok = true; reason = '';
req_fields = {'device_modes', 'device_online', 'hold_timers', ...
    'lockout_timers', 'event_time', 'eligible_mask'};
for k = 1:numel(req_fields)
    f = req_fields{k};
    if ~isfield(rc, f) || isempty(rc.(f))
        ok = false;
        reason = ['missingRuntimeContext:' f];
        return;
    end
end
if numel(rc.device_modes) ~= n
    ok = false;
    reason = 'runtimeContextDeviceCountMismatch';
    return;
end
end

% ---------------------------------------------------------------------
function ok = candidate_consistent(c)
ok = true;
if ~isfield(c, 'selected_gfm_indices') || ~isfield(c, 'n_gfm_required')
    ok = false; return;
end
if ~isequal(c.n_gfm_required, numel(c.selected_gfm_indices)), ok = false; return; end
if numel(unique(c.selected_gfm_indices)) ~= numel(c.selected_gfm_indices)
    ok = false; return;
end
if ~isfield(c, 'modes'), ok = false; return; end
end

% ---------------------------------------------------------------------
function [ok, reason] = runtime_transition_ok(c, baseline_modes, device_online, ...
    hold_timers, lockout_timers, eligible_mask, event_time)
ok = true; reason = '';
if ~isfield(c, 'modes'), return; end
cm = c.modes;
nr = numel(baseline_modes);
for k = 1:nr
    if ~eligible_mask(k), continue; end
    bm = lower(strtrim(char(baseline_modes{k})));
    cand_m = lower(strtrim(char(cm{k})));
    if ~any(strcmp(bm, {'gfl', 'gfm'})) || ~any(strcmp(cand_m, {'gfl', 'gfm'}))
        continue;
    end
    if strcmp(bm, cand_m)
        continue;   % no transition required -> hold/lockout irrelevant
    end
    % A transition IS required. Check hold/lockout against event_time.
    if isfinite(hold_timers(k)) && hold_timers(k) > 0
        ok = false; reason = 'holdTimerBlocksRequiredTransition';
        return;
    end
    if isfinite(lockout_timers(k)) && lockout_timers(k) > event_time
        ok = false; reason = 'lockoutBlocksRequiredTransition';
        return;
    end
    if ~device_online(k)
        ok = false; reason = 'deviceOfflineBlocksRequiredTransition';
        return;
    end
end
end
