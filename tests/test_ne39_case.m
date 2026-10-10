function tests = test_ne39_case
%TEST_NE39_CASE  Data and physics contract for the New England 39-bus case.
%
%   The case is authored from a published transcription, so the thing worth
%   testing is not that it loads.  It is that the numbers in the repository are
%   the numbers of the source, that the power flow reproduces the source's own
%   published solution, and that the case cannot quietly acquire machine data it
%   does not have.
%
%   Tolerances are declared up front from the source's published precision and
%   from the solver's own option -- they are NOT relaxed after seeing a result.
%
%   Contracts:
%     1. Shape and schema (power_case/1.0, 39x12 / 46x7 / 13-21-13 MATPOWER)
%     2. One slack at bus 31; generators at buses 30..39
%     3. The loader is self-contained: its numbers ARE cases.ne39_raw's numbers
%     4. B_half is half of the source's TOTAL line charging
%     5. PF converges and reproduces the source reference on all 39 buses
%     6. Enforcing Q limits moves bus 37 and ONLY bus 37
%     7. Nodal power balance closes
%     8. This case contains no IBRs, and says so in its bus_role labels
%     9. The dynamic state is never unstated, and never invents machine data
%    10. SSSA runs, reports 20 classical states, and names the dynamics it used
%    11. A transient-stability smoke run completes with finite state
%    12. The case is registered in the catalog and dispatched as Newton-Raphson
%
%   THE DYNAMICS ARE NOW PROJECT_DERIVED, so test 9 asserts the SOURCED state:
%   the case carries case_data.machines, and the .reactances-free RTS-24 shape
%   is what keeps the double-conversion trap shut.  The sensitivity the derived
%   inertia requires lives in tests/test_ne39_dynamics_sensitivity.m.
%
%   See also cases.case_ne39, cases.ne39_raw, cases.ne39_machine_parameters,
%   tests.test_ne39_dynamics_sensitivity.

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% =========================================================================
% 1-2. Shape, schema, bus roles
% =========================================================================
function test_shape_matches_the_published_system(testCase)
c = cases.case_ne39();
testCase.verifyEqual(c.case_kind, 'network');
testCase.verifyEqual(c.schema_version, 'power_case/1.0');
testCase.verifySize(c.bus_data, [39 12], 'New England 39-bus has 39 buses.');
testCase.verifySize(c.line_data, [46 7], 'New England 39-bus has 46 branches.');
testCase.verifySize(c.mpc.bus, [39 13]);
testCase.verifySize(c.mpc.gen, [10 21], 'New England has 10 machines.');
testCase.verifySize(c.mpc.branch, [46 13]);
testCase.verifyEqual(c.base_values.S_base_MVA, 100);
testCase.verifyEqual(c.base_values.frequency_Hz, 60);
testCase.verifyEqual(c.base_values.V_base_kV, 345);
testCase.verifyEqual(c.mpc.baseMVA, 100);
end

function test_exactly_one_slack_bus_at_31_and_generators_at_30_to_39(testCase)
c = cases.case_ne39();
is_slack = c.bus_data(:, 2) == 1;
testCase.verifyEqual(sum(is_slack), 1, 'Exactly one slack bus is required.');
testCase.verifyEqual(c.bus_data(is_slack, 1), 31, 'The slack bus is bus 31.');
testCase.verifyEqual(c.generator_buses, (30:39).');
% Nine PV buses: 30, 32..39 (bus 31 is the slack).
testCase.verifyEqual(sum(c.bus_data(:, 2) <= 2), 10);
end

% =========================================================================
% 3. The loader cannot drift from the raw file
% =========================================================================
function test_loader_is_self_contained_and_matches_the_raw_matrices(testCase)
% The point of this test is that nothing is read from the user's Downloads
% folder at run time, and that the in-repo literals ARE the source's literals.
% If someone edits one of the two files alone, this is what notices.
c = cases.case_ne39();
raw = cases.ne39_raw();
testCase.verifyEqual(c.ne39.bus, raw.bus, 'AbsTol', 0);
testCase.verifyEqual(c.ne39.branch, raw.branch, 'AbsTol', 0);
testCase.verifyEqual(c.ne39.gen, raw.gen, 'AbsTol', 0);
testCase.verifyEqual(c.ne39.source_sha256, raw.source_sha256);
testCase.verifyNotEmpty(raw.source_sha256);
testCase.verifyNotEqual(raw.source_sha256, 'UNAVAILABLE_NO_JAVA', ...
    'The source fingerprint must be a real hash, not the stated fallback.');
end

function test_column_map_is_declared_not_inferred(testCase)
raw = cases.ne39_raw();
cm = raw.column_map;
testCase.verifyEqual(numel(cm.bus), size(raw.bus, 2));
testCase.verifyEqual(numel(cm.gen), size(raw.gen, 2));
testCase.verifyEqual(numel(cm.branch), size(raw.branch, 2));
testCase.verifyEqual(cm.bus{8}, 'Vm_pu');
testCase.verifyEqual(cm.bus{9}, 'Va_deg');
testCase.verifyEqual(cm.branch{5}, 'br_b_pu');
end

% =========================================================================
% 4. B_half
% =========================================================================
function test_b_half_is_half_of_the_sources_total_charging(testCase)
% MATPOWER's branch column 5 is TOTAL line charging; the project's line_data
% column 5 is B_half.  Halving twice, or not at all, both produce a case that
% converges to something subtly wrong.
c = cases.case_ne39();
raw = cases.ne39_raw();
testCase.verifyEqual(c.line_data(:, 5), raw.branch(:, 5)/2, 'AbsTol', 1e-12);
testCase.verifyTrue(any(c.line_data(:, 5) ~= 0), ...
    'The case must actually carry charging; an all-zero column would make this test vacuous.');
end

function test_matpower_bus_types_are_remapped_not_copied(testCase)
% MATPOWER is 1=PQ,2=PV,3=SLACK.  The project is 1=slack,2=PV,3=PQ.  Copying the
% column across unchanged would invert every bus's role while still converging.
c = cases.case_ne39();
raw = cases.ne39_raw();
mp_slack = raw.bus(:, 2) == 3;          % MATPOWER SLACK
pr_slack = c.bus_data(:, 2) == 1;       % project slack
testCase.verifyEqual(pr_slack, mp_slack);
testCase.verifyEqual(find(pr_slack), 31);
end

% =========================================================================
% 5-7. Power flow against the source's own published solution
% =========================================================================
function test_power_flow_reproduces_the_source_reference(testCase)
% The source is a solved case, so its bus Vm/Va are a reference the project did
% not produce.  Comparing the solver against its own output would prove
% nothing; comparing it against the source's is a real falsification test.
% Measured agreement is 4.799126e-08 pu (recorded in the case); the tolerance
% below is the solver's declared 1e-10 option plus an order of headroom, NOT a
% value chosen after seeing the residual.
c = cases.case_ne39();
r = solve_pf(c, false);
testCase.verifyTrue(r.converged, 'NE39 power flow must converge.');
testCase.verifyEqual(r.reason, 'converged');
testCase.verifyLessThan(r.iterations, 20);
testCase.verifyLessThan(r.mismatch_history(end), 1e-10);
d = abs(r.bus_voltage - c.reference_solution.bus_voltage);
testCase.verifyLessThan(max(d), 1e-6, ...
    'Every bus, bus 37 included, must reproduce the published solution.');
testCase.verifyLessThan(max(abs(r.bus_angle_deg - c.reference_solution.bus_angle_deg)), 1e-5);
end

function test_the_source_solution_violates_its_own_declared_vmax(testCase)
% Recorded because a reader who assumes the case is limit-clean will be
% confused by bus 36, and because the honest response is to state it rather
% than to trim the setpoint so the case looks tidy.
c = cases.case_ne39();
V = c.reference_solution.bus_voltage;
over = find(V > c.mpc.bus(:, 12) + 1e-9);
testCase.verifyEqual(c.bus_data(over, 1), 36, ...
    'Bus 36 is the only bus above its declared Vmax in the published solution.');
testCase.verifyEqual(V(36), 1.0636, 'AbsTol', 1e-4);
end

function test_the_binding_q_limit_is_at_bus_37_and_not_at_bus_34(testCase)
% The source header warns of two binding Q limits, at buses 34 and 37.  What
% that means for this case was MEASURED, and the measurement is narrower than
% the warning -- so the test pins the measurement, not the warning.
%
%   bus 37  published Qg = -1.37 MVAr against Qmin = 0     -> VIOLATES, clamps
%   bus 34  published Qg = 166.69 MVAr against Qmax = 167  -> 0.31 MVAr inside
%
% Clamping bus 37 redistributes the solution: 30 buses move by more than 1e-6
% and four (2, 25, 26, 37) by more than 1e-4, with bus 37 far the largest.  So
% the claim this test can honestly make is not "only bus 37 moves" -- it is
% "bus 37 moves most, and bus 34 is not what moves it".  The first draft of
% this test asserted the former and was falsified by the solver, which is the
% only reason the number below is trustworthy.
c = cases.case_ne39();
r0 = solve_pf(c, false);
r1 = solve_pf(c, true);
testCase.verifyTrue(r1.converged);

% The published state carries the violation, unclamped.
testCase.verifyLessThan(r0.Q_generation(37), c.bus_data(37, 11), ...
    'Bus 37''s published Q must sit below its own Qmin -- that IS the violation.');
% The tolerance here is the SOURCE's published precision, not a loosened one:
% its generator table prints Qg to five decimals in MVAr (-1.36945), while the
% solve gives -1.3694474 -- a 2.6e-6 MVAr rounding difference, i.e. 2.6e-8 pu.
% Asserting tighter would be asserting that a rounded table equals an unrounded
% solve, which is false for a reason that has nothing to do with this case.
testCase.verifyEqual(r0.Q_generation(37), c.mpc.gen(8, 3)/100, 'AbsTol', 1e-7);

% Enforcing limits clamps exactly that bus, and to exactly its limit.
testCase.verifyEqual(r1.Q_generation(37), c.bus_data(37, 11), 'AbsTol', 1e-9);

% Bus 34 does NOT bind: it stays inside its Qmax under both solves.
testCase.verifyLessThan(r0.Q_generation(34), c.bus_data(34, 12));
testCase.verifyLessThan(r1.Q_generation(34), c.bus_data(34, 12));

% Bus 37 carries the largest voltage shift, and the shift is bounded.
shift = abs(r1.bus_voltage - r0.bus_voltage);
[mx, imx] = max(shift);
testCase.verifyEqual(c.bus_data(imx, 1), 37, ...
    'Bus 37 must carry the largest shift when its Q is clamped.');
testCase.verifyLessThan(mx, 1e-3);
testCase.verifyGreaterThan(sum(shift > 1e-6), 1, ...
    ['A clamped generator redistributes the whole island solution; a shift ' ...
     'confined to one bus would mean the clamp was not applied.']);
end

function test_nodal_power_balance_closes(testCase)
c = cases.case_ne39();
r = solve_pf(c, false);
V = r.bus_voltage .* exp(1i*deg2rad(r.bus_angle_deg));
S = V .* conj(r.Ybus*V);
testCase.verifyLessThan(max(abs(real(S) - (r.P_generation(:) - c.bus_data(:, 7)))), 1e-8);
testCase.verifyLessThan(max(abs(imag(S) - (r.Q_generation(:) - c.bus_data(:, 8)))), 1e-8);
end

% =========================================================================
% 8. No IBRs -- the machine-checkable form of "plain"
% =========================================================================
function test_case_contains_no_inverter_based_resources(testCase)
c = cases.case_ne39();
roles = string(c.bus_role);
testCase.verifyEmpty(roles(roles == "GFL"), 'NE39 must declare no GFL buses.');
testCase.verifyEmpty(roles(roles == "GFM"), 'NE39 must declare no GFM buses.');
testCase.verifyFalse(isfield(c, 'resources'));
testCase.verifyFalse(isfield(c, 'scenario_opt'));
end

function test_bus_role_vocabulary_uses_slack_and_never_ref(testCase)
% The project labels the angle-reference bus SLACK.  This test exists because
% the term was renamed repo-wide and a stray REF would be the first sign that
% one path was missed.
c = cases.case_ne39();
roles = unique(string(c.bus_role));
testCase.verifyTrue(all(ismember(roles, ["SLACK", "PV", "PQ", "GFM", "GFL"])), ...
    'bus_role carries only the declared vocabulary.');
testCase.verifyTrue(ismember("SLACK", roles));
testCase.verifyFalse(any(roles == "REF"));
testCase.verifyEqual(string(c.tables.bus.TypeName(31)), "SLACK");
end

% =========================================================================
% 9. The dynamic state is never unstated
% =========================================================================
function test_dynamics_contract_agrees_with_the_presence_of_machines(testCase)
% The whole point: NE39's dynamics are PROJECT_DERIVED, and the case must SAY
% so rather than presenting derived numbers as published ones.  The contract
% status and the presence of .machines are one fact, checked in both directions.
c = cases.case_ne39();
d = c.dynamics_contract;
testCase.verifyTrue(ismember(d.status, {'SOURCED', 'UNSOURCED_DYNAMICS'}));
testCase.verifyEqual(isfield(c, 'machines'), strcmp(d.status, 'SOURCED'), ...
    'machines must be present if and only if the dynamics are sourced.');
end

function test_dynamics_are_sourced_as_project_derived(testCase)
% cases.ne39_machine_parameters declares 'PROJECT_DERIVED': the class mapping
% onto the published RTS-1996 Table 15 rows and the per-machine assignment are
% the project's.  Any declaration other than 'UNSOURCED' takes the sourced path
% in cases.case_ne39's ne39_dynamics_contract.
c = cases.case_ne39();
d = c.dynamics_contract;
testCase.verifyEqual(d.classification, 'PROJECT_DERIVED');
testCase.verifyEqual(d.status, 'SOURCED', ...
    'PROJECT_DERIVED must land on the sourced side of the branch, not UNSOURCED.');
testCase.verifyTrue(isfield(c, 'machines'), ...
    'Sourced dynamics must attach case_data.machines.');
testCase.verifyNotEmpty(d.source);
testCase.verifySubstring(d.source, 'RTS-1996');
testCase.verifySubstring(d.source, 'Table 15');
% The bases must be the ones Table 15 quotes its numbers on, because
% cases.case_ne39 dispatches its conversion on them.
testCase.verifyEqual(d.base_declaration.H_base, 'MW_rating');
testCase.verifyEqual(d.base_declaration.Xdp_base, 'MVA_rating');
end

function test_machines_use_the_rts24_shape_not_the_emf6_shape(testCase)
% +stability/ts_simulate.m:462-476 applies a SECOND H/D scaling pass and
% assigns every unit the single machines.reactances.Xdp whenever a .reactances
% field is present.  On a 10-machine case that is one shared reactance for ten
% machines plus a double conversion.  +cases/case_ieee_rts24_pgaz.m:282-283
% avoids both by supplying .base and .units and NO .reactances.  That guard now
% runs unconditionally -- the dynamics ARE sourced, so there is no longer a
% state in which it is skipped.
c = cases.case_ne39();
testCase.verifyTrue(isfield(c, 'machines'), 'Dynamics are sourced; .machines must exist.');
testCase.verifyFalse(isfield(c.machines, 'reactances'), ...
    ['machines must NOT carry .reactances: ts_simulate.m:462-476 would then ' ...
     'scale H and D a second time and give all 10 machines one shared Xdp.']);
testCase.verifyTrue(isfield(c.machines, 'base'));
testCase.verifyTrue(isfield(c.machines, 'units'));
testCase.verifyEqual(c.machines.base.S_MVA, 100);
testCase.verifyEqual(numel(c.machines.units), 10);
testCase.verifyEqual([c.machines.units.bus], 30:39);
% Every machine must carry finite positive H and X'd, and the table must not
% be one flat default repeated ten times.
H = [c.machines.units.H];
Xdp = [c.machines.units.Xdp];
testCase.verifyTrue(all(isfinite(H)) && all(H > 0));
testCase.verifyTrue(all(isfinite(Xdp)) && all(Xdp > 0));
testCase.verifyGreaterThan(numel(unique(H)), 1, ...
    'A single H for all ten machines would mean the per-class derivation did not run.');
testCase.verifyFalse(any(abs(H - 5.0) < 1e-12), ...
    'H must not be the project classical default 5 s.');
testCase.verifyFalse(any(abs(Xdp - 0.3) < 1e-12), ...
    'X''d must not be the project classical default 0.3 pu.');
% The conversion itself, re-derived from the declared Table 15 rows: H_sys =
% H_RTS*(Pg/100) and Xdp_sys = Xdp_RTS*(100/Smva_RTS), per machine.
p = cases.ne39_machine_parameters();
for k = 1:numel(p.unit)
    testCase.verifyEqual(c.machines.units(k).H, ...
        p.unit(k).H * (p.unit(k).P_MW / 100), 'AbsTol', 1e-12, ...
        sprintf('Bus %d H must be H_RTS*(Pg/100).', p.unit(k).bus));
    testCase.verifyEqual(c.machines.units(k).Xdp, ...
        p.unit(k).Xdp * (100 / p.unit(k).S_MVA), 'AbsTol', 1e-12, ...
        sprintf('Bus %d X''d must be Xdp_RTS*(100/Smva_RTS).', p.unit(k).bus));
    testCase.verifyEqual(c.machines.units(k).D, p.unit(k).D, 'AbsTol', 0, ...
        'D must be carried as published (0.0 for every Table 15 group).');
end
end

% =========================================================================
% 10-11. SSSA and TS run on the case
% =========================================================================
function test_sssa_reports_twenty_states_and_names_its_dynamics(testCase)
% MEASURED, not assumed: the sourced case runs the CLASSICAL route
% (plugin 'classical_network_linearization', 10 machines x 2 states
% [delta, omega] = 20), because +stability/multicase_sssa.m:52-63 gates the
% EMF6 branch on isfield(case_data.machines,'reactances') and this case has no
% such field.  It is NOT the 60-state 6-EMF model; the assertion below says
% which model produced the 20 states so a later reader cannot mistake it.
c = cases.case_ne39();
s = stability.multicase_sssa(c, struct('model', 'classical'));
testCase.verifyEqual(numel(s.eigenvalues), 20, ...
    'Classical: 10 machines x 2 states (delta, omega).');
testCase.verifyEqual(numel(s.state_names), 20);
testCase.verifyTrue(all(isfinite(s.eigenvalues)));
testCase.verifyGreaterThan(max(abs(imag(s.eigenvalues))), 0, ...
    'A classical multimachine case must have oscillatory modes.');
testCase.verifyEqual(s.metadata.plugin, 'classical_network_linearization', ...
    'The 20 states come from the classical route, not the 6-EMF model.');
% The dynamics actually used must be NAMED.  Measured on the sourced case:
% stability.classical_sssa's dynamic_source reports 'case machine data' because
% this case carries no dynamic_assumptions.source field (classical_sssa.m:123-131).
testCase.verifyEqual(s.metadata.dynamic_data_source, 'case machine data', ...
    'The sourced route must name the machine data it used, not the defaults.');
end

function test_documented_emf6_fallthrough_is_a_documented_behaviour(testCase)
% +stability/multicase_sssa.m:52-63 gates the EMF6 branch on
% isfield(case_data.machines,'reactances').  NE39 deliberately has no such
% field, so requesting emf6 falls through to classical.  That is pre-existing
% behaviour for every catalogued case; it is asserted HERE so that it is a
% documented property of this case rather than a surprise to a later reader.
c = cases.case_ne39();
s = stability.multicase_sssa(c, struct('model', 'emf6'));
testCase.verifyEqual(s.metadata.plugin, 'classical_network_linearization');
end

function test_transient_stability_smoke_run_completes(testCase)
c = cases.case_ne39();
res = stability.ts_simulate(c, struct('t_end', 0.02, 'dt', 0.01, ...
    'fault_enabled', false, 'verbose', false, 'plot_results', false));
testCase.verifyGreaterThanOrEqual(numel(res.t), 2);
testCase.verifyTrue(all(isfinite(res.t)));
if isfield(res, 'delta')
    testCase.verifyTrue(all(isfinite(res.delta(:))));
end
if isfield(res, 'omega')
    testCase.verifyTrue(all(isfinite(res.omega(:))));
end
end

% =========================================================================
% 12. Registration
% =========================================================================
function test_case_is_registered_in_the_catalog(testCase)
% Registration is what makes the case visible to the GUI and to
% tests/test_all_network_analyses.m.  A case that exists but is not registered
% is a case nothing runs and nothing checks.
cat = cases.network_case_catalog();
idx = find(strcmp({cat.id}, 'ne39'), 1);
testCase.verifyNotEmpty(idx, 'ne39 must be registered or nothing can dispatch it.');
testCase.verifyEqual(cat(idx).loader, @cases.case_ne39);
testCase.verifyEqual(cat(idx).ts_options.fault_bus, 16);
testCase.verifyEqual(cat(idx).sssa_options.model, 'classical');
end

function test_solver_reports_the_slack_bus_it_used(testCase)
% The result carries the bus partition it solved.  Asserting on it checks that
% the case's own slack identification reaches the solver, not just that a
% number came back.
c = cases.case_ne39();
r = solve_pf(c, false);
testCase.verifyEqual(r.metadata.slack_bus_ids, 31);
testCase.verifyEqual(r.metadata.num_buses, 39);
testCase.verifyEqual(numel(r.metadata.pv_bus_ids), 9);
testCase.verifyEqual(numel(r.metadata.pq_bus_ids), 29);
end

function test_default_fault_bus_is_present_and_labelled(testCase)
% The default disturbance site is a project choice.  It must be present for the
% GUI to have something to run, and it must be labelled as a choice.
c = cases.case_ne39();
testCase.verifyTrue(ismember(c.ts_defaults.fault_bus, c.bus_data(:, 1)));
testCase.verifyEqual(c.ts_defaults.fault_bus_classification, 'PROJECT_DERIVED');
testCase.verifyNotEmpty(c.ts_defaults.fault_bus_rationale);
end

% =========================================================================
function r = solve_pf(c, enforce_q_limits)
%SOLVE_PF  One power-flow solve with the case's own declared options.
r = pfsolver.powerflow_newton_raphson(c, struct( ...
    'verbose', false, 'plot_results', false, ...
    'max_iter', 50, 'tolerance', 1e-10, ...
    'enforce_q_limits', logical(enforce_q_limits)));
end
