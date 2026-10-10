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
%       with inputs [Pm,Emag] -- byte-for-behaviour unchanged;
%     * opt-in builds ONE nx==7 SG31 device with inputs [P_ref,Emag_ref] and the
%       frozen record survives the uniform provenance rewrite + struct vertcat
%       (schema_id / S_rated_MVA / equilibrium_control_layout are readable on the
%       STACKED device array);
%     * mixed_equilibrium_solve solves the coupled system with the 7-state device
%       as the SG slack: finite residual/KCL, the reference is reported as the
%       [P_ref,Emag_ref] layout (never relabelled as actual shaft Pm), the solved
%       SG RHS is zero, actual shaft power is P_ref+L0 (>0), and the prospective
%       close metrics take the declared PROJECT_DERIVED stator rating;
%     * the 5-SG composition refuses the opt-in instead of silently building it.
%
%   No trajectory, no reclose event, and no synchronism-threshold change is
%   asserted here: the guard thresholds are untouched and the external EMF6 sync
%   controller stays OFF for sg_classical (its early return is not modified).
tests = functiontests(localfunctions);
end

% =========================================================================
% Fixtures (built once; the equilibrium solve is the expensive part)
% =========================================================================
function setupOnce(tc)
p = path;
tc.addTeardown(@() path(p));
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();

c = cases.case_ne39_1sg_9ibr();
opt = struct('sg_reclose_plant', true);

s_on = cases.scenario_ne39_tamu_mixed(c, opt);
[dev_on, meta_on] = stability.build_mixed_resource_devices( ...
    c, s_on.resources, s_on.scenario_opt);

s_off = cases.scenario_ne39_tamu_mixed(c);
[dev_off, ~] = stability.build_mixed_resource_devices( ...
    c, s_off.resources, s_off.scenario_opt);

eq = stability.mixed_equilibrium_solve(c, struct('devices', dev_on), ...
    struct('verbose', false));

tc.TestData.c = c;
tc.TestData.opt = opt;
tc.TestData.s_on = s_on;
tc.TestData.dev_on = dev_on;
tc.TestData.meta_on = meta_on;
tc.TestData.s_off = s_off;
tc.TestData.dev_off = dev_off;
tc.TestData.eq = eq;
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
% the identification markers sg_prospective_close_metrics accepts
tc.verifyEqual(char(sg.provenance.model), 'sg_classical_reclose_project_derived');
tc.verifyTrue(isequal(sg.input_names, {'P_ref','Emag_ref'}));
tc.verifyEqual(tc.TestData.meta_on.model_ids{1}, 'sg_classical_reclose');
end

% =========================================================================
% Coupled equilibrium with the augmented device as the SG slack
% =========================================================================
function test_mixed_equilibrium_solves_with_the_augmented_device(tc)
eq = tc.TestData.eq;
tc.verifyTrue(isfinite(eq.residual_norm) && eq.residual_norm < 1e-8, ...
    eq.failure_reason);
tc.verifyTrue(isfinite(eq.physical_kcl_norm) && eq.physical_kcl_norm < 1e-8);
tc.verifyGreaterThan(eq.rcond, 1e-10);
tc.verifyTrue(all(isfinite(eq.x0)) && all(isfinite(eq.y0)) && ...
    all(isfinite(eq.u_eq)));
% converged==false is allowed ONLY for the pre-existing uncertified Pmax gate;
% a numerical refusal (noConverge / illConditioned / initializerFailure) is not.
if ~eq.converged
    tc.verifyEqual(char(eq.failure_id), 'mixed_equilibrium_solve:deviceLimit', ...
        eq.failure_reason);
    tc.verifyTrue(contains(eq.failure_reason, 'operating limit'), ...
        eq.failure_reason);
end
end

function test_reference_layout_is_the_reclose_pair_not_shaft_pm(tc)
r = tc.TestData.eq.reference;
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
end

function test_solved_sg_state_has_zero_rhs_and_positive_actual_shaft_power(tc)
[eq, dev, x_sg, u_sg] = sg_solved_block(tc);
dx = dev.f(0, x_sg, eq.y0, u_sg, eq.equilibrium_context);
tc.verifyLessThan(norm(dx, inf), 1e-8);
tc.verifyEqual(x_sg(2), 1.0, 'AbsTol', 1e-10);      % omega_abs == 1
p = dev.provenance.params;
% actual shaft power is the solved ELECTRICAL reference plus the declared loss;
% the reference itself is never pushed into the mechanical states.
tc.verifyEqual(x_sg(4), u_sg(1) + p.no_load_loss_pu, 'AbsTol', 1e-7);
tc.verifyGreaterThan(x_sg(4), 0);
tc.verifyEqual(x_sg(3), x_sg(4), 'AbsTol', 1e-7);    % Psv == Pm
tc.verifyEqual(x_sg(5), u_sg(2), 'AbsTol', 1e-7);    % Emag == Emag_ref
tc.verifyEqual(x_sg(7), 0, 'AbsTol', 1e-7);          % nu_hat
tc.verifyTrue(isfinite(x_sg(1)));
% the reclose guard reads classical speed as (omega_abs - 1)
rec = dev.reconstruct(0, x_sg, eq.y0, u_sg, eq.equilibrium_context);
tc.verifyEqual(stability.sg_speed_deviation(dev, rec), x_sg(2) - 1, ...
    'AbsTol', 0);
end

function test_prospective_close_metrics_use_the_declared_stator_rating(tc)
[eq, dev, x_sg, u_sg] = sg_solved_block(tc);
p = dev.provenance.params;
m = stability.sg_prospective_close_metrics(0, x_sg, eq.y0, u_sg, ...
    eq.equilibrium_context, dev, tc.TestData.c);
tc.verifyEqual(char(m.rating_status), 'DECLARED_PROJECT_DERIVED');
tc.verifyEqual(m.rating_MVA, p.S_rated_MVA, 'AbsTol', 0);
tc.verifyEqual(char(m.rating_classification), 'PROJECT_DERIVED');
tc.verifyEqual(m.mechanical_power_pu, x_sg(4), 'AbsTol', 0);
tc.verifyEqual(m.mechanical_power_minus_electrical_pu, x_sg(4) - m.Pe_pu, ...
    'AbsTol', 1e-10);
tc.verifyEqual(char(m.Tm_pu_semantics), ...
    'PER_UNIT_COMMAND_CHANNEL_P_REF_NOT_ACTUAL_SHAFT_POWER');
tc.verifyNotEqual(char(m.rating_status), 'NOT_DECLARED');
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

function [eq, dev, x_sg, u_sg] = sg_solved_block(tc)
eq = tc.TestData.eq;
d = tc.TestData.dev_on;
idx = find(strcmp({d.device_id}, 'SG31'), 1);
xo = sum([d(1:idx-1).nx]);
uo = sum([d(1:idx-1).nu]);
dev = d(idx);
x_sg = eq.x0(xo + (1:dev.nx));
u_sg = eq.u_eq(uo + (1:dev.nu));
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
