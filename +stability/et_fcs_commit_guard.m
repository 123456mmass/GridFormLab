function [ok, reason] = et_fcs_commit_guard(state, event, decision)
%ET_FCS_COMMIT_GUARD  Revalidate an ET-FCSPS request before atomic commit.
%   This pure guard does not mutate hybrid state. The caller must still use the
%   existing atomic transaction and right-limit KCL solve after a PASS.

arguments
    state struct
    event struct
    decision struct
end
ok = false; reason = '';
if ~isfield(decision,'schema') || ~strcmp(decision.schema,'et_fcs_decision/1.0') || ...
        ~isfield(decision,'commit_requested') || ~decision.commit_requested || ...
        ~isfield(decision,'status') || ~strcmp(decision.status,'COMMIT_REQUEST')
    reason = 'stability:et_fcs_commit_guard:notCommitRequest'; return;
end
try
    current = stability.et_fcs_snapshot(state,event);
catch
    reason = 'stability:et_fcs_commit_guard:invalidCurrentSnapshot'; return;
end
if ~isfield(decision,'snapshot_fingerprint') || ...
        ~strcmp(current.fingerprint,decision.snapshot_fingerprint)
    reason = 'stability:et_fcs_commit_guard:staleSnapshot'; return;
end
required = {'winner_candidate_id','winner_modes','reference_owner_index', ...
    'candidate_evidence_fingerprint','decision_fingerprint'};
for k = 1:numel(required)
    if ~isfield(decision,required{k}) || isempty(decision.(required{k}))
        reason = 'stability:et_fcs_commit_guard:incompleteDecision'; return;
    end
end
if ~isfield(decision,'selected_gfm_indices')
    reason = 'stability:et_fcs_commit_guard:incompleteDecision'; return;
end
if numel(decision.winner_modes) ~= numel(current.resource_ids) || ...
        ~isscalar(decision.reference_owner_index) || ...
        decision.reference_owner_index < 1 || ...
        decision.reference_owner_index > numel(current.resource_ids)
    reason = 'stability:et_fcs_commit_guard:malformedWinner'; return;
end
if strcmp(current.resource_types{decision.reference_owner_index},'ibr') && ...
        ~strcmpi(decision.winner_modes{decision.reference_owner_index},'gfm')
    reason = 'stability:et_fcs_commit_guard:ownerNotGfm'; return;
end
ok = true;
end
