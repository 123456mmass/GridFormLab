function case_data = case_ne39()
%CASE_NE39 New England 39-bus, 10-machine system (plain network, no IBRs).
%
%   case_data = cases.case_ne39() returns the project's power_case/1.0 form of
%   the New England 345 kV test system: 39 buses, 46 branches, 10 synchronous
%   generators at buses 30-39, slack at bus 31.
%
%   THIS CASE CONTAINS NO INVERTER-BASED RESOURCES.  Every generator is a
%   synchronous machine.  bus_role therefore carries only SLACK/PV/PQ -- there
%   is no GFL or GFM entry anywhere.  That is deliberate: it makes adding IBRs
%   later an ADDITION (a scenario profile of the kind
%   cases.scenario_ieee14_1sg_4ibr demonstrates) rather than a rewrite, because
%   the resource table, the configuration selector and the event profiles are
%   all already case-agnostic.
%
%   PROVENANCE.  The numbers come from cases.ne39_raw, which cites the primary
%   source (G. W. Bills et al., EEI RP90-1 Report, October 12, 1970) rather than
%   MATPOWER or the PGAz transcription of it.  See that file's header for the
%   full chain and for the source's own caveat.  No MATPOWER routine is called.
%
%   THE SOURCE'S OWN STATED VIOLATIONS ARE CARRIED, NOT HIDDEN.  case39 is a
%   solved case that ships with known violations of its own limits:
%       - Pmax violated at bus 31: Pg = 677.87 MW, Pmax = 646 MW
%       - Qmin violated at bus 37: Qg = -1.37 MVAr, Qmin = 0 MVAr
%       - two binding Q limits at buses 34 and 37, so the voltages published at
%         those two buses have probably deviated from their setpoints
%   These are recorded in case_data.reference_solution_contract.known_violation
%   and the contract test exempts buses 34 and 37 BY NAME.  Nothing here is
%   retuned to make the case "clean": a case that agrees with its own reference
%   because a tolerance was loosened is a case whose evidence is worthless
%   (README.md "Nothing is tuned to make a test pass").
%
%   DYNAMICS ARE PROJECT_DERIVED, AND SAY SO.  The published source is a
%   power-flow case: it carries no H, no D and no reactances.  The 10 machines'
%   dynamics are derived per machine class from the published IEEE RTS-1996
%   Table 15 rows by the stated rule in cases.ne39_machine_parameters, whose
%   header carries the full derivation and its justification.  They are NOT
%   published New England parameters.  case_data.dynamics_contract reports
%   status 'SOURCED' and case_data.machines is attached, so PF/SSSA/TS run on
%   those derived numbers rather than on the project's classical defaults.
%
%   Because the dynamics are derived rather than sourced, any stability claim
%   this case supports in a report or deck is licensed ONLY together with the
%   inertia-sensitivity test at tests/test_ne39_dynamics_sensitivity.m, which
%   re-runs the classical SSSA with H scaled on every machine and reports how
%   far the answer moves.
%
%   Classification: SOURCE_DEFINED network data, PROJECT_DERIVED machine
%   dynamics (class mapping and per-machine assignment are the project's).
%
%   See also cases.ne39_raw, cases.ne39_machine_parameters, cases.standardize_case.

raw = cases.ne39_raw();
mpc = struct();
mpc.version = '2';
mpc.baseMVA = 100;              % SOURCE_DEFINED (raw.source, mpc.baseMVA)
mpc.bus = raw.bus;
mpc.gen = raw.gen;
mpc.branch = raw.branch;
mpc.gencost = raw.gencost;

case_data = convert_mpc_to_project_case(mpc);
case_data.system_name = 'IEEE 39-bus New England (10-machine)';
case_data.source = raw.source_citation;
case_data.source_detail = struct( ...
    'citation', raw.source_citation, ...
    'transcription', raw.source_file, ...
    'transcription_sha256', raw.source_sha256, ...
    'generator_sites', {raw.generator_sites}, ...
    'note', ['The published system description states it is generally ' ...
             'representative of the New England 345 kV system but is not an ' ...
             'exact or complete model of any past, present or projected ' ...
             'configuration of it.']);
case_data.mpc = mpc;
case_data.ne39 = struct( ...
    'bus', raw.bus, 'gen', raw.gen, 'branch', raw.branch, ...
    'gencost', raw.gencost, 'column_map', raw.column_map, ...
    'source_sha256', raw.source_sha256, ...
    'gen_dynamic_status', raw.gen_dynamic_status);

% The source's own published solved state.  Carried verbatim so the contract
% test can compare against the source instead of against the project's own
% output -- a test that compares a solver to itself proves nothing.
case_data.reference_solution = struct( ...
    'bus_voltage', raw.bus(:, 8), ...
    'bus_angle_deg', raw.bus(:, 9), ...
    'classification', 'SOURCE_DEFINED');
% The source's header warns of two binding Q limits at buses 34 and 37.  What
% that means for THIS case was MEASURED, not assumed, and the measurement is
% narrower than the warning:
%   * enforce_q_limits = false reproduces the published state to 4.8e-08 on all
%     39 buses, bus 37 included.  The published solution is an UNCONSTRAINED
%     solve whose bus-37 reactive output happens to sit below its own Qmin.
%   * enforce_q_limits = true clamps bus 37 from -1.37 MVAr to its Qmin of 0
%     MVAr and moves THAT BUS ONLY, by 5.25e-04 pu.  Bus 34 does not move: its
%     Qg of 166.69 MVAr sits 0.31 MVAr inside its Qmax of 167 MVAr.
% Recording the measured scope matters because a test that exempted both 34 and
% 37 "to be safe" would be hiding a bus that agrees perfectly.
case_data.reference_solution_contract = struct( ...
    'classification', 'SOURCE_DEFINED', ...
    'source', 'mpc.bus columns 8/9 (Vm_pu, Va_deg) of the published case', ...
    'unconstrained_agreement_pu', 4.799126e-08, ...
    'q_limit_shift_bus', 37, ...
    'q_limit_shift_pu', 5.254e-04, ...
    'known_violation', [ ...
        'The published case is an UNCONSTRAINED solve that violates its own ' ...
        'limits: Qmin at bus 37 (Qg -1.37 MVAr against Qmin 0 MVAr) and Pmax ' ...
        'at bus 31 (Pg 677.87 MW against Pmax 646 MW).  The source header also ' ...
        'warns of two binding Q limits at buses 34 and 37; measured, only bus ' ...
        '37 actually binds -- bus 34 sits 0.31 MVAr inside its Qmax.  With ' ...
        'enforce_q_limits=true only bus 37 moves, by 5.25e-04 pu.  The limits ' ...
        'are carried AS PUBLISHED and are NOT relaxed to make the case ' ...
        'self-consistent.'], ...
    'exempt_buses', 37, ...
    'note', ['tests/test_ne39_case.m asserts agreement on all 39 buses with ' ...
             'limits off, and pins the bus-37-only shift with limits on. ' ...
             'The exemption is applied BY BUS NUMBER, never by widening a ' ...
             'tolerance for the whole case.']);

% Slide 39 in this repository treats 39-bus as the scalability step beyond
% IEEE-14.  The default disturbance site is PROJECT_DERIVED -- it is a test
% scenario choice, not a claim about the published case, and the source
% nominates no fault.  events/evt_ne39_bus_fault.m lets a user override it
% without touching this file.
case_data.ts_defaults = struct( ...
    'fault_bus', 16, ...
    'fault_bus_classification', 'PROJECT_DERIVED', ...
    'fault_bus_rationale', [ ...
        'Bus 16 is a 345 kV PQ load bus with no local generation, so a fault ' ...
        'there is cleared by remote generation and exercises the transfer ' ...
        'paths. This is a TEST-SCENARIO choice by the project, not a ' ...
        'disturbance described by the published source.']);

case_data.dynamics_contract = ne39_dynamics_contract();
if strcmp(case_data.dynamics_contract.status, 'SOURCED')
    case_data.machines = case_data.dynamics_contract.machines;
end

case_data = cases.standardize_case(case_data);
end

% =========================================================================
function d = ne39_dynamics_contract()
%NE39_DYNAMICS_CONTRACT  The New England machines' dynamic data and its basis.
%   The single point of truth for "does this case have its own H, D and X'd?".
%   It reads cases.ne39_machine_parameters, whose classification is
%   'PROJECT_DERIVED' -- the 10 machines' dynamics are derived per class from
%   the published IEEE RTS-1996 Table 15 rows by the stated rule in that file's
%   header.  'UNSOURCED' is the ONLY not-sourced value: any other declaration,
%   'PROJECT_DERIVED' included, takes the sourced path below and attaches
%   .machines.  The old UNSOURCED_DYNAMICS branch is kept because it is the
%   fail-safe for a case whose dynamics are genuinely absent -- it is not a
%   second live path.
p = cases.ne39_machine_parameters();

d = struct();
d.model = 'classical';
d.source = p.source;
d.classification = p.classification;
if strcmp(p.classification, 'UNSOURCED')
    d.status = 'UNSOURCED_DYNAMICS';
    d.why = [ ...
        'The published 39-bus case is a power-flow case and carries no machine ' ...
        'dynamics, and cases.ne39_machine_parameters declares no derivation ' ...
        'for them. No machines field is attached, so no fabricated inertia ' ...
        'constant can reach the DAE; the project classical defaults apply and ' ...
        'stability.classical_sssa reports them by name.'];
    d.machines = [];
    return;
end

% SOURCED (PROJECT_DERIVED or SOURCE_DEFINED): convert the declared tables
% onto the system base.  Every rule below is dispatched on a base the SOURCE
% FILE DECLARES -- never assumed.
% Two conversion directions exist in this repository and they point opposite
% ways: case_ieee14bus_eecon49_switch.m stores H on the machine base because
% the EMF6 route divides internally, while case_ieee_rts24_pgaz.m stores it on
% the system base.  Guessing produces a plausible-looking case with the wrong
% inertia, so the declaration decides.
S_sys = 100;
u = p.unit;
nu = numel(u);
H = zeros(nu, 1); D = zeros(nu, 1); Xdp = zeros(nu, 1); bus = zeros(nu, 1);
for k = 1:nu
    bus(k) = u(k).bus;
    H(k)   = convert_inertia(u(k).H,   p.H_base,   u(k), S_sys);
    D(k)   = convert_inertia(u(k).D,   p.D_base,   u(k), S_sys);
    Xdp(k) = convert_reactance(u(k).Xdp, p.Xdp_base, u(k), S_sys);
end

% RTS-24 SHAPE, DELIBERATELY.  +stability/ts_simulate.m:462-476 applies a second
% H/D scaling pass AND assigns every unit the single machines.reactances.Xdp
% whenever a .reactances field is present. On a 10-machine case that is one
% shared reactance for ten machines plus a double conversion. Supplying .base
% and .units but NO .reactances avoids both; cases.case_ieee_rts24_pgaz.m:282-283
% does the same for the same reason.
units = struct('gen_id', {}, 'bus', {}, 'H', {}, 'D', {}, 'Xdp', {});
for k = 1:nu
    units(k) = struct('gen_id', u(k).gen_id, 'bus', bus(k), ...
        'H', H(k), 'D', D(k), 'Xdp', Xdp(k));
end
d.status = 'SOURCED';
d.machines = struct( ...
    'model', 'classical', ...
    'base', struct('S_MVA', S_sys, 'V_kV', 345, 'f_Hz', 60), ...
    'units', units);
d.base_declaration = struct('H_base', p.H_base, 'D_base', p.D_base, ...
    'Xdp_base', p.Xdp_base);
end

function v = convert_inertia(v, base, unit, S_sys)
%CONVERT_INERTIA  Inertia onto the system base, dispatched on the declaration.
switch base
    case 'MW_rating',  v = v * (unit.P_MW / S_sys);
    case 'MVA_rating', v = v * (unit.S_MVA / S_sys);
    case 'system_100', % already on the system base
    otherwise
        error('cases:case_ne39:unknownInertiaBase', ...
            'H_base/D_base "%s" is not one of MW_rating, MVA_rating, system_100.', base);
end
end

function v = convert_reactance(v, base, unit, S_sys)
%CONVERT_REACTANCE  X'd onto the system base, dispatched on the declaration.
switch base
    case 'MVA_rating', v = v * (S_sys / unit.S_MVA);
    case 'system_100', % already on the system base
    otherwise
        error('cases:case_ne39:unknownReactanceBase', ...
            'Xdp_base "%s" is not one of MVA_rating, system_100.', base);
end
end

% =========================================================================
function case_data = convert_mpc_to_project_case(mpc)
%CONVERT_MPC_TO_PROJECT_CASE  MATPOWER v2 matrices -> the project's case shape.
%   Follows +cases/case_matpower6_case14.m, with one deliberate difference:
%   case14 wipes its case_data with a bare `case_data = struct();` partway
%   through, discarding the bus_q_limits_classification it had just set.  This
%   version does not, so the reactive-limit provenance survives.
bus = mpc.bus; gen = mpc.gen; br = mpc.branch; base = mpc.baseMVA;
nb = size(bus, 1);

Pgen = zeros(nb, 1); Qgen = zeros(nb, 1);
for k = 1:size(gen, 1)
    if gen(k, 8) ~= 0
        idx = find(bus(:, 1) == gen(k, 1), 1);
        Pgen(idx) = Pgen(idx) + gen(k, 2)/base;
        Qgen(idx) = Qgen(idx) + gen(k, 3)/base;
    end
end

% MATPOWER bus types are 1=PQ, 2=PV, 3=SLACK; the project's internal type is the
% OPPOSITE: 1=slack, 2=PV, 3=PQ.  Remapped explicitly rather than assumed.
type = bus(:, 2);
proj_type = 3*ones(nb, 1);
proj_type(type == 3) = 1;
proj_type(type == 2) = 2;

% Warm start: the source's own voltage at slack/PV buses, flat 1.0 pu at PQ
% buses.  Deliberately NOT the source's solved voltage everywhere -- seeding the
% solver with the answer would make the reference comparison in
% tests/test_ne39_case.m vacuous.
V0 = ones(nb, 1);
V0(proj_type == 1 | proj_type == 2) = bus(proj_type == 1 | proj_type == 2, 8);
A0 = zeros(nb, 1);

% SOURCE_DEFINED reactive limits: mpc.gen columns 4/5 (Qmax/Qmin, MVAr).
Qmax_pu = Inf(nb, 1); Qmin_pu = -Inf(nb, 1);
for k = 1:size(gen, 1)
    if gen(k, 1) < 1 || gen(k, 1) > nb, continue; end
    idx = find(bus(:, 1) == gen(k, 1), 1);
    if isempty(idx), continue; end
    Qmax_pu(idx) = gen(k, 4)/base;
    Qmin_pu(idx) = gen(k, 5)/base;
end

case_data = struct();
case_data.bus_q_limits_classification = struct( ...
    'classification', 'SOURCE_DEFINED', ...
    'source', 'cases.ne39_raw mpc.gen columns 4/5 (Qmax/Qmin MVAr)', ...
    'conversion', 'Q_pu = Q_MVAr / S_base, S_base = 100 MVA (mpc.baseMVA)', ...
    'unconstrained', 'buses with no finite generator limit: Qmax=+Inf, Qmin=-Inf', ...
    'solver_columns', 'bus_data cols 11/12 = Qmin_pu/Qmax_pu', ...
    'known_violation', [ ...
        'Qmin is violated at bus 37 in the source''s own solved state ' ...
        '(Qg = -1.37 MVAr against Qmin = 0 MVAr). The limit is carried as ' ...
        'published and is NOT relaxed to make the case self-consistent. ' ...
        'Measured effect: enforcing Q limits moves bus 37 by 5.25e-04 pu and ' ...
        'no other bus, so the published state is reproducible with limits off.']);
case_data.base_values = struct('S_base_MVA', base, 'V_base_kV', 345, 'frequency_Hz', 60);
case_data.bus_data = [bus(:, 1), proj_type, V0, A0, Pgen, Qgen, ...
    bus(:, 3)/base, bus(:, 4)/base, bus(:, 5)/base, bus(:, 6)/base, ...
    Qmin_pu, Qmax_pu];
% The project's line_data column 5 is B_half; MATPOWER's branch column 5 is
% TOTAL line charging.  Halved once, here and only here.
tap = br(:, 9); tap(tap == 0) = 1;
case_data.line_data = [br(:, 1), br(:, 2), br(:, 3), br(:, 4), br(:, 5)/2, tap, br(:, 10)];
case_data.generator_buses = gen(:, 1);
end
