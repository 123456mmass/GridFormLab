function det = ai_detect_event(snap, opts)
%AI_DETECT_EVENT  Event-triggered decision instants from a supervisor snapshot.
%
%   DET = ai.ai_detect_event(SNAP, OPTS)
%
%   Two rules, selected by OPTS.trigger_rule:
%
%   "spec"        raw demand = |RoCoF| >= rocof_threshold_Hz_s
%                              OR min(V_bus) <= vmin_threshold_pu
%   "production"  enter when S >= gamma_on, leave when S < gamma_off, with
%                 S = min(1,max(0,0.5*J_V + 0.5*J_f)) taken as the WORST IBR
%                 device. These are the engine's own bases and thresholds, so
%                 this rule reproduces the production augment condition rather
%                 than approximating it.
%
%   THIS LAYER IS A SHADOW. Reproducing the production condition here lets the
%   two be compared; it does not place the supervisor inside the engine's
%   decision path, and nothing returned by this function reaches an accepted
%   step, a gate, or a hysteresis timer of a production run.
%
%   DWELL APPLIES TO BOTH RULES. demand must hold for OPTS.dwell_on_s before it
%   commits, and must stay clear for OPTS.dwell_off_s before it re-arms. The
%   spec rule has no stated dwell of its own; the debounce is deliberate and is
%   the one place this implementation adds behaviour the specification does not
%   state. At the suite's 0.05 s sample spacing the 0.10 s default is two
%   samples. Set dwell_on_s = 0 to fire on the first sample instead.
%
%   A NaN index can never trigger. An unavailable measurement is not evidence
%   that the grid is healthy, and this function refuses to read it as either
%   one: the sample simply cannot fire, and the caller sees the NaN in
%   SNAP.rocof_source or SNAP.escr_source.
%
%   DET fields:
%     rule, raw_demand, enter_cond, exit_cond, criteria, state, demand,
%     trigger, trigger_indices, trigger_times, trigger_reasons, first_index,
%     first_time, first_reason, dwell_on_s, dwell_off_s
%
%   TRIGGER marks RISING EDGES -- the instants a decision is due. DEMAND marks
%   the whole window the condition is held, which is what a report should shade.
%
%   See also ai.snapshot_from_state, ai.ai_fallback_selector.

arguments
    snap struct
    opts struct = ai.ai_supervisor_defaults()
end

t = snap.t;
n = snap.n;
rule = lower(string(opts.trigger_rule));

crit = struct();
raw = false(1, n);
enter_cond = false(1, n);
exit_cond = false(1, n);

switch rule
    case "spec"
        crit.rocof = abs(snap.rocof_Hz_s) >= opts.rocof_threshold_Hz_s;
        crit.vmin = snap.V_min_pu <= opts.vmin_threshold_pu;
        % isfinite() is redundant where the comparison already yields false for
        % NaN, but it is what makes "NaN cannot trigger" a stated property
        % rather than a coincidence of IEEE comparison semantics.
        crit.rocof = crit.rocof & isfinite(snap.rocof_Hz_s);
        crit.vmin = crit.vmin & isfinite(snap.V_min_pu);
        raw = crit.rocof | crit.vmin;
        enter_cond = raw;
        exit_cond = ~raw;
    case "production"
        crit.severity_on = isfinite(snap.S) & (snap.S >= opts.gamma_on);
        crit.severity_off = ~isfinite(snap.S) | (snap.S < opts.gamma_off);
        raw = crit.severity_on;
        enter_cond = crit.severity_on;
        exit_cond = crit.severity_off;
    otherwise
        error('ai:ai_detect_event:badTriggerRule', ...
            'Unsupported trigger_rule "%s".', rule);
end

% --- hysteresis + dwell state machine -------------------------------------
state = repmat("released", 1, n);
trigger = false(1, n);
% One reason PER trigger, not one for the run. Different triggers fire on
% different criteria -- in the delivered SG-trip chronology the first comes
% from voltage and a later one from RoCoF -- so a single shared label would
% misattribute every trigger after the first.
reasons = strings(1, 0);
t_enter = NaN;
t_exit = NaN;
current = "released";
for i = 1:n
    if current == "released"
        if enter_cond(i)
            if isnan(t_enter)
                t_enter = t(i);
            end
            if t(i) - t_enter >= opts.dwell_on_s
                current = "augmenting";
                trigger(i) = true;
                t_exit = NaN;
                reasons(end+1) = reason_for(crit, i, rule); %#ok<AGROW>
            end
        else
            t_enter = NaN;
        end
    else
        if exit_cond(i)
            if isnan(t_exit)
                t_exit = t(i);
            end
            if t(i) - t_exit >= opts.dwell_off_s
                current = "released";
                t_enter = NaN;
            end
        else
            t_exit = NaN;
        end
    end
    state(i) = current;
end

det = struct();
det.rule = rule;
det.raw_demand = raw;
det.enter_cond = enter_cond;
det.exit_cond = exit_cond;
det.criteria = crit;
det.state = state;
det.demand = state == "augmenting";
det.trigger = trigger;
det.trigger_indices = find(trigger);
det.trigger_times = t(trigger);
det.trigger_reasons = reasons;
if isempty(reasons)
    det.first_reason = "";
else
    det.first_reason = reasons(1);
end
det.dwell_on_s = opts.dwell_on_s;
det.dwell_off_s = opts.dwell_off_s;
if isempty(det.trigger_indices)
    det.first_index = NaN;
    det.first_time = NaN;
else
    det.first_index = det.trigger_indices(1);
    det.first_time = t(det.first_index);
end
end

% =========================================================================
function s = reason_for(crit, i, rule)
%REASON_FOR  Which criterion is responsible at sample i, as a short label.
parts = strings(1, 0);
names = fieldnames(crit);
for k = 1:numel(names)
    v = crit.(names{k});
    if numel(v) >= i && logical(v(i))
        parts(end+1) = string(names{k}); %#ok<AGROW>
    end
end
if isempty(parts)
    s = rule + ":demand";
else
    s = rule + ":" + strjoin(parts, "+");
end
end
