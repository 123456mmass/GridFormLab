function tests = test_et_fcs_active_rate_accumulator
%TEST_ET_FCS_ACTIVE_RATE_ACCUMULATOR  Transactional online active-rate tests.
%   Asserts the properties the plan requires BEFORE any online-causal claim:
%   a rejected (rolled-back) step consumes NO history/timers; a mode/online
%   change RESETS the column (no frozen/pre-transfer mixing); RoCoF uses the
%   active RHS when present; RoCoV is smoothed; duplicate instants record a
%   left/right jump but create no rate; warmup suppresses early claims; a
%   50 Hz base scales correctly.
tests = functiontests(localfunctions);
end

function test_rollback_leaves_state_untouched(tc)
acc = stability.EtFcsRateAccumulator(struct('warmup_s',0));
[acc,~] = acc.step(0.00, s(1,'gfl',true,60.00,1.0), true);
[acc,~] = acc.step(0.01, s(1,'gfl',true,60.50,1.0), true);
base = acc.rates();
% A rejected step with wild values must NOT move persistent state.
[accR,~] = acc.step(0.02, s(1,'gfl',true,99.0,0.10), false);
rR = accR.rates();
tc.verifyEqual(rR.t, base.t);
tc.verifyEqual(rR.f_hz, base.f_hz);
tc.verifyEqual(rR.rocof_hz_s, base.rocof_hz_s);
% And a subsequent accepted step is identical with or without the rejection.
[accA,~] = acc.step(0.03, s(1,'gfl',true,60.60,1.0), true);
[accB,~] = accR.step(0.03, s(1,'gfl',true,60.60,1.0), true);
tc.verifyEqual(accA.rates().rocof_hz_s, accB.rates().rocof_hz_s);
end

function test_mode_transfer_resets_epoch_no_mixing(tc)
acc = stability.EtFcsRateAccumulator(struct('warmup_s',0));
[acc,~] = acc.step(0.00, s(1,'gfl',true,60.0,1.0), true);
[acc,~] = acc.step(0.01, s(1,'gfl',true,60.1,1.0), true);
r1 = acc.rates();
tc.verifyEqual(r1.epoch,1);
% GFL -> GFM transfer at the same device: epoch bumps and history is cleared.
[acc,~] = acc.step(0.02, s(1,'GFM',true,59.9,1.0), true);
r2 = acc.rates();
tc.verifyEqual(r2.epoch,2);
tc.verifyEqual(numel(r2.t(~isnan(r2.t))),0);      % no pre-transfer sample survives
% A following GFM sample rates against the POST-transfer base only.
[acc,~] = acc.step(0.03, s(1,'GFM',true,59.7,1.0), true);
r3 = acc.rates();
rocof = r3.rocof_hz_s(1);
tc.verifyEqual(rocof,(59.7-59.9)/0.01,'AbsTol',1e-9);
end

function test_variable_dt_causal_rocof(tc)
acc = stability.EtFcsRateAccumulator(struct('warmup_s',0));
[acc,~] = acc.step(0.00, s(1,'gfl',true,60.0,1.0), true);
[acc,~] = acc.step(0.01, s(1,'gfl',true,60.1,1.0), true);
[acc,~] = acc.step(0.03, s(1,'gfl',true,60.3,1.0), true);   % variable dt 0.02
r = acc.rates();
tc.verifyEqual(r.rocof_hz_s(1),10,'AbsTol',1e-9);
tc.verifyEqual(r.rocof_hz_s(2),(60.3-60.1)/0.02,'AbsTol',1e-9);
end

function test_rocof_prefers_active_rhs(tc)
% Frequency that would give a 100 Hz/s causal difference, but the device's own
% active RHS says 2 Hz/s: the RHS wins (SG/GFM speed state).
acc = stability.EtFcsRateAccumulator(struct('warmup_s',0));
[acc,~] = acc.step(0.00, s(1,'sg',true,60.0,1.0), true);
[acc,~] = acc.step(0.01, s(1,'sg',true,61.0,1.0,2.0), true);
r = acc.rates();
tc.verifyEqual(r.rocof_hz_s(1),2.0,'AbsTol',1e-12);
end

function test_warmup_suppresses_early_claims(tc)
acc = stability.EtFcsRateAccumulator(struct('warmup_s',0.05));
[acc,~] = acc.step(0.00, s(1,'gfl',true,60.0,1.0), true);
[acc,~] = acc.step(0.01, s(1,'gfl',true,60.1,1.0), true);
[acc,~] = acc.step(0.06, s(1,'gfl',true,60.2,1.0), true);
r = acc.rates();          % two rate rows: t=0.01 (cold), t=0.06 (warm)
tc.verifyFalse(r.valid(1));
tc.verifyTrue(r.valid(2));
end

function test_duplicate_instant_records_jump_no_rate(tc)
acc = stability.EtFcsRateAccumulator(struct('warmup_s',0));
[acc,~] = acc.step(0.00, s(1,'gfl',true,60.0,1.00), true);
[acc,~] = acc.step(0.01, s(1,'gfl',true,60.1,1.00), true);   % first rate row
[acc,~] = acc.step(0.01, s(1,'gfl',true,60.1,0.90), true);   % duplicate instant
r = acc.rates();
tc.verifyEqual(numel(r.t(~isnan(r.t))),1);     % no second rate row
j = acc.jump_diagnostics();
tc.verifyEqual(j.count,1);
tc.verifyEqual(j.jump,-0.10,'AbsTol',1e-12);
end

function test_right_limit_jump_not_repeated_as_continuous_rate(tc)
acc = stability.EtFcsRateAccumulator(struct('warmup_s',0));
[acc,~] = acc.step(0,s(1,'gfl',true,60,1),true);
[acc,~] = acc.step(.01,s(1,'gfl',true,60,1),true);
[acc,~] = acc.step(.01,s(1,'gfl',true,60,.9),true);
[acc,~] = acc.step(.02,s(1,'gfl',true,60,.9),true);
r = acc.rates();
tc.verifyEqual(r.rocov_pu_raw_s(end),0,'AbsTol',1e-12);
tc.verifyEqual(acc.jump_diagnostics().jump,-.1,'AbsTol',1e-12);
end

function test_time_constant_uses_actual_dt(tc)
acc = stability.EtFcsRateAccumulator(struct('warmup_s',0,'rocov_tau_s',.02));
[acc,~] = acc.step(0,s(1,'gfl',true,60,1),true);
[acc,~] = acc.step(.01,s(1,'gfl',true,60,1),true);
[acc,~] = acc.step(.03,s(1,'gfl',true,60,1.02),true);
r = acc.rates();
tc.verifyEqual(r.rocov_pu_s(end),1-exp(-1),'AbsTol',1e-12);
end

function test_rocov_smoothing_keeps_raw_spike(tc)
% Smoothing must NOT hide a spike: the RAW series keeps it, the filtered series
% damps it; both are retained and distinct.
acc = stability.EtFcsRateAccumulator(struct('warmup_s',0,'rocov_alpha',0.2));
[acc,~] = acc.step(0.00, s(1,'gfl',true,60.0,1.0), true);
[acc,~] = acc.step(0.01, s(1,'gfl',true,60.0,1.0), true);   % raw 0
[acc,~] = acc.step(0.02, s(1,'gfl',true,60.0,2.0), true);   % raw +100 spike
r = acc.rates();
tc.verifyEqual(r.rocov_pu_raw_s(2),100,'AbsTol',1e-9);      % spike preserved
tc.verifyEqual(r.rocov_pu_s(2),20,'AbsTol',1e-9);           % filtered damps it
tc.verifyLessThan(r.rocov_pu_s(2),r.rocov_pu_raw_s(2));
tc.verifyGreaterThan(r.rocov_pu_raw_s(2),0);
end

function test_release_guard_requires_valid(tc)
% A spike during warmup is INVALID: it must not produce a release.
acc = stability.EtFcsRateAccumulator(struct('warmup_s',0.5));
g = struct('f_min',59.8,'f_max',60.2,'rocof_max',5,'rocov_max',0.1);
tt = [0 0.1 0.2]; ff = [60 61 61];      % over-band but still cold (<0.5 s)
for k=1:numel(tt)
    [acc,~] = acc.step(tt(k), s(1,'gfl',true,ff(k),1.0), true);
end
gb = acc.gates(g,0.1);
tc.verifyFalse(gb.dwell.released);
tc.verifyFalse(any(gb.gate.combined));   % no gate fires from an invalid sample
end

function test_offline_resets_epoch(tc)
acc = stability.EtFcsRateAccumulator(struct('warmup_s',0));
[acc,~] = acc.step(0.00, s(1,'gfl',true,60.0,1.0), true);
[acc,~] = acc.step(0.01, s(1,'gfl',true,60.1,1.0), true);
[acc,~] = acc.step(0.02, s(1,'gfl',false,NaN,NaN), true);    % goes offline
r = acc.rates();
tc.verifyEqual(r.epoch,2);
tc.verifyEqual(numel(r.t(~isnan(r.t))),0);     % cleared
end

function test_fbase_scales_frequency(tc)
% A 50 Hz base must be honoured for a speed-state device.
acc = stability.EtFcsRateAccumulator(struct('warmup_s',0,'fbase',50));
[acc,~] = acc.step(0.00, s(1,'sg',true,50.0,1.0), true);
[acc,~] = acc.step(0.01, s(1,'sg',true,50.5,1.0), true);
r = acc.rates();
tc.verifyEqual(r.fbase,50);
tc.verifyEqual(r.f_hz(1),50.5,'AbsTol',1e-12);
end

function test_gates_and_dwell_over_accumulator(tc)
acc = stability.EtFcsRateAccumulator(struct('warmup_s',0));
g = struct('f_min',59.8,'f_max',60.2,'rocof_max',5,'rocov_max',0.1);
% Sustained over-band frequency from the 4th sample.
tt = [0 0.1 0.2 0.3 0.4 0.5 0.6]; ff = [60 60 60 60.5 60.5 60.5 60.5];
for k = 1:numel(tt)
    [acc,~] = acc.step(tt(k), s(1,'gfl',true,ff(k),1.0), true);
end
gb = acc.gates(g,0.25);
tc.verifyTrue(gb.dwell.released);
tc.verifyTrue(any(gb.gate.over_frequency));
end

% -------------------------------------------------------------------------
function x = s(idx, mode, online, f, v, fdot)
x = struct('device_index',idx,'mode',mode,'online',online,'f_hz',f, ...
    'v_mag',v,'fdot_hz_s',NaN);
if nargin >= 6, x.fdot_hz_s = fdot; end
end
