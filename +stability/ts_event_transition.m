function [y_right, Y_right, event_context_right, event_diag, hybrid_state_new] = ...
    ts_event_transition(t_next, event_id, events, x, y, strat, kopt, has_provider, event_tol, hybrid_state)
%TS_EVENT_TRANSITION  Shared event-transition helper (B3).
%   Called at the END of a step that arrives at t_next (a declared event
%   time) to switch ONCE to the right-topology/context and re-solve the
%   algebraic state y under the right topology.
%
%   This is the SINGLE owner of event-transition logic, used by:
%     - legacy adaptive (ts_adaptive_driver)
%     - bundle fixed (run_model_bundle in ts_simulate)
%     - bundle adaptive (via ts_adaptive_driver)
%   The classical fixed-step loop (ts_simulate classical branch) uses its
%   own solve_network path and is bit-identical (unchanged by B3).
%
%   CONTRACT (frozen, B3):
%     - event_id is the NAMED transition that fired ('fault_on' | 'fault_off'),
%       passed in EXPLICITLY by the caller — NOT discovered by perturbing
%       t_next. The right topology is selected by event_id DIRECTLY from
%       the named set (events.Ypre / events.Yfault / events.Ypost), NEVER
%       via ts_topology_at(t_next +/- delta).
%     - event_tol is a FROZEN absolute tolerance (1e-10), passed explicitly
%       so coincidence does NOT depend on a local step-size dt. It is used
%       IDENTICALLY in fixed and adaptive paths. Coincident events are
%       PREVALIDATED before the stepping loop (see prevalidate_events), so
%       this helper assumes a single transition at t_next.
%     - Arrival step already used LEFT topology/context for RHS/provider
%       eval. At the event: switch ONCE to right topology, re-solve y
%       under right topology, publish RIGHT-limit y (delta continuous,
%       no reset map). Next step starts right-consistent.
%
%   Source: project B3 design (docs/project/plans/ibr_interface_foundation.md).
%   Event convention: Sauer-Pai §6.7 (slack V specified, KCL replaced);
%   left/right topology switch at event boundary (no trapezoidal step
%   crosses a topology change).

arguments
    t_next (1,1) double
    event_id (1,1) string
    events struct
    x (:,1) double
    y (:,1) double
    strat struct
    kopt struct
    has_provider (1,1) logical
    event_tol (1,1) double
    hybrid_state struct = struct()
end

% Phase 2: 10-arg overload (hybrid_state present) delegates to the generic
% ts_apply_transition. The legacy 9-arg path (hybrid_state absent/empty)
% runs the existing B3 code UNCHANGED (bit-identical).
% A struct() default with no fields is treated as "absent" (legacy path).
has_hybrid = ~isempty(fieldnames(hybrid_state));
has_transitions = isfield(events, 'transitions') && ~isempty(events.transitions);
if has_hybrid || has_transitions
    transition = find_transition_by_id(events, event_id);
    [y_right, Y_right, hybrid_state_new, event_context_right, event_diag] = ...
        stability.ts_apply_transition(t_next, transition, events, x, y, ...
        hybrid_state, strat, kopt, has_provider, event_tol);
    if nargout >= 5
        hybrid_state_new = hybrid_state_new; %#ok<NASGU> return as 5th output
    end
    return;
end

% Select RIGHT topology by event_id DIRECTLY from the named set.
% NO ts_topology_at(t_next +/- delta).
switch event_id
case 'fault_on'
    Y_right = events.Yfault;
case 'fault_off'
    Y_right = events.Ypost;
otherwise
    error('ts_event_transition:badEventId', ...
        'Unknown event_id "%s" (expected ''fault_on'' | ''fault_off'').', event_id);
end

event_context_right = struct('t', t_next, 'side', 'right', ...
    'topology_name', topology_name_for(event_id), 'event_id', char(event_id));

% Re-solve algebraic y under the right topology.
if strat.needs_algebraic_solve
    g_tol = kopt.algebraic_tolerance;
    if has_provider
        u_ev = stability.eval_input_provider(strat.provider, t_next, event_context_right);
        Jyy_r = strat.jac_y_u(x, y, Y_right, u_ev);
        [y_right, alg_r] = stability.ts_algebraic_solve_u(x, y, Y_right, ...
            strat.dae_g_u, strat.jac_y_u, g_tol, Jyy_r, u_ev);
    else
        Jyy_r = strat.jac_y(x, y, Y_right);
        [y_right, alg_r] = stability.ts_algebraic_solve(x, y, Y_right, ...
            strat.dae_g, @stability.ts_jac_y_fd, g_tol, Jyy_r);
    end
    if ~alg_r.converged
        error('ts_event_transition:eventAlgebraic', ...
            'Right-topology algebraic solve failed at event t=%.6g: residual=%.3e.', ...
            t_next, alg_r.final_residual);
    end
    alg_res_right = alg_r.final_residual;
else
    % Classical (linear) model: re-solved inline in dae_f next step.
    y_right = y;
    alg_res_right = 0;
end

event_diag = struct( ...
    'time', t_next, 'side', 'right', 'topology', topology_name_for(event_id), ...
    'event_id', char(event_id), 'algebraic_residual', alg_res_right);
end

% =========================================================================
function topo = topology_name_for(event_id)
% Map event_id to the named topology label for diagnostics.
switch event_id
case 'fault_on',  topo = 'fault';
case 'fault_off', topo = 'post';
otherwise,        topo = 'unknown';
end
end

% =========================================================================
function transition = find_transition_by_id(events, event_id)
% Phase 2: locate the transition with the given event_id in events.transitions.
if ~isfield(events, 'transitions') || isempty(events.transitions)
    error('ts_event_transition:missingTransitions', ...
        ['Generic path requested (hybrid_state or events.transitions present) ' ...
         'but events.transitions is empty. Provide events.transitions or use ' ...
         'the legacy 9-arg call without hybrid_state.']);
end
T = events.transitions;
for k = 1:numel(T)
    if string(T(k).event_id) == string(event_id)
        transition = T(k);
        return;
    end
end
error('ts_event_transition:unknownEventId', ...
    'event_id "%s" not found in events.transitions.', event_id);
end
