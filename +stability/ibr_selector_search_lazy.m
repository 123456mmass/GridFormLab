function table = ibr_selector_search_lazy(case_data, resources, scenario, opt)
%IBR_SELECTOR_SEARCH_LAZY  Opt-in LAZY / on-demand GFM subset search (fail-closed).
%
%   TABLE = stability.ibr_selector_search_lazy(CASE_DATA, RESOURCES, SCENARIO, OPT)
%   is the opt-in alternative to stability.ibr_selector_table when
%   OPT.lazy_gfm_search == true. It searches the SAME candidate space
%   (switchable dual-mode GFM-capable IBR subsets; SG_OFF + SG_ON contexts) but
%   generates candidates LAZILY, screens each with cheap SOUND necessary
%   conditions, and spends a bounded FULL-EVALUATION BUDGET per context.
%
%   It returns a TABLE whose field contract MIRRORS ibr_selector_table so the
%   run_hybrid_case seam can drop it into OPT.selector_table unchanged.
%
%   CERTIFICATE AUTHORITY (do not weaken)
%     A subset is CERTIFIED only when:
%       (1) the evaluator is the TRUSTED production evaluator
%           (opt.candidate_evaluator absent) OR the caller explicitly trusts the
%           stand-in (opt.certificate.trust_evaluator == true); AND
%       (2) it carries the FULL physical evidence the evaluator produces:
%           feasible + ready_to_commit, topology + SCR + equilibrium + SSSA
%           evaluated, a finite equilibrium rcond, a full-KCL SSSA (full_kcl true,
%           finite gy_rcond, finite active/full residual norms), a finite
%           spectrum (eigenvalues + physical_eigenvalues), the 3-member frozen FD
%           perturbation set (finite fd_omegas + fd_zeta_worsts), finite zeta_worst,
%           and physical_kcl_norm <= 1e-6.
%     A caller-injected evaluator that merely sets feasible=true CANNOT mint a
%     certificate. The physical current/P-Q / DC-reserve / synchronism evidence is
%     enforced INSIDE the trusted evaluator (it rejects a violating equilibrium);
%     what the evaluator does NOT re-surface is reported in
%     table.certificate_evidence_gaps and, when
%     opt.certificate.require_physical_evidence == true, is REQUIRED (absence ->
%     INCONCLUSIVE, never a silent approval).
%
%   FAIL-CLOSED STATUSES (per context)
%     'CERTIFIED'             at least one certified subset; ready_to_commit=true
%     'NO_FEASIBLE_CANDIDATE' whole universe evaluated; every candidate
%                             DEFINITIVELY infeasible (no unknowns)
%     'INCONCLUSIVE'          universe evaluated but some candidate's evidence
%                             was UNKNOWN/missing (structural-only is NOT proof
%                             of infeasibility)
%     'HOLD'                  budget ran out before the universe was covered
%     'INVALID_SG_REFERENCE'  SG_ON reference-owner contract violated
%   Only 'CERTIFIED' sets ready_to_commit. A structural-only pass is never a
%   certificate and never proves infeasibility.
%
%   BUDGET (per context). OPT.budget:
%     .max_full_evaluations    default 32 (applied to EACH context)
%     .max_generated           default Inf
%     .stop_on_first_certified default false (opt-in speed, NOT global optimality;
%                              with it, global_optimality_claimed stays false)
%     .sg_off / .sg_on         optional per-context override struct
%
%   Global optimality is claimed only when the whole universe was evaluated
%   (ctx.universe_complete) AND the search was not stopped early.
%
%   STATE-VALIDITY KEY (no canonical-constant fallback). The fingerprint covers
%   topology (bus/branch/baseMVA), load, dispatch, x/y state (when provided),
%   reference, source impedances, ratings, params, resource/model ids, modes and
%   solver options. A change in any PRESENT field changes the key; a fingerprint
%   mismatch forces a COLD search. Required evidence absent -> INCONCLUSIVE.
%
%   Classification: search control PROJECT_DERIVED; fingerprints NUMERICAL_METHOD
%   (shared in-repo serializer). No external solver, no LLM, no commit.

arguments
    case_data struct
    resources struct
    scenario struct = struct()
    opt struct = struct()
end

if ~(isfield(opt, 'lazy_gfm_search') && isscalar(opt.lazy_gfm_search) && ...
        logical(opt.lazy_gfm_search))
    error('stability:ibr_lazy_search:notOptedIn', ...
        'ibr_selector_search_lazy requires opt.lazy_gfm_search = true.');
end

gamma_req = resolve_gamma_req(scenario, opt);
budget = resolve_budget(opt);
cert_opt = resolve_cert_opt(opt);

% --- state-validity evidence -----------------------------------------
[sv, ok_sv, sv_reason, required_missing] = build_state_validity(case_data, resources, scenario, opt, cert_opt);

% --- cheap evidence (SCR / topology) computed ONCE, shared by both contexts.
cheap = build_cheap(case_data, resources, scenario, opt);

if ok_sv
    % augment the state key with source impedances from the cheap evidence and
    % finalize the fingerprint (no canonical-constant fallback).
    sv = augment_source_impedances(sv, cheap, resources);
    sv_fp = hash_string(struct_to_str(sv));
else
    sv_fp = hash_string(sprintf('sv_invalid|%s', strjoin(required_missing, ',')));
end

% --- build-time island summary (best effort; contract fields must exist).
[islands, energized_count, energized_ids] = build_islands_summary(case_data);

if ~ok_sv
    table = inconclusive_table(gamma_req, budget, sv_fp, sv_reason);
    table.cert_opt = cert_opt;
    table.certificate_evidence_gaps = certificate_evidence_gaps(cert_opt, cheap);
    return;
end

% --- cache (keyed by state validity; mismatched fp forces a cold search).
cache = resolve_cache(opt, sv_fp);

table = struct();
table.schema = 'ibr_lazy_search/1.0';
table.gamma_req = gamma_req;
table.build_islands = islands;
table.energized_island_count = energized_count;
table.reference_island_ids = energized_ids;
table.budget = budget;
table.budget_per_context = true;
table.lazy_gfm_search = true;
table.state_validity_fingerprint = sv_fp;
table.state_validity = sv;
table.built_at = 'lazy_on_demand';
table.cert_opt = cert_opt;
table.certificate_evidence_gaps = certificate_evidence_gaps(cert_opt, cheap);

[table.sg_off, cache] = run_context(case_data, resources, scenario, opt, ...
    'sg_off', false, gamma_req, cheap, budget, sv_fp, cert_opt, cache);
[table.sg_on, cache] = run_context(case_data, resources, scenario, opt, ...
    'sg_on', true, gamma_req, cheap, budget, sv_fp, cert_opt, cache);

table.cache_invalidated = isfield(cache, 'invalidated') && cache.invalidated;
table.search_cache = cache;

% --- fingerprints ------------------------------------------------------
[auth_inputs, evidence] = build_fingerprint_inputs(case_data, resources, ...
    scenario, gamma_req, table.sg_off, table.sg_on, sv, cheap);
[fp, input_fp, evidence_fp] = compute_selector_table_fingerprint(auth_inputs, evidence);
table.selector_table_fingerprint = fp;
table.selector_input_fingerprint = input_fp;
table.candidate_evidence_fingerprint = evidence_fp;
table.selector_auth_inputs = auth_inputs;
table.selector_schema_version = 'ibr_lazy_search_v1';
table.search_fingerprint = hash_string(sprintf('lazy|sv=%s|gamma=%.12g|ev=%s', ...
    sv_fp, gamma_req, evidence_fp));
end

% =====================================================================
% Context search
% =====================================================================
function [res, cache] = run_context(case_data, resources, scenario, opt, ...
        prefix, sg_online, gamma_req, cheap, budget, sv_fp, cert_opt, cache)
res = blank_context(prefix, sg_online);
eligible = eligible_gfm_indices(resources);
res.eligible_gfm_indices = eligible;
nr = numel(resources);

budget = merge_context_budget(budget, opt, prefix);

[ids, modes, online, rt] = committed_arrays(resources, scenario);

reference = [];
ref_pinned = false;
if isfield(opt, prefix) && isstruct(opt.(prefix))
    pin = opt.(prefix);
else
    pin = struct();
end
if isfield(pin, 'reference_resource_index') && ~isempty(pin.reference_resource_index)
    reference = pin.reference_resource_index;
    ref_pinned = true;
end

% ---- Resolve a designated reference OWNER ---------------------------------
% The owner is drawn from the evidence the caller already carries: the pinned
% opt.<prefix>.reference_resource_index, else the scenario/commit policy
% (reference_owner_indices / gfm_reference_resource_indices, then the scalar
% aliases in reference_policy / committed_selection / config). A >1-element
% owner list means a MULTI-ISLAND owner set; single-island scope cannot pick
% one -> fail closed (never silently choose the first).
owner_idx = [];
owner_source = '';
owner_ambiguous = false;
if ref_pinned
    owner_idx = reference;
    owner_source = 'pin';
else
    [owner_idx, owner_ambiguous] = resolve_reference_owner(scenario);
    if ~isempty(owner_idx)
        owner_source = 'scenario';
    end
end
if owner_ambiguous
    res.selection_status = 'INVALID_SG_REFERENCE';
    res.failure_id = 'stability:ibr_lazy_search:multiIslandOwnerAmbiguous';
    res.selection_reason = ['Multiple reference owners (multi-island) with no ' ...
        'single-island designation; owner ambiguity fails closed.'];
    res.counts = [];
    return;
end

if sg_online
    % SG_ON: the reference owner must be an ONLINE synchronous generator. The
    % owner is designated by pin / scenario policy / island evidence. The count
    % of online SGs (numel(online_sg)) is used ONLY as a benign equal-one
    % fallback; a multi-SG online island is valid and MUST be able to certify
    % once an owner is resolved. We never require numel(online_sg) == 1.
    online_sg = find(online & strcmp(rt, 'sg'));
    if isempty(online_sg)
        res.selection_status = 'INVALID_SG_REFERENCE';
        res.failure_id = 'stability:ibr_lazy_search:noOnlineSgOwner';
        res.selection_reason = 'SG_ON requires an online synchronous owner; none is online.';
        res.counts = [];
        return;
    end
    if strcmp(owner_source, 'pin')
        if ~ismember(reference, online_sg)
            res.selection_status = 'INVALID_SG_REFERENCE';
            res.failure_id = 'stability:ibr_lazy_search:referenceOwnerNotOnlineSg';
            res.selection_reason = 'The pinned reference owner is not an online SG.';
            res.counts = [];
            return;
        end
        ref_pinned = true;
    elseif strcmp(owner_source, 'scenario') && ismember(owner_idx, online_sg)
        reference = owner_idx;
        ref_pinned = true;
    elseif numel(online_sg) == 1
        reference = online_sg;
        ref_pinned = true;
    else
        res.selection_status = 'INVALID_SG_REFERENCE';
        res.failure_id = 'stability:ibr_lazy_search:sgReferenceAmbiguous';
        res.selection_reason = sprintf(['SG_ON with %d online SGs and no ' ...
            'designated reference owner (pin or scenario policy). Multi-SG ' ...
            'owner ambiguity fails closed; the first is NOT chosen.'], numel(online_sg));
        res.counts = [];
        return;
    end
else
    % SG_OFF: a designated owner is only binding when it is an eligible
    % voltage-forming IBR in THIS context. A stale SG / pre-trip owner is not a
    % hard constraint (the trip removed its voltage-forming role); ignore it
    % rather than rejecting the whole universe on a stale alias.
    if strcmp(owner_source, 'scenario') && ismember(owner_idx, eligible)
        reference = owner_idx;
        ref_pinned = true;
    elseif strcmp(owner_source, 'pin') && ~ismember(reference, eligible)
        reference = [];
        ref_pinned = false;
    end
end

pinned = isfield(pin, 'n_gfm_required') && ~isempty(pin.n_gfm_required);
cmax = numel(eligible);
cmin = 1;
if sg_online, cmin = 0; end
cmin = min(cmin, max(cmax, 0));
if cmax == 0, cmin = 0; end
if pinned
    cmin = pin.n_gfm_required;
    cmax = pin.n_gfm_required;
end
if isempty(eligible) || cmin > cmax
    res.counts = cmin:cmax;
    res.selection_status = 'NO_FEASIBLE_CANDIDATE';
    res.failure_id = 'stability:ibr_lazy_search:insufficientEligibleGfm';
    res.selection_reason = 'No eligible GFM-capable IBR band to search.';
    return;
end
counts = cmin:cmax;
res.counts = counts;

screen_provider = default_screen_provider(opt);
% ส่ง context ที่กำลังค้นจริง ไม่ให้ SG_ON ถูกประเมินเป็น SG_OFF.
eval_context_opt = opt;
eval_context_opt.sg_online = sg_online;
eval_provider = default_eval_provider(eval_context_opt, case_data, resources, gamma_req);

screen_opt = struct('sg_online', sg_online);
if ref_pinned && ~sg_online
    screen_opt.reference_resource_index = reference;
end

ctx_gen = struct('eligible', eligible, 'counts', counts);
cursor = [];
% SG_ON ต้องประเมิน committed initial set ก่อน เพื่อไม่หยุดที่ certificate
% ของโหมดอื่นโดยยังไม่เคยตรวจโหมดที่จะเริ่ม simulation จริง.
initial_spec = [];
if sg_online
    initial_selected = find(strcmpi(modes,'gfm'));
    if ismember(numel(initial_selected),counts) && all(ismember(initial_selected,eligible))
        initial_spec = struct('selected_gfm_indices',initial_selected, ...
            'n_gfm_required',numel(initial_selected));
    end
end
initial_pending = ~isempty(initial_spec);
drained = false;
% Accumulate evaluated candidates in a cell array. The evaluator may SURFACE
% extra fields (e.g. an evidence record array) and a struct-array append
% requires identical fields; materialise the struct array once, after the
% loop, over the union of observed fields.
eval_cells = {};
n_generated = 0; n_infeasible = 0; n_unknown = 0; n_eval = 0; n_cached = 0;
budget_exhausted = false;

while true
    if initial_pending
        spec = initial_spec; initial_pending = false; done = false;
    else
        [spec, cursor, done] = stability.ibr_lazy_priority(cursor, ctx_gen);
        if ~done && ~isempty(initial_spec) && ...
                isequal(spec.selected_gfm_indices,initial_spec.selected_gfm_indices)
            continue;
        end
    end
    if done
        drained = true;
        break;
    end
    n_generated = n_generated + 1;
    if isfinite(budget.max_generated) && n_generated > budget.max_generated
        budget_exhausted = true;
        break;
    end

    cand = build_candidate(spec, ids, modes, online, rt, reference, ...
        sg_online, ref_pinned);

    sc = feval_any(screen_provider, spec, resources, cheap, screen_opt);
    if strcmp(sc.verdict, 'INFEASIBLE')
        n_infeasible = n_infeasible + 1;
        continue;
    end
    n_unknown = n_unknown + 1;

    key = candidate_key(cand);
    cached = cache_lookup(cache, sv_fp, key, cert_opt);
    if ~isempty(cached)
        eval_cells{end+1} = cached; %#ok<AGROW>
        n_cached = n_cached + 1;
        continue;
    end

    if n_eval >= budget.max_full_evaluations
        budget_exhausted = true;
        break;
    end
    n_eval = n_eval + 1;

    c_out = feval_eval(eval_provider, cand, cheap);
    if ~isfield(c_out, 'feasible'), c_out.feasible = false; end
    eval_cells{end+1} = c_out; %#ok<AGROW>
    if is_certified(c_out, cert_opt)
        cache = cache_store(cache, key, c_out);
        if budget.stop_on_first_certified
            budget_exhausted = true;
            break;
        end
    end
end

evaluated = cellstruct_to_structarray(eval_cells);

res.n_generated = n_generated;
res.n_screened_infeasible = n_infeasible;
res.n_screened_unknown = n_unknown;
res.n_evaluated = n_eval;
res.n_cached = n_cached;
res.budget_exhausted = budget_exhausted;
res.universe_complete = drained;
res.configurations = evaluated;
res.topology_evaluated = any_flag(evaluated, 'topology_evaluated');
res.scr_evaluated = any_flag(evaluated, 'scr_evaluated');
res.equilibrium_evaluated = any_flag(evaluated, 'equilibrium_evaluated');
res.sssa_evaluated = any_flag(evaluated, 'sssa_evaluated');

% --- classify every evaluated candidate ------------------------------
n_cert = 0; n_definf = 0; n_unk = 0;
cert_idx = [];
definf_mask = false(1, numel(evaluated));
for i = 1:numel(evaluated)
    if is_certified(evaluated(i), cert_opt)
        n_cert = n_cert + 1;
        cert_idx(end+1) = i; %#ok<AGROW>
    elseif is_definitively_infeasible(evaluated(i))
        n_definf = n_definf + 1;
        definf_mask(i) = true;
    else
        n_unk = n_unk + 1;
    end
end
% ready_to_commit เป็นอำนาจของ certificate gate ไม่ใช่ flag จาก evaluator.
% runtime validator อ่าน configurations โดยตรง จึงห้ามเหลือ raw-ready row
% ที่ขาด physical evidence แม้ใน context เดียวกันจะมี row อื่นผ่านแล้ว.
for i=1:numel(evaluated)
    evaluated(i).ready_to_commit = ismember(i,cert_idx);
end
res.configurations = evaluated;
res.n_certified = n_cert;
res.n_definitive_infeasible = n_definf;
res.n_unknown_evaluated = n_unk;
res.failed_configs = evaluated(~arrayfun(@(c) is_certified(c, cert_opt), evaluated));

% --- best-ranked candidate (DIAGNOSTIC; never a commit authority) -----
order = rank_candidates(evaluated);
if ~isempty(order)
    bc = evaluated(order(1));
    res.best_ranked_config = bc;
    res.best_ranked_gfm_indices = bc.selected_gfm_indices;
    res.best_ranked_objective_rank = 1;
end

res.global_optimality_claimed = false;
if ~isempty(cert_idx)
    % pick the best-ranked CERTIFIED candidate (frozen objective)
    sel_idx = [];
    for oi = 1:numel(order)
        if any(order(oi) == cert_idx)
            sel_idx = order(oi);
            break;
        end
    end
    sel = evaluated(sel_idx);
    res.selected_config = sel;
    res.selected_gfm_indices = sel.selected_gfm_indices;
    res.reference_resource_index = sel.reference_resource_index;
    res.n_gfm_required = sel.n_gfm_required;
    res.margin = getfield_or(sel, 'margin', NaN);
    res.omega = getfield_or(sel, 'omega', NaN);
    res.physical_kcl_norm = getfield_or(sel, 'physical_kcl_norm', Inf);
    res.ready_to_commit = true;
    res.selection_status = 'CERTIFIED';
    res.failure_id = '';
    res.global_optimality_claimed = drained && ~budget.stop_on_first_certified;
    if res.global_optimality_claimed
        res.selection_reason = 'Certified feasible subset; whole universe evaluated.';
    else
        res.selection_reason = ['Certified feasible subset under budget/early-stop; ' ...
            'NOT globally optimal (universe not fully evaluated).'];
    end
    res.feasibility_log = {sprintf( ...
        ['lazy: generated %d, screened-infeasible %d, unknown %d, evaluated %d, ' ...
         'cached %d, certified %d'], ...
        n_generated, n_infeasible, n_unknown, n_eval, n_cached, n_cert)};
    return;
end

% --- no certificate: fail closed with the RIGHT reason ----------------
res.ready_to_commit = false;
res.selected_config = blank_candidate();
res.selected_gfm_indices = [];
res.reference_resource_index = reference;
res.n_gfm_required = NaN;
res.margin = NaN; res.omega = NaN; res.physical_kcl_norm = Inf;
if ~drained
    % budget ran out with unevaluated candidates
    if n_unk > 0
        res.selection_status = 'INCONCLUSIVE';
        res.failure_id = 'stability:ibr_lazy_search:inconclusiveEvidence';
        res.selection_reason = sprintf( ...
            ['Budget exhausted (HOLD) after %d evaluation(s); %d candidate(s) ' ...
             'had UNKNOWN evidence and some candidates are unevaluated.'], n_eval, n_unk);
    else
        res.selection_status = 'HOLD';
        res.failure_id = 'stability:ibr_lazy_search:budgetHold';
        res.selection_reason = sprintf( ...
            ['Budget exhausted after %d full evaluation(s) with no certificate; ' ...
             'remaining candidates unevaluated. Fail closed (HOLD).'], n_eval);
    end
elseif n_unk > 0
    % whole universe evaluated but some evidence was UNKNOWN: structural-only /
    % missing evidence is NOT a proof of infeasibility.
    res.selection_status = 'INCONCLUSIVE';
    res.failure_id = 'stability:ibr_lazy_search:inconclusiveEvidence';
    res.selection_reason = sprintf( ...
        ['Whole universe evaluated; %d candidate(s) had UNKNOWN/missing evidence ' ...
         'and no subset certified. Inconclusive, NOT proven infeasible.'], n_unk);
else
    res.selection_status = 'NO_FEASIBLE_CANDIDATE';
    res.failure_id = 'stability:ibr_lazy_search:noFeasibleCandidate';
    res.selection_reason = 'Whole universe evaluated; every subset definitively infeasible.';
end
res.feasibility_log = {sprintf( ...
    'lazy: generated %d, screened-infeasible %d, unknown %d, evaluated %d, certified 0', ...
    n_generated, n_infeasible, n_unknown, n_eval)};
end

% =====================================================================
% Certification predicate -- the ONLY path to ready_to_commit
% =====================================================================
function tf = is_certified(c, cert_opt)
tf = false;
if ~isstruct(c) || ~isscalar(c), return; end
% (1) trusted evaluator only
if ~cert_opt.trust_evaluator, return; end
req = {'feasible', 'ready_to_commit', 'topology_evaluated', 'scr_evaluated', ...
    'equilibrium_evaluated', 'sssa_evaluated'};
for k = 1:numel(req)
    if ~isfield(c, req{k}) || isempty(c.(req{k})) || ~logical(c.(req{k}))
        return;
    end
end
% (2) the full physical evidence the evaluator produces
if ~isfinite(getfield_or(c, 'eq_rcond', NaN)), return; end
if ~(isfield(c, 'full_kcl') && ~isempty(c.full_kcl) && logical(c.full_kcl)), return; end
if ~isfinite(getfield_or(c, 'gy_rcond', NaN)), return; end
if ~isfinite(getfield_or(c, 'sssa_f0_norm', NaN)), return; end
if ~isfinite(getfield_or(c, 'sssa_g0_norm', NaN)), return; end
if ~isfinite(getfield_or(c, 'physical_kcl_norm', Inf)) || c.physical_kcl_norm > 1e-6
    return;
end
if isempty(getfield_or(c, 'eigenvalues', [])), return; end
if isempty(getfield_or(c, 'physical_eigenvalues', [])), return; end
fdw = getfield_or(c, 'fd_omegas', []); fdz = getfield_or(c, 'fd_zeta_worsts', []);
if numel(fdw) ~= 3 || any(~isfinite(fdw)), return; end
if numel(fdz) ~= 3 || any(~isfinite(fdz)), return; end
if ~isfinite(getfield_or(c, 'zeta_worst', NaN)), return; end
if ~isfinite(getfield_or(c, 'margin', NaN)), return; end
% (2b) Physical-evidence RECORD ABI (shared with the evaluator): when the
% evaluator emits per-item records {id, applicable, status, value, provenance},
% every APPLICABLE item must PASS. A PENDING_DEVICE_SURFACE item never
% certifies; NOT_APPLICABLE is only acceptable for a STEADY synchronism item
% (never for a transition item). Absent records -> fall back to the scalar
% vector above (no regression for callers that do not surface records).
recs = getfield_or(c, 'evidence', []);
if isempty(recs), recs = getfield_or(c, 'physical_evidence', []); end
if isempty(recs), recs = getfield_or(c, 'evidence_records', []); end
if ~isempty(recs) && ~evidence_records_pass(recs)
    return;
end
% (3) applicable physical evidence (only when the caller requires surfacing)
if cert_opt.require_physical_evidence
    if ~(isfield(c, 'within_limits') && ~isempty(c.within_limits) && logical(c.within_limits))
        return;
    end
    if isfield(c, 'synchronism_ok') && ~isempty(c.synchronism_ok) && ~logical(c.synchronism_ok)
        return;
    end
    if cert_opt.require_dc_reserve
        if ~(isfield(c, 'dc_reserve_MW') && isfinite(c.dc_reserve_MW) && c.dc_reserve_MW >= 0)
            return;
        end
    end
end
tf = true;
end

function ok = evidence_records_pass(recs)
% Shared physical-evidence record ABI: {id, applicable, status, value,
% provenance}. A record passes when applicable==true and status is a pass word.
% NOT_APPLICABLE is only legitimately waivable for a STEADY synchronism item,
% never for a transition item. A PENDING_DEVICE_SURFACE / incomplete / unknown
% item always blocks certification.
ok = true;
if ~isstruct(recs)
    return;
end
pass_words = {'PASS', 'OK', 'SATISFIED', 'COMPLETE', 'WITHIN_LIMITS', 'VALID'};
for k = 1:numel(recs)
    r = recs(k);
    id = '';
    if isfield(r, 'id') && ~isempty(r.id), id = upper(char(r.id)); end
    applicable = true;
    if isfield(r, 'applicable') && ~isempty(r.applicable)
        applicable = logical(r.applicable);
    end
    status = '';
    if isfield(r, 'status') && ~isempty(r.status), status = upper(char(r.status)); end
    is_transition = ~isempty(strfind(id, 'TRANSITION')); %#ok<STREMP>
    is_synchronism = ~isempty(strfind(id, 'SYNCHRON')); %#ok<STREMP>
    if ~applicable
        steady_sync = is_synchronism && ~is_transition;
        if ~steady_sync
            ok = false;
            return;
        end
        continue;
    end
    if ~isempty(strfind(id, 'PENDING')) || ... %#ok<STREMP>
            strcmp(status, 'PENDING') || strcmp(status, 'PENDING_DEVICE_SURFACE') || ...
            strcmp(status, 'INCOMPLETE') || strcmp(status, 'UNKNOWN') || ...
            strcmp(status, 'DEFERRED')
        ok = false;
        return;
    end
    if ~any(strcmp(status, pass_words))
        ok = false;
        return;
    end
end
end

function tf = is_definitively_infeasible(c)
% A candidate is DEFINITIVELY infeasible only when the evaluator reached a
% physical rejection with real evidence. Non-convergence, exceptions, and
% structural-only outcomes are UNKNOWN (not proof of infeasibility).
tf = false;
if ~isstruct(c) || ~isscalar(c), return; end
if isfield(c, 'scr_evaluated') && ~isempty(c.scr_evaluated) && logical(c.scr_evaluated)
    if isfield(c, 'scr_pass') && ~isempty(c.scr_pass) && ~logical(c.scr_pass)
        tf = true; return;
    end
end
if isfield(c, 'equilibrium_evaluated') && logical(c.equilibrium_evaluated) && ...
        isfield(c, 'sssa_evaluated') && logical(c.sssa_evaluated) && ...
        ~(isfield(c, 'feasible') && ~isempty(c.feasible) && logical(c.feasible))
    tf = true; return;
end
if isfield(c, 'equilibrium_evaluated') && logical(c.equilibrium_evaluated) && ...
        isfield(c, 'physical_kcl_norm') && isfinite(c.physical_kcl_norm) && ...
        c.physical_kcl_norm > 1e-6
    tf = true; return;
end
end

% =====================================================================
% Candidate construction
% =====================================================================
function c = build_candidate(spec, ids, modes, online, rt, reference, sg_online, ref_pinned)
nr = numel(ids);
selected = reshape(spec.selected_gfm_indices, 1, []);
c = blank_candidate();
c.resource_ids = ids;
c.resource_type = rt;
c.online = online;
c.selected_gfm_indices = selected;
c.n_gfm_required = numel(selected);

candidate_modes = modes;
for k = 1:nr
    if strcmp(rt{k}, 'ibr') && ismember(k, spec.selected_gfm_indices)
        candidate_modes{k} = 'gfm';
    elseif strcmp(rt{k}, 'ibr') && is_eligible_mode_target(modes{k})
        candidate_modes{k} = 'gfl';
    end
end
c.modes = candidate_modes;
changed = 0;
for k = 1:nr
    changed = changed + ~strcmpi(candidate_modes{k}, modes{k});
end
c.n_mode_changes = changed;

if ref_pinned && ~isempty(reference)
    c.reference_resource_index = reference;
elseif isempty(selected)
    c.reference_resource_index = reference;
else
    c.reference_resource_index = min(selected);
end
selected_ids = ids(selected);
c.tie_break = strjoin(sort(selected_ids), ',');
c.ordering_key = sprintf('%09d|%s', changed, c.tie_break);
c.structural_feasible = true;
c.reason = 'lazyStructuralCandidate';
c.failure_id = 'stability:ibr_lazy_search:notEvaluated';
end

function tf = is_eligible_mode_target(m)
tf = any(strcmpi(char(m), {'gfl', 'gfm'}));
end

% =====================================================================
% Ranking -- frozen objective, shared primitive with build_audit_order
% =====================================================================
function order = rank_candidates(candidates)
n = numel(candidates);
if n == 0
    order = [];
    return;
end
nc = getfield_vec(candidates, 'n_mode_changes', Inf);
try
    [M, ~] = candidate_order_matrix(candidates, nc);
    [~, order] = sortrows(M, [1 2 3 4 5]);
catch
    M = zeros(n, 5);
    for i = 1:n
        c = candidates(i);
        fflag = 1;
        if isfield(c, 'feasible') && ~isempty(c.feasible) && logical(c.feasible)
            fflag = 0;
        end
        mg = getfield_or(c, 'margin', NaN);
        if isfinite(mg), mkey = -mg; else, mkey = 1e12; end
        ngfm = getfield_or(c, 'n_gfm_required', 0);
        M(i, :) = [fflag, nc(i), ngfm, mkey, i];
    end
    [~, order] = sortrows(M, [1 2 3 4 5]);
end
end

% =====================================================================
% Providers
% =====================================================================
function p = default_screen_provider(opt)
if isfield(opt, 'candidate_screen') && ~isempty(opt.candidate_screen)
    p = opt.candidate_screen;
else
    p = @(spec, res, cheap, sopt) stability.ibr_candidate_screen(spec, res, cheap, sopt);
end
end

function p = default_eval_provider(opt, case_data, resources, gamma_req)
if isfield(opt, 'candidate_evaluator') && ~isempty(opt.candidate_evaluator)
    p = opt.candidate_evaluator;
else
    eval_opt = struct();
    if isfield(opt, 'sg_online'), eval_opt.sg_online = opt.sg_online; end
    if isfield(opt, 'dispatch'), eval_opt.dispatch = opt.dispatch; end
    if isfield(opt, 'equilibrium_opt'), eval_opt.equilibrium_opt = opt.equilibrium_opt; end
    if isfield(opt, 'sssa_opt'), eval_opt.sssa_opt = opt.sssa_opt; end
    p = @(cand, scr) stability.ibr_candidate_evaluate( ...
        case_data, resources, cand, scr, gamma_req, eval_opt);
end
end

function out = feval_any(p, varargin)
if isa(p, 'function_handle')
    out = p(varargin{:});
else
    out = feval(p, varargin{:});
end
end

function out = feval_eval(p, cand, cheap)
scr = struct();
if isfield(cheap, 'scr_struct') && ~isempty(cheap.scr_struct)
    scr = cheap.scr_struct;
end
out = feval_any(p, cand, scr);
end

% =====================================================================
% Cheap evidence
% =====================================================================
function cheap = build_cheap(case_data, resources, scenario, opt)
cheap = struct('is_singular', false, 'topology_ok', true, 'Y_rcond', NaN, ...
    'scr_available', false, 'scr_per_resource', [], 'scr_struct', struct(), ...
    'source_aware', false);
scr = [];
if isfield(opt, 'cheap_provider') && ~isempty(opt.cheap_provider)
    cheap = feval_any(opt.cheap_provider, case_data, resources, scenario, opt);
    return;
end
if isfield(opt, 'scr_metrics') && ~isempty(opt.scr_metrics) && isstruct(opt.scr_metrics)
    scr = opt.scr_metrics;
else
    try
        topo = struct('case_data', case_data);
        scr = stability.ibr_scr_metrics(case_data, resources, topo, struct());
    catch me
        cheap.scr_available = false;
        cheap.scr_failure = me.message;
        return;
    end
end
cheap.scr_struct = scr;
if isfield(scr, 'is_singular'), cheap.is_singular = logical(scr.is_singular); end
if isfield(scr, 'Y_rcond'), cheap.Y_rcond = scr.Y_rcond; end
if isfield(scr, 'topology_ok'), cheap.topology_ok = logical(scr.topology_ok); end
if isfield(scr, 'Ybus') && ~isempty(scr.Ybus), cheap.topology_ok = true; end
if isfield(scr, 'method'), cheap.source_aware = strcmpi(char(scr.method), 'source_aware'); end
if isfield(scr, 'per_resource') && ~isempty(scr.per_resource)
    cheap.scr_per_resource = scr.per_resource;
    cheap.scr_available = true;
end
end

% =====================================================================
% State validity (expanded key; no canonical-constant fallback)
% =====================================================================
function [sv, ok, reason, missing] = build_state_validity(case_data, resources, scenario, opt, cert_opt)
sv = struct(); missing = {};
if isfield(opt, 'state_validity') && isstruct(opt.state_validity) && ...
        ~isempty(fieldnames(opt.state_validity))
    sv = opt.state_validity;
else
    if isfield(case_data, 'mpc')
        if isfield(case_data.mpc, 'bus'), sv.bus = case_data.mpc.bus; end
        if isfield(case_data.mpc, 'branch'), sv.branch = case_data.mpc.branch; end
        if isfield(case_data.mpc, 'baseMVA'), sv.baseMVA = case_data.mpc.baseMVA; end
        if isfield(case_data.mpc, 'bus') && size(case_data.mpc.bus, 2) >= 4
            sv.load = case_data.mpc.bus(:, 3:4);   % actual Pd/Qd load
        end
    end
    nr = numel(resources);
    ids = cell(1, nr); mdl = cell(1, nr); cap = cell(1, nr); rat = cell(1, nr);
    par = cell(1, nr); mode = cell(1, nr); onl = false(1, nr);
    for k = 1:nr
        ids{k} = char(resources(k).resource_id);
        mdl{k} = getfield_or(resources(k), 'model_id', '');
        if isfield(resources(k), 'capabilities') && isstruct(resources(k).capabilities)
            cap{k} = sprintf('%s|%s|%s', char(resources(k).capabilities.resource_type), ...
                mat2str(logical(resources(k).capabilities.can_switch_mode)), ...
                strjoin(string(resources(k).capabilities.supported_modes), '/'));
        else
            cap{k} = 'none';
        end
        rat{k} = struct_to_str(getfield_or(resources(k), 'ratings', struct()));
        par{k} = struct_to_str(getfield_or(resources(k), 'dynamic_params', struct()));
        mode{k} = char(getfield_or(resources(k), 'initial_mode', ''));
        onl(k) = logical(getfield_or(resources(k), 'initial_online', false));
    end
    sv.resource_ids = ids; sv.model_ids = mdl; sv.capabilities = cap;
    sv.ratings = rat; sv.params = par; sv.modes = mode; sv.online = onl;
    if isfield(scenario, 'config') && isfield(scenario.config, 'dispatch')
        sv.dispatch = scenario.config.dispatch;
    elseif isfield(opt, 'dispatch') && isstruct(opt.dispatch) && ~isempty(opt.dispatch)
        sv.dispatch = opt.dispatch;
    end
end

% runtime state / reference / solver options (present == included in the key)
if isfield(opt, 'state_validity') && isstruct(opt.state_validity)
    if isfield(opt.state_validity, 'x'), sv.x = opt.state_validity.x; end
    if isfield(opt.state_validity, 'y'), sv.y = opt.state_validity.y; end
    if isfield(opt.state_validity, 'reference_resource_index')
        sv.reference_resource_index = opt.state_validity.reference_resource_index;
    end
end
sv.solver_options = struct( ...
    'equilibrium_opt', getfield_or(opt, 'equilibrium_opt', struct()), ...
    'sssa_opt', getfield_or(opt, 'sssa_opt', struct()), ...
    'gamma_req', resolve_gamma_req(scenario, opt));
sv.model_version = getfield_or(opt, 'model_version', getfield_or(sv, 'model_version', 'eecon49_dual'));
sv.solver_id = getfield_or(opt, 'solver_id', getfield_or(sv, 'solver_id', 'inhouse_nr'));
sv.schema_version = getfield_or(opt, 'schema_version', getfield_or(sv, 'schema_version', 'ibr_lazy_search/1.0'));

% required evidence gate
if ~isfield(sv, 'bus') || isempty(sv.bus), missing{end+1} = 'topology.bus'; end
if ~isfield(sv, 'branch') || isempty(sv.branch), missing{end+1} = 'topology.branch'; end
if ~isfield(sv, 'baseMVA') || isempty(sv.baseMVA), missing{end+1} = 'topology.baseMVA'; end
if ~isfield(sv, 'resource_ids') || isempty(sv.resource_ids), missing{end+1} = 'resource_ids'; end
if ~isfield(sv, 'model_ids') || isempty(sv.model_ids), missing{end+1} = 'model_ids'; end
% state-dependent requirements, only when the caller demands a full runtime key
if cert_opt.require_state
    if ~isfield(sv, 'x') || isempty(sv.x), missing{end+1} = 'x'; end
    if ~isfield(sv, 'y') || isempty(sv.y), missing{end+1} = 'y'; end
    if ~isfield(sv, 'dispatch') || isempty(sv.dispatch), missing{end+1} = 'dispatch'; end
end
if cert_opt.require_physical_evidence
    if ~isfield(sv, 'dispatch') || isempty(sv.dispatch), missing{end+1} = 'dispatch'; end
end

if ~isempty(missing)
    ok = false;
    reason = sprintf('Required state-validity evidence missing: %s', strjoin(missing, ', '));
else
    ok = true;
    reason = '';
end
end

function sv = augment_source_impedances(sv, cheap, resources)
% Fold measured source/Thevenin impedances into the key when available so a
% source-impedance change invalidates the fingerprint. No constant fallback.
sv.source_impedances = [];
if isfield(cheap, 'scr_per_resource') && ~isempty(cheap.scr_per_resource)
    n = numel(cheap.scr_per_resource);
    Z = complex(NaN(1, n), NaN(1, n));
    for p = 1:n
        if isfield(cheap.scr_per_resource(p), 'Zth') && ...
                ~isempty(cheap.scr_per_resource(p).Zth)
            Z(p) = cheap.scr_per_resource(p).Zth;
        end
    end
    if any(isfinite(real(Z)) | isfinite(imag(Z)))
        sv.source_impedances = Z;
    end
end
end

function [auth, evidence] = build_fingerprint_inputs(case_data, resources, scenario, ...
        gamma_req, sg_off, sg_on, sv, cheap)
auth = struct();
if isfield(case_data, 'mpc')
    if isfield(case_data.mpc, 'bus'), auth.bus = case_data.mpc.bus; end
    if isfield(case_data.mpc, 'branch'), auth.branch = case_data.mpc.branch; end
    if isfield(case_data.mpc, 'baseMVA'), auth.baseMVA = case_data.mpc.baseMVA; end
end
auth.resource_ids = sv.resource_ids;
auth.model_ids = sv.model_ids;
auth.capabilities = sv.capabilities;
auth.gamma_req = gamma_req;
if isfield(sv, 'dispatch'), auth.dispatch = sv.dispatch; end
if isfield(scenario, 'selector'), auth.selector = scenario.selector; end
auth.state_validity = sv;
auth.resource_contracts = resources;
if isfield(case_data,'base_values'), auth.base_values = case_data.base_values; end
if isfield(case_data,'dispatch_contract'), auth.dispatch_contract = case_data.dispatch_contract; end
if isfield(cheap,'scr_struct') && isfield(cheap.scr_struct,'Ybus')
    auth.topology_payload = cheap.scr_struct.Ybus;
end
evidence = struct();
evidence.sg_off_configurations = sg_off.configurations;
evidence.sg_on_configurations = sg_on.configurations;
end

% =====================================================================
% Cache (keyed by state validity; a mismatch is a cold search)
% =====================================================================
function cache = resolve_cache(opt, sv_fp)
cache = struct('enabled', false, 'fp', sv_fp, ...
    'entries', struct('key', {}, 'cert', {}), 'invalidated', false);
if isfield(opt, 'cache') && isstruct(opt.cache) && isscalar(opt.cache) && ...
        isfield(opt.cache, 'state_validity_fingerprint')
    cache.enabled = true;
    if strcmp(opt.cache.state_validity_fingerprint, sv_fp)
        if isfield(opt.cache, 'entries') && ~isempty(opt.cache.entries)
            cache.entries = opt.cache.entries;
        end
    else
        cache.invalidated = true;
    end
end
end

function cert = cache_lookup(cache, sv_fp, key, cert_opt)
cert = [];
if ~cache.enabled || ~strcmp(cache.fp, sv_fp)
    return;
end
for i = 1:numel(cache.entries)
    if strcmp(cache.entries(i).key, key) && is_certified(cache.entries(i).cert, cert_opt)
        cert = cache.entries(i).cert;
        return;
    end
end
end

function cache = cache_store(cache, key, cert)
% Store only CERTIFIED candidates. Accumulation always happens so a caller may
% persist table.search_cache; the enabled flag only gates REUSE (lookup).
if isfield(cert, 'feasible') && ~isempty(cert.feasible) && logical(cert.feasible)
else
    return;
end
for i = 1:numel(cache.entries)
    if strcmp(cache.entries(i).key, key)
        cache.entries(i).cert = cert;
        return;
    end
end
cache.entries(end+1) = struct('key', key, 'cert', cert);
end

% =====================================================================
% Certificate evidence gaps (what the evaluator does NOT re-surface)
% =====================================================================
function gaps = certificate_evidence_gaps(cert_opt, cheap)
% The trusted evaluator ENFORCES current/P-Q limits and reference-P limits
% internally (a violating equilibrium is rejected), so it is a certificate
% authority for them. It does NOT re-surface those fields, nor DC reserve or a
% synchronism margin. Record exactly which were not surfaced.
gaps = {};
gaps{end+1} = 'current_pq_limits(exposed_field)';
gaps{end+1} = 'dc_reserve_mw(exposed_field)';
gaps{end+1} = 'synchronism_margin(exposed_field)';
if cert_opt.require_physical_evidence
    gaps{end+1} = 'REQUIRED: absence of the above yields INCONCLUSIVE';
end
if ~isfield(cheap, 'scr_available') || ~logical(cheap.scr_available)
    gaps{end+1} = 'scr_metrics(unavailable)';
end
end

% =====================================================================
% Islands summary
% =====================================================================
function [islands, count, ids] = build_islands_summary(case_data)
islands = struct('island_id', {}, 'bus_positions', {}, 'bus_ids', {}, ...
    'energized', {}, 'has_online_vf_source', {}, 'has_load', {}, 'has_shunt', {});
count = 0; ids = [];
if ~isfield(case_data, 'mpc') || ~isfield(case_data.mpc, 'bus') || ...
        ~isfield(case_data.mpc, 'branch')
    return;
end
try
    Y = canonical_ybus_from_mpc(case_data.mpc);
    islands = stability.island_components(Y, case_data.mpc);
    mask = [islands.energized];
    count = sum(mask);
    ids = [islands(mask).island_id];
catch
end
end

function Y = canonical_ybus_from_mpc(mpc)
bus = mpc.bus; br = mpc.branch; nb = size(bus, 1); Y = zeros(nb, nb);
for k = 1:size(br, 1)
    if size(br, 2) >= 11 && br(k, 11) == 0, continue; end
    i = find(bus(:, 1) == br(k, 1), 1);
    j = find(bus(:, 1) == br(k, 2), 1);
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

% =====================================================================
% Small utilities
% =====================================================================
function [ids, modes, online, rt] = committed_arrays(resources, scenario)
nr = numel(resources);
ids = arrayfun(@(r) char(r.resource_id), resources, 'UniformOutput', false);
modes = arrayfun(@(r) char(getfield_or(r, 'initial_mode', 'gfl')), resources, ...
    'UniformOutput', false);
online = logical(arrayfun(@(r) getfield_or(r, 'initial_online', false), resources));
rt = cell(1, nr);
for k = 1:nr
    rt{k} = lower(char(getfield_or(resources(k), 'resource_type', 'ibr')));
end
if isfield(scenario, 'config') && isstruct(scenario.config) && ...
        isfield(scenario.config, 'resource_ids') && ...
        numel(scenario.config.resource_ids) == nr && ...
        all(strcmp(reshape(scenario.config.resource_ids, 1, []), reshape(ids, 1, [])))
    if isfield(scenario.config, 'mode') && numel(scenario.config.mode) == nr
        modes = reshape(cellstr(string(scenario.config.mode)), 1, []);
    elseif isfield(scenario.config, 'modes') && numel(scenario.config.modes) == nr
        modes = reshape(cellstr(string(scenario.config.modes)), 1, []);
    end
    if isfield(scenario.config, 'online') && numel(scenario.config.online) == nr
        online = reshape(logical(scenario.config.online), 1, []);
    end
end
modes = reshape(modes, 1, []);
end

function eligible = eligible_gfm_indices(resources)
nr = numel(resources);
eligible = [];
for k = 1:nr
    r = resources(k);
    if ~isfield(r, 'initial_online') || ~logical(r.initial_online), continue; end
    rt = 'ibr';
    if isfield(r, 'resource_type'), rt = lower(char(r.resource_type)); end
    if ~strcmp(rt, 'ibr'), continue; end
    if ~isfield(r, 'can_switch_mode') || ~logical(r.can_switch_mode), continue; end
    sup = {};
    if isfield(r, 'capabilities') && isstruct(r.capabilities) && ...
            isfield(r.capabilities, 'supported_modes')
        sup = cellstr(string(r.capabilities.supported_modes));
    elseif isfield(r, 'supported_modes')
        sup = cellstr(string(r.supported_modes));
    end
    if ~(any(strcmpi(sup, 'gfl')) && any(strcmpi(sup, 'gfm'))), continue; end
    eligible(end+1) = k; %#ok<AGROW>
end
end

function key = candidate_key(c)
sel = c.selected_gfm_indices;
if isempty(sel)
    s = 'none';
else
    s = strjoin(cellstr(string(sort(sel))), '-');
end
key = sprintf('n%d_ref%d|%s', numel(sel), ...
    getfield_or(c, 'reference_resource_index', 0), s);
end

function b = any_flag(arr, f)
b = false;
for i = 1:numel(arr)
    if isfield(arr(i), f) && ~isempty(arr(i).(f)) && logical(arr(i).(f))
        b = true;
        return;
    end
end
end

function v = getfield_vec(arr, f, dflt)
n = numel(arr); v = repmat(dflt, 1, n);
for i = 1:n
    if isfield(arr(i), f) && ~isempty(arr(i).(f))
        v(i) = arr(i).(f);
    end
end
end

function v = getfield_or(s, f, dflt)
if isstruct(s) && isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = dflt;
end
end

function gamma_req = resolve_gamma_req(scenario, opt)
if isfield(opt, 'gamma_req') && ~isempty(opt.gamma_req)
    gamma_req = opt.gamma_req;
elseif isfield(scenario, 'selector') && isstruct(scenario.selector) && ...
        isfield(scenario.selector, 'gamma_req_rad_per_s') && ...
        ~isempty(scenario.selector.gamma_req_rad_per_s)
    gamma_req = scenario.selector.gamma_req_rad_per_s;
elseif isfield(scenario, 'selector') && isstruct(scenario.selector) && ...
        isfield(scenario.selector, 'gamma_req') && ~isempty(scenario.selector.gamma_req)
    gamma_req = scenario.selector.gamma_req;
else
    gamma_req = 0.1;
end
if ~isscalar(gamma_req) || ~isfinite(gamma_req) || gamma_req < 0
    error('stability:ibr_lazy_search:badGammaReq', ...
        'gamma_req must be a finite nonnegative scalar.');
end
end

function [idx, ambiguous] = resolve_reference_owner(scenario)
% Resolve a designated SINGLE-island reference owner from the scenario / commit
% evidence carried by the caller. Canonical multi-island fields are checked
% first (see +stability/reference_owner_schema.m), then the commit-path scalar
% aliases. Returns ambiguous=true when the evidence designates MORE THAN ONE
% owner (multi-island), which single-island scope cannot disambiguate -> the
% caller must fail closed rather than silently choose the first.
idx = [];
ambiguous = false;
if ~isstruct(scenario)
    return;
end
scopes = {scenario};
for s = {'reference_policy', 'committed_selection', 'config'}
    if isfield(scenario, s{1}) && isstruct(scenario.(s{1}))
        scopes{end + 1} = scenario.(s{1}); %#ok<AGROW>
    end
end
fields = {'reference_owner_indices', 'gfm_reference_resource_indices', ...
    'reference_resource_index'};
for k = 1:numel(scopes)
    sc = scopes{k};
    for j = 1:numel(fields)
        fld = fields{j};
        if isfield(sc, fld) && ~isempty(sc.(fld))
            v = sc.(fld)(:).';
            if numel(v) > 1
                ambiguous = true;
                return;
            end
            idx = v;
            return;
        end
    end
end
end

function budget = resolve_budget(opt)
budget = struct('max_full_evaluations', 32, 'max_generated', Inf, ...
    'stop_on_first_certified', false);
if isfield(opt, 'budget') && isstruct(opt.budget)
    f = fieldnames(opt.budget);
    for k = 1:numel(f)
        budget.(f{k}) = opt.budget.(f{k});
    end
end
if ~isscalar(budget.max_full_evaluations) || ~isfinite(budget.max_full_evaluations) || ...
        budget.max_full_evaluations < 0 || budget.max_full_evaluations ~= fix(budget.max_full_evaluations)
    error('stability:ibr_lazy_search:badBudget', ...
        'budget.max_full_evaluations must be a nonnegative finite integer.');
end
end

function budget = merge_context_budget(budget, opt, prefix)
if isfield(opt, 'budget') && isstruct(opt.budget) && isfield(opt.budget, prefix) && ...
        isstruct(opt.budget.(prefix))
    f = fieldnames(opt.budget.(prefix));
    for k = 1:numel(f)
        budget.(f{k}) = opt.budget.(prefix).(f{k});
    end
end
end

function cert_opt = resolve_cert_opt(opt)
cert_opt = struct('trust_evaluator', true, 'require_physical_evidence', false, ...
    'require_dc_reserve', false, 'require_state', false);
if isfield(opt, 'candidate_evaluator') && ~isempty(opt.candidate_evaluator)
    cert_opt.trust_evaluator = false;   % an injected evaluator cannot certify
end
if isfield(opt, 'certificate') && isstruct(opt.certificate)
    f = fieldnames(opt.certificate);
    for k = 1:numel(f)
        cert_opt.(f{k}) = opt.certificate.(f{k});
    end
end
end

function res = blank_context(prefix, sg_online)
res = struct('context', prefix, 'sg_online', sg_online, ...
    'eligible_gfm_indices', [], 'counts', [], ...
    'configurations', repmat(blank_candidate(), 0, 1), ...
    'failed_configs', repmat(blank_candidate(), 0, 1), ...
    'selected_config', blank_candidate(), 'selected_gfm_indices', [], ...
    'best_ranked_config', blank_candidate(), 'best_ranked_gfm_indices', [], ...
    'best_ranked_objective_rank', [], ...
    'reference_resource_index', [], 'n_gfm_required', [], ...
    'structural_feasible', true, 'topology_evaluated', false, ...
    'scr_evaluated', false, 'equilibrium_evaluated', false, 'sssa_evaluated', false, ...
    'margin', NaN, 'omega', NaN, 'physical_kcl_norm', Inf, 'ready_to_commit', false, ...
    'selection_status', 'UNINITIALIZED', 'failure_id', '', 'selection_reason', '', ...
    'feasibility_log', {{}}, 'n_generated', 0, 'n_screened_infeasible', 0, ...
    'n_screened_unknown', 0, 'n_evaluated', 0, 'n_cached', 0, ...
    'n_certified', 0, 'n_definitive_infeasible', 0, 'n_unknown_evaluated', 0, ...
    'budget_exhausted', false, 'universe_complete', false, ...
    'global_optimality_claimed', false);
end

function c = blank_candidate()
c = struct('resource_ids', {{}}, 'resource_type', {{}}, 'modes', {{}}, ...
    'online', [], 'selected_gfm_indices', [], 'n_gfm_required', [], ...
    'reference_resource_index', [], 'structural_feasible', false, ...
    'topology_evaluated', false, 'scr_evaluated', false, 'scr_pass', [], ...
    'equilibrium_evaluated', false, 'sssa_evaluated', false, 'sssa_pass', [], ...
    'margin', NaN, 'omega', NaN, 'physical_kcl_norm', Inf, 'eigenvalues', [], ...
    'physical_eigenvalues', [], 'raw_omega', NaN, 'physical_reduction_method', '', ...
    'active_bound_constraint_count', 0, 'coordinate_mode_count', 0, 'gy_rcond', NaN, ...
    'fd_eps_values', [], 'fd_omegas', [], 'fd_stable_classification', [], ...
    'fd_classification_consistent', false, 'fd_robust_margin_pass', false, ...
    'fd_zeta_worsts', [], 'zeta_min', NaN, 'zeta_worst', NaN, 'zeta_margin', NaN, ...
    'ready_to_commit', false, 'feasible', false, 'reason', '', 'failure_id', '', ...
    'n_mode_changes', Inf, 'tie_break', '', 'ordering_key', '', 'full_ordering_key', '', ...
    'eq_x0', [], 'eq_y0', [], 'eq_u_eq', [], 'eq_context', struct(), ...
    'eq_active_indices', [], 'eq_rcond', NaN, 'eq_partition', struct(), ...
    'reduction_method', '', 'sssa_f0_norm', NaN, 'sssa_g0_norm', NaN, 'full_kcl', false);
end

function arr = cellstruct_to_structarray(cells)
% Build a struct array over the UNION of fields observed in a cell array of
% candidate structs. The evaluator may SURFACE additional fields (e.g. an
% evidence-record array); a plain struct-array append requires identical field
% sets, so we materialise the array once over the union. A field missing from a
% given cell takes the reference value seen in the first cell that carries it
% (type-compatible), so the array stays assignment-compatible.
if isempty(cells)
    arr = repmat(blank_candidate(), 0, 1);
    return;
end
fields = {};
for k = 1:numel(cells)
    g = fieldnames(cells{k});
    for j = 1:numel(g)
        if ~any(strcmp(fields, g{j}))
            fields{end+1} = g{j}; %#ok<AGROW>
        end
    end
end
refval = struct();
for j = 1:numel(fields)
    refval.(fields{j}) = [];
    for k = 1:numel(cells)
        if isfield(cells{k}, fields{j})
            refval.(fields{j}) = cells{k}.(fields{j});
            break;
        end
    end
end
arr = repmat(orderfields(refval, fields), numel(cells), 1);
for k = 1:numel(cells)
    ck = cells{k};
    for j = 1:numel(fields)
        if ~isfield(ck, fields{j})
            ck.(fields{j}) = refval.(fields{j});
        end
    end
    arr(k) = orderfields(ck, fields);
end
end

function table = inconclusive_table(gamma_req, budget, sv_fp, reason)
table = struct();
table.schema = 'ibr_lazy_search/1.0';
table.gamma_req = gamma_req;
table.build_islands = struct('island_id', {}, 'bus_positions', {}, 'bus_ids', {}, ...
    'energized', {}, 'has_online_vf_source', {}, 'has_load', {}, 'has_shunt', {});
table.energized_island_count = 0;
table.reference_island_ids = [];
table.budget = budget;
table.budget_per_context = true;
table.lazy_gfm_search = true;
table.state_validity_fingerprint = sv_fp;
table.state_validity = struct();
table.built_at = 'lazy_on_demand';
table.sg_off = inconclusive_context('sg_off', false, reason);
table.sg_on = inconclusive_context('sg_on', true, reason);
table.selector_table_fingerprint = hash_string(sprintf('lazy_inconclusive|%s', sv_fp));
table.selector_input_fingerprint = sv_fp;
table.candidate_evidence_fingerprint = 'none';
table.selector_schema_version = 'ibr_lazy_search_v1';
table.search_fingerprint = hash_string(sprintf('lazy_inconclusive|%s', sv_fp));
table.cache_invalidated = false;
table.search_cache = struct();
end

function c = inconclusive_context(prefix, sg_online, reason)
c = blank_context(prefix, sg_online);
c.selection_status = 'INCONCLUSIVE';
c.failure_id = 'stability:ibr_lazy_search:inconclusiveEvidence';
c.selection_reason = reason;
end

function out = struct_to_str(st)
if ~isstruct(st) || isempty(st)
    out = '';
    return;
end
fns = sort(fieldnames(st));
parts = {};
for k = 1:numel(fns)
    v = st.(fns{k});
    if isnumeric(v)
        if isreal(v)
            parts{end+1} = sprintf('%s=%s', fns{k}, mat2str(v(:)')); %#ok<AGROW>
        else
            parts{end+1} = sprintf('%s=(%s,%s)', fns{k}, mat2str(real(v(:)')), ...
                mat2str(imag(v(:)'))); %#ok<AGROW>
        end
    elseif ischar(v)
        parts{end+1} = sprintf('%s=%s', fns{k}, v); %#ok<AGROW>
    elseif isstring(v)
        parts{end+1} = sprintf('%s=%s', fns{k}, char(strjoin(v, '/'))); %#ok<AGROW>
    elseif islogical(v)
        parts{end+1} = sprintf('%s=%s', fns{k}, mat2str(v(:)')); %#ok<AGROW>
    elseif iscell(v)
        parts{end+1} = sprintf('%s=[%s]', fns{k}, cell_str(v)); %#ok<AGROW>
    elseif isstruct(v) && isscalar(v)
        parts{end+1} = sprintf('%s={%s}', fns{k}, struct_to_str(v)); %#ok<AGROW>
    else
        parts{end+1} = sprintf('%s=?', fns{k}); %#ok<AGROW>
    end
end
out = strjoin(parts, ',');
end

function s = cell_str(c)
elems = cell(1, numel(c));
for i = 1:numel(c)
    v = c{i};
    if isnumeric(v)
        elems{i} = mat2str(v(:)');
    elseif ischar(v)
        elems{i} = v;
    elseif isstring(v)
        elems{i} = char(v);
    elseif islogical(v)
        elems{i} = mat2str(v);
    else
        elems{i} = '?';
    end
end
s = strjoin(elems, '/');
end

function h = hash_string(s)
h = uint32(2166136261);
mask32 = uint64(4294967295);
for k = 1:numel(s)
    h = bitxor(h, uint32(double(s(k))));
    product = uint64(h) * uint64(16777619);
    h = uint32(bitand(product, mask32));
end
h = sprintf('%08x', h);
end
