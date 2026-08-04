function decision = et_fcs_supervisor(state, event, providers, policy)
%ET_FCS_SUPERVISOR  Fail-closed ET-FCSPS decision pipeline (no state mutation).
%   DECISION = stability.et_fcs_supervisor(STATE,EVENT,PROVIDERS,POLICY)
%   executes snapshot -> finite enumeration -> hard screen -> isolated
%   prediction -> metrics -> deterministic ranking. A feasible result is a
%   COMMIT_REQUEST only; the existing atomic hybrid transaction remains the
%   sole production commit authority.
%
%   PROVIDERS.screen and PROVIDERS.predict must be project-owned stability.*
%   functions unless POLICY.allow_diagnostic_callback is explicitly true for
%   a non-production falsification fixture.

arguments
    state struct
    event struct
    providers struct
    policy struct
end

decision = blank_decision();
try
    snapshot = stability.et_fcs_snapshot(state,event);
    decision.snapshot_fingerprint = snapshot.fingerprint;
    if ~snapshot.event.local_request && ~snapshot.event.authenticated
        decision.status = 'HOLD';
        decision.failure_id = '';
        decision.reason = 'No authenticated system event or local AGSI++ request.';
        decision.action = 'HOLD_CURRENT';
        decision.decision_fingerprint = fingerprint_decision(decision);
        return;
    end
    require_provider(providers,'screen');
    require_provider(providers,'predict');
    require_policy(policy);

    candidates = stability.et_fcs_enumerate(snapshot);
    candidates = stability.et_fcs_screen(snapshot,candidates,providers.screen, ...
        allow_diag_opt(policy));
    candidates = stability.et_fcs_predict(snapshot,candidates,providers.predict,policy);
    candidates = stability.et_fcs_metrics(snapshot,candidates,policy);
    [candidates,ranking] = stability.et_fcs_rank(snapshot,candidates,policy);

    decision.candidates = candidates;
    decision.candidate_evidence_fingerprint = ranking.candidate_evidence_fingerprint;
    if strcmp(ranking.status,'INFEASIBLE')
        decision.status = 'INFEASIBLE';
        decision.failure_id = 'stability:et_fcs_supervisor:noFeasibleCandidate';
        decision.reason = 'Every candidate failed a declared hard gate or evidence contract.';
        decision.action = 'HOLD_CURRENT';
        decision.decision_fingerprint = fingerprint_decision(decision);
        return;
    end

    winner = candidates(ranking.winner_index);
    decision.status = 'COMMIT_REQUEST';
    decision.failure_id = '';
    decision.reason = 'Canonical minimum among hard-feasible predicted candidates.';
    decision.action = 'ATOMIC_MODE_OWNER_TRANSACTION';
    decision.commit_requested = true;
    decision.winner_candidate_id = winner.candidate_id;
    decision.winner_modes = winner.modes;
    decision.selected_gfm_indices = winner.selected_gfm_indices;
    decision.reference_owner_index = winner.owner_index;
    decision.winner_cost = winner.cost;
    decision.order_key = winner.order_key;
    decision.decision_fingerprint = fingerprint_decision(decision);
catch me
    decision.status = 'INFEASIBLE';
    decision.failure_id = canonical_failure(me);
    decision.reason = me.message;
    decision.action = 'HOLD_CURRENT';
    decision.commit_requested = false;
    decision.decision_fingerprint = fingerprint_decision(decision);
end
end

function decision = blank_decision()
decision = struct('schema','et_fcs_decision/1.0','status','UNINITIALIZED', ...
    'failure_id','','reason','','action','HOLD_CURRENT','commit_requested',false, ...
    'snapshot_fingerprint','','candidate_evidence_fingerprint','', ...
    'winner_candidate_id','','winner_modes',{{}},'selected_gfm_indices',[], ...
    'reference_owner_index',[],'winner_cost',NaN,'order_key','', ...
    'decision_fingerprint','','candidates',repmat(struct(),0,1));
end

function require_provider(p,name)
if ~isfield(p,name) || isempty(p.(name))
    error('stability:et_fcs_supervisor:missingProvider', ...
        'Mandatory project-owned provider "%s" is missing.',name);
end
end

function require_policy(p)
required = {'prediction_horizon','prediction_time_tol','allow_diagnostic_callback', ...
    'normalization','targets','weights','cost_quantization'};
for k = 1:numel(required)
    if ~isfield(p,required{k}) || isempty(p.(required{k}))
        error('stability:et_fcs_supervisor:missingPolicy', ...
            'Mandatory CASE_DEFINED policy field "%s" is missing.',required{k});
    end
end
end

function o = allow_diag_opt(p)
o = struct('allow_diagnostic_callback',p.allow_diagnostic_callback);
end

function id = canonical_failure(me)
id = me.identifier;
if isempty(id) || ~startsWith(id,'stability:et_fcs_')
    id = 'stability:et_fcs_supervisor:internalFailure';
end
end

function fp = fingerprint_decision(d)
payload = rmfield(d,{'decision_fingerprint','candidates'});
[~,input_fp] = compute_selector_table_fingerprint( ...
    struct('selector',payload),struct());
fp = ['et_fcs_decision_v1:' input_fp];
end
