function tests = test_ts_hybrid_agsi_reference
%TEST_TS_HYBRID_AGSI_REFERENCE  The reference-AGSI overlay must be inert.
%
% The SG-off support supervisor consumes J_V and J_f only. This file is the
% instrument for that boundary: enabling the reference overlay must leave every
% trajectory array, every switching-decision field and the whole event log
% byte-identical, and must leave the result schema untouched when the option is
% omitted. If a future edit lets any reference term reach the severity scalar,
% the hysteresis, the dwell timers or a candidate decision, these assertions
% fail.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function [scenario,opt] = short_arm()
sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp", ...
    case_profile="eecon49_figure4", sg_H=2.5, sg_D=1.0, T_d_on=0.10, T_d_off=1.0);
scenario = cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
opt = struct('dt',0.10,'verbose',false,'plot_results',false, ...
    'max_step_subdivisions',9,'state_predictor','linear_kcl', ...
    'automatic_support_supervision',true, ...
    'severity_gamma_on',0.65,'severity_gamma_off',0.35, ...
    'severity_T_d_on',0.10,'severity_T_d_off',1.00, ...
    'healthy_pf_V',sys.pf.bus_voltage(:).', ...
    'healthy_pf_bus_ids',sys.pf.external_bus_ids(:).');
% The chronology contract requires the whole event sequence to sit inside the
% horizon, so this is the compressed arm used by test_ts_hybrid_fixed_bitident:
% it commits sg_trip, the load step and the fault window at dt=0.10, which is
% enough to exercise the SG-off supervisor, a GFM commit and three topologies.
% The arm fails closed at the post-line wall (TS-2026-08-13-03); that is fine
% here, because these assertions compare two runs of the SAME arm.
opt.t_end = 2.3;
opt.ibr_events = struct('enabled',true,'event_profile','chronology', ...
    'sg_trip',1,'load_step',1.5,'load_step_factor',0.20, ...
    'fault_on',2,'fault_clear',2.15,'fault_bus',9,'Zf',0.01+0.01i, ...
    'line_trip',2.2,'line_from_bus',6,'line_to_bus',13, ...
    'restore_time',2.25,'sg_on',2.25,'coordinated_handback',false, ...
    'automatic_gfm_switching',true, ...
    'delays_overrides',struct('timeout_s',20,'dwell_s',0.5));
end

function test_overlay_does_not_change_the_trajectory_or_the_decisions(testCase)
% G-AGSI-BITIDENT. The overlay is post-processing over the recorded samples, so
% every published array and every decision must be bit-for-bit unchanged.
[scenario,opt] = short_arm();
rOff = stability.run_hybrid_case(scenario,opt);
optOn = opt; optOn.agsi_reference = true;
rOn  = stability.run_hybrid_case(scenario,optOn);

arrays = {'t','x_traj','y_traj','u_history','iter_per_step', ...
    'residual_per_step','accepted_residual_per_step', ...
    'bus_voltage_magnitude','device_currents','device_P','device_Q', ...
    'sg_omega','sg_freq'};
compared = 0;
for k = 1:numel(arrays)
    f = arrays{k};
    if ~isfield(rOff,f) && ~isfield(rOn,f), continue; end
    testCase.verifyTrue(isfield(rOff,f) && isfield(rOn,f), ...
        sprintf('%s must exist in both runs',f));
    testCase.verifyEqual(rOn.(f),rOff.(f),'AbsTol',0, ...
        sprintf('%s must be byte-identical with the overlay enabled',f));
    compared = compared+1;
end
testCase.verifyGreaterThanOrEqual(compared,8, ...
    'the comparison must actually cover the published arrays');

decisions = {'converged','failure_id','failure_reason','reclose_status', ...
    'actual_reclose_time','handback_status','actual_mode_reselection_time', ...
    'reselection_status','committed_config_fingerprint', ...
    'pre_event_input_fingerprint'};
for k = 1:numel(decisions)
    f = decisions{k};
    if ~isfield(rOff,f) && ~isfield(rOn,f), continue; end
    testCase.verifyTrue(isequaln(rOn.(f),rOff.(f)), ...
        sprintf('decision field %s must not change',f));
end

testCase.verifyEqual(numel(rOn.event_log),numel(rOff.event_log));
for k = 1:numel(rOff.event_log)
    testCase.verifyEqual(char(rOn.event_log(k).type), ...
        char(rOff.event_log(k).type));
    testCase.verifyEqual(rOn.event_log(k).t,rOff.event_log(k).t,'AbsTol',0);
    testCase.verifyTrue(isequaln(rOn.event_log(k).applied, ...
        rOff.event_log(k).applied));
end
end

function test_schema_is_untouched_when_the_option_is_omitted(testCase)
% A run that does not ask for the overlay must not carry it, so no downstream
% consumer can start depending on a diagnostic field by accident.
[scenario,opt] = short_arm();
r = stability.run_hybrid_case(scenario,opt);
testCase.verifyFalse(isfield(r,'agsi_reference'));
optOn = opt; optOn.agsi_reference = true;
rOn = stability.run_hybrid_case(scenario,optOn);
testCase.verifyTrue(isfield(rOn,'agsi_reference'));
end

function test_published_terms_are_reference_only_and_not_aggregated(testCase)
% The overlay must publish the four reference sub-indices alongside the trigger
% pair, each with an in-band flag, and must NOT form an aggregate index: an
% aggregate is one step away from being a decision variable.
[scenario,opt] = short_arm();
opt.agsi_reference = true;
r = stability.run_hybrid_case(scenario,opt);
a = r.agsi_reference;
testCase.verifyTrue(startsWith(a.status,'OK'),a.status);
testCase.verifyEqual(a.classification,'ASSUMED_DIAGNOSTIC');
testCase.verifyEqual(a.aggregate_index,'NOT_FORMED_BY_DESIGN');
testCase.verifyEqual(a.rocof_method,'analytic_from_device_rhs_speed_rows');
terms = {'J_V','J_f','J_R','J_P','J_SCR','J_lock'};
for k = 1:numel(terms)
    testCase.verifyTrue(isfield(a.terms,terms{k}), ...
        sprintf('%s must be published',terms{k}));
    testCase.verifyTrue(isfield(a.in_band,terms{k}), ...
        sprintf('%s must carry an in-band flag',terms{k}));
    testCase.verifyEqual(size(a.terms.(terms{k}),1),numel(a.t));
    testCase.verifyEqual(size(a.in_band.(terms{k})),size(a.terms.(terms{k})));
    v = a.terms.(terms{k});
    ok = isfinite(v);
    testCase.verifyEqual(a.in_band.(terms{k})(ok),v(ok)<=1, ...
        sprintf('%s in_band must be exactly J<=1',terms{k}));
end
testCase.verifyEqual(numel(a.t),numel(r.t));
testCase.verifyEqual(numel(a.device_ids),4);
% No weight vector and no aggregate may appear anywhere in the payload.
f = fieldnames(a);
testCase.verifyFalse(any(contains(lower(f),'weight')));
testCase.verifyFalse(any(strcmpi(f,'agsi')));
testCase.verifyFalse(any(contains(lower(f),'severity')));
end

function test_gfm_has_no_pll_lock_term_and_bases_are_reported(testCase)
% Structural, not measured: a grid-forming branch has no PLL, so its lock error
% must be exactly zero rather than a small residual or a NaN. This also pins the
% GFM/GFL ownership the user called out explicitly.
[scenario,opt] = short_arm();
opt.agsi_reference = true;
r = stability.run_hybrid_case(scenario,opt);
a = r.agsi_reference;
gfm_mask = strcmpi(a.mode,'gfm');
testCase.verifyTrue(any(gfm_mask(:)), ...
    'the arm must actually place at least one device in GFM');
testCase.verifyEqual(a.terms.J_lock(gfm_mask),zeros(sum(gfm_mask(:)),1), ...
    'AbsTol',0,'a GFM branch has no PLL, so J_lock must be exactly 0');
gfl_mask = strcmpi(a.mode,'gfl') & a.online;
testCase.verifyTrue(any(gfl_mask(:)));
testCase.verifyTrue(all(isfinite(a.terms.J_lock(gfl_mask))), ...
    'a GFL branch must report a finite PLL lock error');
b = a.bases;
testCase.verifyEqual(b.dV_pu,0.10,'AbsTol',0);
testCase.verifyEqual(b.df_Hz,0.50,'AbsTol',0);
testCase.verifyEqual(b.rocof_Hz_s,1.0,'AbsTol',0);
testCase.verifyEqual(b.dP_pu,0.20,'AbsTol',0);
testCase.verifyEqual(b.scr_floor,3.0,'AbsTol',0);
testCase.verifyEqual(b.vq_pu,0.10,'AbsTol',0);
end

function test_invalid_reference_bases_fail_closed(testCase)
% The bases are diagnostic, but a nonsensical base would silently produce
% meaningless in-band verdicts, so they are validated when the overlay is on.
[scenario,opt] = short_arm();
opt.agsi_reference = true;
bad = {{'agsi_rocof_base_Hz_s',-1},{'agsi_dP_base_pu',-0.2}, ...
    {'agsi_vq_base_pu',-0.1},{'agsi_scr_floor',-3}};
for k = 1:numel(bad)
    o = opt; o.(bad{k}{1}) = bad{k}{2};
    r = stability.run_hybrid_case(scenario,o);
    testCase.verifyFalse(r.converged, ...
        sprintf('%s=%g must fail closed',bad{k}{1},bad{k}{2}));
    testCase.verifyEqual(failure_identifier(r), ...
        'ts_simulate_ibr_hybrid:invalidAgsiReferenceBases', ...
        sprintf('%s=%g must be rejected by the base validator', ...
        bad{k}{1},bad{k}{2}));
    testCase.verifyFalse(isfield(r,'agsi_reference'), ...
        'a rejected configuration must not publish an overlay');
end
end

function id = failure_identifier(r)
%FAILURE_IDENTIFIER  The published failure identifier wherever it landed.
id = '';
if isfield(r,'failure_id') && ~isempty(r.failure_id)
    id = char(r.failure_id);
    return;
end
if isfield(r,'metadata') && isstruct(r.metadata)
    m = r.metadata;
    if isfield(m,'failure_id') && ~isempty(m.failure_id)
        id = char(m.failure_id); return;
    end
    if isfield(m,'ts_meta') && isstruct(m.ts_meta) && ...
            isfield(m.ts_meta,'failure_id') && ~isempty(m.ts_meta.failure_id)
        id = char(m.ts_meta.failure_id); return;
    end
end
end
