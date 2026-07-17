function [ok, err_id, err_msg, runtime, cand] = validate_runtime_candidate_compatibility(table, req, dae, sched, context, Y, runtime_context)
%VALIDATE_RUNTIME_CANDIDATE_COMPATIBILITY  Authenticate a selection request against the cached table.
%
%   [OK, ERR_ID, ERR_MSG, RUNTIME, CAND] = validate_runtime_candidate_compatibility( ...
%       TABLE, REQ, DAE, SCHED, CONTEXT, Y, RUNTIME_CONTEXT) verifies that the
%   authenticated selector table still fits the current runtime and that
%   REQ's candidate is ready, online-eligible, and fingerprint-authenticated
%   against the ACTUAL event-time topology (Y). RUNTIME_CONTEXT carries the
%   identity-aligned event-left modes/online/timers for runtime reranking.
%
%   The fingerprint is recomputed from the LIVE Y (not the stored table
%   topology) and compared against the three stored hashes, so any topology
%   drift since table build fails closed BEFORE ranking (Step 8 + D2).
%
%   The automatic branch RERANKS the cached candidate universe via
%   runtime_rerank_candidates (Step 4d) and returns the runtime winner as
%   commit authority -- it NEVER trusts table.(context).selected_config
%   (build-time audit only). Manual override matches the exact tuple and
%   runs the same authentication without reranking.
%
%   CONTEXT = 'sg_off' | 'sg_on'. Fails closed before any candidate state /
%   right sample is published when incompatible.
%
%   Predicates only -- no physical re-evaluation (no equilibrium/SSSA in
%   the TS loop).
%
%   GATE SCOPE: table/context/3-layer fingerprint/schema present; identity
%   bijection; fingerprint authentication with live Y; candidate internal
%   consistency; cached admissibility; runtime compatibility; numeric rerank.
%

arguments
    table struct
    req struct
    dae struct = struct()
    sched struct = struct()
    context char = 'sg_off'
    Y = []
    runtime_context struct = struct()
end

ok = true; err_id = ''; err_msg = '';
runtime = struct('fingerprint_ok', false, 'identity_ok', false, ...
    'candidate_match', false, 'unique_match', false, ...
    'ready', false, 'online_eligible', false, ...
    'survivors', 0, 'runtime_n_mode_changes', 0, ...
    'fingerprint_layer_status', '');
cand = struct();

% Shared failure-ID namespace for ALL layers (builder, validator, transactions):
% stability:gfm_selection:<suffix>. Outer layers propagate verbatim.
% NEVER prepend additional namespace.
function id = fidi(suffix)
    id = ['stability:gfm_selection:' suffix];
end

% --- scope the candidate array for this context ---
if isfield(table, context) && isfield(table.(context), 'configurations')
    cfgs = table.(context).configurations;
else
    ok = false; err_id = fidi('contextMissing');
    err_msg = sprintf('selector_table context %s missing.', context);
    return;
end

% --- fingerprint must be present + immutable (table tier) ---
if ~isfield(table, 'selector_table_fingerprint') || ...
        isempty(table.selector_table_fingerprint) || ...
        ~isfield(table, 'selector_input_fingerprint') || ...
        isempty(table.selector_input_fingerprint) || ...
        ~isfield(table, 'candidate_evidence_fingerprint') || ...
        isempty(table.candidate_evidence_fingerprint)
    ok = false; err_id = fidi('noFingerprint');
    err_msg = 'selector_table missing 3-layer fingerprint.';
    return;
end
runtime.fingerprint_ok = true;

% -------------------------------------------------------------------------
% --- automatic mode: authenticated lookups + runtime rerank -------------
% -------------------------------------------------------------------------
if strcmp(req.mode, 'automatic')
    [ok, err_id, err_msg, runtime, cand] = automatic_branch(runtime, table, cfgs, ...
        dae, context, Y, runtime_context);
    return;
end

% -------------------------------------------------------------------------
% --- manual_override: EXACT unique authenticated match, no rerank --------
% -------------------------------------------------------------------------
if strcmp(req.mode, 'manual_override')
    [ok, err_id, err_msg, runtime, cand] = manual_branch(runtime, table, req, cfgs, ...
        dae, context, Y, runtime_context);
    return;
end

ok = false; err_id = fidi('unknownMode');
err_msg = sprintf('Unknown selection mode %s.', req.mode);
end

% -------------------------------------------------------------------------
function [ok, err_id, err_msg, runtime_out, cand] = automatic_branch(runtime, table, cfgs, dae, context, Y, runtime_context)
% 10-step authenticated derivation of the runtime commit winner.
ok = true; err_id = ''; err_msg = '';
cand = struct();
id = @fidi;
runtime_local = runtime;

% Step 1: shape + types.
if isempty(cfgs) || ~isstruct(cfgs)
    ok = false; err_id = id('noAuthenticatedCandidate');
    err_msg = sprintf('No authenticated configurations in %s.', context);
    return;
end
if ~isfield(table, 'selector_auth_inputs') || ~isstruct(table.selector_auth_inputs)
    ok = false; err_id = id('noFingerprint');
    err_msg = 'selector_auth_inputs envelope missing.';
    return;
end
if isempty(runtime_context) || ~isstruct(runtime_context) || isempty(Y)
    ok = false; err_id = id('runtimeContextMissing');
    err_msg = 'automatic context requires non-empty Y and runtime_context.';
    return;
end
if numel(runtime_context.device_modes) ~= numel(runtime_context.eligible_mask)
    ok = false; err_id = id('runtimeContextShape');
    err_msg = 'runtime_context vector length mismatch.';
    return;
end
n_res = numel(runtime_context.device_modes);

% Step 2: exact-index identity bijection (no permutation remapping).
if numel(dae.devices) ~= n_res
    ok = false; err_id = id('identityMismatch');
    err_msg = 'device/resource count mismatch.';
    return;
end
for k = 1:n_res
    cids = cfgs(1).resource_ids;
    dids = {dae.devices.device_id};
    if numel(cids) ~= n_res || numel(dids) ~= n_res
        ok = false; err_id = id('identityMismatch');
        err_msg = 'resource_ids/device_id length mismatch.';
        return;
    end
    for j = 1:n_res
        if ~strcmpi(char(cids{j}), char(dids{j}))
            ok = false; err_id = id('identityMismatch');
            err_msg = 'resource_ids must equal device_id index-for-index.';
            return;
        end
    end
end

% Step 3: authenticate ALL 3 fingerprint layers using LIVE Y (BEFORE ranking).
% input_fp is recomputed from the immutable stored inputs with topology_payload
% replaced by LIVE Y (detects topology drift). evidence_fp is recomputed from
% the stored candidate universe (verifies deterministic serialization).
inputs = table.selector_auth_inputs;
inputs.topology_payload = Y;
evidence = struct('sg_off_configurations', table.sg_off.configurations, ...
    'sg_on_configurations', table.sg_on.configurations);
[table_recomp, input_recomp, evidence_recomp] = ...
    compute_selector_table_fingerprint(inputs, evidence);
if ~strcmp(input_recomp, table.selector_input_fingerprint) || ...
        ~strcmp(evidence_recomp, table.candidate_evidence_fingerprint) || ...
        ~strcmp(table_recomp, table.selector_table_fingerprint)
    ok = false; err_id = id('staleFingerprint');
    err_msg = 'selector_table fingerprint stale (topology/inputs mutated).';
    runtime_local.fingerprint_layer_status = 'stale';
    runtime_out = runtime_local;
    return;
end

% Step 4: cached admissibility + internal consistency filter.
keep = true(1, numel(cfgs));
for i = 1:numel(cfgs)
    c = cfgs(i);
    consistent = isfield(c,'feasible') && logical(c.feasible) && ...
        isfield(c,'ready_to_commit') && logical(c.ready_to_commit) && ...
        isfield(c,'modes') && iscell(c.modes) && numel(c.modes) == n_res && ...
        isfield(c,'selected_gfm_indices') && isfield(c,'n_gfm_required');
    if ~consistent
        keep(i) = false;
    end
end
survivors = cfgs(keep);
if isempty(survivors)
    ok = false; err_id = id('noAuthenticatedCandidate');
    err_msg = 'No admissible (feasible+ready) authenticated candidate.';
    return;
end

% Steps 5-6: runtime compatibility (online drift + transitions) handled inside
% runtime_rerank_candidates via the shared primitives.
nchanges = zeros(1, numel(survivors));
incompat = false(1, numel(survivors));
for i = 1:numel(survivors)
    cm = survivors(i).modes;
    [nc, icm] = count_gfl_gfm_transitions(runtime_context.device_modes, cm, runtime_context.eligible_mask);
    nchanges(i) = nc;
    incompat(i) = any(icm);
end

% Steps 7-8: numeric rerank of the admissible universe.
[ranked, order_key, ~] = runtime_rerank_candidates(survivors, runtime_context);
if isempty(ranked)
    ok = false; err_id = id('noAuthenticatedCandidate');
    err_msg = 'No runtime-compatible authenticated candidate survives rerank.';
    return;
end

% Step 9: deterministic first survivor = runtime commit authority.
cand = ranked(1);
runtime_local.identity_ok = true;
runtime_local.survivors = numel(ranked);
runtime_local.runtime_n_mode_changes = nchanges(1);
runtime_local.fingerprint_layer_status = 'authenticated';
runtime_local.candidate_match = true;
runtime_local.unique_match = true;
runtime_local.ready = true;
runtime_local.online_eligible = true;

% Step 10: atomic revalidation is performed by sg_event_handler at commit.
% Here we expose the runtime winner + the build-time audit candidate.
cand.runtime_ranked_candidate = cand;
cand.build_audit_candidate = [];
if isfield(table.(context), 'selected_config')
    cand.build_audit_candidate = table.(context).selected_config;
end
cand.runtime_order_key = order_key;
runtime_out = runtime_local;
end

% -------------------------------------------------------------------------
function [ok, err_id, err_msg, runtime_out, cand] = manual_branch(runtime, table, req, cfgs, dae, context, Y, runtime_context)
% Manual override: exact tuple match + fingerprint auth + compatibility,
% NO rerank. Steps 1-7 + 10 (no rerank step 8).
ok = true; err_id = ''; err_msg = '';
cand = struct();
id = @fidi;
runtime_local = runtime;

if ~isfield(req, 'manual_candidate') || ~isstruct(req.manual_candidate) || isempty(req.manual_candidate)
    ok = false; err_id = id('manualCandidateMissing');
    err_msg = 'manual_override request lacks a manual_candidate tuple.';
    return;
end
mc = req.manual_candidate;
if ~isfield(mc, 'selected_gfm_indices') || ~isfield(mc, 'n_gfm_required') || ...
        ~isfield(mc, 'reference_resource_index')
    ok = false; err_id = id('manualCandidateMalformed');
    err_msg = 'manual_candidate tuple must carry selected_gfm_indices, n_gfm_required, reference_resource_index.';
    return;
end

% Step 2 + 3: identity + fingerprint auth mirror automatic branch.
if isempty(runtime_context) || ~isstruct(runtime_context) || isempty(Y)
    ok = false; err_id = id('runtimeContextMissing');
    err_msg = 'manual_override requires non-empty Y and runtime_context.';
    return;
end
if numel(runtime_context.device_modes) ~= numel(runtime_context.eligible_mask)
    ok = false; err_id = id('runtimeContextShape');
    err_msg = 'runtime_context vector length mismatch.';
    return;
end
if numel(dae.devices) ~= numel(runtime_context.device_modes)
    ok = false; err_id = id('identityMismatch');
    err_msg = 'device/resource count mismatch.';
    return;
end
inputs = table.selector_auth_inputs;
inputs.topology_payload = Y;
evidence = struct('sg_off_configurations', table.sg_off.configurations, ...
    'sg_on_configurations', table.sg_on.configurations);
[table_recomp, input_recomp, evidence_recomp] = ...
    compute_selector_table_fingerprint(inputs, evidence);
if ~strcmp(input_recomp, table.selector_input_fingerprint) || ...
        ~strcmp(evidence_recomp, table.candidate_evidence_fingerprint) || ...
        ~strcmp(table_recomp, table.selector_table_fingerprint)
    ok = false; err_id = id('staleFingerprint');
    err_msg = 'selector_table fingerprint stale.';
    runtime_out = runtime_local;
    return;
end

% Step 4: EXACT unique authenticated match.
matches = [];
for i = 1:numel(cfgs)
    c = cfgs(i);
    if isequal(c.selected_gfm_indices, mc.selected_gfm_indices) && ...
            isequal(c.n_gfm_required, mc.n_gfm_required) && ...
            isequal(c.reference_resource_index, mc.reference_resource_index)
        matches(end+1) = i; %#ok<AGROW>
    end
end
runtime_local.candidate_match = ~isempty(matches);
if isempty(matches)
    ok = false; err_id = id('manualCandidateNotInTable');
    err_msg = 'manual_override tuple has no exact authenticated candidate in selector_table.';
    return;
end
if numel(matches) > 1
    ok = false; err_id = id('manualCandidateAmbiguous');
    err_msg = sprintf('manual_override tuple matches %d table rows; require exactly one.', numel(matches));
    return;
end
runtime_local.unique_match = true;
cand = cfgs(matches(1));
runtime_local.ready = isfield(cand,'ready_to_commit') && logical(cand.ready_to_commit);
if ~runtime_local.ready
    ok = false; err_id = id('candidateNotReady');
    err_msg = sprintf('Matched %s candidate not ready_to_commit.', context);
    return;
end
runtime_local.identity_ok = true;
runtime_local.fingerprint_layer_status = 'authenticated';
runtime_local.candidate_match = true;
runtime_out = runtime_local;
end
