function [y_right, Y_right, hybrid_state_new, event_context_right, event_diag] = ...
    ts_apply_transition(t_next, transition, events, x, y, hybrid_state, strat, kopt, has_provider, event_tol)
%TS_APPLY_TRANSITION  Apply ONE transition (scheduled or guard) (Phase 2).
%   [y_right, Y_right, hybrid_state_new, event_context_right, event_diag] = ...
%       ts_apply_transition(t_next, transition, events, x, y, hybrid_state, ...
%       strat, kopt, has_provider, event_tol) applies a SINGLE named
%       transition to switch ONCE to the right-topology/context, re-solve the
%       algebraic state y under the right topology, and update the hybrid_state.
%
%   Per user corrections 1-3:
%     - topology selected by transition.topology_id DIRECTLY from
%       events.topologies (NO t+eps discovery).
%     - transition.atomic_updates applied as ONE transaction (Y_update, etc.).
%     - transition.hybrid_commit applied to hybrid_state -> hybrid_state_new.
%     - algebraic y re-solved under Y_right (same logic as ts_event_transition
%       B3, replicated exactly so legacy-adapter path is bit-identical).
%     - event_context_right carries an IMMUTABLE hybrid_state_new snapshot.
%     - x is CONTINUOUS across the event (no reset map unless a sourced one
%       exists; sourced reset maps are deferred to Phase 6+ when GFL<->VSG
%       transfer maps are sourced).
%
%   Source: project Phase 2 design (user corrections 1, 2). PROJECT_DERIVED.
%   Algebraic re-solve: in-house ts_algebraic_solve / ts_algebraic_solve_u
%   (no external solver). Event convention: Sauer-Pai §6.7 via Track A B3.

arguments
    t_next (1,1) double
    transition struct
    events struct
    x (:,1) double
    y (:,1) double
    hybrid_state struct
    strat struct
    kopt struct
    has_provider (1,1) logical
    event_tol (1,1) double
end

topo_id = string(transition.topology_id);
topo_fields = fieldnames(events.topologies);
if isempty(topo_id) || ~any(strcmp(topo_fields, topo_id))
    error('ts_apply_transition:badTopologyId', ...
        'Transition "%s" references topology_id "%s" not in events.topologies.', ...
        string(transition.event_id), topo_id);
end
Y_right = events.topologies.(topo_id);

% Apply atomic_updates Y_update if present (overrides topology selection for
% the network Y used in the re-solve). For legacy adapter, atomic_updates has
% Y_update = Yfault/Ypost which EQUALS the topology entry, so no change.
if isfield(transition, 'atomic_updates') && isfield(transition.atomic_updates, 'Y_update') ...
        && ~isempty(transition.atomic_updates.Y_update)
    Y_right = transition.atomic_updates.Y_update;
end

% Update hybrid_state via hybrid_commit (device_modes, active_configuration_id, etc.).
hybrid_state_new = hybrid_state;
if isfield(transition, 'hybrid_commit') && ~isempty(transition.hybrid_commit)
    hybrid_state_new = apply_hybrid_commit(hybrid_state_new, transition.hybrid_commit);
end

% Re-solve algebraic y under the right topology. SAME logic as
% ts_event_transition B3 (lines 64-86) — identical argument order so the
% legacy-adapter path is bit-identical.
if strat.needs_algebraic_solve
    g_tol = kopt.algebraic_tolerance;
    ec_for_solve = struct('t', t_next, 'side', 'right', ...
        'topology_name', char(topo_id), 'event_id', char(transition.event_id), ...
        'hybrid_state', stability.ts_hybrid_state_snapshot(hybrid_state_new));
    if has_provider
        u_ev = stability.eval_input_provider(strat.provider, t_next, ec_for_solve);
        Jyy_r = strat.jac_y_u(x, y, Y_right, u_ev);
        [y_right, alg_r] = stability.ts_algebraic_solve_u(x, y, Y_right, ...
            strat.dae_g_u, strat.jac_y_u, g_tol, Jyy_r, u_ev);
    else
        Jyy_r = strat.jac_y(x, y, Y_right);
        [y_right, alg_r] = stability.ts_algebraic_solve(x, y, Y_right, ...
            strat.dae_g, @stability.ts_jac_y_fd, g_tol, Jyy_r);
    end
    if ~alg_r.converged
        error('ts_apply_transition:eventAlgebraic', ...
            ['Right-topology algebraic solve failed at event t=%.6g ' ...
             '("%s"): residual=%.3e.'], ...
            t_next, string(transition.event_id), alg_r.final_residual);
    end
    alg_res_right = alg_r.final_residual;
else
    % Classical (linear) model: re-solved inline in dae_f next step.
    y_right = y;
    alg_res_right = 0;
end

% Build the immutable-snapshot event_context for downstream RHS/reconstruct.
event_context_right = struct('t', t_next, 'side', 'right', ...
    'topology_name', char(topo_id), 'event_id', char(transition.event_id), ...
    'hybrid_state', stability.ts_hybrid_state_snapshot(hybrid_state_new));

event_diag = struct( ...
    'time', t_next, 'side', 'right', 'topology', char(topo_id), ...
    'event_id', char(transition.event_id), 'algebraic_residual', alg_res_right);
end

% =========================================================================
function hs = apply_hybrid_commit(hs, commit)
% Apply hybrid_commit field updates to hybrid_state. Only metadata fields
% are updated (device_modes, active_configuration_id, etc.). No function
% handles (validated at commit construction; snapshot also guards).
fns = fieldnames(commit);
for i = 1:numel(fns)
    fn = fns{i};
    val = commit.(fn);
    if isstruct(val) && isstruct(hs.(fn))
        % Merge sub-struct (e.g., device_modes) field-by-field.
        sub_fns = fieldnames(val);
        for j = 1:numel(sub_fns)
            hs.(fn).(sub_fns{j}) = val.(sub_fns{j});
        end
    else
        hs.(fn) = val;
    end
end
end
