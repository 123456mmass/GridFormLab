function scenario = scenario_ieee14_1sg_4ibr(scenario_opt)
%SCENARIO_IEEE14_1SG_4IBR  IEEE14 1-SG + 4-IBR scenario profile (Layer 2).
%   scenario = scenario_ieee14_1sg_4ibr() builds the IEEE14 mixed-resource
%   scenario as an indexed RESOURCE TABLE bound to the immutable IEEE14 case
%   data. This is the ONLY place IEEE14 resource IDs (SG1, IBR2/3/6/8) and
%   their buses (1,2,3,6,8) appear as literals. The generic engine
%   (stability.*) never sees them.
%
%   Reuses case_ieee14_1sg_4ibr_auto_vsg for the immutable network/base +
%   SG dynamic data (Kodsi) + dispatch contract + synchronism/delays/selector
%   (all frozen). This profile only adds the resource-table Layer-1 contract
%   and binds it via stability.build_hybrid_scenario.
%
%   Resource table (5 entries, IEEE14-specific):
%     SG1  - sg_emf6, bus 1, Kodsi 615 MVA, supported {"synchronous","breaker_open"}
%     IBR2 - regfm_b1_dual, bus 2, Mbase 140, supported {"gfl","gfm","tripped"}
%     IBR3 - regfm_b1_dual, bus 3, Mbase 100, supported {"gfl","gfm","tripped"}
%     IBR6 - regfm_b1_dual, bus 6, Mbase 100, supported {"gfl","gfm","tripped"}
%     IBR8 - regfm_b1_dual, bus 8, Mbase 100, supported {"gfl","gfm","tripped"}
%
%   STATUS: STRUCTURAL_ONLY (Phase B0). No production-readiness claim.
%
%   Source: case_ieee14_1sg_4ibr_auto_vsg (frozen IEEE14 contract);
%           plan agent-a-atomic-lagoon.md (Layer 2 profile contract).

arguments
    scenario_opt struct = struct()
end

% --- Immutable IEEE14 case data (network/base + SG dynamics + contracts) ---
case_data = cases.case_ieee14_1sg_4ibr_auto_vsg();

% --- Build the resource table (IEEE14 IDs live HERE ONLY) ------------------
% SG1: Kodsi 60Hz EMF6 (decision ledger item 7). The SG factory reads SG
% dynamics from case_data.machines; dynamic_params carries no machine data.
sg1 = resource_entry( ...
    'SG1', 1, 'sg', 'sg_emf6', ...
    ["synchronous","breaker_open"], "synchronous", ...
    struct('Mbase', 615.0), struct());

% IBR2/3/6/8: dual-mode REGFM_B1 (Phase 7). Mbase = CASE_DEFINED unity-PF
% nameplate proxy (IBR2=140, IBR3/6/8=100). REGFM_B1 Table 1 params are
% SOURCE_VERBATIM defaults inside the model; only Mbase is per-resource.
ibr2 = ibr_entry('IBR2', 2, 140.0, 'gfl');
ibr3 = ibr_entry('IBR3', 3, 100.0, 'gfl');
ibr6 = ibr_entry('IBR6', 6, 100.0, 'gfl');
ibr8 = ibr_entry('IBR8', 8, 100.0, 'gfl');

resource_spec = [sg1, ibr2, ibr3, ibr6, ibr8];

% --- Validate the resource table (contract + capability + uniform schema) --
[resources, schema] = stability.resource_table(case_data, resource_spec, scenario_opt);

% --- Bind case_data + resource table + runtime opt into a scenario ---------
scenario = stability.build_hybrid_scenario(case_data, resources, scenario_opt);
scenario.resource_schema = schema;
scenario.scenario_id = 'ieee14_1sg_4ibr';
scenario.provenance = struct( ...
    'case_source', case_data.reference.network, ...
    'sg_dynamics', case_data.reference.sg_dynamics, ...
    'ibr_model', 'REGFM_B1 NREL/TP-5D00-90260 (dual-mode, Phase 7)', ...
    'classification', 'SG1=CASE_DEFINED (Kodsi); IBR Mbase=CASE_DEFINED nameplate proxy; REGFM_B1 Table 1=SOURCE_VERBATIM', ...
    'note', 'IEEE14 IDs/buses confined to this profile only; engine is case-agnostic');
end

% =========================================================================
function r = resource_entry(rid, bus, rtype, mid, supported, initial_mode, ratings, dyn_params)
%RESOURCE_ENTRY  Build one SG resource table entry (uniform provenance).
r = struct();
r.resource_id = rid;
r.bus_id = bus;
r.resource_type = rtype;
r.model_id = mid;
r.supported_modes = supported;
r.voltage_forming_modes = "synchronous";   % SG synchronous forms voltage
r.initial_mode = initial_mode;
r.initial_online = true;
r.can_switch_mode = true;          % SG can go breaker_open
r.can_switch_online = true;        % SG can trip/reclose
r.has_current_limiter = false;     % SG: no inverter limiter
r.has_frt = false;                 % SG: no FRT
r.can_black_start = false;
r.limits = struct( ...
    'ImaxSS', [], 'ImaxF', [], ...   % SG has no inverter current limit
    'Pmax_MW', [], 'Qmax_MVAr', [], ...
    'Emax', [], 'Emin', []);
r.ratings = ratings;
r.dynamic_params = dyn_params;
r.provenance = struct( ...
    'model', mid, ...
    'source', 'Kodsi U.Waterloo TR 2003-3 Table A.2 (60Hz, Gen1 bus1 615MVA); IEEE 1110-2002 Model 2.2', ...
    'classification', 'CASE_DEFINED (decision ledger item 7)', ...
    'details', 'EMF6 6th-order; dynamics in case_data.machines; SG factory reads them there');
end

% =========================================================================
function r = ibr_entry(rid, bus, Mbase, initial_mode)
%IBR_ENTRY  Build one dual-mode IBR resource table entry (uniform provenance).
r = struct();
r.resource_id = rid;
r.bus_id = bus;
r.resource_type = 'ibr';
r.model_id = 'regfm_b1_dual';
r.supported_modes = ["gfl","gfm","tripped"];
r.voltage_forming_modes = "gfm";   % only GFM forms voltage
r.initial_mode = initial_mode;
r.initial_online = true;
r.can_switch_mode = true;
r.can_switch_online = true;
r.has_current_limiter = true;
r.has_frt = true;
r.can_black_start = false;
% Current limits on IBR machine base (REGFM_B1 Table 1 example, CASE_DEFINED).
r.limits = struct( ...
    'ImaxSS', 1.0, 'ImaxF', 1.5, ...   % pu on machine base
    'Pmax_MW', Mbase, 'Qmax_MVAr', Mbase, ...
    'Emax', 1.2, 'Emin', 0.8);
r.ratings = struct('Mbase', Mbase, 'Sbase', 100.0, 'default_P_MW', 0.0);
% dynamic_params: only Mbase is per-IBR; REGFM_B1 Table 1 params are
% SOURCE_VERBATIM defaults inside regfm_b1_vsg_model.
r.dynamic_params = struct('Mbase', Mbase);
r.provenance = struct( ...
    'model', 'regfm_b1_dual', ...
    'source', 'REGFM_B1 NREL/TP-5D00-90260 Table 1 (dual-mode wrapper, Phase 7)', ...
    'classification', 'Mbase=CASE_DEFINED nameplate proxy (NOT Pmax-MW proven); Table 1=SOURCE_VERBATIM', ...
    'details', sprintf('15-state superset gfl/GFM/tripped; Mbase=%.0f MVA; kappa=Sbase/Mbase at boundary', Mbase));
end
