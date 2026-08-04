function evidence = et_fcs_table_screen(snapshot, candidate)
%ET_FCS_TABLE_SCREEN  Project-owned lookup of immutable right-limit evidence.
%   The attached trial table is included in the accepted snapshot fingerprint.
%   This provider performs no solve and no mutation; a separate audited
%   producer must generate the table from the same accepted full-network state.

arguments
    snapshot struct
    candidate struct
end
entry = lookup(snapshot,candidate.candidate_id);
if ~isfield(entry,'screen') || ~isstruct(entry.screen) || ~isscalar(entry.screen)
    error('stability:et_fcs_table_screen:missingEvidence', ...
        'Candidate %s has no scalar screen evidence.',candidate.candidate_id);
end
evidence = entry.screen;
end

function entry = lookup(snapshot,id)
if ~isfield(snapshot,'trial_table') || isempty(snapshot.trial_table) || ...
        ~isfield(snapshot.trial_table,'candidate_id')
    error('stability:et_fcs_table_screen:missingTable', ...
        'The accepted snapshot has no authenticated trial table.');
end
match = find(strcmp({snapshot.trial_table.candidate_id},id));
if ~isscalar(match)
    error('stability:et_fcs_table_screen:identityMismatch', ...
        'Candidate %s must have exactly one trial-table row.',id);
end
entry = snapshot.trial_table(match);
end
