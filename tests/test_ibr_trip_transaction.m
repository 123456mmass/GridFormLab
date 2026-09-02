function tests = test_ibr_trip_transaction()
%TEST_IBR_TRIP_TRANSACTION  A converter leaves service mid-run, atomically.
%   Before this capability existed, nothing in the kernel could take a converter
%   out during a run: `device_online=false` was written in four places and every
%   one of them was the synchronous machine. So the question "the converter that
%   is holding up the island dies -- can the framework recover?" could not be
%   asked at all.
%
%   The transaction is ibr_trip_transaction (ts_simulate_ibr_hybrid.m:2230-2551).
%   Its hard part is not removing the device; it is that removing the REFERENCE
%   OWNER must hand the island angle reference to a surviving converter in the
%   SAME transaction, or refuse. A network solved with ownership pointing at a
%   device that is gone would produce numbers with no physical referent.
%
%   Falsified here:
%     1. OWNERSHIP MOVES on an owner outage, to a converter named by an
%        authenticated SG_OFF table row -- never invented on the spot.
%     2. OWNERSHIP DOES NOT MOVE on a non-owner outage, and no other converter's
%        mode changes. A transaction that reshuffled modes it did not need to
%        would perturb integrators for nothing (the AGSI-2026-08-14-01 hazard).
%     3. BOTH the online flag and the mode are written. Either alone leaves an
%        inconsistent snapshot: ts_dynamic_state_indices and per_island_vf_check
%        read `online`, the device's own callbacks read the mode.
%     4. The outage is ATOMIC -- one left sample, one right sample, one instant,
%        and the right sample satisfies KCL on the same network. No intermediate
%        state in which the device is half-gone is ever published.
%     5. The device really stops injecting current afterwards. A `tripped` label
%        with a live injection would be a bookkeeping lie.
%     6. No destination -> REFUSED by name. Tested on the pure selector, because
%        on this case every single-converter row is feasible and therefore the
%        kernel cannot be driven into that branch without fabricating a table.
%
%   Timeline compressed to about two seconds, as test_ts_hybrid_adaptive_rollback
%   does: this is a unit test of the transition, not a physics study. The 120 s
%   scenario in scripts/reporting/run_ieee14_scenario_suite.m is where the
%   trajectory after the outage is the subject; here the subject is the commit.

tests = functiontests(localfunctions);
end

function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath')))); pf_init_paths();
tc.TestData.scenario = cases.scenario_ieee14_1sg_4ibr( ...
    struct('case_profile','eecon49_figure4'));
tc.TestData.T_TRIP = 0.95;
% Two arms, each run once and shared: the transaction is deterministic, and each
% arm takes tens of seconds.
tc.TestData.r_owner = run_outage_arm(tc,'reference_owner');
tc.TestData.r_other = run_outage_arm(tc,3);
end

% =========================================================================
% 1. The owner outage: ownership moves, in one transaction.
% =========================================================================
function test_an_owner_outage_moves_the_reference_to_a_survivor(tc)
r = tc.TestData.r_owner;
[i_left,i_right] = trip_sample_indices(tc,r);

owner_before = owner_at(r,i_left);
owner_after  = owner_at(r,i_right);
tc.assertEqual(numel(owner_before),1,'exactly one reference owner before the outage');
tc.assertEqual(numel(owner_after),1,'exactly one reference owner after the outage');

target = tripped_index(tc,r);
tc.verifyEqual(target,owner_before, ...
    'ibr_trip_target=''reference_owner'' must resolve to the incumbent owner');
tc.verifyNotEqual(owner_after,owner_before, ...
    'the reference must not still be held by the converter that left');
tc.verifyNotEqual(owner_after,target, ...
    'the reference must not point at the device that is gone');
tc.verifyTrue(is_ibr_index(r,owner_after), ...
    'the new owner must be a converter');
tc.verifyTrue(online_at(r,i_right,owner_after), ...
    'the new owner must be in service');
tc.verifyEqual(mode_at(r,i_right,owner_after),'GFM', ...
    'the new owner must be grid-forming');
end

function test_the_destination_is_an_authenticated_table_row(tc)
% The committed set must be a row the selector table already certified, not a
% set assembled at the event. This is what keeps the equilibrium/SSSA evidence
% behind the configuration the run continues on.
r = tc.TestData.r_owner;
[~,i_right] = trip_sample_indices(tc,r);
hs = hybrid_at(r,i_right);
selected = sort(field_or(hs,'selected_gfm_indices',[]));
tc.assertNotEmpty(selected,'a committed selection must be published');

cfgs = tc.TestData.tbl.sg_off.configurations;
match = false;
for k = 1:numel(cfgs)
    c = cfgs(k);
    if isequal(sort(c.selected_gfm_indices(:).'),selected(:).') && ...
            isequal(c.feasible,true) && isequal(c.ready_to_commit,true)
        match = true; break;
    end
end
tc.verifyTrue(match, sprintf(['committed selection %s is not a feasible, ' ...
    'ready-to-commit SG_OFF row'],mat2str(selected)));

% The event log must carry the same tuple it committed, so the artifact is
% self-describing rather than requiring a re-derivation.
e = trip_log_entry(tc,r);
tc.verifyEqual(sort(e.selected_gfm_indices(:).'),selected(:).');
tc.verifyEqual(e.reference_resource_index,owner_at(r,i_right));
end

function test_the_committed_fingerprint_records_the_outage(tc)
% Provenance: a reader of the artifact must be able to see that this
% configuration was committed BY an outage and which device left.
r = tc.TestData.r_owner;
[~,i_right] = trip_sample_indices(tc,r);
fp = char(string(field_or(hybrid_at(r,i_right),'committed_config_fingerprint','')));
tc.verifySubstring(fp,'ibr_trip_');
tc.verifySubstring(fp,char(r.device_ids{tripped_index(tc,r)}));
end

% =========================================================================
% 2. The non-owner outage changes nothing it does not have to.
% =========================================================================
function test_a_non_owner_outage_leaves_ownership_and_every_mode_alone(tc)
r = tc.TestData.r_other;
[i_left,i_right] = trip_sample_indices(tc,r);
target = tripped_index(tc,r);

tc.assertNotEqual(target,owner_at(r,i_left), ...
    'fixture precondition: device 3 must not be the reference owner');
tc.verifyEqual(owner_at(r,i_right),owner_at(r,i_left), ...
    'a non-owner outage must not move the reference');
tc.verifyEqual(sort(field_or(hybrid_at(r,i_right),'selected_gfm_indices',[])), ...
    sort(field_or(hybrid_at(r,i_left),'selected_gfm_indices',[])), ...
    'a non-owner outage must not change the grid-forming set');

% Every OTHER device keeps its mode and its online flag across the instant.
for d = 1:numel(r.device_ids)
    if d == target, continue; end
    tc.verifyEqual(mode_at(r,i_right,d),mode_at(r,i_left,d), ...
        sprintf('device %s changed mode during an unrelated outage', ...
            r.device_ids{d}));
    tc.verifyEqual(online_at(r,i_right,d),online_at(r,i_left,d), ...
        sprintf('device %s changed online state during an unrelated outage', ...
            r.device_ids{d}));
end
e = trip_log_entry(tc,r);
tc.verifySubstring(e.details,'did not own');
end

% =========================================================================
% 3. Both halves of the snapshot are written.
% =========================================================================
function test_the_outgoing_converter_is_offline_and_in_tripped_mode(tc)
% BOTH, on both arms. `set_context_mode` forces online=true on every transfer
% (eecon49_dual_mode_model.m), so writing only the mode would leave the device
% counted as in service by everything that reads the online flag.
for arm = ["r_owner","r_other"]
    r = tc.TestData.(arm);
    [~,i_right] = trip_sample_indices(tc,r);
    target = tripped_index(tc,r);
    tc.verifyFalse(online_at(r,i_right,target), ...
        sprintf('%s: the outgoing converter must be offline',arm));
    tc.verifyEqual(lower(mode_at(r,i_right,target)),'tripped', ...
        sprintf('%s: the outgoing converter must be in tripped mode',arm));
    % And it stays out: there is no converter reclose mechanism, so an outage is
    % permanent by construction. If that ever stopped being true it would show up
    % here rather than as a puzzling recovery in a figure.
    for k = i_right:numel(r.t)
        tc.verifyFalse(online_at(r,k,target), ...
            sprintf('%s: converter came back at t=%.4f',arm,r.t(k)));
    end
end
end

function test_the_outgoing_converter_stops_injecting_current(tc)
% The physical consequence. A device labelled offline while still injecting would
% make every power balance in the artifact wrong.
for arm = ["r_owner","r_other"]
    r = tc.TestData.(arm);
    [i_left,i_right] = trip_sample_indices(tc,r);
    target = tripped_index(tc,r);
    tc.verifyGreaterThan(abs(r.device_currents(target,i_left)),1e-6, ...
        sprintf('%s: fixture precondition -- the converter was carrying current',arm));
    for k = i_right:numel(r.t)
        tc.verifyLessThan(abs(r.device_currents(target,k)),1e-9, ...
            sprintf('%s: tripped converter still injects at t=%.4f',arm,r.t(k)));
    end
    tc.verifyLessThan(max(abs(r.device_P(target,i_right:end))),1e-9);
    tc.verifyLessThan(max(abs(r.device_Q(target,i_right:end))),1e-9);
end
end

% =========================================================================
% 4. Atomicity and the right-limit solve.
% =========================================================================
function test_the_outage_is_one_atomic_transition(tc)
for arm = ["r_owner","r_other"]
    r = tc.TestData.(arm);
    k = find(abs(r.t-tc.TestData.T_TRIP) <= 1e-9);
    tc.verifyEqual(numel(k),2, ...
        sprintf('%s: the outage instant must carry exactly two samples',arm));
    tc.verifyEqual(r.sample_side(k),{'left','right'}, ...
        sprintf('%s: the pair must be a left limit then a right limit',arm));
    % One transaction id, shared by the pair: that is what makes them one commit
    % rather than two independent events at the same time.
    tc.verifyEqual(r.transaction_id(k(1)),r.transaction_id(k(2)), ...
        sprintf('%s: the pair must belong to one transaction',arm));
    e = trip_log_entry(tc,r);
    tc.verifyTrue(logical(e.applied));
    tc.verifyEmpty(char(string(field_or(e,'failure_id',''))));
end
end

function test_the_right_limit_sample_satisfies_kcl_independently(tc)
% Recomputed from a freshly assembled composite DAE rather than read from the
% kernel's own residual, so this is an independent check that the published
% post-outage state is a solution of the network with the device gone.
KCL_TOL = 1e-6;   % settings.kcl_tol, the kernel's own right-limit contract
for arm = ["r_owner","r_other"]
    r = tc.TestData.(arm);
    dae = shared_dae(tc,r);
    [~,i_right] = trip_sample_indices(tc,r);
    g = dae.dae_g(r.t(i_right),r.x_traj(:,i_right),r.y_traj(:,i_right), ...
        dae.Ynet,r.u_history(:,i_right),r.event_context_history{i_right});
    tc.verifyLessThan(norm(g,inf),KCL_TOL, ...
        sprintf('%s: post-outage sample must satisfy network KCL',arm));
    % The outage removes a device, not a branch: the admittance is untouched.
    e = trip_log_entry(tc,r);
    tc.verifyLessThan(e.right_kcl_norm,KCL_TOL);
end
end

function test_the_supervisor_is_locked_out_immediately_after_the_outage(tc)
% The outage invalidates dwell timers accumulated on a configuration that no
% longer exists, so the kernel arms the ordinary post-transaction lockout
% (ts_simulate_ibr_hybrid.m:768-769). Without it the supervisor could commit a
% second configuration change in the same millisecond on stale evidence.
for arm = ["r_owner","r_other"]
    r = tc.TestData.r_owner; if arm=="r_other", r = tc.TestData.r_other; end
    t_trip = tc.TestData.T_TRIP;
    types = cellfun(@(v)char(string(v)),{r.event_log.type},'UniformOutput',false);
    sup = find(startsWith(types,'gfm_support_'));
    for j = sup
        tc.verifyTrue(r.event_log(j).t < t_trip - 1e-9 || ...
                      r.event_log(j).t > t_trip + 1e-9, ...
            sprintf('%s: a support transaction landed on the outage instant',arm));
    end
end
end

% =========================================================================
% 5. No destination is refused by name -- on the pure selector.
%    The kernel branch that raises ibrTripNoSurvivingConfiguration cannot be
%    reached on this case: every single-converter SG_OFF row ({2},{3},{4},{5})
%    is feasible and ready, so whichever converter leaves, a destination exists.
%    Driving the kernel there would require a fabricated table, which would test
%    the fabrication. The refusal LOGIC lives in the pure selector, so that is
%    where it is falsified.
% =========================================================================
function test_the_selector_refuses_when_no_row_survives(tc)
tbl = tc.TestData.tbl;
[cand,found,audit] = stability.select_post_outage_candidate(tbl,[],[2]);
tc.verifyFalse(found,'no survivors can carry no configuration');
tc.verifyEmpty(fieldnames(cand));
tc.verifyEqual(audit.reason,'NO_AUTHENTICATED_FEASIBLE_SURVIVOR_CONFIGURATION');

% A survivor set that no feasible row is a subset of. Device 9 exists in no row.
[~,found9] = stability.select_post_outage_candidate(tbl,[9],[2]);
tc.verifyFalse(found9);
end

function test_the_selector_never_names_a_device_that_left(tc)
% Every eligible row must consist only of survivors, reference included. This is
% the property the kernel asserts again after the fact
% (ibrTripCandidateNamesLostDevice); if it held only there, a table change could
% make the selector propose an impossible destination and rely on an assertion to
% catch it.
tbl = tc.TestData.tbl;
for lost = 2:5
    survivors = setdiff(2:5,lost);
    [cand,found] = stability.select_post_outage_candidate(tbl,survivors,[lost]);
    tc.assertTrue(found, ...
        sprintf('a destination must exist after converter %d leaves',lost));
    sel = cand.selected_gfm_indices(:).';
    tc.verifyFalse(ismember(lost,sel), ...
        sprintf('destination names the lost converter %d',lost));
    tc.verifyTrue(all(ismember(sel,survivors)));
    tc.verifyTrue(ismember(cand.reference_resource_index,survivors));
    tc.verifyTrue(ismember(cand.reference_resource_index,sel));
end
end

function test_the_selector_prefers_the_least_intervention(tc)
% Losing the sole former from {2} must land on a SINGLE-former row, not on the
% four-former row that is also feasible: the outage is not a severity event and
% must not be used as an excuse to promote every converter. Both are authenticated,
% so only the ranking decides, and the ranking is what this pins.
tbl = tc.TestData.tbl;
[cand,found] = stability.select_post_outage_candidate(tbl,[3 4 5],[2]);
tc.assertTrue(found);
tc.verifyEqual(numel(cand.selected_gfm_indices),1, ...
    'the fewest-intervention destination after losing one former is one former');
end

% =========================================================================
% Helpers
% =========================================================================
function r = run_outage_arm(tc,target)
%RUN_OUTAGE_ARM  One compressed arm. Settings mirror the delivered suite except
%   the horizon, so the transaction under test is the production transaction.
sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp", ...
    case_profile="eecon49_figure4",sg_H=2.5,sg_D=1.0,T_d_on=0.10,T_d_off=1.0);
opt = struct('dt',0.10,'verbose',false,'plot_results',false, ...
    'max_step_subdivisions',9,'state_predictor','linear_kcl', ...
    'automatic_support_supervision',true, ...
    'severity_gamma_on',0.65,'severity_gamma_off',0.35, ...
    'severity_T_d_on',0.10,'severity_T_d_off',1.00, ...
    'healthy_pf_V',sys.pf.bus_voltage(:).', ...
    'healthy_pf_bus_ids',sys.pf.external_bus_ids(:).');
opt.t_end = 1.20;
opt.ibr_events = struct('enabled',true, ...
    'event_profile','sg_trip_then_former_outage', ...
    'sg_trip',0.90,'ibr_trip',tc.TestData.T_TRIP,'ibr_trip_target',target, ...
    'automatic_gfm_switching',true, ...
    'delays_overrides',struct('timeout_s',20,'dwell_s',0.5));
opt.stepper = 'adaptive';
opt.atol_x = 1e-6; opt.rtol_x = 1e-4;
opt.atol_y = 1e-5; opt.rtol_y = 1e-4;
opt.dt_max = 0.5; opt.dt_max_armed = 0.05; opt.reject_limit = 12;
r = stability.run_hybrid_case(tc.TestData.scenario,opt);
% The selector table is rebuilt here once, from the same inputs run_hybrid_case
% uses, so the assertions about "an authenticated row" are checked against the
% table rather than against the run's own claim about it.
if ~isfield(tc.TestData,'tbl')
    tc.TestData.tbl = stability.ibr_selector_table(tc.TestData.scenario.case_data, ...
        tc.TestData.scenario.resources,tc.TestData.scenario,struct());
end
% The trajectory after the outage is NOT this file's subject: an island that
% loses a converter may or may not survive, and the 120 s scenario is where that
% question is asked. What must hold is that the run reached the outage and
% committed it, which every test below checks explicitly.
assert(any(abs(r.t-tc.TestData.T_TRIP) <= 1e-9), ...
    'the arm must reach the scheduled outage instant');
end

function dae = shared_dae(tc,r)
persistent cache
if isempty(cache), cache = containers.Map(); end
key = sprintf('%d',numel(r.t));
if ~isKey(cache,key)
    cache(key) = stability.composite_dae(tc.TestData.scenario.case_data, ...
        r.equilibrium.devices,struct('load_model','cz_p_cz_q'));
end
dae = cache(key);
end

function [i_left,i_right] = trip_sample_indices(tc,r)
k = find(abs(r.t-tc.TestData.T_TRIP) <= 1e-9);
tc.assertEqual(numel(k),2,'the outage instant must carry a left and a right sample');
i_left = k(1); i_right = k(2);
tc.assertEqual(r.sample_side{i_left},'left');
tc.assertEqual(r.sample_side{i_right},'right');
end

function e = trip_log_entry(tc,r)
types = cellfun(@(v)char(string(v)),{r.event_log.type},'UniformOutput',false);
j = find(strcmp(types,'ibr_trip'),1);
tc.assertNotEmpty(j,'the outage must appear in the event log');
e = r.event_log(j);
end

function idx = tripped_index(tc,r)
e = trip_log_entry(tc,r);
% The log carries the device ID; the index is resolved from it so this helper
% does not depend on a positional field that could drift.
idx = find(strcmp(r.device_ids,char(string(e.tripped_device_id))),1);
tc.assertNotEmpty(idx,'the logged device ID must name a device in the run');
end

function hs = hybrid_at(r,k)
hs = r.event_context_history{k}.hybrid_state;
end

function v = owner_at(r,k)
v = field_or(hybrid_at(r,k),'reference_owner_indices',[]);
end

function m = mode_at(r,k,d)
m = char(string(r.device_modes_history{d,k}));
end

function tf = online_at(r,k,d)
tf = logical(r.device_online_history(d,k));
end

function tf = is_ibr_index(r,d)
tf = ~isempty(d) && d >= 1 && d <= numel(r.device_ids) && ...
    startsWith(char(r.device_ids{d}),'IBR');
end

function v = field_or(s,f,d)
v = d;
if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); end
end
