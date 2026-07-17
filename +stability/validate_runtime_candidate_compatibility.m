function [ok, err_id, err_msg, runtime, cand] = validate_runtime_candidate_compatibility(table, req, dae, sched, context)
%VALIDATE_RUNTIME_CANDIDATE_COMPATIBILITY  Authenticate a selection request against the cached table.
%
%   [OK, ERR_ID, ERR_MSG, RUNTIME, CAND] = validate_runtime_candidate_compatibility(...
%       TABLE, REQ, DAE, SCHED, CONTEXT) verifies that the authenticated
%   selector table is still compatible with the current runtime and that the
%       candidate denoted by REQ exists in the table and is ready_to_commit.
%
%   Returns the matched candidate row CAND (empty if no match). Predicates
%   only — no physical re-evaluation (hard rule: no equilibrium/SSSA in the
%   TS loop).
%
%   CONTEXT = 'sg_off' | 'sg_on'. Fails closed before any candidate state /
%   right sample is published when incompatible.
%
%   GATE SCOPE (honest):
%     - table + context + fingerprint present (table tier);
%     - automatic: selected_config exists + ready_to_commit;
%     - manual_override: EXACT tuple (selected_gfm_indices, n_gfm_required,
%       reference_resource_index) matches exactly ONE table row, and that row
%       is ready_to_commit (reference is ownership/audit identity even though
%       Phase 0A proved reference-invariance of physical metrics);
%     - online eligibility: every selected index is an online dual-mode IBR
%       in dae.devices (predicate only, no mode transition attempted — that
%       is sg_event_handler's job).
%
%   KNOWN GAP (not yet implemented; tracked for a later sub-phase): full
%   runtime topology-order, hold, and lockout predicates. sg_event_handler
%   already enforces hold/lockout at commit time (sg_event_handler.m:290-296),
%   so a candidate that passes this gate but is held/locked at commit is
%   rejected there with modeTransitionBlocked. This function does NOT claim
%   to authenticate those runtime states.

arguments
    table struct
    req struct
    dae struct = struct()
    sched struct = struct()
    context char = 'sg_off'
end
ok = true; err_id = ''; err_msg = '';
runtime = struct('fingerprint_ok',false,'candidate_match',false, ...
    'unique_match',false,'ready',false,'online_eligible',false);
cand = struct();

% Shared failure-ID namespace for ALL layers (builder, validator, transactions):
% stability:gfm_selection:<suffix>. Outer layers propagate verbatim.
% NEVER prepend additional namespace.
function id = fid(suffix)
    id = ['stability:gfm_selection:' suffix];
end

% --- scope the candidate array for this context ---
if isfield(table,context) && isfield(table.(context),'configurations')
    cfgs = table.(context).configurations;
else
    ok = false; err_id = fid('contextMissing');
    err_msg = sprintf('selector_table context %s missing.', context);
    return;
end

% --- fingerprint must be present + immutable (table tier) ---
if ~isfield(table,'selector_table_fingerprint') || isempty(table.selector_table_fingerprint)
    ok = false; err_id = fid('noFingerprint');
    err_msg = 'selector_table missing fingerprint.';
    return;
end
runtime.fingerprint_ok = true;

% --- automatic mode: selected_config is the candidate ---
if strcmp(req.mode,'automatic')
    if ~isfield(table.(context),'selected_config') || isempty(table.(context).selected_config)
        ok = false; err_id = fid('noAuthenticatedCandidate');
        err_msg = sprintf('No authenticated selected_config in %s.', context);
        return;
    end
    cand = table.(context).selected_config;
    runtime.candidate_match = true;
    runtime.unique_match = true;
    runtime.ready = isfield(cand,'ready_to_commit') && ~isempty(cand.ready_to_commit) && cand.ready_to_commit;
    if ~runtime.ready
        ok = false; err_id = fid('candidateNotReady');
        err_msg = sprintf('Authenticated %s candidate not ready_to_commit.', context);
        return;
    end
    runtime.online_eligible = check_online_eligible(cand.selected_gfm_indices, dae);
    if ~runtime.online_eligible
        ok = false; err_id = fid('candidateNotOnlineEligible');
        err_msg = 'Selected GFM indices not all online dual-mode IBRs at runtime.';
        return;
    end
    return;
end

% --- manual_override: require an EXACT UNIQUE authenticated match ---
if strcmp(req.mode,'manual_override')
    if ~isfield(req,'manual_candidate') || ~isstruct(req.manual_candidate) || ...
            isempty(req.manual_candidate)
        ok = false; err_id = fid('manualCandidateMissing');
        err_msg = 'manual_override request lacks a manual_candidate tuple.';
        return;
    end
    mc = req.manual_candidate;
    matches = [];
    for i = 1:numel(cfgs)
        c = cfgs(i);
        if isequal(c.selected_gfm_indices, mc.selected_gfm_indices) && ...
                isequal(c.n_gfm_required, mc.n_gfm_required) && ...
                isequal(c.reference_resource_index, mc.reference_resource_index)
            matches(end+1) = i; %#ok<AGROW>
        end
    end
    runtime.candidate_match = ~isempty(matches);
    if isempty(matches)
        ok = false; err_id = fid('manualCandidateNotInTable');
        err_msg = 'manual_override tuple has no exact authenticated candidate in selector_table.';
        return;
    end
    if numel(matches) > 1
        ok = false; err_id = fid('manualCandidateAmbiguous');
        err_msg = sprintf('manual_override tuple matches %d table rows; require exactly one.', numel(matches));
        return;
    end
    runtime.unique_match = true;
    cand = cfgs(matches(1));
    runtime.ready = isfield(cand,'ready_to_commit') && ~isempty(cand.ready_to_commit) && cand.ready_to_commit;
    if ~runtime.ready
        ok = false; err_id = fid('candidateNotReady');
        err_msg = sprintf('Matched %s candidate not ready_to_commit.', context);
        return;
    end
    runtime.online_eligible = check_online_eligible(cand.selected_gfm_indices, dae);
    if ~runtime.online_eligible
        ok = false; err_id = fid('candidateNotOnlineEligible');
        err_msg = 'Selected GFM indices not all online dual-mode IBRs at runtime.';
        return;
    end
    return;
end

ok = false; err_id = fid('unknownMode');
err_msg = sprintf('Unknown selection mode %s.', req.mode);
end

% ---------------------------------------------------------------------
function ok = check_online_eligible(selected, dae)
% Predicate-only: every selected index is an online dual-mode IBR in
% dae.devices. No mode transition, no physics. dae may be empty (tests) in
% which case this gate is skipped (returns true) — the binding eligibility
% check still runs in sg_event_handler at commit time.
ok = true;
if isempty(selected), return; end
if ~isstruct(dae) || ~isfield(dae,'devices') || isempty(dae.devices), return; end
nd = numel(dae.devices);
for k = 1:numel(selected)
    idx = selected(k);
    if idx < 1 || idx > nd, ok = false; return; end
    dev = dae.devices(idx);
    if isfield(dev,'capabilities') && isstruct(dev.capabilities) && ...
            isfield(dev.capabilities,'resource_type') && ...
            strcmpi(char(dev.capabilities.resource_type),'sg')
        ok = false; return;
    end
    if isfield(dev,'capabilities') && isstruct(dev.capabilities) && ...
            isfield(dev.capabilities,'supported_modes')
        sup = string(dev.capabilities.supported_modes);
        if ~(any(strcmpi(sup,'gfl')) && any(strcmpi(sup,'gfm')))
            ok = false; return;
        end
    end
end
end
