function tests = test_ts_hybrid_support_certified_input
%TEST_TS_HYBRID_SUPPORT_CERTIFIED_INPUT  A committed configuration must run the
% selector's OWN certified equilibrium input, and a candidate without one must
% be refused fail-closed.
%
% Contract under test (RECLOSE-2026-08-13-01, secondary).
% stability.ibr_candidate_evaluate certifies feasibility and the SSSA margin
% for the PAIR (configuration, eq_u_eq) and stores that input on every
% candidate row; ibr_config_selector persists it into the authenticated table.
% trip_transaction installs it at the SG trip (:1855-1857).
% sg_off_support_transaction previously kept the event-left input for a
% bumpless transfer, so a live augmentation committed the new configuration
% while the PREVIOUS configuration's operating point stayed in force -- on the
% IEEE14 eecon49 arm up to 0.355 pu per unit away from the committed set's own
% certificate -- with only the algebraic right-limit KCL as acceptance.
%
% Redesign (2026-08-13).  The previous version of this file had two proven
% design defects: (1) it bound the contract under test to the AGSI supervisor
% actually firing (a premise that the Dv=20 droop legitimately suppresses), and
% (2) assumeNotEmpty silently turned two cases into filtered results, masking
% any loss of coverage.  This version therefore:
%   T1 asserts the table invariant directly (no TS run): every ready_to_commit
%      row carries finite full-composite eq_u_eq AND eq_x0 certificates.
%      Substantive replacement for the vacuous self-comparison
%      verifyEqual(cc.eq_u_eq, cc.eq_u_eq) in test_ibr_selector_scr_sssa.m.
%   T2 asserts the pairing on the scheduled sg_trip event, which occurs by
%      schedule (sg_trip=1 < t_end), never by supervisor discretion.
%   T3 keeps the support loop but replaces assumeNotEmpty with an exact count
%      assertion (one committed augmentation on this pinned arm).
%   T4 blanks eq_u_eq on the augmentation row and proves BOTH fail-closed
%      layers: (a) with the stored fingerprints kept, the trip itself refuses
%      the table (staleFingerprint -- the candidate-evidence fingerprint covers
%      eq_u_eq, measured 2026-08-13); (b) with the fingerprints recomputed by
%      the canonical serializer, the support transaction itself refuses the
%      uncertified candidate.  No assume* anywhere: a broken premise FAILS.
%
% DOCUMENTED ASYMMETRY (found by T4, recorded per plan I5): the support guard
% fails closed at ts_simulate_ibr_hybrid.m:2310 when eq_u_eq is empty, but the
% false branch of trip_transaction's :1855 keeps the previous input silently.
% That branch is unreachable through the authenticated path (every evaluated
% candidate row carries eq_u_eq, and a table lacking it cannot pass the
% evidence fingerprint), so the two paths disagree only in dead code; the
% support guard is the binding behaviour and is what this file enforces.
%
% Droop pin.  This suite pins Dv=1.50 in the scenario copy it constructs.
% That is a premise-enabling harness choice, NOT a production-value claim:
% 1.50 is the value whose islanded arm stresses the GFL units enough for the
% support supervisor to fire, so T3/T4b have a reachable premise; at the
% owner-set production droop the island is healthy and no augmentation occurs.
% The contract asserted (certificate pairing + fail-closed guard) is
% value-independent; pinning keeps the suite deterministic across the droop
% change and proves the tests were not written in response to it.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
s = cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
s.resources = pin_gfm_dv(s.resources, 1.50);   % premise pin, see header
sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp", ...
    case_profile="eecon49_figure4", sg_H=2.5, sg_D=1.0, T_d_on=0.10, T_d_off=1.0);
tbl = stability.ibr_selector_table(s.case_data, s.resources, s.scenario_opt, struct());
[devices,~] = stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
dae = stability.composite_dae(s.case_data,devices,struct('load_model','cz_p_cz_q'));
opt = arm_opt(tbl, sys);
r = stability.run_hybrid_case(s,opt);
testCase.TestData.scenario = s;
testCase.TestData.result = r;
testCase.TestData.table = tbl;
testCase.TestData.devices = devices;
testCase.TestData.dae = dae;
testCase.TestData.sys = sys;
end

% ------------------------------------------------------------------ T1
function test_table_rows_carry_certified_inputs(testCase)
tbl = testCase.TestData.table;
dae = testCase.TestData.dae;
for ctx = {'sg_off','sg_on'}
    c = tbl.(ctx{1}).configurations;
    ready = find(arrayfun(@(z) isfield(z,'ready_to_commit') && ...
        isequal(z.ready_to_commit,true), c));
    testCase.verifyNotEmpty(ready, sprintf( ...
        'The %s context must authenticate at least one ready candidate.',ctx{1}));
    for k = ready(:).'
        row = c(k);
        input_ok = isfield(row,'eq_u_eq') && ~isempty(row.eq_u_eq) && ...
            isvector(row.eq_u_eq) && numel(row.eq_u_eq)==numel(dae.u0) && ...
            all(isfinite(row.eq_u_eq));
        state_ok = isfield(row,'eq_x0') && ~isempty(row.eq_x0) && ...
            isvector(row.eq_x0) && numel(row.eq_x0)==numel(dae.x0) && ...
            all(isfinite(row.eq_x0));
        testCase.verifyTrue(input_ok, sprintf( ...
            ['Every ready_to_commit %s row must carry a finite certified input ' ...
             'of composite length %d; row %s (n=%d) does not.'], ctx{1}, ...
            numel(dae.u0), mat2str(row.selected_gfm_indices), row.n_gfm_required));
        testCase.verifyTrue(state_ok, sprintf( ...
            ['Every ready_to_commit %s row must carry a finite certified state ' ...
             'of composite length %d; row %s (n=%d) does not.'], ctx{1}, ...
            numel(dae.x0), mat2str(row.selected_gfm_indices), row.n_gfm_required));
    end
end
end

% ------------------------------------------------------------------ T2
function test_trip_commits_exactly_once_on_schedule(testCase)
r = testCase.TestData.result;
testCase.verifyTrue(r.converged, getf(r,'failure_reason','arm must converge'));
ev = events_of_type(r,'sg_trip');
testCase.verifyEqual(numel(ev), 1, ...
    'The scheduled sg_trip must commit exactly once on this arm.');
testCase.verifyTrue(logical(ev(1).applied), ...
    'The scheduled sg_trip must be applied.');
testCase.verifyEqual(ev(1).t, 1.0, 'AbsTol', 0, ...
    'The sg_trip must land at its scheduled time.');
end

function test_trip_input_equals_its_certificate(testCase)
r = testCase.TestData.result;
tbl = testCase.TestData.table;
devices = testCase.TestData.devices;
ev = events_of_type(r,'sg_trip');
testCase.verifyEqual(numel(ev), 1);
e = ev(1);
sel = e.selected_gfm_indices(:).';
cert = certified_input(tbl, sel);
testCase.verifyNotEmpty(cert, sprintf( ...
    'Committed set %s must exist in the authenticated table with eq_u_eq.', ...
    mat2str(sel)));
slots = dual_pq_slots(devices);
testCase.verifyEqual(e.input_after(slots), cert(slots), 'AbsTol', 0, ...
    sprintf(['The trip transaction must run the certified input of the set it ' ...
             'commits (%s); the selector certifies the PAIR (configuration, ' ...
             'eq_u_eq), never the configuration alone.'], mat2str(sel)));
others = setdiff(1:numel(e.input_before), slots);
testCase.verifyEqual(e.input_after(others), e.input_before(others), 'AbsTol', 0, ...
    'The trip must leave every non-dual-P/Q input entry bit-unchanged.');
end

% ------------------------------------------------------------------ T3
function test_support_augmentation_runs_its_certificate(testCase)
r = testCase.TestData.result;
tbl = testCase.TestData.table;
devices = testCase.TestData.devices;
dae = testCase.TestData.dae;
ev = support_events(r);
testCase.verifyEqual(numel(ev), 1, sprintf( ...
    ['This pinned arm commits exactly one support augmentation. Event log: %s ' ...
     '(ts_simulate publishes res.support_supervision_status, but ' ...
     'run_hybrid_case does not propagate it; the event log is the evidence).'], ...
    event_digest(r)));
e = ev(1);
sel = e.selected_gfm_indices(:).';
cert = certified_input(tbl, sel);
cert_state = certified_state(tbl, sel);
testCase.verifyNotEmpty(cert, sprintf( ...
    'Committed support set %s must exist in the authenticated table.', mat2str(sel)));
testCase.verifyNotEmpty(cert_state, sprintf( ...
    'Committed support set %s must carry authenticated eq_x0.', mat2str(sel)));
slots = dual_pq_slots(devices);
testCase.verifyEqual(e.input_after(slots), cert(slots), 'AbsTol', 0, ...
    sprintf(['A committed support transaction must run the certified input of ' ...
             'the set it commits (%s).'], mat2str(sel)));
others = setdiff(1:numel(e.input_before), slots);
testCase.verifyEqual(e.input_after(others), e.input_before(others), 'AbsTol', 0, ...
    'A support transaction must leave every non-dual-P/Q input entry unchanged.');

% NOTE (AGSI-2026-08-14-02). An earlier revision of this test additionally
% asserted that the incumbent EECON49 GFM's gfm_xi_Vd/gfm_xi_Vq are mapped to
% the authenticated eq_x0 at the right sample. That assertion is REMOVED
% because measurement falsified the contract it encoded: at the t=22.0521
% [2 4] commit the untouched arrival rides the transition (19.7 deg, omega ->
% 1.00017, matching the baseline production run) while the same arrival
% conditioned to the destination equilibrium slips to 376 deg. Unconditional
% incumbent conditioning is therefore NOT a runtime contract; conditioning is
% now attempted only behind the opt-in transition certificate, which judges
% each variant by forward simulation. The certified-INPUT pairing asserted
% above (RECLOSE-2026-08-13-01) is unaffected and remains the contract here.
% The conditioning helper's own contract is covered by
% test_ts_hybrid_support_state_conditioning.m and the certificate's by
% test_ts_hybrid_support_transition_certificate.m.
end

% ------------------------------------------------------------------ T4
function test_tampered_state_evidence_fails_closed_at_trip(testCase)
% The candidate-evidence fingerprint covers eq_x0 as well as eq_u_eq. Altering
% the destination-state certificate without recomputing fingerprints must be
% refused by runtime authentication before any event can commit.
s = testCase.TestData.scenario;
sys = testCase.TestData.sys;
sab = mutate_state_row(testCase.TestData.table, [2 3 4 5], 'tamper');
r = stability.run_hybrid_case(s, arm_opt(sab, sys));
testCase.verifyFalse(r.converged, ...
    'A table whose certified state no longer matches its fingerprint must not run.');
ev = events_of_type(r,'sg_trip');
testCase.verifyEqual(numel(ev),1,sprintf( ...
    'The scheduled trip must still be attempted. Event log: %s',event_digest(r)));
testCase.verifyFalse(logical(ev(1).applied));
testCase.verifyTrue(contains(char(string(getf(ev(1),'failure_id',''))), ...
    'staleFingerprint'),sprintf( ...
    'Refusal must name the stale state-evidence fingerprint, got "%s".', ...
    char(string(getf(ev(1),'failure_id','')))));
testCase.verifyEqual(numel(applied_events(r)),0);
end

function test_default_path_does_not_depend_on_eq_x0(testCase)
% AGSI-2026-08-14-02. eq_x0 (the destination-STATE certificate) is consumed
% only by the opt-in transition-certificate path, which conditions incumbent
% voltage-loop memory and judges the result by forward simulation. On the
% DEFAULT path no incumbent is conditioned, so a re-authenticated table whose
% eq_x0 was deleted must run exactly like the intact table: the destination
% state must not be a hidden dependency of the default runtime.
%
% This replaces an earlier revision that asserted the support transaction must
% REFUSE a missing eq_x0. That assertion encoded unconditional incumbent
% conditioning, which measurement falsified: at the t=22.0521 [2 4] commit the
% untouched arrival rides the transition (19.7 deg) while conditioning it to
% the destination equilibrium slips to 376 deg. The certified-INPUT contract
% (eq_u_eq) is unchanged and is still enforced fail-closed by
% test_support_guard_fails_closed_without_certificate below.
s = testCase.TestData.scenario;
sys = testCase.TestData.sys;
sab = mutate_state_row(testCase.TestData.table,[2 3 4 5],'blank');
sab = reauthenticate(sab);
r = stability.run_hybrid_case(s,arm_opt(sab,sys));
testCase.verifyTrue(r.converged,getf(r,'failure_reason', ...
    'The default path must run with no destination-state certificate.'));
ev = events_of_type(r,'gfm_support_augment');
testCase.verifyEqual(numel(ev),1,sprintf( ...
    'Exactly one augmentation attempt is expected. Event log: %s',event_digest(r)));
testCase.verifyTrue(logical(ev(1).applied), ...
    'The default path must not consult eq_x0, so the augmentation still commits.');
% And it must be byte-identical to the intact-table run on this arm.
ref = testCase.TestData.result;
testCase.verifyEqual(r.t,ref.t,'AbsTol',0, ...
    'Deleting eq_x0 must not perturb the default-path trajectory.');
testCase.verifyEqual(r.x_traj,ref.x_traj,'AbsTol',0);
testCase.verifyEqual(r.u_history,ref.u_history,'AbsTol',0);
end

function test_tampered_evidence_fails_closed_at_trip(testCase)
% Layer 1: blank eq_u_eq on the augmentation row but KEEP the stored
% fingerprints. The candidate-evidence fingerprint covers eq_u_eq, so the
% runtime table authentication must refuse the whole table at trip time; no
% configuration may be committed against the tampered evidence.
s = testCase.TestData.scenario;
sys = testCase.TestData.sys;
sab = blank_row(testCase.TestData.table, [2 3 4 5]);
r = stability.run_hybrid_case(s, arm_opt(sab, sys));
testCase.verifyFalse(r.converged, ...
    'A table whose evidence no longer matches its fingerprint must not run.');
ev = events_of_type(r,'sg_trip');
testCase.verifyEqual(numel(ev), 1, sprintf( ...
    'The scheduled trip must still be attempted. Event log: %s', event_digest(r)));
testCase.verifyFalse(logical(ev(1).applied), ...
    'The trip must not apply a table with tampered evidence.');
testCase.verifyTrue(contains(char(string(getf(ev(1),'failure_id',''))), ...
    'staleFingerprint'), sprintf('Refusal must name the stale evidence fingerprint, got "%s".', ...
    char(string(getf(ev(1),'failure_id','')))));
testCase.verifyEqual(numel(applied_events(r)), 0, ...
    'No event may be applied from a table with tampered evidence.');
end

function test_support_guard_fails_closed_without_certificate(testCase)
% Layer 2: blank eq_u_eq on the augmentation row and RE-AUTHENTICATE the table
% with the canonical serializer (so layer 1 passes). The trip then commits the
% certified [3 4] set, and the support transaction itself must refuse the
% uncertified augmentation candidate instead of committing it against the
% previous configuration's input.
s = testCase.TestData.scenario;
sys = testCase.TestData.sys;
sab = blank_row(testCase.TestData.table, [2 3 4 5]);
sab = reauthenticate(sab);
r = stability.run_hybrid_case(s, arm_opt(sab, sys));
testCase.verifyTrue(r.converged, getf(r,'failure_reason', ...
    'The re-authenticated tamper must still run to t_end.'));
ev = events_of_type(r,'gfm_support_augment');
testCase.verifyEqual(numel(ev), 1, sprintf( ...
    'Exactly one augmentation attempt is expected. Event log: %s', event_digest(r)));
testCase.verifyFalse(logical(ev(1).applied), ...
    'An uncertified augmentation candidate must not be committed.');
testCase.verifyEqual(char(string(ev(1).failure_id)), ...
    'ts_simulate_ibr_hybrid:sgOffSupportTransaction');
testCase.verifyTrue(contains(char(string(ev(1).details)), ...
    'no certified equilibrium input'), ...
    'The refusal must name the missing certificate as the reason.');
testCase.verifyEqual(numel(applied_support(r)), 0, ...
    'No support transaction may apply from the tampered table.');
md = r.device_modes_history;
testCase.verifyEqual(md(:,end).', {'sg','gfl','GFM','GFM','gfl'}, ...
    'The island must remain on the certified trip set; no uncertified commit.');
end

% ------------------------------------------------------------------ helpers
function opt = arm_opt(tbl, sys)
opt = struct('dt',0.01,'t_end',2.4,'verbose',false,'plot_results',false, ...
    'max_step_subdivisions',9,'state_predictor','linear_kcl', ...
    'automatic_support_supervision',true, ...
    'severity_gamma_on',0.65,'severity_gamma_off',0.35, ...
    'severity_T_d_on',0.10,'severity_T_d_off',1.00, ...
    'selector_table',tbl, ...
    'healthy_pf_V',sys.pf.bus_voltage(:).', ...
    'healthy_pf_bus_ids',sys.pf.external_bus_ids(:).');
opt.ibr_events = struct('enabled',true,'event_profile','sg_cycle', ...
    'sg_trip',1,'sg_on',2.3,'automatic_gfm_switching',true, ...
    'delays_overrides',struct('timeout_s',18,'dwell_s',0.5));
end

function resources = pin_gfm_dv(resources, dv)
for k = 1:numel(resources)
    dp = resources(k).dynamic_params;
    if isstruct(dp) && isfield(dp,'gfm_eecon49')
        dp.gfm_eecon49.Dv = dv;
        resources(k).dynamic_params = dp;
    end
end
end

function tbl2 = blank_row(tbl, sel_target)
tbl2 = tbl;
c = tbl2.sg_off.configurations;
for k = 1:numel(c)
    sel = sort(c(k).selected_gfm_indices(:)).';
    if isequal(sel, sort(sel_target(:).'))
        c(k).eq_u_eq = [];
    end
end
tbl2.sg_off.configurations = c;
end

function tbl2 = mutate_state_row(tbl, sel_target, action)
tbl2 = tbl;
c = tbl2.sg_off.configurations;
matched = 0;
for k = 1:numel(c)
    sel = sort(c(k).selected_gfm_indices(:)).';
    if ~isequal(sel,sort(sel_target(:).')), continue; end
    matched = matched + 1;
    if strcmp(action,'blank')
        c(k).eq_x0 = [];
    elseif strcmp(action,'tamper')
        if isempty(c(k).eq_x0)
            error('test_ts_hybrid_support_certified_input:emptyState', ...
                'Target row must carry eq_x0 before tampering.');
        end
        c(k).eq_x0(1) = c(k).eq_x0(1) + 1e-6;
    else
        error('test_ts_hybrid_support_certified_input:badAction', ...
            'Unknown state mutation action %s.',action);
    end
end
assert(matched==1,'Expected one exact SG_OFF candidate row.');
tbl2.sg_off.configurations = c;
end

function tbl = reauthenticate(tbl)
evidence = struct('sg_off_configurations',tbl.sg_off.configurations, ...
    'sg_on_configurations',tbl.sg_on.configurations);
[fp,ifp,efp] = compute_selector_table_fingerprint(tbl.selector_auth_inputs,evidence);
tbl.selector_input_fingerprint = ifp;
tbl.candidate_evidence_fingerprint = efp;
tbl.selector_table_fingerprint = fp;
end

function ev = events_of_type(r, ty)
ev = [];
if ~isfield(r,'event_log') || isempty(r.event_log), return; end
for k = 1:numel(r.event_log)
    e = r.event_log(k);
    if strcmp(char(string(e.type)), ty)
        if isempty(ev), ev = e; else, ev(end+1) = e; end %#ok<AGROW>
    end
end
end

function ev = support_events(r)
ev = [];
if ~isfield(r,'event_log') || isempty(r.event_log), return; end
for k = 1:numel(r.event_log)
    e = r.event_log(k);
    ty = char(string(e.type));
    if ~startsWith(ty,'gfm_support_'), continue; end
    if ~isfield(e,'applied') || ~isequal(logical(e.applied),true), continue; end
    if isempty(e.input_before) || isempty(e.input_after), continue; end
    if isempty(ev), ev = e; else, ev(end+1) = e; end %#ok<AGROW>
end
end

function ev = applied_support(r)
ev = support_events(r);
end

function ev = applied_events(r)
ev = [];
if ~isfield(r,'event_log') || isempty(r.event_log), return; end
for k = 1:numel(r.event_log)
    e = r.event_log(k);
    if isfield(e,'applied') && isequal(logical(e.applied),true)
        if isempty(ev), ev = e; else, ev(end+1) = e; end %#ok<AGROW>
    end
end
end

function txt = event_digest(r)
parts = {};
if isfield(r,'event_log')
    for k = 1:numel(r.event_log)
        e = r.event_log(k);
        parts{end+1} = sprintf('%s(applied=%d)', char(string(e.type)), ...
            double(logical(getf(e,'applied',false)))); %#ok<AGROW>
    end
end
if isempty(parts), txt = '<empty>'; else, txt = strjoin(parts,', '); end
end

function u = certified_input(tbl, sel)
u = [];
if ~isfield(tbl,'sg_off') || ~isfield(tbl.sg_off,'configurations'), return; end
c = tbl.sg_off.configurations;
for k = 1:numel(c)
    s2 = c(k).selected_gfm_indices(:).';
    if numel(s2)==numel(sel) && all(sort(s2)==sort(sel))
        if isfield(c(k),'eq_u_eq') && ~isempty(c(k).eq_u_eq)
            u = c(k).eq_u_eq(:);
        end
        return;
    end
end
end

function x = certified_state(tbl, sel)
x = [];
if ~isfield(tbl,'sg_off') || ~isfield(tbl.sg_off,'configurations'), return; end
c = tbl.sg_off.configurations;
for k = 1:numel(c)
    s2 = c(k).selected_gfm_indices(:).';
    if numel(s2)==numel(sel) && all(sort(s2)==sort(sel))
        if isfield(c(k),'eq_x0') && ~isempty(c(k).eq_x0)
            x = c(k).eq_x0(:);
        end
        return;
    end
end
end

function [left,right] = transaction_samples(r,tx_id)
left = find(r.transaction_id==tx_id & strcmp(r.sample_side,'left'));
right = find(r.transaction_id==tx_id & strcmp(r.sample_side,'right'));
assert(numel(left)==1 && numel(right)==1, ...
    'An applied support transaction must own exactly one left/right sample pair.');
end

function modes = context_modes(dae,ec)
modes = cell(1,numel(dae.devices));
for k = 1:numel(dae.devices)
    key = matlab.lang.makeValidName(char(dae.devices(k).device_id), ...
        'ReplacementStyle','underscore');
    modes{k} = char(ec.hybrid_state.device_modes.(key));
end
end

function gi = gfm_voltage_integrator_indices(dae,k)
names = dae.devices(k).state_names;
ld = find(strcmp(names,'gfm_xi_Vd'));
lq = find(strcmp(names,'gfm_xi_Vq'));
assert(numel(ld)==1 && numel(lq)==1);
gi = dae.device_offsets(k)+[ld lq];
end

function slots = dual_pq_slots(devices)
% Global input indices of P_ref/Q_ref for every ibr_eecon49_dual device.
slots = [];
off = 0;
for k = 1:numel(devices)
    dev = devices(k);
    if isfield(dev,'device_type') && strcmpi(char(dev.device_type),'ibr_eecon49_dual')
        for wanted = ["P_ref","Q_ref"]
            j = find(strcmpi(string(dev.input_names), wanted));
            slots = [slots, off + j]; %#ok<AGROW>
        end
    end
    off = off + dev.nu;
end
slots = sort(slots);
end

function v = getf(s, f, d)
if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
