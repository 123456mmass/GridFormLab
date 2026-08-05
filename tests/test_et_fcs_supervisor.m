function tests = test_et_fcs_supervisor
%TEST_ET_FCS_SUPERVISOR  Falsification/oracle tests for additive ET-FCSPS core.
%   Providers in this file are ASSUMED_DIAGNOSTIC fixtures. Production policy
%   rejects them; the test policy explicitly enables diagnostic callbacks.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.state = base_state();
tc.TestData.event = base_event();
tc.TestData.policy = base_policy();
tc.TestData.providers = struct('screen',@screen_good,'predict',@predict_good);
end

function test_snapshot_is_deterministic_and_value_only(tc)
s1 = stability.et_fcs_snapshot(tc.TestData.state,tc.TestData.event);
s2 = stability.et_fcs_snapshot(tc.TestData.state,tc.TestData.event);
tc.verifyEqual(s1.fingerprint,s2.fingerprint);
tc.verifyEqual(s1.schema,'et_fcs_snapshot/1.0');
tc.verifyTrue(s1.accepted);
end

function test_snapshot_rejects_nonfinite_and_duplicate_identity(tc)
s = tc.TestData.state; s.x(1) = NaN;
tc.verifyError(@() stability.et_fcs_snapshot(s,tc.TestData.event), ...
    'stability:et_fcs_snapshot:nonFiniteState');
s = tc.TestData.state; s.resource_ids{5} = s.resource_ids{4};
tc.verifyError(@() stability.et_fcs_snapshot(s,tc.TestData.event), ...
    'stability:et_fcs_snapshot:badResourceIds');
end

function test_sg_online_enumerates_sixteen_vectors_with_sg_owner(tc)
s = stability.et_fcs_snapshot(tc.TestData.state,tc.TestData.event);
c = stability.et_fcs_enumerate(s);
tc.verifyNumElements(c,16);
tc.verifyEqual(numel(unique({c.candidate_id})),16);
tc.verifyEqual([c.owner_index],ones(1,16));
tc.verifyEmpty(c(1).selected_gfm_indices);
tc.verifyEqual(c(1).candidate_id,'m0000|owner=SG1');
end

function test_sg_off_enumerates_thirty_two_mode_owner_pairs(tc)
st = tc.TestData.state;
st.device_online(1) = false;
st.device_modes{1} = 'breaker_open';
st.reference_owner_indices = [];
ev = tc.TestData.event; ev.local_request = false; ev.authenticated = true;
s = stability.et_fcs_snapshot(st,ev);
c = stability.et_fcs_enumerate(s);
tc.verifyNumElements(c,32);
tc.verifyEqual(numel(unique({c.candidate_id})),32);
for k = 1:numel(c)
    tc.verifyTrue(ismember(c(k).owner_index,c(k).selected_gfm_indices));
    tc.verifyGreaterThanOrEqual(c(k).n_gfm,1);
end

function test_authenticated_sg_trip_uses_event_right_context(tc)
% The immutable snapshot remains the accepted event-left state, while the
% enumerator/screen must use the authenticated event-right online/owner view.
st = tc.TestData.state;
st.decision_device_online = st.device_online;
st.decision_device_online(1) = false;
st.decision_reference_owner_indices = [];
ev = tc.TestData.event; ev.local_request = false; ev.authenticated = true;
s = stability.et_fcs_snapshot(st,ev);
c = stability.et_fcs_enumerate(s);
tc.verifyTrue(s.device_online(1));
tc.verifyFalse(s.decision_device_online(1));
tc.verifyNumElements(c,32);
tc.verifyTrue(all([c.owner_index] ~= 1));
for k = 1:numel(c)
    tc.verifyTrue(ismember(c(k).owner_index,c(k).selected_gfm_indices));
end
c = stability.et_fcs_screen(s,c,@screen_good, ...
    struct('allow_diagnostic_callback',true));
tc.verifyTrue(all([c.screen_pass]));
end
end

function test_hold_and_lockout_prune_only_required_transitions(tc)
st = tc.TestData.state; st.hold_timers(2) = 0.2;
s = stability.et_fcs_snapshot(st,tc.TestData.event);
c = stability.et_fcs_enumerate(s);
c = stability.et_fcs_screen(s,c,@screen_good,struct('allow_diagnostic_callback',true));
tc.verifyTrue(c(1).screen_pass,'All-GFL requires no transition and must survive.');
tc.verifyFalse(c(2).screen_pass,'IBR1 GFL->GFM must be blocked by its hold timer.');
tc.verifyEqual(c(2).screen.failure_id,'stability:et_fcs_screen:holdBlocksTransition');

st = tc.TestData.state; st.lockout_until(2) = st.t + 1;
s = stability.et_fcs_snapshot(st,tc.TestData.event);
c = stability.et_fcs_enumerate(s);
c = stability.et_fcs_screen(s,c,@screen_good,struct('allow_diagnostic_callback',true));
tc.verifyEqual(c(2).screen.failure_id,'stability:et_fcs_screen:lockoutBlocksTransition');
end

function test_voltage_and_unknown_reserve_fail_before_prediction(tc)
p = tc.TestData.providers; p.screen = @screen_low_voltage;
d = stability.et_fcs_supervisor(tc.TestData.state,tc.TestData.event,p,tc.TestData.policy);
tc.verifyEqual(d.status,'INFEASIBLE');
tc.verifyFalse(d.commit_requested);
tc.verifyTrue(all(~[d.candidates.screen_pass]));
tc.verifyTrue(all(strcmp(screen_failure_ids(d.candidates), ...
    'stability:et_fcs_screen:voltageViolation')));

p.screen = @screen_unknown_reserve;
d = stability.et_fcs_supervisor(tc.TestData.state,tc.TestData.event,p,tc.TestData.policy);
tc.verifyEqual(d.status,'INFEASIBLE');
tc.verifyTrue(all(strcmp(screen_failure_ids(d.candidates), ...
    'stability:et_fcs_screen:reserveUnknown')));
end

function test_incomplete_horizon_and_dynamic_gate_fail_closed(tc)
p = tc.TestData.providers; p.predict = @predict_short;
d = stability.et_fcs_supervisor(tc.TestData.state,tc.TestData.event,p,tc.TestData.policy);
tc.verifyEqual(d.status,'INFEASIBLE');
tc.verifyTrue(all(strcmp(prediction_failure_ids(d.candidates), ...
    'stability:et_fcs_predict:incompleteHorizon')));

p.predict = @predict_bad_frequency;
d = stability.et_fcs_supervisor(tc.TestData.state,tc.TestData.event,p,tc.TestData.policy);
tc.verifyEqual(d.status,'INFEASIBLE');
tc.verifyTrue(all(strcmp(prediction_failure_ids(d.candidates), ...
    'stability:et_fcs_predict:frequencyViolation')));
end

function test_no_event_holds_without_requiring_providers(tc)
ev = tc.TestData.event; ev.local_request = false; ev.authenticated = false;
d = stability.et_fcs_supervisor(tc.TestData.state,ev,struct(),struct());
tc.verifyEqual(d.status,'HOLD');
tc.verifyEqual(d.action,'HOLD_CURRENT');
tc.verifyFalse(d.commit_requested);
end

function test_supervisor_replay_is_deterministic_and_does_not_mutate(tc)
before = tc.TestData.state;
d1 = stability.et_fcs_supervisor(before,tc.TestData.event, ...
    tc.TestData.providers,tc.TestData.policy);
d2 = stability.et_fcs_supervisor(before,tc.TestData.event, ...
    tc.TestData.providers,tc.TestData.policy);
tc.verifyEqual(d1.status,'COMMIT_REQUEST');
tc.verifyTrue(d1.commit_requested);
tc.verifyEqual(d1.winner_candidate_id,d2.winner_candidate_id);
tc.verifyEqual(d1.candidate_evidence_fingerprint,d2.candidate_evidence_fingerprint);
tc.verifyEqual(d1.decision_fingerprint,d2.decision_fingerprint);
tc.verifyEqual(before,tc.TestData.state);
end

function test_ranking_is_invariant_to_candidate_input_order(tc)
s = stability.et_fcs_snapshot(tc.TestData.state,tc.TestData.event);
c = stability.et_fcs_enumerate(s);
c = stability.et_fcs_screen(s,c,@screen_good,struct('allow_diagnostic_callback',true));
c = stability.et_fcs_predict(s,c,@predict_good,tc.TestData.policy);
c = stability.et_fcs_metrics(s,c,tc.TestData.policy);
[~,r1] = stability.et_fcs_rank(s,c,tc.TestData.policy);
shuffle = c([16:-2:2,15:-2:1]);
[~,r2] = stability.et_fcs_rank(s,shuffle,tc.TestData.policy);
tc.verifyEqual(r1.winner_candidate_id,r2.winner_candidate_id);
tc.verifyEqual(r1.candidate_evidence_fingerprint,r2.candidate_evidence_fingerprint);
end

function test_commit_guard_accepts_fresh_and_rejects_stale(tc)
d = stability.et_fcs_supervisor(tc.TestData.state,tc.TestData.event, ...
    tc.TestData.providers,tc.TestData.policy);
[ok,reason] = stability.et_fcs_commit_guard(tc.TestData.state,tc.TestData.event,d);
tc.verifyTrue(ok); tc.verifyEmpty(reason);
stale = tc.TestData.state; stale.y(1) = stale.y(1) + 1e-6;
[ok,reason] = stability.et_fcs_commit_guard(stale,tc.TestData.event,d);
tc.verifyFalse(ok);
tc.verifyEqual(reason,'stability:et_fcs_commit_guard:staleSnapshot');
end

function test_provider_exception_is_evidence_not_partial_commit(tc)
p = tc.TestData.providers; p.screen = @screen_exception;
d = stability.et_fcs_supervisor(tc.TestData.state,tc.TestData.event,p,tc.TestData.policy);
tc.verifyEqual(d.status,'INFEASIBLE');
tc.verifyFalse(d.commit_requested);
tc.verifyTrue(all(strcmp(screen_failure_ids(d.candidates), ...
    'stability:et_fcs_screen:providerException')));
end

function test_nonproject_callback_rejected_on_production_policy(tc)
policy = tc.TestData.policy; policy.allow_diagnostic_callback = false;
d = stability.et_fcs_supervisor(tc.TestData.state,tc.TestData.event, ...
    tc.TestData.providers,policy);
tc.verifyEqual(d.status,'INFEASIBLE');
tc.verifyEqual(d.failure_id,'stability:et_fcs_screen:nonProjectProvider');
tc.verifyFalse(d.commit_requested);
end

function test_authenticated_trial_table_runs_with_project_owned_providers(tc)
st = tc.TestData.state;
s0 = stability.et_fcs_snapshot(st,tc.TestData.event);
c = stability.et_fcs_enumerate(s0);
table = repmat(struct('candidate_id','','screen',struct(),'prediction',struct()),numel(c),1);
for k = 1:numel(c)
    table(k).candidate_id = c(k).candidate_id;
    table(k).screen = screen_good(s0,c(k));
    table(k).prediction = predict_good(s0,c(k),table(k).screen, ...
        tc.TestData.policy.prediction_horizon);
end
st.trial_table = table;
policy = tc.TestData.policy; policy.allow_diagnostic_callback = false;
providers = struct('screen','stability.et_fcs_table_screen', ...
    'predict','stability.et_fcs_table_predict');
d = stability.et_fcs_supervisor(st,tc.TestData.event,providers,policy);
tc.verifyEqual(d.status,'COMMIT_REQUEST',sprintf('%s: %s',d.failure_id,d.reason));
tc.verifyTrue(d.commit_requested);
[ok,reason] = stability.et_fcs_commit_guard(st,tc.TestData.event,d);
tc.verifyTrue(ok); tc.verifyEmpty(reason);
end

function test_missing_or_unfrozen_weight_contract_fails_closed(tc)
policy = tc.TestData.policy; policy.weights.voltage = 0.5;
d = stability.et_fcs_supervisor(tc.TestData.state,tc.TestData.event, ...
    tc.TestData.providers,policy);
tc.verifyEqual(d.status,'INFEASIBLE');
tc.verifyEqual(d.failure_id,'stability:et_fcs_rank:badWeights');
tc.verifyFalse(d.commit_requested);
end

function test_ieee14_prototype_policy_is_frozen_and_normalized(tc)
p = stability.et_fcs_policy_ieee14();
tc.verifyEqual(p.classification,'PROJECT_DERIVED_PROTOTYPE');
tc.verifyEqual(p.prediction_horizon,0.25,'AbsTol',0);
tc.verifyFalse(p.allow_diagnostic_callback);
w = struct2cell(p.weights);
tc.verifyEqual(sum(cell2mat(w)),1,'AbsTol',1e-14);
tc.verifyEqual(p.bo.classification,'ASSUMED_DIAGNOSTIC_OFFLINE_REPLAY');
end

function test_bo_replay_is_deterministic_budgeted_and_order_invariant(tc)
c = complete_fixture_candidates(tc);
pp = stability.et_fcs_policy_ieee14(); bo = pp.bo;
r1 = stability.et_fcs_bo_replay(c,bo);
r2 = stability.et_fcs_bo_replay(c([16:-2:2,15:-2:1]),bo);
tc.verifyEqual(r1.status,'COMPLETE');
tc.verifyEqual(r1.evaluation_count,bo.budget);
tc.verifyLessThan(r1.evaluation_count,sum([c.screen_pass]));
tc.verifyEqual(r1.sampled_candidate_ids,r2.sampled_candidate_ids);
tc.verifyEqual(r1.winner_candidate_id,r2.winner_candidate_id);
tc.verifyEqual(r1.regret,r2.regret,'AbsTol',0);
end

function test_bo_full_budget_recovers_exhaustive_winner(tc)
c = complete_fixture_candidates(tc);
pp = stability.et_fcs_policy_ieee14(); bo = pp.bo;
bo.budget = sum([c.screen_pass]); bo.n_initial = 3;
r = stability.et_fcs_bo_replay(c,bo);
tc.verifyEqual(r.status,'COMPLETE');
tc.verifyTrue(r.matches_exhaustive);
tc.verifyEqual(r.regret,0,'AbsTol',0);
tc.verifyEqual(r.evaluation_count,sum([c.screen_pass]));
end

function test_bo_is_offline_inhouse_and_no_screen_path_is_explicit(tc)
c = complete_fixture_candidates(tc);
for k = 1:numel(c), c(k).screen_pass = false; end
pp = stability.et_fcs_policy_ieee14(); bo = pp.bo;
r = stability.et_fcs_bo_replay(c,bo);
tc.verifyEqual(r.status,'NO_SCREEN_FEASIBLE');
source = fileread(which('stability.et_fcs_bo_replay'));
tc.verifyFalse(contains(lower(source),'bayesopt('));
tc.verifyFalse(contains(lower(source),'fmincon('));
tc.verifyFalse(contains(lower(source),'patternsearch('));
end

function test_paired_comparison_uses_identical_screened_universe(tc)
c = complete_fixture_candidates(tc);
pp = stability.et_fcs_policy_ieee14();
x = stability.et_fcs_compare_bo(c,pp.bo);
tc.verifyEqual(x.status,'COMPLETE');
tc.verifyEqual(x.et_fcs_candidate_count,sum([c.screen_pass]));
tc.verifyEqual(x.bo_evaluation_count,pp.bo.budget);
tc.verifyEqual(x.evaluation_reduction_fraction,0.5,'AbsTol',0);
tc.verifyGreaterThanOrEqual(x.bo_regret,0);
end

function st = base_state()
st = struct();
st.accepted = true; st.t = 20; st.x = (1:6)'; st.y = complex((1:4)',0.1);
st.topology_payload = complex([10 -10;-10 10],[0 -20;20 0]);
st.resource_ids = {'SG1','IBR1','IBR2','IBR3','IBR4'};
st.resource_types = {'sg','ibr','ibr','ibr','ibr'};
st.device_modes = {'synchronous','gfl','gfl','gfl','gfl'};
st.device_online = true(1,5);
st.eligible_mask = [false true true true true];
st.reference_capable = true(1,5);
st.resource_island_ids = ones(1,5);
st.energized_island_ids = 1;
st.reference_owner_indices = 1;
st.hold_timers = zeros(1,5);
st.lockout_until = -Inf(1,5);
st.limits = struct('kcl_tol',1e-8,'v_min',0.90,'v_max',1.10, ...
    'i_max',1.20,'f_min',59,'f_max',61,'rocof_max',2);
st.reserve = struct('known',true,'provenance','CASE_DEFINED_fixture');
st.agsi = [0 0.7 0.4 0.2 0.1];
end

function ev = base_event()
ev = struct('event_id','evt-0001','type','agsi_request', ...
    'authenticated',false,'local_request',true);
end

function p = base_policy()
p = struct();
p.prediction_horizon = 0.20;
p.prediction_time_tol = 1e-12;
p.allow_diagnostic_callback = true;
p.normalization = struct('voltage',0.10,'frequency',0.50,'rocof',1.0, ...
    'reserve_p',1.0,'reserve_q',1.0,'handback_p',1.0,'handback_q',1.0, ...
    'handback_i',1.0,'handback_theta',10.0);
p.targets = struct('voltage',1.0,'frequency',60,'reserve_p',0.2,'reserve_q',0.2);
w = 1/9;
p.weights = struct('voltage',w,'frequency',w,'rocof',w,'reserve_p',w, ...
    'reserve_q',w,'current',w,'handback',w,'n_gfm',w,'n_switch',w);
p.cost_quantization = 1e-12;
end

function e = screen_good(s,c)
e = struct('converged',true,'kcl_norm',1e-10, ...
    'voltage_abs',ones(14,1),'current_abs',(0.45+0.02*c.n_gfm)*ones(4,1), ...
    'reserve_known',true,'delta_p_available',0.8-0.04*c.n_gfm, ...
    'delta_q_available',0.7-0.03*c.n_gfm,'mapped_x',s.x,'mapped_y',s.y);
end

function e = screen_low_voltage(s,c)
e = screen_good(s,c); e.voltage_abs(1) = 0.89;
end

function e = screen_unknown_reserve(s,c)
e = screen_good(s,c); e.reserve_known = false;
end

function e = screen_exception(~,~)
e = struct(); %#ok<NASGU>
error('fixture:screenFailure','Injected diagnostic screen failure.');
end

function p = predict_good(s,c,~,Tp)
t = [s.t,s.t+Tp/2,s.t+Tp]; nt = numel(t);
dv = 0.003*(4-c.n_gfm);
p = struct('converged',true,'t',t, ...
    'voltage_abs',(1+dv)*ones(14,nt), ...
    'frequency_hz',(60+0.01*(4-c.n_gfm))*ones(1,nt), ...
    'rocof_hz_s',(0.04+0.01*(4-c.n_gfm))*ones(1,nt), ...
    'current_abs',(0.45+0.02*c.n_gfm)*ones(4,nt), ...
    'reserve_known',true,'delta_p_available',(0.8-0.04*c.n_gfm)*ones(1,nt), ...
    'delta_q_available',(0.7-0.03*c.n_gfm)*ones(1,nt), ...
    'handback',struct('delta_p',0.01*c.n_switch,'delta_q',0.01*c.n_switch, ...
    'delta_i',0.01*c.n_switch,'delta_theta',0.1*c.n_switch));
end

function p = predict_short(s,c,screen,Tp)
p = predict_good(s,c,screen,Tp); p.t(end) = s.t + Tp/2;
end

function p = predict_bad_frequency(s,c,screen,Tp)
p = predict_good(s,c,screen,Tp); p.frequency_hz(:) = s.limits.f_max + 0.1;
end

function c = complete_fixture_candidates(tc)
s = stability.et_fcs_snapshot(tc.TestData.state,tc.TestData.event);
c = stability.et_fcs_enumerate(s);
c = stability.et_fcs_screen(s,c,@screen_good,struct('allow_diagnostic_callback',true));
c = stability.et_fcs_predict(s,c,@predict_good,tc.TestData.policy);
c = stability.et_fcs_metrics(s,c,tc.TestData.policy);
[c,~] = stability.et_fcs_rank(s,c,tc.TestData.policy);
end

function ids = screen_failure_ids(c)
ids = arrayfun(@(x) x.screen.failure_id,c,'UniformOutput',false);
end

function ids = prediction_failure_ids(c)
ids = arrayfun(@(x) x.prediction.failure_id,c,'UniformOutput',false);
end
