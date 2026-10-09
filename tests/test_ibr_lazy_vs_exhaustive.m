function tests = test_ibr_lazy_vs_exhaustive()
%TEST_IBR_LAZY_VS_EXHAUSTIVE  Lazy GFM search vs exhaustive, and fail-closed contracts.
%   Exercises the opt-in lazy selector search (stability.ibr_selector_search_lazy
%   + stability.ibr_lazy_priority + stability.ibr_candidate_screen) against the
%   SAME deterministic objective the exhaustive path uses. Small universes
%   (<= 4 eligible IBRs) are compared exhaustively; the 5-IBR 32-set is checked
%   against a precomputed OFFLINE ORACLE (validation only, no live 5-IBR run).
%
%   The candidate evaluator is an injected SYNTHETIC stand-in used ONLY to test
%   the search CONTROL LOGIC (lazy generation, cheap screen, budget, ranking,
%   fail-closed statuses, cache fingerprinting). A stand-in CANNOT mint a
%   certificate unless the caller explicitly opts in
%   (opt.certificate.trust_evaluator == true). The physical full-evidence
%   certificate path (real stability.ibr_candidate_evaluate) is exercised by the
%   existing test_ieee14_ibr_sg_on_integration suite.
%
%   Source: opt-in lazy GFM search mission (WS-lazy).
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
original_path = path;
testCase.addTeardown(@() path(original_path));
addpath(root, '-begin');
pf_init_paths();
end

% =========================================================================
% 1. Lazy generator: complete + lexicographic + monotone + no 2^N array
% =========================================================================
function test_generator_lazy_complete_lexicographic(testCase)
eligible = [3 5 7 9];
counts = 1:4;
ctx = struct('eligible', eligible, 'counts', counts);
got = {};
cursor = []; done = false; guard = 0;
while ~done
    [spec, cursor, done] = stability.ibr_lazy_priority(cursor, ctx);
    if done, break; end
    got{end+1} = spec.selected_gfm_indices; %#ok<AGROW>
    guard = guard + 1;
    testCase.verifyLessThan(guard, 100);
end
testCase.verifyEqual(numel(got), 15);
expected = {};
for k = 1:4
    C = nchoosek(eligible, k);
    for r = 1:size(C, 1)
        expected{end+1} = C(r, :); %#ok<AGROW>
    end
end
for i = 1:numel(expected)
    testCase.verifyEqual(got{i}, expected{i});
end
sizes = cellfun(@numel, got);
testCase.verifyTrue(all(diff(sizes) >= 0));
end

function test_generator_empty_all_gfl(testCase)
ctx = struct('eligible', [2 4], 'counts', 0);
[s1, ~, d1] = stability.ibr_lazy_priority([], ctx);
testCase.verifyFalse(d1);
testCase.verifyEmpty(s1.selected_gfm_indices);
testCase.verifyEqual(s1.n_gfm_required, 0);
[~, ~, d2] = stability.ibr_lazy_priority(struct('ctx', ctx, 'slot', 2, ...
    'ordinal', 0, 'flat', 1, 'finished', false, 'N', 2), ctx);
testCase.verifyTrue(d2);
end

% =========================================================================
% 2. Cheap screen: three-valued, applicability-aware, never certifies
% =========================================================================
function test_screen_unknown_when_scr_unavailable(testCase)
resources = make_resources();
spec = struct('selected_gfm_indices', [2], 'n_gfm_required', 1);
cheap = struct('is_singular', false, 'topology_ok', true, 'scr_available', false);
s = stability.ibr_candidate_screen(spec, resources, cheap, struct());
testCase.verifyEqual(s.verdict, 'UNKNOWN');
testCase.verifyFalse(s.certifies);
testCase.verifyFalse(s.necessary);
end

function test_screen_infeasible_on_applicable_scr_gate(testCase)
resources = make_resources();
spec = struct('selected_gfm_indices', [2], 'n_gfm_required', 1);
per = make_scr_per(resources, true);   % threshold_applicable = true
per(find([per.resource_index] == 4)).pass = false;
per(find([per.resource_index] == 4)).failure_id = 'test:scrWeak';
cheap = struct('is_singular', false, 'topology_ok', true, 'scr_available', true, ...
    'source_aware', false, 'scr_per_resource', per);
s = stability.ibr_candidate_screen(spec, resources, cheap, struct());
testCase.verifyEqual(s.verdict, 'INFEASIBLE');
testCase.verifyTrue(s.necessary);
testCase.verifyEqual(s.stage, 'scr');
testCase.verifyEqual(s.failure_id, 'test:scrWeak');
testCase.verifyFalse(s.certifies);
end

function test_screen_does_not_borrow_scr_when_not_applicable(testCase)
% eecon49_dual / source-aware: threshold_applicable=false. A low SCR is a
% DIAGNOSTIC; it must NOT become a hard rejection.
resources = make_resources();
spec = struct('selected_gfm_indices', [2], 'n_gfm_required', 1);
per = make_scr_per(resources, false);   % threshold_applicable = false
per(find([per.resource_index] == 4)).pass = false;
per(find([per.resource_index] == 4)).reason = 'SCR 1.1 measured';
cheap = struct('is_singular', false, 'topology_ok', true, 'scr_available', true, ...
    'source_aware', true, 'scr_per_resource', per);
s = stability.ibr_candidate_screen(spec, resources, cheap, struct());
testCase.verifyEqual(s.verdict, 'UNKNOWN');   % NOT infeasible
testCase.verifyFalse(s.necessary);
testCase.verifyFalse(s.certifies);
end

function test_screen_no_source_island_is_hard_and_distinct(testCase)
resources = make_resources();
spec = struct('selected_gfm_indices', [2], 'n_gfm_required', 1);
cheap = struct('is_singular', false, 'topology_ok', true, 'scr_available', true, ...
    'source_aware', true, 'no_source_island', true, ...
    'scr_per_resource', make_scr_per(resources, false));
s = stability.ibr_candidate_screen(spec, resources, cheap, struct('sg_online', false));
testCase.verifyEqual(s.verdict, 'INFEASIBLE');
testCase.verifyEqual(s.stage, 'source');
testCase.verifyFalse(s.certifies);
end

function test_screen_per_resource_source_absent_is_not_hard(testCase)
% A per-resource source_available==false on a selected GFM must NOT be a hard
% rejection: a GFM forms its own voltage, and the source-aware metric is built
% around synchronous sources, so a GFM PCC legitimately shows no modelled
% source. Rejecting on it would be a FALSE constraint that drops every valid
% GFM selection. Guards the source-absence false-constraint regression.
resources = make_resources();
spec = struct('selected_gfm_indices', [2], 'n_gfm_required', 1);
per = make_scr_per(resources, false);
per(find([per.resource_index] == 2)).source_available = false;
per(find([per.resource_index] == 2)).status = 'no_source_island';
cheap = struct('is_singular', false, 'topology_ok', true, 'scr_available', true, ...
    'source_aware', true, 'scr_per_resource', per);
s = stability.ibr_candidate_screen(spec, resources, cheap, struct('sg_online', false));
testCase.verifyNotEqual(s.verdict, 'INFEASIBLE');
testCase.verifyEqual(s.stage, '');
end

function test_screen_missing_scr_entry_is_unknown_not_infeasible(testCase)
resources = make_resources();
spec = struct('selected_gfm_indices', [2], 'n_gfm_required', 1);
per = make_scr_per(resources, true);
per(find([per.resource_index] == 4)) = [];   % drop index 4 evidence
cheap = struct('is_singular', false, 'topology_ok', true, 'scr_available', true, ...
    'source_aware', false, 'scr_per_resource', per);
s = stability.ibr_candidate_screen(spec, resources, cheap, struct());
testCase.verifyEqual(s.verdict, 'UNKNOWN');   % missing evidence != infeasible
end

function test_screen_ignores_reserve_surrogates(testCase)
resources = make_resources();
spec = struct('selected_gfm_indices', [2], 'n_gfm_required', 1);
cheap = struct('is_singular', false, 'topology_ok', true, 'scr_available', false, ...
    'dc_discriminant', -3.7, 'apparent_margin', -0.9, 'reserve_MW', 0, 'margin', -2);
s = stability.ibr_candidate_screen(spec, resources, cheap, struct());
testCase.verifyEqual(s.verdict, 'UNKNOWN');
testCase.verifyFalse(s.necessary);
testCase.verifyTrue(any(strcmp(s.ignored_surrogates, 'dc_discriminant')));
testCase.verifyTrue(any(strcmp(s.ignored_surrogates, 'apparent_margin')));
end

function test_screen_infeasible_on_singular_topology(testCase)
resources = make_resources();
spec = struct('selected_gfm_indices', [2], 'n_gfm_required', 1);
cheap = struct('is_singular', true, 'topology_ok', false, 'scr_available', false);
s = stability.ibr_candidate_screen(spec, resources, cheap, struct());
testCase.verifyEqual(s.verdict, 'INFEASIBLE');
testCase.verifyEqual(s.stage, 'topology');
testCase.verifyFalse(s.certifies);
end

% =========================================================================
% 3. A stand-in evaluator CANNOT mint a certificate by default
% =========================================================================
function test_injected_evaluator_cannot_certify(testCase)
resources = make_resources();
case_data = make_case();
opt = base_opt();
opt.budget = struct('max_full_evaluations', 1000, 'max_generated', Inf, ...
    'stop_on_first_certified', false);
opt.candidate_evaluator = @synth_eval_full;   % full evidence, feasible=true
opt.cheap_provider = @always_unknown_cheap;
table = stability.ibr_selector_search_lazy(case_data, resources, struct(), opt);
ctx = table.sg_off;
testCase.verifyFalse(ctx.ready_to_commit);
testCase.verifyNotEqual(ctx.selection_status, 'CERTIFIED');
testCase.verifyEqual(ctx.n_certified, 0);
testCase.verifyFalse(any([ctx.configurations.ready_to_commit]));
% the stand-in's own ready_to_commit field is NOT accepted as a certificate:
% the SEARCH picks no committable subset.
testCase.verifyEmpty(ctx.selected_gfm_indices);
end

% =========================================================================
% 4. Trusted opt-in + full evidence certifies; lazy == exhaustive
% =========================================================================
function test_trusted_optin_certifies_and_matches_exhaustive(testCase)
resources = make_resources();
case_data = make_case();
counts = 1:4;
opt = base_opt();
opt.budget = struct('max_full_evaluations', 1000, 'max_generated', Inf, ...
    'stop_on_first_certified', false);
opt.candidate_evaluator = @synth_eval_full;
opt.cheap_provider = @always_unknown_cheap;
opt.certificate = struct('trust_evaluator', true);   % CONTROL-BRANCH opt-in

table = stability.ibr_selector_search_lazy(case_data, resources, struct(), opt);
ctx = table.sg_off;
testCase.verifyEqual(ctx.selection_status, 'CERTIFIED');
testCase.verifyTrue(ctx.ready_to_commit);
testCase.verifyTrue(ctx.universe_complete);
testCase.verifyTrue(ctx.global_optimality_claimed);

ref = reference_exhaustive(resources, counts, @synth_eval_full);
% selected (certified) and best-ranked must both equal the exhaustive winner
testCase.verifyEqual(ctx.selected_gfm_indices, ref.selected_gfm_indices);
testCase.verifyEqual(ctx.best_ranked_gfm_indices, ref.selected_gfm_indices);
% missed feasible == 0
testCase.verifyEqual(count_feasible(ctx.configurations), count_feasible(ref.configurations));
% unsafe approvals == 0
testCase.verifyEqual(count_unsafe(ctx.configurations), 0);
end

% =========================================================================
% 5. Budget exhaustion -> HOLD (fail closed)
% =========================================================================
function test_budget_hold_fail_closed(testCase)
resources = make_resources();
case_data = make_case();
opt = base_opt();
opt.budget = struct('max_full_evaluations', 1, 'max_generated', Inf, ...
    'stop_on_first_certified', false);
opt.candidate_evaluator = @synth_eval_none;   % definitively infeasible, no cert
opt.cheap_provider = @always_unknown_cheap;
table = stability.ibr_selector_search_lazy(case_data, resources, struct(), opt);
ctx = table.sg_off;
testCase.verifyEqual(ctx.selection_status, 'HOLD');
testCase.verifyEqual(ctx.failure_id, 'stability:ibr_lazy_search:budgetHold');
testCase.verifyFalse(ctx.ready_to_commit);
testCase.verifyFalse(ctx.universe_complete);
testCase.verifyFalse(ctx.global_optimality_claimed);
testCase.verifyEqual(ctx.n_evaluated, 1);
end

% =========================================================================
% 6. Structural-only / unknown evidence -> INCONCLUSIVE (not NO_FEASIBLE)
% =========================================================================
function test_structural_only_is_inconclusive_not_no_feasible(testCase)
resources = make_resources();
case_data = make_case();
opt = base_opt();
opt.budget = struct('max_full_evaluations', 1000, 'max_generated', Inf, ...
    'stop_on_first_certified', false);
opt.candidate_evaluator = @synth_eval_structural_only;
opt.cheap_provider = @always_unknown_cheap;
table = stability.ibr_selector_search_lazy(case_data, resources, struct(), opt);
ctx = table.sg_off;
testCase.verifyEqual(ctx.selection_status, 'INCONCLUSIVE');
testCase.verifyEqual(ctx.failure_id, 'stability:ibr_lazy_search:inconclusiveEvidence');
testCase.verifyFalse(ctx.ready_to_commit);
testCase.verifyTrue(ctx.universe_complete);
testCase.verifyEqual(ctx.n_certified, 0);
end

function test_all_definitively_infeasible_gives_no_feasible(testCase)
resources = make_resources();
case_data = make_case();
opt = base_opt();
opt.budget = struct('max_full_evaluations', 1000, 'max_generated', Inf, ...
    'stop_on_first_certified', false);
opt.candidate_evaluator = @synth_eval_none;
opt.cheap_provider = @always_unknown_cheap;
table = stability.ibr_selector_search_lazy(case_data, resources, struct(), opt);
ctx = table.sg_off;
testCase.verifyEqual(ctx.selection_status, 'NO_FEASIBLE_CANDIDATE');
testCase.verifyEqual(ctx.n_unknown_evaluated, 0);
testCase.verifyFalse(ctx.ready_to_commit);
end

% =========================================================================
% 7. Cache keyed by state-validity fingerprint; mismatch -> invalidation
% =========================================================================
function test_cache_fingerprint_invalidation(testCase)
resources = make_resources();
case_data = make_case();
opt = base_opt();
opt.budget = struct('max_full_evaluations', 1000, 'max_generated', Inf, ...
    'stop_on_first_certified', false);
opt.candidate_evaluator = @synth_eval_full;
opt.cheap_provider = @always_unknown_cheap;
opt.certificate = struct('trust_evaluator', true);

t1 = stability.ibr_selector_search_lazy(case_data, resources, struct(), opt);
testCase.verifyGreaterThanOrEqual(numel(t1.search_cache.entries), 1);
fp = t1.state_validity_fingerprint;

opt.cache = struct('state_validity_fingerprint', fp, 'entries', t1.search_cache.entries);
t2 = stability.ibr_selector_search_lazy(case_data, resources, struct(), opt);
testCase.verifyFalse(t2.cache_invalidated);
testCase.verifyGreaterThan(t2.sg_off.n_cached, 0);
testCase.verifyEqual(t2.sg_off.selected_gfm_indices, t1.sg_off.selected_gfm_indices);

opt.cache = struct('state_validity_fingerprint', 'deadbeef00', 'entries', t1.search_cache.entries);
t3 = stability.ibr_selector_search_lazy(case_data, resources, struct(), opt);
testCase.verifyTrue(t3.cache_invalidated);
testCase.verifyEqual(t3.sg_off.n_cached, 0);
end

function test_state_key_changes_with_dispatch(testCase)
% A dispatch change must change the state-validity key (no constant fallback).
resources = make_resources();
case_data = make_case();
o1 = base_opt();
o1.dispatch = struct('a', 1);
o1.budget = struct('max_full_evaluations', 1, 'max_generated', 1, ...
    'stop_on_first_certified', false);
o1.candidate_evaluator = @synth_eval_none;
o1.cheap_provider = @always_unknown_cheap;
t1 = stability.ibr_selector_search_lazy(case_data, resources, struct(), o1);
o2 = o1; o2.dispatch = struct('a', 2);
t2 = stability.ibr_selector_search_lazy(case_data, resources, struct(), o2);
testCase.verifyNotEqual(t1.state_validity_fingerprint, t2.state_validity_fingerprint);
end

% =========================================================================
% 8. Opt-in guard + missing evidence -> INCONCLUSIVE
% =========================================================================
function test_requires_opt_in_flag(testCase)
resources = make_resources();
case_data = make_case();
opt = base_opt();
opt = rmfield(opt, 'lazy_gfm_search');
testCase.verifyError(@() stability.ibr_selector_search_lazy( ...
    case_data, resources, struct(), opt), 'stability:ibr_lazy_search:notOptedIn');
end

function test_missing_topology_is_inconclusive(testCase)
resources = make_resources();
case_data = struct('mpc', struct('baseMVA', 100));
opt = base_opt();
table = stability.ibr_selector_search_lazy(case_data, resources, struct(), opt);
testCase.verifyEqual(table.sg_off.selection_status, 'INCONCLUSIVE');
testCase.verifyEqual(table.sg_off.failure_id, ...
    'stability:ibr_lazy_search:inconclusiveEvidence');
testCase.verifyFalse(table.sg_off.ready_to_commit);
end

% =========================================================================
% 9. 5-IBR 32-set: OFFLINE ORACLE (validation only, no live run)
% =========================================================================
function test_five_ibr_offline_oracle(testCase)
eligible = [1 2 3 4 5];
counts = 0:5;
ctx = struct('eligible', eligible, 'counts', counts);
seen = zeros(1, 0); cursor = []; done = false; n = 0;
while ~done
    [spec, cursor, done] = stability.ibr_lazy_priority(cursor, ctx);
    if done, break; end
    n = n + 1;
    seen(n) = numel(spec.selected_gfm_indices); %#ok<AGROW>
end
testCase.verifyEqual(n, 32);
oracle_sizes = [0, ones(1,5), 2*ones(1,10), 3*ones(1,10), 4*ones(1,5), 5];
expected_sizes = zeros(1, 0);
for k = counts
    expected_sizes = [expected_sizes, k*ones(1, nchoosek(5, k))]; %#ok<AGROW>
end
testCase.verifyEqual(seen, expected_sizes);
testCase.verifyEqual(oracle_sizes, expected_sizes);
end

% =========================================================================
% 10. Real NE39 5-SG + 5-IBR: multi-SG SG_ON reference-owner resolution
% =========================================================================
function test_ne39_5sg_sg_on_multiowner_resolution(testCase)
% NE39 has FIVE online SGs, not one. The old code required exactly one and
% failed with 'sgReferenceOwner'. The owner must be resolved from evidence and
% verified to be an ONLINE SG; a multi-SG online island must be able to
% certify. Without a designated owner, ambiguity must FAIL CLOSED (never pick
% the first online SG silently).
[resources, case_data] = ne39_inputs();
online_sg = find(arrayfun(@(r) strcmp(lower(char(r.resource_type)), 'sg') && ...
    logical(r.initial_online), resources));
testCase.verifyGreaterThanOrEqual(numel(online_sg), 5);   % really multi-SG

opt = base_opt();
opt.budget = struct('max_full_evaluations', 1000, 'max_generated', Inf, ...
    'stop_on_first_certified', false);
opt.candidate_evaluator = @synth_eval_full;
opt.cheap_provider = @always_unknown_cheap;
opt.certificate = struct('trust_evaluator', true);

% (a) no designated owner -> multi-SG ambiguity fails closed
t0 = stability.ibr_selector_search_lazy(case_data, resources, struct(), opt);
testCase.verifyEqual(t0.sg_on.selection_status, 'INVALID_SG_REFERENCE');
testCase.verifyEqual(t0.sg_on.failure_id, ...
    'stability:ibr_lazy_search:sgReferenceAmbiguous');
testCase.verifyFalse(t0.sg_on.ready_to_commit);

% (b) pinned owner (an online SG) -> multi-SG island certifies
opt_pin = opt;
opt_pin.sg_on = struct('reference_resource_index', online_sg(1));
t1 = stability.ibr_selector_search_lazy(case_data, resources, struct(), opt_pin);
testCase.verifyEqual(t1.sg_on.selection_status, 'CERTIFIED');
testCase.verifyTrue(t1.sg_on.ready_to_commit);
testCase.verifyEqual(t1.sg_on.reference_resource_index, online_sg(1));

% (c) scenario designated owner -> certifies too
scenario_owner = struct('committed_selection', ...
    struct('reference_resource_index', online_sg(end)));
t2 = stability.ibr_selector_search_lazy(case_data, resources, scenario_owner, opt);
testCase.verifyEqual(t2.sg_on.selection_status, 'CERTIFIED');
testCase.verifyEqual(t2.sg_on.reference_resource_index, online_sg(end));

% (d) SG_OFF context must NOT be blocked by the SG count
testCase.verifyNotEqual(t1.sg_off.selection_status, 'INVALID_SG_REFERENCE');
end

function test_ne39_multi_island_owner_ambiguity_fails_closed(testCase)
% A >1-element owner list (multi-island owner set) cannot be disambiguated by
% single-island scope -> fail closed, never silently choose the first.
[resources, case_data] = ne39_inputs();
opt = base_opt();
opt.budget = struct('max_full_evaluations', 1000, 'max_generated', Inf, ...
    'stop_on_first_certified', false);
opt.candidate_evaluator = @synth_eval_full;
opt.cheap_provider = @always_unknown_cheap;
opt.certificate = struct('trust_evaluator', true);
scenario = struct('reference_owner_indices', [1 2]);
t = stability.ibr_selector_search_lazy(case_data, resources, scenario, opt);
testCase.verifyEqual(t.sg_on.selection_status, 'INVALID_SG_REFERENCE');
testCase.verifyEqual(t.sg_on.failure_id, ...
    'stability:ibr_lazy_search:multiIslandOwnerAmbiguous');
testCase.verifyFalse(t.sg_on.ready_to_commit);
end

function test_ne39_sg_on_pinned_non_sg_owner_fails_closed(testCase)
% A pinned SG_ON owner that is NOT an online SG is a caller error -> fail closed.
[resources, case_data] = ne39_inputs();
ibr_idx = find(arrayfun(@(r) strcmp(lower(char(r.resource_type)), 'ibr'), resources), 1);
opt = base_opt();
opt.budget = struct('max_full_evaluations', 100, 'max_generated', Inf, ...
    'stop_on_first_certified', false);
opt.candidate_evaluator = @synth_eval_full;
opt.cheap_provider = @always_unknown_cheap;
opt.certificate = struct('trust_evaluator', true);
opt.sg_on = struct('reference_resource_index', ibr_idx);
t = stability.ibr_selector_search_lazy(case_data, resources, struct(), opt);
testCase.verifyEqual(t.sg_on.selection_status, 'INVALID_SG_REFERENCE');
testCase.verifyEqual(t.sg_on.failure_id, ...
    'stability:ibr_lazy_search:referenceOwnerNotOnlineSg');
end

% =========================================================================
% 11. Physical-evidence RECORD ABI (id/applicable/status/value/provenance)
% =========================================================================
function test_evidence_record_pending_device_surface_cannot_certify(testCase)
resources = make_resources();
case_data = make_case();
recs = struct('id', 'PENDING_DEVICE_SURFACE', 'applicable', true, ...
    'status', 'PENDING', 'value', NaN, 'provenance', 'test');
opt = base_opt();
opt.budget = struct('max_full_evaluations', 1000, 'max_generated', Inf, ...
    'stop_on_first_certified', false);
opt.candidate_evaluator = @(cand, varargin) synth_eval_full_records(cand, recs);
opt.cheap_provider = @always_unknown_cheap;
opt.certificate = struct('trust_evaluator', true);
t = stability.ibr_selector_search_lazy(case_data, resources, struct(), opt);
testCase.verifyNotEqual(t.sg_off.selection_status, 'CERTIFIED');
testCase.verifyFalse(t.sg_off.ready_to_commit);
end

function test_evidence_record_transition_not_applicable_cannot_certify(testCase)
resources = make_resources();
case_data = make_case();
recs = struct('id', 'TRANSITION_DAMPING', 'applicable', false, ...
    'status', 'NOT_APPLICABLE', 'value', NaN, 'provenance', 'test');
opt = base_opt();
opt.budget = struct('max_full_evaluations', 1000, 'max_generated', Inf, ...
    'stop_on_first_certified', false);
opt.candidate_evaluator = @(cand, varargin) synth_eval_full_records(cand, recs);
opt.cheap_provider = @always_unknown_cheap;
opt.certificate = struct('trust_evaluator', true);
t = stability.ibr_selector_search_lazy(case_data, resources, struct(), opt);
testCase.verifyNotEqual(t.sg_off.selection_status, 'CERTIFIED');
end

function test_missing_dc_reserve_disables_raw_ready_rows(testCase)
resources = make_resources();
case_data = make_case();
opt = base_opt();
opt.budget = struct('max_full_evaluations', 1000, 'max_generated', Inf, ...
    'stop_on_first_certified', false);
opt.candidate_evaluator = @synth_eval_limits_without_dc;
opt.cheap_provider = @always_unknown_cheap;
opt.dispatch = struct('ConverterAlpha', 1);
opt.certificate = struct('trust_evaluator', true, ...
    'require_physical_evidence', true, 'require_dc_reserve', true);
t = stability.ibr_selector_search_lazy(case_data, resources, struct(), opt);
testCase.verifyTrue(any([t.sg_off.configurations.feasible]));
testCase.verifyFalse(any([t.sg_off.configurations.ready_to_commit]));
testCase.verifyEqual(t.sg_off.n_certified, 0);
testCase.verifyFalse(t.sg_off.ready_to_commit);
end

function out = synth_eval_limits_without_dc(cand, varargin) %#ok<INUSD>
out = synth_eval_full(cand);
out.within_limits = true;
end

function test_evidence_record_steady_sync_not_applicable_can_certify(testCase)
resources = make_resources();
case_data = make_case();
recs = struct('id', 'SYNCHRONISM_STEADY', 'applicable', false, ...
    'status', 'NOT_APPLICABLE', 'value', NaN, 'provenance', 'test');
opt = base_opt();
opt.budget = struct('max_full_evaluations', 1000, 'max_generated', Inf, ...
    'stop_on_first_certified', false);
opt.candidate_evaluator = @(cand, varargin) synth_eval_full_records(cand, recs);
opt.cheap_provider = @always_unknown_cheap;
opt.certificate = struct('trust_evaluator', true);
t = stability.ibr_selector_search_lazy(case_data, resources, struct(), opt);
testCase.verifyEqual(t.sg_off.selection_status, 'CERTIFIED');
testCase.verifyTrue(t.sg_off.ready_to_commit);
end

% =========================================================================
% Helpers
% =========================================================================
function opt = base_opt()
opt = struct();
opt.lazy_gfm_search = true;
opt.gamma_req = 0.1;
opt.solver_id = 'inhouse_nr';
opt.model_version = 'eecon49_dual';
end

function resources = make_resources()
base = struct('resource_id', '', 'bus_id', 0, 'resource_type', 'sg', ...
    'model_id', 'sg_emf6', 'supported_modes', ["synchronous" "breaker_open"], ...
    'voltage_forming_modes', 'synchronous', 'initial_mode', 'synchronous', ...
    'initial_online', true, 'can_switch_mode', true, 'can_switch_online', true, ...
    'has_current_limiter', false, 'has_frt', false, 'can_black_start', false, ...
    'limits', struct(), 'ratings', struct(), 'dynamic_params', struct(), ...
    'provenance', struct('model', 'test', 'source', 'test', ...
    'classification', 'CASE_DEFINED', 'details', 'lazy test'));
resources = repmat(base, 1, 5);
resources(1).resource_id = 'MachineAlpha';
resources(1).bus_id = 101;
names = {'ConverterAlpha', 'ConverterBeta', 'ConverterGamma', 'ConverterDelta'};
for k = 1:4
    resources(k+1).resource_id = names{k};
    resources(k+1).bus_id = 200 + k;
    resources(k+1).resource_type = 'ibr';
    resources(k+1).model_id = 'eecon49_dual';
    resources(k+1).supported_modes = ["gfl" "gfm" "tripped"];
    resources(k+1).voltage_forming_modes = 'gfm';
    resources(k+1).initial_mode = 'gfl';
    resources(k+1).has_current_limiter = true;
    resources(k+1).has_frt = true;
    resources(k+1).ratings = struct('Mbase', 50);
    resources(k+1).dynamic_params = struct('Xdp', 0.2);
end
end

function per = make_scr_per(resources, applicable)
per = repmat(struct('resource_index', 0, 'pass', true, 'reason', '', ...
    'failure_id', '', 'threshold_applicable', applicable, 'source_available', true, ...
    'status', 'valid'), 0, 1);
for k = 1:numel(resources)
    e = struct('resource_index', k, 'pass', true, 'reason', '', 'failure_id', '', ...
        'threshold_applicable', applicable, 'source_available', true, 'status', 'valid');
    per(end+1) = e; %#ok<AGROW>
end
end

function case_data = make_case()
baseMVA = 100;
bus = [1 3 0 0 0 0 1 1.0 0 230 1 1.1 0.9;
       2 1 0 0 0 0 1 1.0 0 230 1 1.1 0.9];
branch = [1 2 0.01 0.1 0.02 100 100 100 0 0 1 -360 360];
case_data = struct('mpc', struct('baseMVA', baseMVA, 'bus', bus, 'branch', branch));
end

function [resources, case_data] = ne39_inputs()
% Prefer the REAL NE39 5-SG + 5-IBR table (5 online SGs + 5 GFM-capable IBRs)
% when the case files are on the path; otherwise fall back to a structural
% stand-in with the same shape so the multi-SG reference-owner logic is still
% exercised in an isolated worktree. NOTE: exist(...,'file') returns 0 for
% package functions in this environment, so use which() to detect presence.
resources = [];
case_data = [];
if ~isempty(which('cases.scenario_ne39_5sg_5ibr'))
    s = cases.scenario_ne39_5sg_5ibr();
    if isfield(s, 'resources') && numel(s.resources) >= 6
        resources = s.resources;
        case_data = s.case_data;
    end
end
if isempty(resources)
    [resources, case_data] = make_ne39_like();
end
end

function [resources, case_data] = make_ne39_like()
% 5 synchronous generators (SG31/32/35/38/39) + 5 GFM-capable eecon49_dual
% inverters (IBR30/33/34/36/37): the NE39 resource shape without running power
% flow (so it stays cheap and deterministic for the control-logic tests).
base = struct('resource_id', '', 'bus_id', 0, 'resource_type', 'sg', ...
    'model_id', 'sg_classical', 'supported_modes', ["synchronous" "breaker_open"], ...
    'voltage_forming_modes', 'synchronous', 'initial_mode', 'synchronous', ...
    'initial_online', true, 'can_switch_mode', true, 'can_switch_online', true, ...
    'has_current_limiter', false, 'has_frt', false, 'can_black_start', false, ...
    'limits', struct(), 'ratings', struct(), 'dynamic_params', struct(), ...
    'provenance', struct('model', 'test', 'source', 'test', ...
    'classification', 'CASE_DEFINED', 'details', 'ne39-like'));
resources = repmat(base, 1, 10);
sg_ids = {'SG31', 'SG32', 'SG35', 'SG38', 'SG39'};
ibr_ids = {'IBR30', 'IBR33', 'IBR34', 'IBR36', 'IBR37'};
for k = 1:5
    resources(k).resource_id = sg_ids{k};
    resources(k).bus_id = 30 + k;
end
for k = 1:5
    j = 5 + k;
    resources(j).resource_id = ibr_ids{k};
    resources(j).bus_id = 40 + k;
    resources(j).resource_type = 'ibr';
    resources(j).model_id = 'eecon49_dual';
    resources(j).supported_modes = ["gfl" "gfm" "tripped"];
    resources(j).voltage_forming_modes = 'gfm';
    resources(j).initial_mode = 'gfl';
    resources(j).has_current_limiter = true;
    resources(j).has_frt = true;
end
case_data = make_case();
end

function cheap = always_unknown_cheap(~, ~, ~, ~)
cheap = struct('is_singular', false, 'topology_ok', true, 'scr_available', false, ...
    'source_aware', false);
end

function out = synth_eval_full(cand, varargin) %#ok<INUSD>
% Faithful full-evidence stand-in. A subset is feasible iff the sum of its
% selected indices is even; margin = sum/10. Populates the FULL evidence vector
% the trusted predicate requires, so only the trusted opt-in can certify it.
out = cand;
out.topology_evaluated = true;
out.scr_evaluated = true;
out.scr_pass = true;
out.equilibrium_evaluated = true;
out.sssa_evaluated = true;
out.full_kcl = true;
out.eq_rcond = 1e-3;
out.gy_rcond = 1e-3;
out.sssa_f0_norm = 1e-9;
out.sssa_g0_norm = 1e-9;
out.physical_kcl_norm = 1e-9;
out.eigenvalues = [-1 -2];
out.physical_eigenvalues = [-1 -2];
out.fd_omegas = [-1 -1 -1];
out.fd_zeta_worsts = [0.2 0.2 0.2];
out.zeta_worst = 0.2;
out.zeta_min = 0.05;
sel = sort(cand.selected_gfm_indices);
feas = mod(sum(sel), 2) == 0;
out.sssa_pass = feas;
if feas
    out.feasible = true;
    out.ready_to_commit = true;
    out.margin = sum(sel) / 10;
else
    out.feasible = false;
    out.ready_to_commit = false;
    out.margin = NaN;
end
out.reason = 'synth_eval_full';
end

function out = synth_eval_full_records(cand, recs)
% synth_eval_full plus a physical-evidence RECORD array, to exercise the
% shared evidence ABI gate in the certification predicate.
out = synth_eval_full(cand);
out.evidence = recs;
end

function out = synth_eval_none(cand, varargin) %#ok<INUSD>
% Definitive infeasibility: equilibrium + SSSA reached, feasible=false.
out = cand;
out.topology_evaluated = true;
out.scr_evaluated = true;
out.scr_pass = true;
out.equilibrium_evaluated = true;
out.sssa_evaluated = true;
out.physical_kcl_norm = 1e-9;
out.feasible = false;
out.ready_to_commit = false;
out.margin = NaN;
out.reason = 'synth_eval_none';
end

function out = synth_eval_structural_only(cand, varargin) %#ok<INUSD>
% feasible=true WITHOUT equilibrium/SSSA -> UNKNOWN (never a certificate, and
% never a proof of infeasibility).
out = cand;
out.topology_evaluated = true;
out.scr_evaluated = true;
out.physical_kcl_norm = 1e-9;
out.feasible = true;
out.ready_to_commit = false;
out.margin = 1.0;
out.reason = 'structural_only';
end

function ref = reference_exhaustive(resources, counts, ev)
nr = numel(resources); %#ok<NASGU>
eligible = find(arrayfun(@(r) strcmp(lower(char(r.resource_type)), 'ibr') && ...
    logical(r.initial_online) && logical(r.can_switch_mode), resources));
ref = struct('selected_gfm_indices', [], 'configurations', []);
cfgs = [];
for k = counts
    if k == 0
        C = zeros(1, 0);
    else
        C = nchoosek(eligible, k);
    end
    for r = 1:size(C, 1)
        sel = C(r, :);
        cand = struct('selected_gfm_indices', sel, 'n_gfm_required', numel(sel), ...
            'n_mode_changes', numel(sel));
        c_out = ev(cand);
        c_out.n_mode_changes = numel(sel);
        if isempty(cfgs)
            cfgs = c_out;
        else
            cfgs(end+1) = c_out; %#ok<AGROW>
        end
    end
end
nc = zeros(1, numel(cfgs));
for i = 1:numel(cfgs), nc(i) = cfgs(i).n_mode_changes; end
if ~isempty(cfgs)
    [M, ~] = candidate_order_matrix(cfgs, nc);
    [~, order] = sortrows(M, [1 2 3 4 5]);
    cfgs = cfgs(order);
end
ref.configurations = cfgs;
if ~isempty(cfgs)
    ref.selected_gfm_indices = cfgs(1).selected_gfm_indices;
end
end

function n = count_feasible(cfgs)
n = 0;
for i = 1:numel(cfgs)
    if isfield(cfgs(i), 'feasible') && ~isempty(cfgs(i).feasible) && logical(cfgs(i).feasible)
        n = n + 1;
    end
end
end

function n = count_ready(cfgs)
n = 0;
for i = 1:numel(cfgs)
    if isfield(cfgs(i), 'ready_to_commit') && ~isempty(cfgs(i).ready_to_commit) && ...
            logical(cfgs(i).ready_to_commit)
        n = n + 1;
    end
end
end

function n = count_unsafe(cfgs)
n = 0;
for i = 1:numel(cfgs)
    c = cfgs(i);
    if isfield(c, 'ready_to_commit') && ~isempty(c.ready_to_commit) && ...
            logical(c.ready_to_commit) && ...
            ~(isfield(c, 'feasible') && ~isempty(c.feasible) && logical(c.feasible))
        n = n + 1;
    end
end
end
