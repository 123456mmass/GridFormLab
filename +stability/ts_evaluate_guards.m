function [fired_guard, hybrid_state_out, guard_diag] = ...
    ts_evaluate_guards(t, x, y, hybrid_state, events, event_context, dt)
%TS_EVALUATE_GUARDS  Evaluate guard-triggered transitions from committed state (Phase 2).
%   [fired_guard, hybrid_state_out, guard_diag] = ts_evaluate_guards(t, x, y,
%       hybrid_state, events, event_context, dt) evaluates all guards against
%       the COMMITTED (t, x, y, hybrid_state) and returns the guard that
%       fires (highest priority = lowest priority number meeting
%       threshold+dwell).
%
%   Per user correction 1B:
%     - Guard evaluation is NOT an input provider (R1 providers stay
%       exogenous fn(t,event_context)).
%     - Evaluated ONLY from committed/accepted (t,x,y,hybrid_state). NEVER
%       from a trial state. Rejected adaptive trials must NOT advance guard,
%       dwell, delay, lockout, or selector state.
%     - Sourced threshold + sourced dwell (ASSUMED_DIAGNOSTIC for synthetic
%       tests; excluded from production).
%     - Deterministic priority (lower number = higher priority).
%     - Timeout/fail-closed: if a guard has been armed (threshold met) for
%       longer than guard.timeout without dwell being satisfied, FAIL CLOSED.
%
%   This function does NOT apply the transition — it returns the fired guard
%   and the updated hybrid_state (with advanced dwell_timers). The driver
%   calls ts_apply_transition to apply the transition if one fired.
%
%   Source: project Phase 2 design (user correction 1B). PROJECT_DERIVED.
%   Guard threshold/dwell VALUES must be sourced in production; synthetic
%   tests use ASSUMED_DIAGNOSTIC values (clearly labeled).

arguments
    t (1,1) double
    x (:,1) double
    y (:,1) double
    hybrid_state struct
    events struct
    event_context struct
    dt (1,1) double
end

fired_guard = struct([]);
hybrid_state_out = hybrid_state;
guard_diag = struct('guard_id', strings(0,1), 'threshold_met', false(0,1), ...
    'dwell_accumulated', zeros(0,1), 'fired', false(0,1));

if ~isfield(events, 'guards') || isempty(events.guards)
    return;
end

G = events.guards;
ng = numel(G);
if ng == 0
    return;
end

firing = false(ng, 1);
firing_priorities = inf(ng, 1);
for k = 1:ng
    g = G(k);
    gid = string(g.guard_id);

    % Evaluate the guard measurement from committed state.
    % The guard carries a measurement_fn @(t,x,y,hybrid_state) -> scalar.
    % This is NOT an input provider: it reads committed state, not exogenous
    % inputs. For Phase 2 synthetic tests, measurement_fn is a fixture.
    if isfield(g, 'measurement_fn') && ~isempty(g.measurement_fn)
        measurement = g.measurement_fn(t, x, y, hybrid_state);
    else
        % No measurement function: guard cannot evaluate; skip.
        measurement = inf;
    end

    threshold_val = g.threshold.value;
    threshold_met = measurement >= threshold_val;

    % Dwell accumulation: only advance if threshold met.
    dwell_key = matlab.lang.makeValidName(char(gid), 'ReplacementStyle', 'underscore');
    if ~isfield(hybrid_state_out.dwell_timers, dwell_key)
        hybrid_state_out.dwell_timers.(dwell_key) = 0;
    end
    current_dwell = hybrid_state_out.dwell_timers.(dwell_key);

    if threshold_met
        new_dwell = current_dwell + dt;
    else
        new_dwell = 0;  % RESET: guard disarm when threshold drops.
    end
    hybrid_state_out.dwell_timers.(dwell_key) = new_dwell;

    % Timeout check: if the guard can NEVER fire (required dwell exceeds the
    % allowed armed-timeout), FAIL CLOSED immediately when armed. Otherwise,
    % if armed for longer than timeout without dwell being satisfied, fail.
    if isfield(g, 'timeout') && isfinite(g.timeout) && threshold_met
        if g.dwell.value > g.timeout
            % Impossible case: dwell required exceeds timeout; guard can
            % never satisfy dwell before timing out. Fail closed.
            error('ts_evaluate_guards:timeoutExceeded', ...
                ['Guard "%s" requires dwell %.4gs but timeout is %.4gs ' ...
                 '(dwell > timeout). Guard can never fire; fail closed.'], ...
                gid, g.dwell.value, g.timeout);
        elseif new_dwell > g.timeout
            error('ts_evaluate_guards:timeoutExceeded', ...
                ['Guard "%s" armed (threshold met) for %.4gs exceeding ' ...
                 'timeout %.4gs without dwell %.4gs being satisfied. ' ...
                 'Fail closed.'], ...
                gid, new_dwell, g.timeout, g.dwell.value);
        end
    end

    fired = threshold_met && (new_dwell >= g.dwell.value);
    firing(k) = fired;
    if fired
        firing_priorities(k) = g.priority;
    end

    guard_diag.guard_id(end+1, 1) = gid; %#ok<AGROW>
    guard_diag.threshold_met(end+1, 1) = threshold_met; %#ok<AGROW>
    guard_diag.dwell_accumulated(end+1, 1) = new_dwell; %#ok<AGROW>
    guard_diag.fired(end+1, 1) = fired; %#ok<AGROW>
end

% Select the firing guard with the lowest priority number (highest priority).
if any(firing)
    firing_idx = find(firing);
    [min_pri, min_idx] = min(firing_priorities(firing_idx));
    selected = firing_idx(min_idx);
    % Tie check: multiple guards with the same min priority => ambiguous.
    ties = firing_idx(firing_priorities(firing_idx) == min_pri);
    if numel(ties) > 1
        error('ts_evaluate_guards:ambiguousPriority', ...
            ['Multiple guards fired with the same priority=%d at t=%.6g. ' ...
             'Deterministic priority requires unique priorities among ' ...
             'simultaneous firing guards.'], min_pri, t);
    end
    fired_guard = G(selected);
    % Reset the dwell timer of the fired guard (it has committed its
    % transition; re-arm starts fresh).
    dwell_key = matlab.lang.makeValidName(char(fired_guard.guard_id), ...
        'ReplacementStyle', 'underscore');
    hybrid_state_out.dwell_timers.(dwell_key) = 0;
end
end
