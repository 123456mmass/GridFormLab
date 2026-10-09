function tests = test_et_fcs_causal_rates
%TEST_ET_FCS_CAUSAL_RATES  Production SI/ROCOF/ROCOV rate + gate tests.
%   Asserts ACTUAL produced rates and CAUSALITY, not just policy plumbing:
%   exact analytic rates, future samples cannot change a past decision, the
%   historical gradient() stencil IS non-causal (counterexample), duplicate
%   event instants / rejected rollbacks are invalidated rather than divided by
%   zero, warmup suppresses early claims, the three gates fire independently,
%   and release requires a continuous dwell.
tests = functiontests(localfunctions);
end

% -------------------------------------------------------------------------
function test_exact_analytic_rates(tc)
% theta advancing at a constant 0.5 Hz slip -> f == 60.5 exactly, rocof == 0.
dt = 0.01; t = (0:5)'*dt; df = 0.5;
theta = 2*pi*df*t; Vmag = 1.0 + 0*t;
r = stability.et_fcs_causal_rates(t,theta,Vmag,struct('warmup_s',0));
idx = find(r.valid);
tc.verifyGreaterThanOrEqual(numel(idx),4);
tc.verifyEqual(r.f_hz(idx),60.5*ones(numel(idx),1),'AbsTol',1e-10);
tc.verifyEqual(r.rocof_hz_s(idx),zeros(numel(idx),1),'AbsTol',1e-9);
tc.verifyEqual(r.rocov_pu_s(idx),zeros(numel(idx),1),'AbsTol',1e-12);
tc.verifyEqual(r.method,'causal_backward_accepted_steps');
tc.verifyTrue(r.causal);
end

function test_rocov_exact(tc)
% Vmag ramp 0.01 pu/s -> rocov == 0.01 exactly.
dt = 0.01; t = (0:5)'*dt; theta = zeros(size(t));
Vmag = 1.0 + 0.01*t;
r = stability.et_fcs_causal_rates(t,theta,Vmag,struct('warmup_s',0));
idx = find(r.valid);
tc.verifyEqual(r.rocov_pu_s(idx),0.01*ones(numel(idx),1),'AbsTol',1e-12);
end

function test_causality_future_samples_do_not_change_past(tc)
% Two histories identical through index 5, differing at 6..10. Rates at
% indices <=5 must be bit-identical; the estimator is one-sided.
dt = 0.01; t = (0:9)'*dt;
base = 2*pi*(0.2*t);                       % 0.2 Hz slip
other = base; other(6:end) = other(6:end) + linspace(0,3,numel(base)-5)';
ra = stability.et_fcs_causal_rates(t,base,ones(size(t)),struct('warmup_s',0));
rb = stability.et_fcs_causal_rates(t,other,ones(size(t)),struct('warmup_s',0));
for k = 1:5
    tc.verifyEqual(rb.f_hz(k),ra.f_hz(k));
    tc.verifyEqual(rb.rocof_hz_s(k),ra.rocof_hz_s(k));
    tc.verifyEqual(rb.rocov_pu_s(k),ra.rocov_pu_s(k));
end
end

function test_gradient_stencil_is_non_causal_counterexample(tc)
% The historical metric used gradient(), whose interior differencing spans
% k-1..k+1. Demonstrate that at index 5 gradient() DOES change when only future
% samples change -- the exact non-causality this module removes.
dt = 0.01; t = (0:9)'*dt;
base = 2*pi*(0.2*t); other = base; other(6:end) = other(6:end) + 3;
fa = gradient(base,dt); fb = gradient(other,dt);
tc.verifyNotEqual(fa(5),fb(5));            % gradient is non-causal here
ra = stability.et_fcs_causal_rates(t,base,ones(size(t)),struct('warmup_s',0));
rb = stability.et_fcs_causal_rates(t,other,ones(size(t)),struct('warmup_s',0));
tc.verifyEqual(ra.f_hz(5),rb.f_hz(5));     % estimator is causal here
end

function test_duplicate_event_time_is_invalid_not_garbage(tc)
% A duplicate accepted instant (identical event time) must not divide by zero.
dt = 0.01; t = [0;0.01;0.02;0.02;0.03;0.04]; theta = 2*pi*0.1*t;
r = stability.et_fcs_causal_rates(t,theta,ones(size(t)),struct('warmup_s',0));
tc.verifyGreaterThanOrEqual(r.n_duplicate_time,1);
tc.verifyFalse(r.valid(4));
tc.verifyTrue(all(isfinite(r.f_hz(2:3))));
tc.verifyTrue(all(isfinite(r.f_hz(5:6))));
tc.verifyTrue(any(isnan(r.f_hz)));         % the duplicate instant is NaN, not Inf
tc.verifyFalse(any(isinf(r.f_hz)));
end

function test_rejected_rollback_nonadvancing_is_flagged(tc)
% A rejected step leaves time unchanged; it must be flagged and skipped, and
% the following accepted sample must still be computed from its own interval.
t = [0;0.01;0.01;0.02]; theta = 2*pi*0.1*t;
r = stability.et_fcs_causal_rates(t,theta,ones(size(t)),struct('warmup_s',0));
tc.verifyGreaterThanOrEqual(r.n_duplicate_time + r.n_nonadvancing,1);
tc.verifyFalse(r.valid(3));
end

function test_warmup_suppresses_early_claims(tc)
dt = 0.01; t = (0:6)'*dt; theta = 2*pi*0.1*t;   % slope 0.1 -> f=60.1
r = stability.et_fcs_causal_rates(t,theta,ones(size(t)),struct('warmup_s',0.05));
early = t < 0.05;
tc.verifyFalse(any(r.valid(early)));
tc.verifyTrue(all(isnan(r.f_hz(early))));
late = t >= 0.05; idx = find(late);
tc.verifyTrue(r.valid(idx(1)));
tc.verifyEqual(r.f_hz(idx(1)),60.1,'AbsTol',1e-10);
end

function test_independent_gates_fire_separately(tc)
% Construct rates that violate ONE quantity at a time; each gate must fire
% alone. This is gate logic, exercised on a crafted rates struct.
n = 6; t = (0:n-1)'*0.01;
g = struct('f_min',59.8,'f_max',60.2,'rocof_max',5,'rocov_max',0.1);

% A: frequency out of band, RoCoF/RoCoV clean.
rA = craft_rates(t, 60.5*ones(n,1), zeros(n,1), zeros(n,1));
gA = stability.et_fcs_rate_gates(rA,g,struct('t',t));
tc.verifyTrue(any(gA.over_frequency));
tc.verifyFalse(any(gA.rocof_gate));
tc.verifyFalse(any(gA.rocov_gate));

% B: frequency in band, RoCoF high.
rB = craft_rates(t, 60.0*ones(n,1), 10*ones(n,1), zeros(n,1));
gB = stability.et_fcs_rate_gates(rB,g,struct('t',t));
tc.verifyFalse(any(gB.frequency_gate));
tc.verifyTrue(any(gB.rocof_gate));
tc.verifyFalse(any(gB.rocov_gate));

% C: frequency in band, RoCoF clean, RoCoV high.
rC = craft_rates(t, 60.0*ones(n,1), zeros(n,1), 0.5*ones(n,1));
gC = stability.et_fcs_rate_gates(rC,g,struct('t',t));
tc.verifyFalse(any(gC.frequency_gate));
tc.verifyFalse(any(gC.rocof_gate));
tc.verifyTrue(any(gC.rocov_gate));
end

function test_gate_respects_validity(tc)
% An unwarmed/invalid sample can never assert a gate even if its raw value would.
n = 6; t = (0:n-1)'*0.01;
r = craft_rates(t, 65*ones(n,1), 20*ones(n,1), ones(n,1));
r.valid = false(n,1);
g = stability.et_fcs_rate_gates(r,struct('f_min',59.8,'f_max',60.2, ...
    'rocof_max',5,'rocov_max',0.1),struct('t',t));
tc.verifyFalse(any(g.combined));
end

function test_release_dwell_requires_continuous_assertion(tc)
t = (0:9)'*0.1;                            % 0.1 s grid
g = struct('f_min',59.8,'f_max',60.2,'rocof_max',5,'rocov_max',0.1);
% Single isolated spike at index 5: must NOT release with dwell 0.25 s.
f = 60*ones(10,1); f(5) = 60.5;
r = craft_rates(t,f,zeros(10,1),zeros(10,1));
[~,d] = stability.et_fcs_rate_gates(r,g,struct('t',t,'dwell_s',0.25));
tc.verifyFalse(d.released);
tc.verifyEqual(d.proposal_index,[]);
% Sustained excursion from index 4 onward: releases once 0.25 s has elapsed.
f2 = 60*ones(10,1); f2(4:end) = 60.5;
r2 = craft_rates(t,f2,zeros(10,1),zeros(10,1));
[~,d2] = stability.et_fcs_rate_gates(r2,g,struct('t',t,'dwell_s',0.25));
tc.verifyTrue(d2.released);
tc.verifyGreaterThanOrEqual(t(d2.proposal_index)-t(4),0.25 - 1e-12);
end

function test_active_rates_column_wise(tc)
% Active column matches the scalar estimator; inactive column is all-NaN and
% never valid (offline resource has no connected-grid rate).
dt = 0.01; t = (0:5)'*dt;
theta = [2*pi*0.3*t, 2*pi*0.7*t];       % active col1, inactive col2
Vmag = [ones(6,1), ones(6,1)];
o = stability.et_fcs_active_rates(t,theta,Vmag,[true false],struct('warmup_s',0));
r1 = stability.et_fcs_causal_rates(t,theta(:,1),Vmag(:,1),struct('warmup_s',0));
tc.verifyEqual(o.f_hz(:,1),r1.f_hz,'AbsTol',0);
tc.verifyTrue(all(isnan(o.f_hz(:,2))));
tc.verifyFalse(any(o.valid(:,2)));
tc.verifyTrue(any(o.valid(:,1)));
end

function test_active_rates_mask_required(tc)
t = (0:3)'; a = ones(4,2); v = ones(4,2);
tc.verifyError(@() stability.et_fcs_active_rates(t,a,v,[true true true]), ...
    'stability:et_fcs_active_rates:maskMismatch');
end

function test_length_mismatch_errors(tc)
tc.verifyError(@() stability.et_fcs_causal_rates([0;1;2],[0;1],[0;1;2]), ...
    'stability:et_fcs_causal_rates:lengthMismatch');
end

% -------------------------------------------------------------------------
function r = craft_rates(t,f,rocof,rocov)
r = struct('f_hz',f(:),'rocof_hz_s',rocof(:),'rocov_pu_s',rocov(:), ...
    'valid',true(numel(t),1),'t',t(:));
end
