function evidence = et_fcs_table_predict(snapshot, candidate, screen, prediction_horizon)
%ET_FCS_TABLE_PREDICT  Project-owned lookup of immutable nonlinear trial data.
%   The main predictor validates time coverage and every dynamic hard gate.
%   SCREEN and PREDICTION_HORIZON are accepted for provider-interface parity;
%   the returned evidence remains the exact stored trajectory, never rescaled.

arguments
    snapshot struct
    candidate struct
    screen struct %#ok<INUSA>
    prediction_horizon (1,1) double {mustBePositive} %#ok<INUSA>
end
if ~isfield(snapshot,'trial_table') || isempty(snapshot.trial_table) || ...
        ~isfield(snapshot.trial_table,'candidate_id')
    error('stability:et_fcs_table_predict:missingTable', ...
        'The accepted snapshot has no authenticated trial table.');
end
match = find(strcmp({snapshot.trial_table.candidate_id},candidate.candidate_id));
if ~isscalar(match)
    error('stability:et_fcs_table_predict:identityMismatch', ...
        'Candidate %s must have exactly one trial-table row.',candidate.candidate_id);
end
entry = snapshot.trial_table(match);
if ~isfield(entry,'prediction') || ~isstruct(entry.prediction) || ...
        ~isscalar(entry.prediction)
    error('stability:et_fcs_table_predict:missingEvidence', ...
        'Candidate %s has no scalar prediction evidence.',candidate.candidate_id);
end
evidence = entry.prediction;
end
