function table = ibr_selector_table(case_data, resources, scenario, opt)
%IBR_SELECTOR_TABLE  Precomputed authenticated SG_OFF + SG_ON selector tables.
%   TABLE = ibr_selector_table(CASE_DATA, RESOURCES, SCENARIO, OPT) builds
%   BOTH the SG_OFF and SG_ON candidate tables BEFORE time-domain simulation
%   by calling the EXISTING stability.ibr_config_selector /
%   ibr_candidate_evaluate path. It does NOT duplicate selector, equilibrium,
%   or SSSA algorithms. The complete candidate evidence is cached and bound to
%   a selector_table_fingerprint.
%
%   FEASIBLE-COUNT ENUMERATION (closes the single-count defect): for each
%   context the table enumerates EVERY count in the safe feasible band, not
%   only one caller-pinned count, and lets the frozen ranking policy decide
%   the winner:
%     cmin = 1 for SG_OFF (no synchronous owner => >=1 GFM), 0 for SG_ON (the
%       online SG may own every island; zero GFM is then permitted).
%     cmax = number of eligible switchable GFM-capable IBRs.
%   Topology-infeasible counts (e.g. too few GFMs to cover the islands) are
%   rejected by the evaluator within the enumerated band, so the policy still
%   selects the physically correct count. Candidates are accumulated into a
%   flat array per context sharing ONE struct template; the best feasible
%   across all counts is the authenticated selected_config. A caller pin
%   (manual_override / explicit n_gfm_required) collapses the band to one.
%
%   FINGERPRINT SPLIT: the fingerprint authenticates the full candidate
%   universe (immutable topology/resources/models/parameters/dispatch/policy/
%   gamma_req/cached evidence). Runtime compatibility (topology, resource
%   order, online/hold/lockout/modes) is checked separately by
%   validate_runtime_candidate_compatibility and is NOT folded into the
%   precomputed evidence.
%
%   Output TABLE struct:
%     .sg_off               context result (flat candidate array, all counts)
%     .sg_on                context result (flat candidate array, all counts)
%     .selector_table_fingerprint  authenticates the full candidate universe
%     .gamma_req            frozen margin
%     .built_at             build provenance (no wall-clock; deterministic)
%
%   Selection policy (deterministic, applied at runtime lookup):
%     feasibility -> fewer runtime mode changes -> fewer GFMs ->
%     larger stability margin -> resource-ID tie-break
%
%   Classification: table build PROJECT_DERIVED (calls existing selector);
%   fingerprint canonical serialization NUMERICAL_METHOD. No external solver.
%
%   Source: F1 (three fingerprints), C7 (precomputed authenticated table).

arguments
    case_data struct
    resources struct
    scenario struct
    opt struct = struct()
end

gamma_req = resolve_gamma_req(scenario, opt);

% --- Single-island build gate (Step C) ---------------------------------
% Detect energized islands from the build-time topology BEFORE any candidate
% enumeration. Multi-energized-island topology is NOT_VALIDATED for automatic
% selection (single-island scope, Step 5) and fails closed here. The actual
% energized island ID is recorded so the handler publishes the real ID instead
% of the literal `1` (closes the sg_event_handler.m:112 defect).
[islands, energized_count, energized_island_ids] = analyze_build_islands(case_data);
if energized_count > 1
    error('stability:ibr_selector_table:multiIslandUnsupported', ...
        ['The network has %d energized islands; automatic GFM selection is ' ...
         'validated for a SINGLE energized island only (Step 5). ' ...
         'Multi-island selection is NOT_VALIDATED.'], energized_count);
end

table = struct();
table.gamma_req = gamma_req;
table.build_islands = islands;
table.energized_island_count = energized_count;
table.reference_island_ids = energized_island_ids;
table.sg_off = build_context(case_data, resources, scenario, opt, gamma_req, false);
table.sg_on = build_context(case_data, resources, scenario, opt, gamma_req, true);
[table.selector_table_fingerprint, ...
 table.selector_input_fingerprint, ...
 table.candidate_evidence_fingerprint, ...
 table.selector_auth_inputs, ...
 table.selector_schema_version] = ...
    build_fingerprint(case_data, resources, scenario, gamma_req, table.sg_off, table.sg_on);
table.built_at = 'precomputed_before_ts';
end

% ---------------------------------------------------------------------
function [islands, energized_count, energized_island_ids] = analyze_build_islands(case_data)
% Build-time energized-island analysis (Step C). Uses the SAME canonical
% Ybus construction as build_fingerprint (mirrors ibr_scr_metrics.build_ybus_network:
% tap/shift, branch status col 11, bus shunt G+B) so the build-time Ybus and
% the build-time mpc are always mutually consistent — the branch cross-check
% in island_components.m:79-97 therefore always passes at build time.
%
% Returns the per-component struct array ISLANDS (from stability.island_components),
% the count of ENERGIZED islands, and the list of energized island IDs.
% An isolated bus with no load/shunt/resource is de-energized (island_components.m:8-14)
% and does NOT count toward energized_count.
topology_payload = [];
if isfield(case_data, 'mpc') && isfield(case_data.mpc, 'bus') && ...
        isfield(case_data.mpc, 'branch') && isfield(case_data.mpc, 'baseMVA')
    topology_payload = canonical_ybus_from_mpc(case_data.mpc);
end
if isempty(topology_payload) || ~isfield(case_data, 'mpc')
    islands = struct('island_id', {}, 'bus_positions', {}, 'bus_ids', {}, ...
        'energized', {}, 'has_online_vf_source', {}, 'has_load', {}, 'has_shunt', {});
    energized_count = 0;
    energized_island_ids = [];
    return;
end
islands = stability.island_components(topology_payload, case_data.mpc);
energized_mask = [islands.energized];
energized_count = sum(energized_mask);
energized_island_ids = [islands(energized_mask).island_id];
end

% =========================================================================
function result = build_context(case_data, resources, scenario, opt, gamma_req, sg_online)
prefix = 'sg_off';
if sg_online
    prefix = 'sg_on';
end
% Caller pin (manual_override / explicit single count).
pinned = isfield(opt, prefix) && isstruct(opt.(prefix)) && ...
    isfield(opt.(prefix), 'n_gfm_required') && ~isempty(opt.(prefix).n_gfm_required);

% Feasible-count range per context. The safe bounded band is enumerated and
% the frozen ranking policy (feasible-first) decides the winning count —
% topology-infeasible counts are rejected by the evaluator, so enumeration
% only needs the band [cmin,cmax] below (a NUMERICAL_METHOD, documented):
%   SG_OFF: at least one GFM required (no synchronous owner) → cmin = 1.
%   SG_ON : zero GFM permitted (SG owns its island(s)) → cmin = 0.
% cmax = number of eligible switchable GFM-capable IBRs.
eligible = eligible_gfm_indices(resources);
cmax = numel(eligible);
% Exhaustive-universe safety bound (Step 6): the full-band enumeration is
% validated only for a small eligible universe. A larger universe would make
% the exhaustive build intractable and is NOT_VALIDATED for automatic
% selection. Fail closed BEFORE enumeration with a canonical ID. IEEE14 has
% <= 4 eligible, so this is a safety bound, not a behavior change.
N_exhaustive_max = 4;
if cmax > N_exhaustive_max
    error('stability:gfm_selection:excessiveUniverse', ...
        ['Eligible GFM-capable universe (%d) exceeds the exhaustive ' ...
         'enumeration bound N_exhaustive_max=%d. Automatic selection over a ' ...
         'larger universe is NOT_VALIDATED (use lazy search, a separate mission).'], ...
        cmax, N_exhaustive_max);
end
cmin = 1;
if sg_online, cmin = 0; end
cmin = min(cmin, max(cmax, 0));
if cmax == 0, cmin = 0; end

% Range to enumerate. manual_override / explicit caller count pins to one.
if pinned
    cmin = opt.(prefix).n_gfm_required;
    cmax = opt.(prefix).n_gfm_required;
end
counts = cmin:cmax;

topology = struct('case_data', case_data);

% Accumulate candidates across all feasible counts (one shared struct template).
all_cfgs = repmat(blank_candidate(), 0, 1);
for n_req = counts
    ctx_opt = struct('case_data', case_data, 'gamma_req', gamma_req, 'sg_online', sg_online, ...
        'n_gfm_required', n_req);
    if pinned && isfield(opt.(prefix), 'reference_resource_index') && ...
            ~isempty(opt.(prefix).reference_resource_index)
        ctx_opt.reference_resource_index = opt.(prefix).reference_resource_index;
    end
    if pinned && isfield(opt.(prefix), 'dispatch') && ~isempty(opt.(prefix).dispatch)
        ctx_opt.dispatch = opt.(prefix).dispatch;
    end
    ctx_res = stability.ibr_config_selector(resources, topology, scenario, ctx_opt);
    ctx_res.context = prefix;
    ctx_res.sg_online = sg_online;
    ctx_res.count = n_req;
    if isempty(ctx_res.configurations)
        nothing = blank_candidate();
        nothing.n_gfm_required = n_req;
        all_cfgs = cat_candidates(all_cfgs, nothing);
    else
        cfgs = ctx_res.configurations;
        for i = 1:numel(cfgs)
            cfgs(i).count = n_req;
        end
        all_cfgs = cat_candidates(all_cfgs, cfgs);
    end
end

% Assemble context result over the flat candidate array.
result.context = prefix;
result.sg_online = sg_online;
result.eligible_gfm_indices = eligible;
result.counts = counts;
result.configurations = all_cfgs;
% Overall best feasible across all counts (frozen policy), else first.
% Use the shared NUMERIC ordering primitive (build_audit_order) instead of a
% sprintf string sort key. The original string-key sort (mirroring
% ibr_config_selector.full_ordering_key) had a margin-sort bug: lexicographic
% sort of signed-decimal margin strings is NOT numeric order, so an UNSTABLE
% candidate (negative margin) could wrongly outrank a STABLE one. build_audit_order
% uses internal/candidate_order_matrix (sortrows on a numeric matrix), fixing
% this. build_audit_order is the BUILD-TIME AUDIT path; runtime commit authority
% is stability.runtime_rerank_candidates (advisor finding #1, 2026-07-17).
if ~isempty(all_cfgs)
    [all_cfgs, ~] = stability.build_audit_order(all_cfgs);
end
feasible_idx = find([all_cfgs.feasible], 1);
if ~isempty(feasible_idx)
    selected = all_cfgs(feasible_idx);
    sel_status = 'FEASIBLE';
    fail_id = '';
else
    if isempty(all_cfgs)
        selected = blank_candidate();
    else
        selected = all_cfgs(1);
    end
    sel_status = 'NO_FEASIBLE_CANDIDATE';
    fail_id = 'stability:ibr_config_selector:noFeasibleCandidate';
end
result.selected_config = selected;
result.selected_gfm_indices = selected.selected_gfm_indices;
result.reference_resource_index = selected.reference_resource_index;
result.n_gfm_required = selected.n_gfm_required;
result.structural_feasible = true;
result.topology_evaluated = any([all_cfgs.topology_evaluated]);
result.scr_evaluated = any([all_cfgs.scr_evaluated]);
result.equilibrium_evaluated = any([all_cfgs.equilibrium_evaluated]);
result.sssa_evaluated = any([all_cfgs.sssa_evaluated]);
result.margin = selected.margin;
result.omega = selected.omega;
result.physical_kcl_norm = selected.physical_kcl_norm;
result.ready_to_commit = selected.ready_to_commit;
result.selection_status = sel_status;
result.failure_id = fail_id;
result.feasibility_log = {sprintf('%d candidate counts [%d..%d]; %d feasible', ...
    numel(counts), cmin, cmax, sum([all_cfgs.feasible]))};
result.failed_configs = all_cfgs(~[all_cfgs.feasible]);
end

% ---------------------------------------------------------------------
function eligible = eligible_gfm_indices(resources)
% Eligible switchable GFM-capable IBRs (mirrors ibr_config_selector
% eligibility). Eligible = online, IBR (not SG), can_switch_mode, and
% supports BOTH gfl + gfm.
nr = numel(resources);
eligible = [];
for k = 1:nr
    r = resources(k);
    if ~logical(r.initial_online), continue; end
    try, rt = lower(char(r.resource_type)); catch, rt = 'ibr'; end
    if ~strcmp(rt, 'ibr'), continue; end
    if ~logical(r.can_switch_mode), continue; end
    sup = {};
    if isfield(r, 'capabilities') && isstruct(r.capabilities) && ...
            isfield(r.capabilities, 'supported_modes')
        sup = r.capabilities.supported_modes;
    elseif isfield(r, 'supported_modes')
        sup = r.supported_modes;
    end
    if ~(any(strcmpi(sup, 'gfl')) && any(strcmpi(sup, 'gfm'))), continue; end
    eligible(end+1) = k; %#ok<AGROW>
end
end

function s = blank_candidate()
s = struct('selected_gfm_indices',[],'n_gfm_required',0,'reference_resource_index',[], ...
    'resource_ids',{{}},'modes',{{}},'online',[],'resource_type',{{}}, ...
    'n_mode_changes',0,'tie_break','','ordering_key','', ...
    'feasible',false,'topology_evaluated',false,'scr_evaluated',false, ...
    'scr_pass',false,'equilibrium_evaluated',false,'sssa_evaluated',false, ...
    'sssa_pass',[],'margin',NaN,'omega',NaN,'physical_kcl_norm',Inf, ...
    'fd_eps_values',[],'fd_omegas',[],'fd_stable_classification',[], ...
    'fd_classification_consistent',false,'fd_robust_margin_pass',false, ...
    'fd_zeta_worsts',[],'zeta_min',NaN,'zeta_worst',NaN,'zeta_margin',NaN, ...
    'eigenvalues',[],'reason','','failure_id','','ready_to_commit',false, ...
    'count',0);
end

function out = cat_candidates(out, add)
% Concatenate candidate structs into a homogeneous struct array.
%
% The evaluator (ibr_config_selector) may return candidates with extra
% fields (full_ordering_key, count, modes, ...) beyond blank_candidate, and
% variable-length fields (selected_gfm_indices is [2] for n=1 but
% [2 3 4 5] for n=4). horzcat `[out, add]` fails on either mismatch.
%
% Approach: collect the UNION of all field names across out+add, pad every
% element to that union (missing fields -> blank_candidate value if the
% field exists there, else []), then build the struct array field-by-field
% so variable-length fields are carried per-element without shape constraint.
if isempty(add), return; end
all_fields = fieldnames(blank_candidate());
if ~isempty(out)
    for i = 1:numel(out)
        all_fields = union(all_fields, fieldnames(out(i)));
    end
end
for i = 1:numel(add)
    all_fields = union(all_fields, fieldnames(add(i)));
end
tpl = blank_candidate();
pad_out = pad_to_fields(out, all_fields, tpl);
pad_add = pad_to_fields(add, all_fields, tpl);
n_out = numel(pad_out);
n_add = numel(pad_add);
% Build result by constructing a scalar struct with all fields, then repmat
% and assign per element per field (field-wise assignment tolerates
% variable-length fields).
result = struct();
for k = 1:numel(all_fields)
    f = all_fields{k};
    if isfield(tpl, f)
        result.(f) = tpl.(f);
    else
        result.(f) = [];
    end
end
result = repmat(result, n_out + n_add, 1);
for i = 1:n_out
    for k = 1:numel(all_fields)
        f = all_fields{k};
        result(i).(f) = pad_out(i).(f);
    end
end
for i = 1:n_add
    for k = 1:numel(all_fields)
        f = all_fields{k};
        result(n_out + i).(f) = pad_add(i).(f);
    end
end
out = result;
end

function s_arr = pad_to_fields(s_arr, fields, tpl)
n = numel(s_arr);
if n == 0, return; end
for i = 1:n
    for k = 1:numel(fields)
        f = fields{k};
        if ~isfield(s_arr(i), f)
            if isfield(tpl, f)
                s_arr(i).(f) = tpl.(f);
            else
                s_arr(i).(f) = [];
            end
        end
    end
end
end

function gamma_req = resolve_gamma_req(scenario, opt)
if isfield(opt, 'gamma_req') && ~isempty(opt.gamma_req)
    gamma_req = opt.gamma_req;
elseif isfield(scenario, 'selector') && isstruct(scenario.selector)
    if isfield(scenario.selector, 'gamma_req_rad_per_s') && ...
            ~isempty(scenario.selector.gamma_req_rad_per_s)
        gamma_req = scenario.selector.gamma_req_rad_per_s;
    elseif isfield(scenario.selector, 'gamma_req') && ~isempty(scenario.selector.gamma_req)
        gamma_req = scenario.selector.gamma_req;
    else
        gamma_req = 0.1;
    end
else
    gamma_req = 0.1;
end
if ~isscalar(gamma_req) || ~isfinite(gamma_req) || gamma_req < 0
    error('stability:ibr_selector_table:badGammaReq', ...
        'gamma_req must be a finite nonnegative scalar.');
end
end

function [fp, input_fp, evidence_fp, auth_inputs, schema_version] = ...
        build_fingerprint(case_data, resources, scenario, gamma_req, sg_off, sg_on)
% Canonical fingerprint via the shared function compute_selector_table_fingerprint.
% Builder and validator MUST agree — both call the same canonical serializer.
% Build-time topology is derived from case_data.mpc (immutable network data).
% Runtime validator will re-derive topology from the ACTUAL Y at event time.

% Build topology_payload: the canonical complex Ybus matrix derived from
% case_data.mpc (immutable network data). The fingerprint serializer expects
% a numeric complex matrix, not the mpc struct. This is the SAME audited Ybus
% construction used by ibr_scr_metrics.build_ybus_network (tap/shift, branch
% status col 11, bus shunt G+B) so builder and runtime validator agree.
topology_payload = [];
if isfield(case_data, 'mpc') && isfield(case_data.mpc, 'bus') && ...
        isfield(case_data.mpc, 'branch') && isfield(case_data.mpc, 'baseMVA')
    topology_payload = canonical_ybus_from_mpc(case_data.mpc);
end

% Closed versioned auth envelope (advisor Q1, Revision 4): the immutable
% input struct stored on the table so the validator can recompute the input
% fingerprint WITHOUT reconstructing bus/branch/baseMVA/model_ids/capabilities/
% dispatch/selector/base_values from dae/sched (which do not carry them
% identically to the builder side — see run_hybrid_case.m:263-269,315-329,
% composite_dae.m:245-264). The validator MUST replace .topology_payload
% with live Y before recomputing — it must NEVER compare the stored
% topology fingerprint against itself.
auth_inputs = struct();
auth_inputs.bus = [];
auth_inputs.branch = [];
auth_inputs.baseMVA = [];
if isfield(case_data, 'mpc')
    if isfield(case_data.mpc, 'bus'), auth_inputs.bus = case_data.mpc.bus; end
    if isfield(case_data.mpc, 'branch'), auth_inputs.branch = case_data.mpc.branch; end
    if isfield(case_data.mpc, 'baseMVA'), auth_inputs.baseMVA = case_data.mpc.baseMVA; end
end
nr = numel(resources);
ids = cell(1, nr);
model_ids = cell(1, nr);
caps = cell(1, nr);
for k = 1:nr
    ids{k} = char(resources(k).resource_id);
    if isfield(resources(k), 'model_id')
        model_ids{k} = char(resources(k).model_id);
    else
        model_ids{k} = '';
    end
    if isfield(resources(k), 'capabilities') && isstruct(resources(k).capabilities)
        caps{k} = sprintf('%s|%s|%s', ...
            char(resources(k).capabilities.resource_type), ...
            mat2str(resources(k).capabilities.can_switch_mode), ...
            strjoin(string(resources(k).capabilities.supported_modes), '/'));
    else
        caps{k} = 'none';
    end
end
auth_inputs.resource_ids = ids;
auth_inputs.model_ids = model_ids;
auth_inputs.capabilities = caps;
if isfield(scenario, 'config') && isstruct(scenario.config) && ...
        isfield(scenario.config, 'dispatch')
    auth_inputs.dispatch = scenario.config.dispatch;
end
auth_inputs.gamma_req = gamma_req;
if isfield(scenario, 'selector') && isstruct(scenario.selector)
    auth_inputs.selector = scenario.selector;
end
if isfield(case_data, 'base_values') && isstruct(case_data.base_values)
    auth_inputs.base_values = case_data.base_values;
end
auth_inputs.topology_payload = topology_payload;

% Evidence struct: pass RAW candidate struct arrays through the shared
% canonical serializer (Revision 4). This removes the prior lossy local
% struct_to_str that collapsed cell/struct fields to '?' (advisor Q1).
% Builder + validator now use ONE serialization path.
evidence = struct();
evidence.sg_off_configurations = sg_off.configurations;
evidence.sg_on_configurations = sg_on.configurations;

[fp, input_fp, evidence_fp] = compute_selector_table_fingerprint(auth_inputs, evidence);
schema_version = 'selector_table_v2';
end

function Y = canonical_ybus_from_mpc(mpc)
% Canonical complex Ybus from an mpc struct. This mirrors the audited
% construction in ibr_scr_metrics.build_ybus_network (same tap/shift handling,
% branch-status column 11, bus shunt G+B on baseMVA) so the build-time
% fingerprint and the runtime validator derive IDENTICAL topology matrices
% from the same immutable mpc. No external solver; audited primitives only.
bus = mpc.bus;
br = mpc.branch;
nb = size(bus, 1);
Y = zeros(nb, nb);
for k = 1:size(br, 1)
    if size(br, 2) >= 11 && br(k, 11) == 0, continue; end
    from_id = br(k, 1);
    to_id = br(k, 2);
    i = find(bus(:, 1) == from_id, 1);
    j = find(bus(:, 1) == to_id, 1);
    if isempty(i) || isempty(j), continue; end
    r = br(k, 3); x = br(k, 4); b = br(k, 5);
    tap = br(k, 9); shift = br(k, 10);
    if tap == 0, tap = 1; end
    a = tap * exp(1i * deg2rad(shift));
    yser = 1 / (r + 1i * x);
    Y(i, i) = Y(i, i) + yser / (a * conj(a)) + 1i * b / 2;
    Y(j, j) = Y(j, j) + yser + 1i * b / 2;
    Y(i, j) = Y(i, j) - yser / conj(a);
    Y(j, i) = Y(j, i) - yser / a;
end
if size(bus, 2) >= 6 && isfield(mpc, 'baseMVA') && mpc.baseMVA ~= 0
    Y = Y + diag((bus(:, 5) + 1i * bus(:, 6)) / mpc.baseMVA);
end
end

function h = hash_string(s)
% Deterministic in-house hash (no toolbox dependency). FNV-1a 32-bit variant.
% MATLAB integer multiply is SATURATING (clamps to intmax), not modular, so a
% direct `h * uint32(16777619)` saturates at 0xFFFFFFFF after the first overflow
% and every distinct input collides to the same hash. Use an exact uint64
% intermediate and mask the low 32 bits to implement true modular arithmetic.
% Max product 0xFFFFFFFF * 16777619 ~= 7.2e16 < uint64 max (1.8e19): no overflow.
h = uint32(2166136261);
mask32 = uint64(4294967295);   % 2^32 - 1
for k = 1:numel(s)
    h = bitxor(h, uint32(double(s(k))));
    product = uint64(h) * uint64(16777619);
    h = uint32(bitand(product, mask32));
end
h = sprintf('%08x', h);
end
