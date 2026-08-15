function tests = test_ts_hybrid_support_state_conditioning
%TEST_TS_HYBRID_SUPPORT_STATE_CONDITIONING  Destination-state transaction map.
% The all-GFM support destination is a certified stable equilibrium, but a GFM
% that is incumbent across the transaction does not invoke mode_transfer_state.
% Its gfm_xi_Vd/gfm_xi_Vq therefore belong to the old operating point unless
% the support transaction maps those two dependent PI coordinates explicitly.
% This suite freezes the narrow ownership contract independently of supervisor
% timing and of the long IEEE14 chronology (AGSI-2026-08-14-01).
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
s = cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
[devices,~] = stability.build_mixed_resource_devices( ...
    s.case_data,s.resources,s.scenario_opt);
dae = stability.composite_dae( ...
    s.case_data,devices,struct('load_model','cz_p_cz_q'));
dual = find(strcmpi({dae.devices.device_type},'ibr_eecon49_dual'));
testCase.assertGreaterThanOrEqual(numel(dual),3, ...
    'The fixture needs at least three switchable EECON49 devices.');
testCase.TestData.dae = dae;
testCase.TestData.dual = dual;
end

function test_augment_conditions_only_incumbent_named_pair(testCase)
dae = testCase.TestData.dae;
dual = testCase.TestData.dual;
[before,after] = all_gfl_modes(dae);
before{dual(1)} = 'GFM';
after{dual(1)} = 'GFM';
after{dual(2)} = 'GFM';
after{dual(3)} = 'GFM';
[x,candidate] = separated_certificate(dae,dual);
ec = right_context(dae,after);

[x2,audit] = stability.condition_eecon49_incumbent_gfm_state( ...
    7.25,x,candidate,dae,before,after,dae.y0,dae.u0,ec);
expected = named_pair(dae,dual(1));
mask = false(size(x)); mask(expected) = true;

verifyTrue(testCase,audit.applied);
verifyEqual(testCase,audit.device_indices,dual(1));
verifyEqual(testCase,audit.device_ids,{dae.devices(dual(1)).device_id});
verifyEqual(testCase,audit.global_state_indices,expected);
verifyEqual(testCase,x2(expected),candidate.eq_x0(expected),'AbsTol',0);
verifyEqual(testCase,x2(~mask),x(~mask),'AbsTol',0, ...
    ['An augmentation may condition only the two named states of a device ' ...
     'that is GFM on both sides; mode changers remain transfer-map owned.']);
verifyLessThanOrEqual(testCase,audit.max_current_jump,1e-10);
end

function test_release_conditions_every_remaining_incumbent(testCase)
dae = testCase.TestData.dae;
dual = testCase.TestData.dual;
[before,after] = all_gfl_modes(dae);
for k = dual(1:3), before{k} = 'GFM'; end
after{dual(1)} = 'GFM';
after{dual(2)} = 'GFM';
[x,candidate] = separated_certificate(dae,dual);
ec = right_context(dae,after);

[x2,audit] = stability.condition_eecon49_incumbent_gfm_state( ...
    8.5,x,candidate,dae,before,after,dae.y0,dae.u0,ec);
expected = [named_pair(dae,dual(1)); named_pair(dae,dual(2))];
expected = expected(:);
mask = false(size(x)); mask(expected) = true;
released_pair = named_pair(dae,dual(3));

verifyEqual(testCase,audit.device_indices,dual(1:2));
verifyEqual(testCase,x2(expected),candidate.eq_x0(expected),'AbsTol',0);
verifyEqual(testCase,x2(released_pair),x(released_pair),'AbsTol',0, ...
    'The device leaving GFM remains exclusively owned by its transfer map.');
verifyEqual(testCase,x2(~mask),x(~mask),'AbsTol',0);
verifyLessThanOrEqual(testCase,audit.max_current_jump,1e-10);
end

function test_other_family_is_bit_identical_noop(testCase)
dae = testCase.TestData.dae;
k = testCase.TestData.dual(1);
dae.devices(k).device_type = 'ibr_decoupled_dual';
[before,after] = all_gfl_modes(dae);
before{k} = 'GFM'; after{k} = 'GFM';
ec = right_context(dae,after);

[x2,audit] = stability.condition_eecon49_incumbent_gfm_state( ...
    0,dae.x0,struct('eq_x0',[]),dae,before,after,dae.y0,dae.u0,ec);
verifyEqual(testCase,x2,dae.x0,'AbsTol',0);
verifyFalse(testCase,audit.applied);
verifyEmpty(testCase,audit.device_indices);
end

function test_bad_certificate_states_fail_closed(testCase)
[dae,before,after,ec] = one_incumbent_fixture(testCase);
x = dae.x0;
invoke = @(candidate) stability.condition_eecon49_incumbent_gfm_state( ...
    0,x,candidate,dae,before,after,dae.y0,dae.u0,ec);
id = 'stability:condition_eecon49_incumbent_gfm_state:badCertificateState';

verifyError(testCase,@() invoke(struct()),id);
verifyError(testCase,@() invoke(struct('eq_x0',x(1:end-1))),id);
bad = x; bad(end) = NaN;
verifyError(testCase,@() invoke(struct('eq_x0',bad)),id);
end

function test_named_state_layout_must_be_exact_and_unique(testCase)
[dae,before,after,ec,k] = one_incumbent_fixture(testCase);
local = find(strcmp(dae.devices(k).state_names,'gfm_xi_Vq'));
dae.devices(k).state_names{local} = 'gfm_xi_Vd';
invoke = @() stability.condition_eecon49_incumbent_gfm_state( ...
    0,dae.x0,struct('eq_x0',dae.x0),dae,before,after,dae.y0,dae.u0,ec);
verifyError(testCase,invoke, ...
    'stability:condition_eecon49_incumbent_gfm_state:badDeviceLayout');
end

function test_right_context_must_confirm_online_gfm(testCase)
[dae,before,after,ec,k] = one_incumbent_fixture(testCase);
key = matlab.lang.makeValidName(char(dae.devices(k).device_id), ...
    'ReplacementStyle','underscore');
ec.hybrid_state.device_online.(key) = false;
invoke = @() stability.condition_eecon49_incumbent_gfm_state( ...
    0,dae.x0,struct('eq_x0',dae.x0),dae,before,after,dae.y0,dae.u0,ec);
verifyError(testCase,invoke, ...
    'stability:condition_eecon49_incumbent_gfm_state:badRightContext');
end

function test_current_jump_is_rejected(testCase)
[dae,before,after,ec,k] = one_incumbent_fixture(testCase);
pair = named_pair(dae,k);
local_vd = pair(1)-dae.device_offsets(k);
dae.devices(k).current_injection = ...
    @(~,xd,~,~,~) complex(xd(local_vd),0);
candidate = struct('eq_x0',dae.x0);
candidate.eq_x0(pair(1)) = candidate.eq_x0(pair(1)) + 0.25;
invoke = @() stability.condition_eecon49_incumbent_gfm_state( ...
    0,dae.x0,candidate,dae,before,after,dae.y0,dae.u0,ec);
verifyError(testCase,invoke, ...
    'stability:condition_eecon49_incumbent_gfm_state:currentContinuity');
end

function test_nonfinite_current_is_rejected(testCase)
[dae,before,after,ec,k] = one_incumbent_fixture(testCase);
dae.devices(k).current_injection = @(~,~,~,~,~) complex(NaN,0);
invoke = @() stability.condition_eecon49_incumbent_gfm_state( ...
    0,dae.x0,struct('eq_x0',dae.x0),dae,before,after,dae.y0,dae.u0,ec);
verifyError(testCase,invoke, ...
    'stability:condition_eecon49_incumbent_gfm_state:nonfiniteCurrent');
end

function [dae,before,after,ec,k] = one_incumbent_fixture(testCase)
dae = testCase.TestData.dae;
k = testCase.TestData.dual(1);
[before,after] = all_gfl_modes(dae);
before{k} = 'GFM'; after{k} = 'GFM';
ec = right_context(dae,after);
end

function [x,candidate] = separated_certificate(dae,devices)
x = dae.x0(:);
certificate = x;
for q = 1:numel(devices)
    gi = named_pair(dae,devices(q));
    certificate(gi) = [0.125*q; -0.075*q];
    x(gi) = [-0.031*q; 0.047*q];
end
candidate = struct('eq_x0',certificate);
end

function gi = named_pair(dae,k)
names = dae.devices(k).state_names;
ld = find(strcmp(names,'gfm_xi_Vd'));
lq = find(strcmp(names,'gfm_xi_Vq'));
assert(numel(ld)==1 && numel(lq)==1);
gi = dae.device_offsets(k) + [ld lq];
end

function [before,after] = all_gfl_modes(dae)
before = repmat({'gfl'},1,numel(dae.devices));
after = before;
for k = 1:numel(dae.devices)
    if isfield(dae.devices(k),'capabilities') && ...
            isfield(dae.devices(k).capabilities,'resource_type') && ...
            strcmpi(char(dae.devices(k).capabilities.resource_type),'sg')
        before{k} = 'breaker_open';
        after{k} = 'breaker_open';
    end
end
end

function ec = right_context(dae,modes)
hs = struct('device_modes',struct(),'device_online',struct());
for k = 1:numel(dae.devices)
    dev = dae.devices(k);
    key = matlab.lang.makeValidName(char(dev.device_id), ...
        'ReplacementStyle','underscore');
    hs.device_modes.(key) = modes{k};
    is_sg = isfield(dev,'capabilities') && ...
        isfield(dev.capabilities,'resource_type') && ...
        strcmpi(char(dev.capabilities.resource_type),'sg');
    hs.device_online.(key) = ~is_sg;
end
ec = struct('hybrid_state',hs);
end
