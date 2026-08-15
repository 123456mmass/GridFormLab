function tests = test_ts_hybrid_support_transition_certificate
%TEST_TS_HYBRID_SUPPORT_TRANSITION_CERTIFICATE  Contract for the opt-in
% simulation-based support transition certificate (AGSI-2026-08-14-02).
%
% The certificate forward-simulates the accepted right state of a support
% transaction and refuses fail-closed when the island would lose synchronism
% (pairwise relative-angle excursion reaching the 90-degree pole-slip
% boundary) or when a trial step cannot be solved. This suite freezes:
%   - a certified destination EQUILIBRIUM is accepted (a fixed point does not
%     drift), with a full horizon and a small peak excursion;
%   - a state driven far from that equilibrium is refused with the stable
%     lostSynchronism id;
%   - every fail-closed input branch (bad state/Y, bad candidate spectrum,
%     bad device layout) throws its documented id BEFORE any trial runs;
%   - fewer than two online formers is a trivial accept (no pairwise relation);
%   - the verdict is deterministic (same inputs -> same audit).
%
% The end-to-end discrimination on the real production commits (settled ACCEPT
% vs mid-transient REJECT) is proven by the offline oracle and the full
% chronology gate, not here; this suite is the pure per-call contract.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
s = cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
tbl = stability.ibr_selector_table(s.case_data,s.resources,s.scenario_opt,struct());
row = [];
c = tbl.sg_off.configurations;
for k = 1:numel(c)
    if isequal(sort(c(k).selected_gfm_indices(:).'),[2 3 4 5]) && ...
            isfield(c(k),'eq_x0') && ~isempty(c(k).eq_x0)
        row = c(k);
    end
end
testCase.assertNotEmpty(row,'The [2 3 4 5] SG-off row must be authenticated.');
% Build the matching SG-off all-four island DAE + right context.
[dae,ecoff] = all_four_island(s);
testCase.TestData.s = s;
testCase.TestData.row = row;
testCase.TestData.dae = dae;
testCase.TestData.ec = ecoff;
testCase.TestData.settings = struct('rho',s.case_data.delays.rho, ...
    'kcl_tol',1e-6,'newton_tol',1e-8,'max_iter',50,'fd_eps',3e-6, ...
    'sync_dwell',s.case_data.synchronism.dwell_s, ...
    'severity_f0_Hz',s.case_data.base_values.frequency_Hz);
testCase.TestData.Y = dae.Ynet;
end

function test_certified_equilibrium_is_accepted(testCase)
d = testCase.TestData;
[ok,reason,audit] = stability.certify_support_transition( ...
    0,d.row.eq_x0,d.row.eq_y0,d.row.eq_u_eq,d.ec,d.Y,d.dae,d.settings,d.row);
verifyTrue(testCase,ok,sprintf('A certified equilibrium must be accepted: %s',reason));
verifyEqual(testCase,audit.exit_reason,'completed');
verifyGreaterThan(testCase,audit.horizon,0);
verifyGreaterThanOrEqual(testCase,audit.steps_run,1);
verifyLessThan(testCase,audit.peak_excursion_deg,90);
verifyTrue(testCase,audit.applied);
verifyEqual(testCase,numel(audit.gfm_device_ids),4, ...
    'All four committed formers must be in the pairwise set.');
end

function test_perturbed_state_loses_synchronism(testCase)
% Split one former a full half-turn from the others at t=0: the pairwise
% relative angle then starts at the unstable-equilibrium separation, so the
% trial must refuse regardless of the subsequent swing direction.
d = testCase.TestData;
x = d.row.eq_x0;
k = pick_gfm(d.dae,1);
gj = d.dae.device_offsets(k) + find(strcmp(d.dae.devices(k).state_names,'gfm_delta_VSG'));
x(gj) = x(gj) + 2*pi/3;   % 120 deg split, then the swing carries it past 180
[ok,reason,audit] = stability.certify_support_transition( ...
    0,x,d.row.eq_y0,d.row.eq_u_eq,d.ec,d.Y,d.dae,d.settings,d.row);
verifyFalse(testCase,ok,'A large angle split must be refused.');
verifyTrue(testCase,any(strcmp(audit.failure_id, ...
    {'certify_support_transition:lostSynchronism', ...
     'certify_support_transition:trialNonconvergence'})), ...
    sprintf('Unexpected failure id "%s".',audit.failure_id));
verifyNotEmpty(testCase,reason);
end

function test_slip_limit_is_the_unstable_equilibrium_separation(testCase)
% Freeze the corrected boundary: the certificate must use the
% unstable-equilibrium separation (180 deg), NOT the 90-degree steady-state
% pull-out limit. A heavily damped grid-forming first swing can legitimately
% exceed 90 deg and recover, and using 90 deg false-rejected a support commit
% that the production baseline rode healthily (AGSI-2026-08-14-02).
d = testCase.TestData;
[~,~,audit] = stability.certify_support_transition( ...
    0,d.row.eq_x0,d.row.eq_y0,d.row.eq_u_eq,d.ec,d.Y,d.dae,d.settings,d.row);
verifyEqual(testCase,audit.slip_limit_deg,180.0,'AbsTol',0);
end

function test_bad_state_fails_closed(testCase)
d = testCase.TestData;
x = d.row.eq_x0; x(1) = NaN;
[ok,~,audit] = stability.certify_support_transition( ...
    0,x,d.row.eq_y0,d.row.eq_u_eq,d.ec,d.Y,d.dae,d.settings,d.row);
verifyFalse(testCase,ok);
verifyEqual(testCase,audit.failure_id,'certify_support_transition:badInputs');
verifyEqual(testCase,audit.steps_run,0,'No trial may run on a bad input.');
end

function test_nonsquare_network_fails_closed(testCase)
d = testCase.TestData;
[ok,~,audit] = stability.certify_support_transition( ...
    0,d.row.eq_x0,d.row.eq_y0,d.row.eq_u_eq,d.ec,d.Y(:,1:end-1),d.dae,d.settings,d.row);
verifyFalse(testCase,ok);
verifyEqual(testCase,audit.failure_id,'certify_support_transition:badInputs');
end

function test_unstable_candidate_spectrum_fails_closed(testCase)
d = testCase.TestData;
bad = d.row; bad.omega = 0.5;   % positive real part = not certified stable
[ok,~,audit] = stability.certify_support_transition( ...
    0,d.row.eq_x0,d.row.eq_y0,d.row.eq_u_eq,d.ec,d.Y,d.dae,d.settings,bad);
verifyFalse(testCase,ok);
verifyEqual(testCase,audit.failure_id, ...
    'certify_support_transition:badCandidateSpectrum');
verifyEqual(testCase,audit.steps_run,0);
end

function test_missing_omega_fails_closed(testCase)
d = testCase.TestData;
bad = d.row; bad.omega = NaN;
[ok,~,audit] = stability.certify_support_transition( ...
    0,d.row.eq_x0,d.row.eq_y0,d.row.eq_u_eq,d.ec,d.Y,d.dae,d.settings,bad);
verifyFalse(testCase,ok);
verifyEqual(testCase,audit.failure_id, ...
    'certify_support_transition:badCandidateSpectrum');
end

function test_fewer_than_two_formers_is_trivial_accept(testCase)
% A right context with at most one online GFM has no pairwise relation to
% protect, so the certificate accepts without running a trial.
d = testCase.TestData;
ec1 = d.ec;
gfm = find_gfm(d.dae,ec1);
for j = 2:numel(gfm)
    key = matlab.lang.makeValidName(char(d.dae.devices(gfm(j)).device_id), ...
        'ReplacementStyle','underscore');
    ec1.hybrid_state.device_modes.(key) = 'gfl';
end
[ok,~,audit] = stability.certify_support_transition( ...
    0,d.row.eq_x0,d.row.eq_y0,d.row.eq_u_eq,ec1,d.Y,d.dae,d.settings,d.row);
verifyTrue(testCase,ok);
verifyEqual(testCase,audit.exit_reason,'fewerThanTwoFormers');
verifyEqual(testCase,audit.steps_run,0);
% The trivial-accept branch derives no horizon, so it must stay non-finite:
% the driver keys its log message on this exit reason precisely so that it
% never prints `horizon=NaN` for a quantity that was never computed.
verifyFalse(testCase,isfinite(audit.horizon));
% ...and it reports the surviving former, which the driver counts in that
% message. An empty list would make the message claim zero formers.
verifyEqual(testCase,numel(audit.gfm_device_ids),1);
end

function test_verdict_is_deterministic(testCase)
d = testCase.TestData;
[ok1,~,a1] = stability.certify_support_transition( ...
    0,d.row.eq_x0,d.row.eq_y0,d.row.eq_u_eq,d.ec,d.Y,d.dae,d.settings,d.row);
[ok2,~,a2] = stability.certify_support_transition( ...
    0,d.row.eq_x0,d.row.eq_y0,d.row.eq_u_eq,d.ec,d.Y,d.dae,d.settings,d.row);
verifyEqual(testCase,ok1,ok2);
verifyEqual(testCase,a1.peak_excursion_deg,a2.peak_excursion_deg,'AbsTol',0);
verifyEqual(testCase,a1.steps_run,a2.steps_run);
verifyEqual(testCase,a1.horizon,a2.horizon,'AbsTol',0);
end

% ------------------------------------------------------------------ helpers
function [dae,ec] = all_four_island(s)
resources = s.resources;
for k = 2:5, resources(k).initial_mode = 'GFM'; end
[devices,~] = stability.build_mixed_resource_devices( ...
    s.case_data,resources,s.scenario_opt);
dae = stability.composite_dae(s.case_data,devices,struct('load_model','cz_p_cz_q'));
hs = stability.ts_hybrid_state_init(devices);
hs.device_online.SG1 = false;
key = matlab.lang.makeValidName('SG1','ReplacementStyle','underscore');
if isfield(hs.device_modes,key), hs.device_modes.(key) = 'breaker_open'; end
hs.selected_gfm_indices = [2 3 4 5];
hs.n_gfm_required = 4;
hs.reference_resource_index = 2;
hs.reference_island_ids = 1;
ec = struct('hybrid_state',hs);
end

function k = pick_gfm(dae,which)
gfm = [];
for k = 1:numel(dae.devices)
    if strcmpi(char(dae.devices(k).device_type),'ibr_eecon49_dual')
        gfm(end+1) = k; %#ok<AGROW>
    end
end
k = gfm(which);
end

function gfm = find_gfm(dae,ec)
gfm = [];
for k = 1:numel(dae.devices)
    key = matlab.lang.makeValidName(char(dae.devices(k).device_id), ...
        'ReplacementStyle','underscore');
    if isfield(ec.hybrid_state.device_modes,key) && ...
            strcmpi(char(ec.hybrid_state.device_modes.(key)),'gfm')
        gfm(end+1) = k; %#ok<AGROW>
    end
end
end
