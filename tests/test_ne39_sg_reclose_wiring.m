function tests = test_ne39_sg_reclose_wiring
%TEST_NE39_SG_RECLOSE_WIRING  Opt-in wiring of the existing 7-state SG31 plant
%into the real chronology path (scenario -> builder -> equilibrium).
%
%   This file adds NO new plant physics and relaxes NO gate.  It proves that the
%   already-frozen primitives
%     p   = stability.ne39_sg_reclose_plant_params(case_data)
%     dev = stability.sg_classical_reclose_device(case_data, id, bus_id, ...
%                                bus_position, bus_ids, V0, p)
%   are actually reachable from the production path, and only when the caller
%   opts in with
%     scenario_opt.sg_reclose_plant = true
%   on the SG31 + 9-IBR composition:
%     * default (flag absent/false) still builds the legacy nx==2 classical SG
%       with inputs [Pm,Emag] and no augmented plant record -- unchanged;
%     * opt-in builds ONE nx==7 SG31 device with inputs [P_ref,Emag_ref] and the
%       frozen record survives the uniform provenance rewrite + struct vertcat
%       (schema_id / S_rated_MVA / equilibrium_control_layout are readable on the
%       STACKED device array), with source H/D/X'd passed through unchanged and
%       the declared 1% no-load loss;
%     * the 5-SG composition refuses the opt-in instead of silently building it.
%
%   ACCEPTANCE FIXTURE (replaces the former bare-TAMU fixture).  The former
%   fixture used cases.case_ne39_1sg_9ibr() with no study capability, left all
%   nine IBRs in their default GFL initial mode, and accepted
%   eq.converged==false whenever failure_id was
%   'mixed_equilibrium_solve:deviceLimit'.  That is not an acceptance test: a
%   non-converged equilibrium was being reported as a pass.  This file now uses
%   the SAME designed all-9-GFM physical witness the chronology study uses:
%     opt        = ne39_endpoint_design_options();
%     c          = cases.ne39_chronology_design(cases.case_ne39_1sg_9ibr(), opt);
%     initial_modes = all nine IBR resource ids -> 'gfm'
%     scenario_opt  = struct('sg_reclose_plant',true,'initial_modes',initial_modes)
%   and then requires the FULL coupled equilibrium to succeed:
%     equilibrium converged == true (no physical failure tolerated),
%     residual_norm < 1e-8, physical_kcl_norm < 1e-8, rcond > 1e-10,
%     every one of the seven SG31 states stationary under the production RHS
%     (norm(f,inf) < 1e-8 at the solved x,y,u), and the plant's own PLL states
%     aligned by exact stationary semantics (theta_hat == angle(V_bus),
%     nu_hat == 0).
%
%   Also asserted here, in the same fixture: the reclose reference layout is the
%   [P_ref,Emag_ref] pair and is never relabelled as an actual shaft quantity
%   (Pm_solved_pu stays NaN while the actual shaft state is P_ref + L0), and the
%   prospective close metrics take the declared PROJECT_DERIVED stator rating.
%
%   A separate, deliberately small test exercises the SG-off all-GFM path --
%   the only production path that reaches
%   stability.mixed_ibr_reduced_initialize -- and requires the reduced
%   initializer to converge AND to leave the seven-state SG's terminal-phase
%   estimator at the solved voltage (theta_hat == angle(V_bus), nu_hat == 0).
%
%   No trajectory, no reclose event, and no synchronism-threshold change is
%   asserted here: the guard thresholds are untouched, no 160 s chronology is
%   replayed, and the external EMF6 sync controller stays OFF for sg_classical
%   (its early return is not modified).  Nothing in this file is a production or
%   mission certificate.
tests = functiontests(localfunctions);
end

% =========================================================================
% Fixtures (built once; the equilibrium solves are the expensive part)
% =========================================================================
function setupOnce(tc)
p = path;
tc.addTeardown(@() path(p));
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();

% The SAME designed witness the chronology study uses, so the acceptance
% equilibrium is a designed physical operating point and not a bare TAMU case.
[design_opt, analysis] = ne39_endpoint_design_options();
c = cases.ne39_chronology_design(cases.case_ne39_1sg_9ibr(), design_opt);

% Opt-in scenario: SG31 becomes the 7-state reclose plant.
s_on = cases.scenario_ne39_tamu_mixed(c, struct('sg_reclose_plant', true));
% All nine IBRs explicitly in GFM.  The override ids are taken from the
% resource table itself (the format stability.resource_table resolves), never
% hard-coded, so the witness cannot silently stop covering all nine.
ibr_ids = {s_on.resources(strcmp({s_on.resources.resource_type}, 'ibr')).resource_id};
initial_modes = struct('device_id', ibr_ids, 'mode', repmat({'gfm'}, size(ibr_ids)));
opt = struct('sg_reclose_plant', true, 'initial_modes', initial_modes);
s_gfm = cases.scenario_ne39_tamu_mixed(c, opt);

% Flag absent: the legacy path, built from the SAME designed case.
s_off = cases.scenario_ne39_tamu_mixed(c);

[dev_on, meta_on] = stability.build_mixed_resource_devices( ...
    c, s_on.resources, s_on.scenario_opt);
[dev_gfm, meta_gfm] = stability.build_mixed_resource_devices( ...
    c, s_gfm.resources, s_gfm.scenario_opt);
[dev_off, ~] = stability.build_mixed_resource_devices( ...
    c, s_off.resources, s_off.scenario_opt);

% Acceptance: FULL coupled equilibrium, SG31 online as the SG slack and every
% IBR a GFM.  No failure is tolerated below.
eq = stability.mixed_equilibrium_solve(c, struct('devices', dev_gfm), ...
    struct('verbose', false, 'tolerance', 1e-8));

% Plant record / reference-pair fixture (legacy P/Q-ref composition with the
% nine IBRs left in their default GFL mode).
eq_pq = stability.mixed_equilibrium_solve(c, struct('devices', dev_on), ...
    struct('verbose', false, 'tolerance', 1e-8));

% SG-off all-GFM reduced-initializer regression fixture.  This is the only
% production configuration that calls stability.mixed_ibr_reduced_initialize.
off_resources = s_gfm.resources;
sg_row = find(strcmp({off_resources.resource_type}, 'sg'), 1);
off_resources(sg_row).initial_online = false;
off_resources(sg_row).initial_mode = 'breaker_open';
[dev_sgoff, ~] = stability.build_mixed_resource_devices(c, off_resources, ...
    struct('dispatch', c.dispatch_contract.post_trip.post_trip_Pg_MW));
% The builder already consumed the post-trip dispatch: assert that instead of
% overriding device inputs (an override would mask a builder regression).
assert_ibr_p_ref_dispatch(tc, c, dev_sgoff, ...
    c.dispatch_contract.post_trip.post_trip_Pg_MW);
dae_sgoff = stability.composite_dae(c, dev_sgoff, struct());
ec_sgoff = struct('hybrid_state', stability.ts_hybrid_state_init(dev_sgoff));
% Reference = the first IBR of the composition, resolved from the RESOURCE table
% (the device ABI exposes device_type, not resource_type, so the table index is
% the reliable mapping).
sgoff_ref = find(strcmp({off_resources.resource_type}, 'ibr'), 1);
init_sgoff = stability.mixed_ibr_reduced_initialize(dae_sgoff, ec_sgoff, ...
    sgoff_ref, struct('tolerance', 1e-10, 'max_iter', 300, 'verbose', false));

% ONLINE seven-state SG + GFM reference fixture.  mixed_ibr_reduced_initialize
% only seeds devices in its ONLINE classical SG set, so the only configuration
% that reaches the new terminal-phase seed is an island whose balancing
% reference is an online GFM while SG31 is still online.  This is the pre-trip
% SG-on/GFM-reference initializer used by the project's all-GFM probes.
assert_ibr_p_ref_dispatch(tc, c, dev_gfm, ...
    c.dispatch_contract.pre_fault);
dae_sgonline = stability.composite_dae(c, dev_gfm, struct());
ec_sgonline = struct('hybrid_state', stability.ts_hybrid_state_init(dev_gfm));
sgonline_ref = find(strcmp({dev_gfm.device_type}, 'ibr_eecon49_dual'), 1);
init_sgonline = stability.mixed_ibr_reduced_initialize(dae_sgonline, ...
    ec_sgonline, sgonline_ref, ...
    struct('tolerance', 1e-10, 'max_iter', 300, 'verbose', false));

tc.TestData.c = c;
tc.TestData.design_opt = design_opt;
tc.TestData.analysis = analysis;
tc.TestData.initial_modes = initial_modes;
tc.TestData.opt = opt;
tc.TestData.s_on = s_on;
tc.TestData.s_gfm = s_gfm;
tc.TestData.dev_on = dev_on;
tc.TestData.meta_on = meta_on;
tc.TestData.dev_gfm = dev_gfm;
tc.TestData.meta_gfm = meta_gfm;
tc.TestData.s_off = s_off;
tc.TestData.dev_off = dev_off;
tc.TestData.eq = eq;
tc.TestData.eq_pq = eq_pq;
tc.TestData.dae_sgoff = dae_sgoff;
tc.TestData.ec_sgoff = ec_sgoff;
tc.TestData.init_sgoff = init_sgoff;
tc.TestData.dae_sgonline = dae_sgonline;
tc.TestData.ec_sgonline = ec_sgonline;
tc.TestData.init_sgonline = init_sgonline;
tc.TestData.sgonline_ref = sgonline_ref;
end

% =========================================================================
% Default path: flag absent keeps the legacy two-state classical SG
% =========================================================================
function test_default_opt_absent_keeps_the_legacy_two_state_sg(tc)
tc.verifyEqual(char(tc.TestData.s_off.resources(1).model_id), 'sg_classical');
sg = sg_device(tc.TestData.dev_off);
tc.verifyEqual(sg.nx, 2);
tc.verifyEqual(sg.nu, 2);
tc.verifyTrue(isequal(sg.input_names, {'Pm','Emag'}));
tc.verifyTrue(isequal(sg.state_names, {'delta','omega'}));
tc.verifyEqual(char(sg.device_type), 'sg_classical');
tc.verifyEqual(sg.provenance.model, 'sg_classical');
% no augmented record leaks into the legacy device
tc.verifyEqual(augmented_schema_id(sg), '');
end

% =========================================================================
% Opt-in: SG31 becomes the seven-state reclose plant
% =========================================================================
function test_opt_in_selects_the_seven_state_reclose_plant(tc)
resources = tc.TestData.s_on.resources;
tc.verifyEqual(char(resources(1).resource_id), 'SG31');
tc.verifyEqual(char(resources(1).model_id), 'sg_classical_reclose');
% 5-SG/4-SG/... resources are untouched: the remaining nine stay IBR.
tc.verifyEqual(sum(strcmp({resources.resource_type}, 'sg')), 1);
tc.verifyEqual(sum(strcmp({resources.model_id}, 'eecon49_dual')), 9);

d = tc.TestData.dev_on;
tc.verifyEqual(numel(d), 10);
sg = sg_device(d);
tc.verifyEqual(sg.nx, 7, 'nx must be the 7-state plant, not 2');
tc.verifyEqual(sg.nu, 2);
tc.verifyTrue(isequal(sg.input_names, {'P_ref','Emag_ref'}), ...
    'inputs are electrical references, not the actual shaft state');
tc.verifyTrue(isequal(sg.state_names, ...
    {'delta','omega','Psv','Pm','Emag','theta_hat','nu_hat'}));
% device_type stays 'sg_classical', which is exactly what keeps the external
% EMF6 synchronizer DISABLED (ts initialize_sync_controller early return).
tc.verifyEqual(char(sg.device_type), 'sg_classical');
tc.verifyEqual(sg.bus_id, 31);
tc.verifyTrue(all(sg.dynamic_state_indices_for_context(struct()) == (1:7)));
end

function test_frozen_plant_record_survives_the_uniform_provenance_rewrite(tc)
sg = sg_device(tc.TestData.dev_on);
p = sg.provenance.params;
tc.verifyTrue(isstruct(p), 'provenance.params must survive the copier rewrite');
tc.verifyEqual(char(p.schema_id), 'ne39_sg31_classical_reclose_v1');
tc.verifyEqual(char(p.classification), 'PROJECT_DERIVED');
tc.verifyTrue(isfield(p, 'S_rated_MVA') && isscalar(p.S_rated_MVA) && ...
    isfinite(p.S_rated_MVA) && p.S_rated_MVA > 0);
tc.verifyEqual(char(p.equilibrium_control_layout), ...
    'classical_reclose_pref_emag_ref');
% H/D/X'd are the unchanged source reduction, not re-derived here.
m = tc.TestData.c.machines.units(1);
tc.verifyEqual(p.H_system_s, m.H, 'AbsTol', 0);
tc.verifyEqual(p.D_system_pu, m.D, 'AbsTol', 0);
tc.verifyEqual(p.Xdp_system_pu, m.Xdp, 'AbsTol', 0);
% The declared no-load shaft loss is exactly 1% of the healthy SG31 shaft power
% and is a separate PROJECT_DERIVED term, never folded into source D.
tc.verifyEqual(p.no_load_loss_fraction, 0.01, 'AbsTol', 0);
tc.verifyEqual(p.no_load_loss_pu, 0.01*p.P_ref0_pu, 'AbsTol', 1e-12);
tc.verifyGreaterThan(p.no_load_loss_pu, 0);
% the identification markers sg_prospective_close_metrics accepts
tc.verifyEqual(char(sg.provenance.model), 'sg_classical_reclose_project_derived');
tc.verifyTrue(isequal(sg.input_names, {'P_ref','Emag_ref'}));
tc.verifyEqual(tc.TestData.meta_on.model_ids{1}, 'sg_classical_reclose');
end

% =========================================================================
% Acceptance witness: designed physical case, SG31 online, all nine IBRs GFM
% =========================================================================
function test_witness_sets_every_ibr_to_gfm_and_keeps_one_sg31(tc)
r = tc.TestData.s_gfm.resources;
tc.verifyEqual(numel(r), 10);
sg = r(strcmp({r.resource_type}, 'sg'));
tc.verifyEqual(numel(sg), 1);
tc.verifyEqual(char(sg.resource_id), 'SG31');
tc.verifyEqual(char(sg.model_id), 'sg_classical_reclose');
ibr = r(strcmp({r.resource_type}, 'ibr'));
tc.verifyEqual(numel(ibr), 9);
for k = 1:numel(ibr)
    tc.verifyEqual(char(ibr(k).initial_mode), 'gfm', ...
        sprintf('%s must be committed GFM for the physical witness', ...
        char(ibr(k).resource_id)));
end
% The mode request is the override format stability.resource_table accepts and
% it names the case's own nine IBR resource ids.
tc.verifyEqual(numel(tc.TestData.initial_modes), 9);
for k = 1:numel(tc.TestData.initial_modes)
    tc.verifyEqual(char(tc.TestData.initial_modes(k).mode), 'gfm');
end
tc.verifyEqual(ibr_ids_of(tc.TestData.dev_gfm), ibr_ids_of(tc.TestData.dev_on));
% The equilibrium commits every IBR to gfm; that mode map is the authoritative
% check.  (E_ref existence is NOT evidence of GFM: the shared dual-mode EECON49
% ABI declares E_ref in both modes.)
hs = tc.TestData.eq.equilibrium_context.hybrid_state;
for k = 1:numel(ibr)
    key = matlab.lang.makeValidName(char(ibr(k).resource_id), ...
        'ReplacementStyle', 'underscore');
    tc.verifyTrue(isfield(hs.device_modes, key));
    tc.verifyEqual(lower(char(hs.device_modes.(key))), 'gfm');
    tc.verifyTrue(logical(hs.device_online.(key)));
end
end

function test_mixed_equilibrium_converges_for_the_all_gfm_witness(tc)
eq = tc.TestData.eq;
% ACCEPTANCE: the full coupled equilibrium must converge.  A device limit, an
% ill-conditioned Jacobian, an initializer refusal or a non-converged Newton is
% a FAILURE here -- never an accepted outcome.
tc.verifyTrue(eq.converged, eq.failure_reason);
tc.verifyTrue(isfinite(eq.residual_norm) && eq.residual_norm < 1e-8, ...
    eq.failure_reason);
tc.verifyTrue(isfinite(eq.physical_kcl_norm) && eq.physical_kcl_norm < 1e-8);
tc.verifyGreaterThan(eq.rcond, 1e-10);
tc.verifyTrue(all(isfinite(eq.x0)) && all(isfinite(eq.y0)) && ...
    all(isfinite(eq.u_eq)));
% The gate that used to be tolerated is now explicit: every device must be
% inside its declared equilibrium limits.
if isfield(eq, 'limit_checks') && isstruct(eq.limit_checks) && ...
        isfield(eq.limit_checks, 'devices') && isstruct(eq.limit_checks.devices)
    names = fieldnames(eq.limit_checks.devices);
    for k = 1:numel(names)
        tc.verifyTrue(logical(eq.limit_checks.devices.(names{k}).within_limits), ...
            sprintf('device %s left its equilibrium limits', names{k}));
    end
end
end

% =========================================================================
% The seven-state SG31 plant at the acceptance equilibrium
% =========================================================================
function test_all_seven_sg_states_are_stationary_at_the_witness(tc)
eq = tc.TestData.eq;
tc.verifyTrue(isfield(eq, 'equilibrium_context') && isstruct(eq.equilibrium_context), ...
    'the solved equilibrium must expose its equilibrium_context for the RHS audit');
[sg, x_sg, u_sg] = sg_solved_block(eq, tc.TestData.dev_gfm);
% Full seven-state production RHS with no state frozen and no coordinate
% dropped: every declared state participates.
dx = sg.f(0, x_sg, eq.y0, u_sg, eq.equilibrium_context);
tc.verifyEqual(numel(x_sg), 7);
tc.verifyTrue(all(isfinite(dx)));
tc.verifyLessThan(norm(dx, inf), 1e-8);

% dl/dt = w0*(omega-1), so the solved absolute speed is exactly nominal.
tc.verifyEqual(x_sg(2), 1.0, 'AbsTol', 1e-10);
tc.verifyEqual(dx(1), 0, 'AbsTol', 1e-8);
% The valve and chest states sit at their stationary shaft power, and the actual
% shaft power is the solved ELECTRICAL reference plus the declared no-load loss.
p = sg.provenance.params;
tc.verifyEqual(x_sg(3), x_sg(4), 'AbsTol', 1e-7);
tc.verifyEqual(x_sg(4), u_sg(1) + p.no_load_loss_pu, 'AbsTol', 1e-7);
tc.verifyGreaterThan(x_sg(4), 0);
tc.verifyEqual(dx(3), 0, 'AbsTol', 1e-8);
tc.verifyEqual(dx(4), 0, 'AbsTol', 1e-8);
% The reduced field magnitude tracks its reference on line; the PLL pair is at
% the exact stationary value for the solved terminal voltage.
tc.verifyEqual(x_sg(5), u_sg(2), 'AbsTol', 1e-7);
tc.verifyEqual(dx(5), 0, 'AbsTol', 1e-8);
V_terminal = complex(eq.y0(2*sg.bus_position-1), eq.y0(2*sg.bus_position));
tc.verifyEqual(x_sg(6), angle(V_terminal), 'AbsTol', 1e-9);
tc.verifyEqual(x_sg(7), 0, 'AbsTol', 1e-9);
tc.verifyEqual(dx(6), 0, 'AbsTol', 1e-8);
tc.verifyEqual(dx(7), 0, 'AbsTol', 1e-8);
tc.verifyLessThanOrEqual(abs(deviation_wrap(x_sg(6) - angle(V_terminal))), 1e-9);
% the reclose guard reads classical speed as (omega_abs - 1)
rec = sg.reconstruct(0, x_sg, eq.y0, u_sg, eq.equilibrium_context);
tc.verifyEqual(stability.sg_speed_deviation(sg, rec), x_sg(2) - 1, 'AbsTol', 0);
end

function test_reference_layout_is_the_reclose_pair_not_shaft_pm(tc)
eq = tc.TestData.eq;
r = eq.reference;
tc.verifyEqual(char(r.device_id), 'SG31');
tc.verifyEqual(char(r.control_layout), 'classical_reclose_pref_emag_ref');
tc.verifyTrue(isequal(r.slack_input_names, {'P_ref','Emag_ref'}));
tc.verifyTrue(isfinite(r.P_ref_solved_pu) && r.P_ref_solved_pu > 0);
tc.verifyTrue(isfinite(r.Emag_ref_solved_pu) && r.Emag_ref_solved_pu > 0);
tc.verifyTrue(isfinite(r.P_ref_scheduled_pu));
% the solved reference is NOT relabelled as an actual shaft quantity
tc.verifyTrue(isnan(r.Pm_solved_pu));
tc.verifyTrue(isnan(r.Pm_scheduled_pu));
tc.verifyTrue(isnan(r.Tm_solved_pu));
tc.verifyTrue(isnan(r.Efd_solved_pu));
tc.verifyTrue(isnan(r.Emag_solved_pu));
% the solved electrical reference is pinned to the device's solved input slot
[~, ~, u_sg] = sg_solved_block(eq, tc.TestData.dev_gfm);
tc.verifyEqual(r.P_ref_solved_pu, u_sg(1), 'AbsTol', 0);
tc.verifyEqual(r.Emag_ref_solved_pu, u_sg(2), 'AbsTol', 0);
end

function test_prospective_close_metrics_use_the_declared_stator_rating(tc)
eq = tc.TestData.eq;
[sg, x_sg, u_sg] = sg_solved_block(eq, tc.TestData.dev_gfm);
p = sg.provenance.params;
m = stability.sg_prospective_close_metrics(0, x_sg, eq.y0, u_sg, ...
    eq.equilibrium_context, sg, tc.TestData.c);
tc.verifyEqual(char(m.rating_status), 'DECLARED_PROJECT_DERIVED');
tc.verifyEqual(char(m.rating_classification), 'PROJECT_DERIVED');
tc.verifyEqual(m.rating_MVA, p.S_rated_MVA, 'AbsTol', 0);
tc.verifyEqual(m.mechanical_power_pu, x_sg(4), 'AbsTol', 0);
tc.verifyEqual(m.mechanical_power_minus_electrical_pu, x_sg(4) - m.Pe_pu, ...
    'AbsTol', 1e-10);
tc.verifyEqual(char(m.Tm_pu_semantics), ...
    'PER_UNIT_COMMAND_CHANNEL_P_REF_NOT_ACTUAL_SHAFT_POWER');
tc.verifyNotEqual(char(m.rating_status), 'NOT_DECLARED');
% ACCEPTANCE gate, not just provenance: the prospective close audit must PASS
% on the witness (finite declared rating, finite state, within the current and
% apparent-power circles), and every sub-gate it aggregates must be true.
tc.verifyTrue(logical(m.passes), sprintf( ...
    'prospective close audit failed: rating_status=%s current=%.12g apparent=%.12g finite=%d', ...
    char(m.rating_status), abs(m.I), abs(m.S_abs_pu), logical(m.finite)));
tc.verifyTrue(logical(m.finite));
tc.verifyTrue(logical(m.current_pass));
tc.verifyTrue(logical(m.apparent_power_pass));
end

% =========================================================================
% The same plant on the legacy P/Q-reference composition (IBRs stay GFL)
% =========================================================================
function test_pq_reference_composition_still_solves_with_the_seven_state_sg(tc)
eq = tc.TestData.eq_pq;
tc.verifyTrue(eq.converged, eq.failure_reason);
tc.verifyTrue(isfinite(eq.residual_norm) && eq.residual_norm < 1e-8, ...
    eq.failure_reason);
tc.verifyTrue(isfinite(eq.physical_kcl_norm) && eq.physical_kcl_norm < 1e-8);
tc.verifyGreaterThan(eq.rcond, 1e-10);
tc.verifyEqual(char(eq.reference.control_layout), ...
    'classical_reclose_pref_emag_ref');
[sg, x_sg, u_sg] = sg_solved_block(eq, tc.TestData.dev_on);
dx = sg.f(0, x_sg, eq.y0, u_sg, eq.equilibrium_context);
tc.verifyLessThan(norm(dx, inf), 1e-8);
tc.verifyEqual(x_sg(4), u_sg(1) + sg.provenance.params.no_load_loss_pu, ...
    'AbsTol', 1e-7);
end

% =========================================================================
% SG-off all-GFM path: the reduced initializer must seed the seven-state plant
% =========================================================================
function test_sg_off_reduced_initializer_preserves_the_seven_state_anchor(tc)
% STATIONARY-NETWORK INITIALIZATION check, not an offline steady-state claim.
% The offline SG is NOT part of the reduced solve and the terminal-phase seed
% below does not apply to it (the seed loops the ONLINE classical SG set only):
% mixed_ibr_reduced_initialize starts from dae.x0 and leaves every offline state
% at its factory anchor, so this test asserts the anchor is PRESERVED -- not that
% the offline device was re-seeded to the solved voltage.  mixed_equilibrium_solve
% separately re-anchors all offline states; the offline states are TS states and
% must evolve, so the physical offline rotor RHS is deliberately NON-zero (the
% anchor keeps the positive shaft-power seed Pm = P0 + L0) and is asserted so.
init = tc.TestData.init_sgoff;
tc.verifyTrue(init.applicable);
tc.verifyTrue(init.converged, init.failure_reason);
% The offline SG31 stays a seven-state device and is ANCHOR-PRESERVED by that
% initializer (it is neither reduced to two states nor re-seeded).
dae = tc.TestData.dae_sgoff;
idx = find(strcmp({dae.devices.device_id}, 'SG31'), 1);
tc.verifyEqual(dae.devices(idx).nx, 7, 'SG31 must stay seven-state offline');
xr = dae.device_offsets(idx) + (1:7);
ur = dae.u_offsets(idx) + (1:2);
x_sg = init.x0(xr);
tc.verifyTrue(all(isfinite(x_sg)));
% Honest expectation: the whole seven-state block is the factory anchor,
% bit-for-bit, because the offline device is outside the reduced solve.
anchor = dae.devices(idx).x0;
tc.verifyTrue(all(isfinite(anchor)));
tc.verifyEqual(x_sg, anchor(:), 'AbsTol', 0);
tc.verifyEqual(x_sg(2), 1.0, 'AbsTol', 1e-10);
% All seven states stay structural dynamic states offline: the plant declares no
% frozen state and the dynamic index set covers 1:7 in this context, so nothing
% is silently pinned out of the TS partition.
tc.verifyTrue(isempty(dae.devices(idx).frozen_state_indices));
tc.verifyTrue(all(dae.devices(idx).dynamic_state_indices_for_context( ...
    tc.TestData.ec_sgoff) == (1:7)));
% The offline plant, under the context that says it is offline, does not inject
% and is NOT at a zero-RHS stationary point with its positive shaft-power seed.
off_ctx = struct('hybrid_state', ...
    struct('device_online', struct('SG31', false), ...
           'device_modes', struct('SG31', 'breaker_open')));
tc.verifyEqual(abs(dae.devices(idx).current_injection(0, x_sg, init.y0, ...
    init.u_eq(ur), off_ctx)), 0, 'AbsTol', 1e-12);
rec_off = dae.devices(idx).reconstruct(0, x_sg, init.y0, init.u_eq(ur), off_ctx);
tc.verifyFalse(logical(rec_off.online));
tc.verifyEqual(rec_off.P, 0, 'AbsTol', 0);
dx_off = dae.devices(idx).f(0, x_sg, init.y0, init.u_eq(ur), off_ctx);
tc.verifyGreaterThan(x_sg(4), 0);
tc.verifyGreaterThan(abs(dx_off(2)), 1e-9, ...
    'a positive offline shaft-power seed must not be stationary');
% The legacy two-state machine declares neither estimator state, so the
% alignment block cannot touch it.
tc.verifyFalse(any(strcmpi(string(sg_device(tc.TestData.dev_off).state_names), ...
    'theta_hat')));
end

% =========================================================================
% ONLINE seven-state SG + GFM reference: the only fixture that reaches the new
% terminal-phase seed in the reduced initializer
% =========================================================================
function test_online_sg_reduced_initializer_seeds_the_terminal_phase(tc)
% The seed loops the ONLINE classical SG set, so it needs an island whose
% balancing reference is an online GFM while SG31 is still online (the
% pre-trip SG-on/GFM-reference initializer).  This fixture is the reachable
% mixed online SG + GFM reference configuration and is what actually covers the
% new code; the SG-off fixture above cannot cover it by construction.
init = tc.TestData.init_sgonline;
tc.verifyTrue(init.applicable);
tc.verifyTrue(init.converged, init.failure_reason);
dae = tc.TestData.dae_sgonline;
idx = find(strcmp({dae.devices.device_id}, 'SG31'), 1);
tc.verifyEqual(dae.devices(idx).nx, 7);
% The device under test is the online one, so the seed block is reachable here.
hs = tc.TestData.ec_sgonline.hybrid_state;
tc.verifyTrue(logical(hs.device_online.SG31));
tc.verifyEqual(lower(char(hs.device_modes.SG31)), 'synchronous');
% The reference of the reduced solve is the online GFM, not the SG.
tc.verifyEqual(init.reference_device_index, tc.TestData.sgonline_ref);
tc.verifyEqual(char(dae.devices(tc.TestData.sgonline_ref).device_type), ...
    'ibr_eecon49_dual');
ref_key = matlab.lang.makeValidName( ...
    char(dae.devices(tc.TestData.sgonline_ref).device_id), ...
    'ReplacementStyle', 'underscore');
tc.verifyTrue(logical(hs.device_online.(ref_key)));
tc.verifyEqual(lower(char(hs.device_modes.(ref_key))), 'gfm');
% The new seed guarantees theta_hat = angle(V_bus) and nu_hat = 0 at the SOLVED
% post-gauge voltage, independent of the PF warm-start angle.
xr = dae.device_offsets(idx) + (1:7);
ur = dae.u_offsets(idx) + (1:2);
x_sg = init.x0(xr);
anchor = dae.devices(idx).x0;
bp = dae.devices(idx).bus_position;
V_terminal = complex(init.y0(2*bp-1), init.y0(2*bp));
tc.verifyLessThanOrEqual(abs(deviation_wrap(x_sg(6) - angle(V_terminal))), 1e-12);
tc.verifyEqual(x_sg(7), 0, 'AbsTol', 1e-12);
% The solved post-gauge terminal angle is the one the plant must track.  The
% factory anchor is the pre-gauge PF value; it is expected to differ, but if the
% two coincide (gauge shift ~0) the alignment claim is the only falsifiable one,
% so it is asserted first.
if abs(deviation_wrap(angle(V_terminal) - anchor(6))) > 1e-12
    tc.verifyGreaterThan(abs(deviation_wrap(x_sg(6) - anchor(6))), 1e-12, ...
        'the solved post-gauge angle must track the solve, not the factory anchor');
end
% Where the initializer's own seed semantics guarantee stationarity, that is
% asserted: the two terminal-phase estimator equations are zero at the seed.  The
% rest of the SG RHS is NOT guaranteed here (the initializer retains the factory
% Psv/Pm/Emag while the solved Q/voltage may differ), so it is only required to
% be finite and in-domain; the full seven-state zero-RHS claim is made by the
% coupled equilibrium fixtures above, not by this initializer fixture.
online_ctx = struct('hybrid_state', ...
    struct('device_online', struct('SG31', true), ...
           'device_modes', struct('SG31', 'synchronous')));
dx = dae.devices(idx).f(0, x_sg, init.y0, init.u_eq(ur), online_ctx);
tc.verifyTrue(all(isfinite(dx)));
tc.verifyEqual(dx(6), 0, 'AbsTol', 1e-9, ...
    'the seeded terminal-phase estimator must be stationary');
tc.verifyEqual(dx(7), 0, 'AbsTol', 1e-9, ...
    'the seeded frequency-estimator integrator must be stationary');
end

% =========================================================================
% Fail closed on any other composition
% =========================================================================
function test_opt_in_is_rejected_for_the_five_sg_composition(tc)
expect_error_prefix(tc, @() cases.scenario_ne39_tamu_mixed( ...
    cases.case_ne39_5sg_5ibr(), tc.TestData.opt), ...
    'cases:ne39SgReclosePlant:unsupportedComposition');
end

function test_opt_in_flag_must_be_boolean(tc)
expect_error_prefix(tc, @() cases.scenario_ne39_tamu_mixed( ...
    tc.TestData.c, struct('sg_reclose_plant', 2)), ...
    'cases:ne39SgReclosePlant:flag');
end

% =========================================================================
% Helpers
% =========================================================================
function sg = sg_device(d)
idx = find(strcmp({d.device_id}, 'SG31'), 1);
if isempty(idx)
    error('test_ne39_sg_reclose_wiring:missingSG31', 'SG31 device not found.');
end
sg = d(idx);
end

function ids = ibr_ids_of(d)
ids = sort({d(~strcmp({d.device_type}, 'sg_classical')).device_id});
end

function assert_ibr_p_ref_dispatch(tc, c, d, dispatch)
%ASSERT_IBR_P_REF_DISPATCH  The builder must have consumed the dispatch itself.
%   stability.build_mixed_resource_devices is called with the SAME dispatch
%   struct that is checked here, so each IBR's P_ref input must already equal
%   dispatch.MW / baseMVA on assembly.  This asserts that fact and never writes
%   into a device input: overriding u0 here would hide a builder regression
%   instead of revealing it.  Only IBR P_ref slots are checked; the SG's
%   equilibrium references are left alone.
base = c.mpc.baseMVA;
n_checked = 0;
for k = 1:numel(d)
    if strcmp(char(d(k).device_type), 'sg_classical')
        % The SG (opt-in reclose plant) legitimately declares [P_ref,Emag_ref];
        % it is outside the IBR dispatch contract asserted here.
        continue;
    end
    rid = char(d(k).device_id);
    tc.verifyTrue(isfield(dispatch, rid), ...
        sprintf('dispatch is missing %s', rid));
    slot = find(strcmpi(string(d(k).input_names), 'P_ref'), 1);
    tc.verifyEqual(numel(slot), 1, ...
        sprintf('%s must declare one P_ref input', rid));
    tc.verifyEqual(d(k).u0(slot), dispatch.(rid)/base, 'AbsTol', 0, ...
        sprintf('%s P_ref must already be the dispatched schedule', rid));
    n_checked = n_checked + 1;
end
tc.verifyEqual(n_checked, 9, 'the designed composition has nine IBRs');
end

function [sg, x_sg, u_sg] = sg_solved_block(eq, d)
idx = find(strcmp({d.device_id}, 'SG31'), 1);
if isempty(idx)
    error('test_ne39_sg_reclose_wiring:missingSG31', 'SG31 device not found.');
end
xo = sum([d(1:idx-1).nx]);
uo = sum([d(1:idx-1).nu]);
sg = d(idx);
x_sg = eq.x0(xo + (1:sg.nx));
u_sg = eq.u_eq(uo + (1:sg.nu));
end

function id = augmented_schema_id(dev)
id = '';
if ~isfield(dev, 'provenance') || ~isstruct(dev.provenance) || ...
        ~isfield(dev.provenance, 'params') || ~isstruct(dev.provenance.params)
    return;
end
if isfield(dev.provenance.params, 'schema_id')
    id = char(dev.provenance.params.schema_id);
end
end

function e = deviation_wrap(a)
% Same wrapped phase error the device uses: mod(a+pi,2*pi)-pi.
e = mod(a + pi, 2*pi) - pi;
end

function expect_error_prefix(tc, fn, prefix)
threw = false;
try
    fn();
catch me
    threw = true;
    tc.verifyTrue(startsWith(me.identifier, prefix), ...
        sprintf('expected error prefix %s, got %s (%s)', prefix, me.identifier, me.message));
end
tc.verifyTrue(threw, sprintf('expected an error with prefix %s', prefix));
end
