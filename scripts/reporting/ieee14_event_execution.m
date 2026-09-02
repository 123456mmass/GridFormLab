function [executed,not_executed,defining,defining_ok] = ...
    ieee14_event_execution(r,arm)
%IEEE14_EVENT_EXECUTION  Which SCHEDULED events a run actually carried out.
%   [EXECUTED,NOT_EXECUTED,DEFINING,DEFINING_OK] = ieee14_event_execution(R,ARM)
%   compares the events R's schedule ARMED against the events its kernel
%   APPLIED, and reports whether the one event the scenario exists to exercise
%   was among them.
%
%   The distinction matters because nothing in an expectation token notices it.
%   A run that stops early leaves scheduled events behind and still satisfies
%   TRAJECTORY_THEN_ANY, so "the expectation was met" can be true of a scenario
%   that never reached the disturbance it was built around. This helper is what
%   lets the runner and its manifest state those two facts separately.
%
%   Inputs:
%     r    - result struct from stability.run_hybrid_case. Reads r.events (the
%            validated schedule) and r.event_log (what the kernel did).
%     arm  - scenario row. Reads arm.id and, if present, arm.defining_event.
%
%   Outputs:
%     executed     - scheduled event types that appear in the log as applied
%     not_executed - scheduled event types that do not
%     defining     - the declared defining event ('' when none is declared)
%     defining_ok  - whether that event executed; true when none is declared,
%                    because a scenario with no defining event cannot be short
%                    of it
%
%   Two decisions worth stating, because both could reasonably have gone the
%   other way and neither is recoverable by a reader of the output:
%
%   1. Only SCHEDULED events are classified. Supervisor-initiated log entries
%      (gfm_support_augment, gfm_support_release, sg_reclose, sg_reselection)
%      are outcomes rather than requests, so "not executed" is meaningless for
%      them and counting them would report phantom misses on every run.
%
%   2. An event present in the log with applied=false counts as NOT executed.
%      That is the fail-closed case. Treating a refusal as execution would
%      report a scenario as having exercised a transaction it actually declined,
%      which is the opposite of what this helper exists to prevent.
%
%   Classification: reporting/diagnostic. Pure function over a result struct; no
%   value it returns feeds PF, SSSA, TS, a selector, a controller or an
%   acceptance decision.

arguments
    r struct
    arm struct
end

executed = {};
not_executed = {};

scheduled = {};
if isfield(r,'events') && ~isempty(r.events)
    scheduled = cellstr(string({r.events.type}));
end

applied = {};
if isfield(r,'event_log') && ~isempty(r.event_log)
    L = r.event_log;
    ok = arrayfun(@(e) isfield(e,'applied') && ~isempty(e.applied) && ...
        logical(e.applied), L);
    applied = cellstr(string({L(ok).type}));
end

for k = 1:numel(scheduled)
    if any(strcmp(applied,scheduled{k}))
        executed{end+1} = scheduled{k}; %#ok<AGROW>
    else
        not_executed{end+1} = scheduled{k}; %#ok<AGROW>
    end
end

defining = '';
if isfield(arm,'defining_event'), defining = char(string(arm.defining_event)); end
if isempty(defining)
    defining_ok = true;
    return;
end

% A defining event the schedule never armed is a contradiction between the
% scenario row and its own event overrides, and it would otherwise surface as a
% permanent, unexplained "NOT EXECUTED". Fail closed and name both sides.
if ~any(strcmp(scheduled,defining))
    id = '<unnamed>';
    if isfield(arm,'id'), id = char(string(arm.id)); end
    error('ieee14_event_execution:definingEventNotScheduled', ...
        ['Scenario "%s" declares defining_event "%s", which its own schedule ' ...
         'does not arm (scheduled: %s). One of the two is wrong.'], ...
        id,defining,strjoin(scheduled,', '));
end

defining_ok = any(strcmp(executed,defining));
end
