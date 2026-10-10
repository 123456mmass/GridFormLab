function tests = test_ai_supervisor_contract
%TEST_AI_SUPERVISOR_CONTRACT  Contract tests for the AI supervisory layer.
%
%   No test here opens a network connection. The model call is bypassed with
%   force_fallback = true wherever the loop is exercised, so the whole pipeline
%   -- snapshot, trigger, features, selection, apply -- is covered on a machine
%   with no API key, no route out, and no MATLAB toolboxes.
%
%   What is being pinned is not that the code runs. It is that the four design
%   rules hold at the point of action: a primary is always named, no more than
%   two buses are ever selected, an already-forming bus is never selected, and
%   an unavailable index is never read as a healthy one.
%
%   See also ai.ai_detect_event, ai.ai_parse_decision, ai.ai_fallback_selector.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% =========================================================================
% ESCR
% =========================================================================
function test_escr_matches_closed_form(testCase)
% For Y = [2 -1; -1 2] the self-impedance at bus 1 is 2/3, so a 1.0 pu bus
% with a 1.0 pu rating has ESCR 1.5 exactly. If the formula, the solve, or the
% rating normalisation drifts, this is the number that moves.
Ylog = struct('t', 0, 'topology', 'base', 'Y', [2 -1; -1 2]);
escr = ai.ai_escr_metrics(Ylog, 1, 1.0, [1.0; 0.9], 0.0);
testCase.verifyEqual(escr, 1.5, 'RelTol', 1e-12);
end

function test_escr_scales_with_voltage_squared(testCase)
Ylog = struct('t', 0, 'topology', 'base', 'Y', [2 -1; -1 2]);
escr = ai.ai_escr_metrics(Ylog, 2, 1.0, [1.0; 0.9], 0.0);
testCase.verifyEqual(escr, 0.81/(2/3), 'RelTol', 1e-12);
end

function test_escr_singular_admittance_is_nan_not_zero(testCase)
% A zero would read as an infinitely strong bus and invert the selection rule,
% which ranks on the SMALLEST ESCR. NaN is the only honest answer.
ws = warning('query', 'MATLAB:singularMatrix');
warning('off', 'MATLAB:singularMatrix');
restore = onCleanup(@() warning(ws));
Ylog = struct('t', 0, 'topology', 'base', 'Y', [1 -1; -1 1]);
escr = ai.ai_escr_metrics(Ylog, 1, 1.0, [1.0; 0.9], 0.0);
testCase.verifyTrue(isnan(escr), 'Singular Y must yield NaN, not a number.');
end

function test_escr_rating_count_must_match_bus_count(testCase)
Ylog = struct('t', 0, 'topology', 'base', 'Y', [2 -1; -1 2]);
testCase.verifyError(@() ai.ai_escr_metrics(Ylog, [1 2], 1.0, [1;1], 0.0), ...
    'ai:ai_escr_metrics:ratingCountMismatch');
end

function test_escr_rejects_voltage_matrix_of_wrong_width(testCase)
Ylog = struct('t', 0, 'topology', 'base', 'Y', [2 -1; -1 2]);
testCase.verifyError(@() ai.ai_escr_metrics(Ylog, 1, 1.0, [1.0; 0.9], [0 0.05]), ...
    'ai:ai_escr_metrics:sampleCountMismatch');
end

% =========================================================================
% MI-ESCR
% The multi-infeed ratio is a different quantity from the single-infeed one
% above: each converter's own voltage support lowers its Thevenin impedance and
% the other converters load it. These tests pin the arithmetic on closed forms
% small enough to do by hand, and pin the places where a wrong answer would be
% plausible rather than obviously broken.
% =========================================================================
function test_miescr_with_no_source_equals_the_single_infeed_ratio(testCase)
% The two functions are pinned against each other rather than asserted to
% agree: with nothing stamped there is no interaction to count, so the
% multi-infeed ratio must reduce to exactly the single-infeed number.
Y = [2 -1; -1 2];
Ylog = struct('t', 0, 'topology', 'base', 'Y', Y);
single = ai.ai_escr_metrics(Ylog, 1, 1.0, [1.0; 0.9], 0.0);
multi = ai.miescr_metrics(Y, 1, [1.0; 0.9], 1.0);
testCase.verifyEqual(single, 1.5, 'RelTol', 1e-12);
testCase.verifyEqual(multi, single, 'RelTol', 1e-12);
end

function test_miescr_no_source_leaves_the_interaction_matrix_empty(testCase)
% MII is defined as |Z(j,i)|/|Z(i,i)| between DIFFERENT converters. A single
% converter has no partner, so its off-diagonal must be zero -- not NaN and not
% a self-entry of 1, either of which would corrupt the denominator sum.
Y = [2 -1; -1 2];
[~, info] = ai.miescr_metrics(Y, 1, [1.0; 0.9], 1.0);
testCase.verifyEqual(info.MII, 0);
end

function test_miescr_stamps_the_source_admittance_on_the_diagonal(testCase)
% Stamping y = 1 at bus 1 of Y = [2 -1; -1 2] gives [3 -1; -1 2], whose
% self-impedance is 2/5. S_sc is therefore 2.5 pu, and with one converter and
% no partner to load it the ratio is 2.5 exactly.
Y = [2 -1; -1 2];
src = struct('bus_position', 1, 'admittance', 1.0);
[escr, info] = ai.miescr_metrics(Y, 1, [1.0; 0.9], 1.0, struct('sources', src));
testCase.verifyEqual(info.Ssc_pu(1), 2.5, 'RelTol', 1e-12);
testCase.verifyEqual(escr(1), 2.5, 'RelTol', 1e-12);
end

function test_miescr_stamping_a_source_cannot_make_a_bus_weaker(testCase)
% The direction matters more than the value: a converter that forms voltage can
% only lower the Thevenin impedance seen at its own bus. If stamping ever
% LOWERED S_sc, the whole "more formers is stronger" reading would be an
% artefact of the sign convention.
Y = [2 -1; -1 2];
base = ai.miescr_metrics(Y, 1, [1.0; 0.9], 1.0);
src = struct('bus_position', 1, 'admittance', 1.0);
stamped = ai.miescr_metrics(Y, 1, [1.0; 0.9], 1.0, struct('sources', src));
testCase.verifyGreaterThan(stamped(1), base(1));
end

function test_miescr_interaction_loads_the_denominator(testCase)
% Two converters, both stamping y = 1 on Y = [2 -1; -1 2]: the augmented matrix
% is [3 -1; -1 3], Z11 = 3/8 and Z21 = 1/8, so MII(2,1) = 1/3. S_sc = 8/3.
%   cigre      (8/3) / (1 + 1/3) = 2
%   numerator  (8/3 - 1/3) / 1   = 7/3
% Both are pinned because they are NOT the same number and the difference is
% the whole reason the option exists.
Y = [2 -1; -1 2];
src = struct('bus_position', {1, 2}, 'admittance', {1.0, 1.0});
[e, info] = ai.miescr_metrics(Y, [1 2], [1.0; 1.0], [1 1], ...
    struct('sources', src));
testCase.verifyEqual(info.MII(2, 1), 1/3, 'RelTol', 1e-12);
testCase.verifyEqual(e(1), 2.0, 'RelTol', 1e-12);
testCase.verifyEqual(info.escr_numerator(1), 7/3, 'RelTol', 1e-12);
end

function test_miescr_numerator_form_can_go_negative(testCase)
% On a very weakly coupled pair the interaction term can exceed S_sc, and the
% numerator form is then negative. That is not a bug to be clamped away: it is
% the shape this form has, and the reason the published denominator form is the
% default. Y = [1 -0.99; -0.99 1] has det 0.0199, so Z11 = 50.2513,
% MII(2,1) = 0.99 and S_sc = 0.0199.
Y = [1 -0.99; -0.99 1];
[e, info] = ai.miescr_metrics(Y, [1 2], [1.0; 1.0], [1 1]);
testCase.verifyEqual(info.MII(2, 1), 0.99, 'RelTol', 1e-9);
testCase.verifyLessThan(info.escr_numerator(1), 0);
testCase.verifyEqual(info.escr_cigre(1), 0.01, 'RelTol', 1e-9);
testCase.verifyEqual(e(1), info.escr_cigre(1), 'RelTol', 1e-12);
end

function test_miescr_numerator_form_is_requested_explicitly(testCase)
% Asking for the numerator form must change the RETURNED column, not merely
% populate a second field a caller has to know to look at.
Y = [1 -0.99; -0.99 1];
[e, info] = ai.miescr_metrics(Y, [1 2], [1.0; 1.0], [1 1], ...
    struct('form', 'numerator'));
testCase.verifyEqual(e(1), 0.0199 - 0.99, 'RelTol', 1e-9);
testCase.verifyEqual(e(1), info.escr_numerator(1), 'RelTol', 1e-12);
testCase.verifyLessThan(e(1), info.escr_cigre(1));
end

function test_miescr_a_current_source_stamps_nothing(testCase)
% A grid-following converter is a current source: it holds no bus voltage of
% its own. It is represented by the ABSENCE of a source entry, and a zero
% admittance passed in its place must produce exactly the unstamped answer --
% not a small stamp, which would invent voltage support the model lacks.
Y = [2 -1; -1 2];
plain = ai.miescr_metrics(Y, 1, [1.0; 0.9], 1.0);
src = struct('bus_position', 1, 'admittance', 0);
[zeroed, info] = ai.miescr_metrics(Y, 1, [1.0; 0.9], 1.0, struct('sources', src));
testCase.verifyEqual(zeroed(1), plain(1), 'RelTol', 1e-12);
testCase.verifyEmpty(info.sources_applied);
end

function test_miescr_a_missing_admittance_is_skipped_not_nan(testCase)
% robustness for a live topology log: a source entry whose admittance is empty
% is whatever it is, but it must not turn the whole ratio NaN.
Y = [2 -1; -1 2];
src = struct('bus_position', 1, 'admittance', []);
[escr, info] = ai.miescr_metrics(Y, 1, [1.0; 0.9], 1.0, struct('sources', src));
testCase.verifyEqual(escr(1), 1.5, 'RelTol', 1e-12);
testCase.verifyTrue(isempty(info.sources_applied));
end

function test_miescr_singular_admittance_is_nan_not_zero(testCase)
% Same rule as the single-infeed metric: a zero would read as an infinitely
% weak bus and invert any rule that ranks on the smallest value.
ws = warning('query', 'MATLAB:singularMatrix');
warning('off', 'MATLAB:singularMatrix');
restore = onCleanup(@() warning(ws));
[escr, info] = ai.miescr_metrics([1 -1; -1 1], 1, [1.0; 0.9], 1.0);
testCase.verifyTrue(isnan(escr(1)), 'Singular Y must yield NaN, not a number.');
testCase.verifyTrue(info.is_singular);
end

function test_miescr_rating_count_must_match_bus_count(testCase)
testCase.verifyError(@() ai.miescr_metrics([2 -1; -1 2], [1 2], [1.0; 0.9], 1.0), ...
    'ai:miescr_metrics:ratingCountMismatch');
end

function test_miescr_rejects_a_bus_position_outside_the_matrix(testCase)
testCase.verifyError(@() ai.miescr_metrics([2 -1; -1 2], 3, [1.0; 0.9], 1.0), ...
    'ai:miescr_metrics:busOutOfRange');
end

function test_miescr_rejects_an_unsupported_form(testCase)
% A typo in the form name must not silently fall back to the default, because
% the two forms disagree in sign on a weak island.
testCase.verifyError(@() ai.miescr_metrics([2 -1; -1 2], 1, [1.0; 0.9], 1.0, ...
    struct('form', 'cigre_ish')), 'ai:miescr_metrics:badForm');
end

function test_miescr_voltage_may_be_given_per_bus_or_per_converter(testCase)
Y = [2 -1; -1 2];
src = struct('bus_position', 1, 'admittance', 1.0);
per_bus = ai.miescr_metrics(Y, 1, [1.0; 0.9], 1.0, struct('sources', src));
per_ibr = ai.miescr_metrics(Y, 1, 1.0, 1.0, struct('sources', src));
testCase.verifyEqual(per_bus(1), per_ibr(1), 'RelTol', 1e-12);
end

function test_miescr_never_returns_a_gate_verdict(testCase)
% The production SCR gate admits this model family without consulting any
% short-circuit number. Every output here is a diagnostic, and the returned
% classification has to say so rather than leaving a caller to assume the
% number was used for something.
[~, info] = ai.miescr_metrics([2 -1; -1 2], 1, [1.0; 0.9], 1.0);
testCase.verifySubstring(info.classification, 'diagnostic');
end

% =========================================================================
% trigger detection
% =========================================================================
function test_spec_rule_fires_on_sustained_rocof(testCase)
snap = plain_snap(20);
snap.rocof_Hz_s(5:10) = -0.9;
det = ai.ai_detect_event(snap, ai.ai_supervisor_defaults());
% Demand starts at t = 0.20 and must hold dwell_on_s = 0.10, so the commit is
% at t = 0.30 -- index 7 at 0.05 s spacing.
testCase.verifyEqual(det.first_index, 7);
testCase.verifyEqual(det.first_reason, "spec:rocof");
end

function test_spec_rule_fires_on_low_voltage(testCase)
snap = plain_snap(20);
snap.V_min_pu(5:10) = 0.88;
det = ai.ai_detect_event(snap, ai.ai_supervisor_defaults());
testCase.verifyEqual(det.first_index, 7);
testCase.verifyEqual(det.first_reason, "spec:vmin");
end

function test_dwell_blocks_a_single_sample_spike(testCase)
% One sample over the line is a measurement, not an emergency. Without the
% debounce the supervisor would commit on it, and at 0.05 s spacing that is a
% decision every 50 ms.
snap = plain_snap(20);
snap.rocof_Hz_s(5) = -5.0;
det = ai.ai_detect_event(snap, ai.ai_supervisor_defaults());
testCase.verifyEmpty(det.trigger_indices);
end

function test_zero_dwell_fires_on_the_first_demand_sample(testCase)
snap = plain_snap(20);
snap.rocof_Hz_s(5) = -5.0;
det = ai.ai_detect_event(snap, ...
    ai.ai_supervisor_defaults(struct('dwell_on_s', 0)));
testCase.verifyEqual(det.first_index, 5);
end

function test_nan_measurement_can_never_trigger(testCase)
% An unavailable measurement is not evidence of a healthy grid, and it is not
% evidence of an emergency either. It simply cannot fire.
snap = plain_snap(20);
snap.rocof_Hz_s(:) = NaN;
snap.V_min_pu(:) = NaN;
det = ai.ai_detect_event(snap, ai.ai_supervisor_defaults());
testCase.verifyEmpty(det.trigger_indices);
end

function test_each_trigger_carries_its_own_reason(testCase)
% Different triggers fire on different criteria, so one shared label would
% misattribute every trigger after the first.
snap = plain_snap(80);
snap.rocof_Hz_s(5:10) = -0.9;      % first emergency: rate of change
snap.V_min_pu(40:50) = 0.88;       % second emergency: voltage
det = ai.ai_detect_event(snap, ai.ai_supervisor_defaults());
testCase.verifyEqual(numel(det.trigger_indices), 2);
testCase.verifyEqual(det.trigger_reasons, ["spec:rocof" "spec:vmin"]);
testCase.verifyEqual(det.first_reason, "spec:rocof");
end

function test_production_rule_fires_on_severity_and_hysteresis(testCase)
snap = plain_snap(20);
snap.S(5:12) = 0.80;
det = ai.ai_detect_event(snap, ...
    ai.ai_supervisor_defaults(struct('trigger_rule', "production")));
testCase.verifyEqual(det.first_index, 7);
testCase.verifyTrue(all(det.state(7:12) == "augmenting"));
end

function test_production_rule_ignores_severity_below_gamma_on(testCase)
snap = plain_snap(20);
snap.S(5:12) = 0.60;   % above gamma_off, below gamma_on: not a demand
det = ai.ai_detect_event(snap, ...
    ai.ai_supervisor_defaults(struct('trigger_rule', "production")));
testCase.verifyEmpty(det.trigger_indices);
end

function test_demand_window_is_reported_separately_from_the_trigger(testCase)
% TRIGGER is the instant a decision is due; DEMAND is the window it is due
% over. The window is held for dwell_off_s after the raw condition clears, so
% it deliberately outlives the condition -- that latch is what stops a
% re-arming supervisor from firing again on the same emergency.
snap = plain_snap(20);
snap.rocof_Hz_s(5:10) = -0.9;
det = ai.ai_detect_event(snap, ai.ai_supervisor_defaults());
testCase.verifyEqual(find(det.demand, 1), 7);
testCase.verifyFalse(any(det.demand(1:6)));
testCase.verifyTrue(det.demand(11), 'The latch must hold past the raw demand.');
testCase.verifyEqual(numel(det.trigger_indices), 1);
end

function test_unknown_trigger_rule_is_refused(testCase)
% ai_supervisor_defaults refuses a bad rule first, so this drives the
% detection branch directly: the guard must exist in both places, because a
% caller may hand-build an options struct.
snap = plain_snap(5);
opts = ai.ai_supervisor_defaults();
opts.trigger_rule = "bogus";
testCase.verifyError(@() ai.ai_detect_event(snap, opts), ...
    'ai:ai_detect_event:badTriggerRule');
end

function test_defaults_refuse_a_bad_trigger_rule(testCase)
testCase.verifyError(@() ai.ai_supervisor_defaults( ...
    struct('trigger_rule', "bogus")), 'ai:ai_supervisor_defaults:badTriggerRule');
end

function test_defaults_refuse_a_ceiling_above_two(testCase)
% Above two forming converters the stability argument the design rests on no
% longer holds, so the ceiling is not a free parameter.
testCase.verifyError(@() ai.ai_supervisor_defaults( ...
    struct('max_gfm_buses', 3)), 'ai:ai_supervisor_defaults:badMaxGfmBuses');
end

function test_defaults_refuse_an_unknown_option_name(testCase)
testCase.verifyError(@() ai.ai_supervisor_defaults( ...
    struct('not_an_option', 1)), 'ai:ai_supervisor_defaults:unknownOption');
end

% =========================================================================
% feature extraction
% =========================================================================
function test_complex_healthy_profile_is_reduced_to_magnitude(testCase)
% The cache stores V0_per_bus as a PHASOR. J_V is defined on voltage
% magnitudes, so a phasor must be reduced before it is differenced -- and a
% complex value that survives as far as the payload makes jsonencode refuse
% the request outright. Both halves are asserted, because the second is how
% this was found against a real cache.
state = raw_state();
state.healthy_V = exp(1i * [0; -0.05; -0.08; -0.12; -0.06]);
snap = ai.snapshot_from_state(state, ai.ai_supervisor_defaults());
testCase.verifyTrue(isreal(snap.healthy_V));
feat = ai.ai_extract_features(snap, 1:3);
testCase.verifyTrue(isreal([feat.buses.V_drop_pu]));
testCase.verifyGreaterThan(feat.buses(3).V_drop_pu, 0.09);
[~, payload] = ai.ai_build_prompt(feat, ai.ai_supervisor_defaults(), struct());
back = jsondecode(payload);
testCase.verifyTrue(isnumeric([back.candidates.escr]));
testCase.verifyTrue(isreal([back.candidates.escr]));
testCase.verifyEqual(sort([back.candidates.bus]), [2 3 6 8]);
end

function test_features_rank_by_ascending_escr(testCase)
feat = ai.ai_extract_features(feature_snap(), 1:3);
testCase.verifyEqual(feat.rank_by_escr, [3 1 2 4]);
testCase.verifyEqual(feat.buses(3).bus_id, 6);
end

function test_features_exclude_forming_buses_from_the_rule_primary(testCase)
snap = feature_snap();
snap.modes_ibr(3, :) = {'gfm', 'gfm', 'gfm'};
snap.escr(3, :) = 1.65;   % still the weakest, but already forming
feat = ai.ai_extract_features(snap, 1:3);
testCase.verifyEqual(feat.gfm_indices, 3);
testCase.verifyNotEqual(feat.rule_primary, 3);
testCase.verifyEqual(feat.rule_primary, 1);
end

function test_features_use_the_window_median_not_the_spike(testCase)
% One bad sample inside the window must not be what the ranking rests on.
snap = feature_snap();
snap.escr(1, 2) = 0.01;
feat = ai.ai_extract_features(snap, 1:3);
testCase.verifyGreaterThan(feat.buses(1).escr_median, 1.0);
testCase.verifyEqual(feat.buses(1).escr_min, 0.01);
end

function test_features_report_reconstructed_rocof(testCase)
snap = feature_snap();
snap.rocof_source(2) = "finite_difference";
feat = ai.ai_extract_features(snap, 1:3);
testCase.verifyTrue(any(contains(feat.notes, "finite differences")));
end

% =========================================================================
% reply validation
% =========================================================================
function test_parse_accepts_a_conforming_reply(testCase)
feat = base_feat();
txt = ['{"action":"SWITCH_MODE","target_buses":[6],"target_mode":"GFM",' ...
    '"confidence":0.95,"primary_reason":"Bus 6 has the lowest ESCR."}'];
[dec, ok, why] = ai.ai_parse_decision(txt, feat, ai.ai_supervisor_defaults());
testCase.verifyTrue(ok, why);
testCase.verifyEqual(dec.target_buses, 6);
testCase.verifyEqual(dec.source, "LLM");
end

function test_parse_rejects_more_than_two_buses(testCase)
% The single most important refusal in this file. Three forming converters is
% the circulating-current condition the ceiling exists to prevent, and a
% permissive parser would apply it literally.
feat = base_feat();
txt = ['{"action":"SWITCH_MODE","target_buses":[2,3,6],"target_mode":"GFM",' ...
    '"confidence":0.9,"primary_reason":"all of them"}'];
[~, ok, why] = ai.ai_parse_decision(txt, feat, ai.ai_supervisor_defaults());
testCase.verifyFalse(ok);
testCase.verifySubstring(why, "ceiling");
end

function test_parse_rejects_a_bus_that_is_not_a_candidate(testCase)
feat = base_feat();
txt = ['{"action":"SWITCH_MODE","target_buses":[9],"target_mode":"GFM",' ...
    '"confidence":0.9,"primary_reason":"bus 9"}'];
[~, ok, ~] = ai.ai_parse_decision(txt, feat, ai.ai_supervisor_defaults());
testCase.verifyFalse(ok);
end

function test_parse_rejects_a_bus_that_is_already_forming(testCase)
feat = base_feat();
feat.gfm_indices = 3;
txt = ['{"action":"SWITCH_MODE","target_buses":[6],"target_mode":"GFM",' ...
    '"confidence":0.9,"primary_reason":"bus 6"}'];
[~, ok, why] = ai.ai_parse_decision(txt, feat, ai.ai_supervisor_defaults());
testCase.verifyFalse(ok);
testCase.verifySubstring(why, "already forming");
end

function test_parse_rejects_confidence_outside_the_unit_interval(testCase)
feat = base_feat();
txt = ['{"action":"SWITCH_MODE","target_buses":[6],"target_mode":"GFM",' ...
    '"confidence":1.4,"primary_reason":"bus 6"}'];
[~, ok, ~] = ai.ai_parse_decision(txt, feat, ai.ai_supervisor_defaults());
testCase.verifyFalse(ok);
end

function test_parse_rejects_an_empty_target_list(testCase)
feat = base_feat();
txt = ['{"action":"SWITCH_MODE","target_buses":[],"target_mode":"GFM",' ...
    '"confidence":0.9,"primary_reason":"none"}'];
[~, ok, ~] = ai.ai_parse_decision(txt, feat, ai.ai_supervisor_defaults());
testCase.verifyFalse(ok);
end

function test_parse_rejects_non_json(testCase)
feat = base_feat();
[~, ok, ~] = ai.ai_parse_decision("I would choose bus 6.", feat, ...
    ai.ai_supervisor_defaults());
testCase.verifyFalse(ok);
end

function test_parse_strips_a_markdown_fence_and_records_it(testCase)
feat = base_feat();
txt = "```json" + newline + ...
    "{""action"":""SWITCH_MODE"",""target_buses"":[6],""target_mode"":""GFM""," + ...
    """confidence"":0.9,""primary_reason"":""bus 6""}" + newline + "```";
[dec, ok, why] = ai.ai_parse_decision(txt, feat, ai.ai_supervisor_defaults());
testCase.verifyTrue(ok, why);
testCase.verifyTrue(any(contains(dec.warnings, "fence")));
end

function test_parse_maps_a_device_id_and_records_the_repair(testCase)
feat = base_feat();
txt = ['{"action":"SWITCH_MODE","target_buses":["IBR6"],"target_mode":"GFM",' ...
    '"confidence":0.9,"primary_reason":"IBR6"}'];
[dec, ok, why] = ai.ai_parse_decision(txt, feat, ai.ai_supervisor_defaults());
testCase.verifyTrue(ok, why);
testCase.verifyEqual(dec.target_buses, 6);
testCase.verifyTrue(any(contains(dec.warnings, "device id")));
end

function test_parse_rejects_a_repeated_bus(testCase)
feat = base_feat();
txt = ['{"action":"SWITCH_MODE","target_buses":[6,6],"target_mode":"GFM",' ...
    '"confidence":0.9,"primary_reason":"bus 6 twice"}'];
[~, ok, ~] = ai.ai_parse_decision(txt, feat, ai.ai_supervisor_defaults());
testCase.verifyFalse(ok);
end

% =========================================================================
% fallback selector
% =========================================================================
function test_fallback_names_the_weakest_bus(testCase)
dec = ai.ai_fallback_selector(base_feat(), ai.ai_supervisor_defaults(), "");
testCase.verifyEqual(dec.target_buses, 6);
testCase.verifyEqual(dec.source, "FALLBACK_RULE");
testCase.verifyEqual(dec.action, "SWITCH_MODE");
end

function test_fallback_spends_the_second_bus_only_on_a_severe_collapse(testCase)
opts = ai.ai_supervisor_defaults();
feat = base_feat();
feat.V_min_pu = 0.95;                 % not severe
testCase.verifyEqual(numel(ai.ai_fallback_selector(feat, opts, "").target_buses), 1);
feat.V_min_pu = 0.75;                 % severe
testCase.verifyEqual(numel(ai.ai_fallback_selector(feat, opts, "").target_buses), 2);
end

function test_fallback_never_exceeds_the_ceiling(testCase)
opts = ai.ai_supervisor_defaults(struct('max_gfm_buses', 1));
feat = base_feat();
feat.V_min_pu = 0.60;
testCase.verifyEqual(numel(ai.ai_fallback_selector(feat, opts, "").target_buses), 1);
end

function test_fallback_reports_no_action_when_everything_is_forming(testCase)
feat = base_feat();
feat.gfm_indices = 1:4;
feat.rank_by_escr = [3 1 2 4];
dec = ai.ai_fallback_selector(feat, ai.ai_supervisor_defaults(), "");
testCase.verifyEqual(dec.action, "NO_ACTION");
testCase.verifyEmpty(dec.target_buses);
end

function test_fallback_lowers_confidence_when_escr_is_unavailable(testCase)
% The real shape of "no ESCR": the field exists and is NaN, because a cache
% without agsi_reference still yields a snapshot. Missing fields would be a
% different failure and would be caught by the selector's own indexing.
opts = ai.ai_supervisor_defaults();
feat = base_feat();
with_escr = ai.ai_fallback_selector(feat, opts, "").confidence;
feat.escr_source = "unavailable";
for k = 1:numel(feat.buses)
    feat.buses(k).escr_median = NaN;
    feat.buses(k).escr_min = NaN;
    feat.buses(k).escr_max = NaN;
    feat.buses(k).escr_end = NaN;
end
without = ai.ai_fallback_selector(feat, opts, "");
testCase.verifyEqual(without.confidence, 0.30);
testCase.verifyTrue(any(contains(without.warnings, "ESCR unavailable")));
testCase.verifyGreaterThan(with_escr, without.confidence);
end

% =========================================================================
% apply
% =========================================================================
function test_apply_updates_the_shadow_table_and_logs(testCase)
mt = base_mode_table();
dec = decide([6], 0.9);
[mt, entry] = ai.ai_apply_decision(mt, dec, 1.0, ai.ai_supervisor_defaults());
testCase.verifyTrue(entry.applied);
testCase.verifyEqual(mt.modes{3}, 'gfm');
testCase.verifyEqual(numel(mt.history), 1);
testCase.verifyEqual(mt.modes{1}, 'gfl', 'Other buses must be untouched.');
end

function test_apply_refuses_a_bus_already_forming(testCase)
mt = base_mode_table();
mt.modes{3} = 'gfm';
[~, entry] = ai.ai_apply_decision(mt, decide([6], 0.9), 1.0, ...
    ai.ai_supervisor_defaults());
testCase.verifyFalse(entry.applied);
testCase.verifySubstring(entry.reason, "already forming");
end

function test_apply_refuses_above_the_ceiling(testCase)
mt = base_mode_table();
[~, entry] = ai.ai_apply_decision(mt, decide([2 3 6], 0.9), 1.0, ...
    ai.ai_supervisor_defaults());
testCase.verifyFalse(entry.applied);
testCase.verifySubstring(entry.reason, "ceiling");
end

function test_apply_refuses_a_bus_with_no_converter(testCase)
mt = base_mode_table();
[~, entry] = ai.ai_apply_decision(mt, decide([9], 0.9), 1.0, ...
    ai.ai_supervisor_defaults());
testCase.verifyFalse(entry.applied);
end

function test_apply_records_a_no_action_verdict_without_changing_modes(testCase)
mt = base_mode_table();
dec = decide([], 1.0);
dec.action = "NO_ACTION";
[mt, entry] = ai.ai_apply_decision(mt, dec, 1.0, ai.ai_supervisor_defaults());
testCase.verifyFalse(entry.applied);
testCase.verifyTrue(all(strcmp(mt.modes, 'gfl')));
end

% =========================================================================
% response-body decoding
% =========================================================================
function test_decode_reads_a_parsed_body(testCase)
body = struct('choices', struct('message', struct('content', 'ok')));
[c, why] = ai.ai_decode_chat_body(body);
testCase.verifyEqual(c, "ok");
testCase.verifyEqual(why, "");
end

function test_decode_tolerates_the_gateway_sse_terminator(testCase)
% Recorded verbatim from the first real request through this client. The
% gateway answers a NON-streaming request with a complete JSON object followed
% by "data: [DONE]", which is invalid JSON. Decoding that body is the whole
% reason this function is separate from ai.ai_call_llm.
body = ['{"id":"0217903241110613","object":"chat.completion",' ...
    '"model":"deepseek-v4.1-flash","choices":[{"index":0,' ...
    '"finish_reason":"stop","message":{"role":"assistant","content":"ok",' ...
    '"reasoning_content":"The user wants exactly ok."}}]}data: [DONE]'];
[c, why] = ai.ai_decode_chat_body(body);
testCase.verifyEqual(why, "");
testCase.verifyEqual(c, "ok");
end

function test_decode_still_works_without_the_terminator(testCase)
body = ['{"choices":[{"message":{"content":"ok"}}]}'];
[c, why] = ai.ai_decode_chat_body(body);
testCase.verifyEqual(why, "");
testCase.verifyEqual(c, "ok");
end

function test_decode_refuses_a_real_event_stream(testCase)
% A genuine stream must be refused, not partly decoded: reading its first
% frame would hide a transport problem rather than report one.
body = ['data: {"choices":[{"delta":{"content":"o"}}]}', newline, ...
    'data: {"choices":[{"delta":{"content":"k"}}]}'];
[c, why] = ai.ai_decode_chat_body(body);
testCase.verifyEqual(c, "");
testCase.verifySubstring(why, "event stream");
end

function test_decode_reports_an_error_object(testCase)
body = '{"error":{"message":"invalid api key","type":"auth_error"}}';
[c, why] = ai.ai_decode_chat_body(body);
testCase.verifyEqual(c, "");
testCase.verifySubstring(why, "error object");
end

function test_decode_reports_a_missing_choices_array(testCase)
[c, why] = ai.ai_decode_chat_body('{"id":"x"}');
testCase.verifyEqual(c, "");
testCase.verifySubstring(why, "no choices");
end

function test_decode_reports_empty_content(testCase)
body = '{"choices":[{"message":{"content":""}}]}';
[c, why] = ai.ai_decode_chat_body(body);
testCase.verifyEqual(c, "");
testCase.verifySubstring(why, "empty");
end

% =========================================================================
% the whole loop, offline
% =========================================================================
function test_full_loop_selects_the_weakest_bus_with_no_network(testCase)
tmp = write_synthetic_cache();
cleanup = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>

report = ai_supervisor("synth", 'cache_dir', tmp, ...
    'force_fallback', true, 'verbose', false);

testCase.verifyGreaterThan(numel(report.decisions), 0, ...
    'The synthetic transient must produce at least one decision.');
d = report.decisions(1);
testCase.verifyEqual(d.source, "FALLBACK_RULE");
testCase.verifyEqual(d.target_buses, 6);
testCase.verifyLessThanOrEqual(numel(d.target_buses), 2);
testCase.verifyTrue(d.applied);
testCase.verifyEqual(report.mode_table.modes{3}, 'gfm', ...
    'Bus 6 is the weakest candidate and must be the one switched.');
testCase.verifyEqual(report.mode_table.modes{4}, 'gfl', ...
    'Bus 8 is not selected at any trigger in this fixture.');
end

function test_full_loop_does_not_reselect_its_own_commitment(testCase)
% The second emergency has the same weakest bus as the first. The snapshot
% still records that bus as grid-following, because the snapshot describes the
% ENGINE's run and the supervisor never steered it -- so without the committed
% buses being fed back in, the loop would spend its second selection
% re-selecting a bus it had already switched, and leave the emergency
% unanswered. This is the loop being closed, and it is the one behaviour that
% only appears on the second trigger.
tmp = write_synthetic_cache();
cleanup = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>

report = ai_supervisor("synth", 'cache_dir', tmp, ...
    'force_fallback', true, 'verbose', false);

testCase.verifyGreaterThanOrEqual(numel(report.decisions), 2, ...
    'The fixture holds two separate emergencies.');
testCase.verifyEqual(report.decisions(1).target_buses, 6);
testCase.verifyNotEqual(report.decisions(2).target_buses, 6, ...
    'Bus 6 was committed at the first trigger and must not be offered again.');
testCase.verifyEqual(report.decisions(2).target_buses, 2);
% The two commitments together, and nothing else, are what the table holds.
testCase.verifyEqual(report.mode_table.modes, ...
    {'gfm'; 'gfl'; 'gfm'; 'gfl'});
testCase.verifyEqual(numel(report.mode_table.history), ...
    numel(report.decisions));
end

function test_mode_table_names_the_ibr_devices_not_every_device(testCase)
% modes is aligned with ibr_buses, so indexing the full device list against it
% labels bus 2 as SG1. Costly to notice by eye and easy to assert.
tmp = write_synthetic_cache();
cleanup = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>
report = ai_supervisor("synth", 'cache_dir', tmp, ...
    'force_fallback', true, 'verbose', false);
testCase.verifyEqual(report.mode_table.ibr_buses, [2 3 6 8]);
testCase.verifyEqual(report.mode_table.device_ids, ...
    {'IBR2', 'IBR3', 'IBR6', 'IBR8'});
end

function test_features_exclude_a_supervisor_committed_bus(testCase)
snap = feature_snap();
feat = ai.ai_extract_features(snap, 1:3, 6);
testCase.verifyEqual(feat.committed_indices, 3);
testCase.verifyEqual(feat.gfm_indices, 3);
testCase.verifyNotEqual(feat.rule_primary, 3);
testCase.verifyEqual(feat.buses(3).mode, "gfm");
testCase.verifyTrue(any(contains(feat.notes, "committed by this supervisor")));
end

function test_full_loop_is_deterministic(testCase)
tmp = write_synthetic_cache();
cleanup = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>

a = ai_supervisor("synth", 'cache_dir', tmp, 'force_fallback', true, ...
    'verbose', false);
b = ai_supervisor("synth", 'cache_dir', tmp, 'force_fallback', true, ...
    'verbose', false);
testCase.verifyEqual(a.decisions(1).target_buses, b.decisions(1).target_buses);
testCase.verifyEqual(a.decisions(1).primary_reason, b.decisions(1).primary_reason);
end

function test_full_loop_survives_a_missing_cache_with_a_named_error(testCase)
testCase.verifyError(@() ai_supervisor("no_such_scenario", ...
    'cache_dir', tempname, 'force_fallback', true, 'verbose', false), ...
    'ai:snapshot_from_cache:cacheMissing');
end

function test_both_trigger_rules_run_on_the_same_cache(testCase)
% The switch exists so the two criteria can be compared on identical physics.
% Each must produce its own verdict through the same downstream pipeline.
tmp = write_synthetic_cache();
cleanup = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>

spec = ai_supervisor("synth", 'cache_dir', tmp, 'force_fallback', true, ...
    'verbose', false, 'trigger_rule', "spec");
prod = ai_supervisor("synth", 'cache_dir', tmp, 'force_fallback', true, ...
    'verbose', false, 'trigger_rule', "production");
testCase.verifyEqual(spec.trigger_rule, "spec");
testCase.verifyEqual(prod.trigger_rule, "production");
testCase.verifyGreaterThan(numel(spec.decisions), 0);
testCase.verifyGreaterThan(numel(prod.decisions), 0);
end

function test_unknown_option_is_refused(testCase)
testCase.verifyError(@() ai_supervisor("synth", 'not_an_option', 1), ...
    'ai_supervisor:unknownOption');
end

function test_missing_api_key_is_refused_before_any_request(testCase)
% The key is never read from a file, so an unset variable is the normal state
% on a fresh machine. It must be refused by name, and refused BEFORE a request
% goes out -- an attempt count of 0 is what proves nothing was sent.
env = 'AI_SUPERVISOR_UNSET_KEY_FOR_TEST';
testCase.verifyEmpty(getenv(env), ...
    'This test needs the variable to be unset in the environment.');
opts = ai.ai_supervisor_defaults(struct('api_key_env', string(env)));
resp = ai.ai_call_llm("system", "{}", opts);
testCase.verifyFalse(resp.ok);
testCase.verifyEqual(resp.error_id, "ai:ai_call_llm:missingApiKey");
testCase.verifyEqual(resp.attempts, 0);
end

function test_request_body_never_carries_the_api_key(testCase)
% The key belongs in the Authorization header and nowhere else. A body that
% echoed it would be logged, cached, and possibly published in a report.
env = 'AI_SUPERVISOR_KEY_PLACEMENT_TEST';
setenv(env, 'secret-probe-value');
restore = onCleanup(@() setenv(env, '')); %#ok<NASGU>
opts = ai.ai_supervisor_defaults(struct( ...
    'api_key_env', string(env), ...
    'endpoint', "http://127.0.0.1:1/v1/chat/completions", ...
    'timeout_s', 1, 'max_retries', 0));
resp = ai.ai_call_llm("system", "{}", opts);
% Port 1 refuses immediately, so no service is involved; the body was built
% and is inspectable regardless of how the send turns out.
testCase.verifyFalse(contains(resp.request_json, 'secret-probe-value'));
testCase.verifyFalse(resp.ok, 'A refused connection must not report success.');
end

% =========================================================================
% request construction
%
% Every assertion below stands for a live run that failed. Each of these
% mistakes builds without complaint and only shows up as a server-side error
% that names something else entirely, so they are pinned here instead.
% =========================================================================
function test_request_headers_are_a_row_not_a_column(testCase)
% A [2 1] column of HeaderField builds fine and then makes send() throw
% MATLAB:catenate:dimensionMismatch. That error names concatenation, not the
% headers, so it sends a reader to the wrong file.
[req, ~] = ai.ai_build_request("sys", "user", "k", ai.ai_supervisor_defaults());
testCase.verifyEqual(size(req.Header, 1), 1, ...
    'Headers must be a single row; a column breaks send() before any packet leaves.');
testCase.verifyGreaterThanOrEqual(numel(req.Header), 2);
end

function test_request_body_is_a_struct_not_a_pre_encoded_string(testCase)
% The body must be handed over as a struct for MATLAB to encode ONCE. Given
% Content-Type: application/json, a char body is encoded as a JSON *string* --
% the gateway then reports HTTP 400 "Missing model", because what arrived was
% "\"{\\\"model\\\":...}\"" and not an object.
[req, ~] = ai.ai_build_request("sys", "user", "k", ai.ai_supervisor_defaults());
testCase.verifyFalse(ischar(req.Body.Data), ...
    'A char body is re-encoded as a JSON string, not passed through.');
testCase.verifyFalse(isstring(req.Body.Data));
testCase.verifyTrue(isstruct(req.Body.Data));
testCase.verifyTrue(isfield(req.Body.Data, 'model'));
end

function test_logged_request_json_is_what_the_body_encodes(testCase)
% resp.request_json is kept for provenance. If it were assembled separately
% from the body, it could describe a request that was never sent.
[req, js] = ai.ai_build_request("sys", "user", "k", ai.ai_supervisor_defaults());
testCase.verifyEqual(js, string(jsonencode(req.Body.Data)));
end

function test_request_carries_the_bearer_token_and_a_json_content_type(testCase)
[req, ~] = ai.ai_build_request("sys", "user", "k", ai.ai_supervisor_defaults());
names = string({req.Header.Name});
testCase.verifyTrue(any(names == "Authorization"));
testCase.verifyTrue(any(names == "Content-Type"));
auth = req.Header(names == "Authorization");
testCase.verifyEqual(string(auth.Value), "Bearer k");
end

function test_request_payload_asks_for_a_json_object(testCase)
% The prompt contract is a JSON object verdict. Requesting it from the server
% is what keeps the reply parseable without prose-stripping heuristics.
[~, js] = ai.ai_build_request("sys", "user", "k", ai.ai_supervisor_defaults());
d = jsondecode(js);
testCase.verifyEqual(string(d.response_format.type), "json_object");
testCase.verifyEqual(string(d.reasoning_effort), "high");
testCase.verifyEqual(numel(d.messages), 2);
% jsondecode returns a struct array here, not a cell.
testCase.verifyEqual(string(d.messages(1).role), "system");
testCase.verifyEqual(string(d.messages(2).role), "user");
end

function tmp = write_synthetic_cache()
%WRITE_SYNTHETIC_CACHE  Save the fixture under the name the reader expects.
tmp = tempname;
mkdir(tmp);
result = synthetic_result(); %#ok<NASGU>
save(fullfile(tmp, 'synth.mat'), 'result', '-v7');
end

% =========================================================================
% fixtures
% =========================================================================
function snap = plain_snap(n)
%PLAIN_SNAP  The minimum ai_detect_event reads.
snap = struct();
snap.t = (0:n-1) * 0.05;
snap.n = n;
snap.rocof_Hz_s = zeros(1, n);
snap.V_min_pu = ones(1, n);
snap.S = zeros(1, n);
end

function snap = feature_snap()
%FEATURE_SNAP  A four-IBR snapshot with bus 6 the weakest, as the case is.
n = 3;
snap = struct();
snap.t = [0 0.05 0.10];
snap.n = n;
snap.bus_ids = (1:14)';
snap.device_ids = {'SG1', 'IBR2', 'IBR3', 'IBR6', 'IBR8'};
snap.ibr_device_indices = [2 3 4 5];
snap.ibr_bus_ids = [2 3 6 8];
snap.ibr_bus_positions = [2 3 6 8];
snap.V_bus_pu = ones(14, n);
snap.V_bus_pu(6, :) = 0.90;
snap.V_min_pu = 0.90 * ones(1, n);
snap.V_ibr_pu = repmat([0.97; 0.98; 0.90; 0.99], 1, n);
snap.f_coi_Hz = [60.0 59.4 59.1];
snap.rocof_Hz_s = [-0.5 -3.0 -0.2];
snap.rocof_source = ["analytic" "analytic" "analytic"];
snap.S = [0.3 0.8 0.5];
snap.J_V = zeros(4, n);
snap.J_f = zeros(1, n);
snap.escr = repmat([2.2; 2.6; 1.65; 2.9], 1, n);
snap.escr_source = "provided";
snap.modes_ibr = repmat({'gfl'}, 4, n);
snap.healthy_V = ones(5, 1);
snap.healthy_bus_ids = (1:5)';
end

function feat = base_feat()
%BASE_FEAT  A conforming feature set; bus 6 is the weakest at ESCR 1.65.
feat = struct();
feat.buses = [ ...
    feat_bus(2, "IBR2", 2.20, 0.97, 0.03), ...
    feat_bus(3, "IBR3", 2.60, 0.98, 0.02), ...
    feat_bus(6, "IBR6", 1.65, 0.93, 0.07), ...
    feat_bus(8, "IBR8", 2.90, 0.99, 0.01)];
feat.gfm_indices = [];
feat.rank_by_escr = [3 1 2 4];
feat.rank_by_vdrop = [3 1 2 4];
feat.rule_primary = 3;
feat.escr_source = "provided";
feat.notes = {};
feat.t_start_s = 0;
feat.t_end_s = 0.10;
feat.n_samples = 3;
feat.f0_Hz = 60.0;
feat.f_end_Hz = 59.1;
feat.f_nadir_Hz = 59.0;
feat.rocof_peak_Hz_s = -3.0;
feat.rocof_end_Hz_s = -0.2;
feat.rocof_source = "analytic";
feat.V_min_pu = 0.90;
feat.t_vmin_s = 0.05;
end

function b = feat_bus(id, dev, escr, v, drop)
b = struct('bus_id', id, 'device_id', dev, 'mode', "gfl", ...
    'escr_median', escr, 'escr_min', escr*0.95, 'escr_max', escr*1.05, ...
    'escr_end', escr, 'V_median_pu', v, 'V_min_pu', v - 0.01, ...
    'V_drop_pu', drop);
end

function mt = base_mode_table()
mt = struct();
mt.device_ids = {'SG1', 'IBR2', 'IBR3', 'IBR6', 'IBR8'};
mt.ibr_buses = [2 3 6 8];
mt.modes = repmat({'gfl'}, 4, 1);
mt.history = struct([]);
end

function dec = decide(buses, conf)
dec = struct('action', "SWITCH_MODE", 'target_buses', buses, ...
    'target_mode', "GFM", 'confidence', conf, ...
    'primary_reason', "test", 'warnings', strings(1,0), 'source', "LLM");
end

function result = synthetic_result()
%SYNTHETIC_RESULT  A cached run: SG plus four IBRs, bus 6 hit hardest.
%   Not a simulation. It exists so the whole supervisor pipeline can be
%   exercised with no network and no 60 MB cache on disk.
n = 61;
t = (0:n-1) * 0.05;
result = struct();
result.t = t;
result.bus_ids = (1:14)';
result.device_ids = {'SG1', 'IBR2', 'IBR3', 'IBR6', 'IBR8'};
result.device_bus_ids = [1 2 3 6 8];
result.device_modes_history = repmat({'gfl'}, 5, n);
result.device_modes_history(1, :) = {'sg'};

% TWO separate emergencies, not one long one. The gap between them is what
% makes the loop re-arm, which is the only way the second decision can show
% whether the supervisor remembers what it committed at the first.
emergency = (t >= 0.5 & t < 0.95) | (t >= 2.0 & t <= 2.2);
V = ones(14, n);
V(1, emergency) = 0.90;
V(2, emergency) = 0.95;
V(3, emergency) = 0.95;
V(6, emergency) = 0.88;
V(8, emergency) = 0.97;
result.bus_voltage_magnitude = V;

f = 60 * ones(1, n);
f(emergency) = 59.0;
result.coi_frequency_Hz = f;

ar = struct();
ar.device_indices = [2 3 4 5];
ar.rocof_Hz_s = zeros(1, n);
ar.rocof_Hz_s(t >= 0.5 & t < 0.75) = -3.0;
ar.rocof_Hz_s(t >= 2.0 & t <= 2.2) = -3.0;
ar.rocof_method = 'synthetic_fixture';
ar.base_classification = 'SYNTHETIC_FIXTURE';
scr = repmat([2.2 2.6 1.65 2.9], n, 1);
ar.scr = scr;
result.agsi_reference = ar;

result.metadata = struct();
result.metadata.device_build = struct();
result.metadata.device_build.bus_ids = [1 2 3 6 8]';
% A PHASOR, exactly as build_mixed_resource_devices publishes it. The fixture
% is complex on purpose: a real-valued stand-in would let the reduction to
% magnitude go untested, and the payload only breaks on real data.
result.metadata.device_build.V0_per_bus = ...
    exp(1i * [0; -0.05; -0.08; -0.12; -0.06]);
end

function state = raw_state()
%RAW_STATE  A minimal inputs struct for ai.snapshot_from_state.
n = 3;
state = struct();
state.t = [0 0.05 0.10];
state.V_bus_pu = ones(14, n);
state.V_bus_pu(6, :) = 0.90;
state.bus_ids = (1:14)';
state.device_bus_ids = [1 2 3 6 8];
state.device_ids = {'SG1', 'IBR2', 'IBR3', 'IBR6', 'IBR8'};
state.device_modes = repmat({'gfl'}, 5, n);
state.device_modes(1, :) = {'sg'};
state.ibr_device_indices = [2 3 4 5];
state.f_coi_Hz = [60.0 59.4 59.1];
state.rocof_Hz_s = [-0.5 -3.0 -0.2];
state.healthy_bus_ids = [1 2 3 6 8]';
state.healthy_V = ones(5, 1);
state.escr = repmat([2.2; 2.6; 1.65; 2.9], 1, n);
end
