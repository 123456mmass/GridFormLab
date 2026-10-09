function tests=test_ne39_rate_policy()
%TEST_NE39_RATE_POLICY ทดสอบ proposal แยกจาก transition authority.
tests=functiontests(localfunctions);
end

function setupOnce(tc)
p=path; tc.addTeardown(@()path(p));
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_rates_block_release(tc)
[p,s]=inputs(); s.rocof_hz_s=2;
[d,st]=stability.ne39_rate_policy(0,s,struct(),p);
tc.verifyTrue(d.rocof_trigger); tc.verifyFalse(d.release);
[d,~]=stability.ne39_rate_policy(.2,s,st,p);
tc.verifyTrue(d.augment); tc.verifyFalse(d.release);
s.rocof_hz_s=0; s.rocov_pu_s=-2;
[d,~]=stability.ne39_rate_policy(.3,s,struct(),p);
tc.verifyTrue(d.rocov_trigger); tc.verifyFalse(d.release);
end

function test_release_requires_continuous_safe_evidence(tc)
[p,s]=inputs();
[d,st]=stability.ne39_rate_policy(0,s,struct(),p);
tc.verifyFalse(d.release);
s.valid=false;
[~,st]=stability.ne39_rate_policy(.8,s,st,p);
s.valid=true;
[~,st]=stability.ne39_rate_policy(.9,s,st,p);
[d,st]=stability.ne39_rate_policy(1.5,s,st,p);
tc.verifyFalse(d.release);
[d,~]=stability.ne39_rate_policy(2,s,st,p);
tc.verifyTrue(d.release);
end

function test_projection_outward_only(tc)
[p,s]=inputs(); s.v_pu=.91; s.rocov_pu_s=-.1;
[d,~]=stability.ne39_rate_policy(0,s,struct(),p);
tc.verifyTrue(d.prediction_trigger);
tc.verifyFalse(d.rocov_trigger);
s.rocov_pu_s=.1;
[d,~]=stability.ne39_rate_policy(0,s,struct(),p);
tc.verifyFalse(d.prediction_trigger);
end

function test_duplicate_does_not_mutate_state(tc)
[p,s]=inputs();
[~,st]=stability.ne39_rate_policy(0,s,struct(),p);
s.severity=1;
[d,after]=stability.ne39_rate_policy(0,s,st,p);
tc.verifyEqual(after,st); tc.verifyFalse(d.augment);
end

function test_independent_si_and_invalid_evidence(tc)
[p,s]=inputs(); s.severity=.8;
[d,st]=stability.ne39_rate_policy(0,s,struct(),p);
tc.verifyTrue(d.si_trigger); tc.verifyFalse(d.rocof_trigger);
s.f_hz=NaN;
[d,st]=stability.ne39_rate_policy(.2,s,st,p);
tc.verifyFalse(d.augment); tc.verifyFalse(d.release);
tc.verifyTrue(isnan(st.up_since));
end

function test_all_devices_must_be_safe(tc)
[p,s]=inputs();
for name=fieldnames(s)'
    s.(name{1})=repmat(s.(name{1}),1,2);
end
s.rocof_hz_s=[0 2];
[d,st]=stability.ne39_rate_policy(0,s,struct(),p);
[d,~]=stability.ne39_rate_policy(2,s,st,p);
tc.verifyTrue(d.rocof_trigger); tc.verifyFalse(d.release);
s.rocof_hz_s=[0 0]; s.valid=[true false];
[d,~]=stability.ne39_rate_policy(3,s,struct(),p);
tc.verifyFalse(d.valid); tc.verifyFalse(d.release);
end

function test_invalid_contract_and_shapes(tc)
[p,s]=inputs(); bad=rmfield(p,'rocov_max');
tc.verifyError(@()stability.ne39_rate_policy(0,s,struct(),bad), ...
    'stability:ne39_rate_policy:badPolicy');
bad=p; bad.si_off=-1;
tc.verifyError(@()stability.ne39_rate_policy(0,s,struct(),bad), ...
    'stability:ne39_rate_policy:badPolicy');
s.valid='yes';
tc.verifyError(@()stability.ne39_rate_policy(0,s,struct(),p), ...
    'stability:ne39_rate_policy:shape');
end

function [p,s]=inputs()
p=struct('si_on',.65,'si_off',.35,'rocof_max',1,'rocov_max',1, ...
    'v_min',.9,'v_max',1.1,'f_min',59.5,'f_max',60.5, ...
    'prediction_horizon',.25,'on_dwell',.1,'off_dwell',1);
s=struct('severity',.1,'v_pu',1,'f_hz',60, ...
    'rocof_hz_s',0,'rocov_pu_s',0,'valid',true);
end
