function tests = test_ne39_sg_reclose_plant
%TEST_NE39_SG_RECLOSE_PLANT  Primitive facts for the opt-in NE39 SG31 reduced
%reclose plant.
%
%   Exercises the ACTUAL interfaces only:
%     p   = stability.ne39_sg_reclose_plant_params(case_data, opt)
%     dev = stability.sg_classical_reclose_device(case_data, id, bus_id, ...
%                                  bus_position, bus_ids, V0, p)   (legacy 7 args)
%
%   Scope is deliberately primitive and factual:
%     * builder rejects unsupported composition, unknown/out-of-range options,
%       zero no-load loss and invalid machine/base input;
%     * source H, D and X'd pass through unchanged; the healthy operating point
%       is the same PF port the legacy two-state device solves;
%     * the stator envelope is an explicit frozen PROJECT_DERIVED rule
%       margin*hypot(Pmax_MW,Q_envelope), NOT MBASE;
%     * the legacy two-state device is unchanged and gains no new state;
%     * the new device declares its states explicitly, with nothing hidden;
%     * the exact shaft power balance and the instant offline RHS;
%     * a negative mechanical-power state fails closed or restores outward;
%     * the no-load equilibrium has no drift in any declared state;
%     * a forced-terminal +/-0.1 Hz capture screen driven by the ACTUAL device
%       f with a time-varying own-bus phasor;
%     * fixed-terminal finite-difference Jacobian of the ACTUAL f: all roots
%       finite and the offline augmented plant stable.
%
%   What this file deliberately does NOT do:
%     * no production/acceptance PASS token is declared anywhere; the capture
%       screen is a forced-terminal check on one device, not an SSSA, network or
%       mission certificate;
%     * no reclose event is asserted: no close transaction interface exists yet,
%       so no actual-reclose claim can honestly be made here;
%     * the 160 s raw and the legacy negative-coast disproof are NOT replayed.
%
%   While +stability/sg_classical_reclose_device.m is still being written, every
%   test that needs the factory reports INCOMPLETE via tc.assumeTrue. That is the
%   honest outcome: an assumption failure is not a pass.
tests = functiontests(localfunctions);
end

% =========================================================================
% Fixtures
% =========================================================================
function setupOnce(tc)
p = path;
tc.addTeardown(@() path(p));
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
tc.TestData.root = fileparts(fileparts(mfilename('fullpath')));
tc.TestData.c = cases.case_ne39_1sg_9ibr();
tc.TestData.p = stability.ne39_sg_reclose_plant_params(tc.TestData.c);
end

% =========================================================================
% Builder: accepted composition and declared schema
% =========================================================================
function test_builder_accepts_base_composition_and_declares_schema(tc)
c = tc.TestData.c;
p = stability.ne39_sg_reclose_plant_params(c, struct());
tc.verifyTrue(startsWith(p.schema_id, 'ne39_sg31_classical_reclose'), ...
    'the frozen plant schema identifier must be declared');
tc.verifyEqual(char(p.resource_id), 'SG31');
tc.verifyEqual(double(p.bus_id), 31);
tc.verifyEqual(char(p.classification), 'PROJECT_DERIVED');
tc.verifyEqual(double(p.system_base_MVA), double(c.base_values.S_base_MVA));
tc.verifyEqual(double(p.frequency_Hz), double(c.base_values.frequency_Hz));
% Defaults are declared for every optional design input.
for name = {'no_load_loss_fraction', 'Tsv_s', 'Tch_s', 'T_emag_s', ...
        'omega_n_rad_s', 'zeta_target', 'stator_rating_margin', 'omega_min_pu'}
    tc.verifyTrue(isfield(p, name{1}), sprintf('p.%s must be declared.', name{1}));
    tc.verifyTrue(isscalar(p.(name{1})) && isfinite(p.(name{1})), ...
        sprintf('p.%s must be one finite scalar.', name{1}));
end
% No tracker (PLL) field is asserted here: those fields are forthcoming and are
% gated by tc.assumeTrue in the tests that need them.
end

% =========================================================================
% Builder: rejection paths
% =========================================================================
function test_builder_rejects_unsupported_composition(tc)
c5 = cases.case_ne39_5sg_5ibr();
expect_error_prefix(tc, @() stability.ne39_sg_reclose_plant_params(c5), ...
    'stability:ne39_sg_reclose_plant_params:unsupportedComposition');
end

function test_builder_rejects_unknown_and_out_of_range_options(tc)
c = tc.TestData.c;
% Unknown option name.
expect_error_prefix(tc, ...
    @() stability.ne39_sg_reclose_plant_params(c, struct('not_an_option', 1)), ...
    'stability:ne39_sg_reclose_plant_params:unknownOption');
% Declared PROJECT_DERIVED ranges. Each call must fail closed, never clamp.
bad = { ...
    struct('no_load_loss_fraction', 0.06), ...
    struct('Tsv_s', 0.01), struct('Tsv_s', 0.50), ...
    struct('Tch_s', 0.10), struct('Tch_s', 0.90), ...
    struct('T_emag_s', 0.05), struct('T_emag_s', 2.00), ...
    struct('omega_n_rad_s', 0.05), struct('omega_n_rad_s', 0.50), ...
    struct('zeta', 0.50), struct('zeta', 2.00), ...
    struct('emag_min_fraction', 0.30), struct('emag_max_fraction', 2.00), ...
    struct('omega_min_pu', 0.01), struct('omega_min_pu', 0.90), ...
    struct('stator_rating_margin', 0.90), struct('stator_rating_margin', 1.50)};
for k = 1:numel(bad)
    expect_error_prefix(tc, ...
        @() stability.ne39_sg_reclose_plant_params(c, bad{k}), ...
        'stability:ne39_sg_reclose_plant_params:optionRange');
end
% Emag upper bound must exceed its lower bound.
expect_error_prefix(tc, @() stability.ne39_sg_reclose_plant_params(c, ...
    struct('emag_min_fraction', 1.00, 'emag_max_fraction', 1.00)), ...
    'stability:ne39_sg_reclose_plant_params:emagRange');
% An explicit prime-mover ceiling below the healthy shaft input fails closed.
% Both a clearly-too-small ceiling and one that is only below the healthy
% shaft input plus loss are exercised, because the binding headroom check and
% the earlier ceiling guard are separate statements.
expect_error_prefix(tc, ...
    @() stability.ne39_sg_reclose_plant_params(c, struct('Pmax_MW', 5)), ...
    'stability:ne39_sg_reclose_plant_params:');
expect_error_prefix(tc, ...
    @() stability.ne39_sg_reclose_plant_params(c, struct('Pmax_MW', 100)), ...
    'stability:ne39_sg_reclose_plant_params:');
end

function test_builder_rejects_zero_loss_and_bad_machine_inputs(tc)
c = tc.TestData.c;
% Zero loss is not admissible: with the source D=0 nothing could ever arrest an
% offline rotor, so a zero-loss plant must fail closed rather than silently
% degrade into the legacy unbeatable coast.
expect_error_prefix(tc, @() stability.ne39_sg_reclose_plant_params(c, ...
    struct('no_load_loss_fraction', 0)), ...
    'stability:ne39_sg_reclose_plant_params:optionRange');
% Machine data is read, never invented.
c2 = c; c2.machines.units(1).H = NaN;
expect_error_prefix(tc, @() stability.ne39_sg_reclose_plant_params(c2), ...
    'stability:ne39_sg_reclose_plant_params:machineData');
c3 = c; c3.machines.units(1).D = -1;
expect_error_prefix(tc, @() stability.ne39_sg_reclose_plant_params(c3), ...
    'stability:ne39_sg_reclose_plant_params:machineRange');
c4 = c; c4.machines.units(1).H = 0;
expect_error_prefix(tc, @() stability.ne39_sg_reclose_plant_params(c4), ...
    'stability:ne39_sg_reclose_plant_params:machineRange');
% H/D/Xdp must already be declared on the system power base.
c5 = c; c5.machines.base.S_MVA = 615;
expect_error_prefix(tc, @() stability.ne39_sg_reclose_plant_params(c5), ...
    'stability:ne39_sg_reclose_plant_params:machineBase');
c6 = c; c6.base_values.S_base_MVA = 0;
expect_error_prefix(tc, @() stability.ne39_sg_reclose_plant_params(c6), ...
    'stability:ne39_sg_reclose_plant_params:badBase');
% A non-positive SOLVED SG31 active dispatch has no operating point to freeze.
% Two inert mutations must not be used here:
%   * editing bus_data column 5 is inert on ANY row, because SG31 is the slack
%     and pf_build_results.m:12-13 overwrites P_generation for slack/PV buses
%     with the solved injection (P_final + P_load);
%   * changing the slack bus type (to PQ, or adding a second slack) makes
%     pf_prepare_case.m:135-137 reject the case -- "exactly one slack bus is
%     required" -- before this guard is ever reached.
% The only honest lever is the system-wide active imbalance. For a uniform
% active-load shed Delta, P_solved(SG31) = P_old - Delta + dP_losses, so any
% shed just past P_old (~5.504 pu) flips the solved injection negative. The
% smallest effective shed is tried first because it perturbs the network least:
% the 0.5/0.2/0 scales shed ~31/49/61 pu, reverse 25-55 pu through the network
% and collapse the PF (powerFlow) instead of reaching this guard.
shed_pu = [7 9 12];
load_pu = sum(c.bus_data(:, 7));
shed_hit = false;
shed_ids = repmat({'NOT_TRIED'}, 1, numel(shed_pu));
for k = 1:numel(shed_pu)
    ck = c;
    ck.bus_data(:, 7) = ck.bus_data(:, 7)*(1 - shed_pu(k)/load_pu);
    try
        stability.ne39_sg_reclose_plant_params(ck);
        shed_ids{k} = 'NO_ERROR';
    catch me
        shed_ids{k} = me.identifier;
        if strcmp(me.identifier, ...
                'stability:ne39_sg_reclose_plant_params:operatingPoint')
            shed_hit = true;
            break;
        end
    end
end
tc.verifyTrue(shed_hit, ...
    sprintf(['a uniform active-load shed that makes the SOLVED SG31 injection ' ...
    'non-positive must raise operatingPoint; observed: %s'], strjoin(shed_ids, ', ')));
% The stator envelope needs a declared reactive envelope.
c8 = c; row = find(c8.mpc.gen(:, 1) == 31, 1); c8.mpc.gen(row, 4:5) = [NaN NaN];
expect_error_prefix(tc, @() stability.ne39_sg_reclose_plant_params(c8), ...
    'stability:ne39_sg_reclose_plant_params:missingQEnvelope');
end

% =========================================================================
% Source values preserved; same operating point as the legacy device
% =========================================================================
function test_source_values_pass_through_and_match_legacy_operating_point(tc)
c = tc.TestData.c;
p = tc.TestData.p;
u = c.machines.units(1);
% H, D and X'd are passed through with no conversion and no reinterpretation.
tc.verifyEqual(p.H_system_s, double(u.H), 'AbsTol', 0);
tc.verifyEqual(p.D_system_pu, double(u.D), 'AbsTol', 0);
tc.verifyEqual(p.Xdp_system_pu, double(u.Xdp), 'AbsTol', 0);
tc.verifyEqual(p.D_system_pu, 0, 'AbsTol', 0, ...
    'the source D=0 must survive unchanged; the no-load loss is a separate field');
% The healthy operating point is recomputed independently from the case.
[~, P0, Q0, E0] = healthy_point(c);
tc.verifyEqual(p.P_ref0_pu, P0, 'RelTol', 1e-12);
tc.verifyEqual(p.Q0_pu, Q0, 'RelTol', 1e-12);
tc.verifyEqual(p.Emag0_pu, abs(E0), 'RelTol', 1e-12);
tc.verifyEqual(p.delta0_rad, angle(E0), 'AbsTol', 1e-12);
% MBASE is recorded for provenance only, never promoted to a stator rating.
tc.verifyTrue(isfield(p, 'machine_MBASE_MVA'));
tc.verifyTrue(isfield(p, 'machine_MBASE_role'));
tc.verifyEqual(char(p.machine_MBASE_role), ...
    'SOURCE_MODEL_NORMALIZATION_ONLY_NOT_STATOR_RATING');
% The legacy two-state device solves the same PF port, so the frozen healthy
% controls must agree with it to machine precision.
[~, dev_legacy, ~, ~, legacy_u0, legacy_x0] = legacy_device(tc);
tc.verifyEqual(dev_legacy.nx, 2);
tc.verifyEqual(p.P_ref0_pu, legacy_u0(1), 'RelTol', 1e-9, ...
    'the new plant must be anchored to the legacy healthy PF port');
tc.verifyEqual(p.Emag0_pu, legacy_u0(2), 'RelTol', 1e-9);
tc.verifyEqual(p.delta0_rad, legacy_x0(1), 'AbsTol', 1e-9);
end

% =========================================================================
% Stator envelope: explicit frozen rule, not MBASE
% =========================================================================
function test_rating_is_explicit_frozen_rule_and_not_mbase(tc)
c = tc.TestData.c;
p = tc.TestData.p;
tc.verifyEqual(p.S_rated_MVA, ...
    p.stator_rating_margin*hypot(p.Pmax_MW, p.Q_envelope_MVAr), 'RelTol', 1e-12);
tc.verifyEqual(p.I_rated_system_pu, p.S_rated_MVA/p.system_base_MVA, 'RelTol', 1e-12);
% The declared envelope is an apparent-power circle, not the source MBASE.
tc.verifyNotEqual(p.S_rated_MVA, p.machine_MBASE_MVA);
tc.verifyGreaterThan(p.S_rated_MVA, p.machine_MBASE_MVA);
tc.verifyTrue(isfinite(p.machine_MBASE_MVA), ...
    'the source MBASE must be recorded so its exclusion is auditable');
% Provenance: ceiling and stator proxy are project design assumptions; the
% reactive envelope comes from the source limits.
tc.verifyTrue(startsWith(p.Pmax_provenance, 'PROJECT_DERIVED'));
tc.verifyTrue(startsWith(p.Q_envelope_provenance, 'SOURCE_DEFINED'));
tc.verifyTrue(startsWith(p.stator_rating_provenance, 'PROJECT_DERIVED'));
% An explicit envelope and margin move the rating by exactly the frozen rule.
p2 = stability.ne39_sg_reclose_plant_params(c, ...
    struct('Q_envelope_MVAr', 500, 'stator_rating_margin', 1.25));
tc.verifyEqual(p2.S_rated_MVA, 1.25*hypot(p2.Pmax_MW, 500), 'RelTol', 1e-12);
tc.verifyTrue(startsWith(p2.Q_envelope_provenance, 'PROJECT_DERIVED'));
end

function test_loss_gain_headroom_consistency(tc)
p = tc.TestData.p;
% The loss is declared, positive, and derived only from the healthy dispatch.
tc.verifyGreaterThan(p.no_load_loss_pu, 0);
tc.verifyEqual(p.no_load_loss_pu, ...
    p.no_load_loss_fraction*p.P_ref0_pu, 'RelTol', 1e-12);
tc.verifyEqual(p.no_load_loss_MW, p.no_load_loss_pu*p.system_base_MVA, 'RelTol', 1e-12);
% Capture gains are recomputed independently from the documented linearization.
w0 = 2*pi*p.frequency_Hz;
tc.verifyEqual(p.Komega, ...
    4*p.H_system_s*p.zeta_target*p.omega_n_rad_s - p.D_system_pu - 2*p.no_load_loss_pu, ...
    'RelTol', 1e-12);
tc.verifyEqual(p.Ktheta, 2*p.H_system_s*p.omega_n_rad_s^2/w0, 'RelTol', 1e-12);
tc.verifyGreaterThanOrEqual(p.Komega, 0);
tc.verifyGreaterThan(p.Ktheta, 0);
% The healthy shaft input plus the declared loss must fit inside the ceiling.
tc.verifyGreaterThan(p.Pmax_pu, p.P_ref0_pu + p.no_load_loss_pu);
tc.verifyEqual(p.Pmax_pu, p.Pmax_MW/p.system_base_MVA, 'RelTol', 1e-12);
end

% =========================================================================
% Legacy device isolation
% =========================================================================
function test_legacy_two_state_device_is_unchanged(tc)
[c, dev, bp, V0] = legacy_device(tc);
tc.verifyEqual(dev.nx, 2, 'the legacy classical SG stays second order');
tc.verifyTrue(isequal(dev.state_names, {'delta', 'omega'}));
tc.verifyTrue(isequal(dev.input_names, {'Pm', 'Emag'}));
tc.verifyEqual(dev.x0(2), 1.0, 'AbsTol', 0, 'legacy state 2 is absolute speed');
tc.verifyEqual(double(dev.bus_position), double(bp));
% No augmented state or reference input may leak into the legacy device.
for name = {'Psv', 'theta_hat', 'nu_hat', 'P_ref', 'Emag_ref'}
    tc.verifyFalse(any(strcmp(dev.state_names, name{1})), ...
        sprintf('legacy device must not declare state %s', name{1}));
    tc.verifyFalse(any(strcmp(dev.input_names, name{1})), ...
        sprintf('legacy device must not declare input %s', name{1}));
end
% Default legacy construction stays finite and unchanged in kind.
ec = offline_context('SG31');
y = own_bus_y(size(c.bus_data, 1), bp, V0);
dx = dev.f(0, dev.x0, y, dev.u0, ec);
tc.verifyEqual(numel(dx), 2);
tc.verifyTrue(all(isfinite(dx)));
end

% =========================================================================
% New device: declared states are actual and all active
% =========================================================================
function test_declared_states_are_actual_and_all_active(tc)
[~, p, dev] = required_new_device(tc);
tc.verifyEqual(dev.nx, 7, 'the approved interface declares seven states');
tc.verifyTrue(isequal(dev.state_names, ...
    {'delta', 'omega', 'Psv', 'Pm', 'Emag', 'theta_hat', 'nu_hat'}));
tc.verifyTrue(isequal(dev.input_names, {'P_ref', 'Emag_ref'}), ...
    'inputs are electrical reference values, not the actual shaft-power state');
tc.verifyEqual(char(dev.device_type), 'sg_classical');
% Nothing is hidden: the declared name list covers every state exactly once.
tc.verifyEqual(numel(dev.state_names), dev.nx);
tc.verifyEqual(numel(unique(dev.state_names)), dev.nx);
tc.verifyEqual(numel(dev.input_names), dev.nu);
% The first two dynamics are the absolute-speed classical pair, as approved.
tc.verifyEqual(dev.x0(2), 1.0, 'AbsTol', 1e-12, 'state 2 is omega_ABS');
tc.verifyEqual(dev.x0(1), p.delta0_rad, 'AbsTol', 1e-9, ...
    'state 1 is the healthy rotor angle');
% Actual shaft/valve states start nonnegative and never below the loss floor.
tc.verifyGreaterThanOrEqual(dev.x0(3), 0);
tc.verifyGreaterThanOrEqual(dev.x0(4), p.no_load_loss_pu - 1e-12);
tc.verifyGreaterThanOrEqual(dev.x0(5), p.Emag_min_pu - 1e-12);
tc.verifyLessThanOrEqual(dev.x0(5), p.Emag_max_pu + 1e-12);
% All seven coordinates are active, offline included: the actuator and tracker
% states must keep being integrated while the breaker is open.
if isfield(dev, 'frozen_state_indices')
    tc.verifyTrue(isempty(dev.frozen_state_indices));
end
if isfield(dev, 'active_state_indices')
    tc.verifyTrue(isequal(sort(dev.active_state_indices(:))', 1:7));
end
if isfield(dev, 'dynamic_state_indices_for_context') && ...
        isa(dev.dynamic_state_indices_for_context, 'function_handle')
    idx = dev.dynamic_state_indices_for_context(offline_context('SG31'));
    tc.verifyTrue(isequal(sort(idx(:))', 1:7));
end
% The equilibrium-control layout is declared for the later normalization step.
% Heterogeneous concatenation with other factories is NOT asserted here.
if isfield(dev, 'equilibrium_control_layout')
    tc.verifyEqual(char(dev.equilibrium_control_layout), ...
        'classical_reclose_pref_emag_ref');
end
end

% =========================================================================
% Exact shaft power balance and instant offline RHS (no integration)
% =========================================================================
function test_instant_offline_shaft_rhs_energy_balance(tc)
[c, p, dev] = required_new_device(tc);
ec = offline_context('SG31');
nb = size(c.bus_data, 1);
bp = double(dev.bus_position);
y = own_bus_y(nb, bp, abs(p.Emag0_pu)*exp(1i*p.delta0_rad));
u = [p.P_ref0_pu; p.Emag0_pu];
i_w = state_index(tc, dev, 'omega');
i_pm = state_index(tc, dev, 'Pm');
% The shaft RHS is evaluated with the mechanical state HELD at the given value.
% This is an instant-RHS test only: no trajectory is claimed, and none is
% possible here because the active governor would move Pm.
w = 1.05;
x = [p.delta0_rad; w; 0; 0; p.Emag0_pu; p.delta0_rad; 0];
dx = dev.f(0, x, y, u, ec);
oracle = (0 - 0 - p.no_load_loss_pu*w^2 - p.D_system_pu*w*(w-1))/(2*p.H_system_s*w);
tc.verifyEqual(dx(i_w), oracle, 'RelTol', 1e-9, ...
    'dx(omega) must be the documented power balance 2H w dw = Pm - Pe - L0 w^2 - D w (w-1)');
tc.verifyLessThan(dx(i_w), 0, 'with Pm=0 and Pe=0 the offline shaft must decelerate');
tc.verifyTrue(all(isfinite(dx)));
% With the shaft exactly at the speed-dependent no-load balance, dx(omega)=0.
% Only the shaft coordinate is asserted: valve/chest coordinates are still
% moving at this instant, so the whole vector is not an equilibrium.
x_eq = x; x_eq(i_pm) = p.no_load_loss_pu*w^2;
dx_eq = dev.f(0, x_eq, y, u, ec);
tc.verifyEqual(dx_eq(i_w), 0, 'AbsTol', 1e-12, ...
    'the shaft RHS must vanish at the speed-dependent no-load balance Pm = L0 w^2');
% And a positive shaft power accelerates.
x_hi = x; x_hi(i_pm) = p.Pmax_pu;
dx_hi = dev.f(0, x_hi, y, u, ec);
tc.verifyGreaterThan(dx_hi(i_w), 0, ...
    'a positive shaft power must accelerate the offline rotor');
tc.verifyTrue(all(isfinite(dx_hi)));
end

function test_negative_mechanical_power_fails_closed_or_restores(tc)
[c, p, dev] = required_new_device(tc);
ec = offline_context('SG31');
nb = size(c.bus_data, 1);
bp = double(dev.bus_position);
y = own_bus_y(nb, bp, abs(p.Emag0_pu)*exp(1i*p.delta0_rad));
u = [p.P_ref0_pu; p.Emag0_pu];
i_pm = state_index(tc, dev, 'Pm');
x = [p.delta0_rad; 1.0; 0; -0.5*p.no_load_loss_pu; p.Emag0_pu; p.delta0_rad; 0];
% Either the device rejects the non-physical state, or its own derivative must
% push the shaft power back OUT of the negative half-plane. Silently riding a
% negative mechanical power is the one outcome that is not acceptable.
try
    dx = dev.f(0, x, y, u, ec);
    tc.verifyGreaterThan(dx(i_pm), 0, ...
        ['a negative mechanical-power state must either fail closed or have an ' ...
         'outward (restoring) derivative; got dx(Pm) <= 0']);
catch me
    tc.verifyTrue(startsWith(me.identifier, 'stability:sg_classical_reclose_device'), ...
        sprintf(['a rejected negative-power state must fail closed with a device ' ...
        'error id, got "%s"'], me.identifier));
end
end

% =========================================================================
% No-load equilibrium: every declared derivative vanishes
% =========================================================================
function test_no_load_equilibrium_derivatives_vanish(tc)
[c, p, dev] = required_new_device(tc);
ec = offline_context('SG31');
nb = size(c.bus_data, 1);
bp = double(dev.bus_position);
theta_bus = 0.07;
Vbus = 1.0*exp(1i*theta_bus);
y = own_bus_y(nb, bp, Vbus);
% No-load setup: electrical active reference 0, own-bus voltage matched, shaft
% and valve at the speed-dependent loss, tracker locked, no tracker rate.
u = [0; abs(Vbus)];
x = [theta_bus; 1.0; p.no_load_loss_pu; p.no_load_loss_pu; abs(Vbus); theta_bus; 0];
dx = dev.f(0, x, y, u, ec);
tc.verifyEqual(norm(dx, inf), 0, 'AbsTol', 1e-9, ...
    'the no-load equilibrium must have no drift in any declared state');
for name = {'delta', 'omega', 'Psv', 'Pm', 'Emag', 'theta_hat', 'nu_hat'}
    i = state_index(tc, dev, name{1});
    tc.verifyEqual(dx(i), 0, 'AbsTol', 1e-9, ...
        sprintf('d%s/dt must vanish at the no-load equilibrium', name{1}));
end
end

% =========================================================================
% Forced-terminal +/-0.1 Hz capture screen on the ACTUAL device f
% =========================================================================
function test_offline_capture_screen_forced_terminal_plus_point_one_hz(tc)
[c, p, dev] = required_new_device(tc);
tc.assumeTrue(isfield(p, 'pll_Kp_rad_s'), ...
    'tracker (PLL) gains are forthcoming in the params interface; INCOMPLETE by design.');
w0 = 2*pi*p.frequency_Hz;
df_hz = 0.1;                       % declared worst-case practical grid offset
w_grid = 1 + df_hz/p.frequency_Hz; % absolute pu
nb = size(c.bus_data, 1);
bp = double(dev.bus_position);
theta0 = 0.07;
theta_bus = @(t) theta0 + w0*(df_hz/p.frequency_Hz)*t;
% Forced terminal: ONLY the device's own bus carries a phasor. This is a
% device-local screen, not a network or SSSA certificate, and no gate PASS is
% declared from it.
yfun = @(t) own_bus_y(nb, bp, 1.0*exp(1i*theta_bus(t)));
u = [0; 1.0];                      % no-load electrical active reference
% Start with the tracker locked to the offset grid and the machine at nominal
% speed: the screen asks whether the machine is captured onto the offset grid.
x0 = [theta0; 1.0; p.no_load_loss_pu; p.no_load_loss_pu; 1.0; theta0; w0*(df_hz/p.frequency_Hz)];
odef = @(t, x) dev.f(t, x(:), yfun(t), u, offline_context('SG31'));
sol = ode113(odef, [0 125], x0(:), ...
    odeset('RelTol', 1e-7, 'AbsTol', 1e-9, 'MaxStep', 0.02));
t = sol.x(:).';
X = sol.y;
tc.verifyEqual(size(X, 1), dev.nx);
i_d = state_index(tc, dev, 'delta');
i_w = state_index(tc, dev, 'omega');
i_pm = state_index(tc, dev, 'Pm');
i_em = state_index(tc, dev, 'Emag');
i_nu = state_index(tc, dev, 'nu_hat');
w_hat = 1 + X(i_nu, :)/w0;
slip = abs(X(i_w, :) - w_hat);
pe = wrap_to_pi(theta_bus(t) - X(i_d, :));
% Physical envelopes must hold across the whole screen.
tc.verifyTrue(all(X(i_pm, :) >= 0), 'the actual shaft power must stay nonnegative');
tc.verifyTrue(all(X(i_em, :) >= p.Emag_min_pu - 1e-12 & ...
    X(i_em, :) <= p.Emag_max_pu + 1e-12), ...
    'Emag must stay inside its declared envelope');
tc.verifyTrue(all(X(i_w, :) >= p.omega_min_pu), ...
    'the speed must stay above the declared admissible minimum');
% The tracker must have locked to the OFFSET grid, not to nominal.
tail_m = t >= (t(end) - 5);
tc.verifyLessThan(abs(mean(w_hat(tail_m)) - w_grid), 1e-4, ...
    'the tracker must lock onto the offset grid frequency, not nominal');
% Capture screen: in the closing window both offset gates of the case hold, and
% a sustained close-eligible window of at least the declared dwell exists.
tc.verifyLessThan(max(slip(tail_m)), c.synchronism.df_max_pu, ...
    'residual slip must fall inside the declared df gate before the horizon');
tc.verifyLessThan(max(abs(pe(tail_m))), deg2rad(c.synchronism.dtheta_max_deg), ...
    'residual phase error must fall inside the declared dtheta gate');
elig = slip < c.synchronism.df_max_pu & abs(pe) < deg2rad(c.synchronism.dtheta_max_deg);
window = t >= max(0, t(end) - 20);
run_s = longest_true_run(elig(window), t(window));
tc.verifyGreaterThanOrEqual(run_s, c.synchronism.dwell_s - 1e-12, ...
    'a sustained close-eligible window of at least the declared dwell is required');
% Reported, not gated: the transient phase excursion while the rotor is captured.
fprintf(['NE39_SG_RECLOSE_CAPTURE forced_terminal df_hz=%.3f slip_last5s=%.3e ' ...
    'phase_last5s_deg=%.4f phase_max_deg=%.4f eligible_run_s=%.3f\n'], ...
    df_hz, max(slip(tail_m)), rad2deg(max(abs(pe(tail_m)))), ...
    rad2deg(max(abs(pe))), run_s);
end

% =========================================================================
% Fixed-terminal FD Jacobian of the ACTUAL f
% =========================================================================
function test_fixed_terminal_fd_jacobian_roots_finite(tc)
[c, p, dev] = required_new_device(tc);
tc.assumeTrue(isfield(p, 'pll_Kp_rad_s'), ...
    'tracker (PLL) gains are forthcoming in the params interface; INCOMPLETE by design.');
ec = offline_context('SG31');
nb = size(c.bus_data, 1);
bp = double(dev.bus_position);
theta_bus = 0.07;
Vbus = 1.0*exp(1i*theta_bus);
y = own_bus_y(nb, bp, Vbus);
u = [0; abs(Vbus)];
x0 = [theta_bus; 1.0; p.no_load_loss_pu; p.no_load_loss_pu; abs(Vbus); theta_bus; 0];
nx = dev.nx;
J = zeros(nx);
h = 1e-6;
for k = 1:nx
    step = zeros(nx, 1);
    step(k) = h;
    J(:, k) = (dev.f(0, x0 + step, y, u, ec) - dev.f(0, x0 - step, y, u, ec))/(2*h);
end
tc.verifyTrue(all(isfinite(J(:))), 'the fixed-terminal Jacobian must be finite');
lam = eig(J);
tc.verifyEqual(numel(lam), nx);
tc.verifyTrue(all(isfinite(lam)), 'every offline augmented root must be finite');
tc.verifyLessThan(max(real(lam)), 0, ...
    'the offline augmented plant must be stable at the no-load equilibrium');
fprintf(['NE39_SG_RECLOSE_ROOTS nx=%d max_real_eig=%.6e min_real_eig=%.6e ' ...
    'max_abs_eig=%.6e\n'], nx, max(real(lam)), min(real(lam)), max(abs(lam)));
% Full-network SSSA on the augmented partition is an integration step and is
% NOT claimed here.
end

% =========================================================================
% Helpers
% =========================================================================
function [c, dev, bp, V0, u0, x0] = legacy_device(tc)
c = tc.TestData.c;
bus_ids = c.bus_data(:, 1).';
bp = find(bus_ids == 31, 1);
V0 = c.bus_data(bp, 3)*exp(1i*deg2rad(c.bus_data(bp, 4)));
dev = stability.sg_classical_device(c, "SG31", 31, bp, bus_ids, V0, struct());
u0 = dev.u0;
x0 = dev.x0;
end

function [c, p, dev] = required_new_device(tc)
c = tc.TestData.c;
p = tc.TestData.p;
tc.assumeTrue(has_reclose_factory(tc), ...
    '+stability/sg_classical_reclose_device.m is not present yet; INCOMPLETE by design.');
bus_ids = c.bus_data(:, 1).';
bp = find(bus_ids == 31, 1);
V0 = c.bus_data(bp, 3)*exp(1i*deg2rad(c.bus_data(bp, 4)));
dev = stability.sg_classical_reclose_device(c, "SG31", 31, bp, bus_ids, V0, p);
end

function tf = has_reclose_factory(tc)
tf = exist(fullfile(tc.TestData.root, '+stability', ...
    'sg_classical_reclose_device.m'), 'file') == 2;
end

function [V0, P0, Q0, E0] = healthy_point(c)
row = find(c.bus_data(:, 1) == 31, 1);
V0 = c.bus_data(row, 3)*exp(1i*deg2rad(c.bus_data(row, 4)));
P0 = c.bus_data(row, 5);
Q0 = c.bus_data(row, 6);
E0 = V0 + 1i*c.machines.units(1).Xdp*conj((P0 + 1i*Q0)/V0);
end

function ec = offline_context(device_id)
key = matlab.lang.makeValidName(char(device_id), 'ReplacementStyle', 'underscore');
ec = struct('hybrid_state', struct( ...
    'device_online', struct(key, false), ...
    'device_modes', struct(key, 'breaker_open')));
end

function y = own_bus_y(nb, bp, Vbus)
y = zeros(2*nb, 1);
y(2*bp - 1) = real(Vbus);
y(2*bp) = imag(Vbus);
end

function i = state_index(tc, dev, name)
i = find(strcmp(dev.state_names, name), 1);
tc.verifyNotEmpty(i, sprintf('the device must declare state %s', name));
end

function a = wrap_to_pi(a)
a = mod(a + pi, 2*pi) - pi;
end

function run_s = longest_true_run(flag, tt)
run_s = 0;
i = 1;
n = numel(flag);
while i <= n
    if flag(i)
        j = i;
        while j < n && flag(j + 1)
            j = j + 1;
        end
        run_s = max(run_s, tt(j) - tt(i));
        i = j + 1;
    else
        i = i + 1;
    end
end
end

function expect_error_prefix(tc, fn, prefix)
threw = false;
try
    fn();
catch me
    threw = true;
    tc.verifyTrue(startsWith(me.identifier, prefix), ...
        sprintf('expected an error id starting with "%s", got "%s" (%s)', ...
        prefix, me.identifier, me.message));
end
tc.verifyTrue(threw, sprintf('expected an error id starting with "%s"', prefix));
end
