function tests=test_ne39_voltage_observation()
%TEST_NE39_VOLTAGE_OBSERVATION ตรวจเวลาซ้ำที่ event/recovery/censoring.
tests=functiontests(localfunctions);
end

function setupOnce(tc)
p=path; tc.addTeardown(@()path(p)); pf_init_paths();
end

function test_event_jump_duration_and_recovery(tc)
t=[0 1 1 2 3 4]; vm=[1 1 1.2 1.15 1 1;1 .8 .8 1 1 1.2];
b=struct('v_min',.9,'v_max',1.1);
a=stability.ne39_voltage_observation(t,vm,[8;35],b);
tc.verifyTrue(a.any_excursion); tc.verifyFalse(a.final_all_in_band);
tc.verifyEqual(a.outside_duration_left_hold_s,[2;1]);
tc.verifyEqual(numel(a.excursions),3);
r=a.excursions(1); tc.verifyEqual(r.entry_bracket_s,[1 1]);
tc.verifyEqual(r.recovery_sample_s,3); tc.verifyEqual(r.exit_bracket_s,[2 3]);
tc.verifyEqual(r.duration_left_hold_s,2);
r=a.excursions(3); tc.verifyTrue(r.right_censored);
tc.verifyTrue(isnan(r.recovery_sample_s)); tc.verifyEqual(r.duration_left_hold_s,0);
end

function test_no_excursion_and_boundary_inclusive(tc)
a=stability.ne39_voltage_observation([0 1],[.9 1.1],8,struct('v_min',.9,'v_max',1.1));
tc.verifyFalse(a.any_excursion); tc.verifyTrue(a.final_all_in_band);
tc.verifyEmpty(a.excursions); tc.verifyEqual(a.outside_duration_left_hold_s,0);
tc.verifyEqual(a.final_in_band_since_sample_s,0);
tc.verifyEqual(a.final_in_band_sampled_span_s,1);
end

function test_invalid_policy_rejected(tc)
a=struct('status','PASS','complete',true,'nonvoltage_status','PASS', ...
    'voltage_reference',struct('pass',true));
thrown=false;
try, stability.ne39_snapshot_policy(a,"ignore_everything"); catch, thrown=true; end
tc.verifyTrue(thrown);
a.complete=false; tc.verifyFalse(stability.ne39_snapshot_policy(a,"observe_voltage"));
end
