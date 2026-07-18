function [devices, dev_meta] = build_ieee14_sg_ibr_devices(case_data, device_modes, dispatch_MW)
%BUILD_IEEE14_SG_IBR_DEVICES  Thin IEEE14 wrapper around the generic builder.
%   [DEVICES, DEV_META] = build_ieee14_sg_ibr_devices(CASE_DATA, DEVICE_MODES,
%       DISPATCH_MW) builds the 5-device IEEE14 bundle (SG1 + IBR2/3/6/8) via
%   the GENERIC stability.build_mixed_resource_devices, preserving the legacy
%   (case_data, device_modes, dispatch_MW) signature for existing callers.
%
%   This is a BACKWARD-COMPATIBLE wrapper. New code should call the generic
%   engine directly via +cases/scenario_ieee14_1sg_4ibr + stability.run_hybrid_case.
%   IEEE14 IDs (SG1, IBR2/3/6/8) and buses (1,2,3,6,8) are confined to the
%   scenario profile (cases.scenario_ieee14_1sg_4ibr); this wrapper only
%   translates the legacy signature into a scenario_opt.
%
%   The uniform device-struct schema emitted by the generic builder FIXES the
%   Phase B singular-Jacobian root cause (struct provenance mismatch between
%   SG and IBR devices). SG and IBR devices now share identical field names.
%
%   Inputs (legacy):
%     case_data   - the IEEE14 case (case_ieee14_1sg_4ibr_auto_vsg)
%     device_modes - struct array (.device_id, .mode) for the 4 IBRs
%     dispatch_MW  - struct with per-IBR active-power dispatch (MW, system base)
%
%   Output:
%     devices  - 1x5 struct array (uniform schema; SG1 first, then 4 IBRs)
%     dev_meta - struct with bus_ids, V0_per_bus, Sbase, resource_ids, etc.
%
%   Source: plan agent-a-atomic-lagoon.md (Phase B0 demote-to-wrapper).

arguments
    case_data struct
    device_modes struct
    dispatch_MW struct
end

% --- Translate legacy signature into a scenario_opt -------------------------
% device_modes applies to IBRs only (SG1 is always "synchronous" online here).
% An optional device_modes(k).gfl_family ('rms10') selects the GFL-RMS10
% branch for that IBR; it flows into the resource dynamic_params and on into
% dual_mode_ibr_model. Omitting it keeps the WECC default.
scenario_opt = struct();
scenario_opt.dispatch = dispatch_MW;
scenario_opt.initial_modes = device_modes;
gfl_families = struct();
for k = 1:numel(device_modes)
    if isfield(device_modes(k),'gfl_family') && ~isempty(device_modes(k).gfl_family)
        gfl_families.(device_modes(k).device_id) = char(device_modes(k).gfl_family);
    end
end

% --- Build the IEEE14 resource table via the scenario profile ---------------
% The profile confines IEEE14 IDs/buses; resource_table validates + freezes.
[resources, ~] = stability.resource_table(case_data, ...
    ieee14_resource_spec(gfl_families), scenario_opt);

% --- Dispatch the generic builder (uniform schema) --------------------------
[devices, dev_meta] = stability.build_mixed_resource_devices( ...
    case_data, resources, scenario_opt);
end

% =========================================================================
function spec = ieee14_resource_spec(gfl_families)
%IEEE14_RESOURCE_SPEC  IEEE14 resource table (IDs/buses confined HERE ONLY).
%   Mirrors +cases/scenario_ieee14_1sg_4ibr but as a local spec so this wrapper
%   stays self-contained for legacy callers that pass their own case_data.
%   Optional GFL_FAMILIES struct (fielded by IBR id) selects the RMS10 branch
%   for that IBR via dynamic_params.gfl_family.
if nargin < 1, gfl_families = struct(); end
Sbase = 100.0;
sg1 = struct( ...
    'resource_id','SG1','bus_id',1,'resource_type','sg','model_id','sg_emf6', ...
    'supported_modes',["synchronous","breaker_open"], ...
    'voltage_forming_modes',"synchronous", ...
    'initial_mode',"synchronous",'initial_online',true, ...
    'can_switch_mode',true,'can_switch_online',true, ...
    'has_current_limiter',false,'has_frt',false,'can_black_start',false, ...
    'limits',struct('ImaxSS',[],'ImaxF',[],'Pmax_MW',[],'Qmax_MVAr',[], ...
    'Emax',[],'Emin',[]), ...
    'ratings',struct('Mbase',615.0,'Sbase',Sbase), ...
    'dynamic_params',struct(), ...
    'provenance',struct('model','sg_emf6', ...
    'source','Kodsi U.Waterloo TR 2003-3 Table A.2 (60Hz, Gen1 bus1 615MVA)', ...
    'classification','CASE_DEFINED (decision ledger item 7)', ...
    'details','EMF6 6th-order; dynamics in case_data.machines'));
ibr_ids = {'IBR2','IBR3','IBR6','IBR8'};
buses = [2,3,6,8];
mbases = [140,100,100,100];
spec = sg1;
for k = 1:numel(ibr_ids)
    rid = ibr_ids{k};
    dyn_params = struct('Mbase',mbases(k));
    details = sprintf('20-state superset (GFM13+GFL7); Mbase=%.0f MVA',mbases(k));
    if isfield(gfl_families, rid)
        fam = gfl_families.(rid);
        dyn_params.gfl_family = fam;
        if strcmpi(strtrim(fam),'rms10')
            details = sprintf('23-state superset (GFM13+GFL-RMS10); Mbase=%.0f MVA',mbases(k));
        end
    end
    r = struct( ...
        'resource_id',rid,'bus_id',buses(k),'resource_type','ibr', ...
        'model_id','regfm_b1_dual', ...
        'supported_modes',["gfl","gfm","tripped"], ...
        'voltage_forming_modes',"gfm", ...
        'initial_mode',"gfl",'initial_online',true, ...
        'can_switch_mode',true,'can_switch_online',true, ...
        'has_current_limiter',true,'has_frt',true,'can_black_start',false, ...
        'limits',struct('ImaxSS',1.0,'ImaxF',1.5,'Pmax_MW',mbases(k), ...
        'Qmax_MVAr',mbases(k),'Emax',1.2,'Emin',0.8), ...
        'ratings',struct('Mbase',mbases(k),'Sbase',Sbase,'default_P_MW',0.0), ...
        'dynamic_params',dyn_params, ...
        'provenance',struct('model','regfm_b1_dual', ...
        'source','WECC REGC_A/REEC_A GFL + REGFM_B1 NREL/TP-5D00-90260 G2 GFM', ...
        'classification','Mbase=CASE_DEFINED nameplate proxy; controllers=SOURCE_DEFINED/SOURCE_MAPPED', ...
        'details',details));
    spec(end+1) = r; %#ok<AGROW>
end
end
