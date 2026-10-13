function tests=test_ne39_weighted_supervisor()
%TEST_NE39_WEIGHTED_SUPERVISOR  Opt-in four-term severity and its actual gate.
%   Controlled decision tests use FIXED weights/bases and a rate-only change.
%   They prove the canonical weighted sample drives the policy release decision
%   (release true -> hold/reset after the baseline dwell), not only the formula.
%   These are controlled decision tests, NOT physical transition certificates.
tests=functiontests(localfunctions);
end

function setupOnce(tc)
p=path; tc.addTeardown(@()path(p));
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% ---------------------------------------------------------------- helpers ----
function [p,terms]=policy_and_baseline()
% Fixed design config from the approved supervisor plan section 5.
p=struct('si_on',.65,'si_off',.35,'rocof_max',1,'rocov_max',1, ...
    'v_min',.9,'v_max',1.1,'f_min',59.5,'f_max',60.5, ...
    'prediction_horizon',.25,'on_dwell',.1,'off_dwell',1,'per_device_release',true);
terms=struct('V_pu',1,'V_ref_pu',1,'f_hz',60,'rocof_hz_s',0, ...
    'rocov_pu_s',0,'f0_Hz',60);
end

function w=fixed_weights()
w=[.35 .35 .15 .15];
end

function b=fixed_bases()
b=[.10 .50 1 1];
end

function sample=sample_from(terms,severity)
sample=struct('severity',severity,'v_pu',terms.V_pu,'f_hz',terms.f_hz, ...
    'rocof_hz_s',terms.rocof_hz_s,'rocov_pu_s',terms.rocov_pu_s,'valid',true);
end

% -------------------------------------------------------- formula + clip ----
function test_weighted_severity_four_terms(tc)
t=struct('V_pu',1.05,'V_ref_pu',1,'f_hz',60.25,'rocof_hz_s',-.4, ...
    'rocov_pu_s',.3,'f0_Hz',60);
[si,c]=stability.ne39_weighted_severity(t,fixed_weights(),fixed_bases());
% JV=.5, Jf=.5, JROCOF=.4, JROCOV=.3
tc.verifyEqual(c.Jv,.5,'AbsTol',1e-12);
tc.verifyEqual(c.Jf,.5,'AbsTol',1e-12);
tc.verifyEqual(c.Jrocof,.4,'AbsTol',1e-12);
tc.verifyEqual(c.Jrocov,.3,'AbsTol',1e-12);
tc.verifyEqual(si,.35*.5+.35*.5+.15*.4+.15*.3,'AbsTol',1e-12);
end

function test_clip_is_applied_after_sum_not_per_term(tc)
% Each term alone is >1, but the scalar is clipped only after the weighted sum.
t=struct('V_pu',2,'V_ref_pu',1,'f_hz',60,'rocof_hz_s',0,'rocov_pu_s',0,'f0_Hz',60);
[si,c]=stability.ne39_weighted_severity(t,fixed_weights(),fixed_bases());
tc.verifyGreaterThan(c.Jv,1);
tc.verifyEqual(si,min(1,.35*c.Jv),'AbsTol',1e-12);
tc.verifyEqual(si,1);
end

function test_frequency_term_uses_caller_nominal_not_hard_coded(tc)
t=struct('V_pu',1,'V_ref_pu',1,'f_hz',50.25,'rocof_hz_s',0,'rocov_pu_s',0,'f0_Hz',50);
[~,c]=stability.ne39_weighted_severity(t,fixed_weights(),fixed_bases());
tc.verifyEqual(c.Jf,.5,'AbsTol',1e-12);
end

function test_invalid_weights_bases_and_terms_rejected(tc)
t=struct('V_pu',1,'V_ref_pu',1,'f_hz',60,'rocof_hz_s',0,'rocov_pu_s',0,'f0_Hz',60);
tc.verifyError(@()stability.ne39_weighted_severity(t,[.5 .5 .5 0],fixed_bases()), ...
    'stability:ne39_weighted_severity:badWeights');
tc.verifyError(@()stability.ne39_weighted_severity(t,[-.1 .6 .25 .25],fixed_bases()), ...
    'stability:ne39_weighted_severity:badWeights');
tc.verifyError(@()stability.ne39_weighted_severity(t,fixed_weights(),[0 .5 1 1]), ...
    'stability:ne39_weighted_severity:badBases');
bad=t; bad.rocof_hz_s=NaN;
tc.verifyError(@()stability.ne39_weighted_severity(bad,fixed_weights(),fixed_bases()), ...
    'stability:ne39_weighted_severity:badTerms');
bad=rmfield(t,'f0_Hz');
tc.verifyError(@()stability.ne39_weighted_severity(bad,fixed_weights(),fixed_bases()), ...
    'stability:ne39_weighted_severity:badTerms');
end

% ------------------------------------------------- option validation/omission --
function test_omission_keeps_legacy_two_term(tc)
r=stability.ne39_weighted_options(struct());
tc.verifyFalse(r.enabled);
tc.verifyEmpty(r.weights);
r=stability.ne39_weighted_options(struct('ne39_weighted_severity',false));
tc.verifyFalse(r.enabled);
end

function test_opt_in_defaults_are_the_approved_design(tc)
r=stability.ne39_weighted_options(struct('ne39_weighted_severity',true));
tc.verifyTrue(r.enabled);
tc.verifyEqual(r.weights,[.35 .35 .15 .15]);
tc.verifyEqual(r.bases,[.10 .50 1 1]);
tc.verifyEqual(r.classification,'PROJECT_DERIVED_UNVALIDATED');
end

function test_invalid_option_values_rejected(tc)
tc.verifyError(@()stability.ne39_weighted_options( ...
    struct('ne39_weighted_severity',true,'ne39_severity_weights',[.5 .5 .5 0])), ...
    'stability:ne39_weighted_options:badWeights');
tc.verifyError(@()stability.ne39_weighted_options( ...
    struct('ne39_weighted_severity',true,'ne39_severity_bases',[.1 .5 0 1])), ...
    'stability:ne39_weighted_options:badBases');
tc.verifyError(@()stability.ne39_weighted_options( ...
    struct('ne39_weighted_severity','yes')), ...
    'stability:ne39_weighted_options:badFlag');
end

% -------------------------------------------- threshold/dwell conflict contract --
function test_threshold_pairs_resolve_from_one_spelling(tc)
r=stability.ne39_resolve_threshold_pairs(struct(),struct('si_on',.65,'si_off',.35, ...
    'on_dwell',.1,'off_dwell',1),.65,.35,.1,1);
tc.verifyEqual(r.si_on,.65); tc.verifyEqual(r.si_off,.35);
tc.verifyEqual(r.on_dwell,.1); tc.verifyEqual(r.off_dwell,1);
r=stability.ne39_resolve_threshold_pairs(struct('severity_gamma_on',.7, ...
    'severity_gamma_off',.3,'severity_T_d_on',.2,'severity_T_d_off',2), ...
    struct(),.65,.35,.1,1);
tc.verifyEqual(r.si_on,.7); tc.verifyEqual(r.si_off,.3);
tc.verifyEqual(r.on_dwell,.2); tc.verifyEqual(r.off_dwell,2);
tc.verifyEqual(r.source.si_on,'severity');
end

function test_threshold_conflict_raises_not_silent(tc)
tc.verifyError(@()stability.ne39_resolve_threshold_pairs( ...
    struct('severity_gamma_on',.7),struct('si_on',.65),.65,.35,.1,1), ...
    'stability:ne39_resolve_threshold_pairs:conflict');
tc.verifyError(@()stability.ne39_resolve_threshold_pairs( ...
    struct('severity_T_d_off',2),struct('off_dwell',1),.65,.35,.1,1), ...
    'stability:ne39_resolve_threshold_pairs:conflict');
end

function test_threshold_equal_spellings_are_accepted(tc)
r=stability.ne39_resolve_threshold_pairs(struct('severity_gamma_on',.65), ...
    struct('si_on',.65),.65,.35,.1,1);
tc.verifyEqual(r.source.si_on,'both_equal');
end

function test_resolved_order_must_be_ordered(tc)
tc.verifyError(@()stability.ne39_resolve_threshold_pairs(struct(),struct('si_off',.7), ...
    .65,.35,.1,1),'stability:ne39_resolve_threshold_pairs:badOrder');
end

% -------------------------------------- actual release decision (controlled) --
function test_rocof_rate_change_releases_then_holds(tc)
% Plan section 5, ROCOF row: V=Vhealthy=1, f=60.35, rv=0; rate rf 0 -> -0.8;
% SI .245 -> .365. The valid safe baseline accumulates the off-dwell until
% actual release=true. The advancing rate-only step then holds and resets the
% dwell. Projected f = 60.35 + .25*(-.8) = 60.15 stays inside [59.5,60.5].
[p,terms]=policy_and_baseline();
terms.f_hz=60.35;
si_base=stability.ne39_weighted_severity(terms,fixed_weights(),fixed_bases());
tc.verifyEqual(si_base,.245,'AbsTol',1e-9);
s=sample_from(terms,si_base);
[~,st]=stability.ne39_rate_policy(0,s,struct(),p);
[d,st]=stability.ne39_rate_policy(.5,s,st,p);
tc.verifyFalse(d.release,'release must wait for the full off-dwell');
[d,st]=stability.ne39_rate_policy(1.6,s,st,p);
tc.verifyTrue(d.release,'release true after baseline off-dwell');
% Rate-only change at an advancing timestamp.
terms.rocof_hz_s=-.8;
si_rate=stability.ne39_weighted_severity(terms,fixed_weights(),fixed_bases());
tc.verifyEqual(si_rate,.365,'AbsTol',1e-9);
s2=sample_from(terms,si_rate);
[d,st2]=stability.ne39_rate_policy(1.7,s2,st,p);
tc.verifyFalse(d.release,'release must hold after the rate change');
tc.verifyFalse(d.prediction_trigger,'projected f 60.15 is inside the band');
tc.verifyFalse(d.rocof_trigger,'|rocof| .8 is below rocof_max 1');
tc.verifyTrue(isnan(st2.down_since),'down dwell must reset on hold');
end

function test_rocov_rate_change_releases_then_holds(tc)
% Plan section 5, ROCOV row: V=1.07, Vhealthy=1, f=60.05, rf=0; rate rv 0 -> -0.6;
% SI .28 -> .37. Fixed V stays 1.07. The f contribution .035 is part of the
% baseline. Projected V = 1.07 + .25*(-.6) = .92 stays above v_min .9.
[p,terms]=policy_and_baseline();
terms.V_pu=1.07; terms.f_hz=60.05;
si_base=stability.ne39_weighted_severity(terms,fixed_weights(),fixed_bases());
tc.verifyEqual(si_base,.28,'AbsTol',1e-9);
s=sample_from(terms,si_base);
[~,st]=stability.ne39_rate_policy(0,s,struct(),p);
[d,st]=stability.ne39_rate_policy(.5,s,st,p);
tc.verifyFalse(d.release,'release must wait for the full off-dwell');
[d,st]=stability.ne39_rate_policy(1.6,s,st,p);
tc.verifyTrue(d.release,'release true after baseline off-dwell');
terms.rocov_pu_s=-.6;
si_rate=stability.ne39_weighted_severity(terms,fixed_weights(),fixed_bases());
tc.verifyEqual(si_rate,.37,'AbsTol',1e-9);
s2=sample_from(terms,si_rate);
[d,st2]=stability.ne39_rate_policy(1.7,s2,st,p);
tc.verifyFalse(d.release,'release must hold after the rate change');
tc.verifyFalse(d.prediction_trigger,'projected V .92 is above v_min');
tc.verifyFalse(d.rocov_trigger,'|rocov| .6 is below rocov_max 1');
tc.verifyTrue(isnan(st2.down_since),'down dwell must reset on hold');
end

function test_individual_release_does_not_require_all_low_si(tc)
[p,t]=policy_and_baseline();
s=sample_from(t,.1);
for name=fieldnames(s)'
    s.(name{1})=repmat(s.(name{1}),1,2);
end
s.severity=[.1 .5]; s.release_capable=[true true];
[~,st]=stability.ne39_rate_policy(0,s,struct(),p);
[d,st]=stability.ne39_rate_policy(1.2,s,st,p);
tc.verifyTrue(d.release);
tc.verifyEqual(d.release_eligible,[true;false]);
s.valid=[true false];
[d,st]=stability.ne39_rate_policy(1.3,s,st,p);
tc.verifyFalse(d.release);
tc.verifyTrue(all(isnan(st.release_since)));
end

function test_public_kernel_consumes_local_weighted_sample(tc)
[design,analysis]=ne39_endpoint_design_options();
c=cases.ne39_chronology_design(cases.case_ne39_1sg_9ibr(),design);
scenario=cases.scenario_ne39_tamu_mixed(c,struct('initial_modes',analysis.initial_modes));
events=struct('enabled',true,'event_profile','fault_only','fault_bus',16, ...
    'fault_on',.001,'fault_clear',.002,'Zf',1i*1e6,'automatic_gfm_switching',false);
op=struct('t_end',.06,'dt',.001,'verbose',false,'ibr_events',events, ...
    'stepper','adaptive','adaptive_strict_lte',true,'dt_min',.0025/4096, ...
    'dt_max',.025,'dt_max_armed',.01,'rannacher_n',0, ...
    'atol_x',2e-8,'rtol_x',1e-7,'atol_y',2e-8,'rtol_y',1e-7, ...
    'healthy_pf_V',c.bus_data(:,3).','healthy_pf_bus_ids',c.bus_data(:,1).', ...
    'ne39_rate_policy',true,'ne39_weighted_severity',true, ...
    'ne39_policy',struct('off_dwell',.003));
r=stability.run_hybrid_case(scenario,op);
tc.assertTrue(r.converged,r.failure_reason);
logs=r.ne39_decision_log;
hit=find(cellfun(@(d)d.valid,logs),1,'last');
tc.assertNotEmpty(hit);
d=logs{hit};
tc.verifyEqual(d.si_components.frequency_basis,'LOCAL_DEVICE');
cj=d.si_components;
expected=min(1,.35*cj.Jv+.35*cj.Jf+.15*cj.Jrocof+.15*cj.Jrocov);
tc.verifyEqual(d.sample.severity,expected,'AbsTol',1e-12);
tc.verifyEqual(cj.Jf,abs(d.sample.f_hz-60)/.5,'AbsTol',1e-12);
tc.verifyTrue(isfield(d,'release_eligible'));
tc.verifyFalse(logs{1}.valid);
for k=2:numel(logs)
    if isequal(logs{k}.t,logs{k-1}.t)
        tc.verifyFalse(logs{k}.release);
    end
end
end

function test_dwell_restarts_after_hold(tc)
% After a hold resets the dwell, a return to a safe baseline must wait for a
% fresh full off-dwell before release is true again (no carry-over).
[p,terms]=policy_and_baseline();
terms.f_hz=60.35;
s=sample_from(terms,stability.ne39_weighted_severity(terms,fixed_weights(),fixed_bases()));
[~,st]=stability.ne39_rate_policy(0,s,struct(),p);
[d,st]=stability.ne39_rate_policy(1.2,s,st,p);
tc.verifyTrue(d.release);
terms.rocof_hz_s=-.8;
s2=sample_from(terms,stability.ne39_weighted_severity(terms,fixed_weights(),fixed_bases()));
[~,st]=stability.ne39_rate_policy(1.3,s2,st,p);
terms.rocof_hz_s=0;
s3=sample_from(terms,stability.ne39_weighted_severity(terms,fixed_weights(),fixed_bases()));
[d,st]=stability.ne39_rate_policy(1.5,s3,st,p);
tc.verifyFalse(d.release,'dwell restarted, release must not be immediate');
[d,~]=stability.ne39_rate_policy(2.6,s3,st,p);
tc.verifyTrue(d.release,'release true only after a fresh full off-dwell');
end
