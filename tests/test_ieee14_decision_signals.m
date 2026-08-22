function tests = test_ieee14_decision_signals()
%TEST_IEEE14_DECISION_SIGNALS  Decision-bundle contract (no graphics, no run).
%   Falsification targets:
%     1. Silent degradation when the run never published the reference-AGSI
%        overlay. The option is opt-in and defaults false
%        (ts_simulate_ibr_hybrid.m:1473), and the admittance log the overlay
%        needs exists only under the same option, so the terms cannot be
%        recovered afterwards. A decision page with a blank sub-index panel would
%        misrepresent the run, so the bundle must refuse with a named identifier.
%        This test is the regression guard for the defect that produced the
%        delivered chronology without the overlay.
%     2. A severity reconstruction that does not match the engine's own
%        expression, or that silently tolerates disagreement between the overlay
%        COI and the published COI when the kernel computes it three ways.
%     3. Reference ownership inferred from "the first GFM" rather than read from
%        the accepted hybrid-state history, and multi-island ownership truncated
%        without a count.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath')))); pf_init_paths();
end

% =========================================================================
% Fail-closed contract
% =========================================================================

function test_absent_overlay_fails_closed(tc)
r = fixture();
r = rmfield(r,'agsi_reference');
tc.verifyError(@() ieee14_switch_decision_signals(r), ...
    'ieee14_switch_decision_signals:overlayAbsent');
end

function test_overlay_without_status_fails_closed(tc)
r = fixture();
r.agsi_reference = rmfield(r.agsi_reference,'status');
tc.verifyError(@() ieee14_switch_decision_signals(r), ...
    'ieee14_switch_decision_signals:overlayMalformed');
end

function test_every_non_ok_status_fails_closed(tc)
for s = {'OVERLAY_FAILED','NO_SAMPLES','NO_IBR_DEVICES','OK_NO_SCR_TOPOLOGY_LOG'}
    r = fixture();
    r.agsi_reference.status = s{1};
    tc.verifyError(@() ieee14_switch_decision_signals(r), ...
        'ieee14_switch_decision_signals:overlayNotOk', ...
        sprintf('status "%s" must refuse',s{1}));
end
end

function test_missing_term_fails_closed(tc)
for name = {'J_V','J_f','J_R','J_P','J_lock','J_SCR'}
    r = fixture();
    r.agsi_reference.terms = rmfield(r.agsi_reference.terms,name{1});
    tc.verifyError(@() ieee14_switch_decision_signals(r), ...
        'ieee14_switch_decision_signals:overlayIncomplete', ...
        sprintf('missing %s must refuse',name{1}));
end
end

function test_sample_count_mismatch_fails_closed(tc)
r = fixture();
r.t = r.t(1:end-1);
tc.verifyError(@() ieee14_switch_decision_signals(r), ...
    'ieee14_switch_decision_signals:sampleCountMismatch');
end

function test_unmappable_device_fails_closed(tc)
r = fixture();
r.agsi_reference.device_ids = {'IBR2','IBR3','IBR6','IBR9'};
tc.verifyError(@() ieee14_switch_decision_signals(r), ...
    'ieee14_switch_decision_signals:deviceMappingFailed');
end

% =========================================================================
% Severity reconstruction and the COI cross-check
% =========================================================================

function test_severity_matches_an_independent_recomputation(tc)
r = fixture();
d = ieee14_switch_decision_signals(r);
JV = r.agsi_reference.terms.J_V;
Jf = r.agsi_reference.terms.J_f;
expected = min(1,max(0,0.5*JV + 0.5*Jf));
tc.verifyEqual(d.S,expected,'AbsTol',0);
end

function test_severity_is_saturated_into_the_unit_interval(tc)
r = fixture();
r.agsi_reference.terms.J_V(3,:) = 9;      % drives 0.5*JV+0.5*Jf above 1
r.agsi_reference.terms.J_V(4,:) = -9;     % and below 0
d = ieee14_switch_decision_signals(r);
tc.verifyLessThanOrEqual(max(d.S(:)),1);
tc.verifyGreaterThanOrEqual(min(d.S(:)),0);
tc.verifyEqual(d.S(3,1),1,'AbsTol',0);
tc.verifyEqual(d.S(4,1),0,'AbsTol',0);
end

function test_coi_disagreement_fails_closed(tc)
r = fixture();
r.agsi_reference.f_coi_Hz(5) = r.agsi_reference.f_coi_Hz(5) + 1e-6;
tc.verifyError(@() ieee14_switch_decision_signals(r), ...
    'ieee14_switch_decision_signals:coiDisagreement');
end

function test_coi_agreement_within_tolerance_is_accepted(tc)
r = fixture();
r.agsi_reference.f_coi_Hz(5) = r.agsi_reference.f_coi_Hz(5) + 1e-13;
d = ieee14_switch_decision_signals(r);
tc.verifyLessThanOrEqual(d.diagnostics.coi_residual_Hz,1e-9);
end

function test_gamma_thresholds_come_from_the_caller(tc)
% severity_gamma_on/off are top-level run options and are not republished in
% result.metadata, so they cannot be recovered from the result.
r = fixture();
d1 = ieee14_switch_decision_signals(r);
tc.verifyEqual(d1.gamma_on,0.65,'AbsTol',0);
tc.verifyEqual(d1.gamma_off,0.35,'AbsTol',0);
d2 = ieee14_switch_decision_signals(r,gamma_on=0.8,gamma_off=0.2);
tc.verifyEqual(d2.gamma_on,0.8,'AbsTol',0);
tc.verifyEqual(d2.gamma_off,0.2,'AbsTol',0);
end

% =========================================================================
% Mode and reference-owner traces
% =========================================================================

function test_mode_trace_is_read_per_device_row(tc)
r = fixture();
d = ieee14_switch_decision_signals(r);
tc.verifyEqual(size(d.mode_gfm),[numel(r.t) 4]);
% Device rows 2..5 of the fixture switch to gfm at sample 6 onwards.
tc.verifyFalse(any(d.mode_gfm(1,:)));
tc.verifyTrue(all(d.mode_gfm(end,:)));
tc.verifyEqual(d.device_result_rows,2:5);
end

function test_reference_owner_codes_sg_as_zero_and_ibr_by_position(tc)
r = fixture();
d = ieee14_switch_decision_signals(r);
tc.verifyEqual(d.ref_code(1),0);      % SG owns the reference at t=0
tc.verifyEqual(d.ref_code(end),1);    % IBR2 (overlay column 1) owns it at the end
end

function test_multi_island_ownership_is_counted_not_truncated_silently(tc)
r = fixture();
r.event_context_history{4}.hybrid_state.reference_owner_indices = [2 3];
tc.verifyWarning(@() ieee14_switch_decision_signals(r), ...
    'ieee14_switch_decision_signals:multiIslandOwnership');
w = warning('off','ieee14_switch_decision_signals:multiIslandOwnership');
d = ieee14_switch_decision_signals(r);
warning(w);
tc.verifyEqual(d.ref_owner_count(4),2);
tc.verifyEqual(d.diagnostics.multi_island_samples,1);
end

function test_bundle_publishes_the_decision_contract(tc)
r = fixture();
d = ieee14_switch_decision_signals(r);
tc.verifyEqual(d.decision_contract.consumed_by_supervisor,{'S','J_V','J_f'});
tc.verifyEqual(d.decision_contract.reference_only, ...
    {'J_R','J_P','J_lock','J_SCR'});
tc.verifyEqual(d.decision_contract.aggregate_index,'NOT_FORMED_BY_DESIGN');
tc.verifyEqual(d.decision_contract.classification,'ASSUMED_DIAGNOSTIC');
end

% =========================================================================
function r = fixture()
nt = 12; m = 4;
t = linspace(0,250,nt)';
f = 60 - 0.01*(1:nt)';
r = struct();
r.t = t;
r.coi_frequency_Hz = f;
r.device_ids = {'SG1','IBR2','IBR3','IBR6','IBR8'};
r.device_bus_ids = [1 2 3 6 8];
r.device_online_history = true(5,nt);
modes = [repmat({'synchronous'},1,nt); repmat({'gfl'},4,nt)];
modes(2:5,6:end) = repmat({'gfm'},4,nt-5);
r.device_modes_history = modes;
r.event_context_history = cell(1,nt);
for k = 1:nt
    owner = 1;                       % SG
    if k >= 6, owner = 2; end        % IBR2
    r.event_context_history{k} = struct('hybrid_state', ...
        struct('reference_owner_indices',owner));
end
terms = struct();
terms.J_V    = 0.10*ones(nt,m) + 0.01*(1:m);
terms.J_f    = repmat(abs(f-60)/0.5,1,m);
terms.J_R    = 0.20*ones(nt,m);
terms.J_P    = 0.30*ones(nt,m);
terms.J_lock = zeros(nt,m);
terms.J_SCR  = 0.40*ones(nt,m);
in_band = struct();
for fn = fieldnames(terms).'
    in_band.(fn{1}) = terms.(fn{1}) <= 1;
end
r.agsi_reference = struct( ...
    'status','OK', ...
    'classification','ASSUMED_DIAGNOSTIC', ...
    'aggregate_index','NOT_FORMED_BY_DESIGN', ...
    'bases',struct('dV_pu',0.10,'df_Hz',0.50,'rocof_Hz_s',1.0, ...
        'dP_pu',0.20,'scr_floor',3.0,'vq_pu',0.10,'f0_Hz',60), ...
    't',t,'device_ids',{{'IBR2','IBR3','IBR6','IBR8'}}, ...
    'device_indices',2:5,'terms',terms,'in_band',in_band, ...
    'online',true(nt,m),'mode',{modes(2:5,:).'}, ...
    'scr',5*ones(nt,m),'f_coi_Hz',f,'rocof_Hz_s',zeros(nt,1));
end
