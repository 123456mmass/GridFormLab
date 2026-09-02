function tests = test_line_fault_relay_clear()
%TEST_LINE_FAULT_RELAY_CLEAR  Protection clears a line fault by opening the line.
%   A fault on a line is not cleared the way a bus fault is. The relay opens the
%   breakers at BOTH ends of the faulted branch, so the branch and the fault leave
%   the network together, in one operation, and the branch does not come back.
%   Representing that as two events (line_trip then fault_clear, or the reverse)
%   would invent an interval that does not exist: either a line open with the
%   fault still on it, or a healed fault on a line that is still carrying load.
%
%   The handler under test is 'line_fault_clear'
%   (ts_simulate_ibr_hybrid.m:592-628). Its whole body is one subtraction,
%   Ycandidate = Ybase_current - Yline_stamp, which is only correct because
%   'fault_on' adds the fault shunt to Ycurr alone and never to Ybase_current
%   (:562-570). That is an easy invariant to break from a distance, and breaking
%   it leaves a fault shunt energized for the rest of the run while the event log
%   says the fault was cleared. So the central assertion here is not on a flag or
%   a label: it is an INDEPENDENT KCL residual test against four candidate
%   networks, rebuilt from the case rather than from anything the kernel returned.
%   Exactly one of them may explain the post-clearing sample.
%
%   Timeline: compressed to about one second, the same technique
%   test_ts_hybrid_adaptive_rollback.m uses, so this is a unit test of the
%   transition rather than a production run. The 120 s scenario in
%   scripts/run_ieee14_scenario_suite.m is the physics study; this is the
%   correctness evidence for the transition itself, and it is needed precisely
%   because a long run can stop before reaching this event.
%
%   Branch 9-14 is the faulted line. Bus 9's other incident branches are
%   transformers, and opening 9-14 strands no bus: bus 14 keeps 13-14 and bus 9
%   keeps 4-9, 7-9 and 9-10. The fault is at bus 9, i.e. a ZERO-DISTANCE
%   (close-in) fault on the line, on the line side of the bus-9 breaker. There is
%   no mid-line fault model in this kernel and this test does not pretend
%   otherwise.

tests = functiontests(localfunctions);
end

function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath')))); pf_init_paths();
% One run, shared by every test in this file: the transition is deterministic and
% re-running it per test would multiply the cost for no extra evidence.
[r,scenario] = run_relay_clear_arm();
tc.TestData.r = r;
tc.TestData.scenario = scenario;
tc.TestData.FAULT_BUS = 9;
tc.TestData.LINE = [9 14];
tc.TestData.T_CLEAR = 0.95;
end

% =========================================================================
% 1. The run reaches the event at all.
% =========================================================================
function test_the_arm_converges_and_applies_every_scheduled_event(tc)
r = tc.TestData.r;
tc.assertTrue(r.converged, sprintf('arm must converge (%s: %s)', ...
    char(string(field_or(r,'failure_id',''))), ...
    char(string(field_or(r,'failure_reason','')))));
tc.verifyEqual({r.events.type}, ...
    {'sg_trip','fault_on','line_fault_clear','sg_on'});
for k = 1:numel(r.events)
    ty = char(string(r.events(k).type));
    j = find(strcmp(cellfun(@(v)char(string(v)),{r.event_log.type}, ...
        'UniformOutput',false),ty),1);
    tc.assertNotEmpty(j,sprintf('event %s never reached the log',ty));
    tc.verifyTrue(logical(r.event_log(j).applied), ...
        sprintf('event %s was logged but not applied',ty));
end
end

% =========================================================================
% 2. THE assertion: the post-clearing sample satisfies the reduced,
%    UNFAULTED network and nothing else.
% =========================================================================
function test_the_cleared_sample_satisfies_only_the_reduced_unfaulted_network(tc)
% Four candidate networks are built independently of the kernel: the full
% network, the network with branch 9-14 out, and each of those plus the fault
% shunt. The right-limit sample at the clearing instant must satisfy the reduced
% UNFAULTED one and be inconsistent with the other three. This single test
% falsifies both halves of the atomic operation at once:
%   - residual small on Yopen        => the fault shunt is gone
%   - residual LARGE on Ypre         => the branch is really out
% A handler that forgot -Yline_stamp would satisfy Ypre; one that subtracted the
% branch from Ycurr while leaving the fault in Ybase_current would satisfy
% Yfault_open. Neither can pass this.
r = tc.TestData.r;
N = candidate_networks(tc);
[i_left,i_right] = clearing_sample_indices(tc,r);

res_right = residuals(r,i_right,N);
KCL_TOL = 1e-6;   % the kernel's own right-limit contract (settings.kcl_tol)

tc.verifyLessThan(res_right.open,KCL_TOL, ...
    'the cleared sample must satisfy the network with branch 9-14 OUT and no fault');
tc.verifyGreaterThan(res_right.pre,1e-3, ...
    'if it also satisfied the FULL network, the branch was never opened');
tc.verifyGreaterThan(res_right.fault_open,1e-3, ...
    'if it satisfied the reduced FAULTED network, the fault shunt survived clearing');
tc.verifyGreaterThan(res_right.fault_full,1e-3, ...
    'if it satisfied the full faulted network, nothing was applied at all');

% And the LEFT limit of the same instant is the faulted FULL network: this is
% what makes the pair a transition rather than two unrelated samples.
res_left = residuals(r,i_left,N);
tc.verifyLessThan(res_left.fault_full,KCL_TOL, ...
    'the left limit at the clearing instant must still be the faulted full network');
tc.verifyGreaterThan(res_left.open,1e-3, ...
    'the left limit must NOT already be the cleared network');
end

function test_the_branch_stamp_is_exactly_the_difference_of_the_two_networks(tc)
% The handler subtracts Yline_stamp, built by chronology_branch_stamp from the
% branch row. If that stamp were not exactly the branch's contribution, the
% "reduced network" the run continues on would be a network that does not
% correspond to any breaker state. Compare it against an independently rebuilt
% Ybus with the branch status set to 0.
N = candidate_networks(tc);
tc.verifyGreaterThan(norm(N.pre-N.open,inf),1e-3, ...
    'sanity: opening branch 9-14 must change the admittance matrix');
% Only the four entries of the 9-14 block may differ, and only those.
d = abs(N.pre-N.open) > 1e-12;
p = tc.TestData.scenario.case_data.mpc.bus(:,1);
i9 = find(p==9,1); i14 = find(p==14,1);
expect = false(size(d));
expect([i9 i14],[i9 i14]) = true;
tc.verifyEqual(d,expect, ...
    'opening one branch may touch only that branch''s 2x2 block');
end

% =========================================================================
% 3. Atomicity: one instant, one transition, no intermediate topology.
% =========================================================================
function test_the_clearing_is_one_transition_with_no_intermediate_state(tc)
r = tc.TestData.r;
t_clear = tc.TestData.T_CLEAR;
k = find(abs(r.t-t_clear) <= 1e-9);
tc.verifyEqual(numel(k),2, ...
    'the clearing instant must carry exactly one left and one right sample');
tc.verifyEqual(r.sample_side(k),{'left','right'}, ...
    'the pair must be a left limit followed by a right limit');
tc.verifyEqual(r.topology_history{k(1)},'fault');
tc.verifyEqual(r.topology_history{k(2)},'line_fault_cleared');
end

function test_no_separate_line_trip_or_fault_clear_event_is_emitted(tc)
% The profile expresses ONE event. If a line_trip or a fault_clear also appeared,
% the network would be stepped twice and there would exist an interval with the
% line open and the fault still energized -- the very state this design removes.
r = tc.TestData.r;
types = cellfun(@(v)char(string(v)),{r.events.type},'UniformOutput',false);
tc.verifyFalse(any(strcmp(types,'line_trip')));
tc.verifyFalse(any(strcmp(types,'fault_clear')));
tc.verifyFalse(any(strcmp(types,'topology_restore')), ...
    'a restore would put the faulted line back, which this profile must not do');
tc.verifyEqual(sum(strcmp(types,'line_fault_clear')),1);
% The schedule must also publish no fault_clear instant at all.
tc.verifyTrue(isnan(r.sched.fault_clear));
tc.verifyEqual(r.sched.line_fault_clear,t_clear_of(tc),'AbsTol',0);
end

% =========================================================================
% 4. The line stays out, and the topology label is not 'fault'.
% =========================================================================
function test_the_line_stays_out_for_the_rest_of_the_run(tc)
% There is no restore in this profile, so every sample after the clearing must
% still satisfy the REDUCED network. A later sample is checked directly rather
% than trusting the absence of a restore event: an unnoticed path that rebuilt
% Ybase_current from Ypre would show up here and nowhere else.
r = tc.TestData.r;
N = candidate_networks(tc);
[~,i_right] = clearing_sample_indices(tc,r);
last = numel(r.t);
tc.assertGreaterThan(last,i_right,'the run must continue past the clearing');

res = residuals(r,last,N);
tc.verifyLessThan(res.open,1e-3, ...
    'the final sample must still be on the network with branch 9-14 out');
tc.verifyGreaterThan(res.pre,res.open, ...
    'the final sample must fit the reduced network better than the full one');
end

function test_the_topology_label_is_not_fault_after_clearing(tc)
% Not cosmetic. 'fault' is the guard sg_off_support_transaction uses to refuse a
% support commit on a faulted network (ts_simulate_ibr_hybrid.m:2964) and that
% ibr_trip_transaction uses to refuse a reference recovery (:2347). If the label
% stayed 'fault' after the fault was gone, the severity supervisor would be
% silently frozen out for the remainder of the run and the scenario would report
% "no adaptation" for a reason that is pure bookkeeping.
r = tc.TestData.r;
[~,i_right] = clearing_sample_indices(tc,r);
for k = i_right:numel(r.t)
    tc.verifyNotEqual(r.topology_history{k},'fault', ...
        sprintf('sample %d (t=%.4f) is still labelled ''fault'' after clearing', ...
            k,r.t(k)));
end
tc.verifyEqual(r.topology_history{i_right},'line_fault_cleared');
end

function test_the_reclose_request_is_accepted_and_guarded_on_the_reduced_network(tc)
% What this arm can honestly show is that the reclose MECHANISM survives the
% clearing: the sg_on request is accepted after the line is out, the offline-SG
% synchronizer is armed, and the synchronism guard is being evaluated against the
% reduced network. Whether the machine actually resynchronizes is physics, and on
% a timeline compressed to 0.03 s after a bolted fault it does not: the guard
% closes with dtheta near 105 deg against a 10 deg limit, so this arm ends
% PENDING_SYNC_FAIL. Demanding SUCCESS here would be asserting an outcome the
% compressed timeline cannot deliver, and relaxing the guard to obtain it would
% be worse. The 120 s scenario is where that question belongs.
r = tc.TestData.r;

j = find(strcmp(cellfun(@(v)char(string(v)),{r.event_log.type}, ...
    'UniformOutput',false),'sg_on'),1);
tc.assertNotEmpty(j,'the sg_on request must reach the log');
tc.verifyTrue(logical(r.event_log(j).applied), ...
    'the reclose request must be ACCEPTED on the reduced network');
tc.verifyGreaterThan(r.event_log(j).t,tc.TestData.T_CLEAR, ...
    'the request must be handled after the line was opened');

% The guard ran: a populated record is what proves the request entered the
% synchronism path rather than being silently dropped.
g = field_or(r,'last_synchronism_guard',struct());
tc.assertTrue(isstruct(g) && isfield(g,'passes'), ...
    'the synchronism guard must have been evaluated');
tc.verifyTrue(isfinite(g.dtheta) && isfinite(g.df) && isfinite(g.dV), ...
    'the guard must report finite angle, frequency and voltage differences');

% The outcome is recorded as a defined token, whichever way it went. No claim is
% made here about which one; the assertion is that the kernel reached a decision
% instead of leaving the request dangling.
tc.verifyTrue(ismember(char(string(r.reclose_status)), ...
    {'SUCCESS','PENDING_SYNC_FAIL','SYNC_TIMEOUT'}), ...
    sprintf('unexpected reclose status "%s"',char(string(r.reclose_status))));
if strcmp(char(string(r.reclose_status)),'SUCCESS')
    tc.verifyGreaterThan(r.actual_reclose_time,tc.TestData.T_CLEAR);
else
    tc.verifyTrue(isnan(r.actual_reclose_time), ...
        'a reclose that did not happen must publish no instant');
end
end

% =========================================================================
% Helpers
% =========================================================================
function [r,scenario] = run_relay_clear_arm()
%RUN_RELAY_CLEAR_ARM  The compressed arm. Settings mirror the delivered
%   scenario suite except for the horizon, so the transition under test is the
%   production transition.
sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp", ...
    case_profile="eecon49_figure4",sg_H=2.5,sg_D=1.0,T_d_on=0.10,T_d_off=1.0);
scenario = cases.scenario_ieee14_1sg_4ibr( ...
    struct('case_profile','eecon49_figure4'));
opt = struct('dt',0.10,'verbose',false,'plot_results',false, ...
    'max_step_subdivisions',9,'state_predictor','linear_kcl', ...
    'automatic_support_supervision',true, ...
    'severity_gamma_on',0.65,'severity_gamma_off',0.35, ...
    'severity_T_d_on',0.10,'severity_T_d_off',1.00, ...
    'healthy_pf_V',sys.pf.bus_voltage(:).', ...
    'healthy_pf_bus_ids',sys.pf.external_bus_ids(:).');
opt.t_end = 1.00;
opt.ibr_events = struct('enabled',true, ...
    'event_profile','line_fault_relay_clear', ...
    'sg_trip',0.90,'fault_on',0.94,'fault_bus',9,'Zf',0.01+0.01i, ...
    'line_fault_clear',0.95,'line_from_bus',9,'line_to_bus',14, ...
    'sg_on',0.98,'coordinated_handback',false, ...
    'automatic_gfm_switching',true, ...
    'delays_overrides',struct('timeout_s',20,'dwell_s',0.5));
opt.stepper = 'adaptive';
opt.atol_x = 1e-6; opt.rtol_x = 1e-4;
opt.atol_y = 1e-5; opt.rtol_y = 1e-4;
opt.dt_max = 0.5; opt.dt_max_armed = 0.05; opt.reject_limit = 12;
r = stability.run_hybrid_case(scenario,opt);
end

function N = candidate_networks(tc)
%CANDIDATE_NETWORKS  Four networks rebuilt from the CASE, not from the kernel.
%   Independence is the point: if these were derived from anything the run
%   returned, a handler bug could satisfy them by construction.
persistent cache
if ~isempty(cache), N = cache; return; end
r = tc.TestData.r;
c = tc.TestData.scenario.case_data;
devs = r.equilibrium.devices;

dae = stability.composite_dae(c,devs,struct('load_model','cz_p_cz_q'));
c_open = c;
br = c_open.mpc.branch;
L = tc.TestData.LINE;
hit = find((br(:,1)==L(1) & br(:,2)==L(2)) | (br(:,1)==L(2) & br(:,2)==L(1)));
assert(numel(hit)==1,'branch %d-%d must be one row',L(1),L(2));
c_open.mpc.branch(hit,11) = 0;
dae_open = stability.composite_dae(c_open,devs, ...
    struct('load_model','cz_p_cz_q'));

fp = r.sched.fault_bus_position;
Zf = r.sched.Zf;
N = struct();
N.dae = dae;
N.pre = dae.Ynet;
N.open = dae_open.Ynet;
N.fault_full = N.pre;  N.fault_full(fp,fp) = N.fault_full(fp,fp)+1/Zf;
N.fault_open = N.open; N.fault_open(fp,fp) = N.fault_open(fp,fp)+1/Zf;
cache = N;
end

function res = residuals(r,k,N)
%RESIDUALS  ||g||_inf of one stored sample against each candidate network.
%   The sample's OWN input vector and event context are used, so the only thing
%   varied is the network.
res = struct();
names = {'pre','open','fault_full','fault_open'};
for q = 1:numel(names)
    g = N.dae.dae_g(r.t(k),r.x_traj(:,k),r.y_traj(:,k),N.(names{q}), ...
        r.u_history(:,k),r.event_context_history{k});
    res.(names{q}) = norm(g,inf);
end
end

function [i_left,i_right] = clearing_sample_indices(tc,r)
k = find(abs(r.t-tc.TestData.T_CLEAR) <= 1e-9);
tc.assertEqual(numel(k),2, ...
    'the clearing instant must carry exactly a left and a right sample');
i_left = k(1); i_right = k(2);
tc.assertEqual(r.sample_side{i_left},'left');
tc.assertEqual(r.sample_side{i_right},'right');
end

function t = t_clear_of(tc)
t = tc.TestData.T_CLEAR;
end

function v = field_or(s,f,d)
v = d;
if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); end
end
