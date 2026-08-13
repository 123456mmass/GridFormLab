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
%     IBR2/3/6/8 - profile-owned dual-mode IBRs at buses 2/3/6/8.
%       mission: REGFM_B1 + WECC/RMS10 family and historical nameplates.
%       eecon49_figure4: shared-plant GFL(PLL)/GFM(VSG, no PLL), 100 MVA each.
%       decoupled_figure4: the same case and GFL branch with the project GFM
%         swing whose droop, transient damping and inertia are independent
%         (ibr.decoupled_dual_mode_model, 17 states).
%
%   STATUS: SOURCE_MODELS_IMPLEMENTED_PENDING_END_TO_END_GATES.
%
%   Source: case_ieee14_1sg_4ibr_auto_vsg (frozen IEEE14 contract);
%           plan agent-a-atomic-lagoon.md (Layer 2 profile contract).

arguments
    scenario_opt struct = struct()
end

% --- Immutable IEEE14 case data (network/base + SG dynamics + contracts) ---
case_profile = 'mission';
if isfield(scenario_opt,'case_profile') && ~isempty(scenario_opt.case_profile)
    case_profile = lower(char(scenario_opt.case_profile));
end
switch case_profile
    case 'mission'
        case_data = cases.case_ieee14_1sg_4ibr_auto_vsg();
    case 'eecon49_figure4'
        case_data = cases.case_ieee14bus_eecon49_switch();
    case 'decoupled_figure4'
        % Same immutable network/base/dispatch/event case as the source
        % profile, so the two GFM structures are compared on identical inputs.
        % Only the IBR GFM swing model and its parameters differ.
        case_data = cases.case_ieee14bus_eecon49_switch();
    otherwise
        error('cases:scenario_ieee14_1sg_4ibr:badCaseProfile', ...
            'Unknown case_profile "%s".',case_profile);
end

% Normal operation uses the frozen pre-fault dispatch from the mission case.
% Previously an omitted scenario_opt.dispatch silently constructed all four
% IBRs at zero MW and made the SG carry the complete system load, contradicting
% the case contract and the later post-trip participation schedule.
if ~isfield(scenario_opt,'dispatch') || ...
        ~isstruct(scenario_opt.dispatch) || ...
        isempty(fieldnames(scenario_opt.dispatch))
    pf = case_data.dispatch_contract.pre_fault;
    scenario_opt.dispatch = struct( ...
        'IBR2',pf.IBR2_Pg_MW,'IBR3',pf.IBR3_Pg_MW, ...
        'IBR6',pf.IBR6_Pg_MW,'IBR8',pf.IBR8_Pg_MW);
end

% --- Build the resource table (IEEE14 IDs live HERE ONLY) ------------------
% SG1: Kodsi 60Hz EMF6 (decision ledger item 7). The SG factory reads SG
% dynamics from case_data.machines; dynamic_params carries no machine data.
sg1 = resource_entry( ...
    'SG1', 1, 'sg', 'sg_emf6', ...
    ["synchronous","breaker_open"], "synchronous", ...
    struct('Mbase', 615.0), struct());

% IBR2/3/6/8 construction profile.  Legacy remains the API default.  The
% opt-in Profile B constructs the 23-state dual family for all four devices;
% runtime mode selection then activates IBR2 GFM13 and IBR3/6/8 GFL-RMS10.
ibr_profile = 'legacy';
if isfield(scenario_opt, 'ibr_profile') && ~isempty(scenario_opt.ibr_profile)
    ibr_profile = lower(char(scenario_opt.ibr_profile));
end
switch ibr_profile
    case 'legacy'
        gfl_family = '';
    case 'rms10_profile_b'
        gfl_family = 'rms10';
    otherwise
        error('cases:scenario_ieee14_1sg_4ibr:badIbrProfile', ...
            'Unknown ibr_profile "%s".', ibr_profile);
end

% IBR2/3/6/8: profile-owned dual-mode model and machine base.
% The mission case retains its historical nameplates. The Figure-4 source
% case defines a common 100-MVA IBR base for every converter.
% The EECON49 Figure-4 case additionally owns a nonzero GFL reactive-power
% schedule in bus_data(:,6).  Preserve it in resource metadata so the generic
% factory does not silently replace the mapped PQ operating point by unity PF.
% Other profiles retain their historical Q_ref=0 default exactly.
q_default_MVAr = zeros(1,4);
if any(strcmp(case_profile,{'eecon49_figure4','decoupled_figure4'}))
    q_default_MVAr = case_ibr_q_dispatch_MVAr(case_data,[2 3 6 8]);
    if strcmp(case_profile,'decoupled_figure4')
        ibr_model_id = 'decoupled_dual';
    else
        ibr_model_id = 'eecon49_dual';
    end
    ibr_Mbase = [100 100 100 100];
    if ~isempty(gfl_family)
        error('cases:scenario_ieee14_1sg_4ibr:profileConflict', ...
            '%s owns its GFL/GFM branches; rms10_profile_b is incompatible.', ...
            case_profile);
    end
else
    ibr_model_id = 'regfm_b1_dual';
    ibr_Mbase = [140 100 100 100];
end
ibr2 = ibr_entry('IBR2',2,ibr_Mbase(1),'gfl',gfl_family,q_default_MVAr(1),ibr_model_id);
ibr3 = ibr_entry('IBR3',3,ibr_Mbase(2),'gfl',gfl_family,q_default_MVAr(2),ibr_model_id);
ibr6 = ibr_entry('IBR6',6,ibr_Mbase(3),'gfl',gfl_family,q_default_MVAr(3),ibr_model_id);
ibr8 = ibr_entry('IBR8',8,ibr_Mbase(4),'gfl',gfl_family,q_default_MVAr(4),ibr_model_id);

resource_spec = [sg1, ibr2, ibr3, ibr6, ibr8];

% --- Validate the resource table (contract + capability + uniform schema) --
[resources, schema] = stability.resource_table(case_data, resource_spec, scenario_opt);

% --- Bind case_data + resource table + runtime opt into a scenario ---------
scenario = stability.build_hybrid_scenario(case_data, resources, scenario_opt);
scenario.resource_schema = schema;
scenario.scenario_id = 'ieee14_1sg_4ibr';
if strcmp(case_profile,'eecon49_figure4')
    scenario.scenario_id = 'ieee14_eecon49_1sg_4ibr';
elseif strcmp(case_profile,'decoupled_figure4')
    scenario.scenario_id = 'ieee14_decoupled_1sg_4ibr';
end
if strcmp(ibr_model_id,'eecon49_dual')
    ibr_model_label = 'project-owned full-state GFL(PLL) + GFM(VSG without PLL) shared-plant dual';
    ibr_classification = ['AC/control equations=SOURCE_MAPPED; DC-source regulator, ' ...
        'fixed superset and transfer=PROJECT_DERIVED; parameters/bases=CASE_DEFINED'];
elseif strcmp(ibr_model_id,'decoupled_dual')
    ibr_model_label = ['project-owned full-state GFL(PLL) + GFM(decoupled VSG ' ...
        'without PLL, independent droop/damping/inertia) shared-plant dual'];
    ibr_classification = ['GFL and shared-plant AC/control equations=SOURCE_MAPPED; ' ...
        'GFM swing block (R_droop/D_t/wD washout), DC-source regulator, fixed ' ...
        'superset and transfer=PROJECT_DERIVED; bases=CASE_DEFINED'];
else
    ibr_model_label = sprintf('%s GFL + REGFM_B1 G2 GFM dual-mode superset',gfl_family_label(gfl_family));
    ibr_classification = ['SG1=CASE_DEFINED (Kodsi); IBR Mbase=CASE_DEFINED nameplate proxy; ' ...
        'REGFM_B1 Table 1=SOURCE_VERBATIM'];
end
scenario.provenance = struct( ...
    'case_source', case_data.reference.network, ...
    'sg_dynamics', case_data.reference.sg_dynamics, ...
    'ibr_model',ibr_model_label, ...
    'classification',ibr_classification, ...
    'note', 'IEEE14 IDs/buses confined to this profile only; engine is case-agnostic');
end

function label = gfl_family_label(family)
if strcmpi(family, 'rms10')
    label = 'GFL-RMS10 (23-state dual)';
else
    label = 'WECC REGC_A/REEC_A (20-state dual)';
end
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
function r = ibr_entry(rid,bus,Mbase,initial_mode,gfl_family,default_Q_MVAr,model_id)
%IBR_ENTRY  Build one dual-mode IBR resource table entry (uniform provenance).
%   Optional GFL_FAMILY (5th arg) selects the GFL branch at construction:
%     '' | 'wecc_regca_reeca'  -> WECC 7-state (default, 20-state dual)
%     'rms10'                  -> GFL-RMS10 10-state (23-state dual)
%   DEFAULT_Q_MVAR is the case-owned initial GFL reactive-power dispatch.
%   The family and dispatch flow through the resource table into the generic
%   builder. Omitting either optional value preserves the historical defaults.
if nargin < 5, gfl_family = ''; end
if nargin < 6, default_Q_MVAr = 0.0; end
if nargin < 7, model_id = 'regfm_b1_dual'; end
r = struct();
r.resource_id = rid;
r.bus_id = bus;
r.resource_type = 'ibr';
r.model_id = model_id;
r.supported_modes = ["gfl","gfm","tripped"];
r.voltage_forming_modes = "gfm";   % only GFM forms voltage
r.initial_mode = initial_mode;
r.initial_online = true;
r.can_switch_mode = true;
r.can_switch_online = true;
r.has_current_limiter = true;
r.has_frt = true;
r.can_black_start = false;
if any(strcmp(model_id,{'eecon49_dual','decoupled_dual'}))
    ImaxSS=1.2; ImaxF=1.2;
else
    ImaxSS=1.0; ImaxF=1.5;
end
r.limits = struct( ...
    'ImaxSS',ImaxSS,'ImaxF',ImaxF, ...   % pu on machine base
    'Pmax_MW', Mbase, 'Qmax_MVAr', Mbase, ...
    'Emax', 1.2, 'Emin', 0.8);
r.ratings = struct('Mbase', Mbase, 'Sbase', 100.0, ...
    'default_P_MW', 0.0, 'default_Q_MVAr', default_Q_MVAr);
% dynamic_params: Mbase is shared at the system/device boundary. WECC and
% REGFM_B1 parameters otherwise remain owned by their source-model defaults.
% An optional gfl_family selects the RMS10 opt-in branch (construction-time).
r.dynamic_params = struct('Mbase', Mbase);
if any(strcmp(model_id,{'eecon49_dual','decoupled_dual'}))
    r.dynamic_params.Sbase=100.0;
    r.dynamic_params.fbase=60.0;
    % Converter command/actuation delay (source eq.(20)-(21), first-order lag
    % v_del/v_cmd = 1/(1+T_d s)) is REDUCED OUT of the state vector. The delay
    % is NOT source-specified: PROJECT_DERIVED, owner-set 2026-08-12 from
    % digital-VSC control physics -- T_d = 1.5*Ts = 1.5/f_sw (computation 1
    % sample + PWM/zero-order hold 0.5 sample). At the utility-scale switching/
    % control frequency f_sw = 5 kHz (Ts = 0.2 ms) this is T_d = 3.0e-4 s, which
    % is >300x below the phasor step dt = 0.10 s. By singular perturbation the
    % fast lag collapses onto its slow manifold v_del = v_cmd, so the two delay
    % states per branch are removed and the AC current dynamics use the
    % commanded voltage directly (see the device models). This retires the
    % earlier placeholder T_d = 0.02 s, whose ~530 Hz-class pole the RMS network
    % model cannot resolve and which produced a spurious +1.29@11.4 Hz mode
    % (defect TD-2026-08-12-01). f_sw is stored below as the reduction basis;
    % no Td parameter is passed to the device builders.
    r.dynamic_params.f_sw_Hz=5000;
    r.dynamic_params.gfl_eecon49=struct('Lf',0.15,'Rf',0.015,'Cdc',0.10, ...
        'Vdc_ref',1.0,'Imax',1.2,'kpPLL',1.2,'kiPLL',5.0, ...
        'kpP',0.8,'kiP',2.5,'kpQ',0.8,'kiQ',2.5,'kpI',0.3,'kiI',4.0);
    if strcmp(model_id,'eecon49_dual')
    r.dynamic_params.gfm_eecon49=struct('Lf',0.15,'Rf',0.015,'Cdc',0.10, ...
        'Vdc_ref',1.0,'Imax',1.2,'M',0.08,'Dv',20.0, ...
        'tauE',0.05,'kQ',0.25,'kE',8.0,'kpV',1.2,'kiV',4.5, ...
        'kpI',0.3,'kiI',4.0);
    % Dv=20.0 is PROJECT_DERIVED (owner-set 2026-08-13) for the islanded
    % grid-forming role.  The frozen design target it meets is a 5 % P-f droop
    % (within the WECC/CAISO 3-5 % practice and the ERCOT GFM test assumption
    % <=5 %).  The source-printed value is Dv=1.50 (66.7 % droop), verified in
    % docs/text/EECON49_[Nui].pdf p.5 -- readable with `pdftotext -layout`;
    % only the Read tool cannot render it, which is a tool limitation and NOT
    % encryption.  In this single-coefficient VSG the same Dv also sets the
    % swing damping: at the MEASURED synchronising coefficient
    % K = 0.1135..0.1862 pu/rad (full-KCL Schur-reduced SSSA, all-GFM
    % SG-online) Dv=20 gives zeta = 4.22..5.40, i.e. heavily over-damped, and
    % Dv=1.50 gives zeta = 0.41.  Reaching zeta = 1/sqrt(2) here would need
    % Dv = 2.6..3.4, i.e. 30-38 % droop.  Droop and damping therefore cannot
    % both be placed by this structure; that documented limitation is what
    % ibr.gfm_decoupled_full_model addresses.  M=0.08 (H_v=0.04 s) unchanged.
    % Derivation and both values side by side:
    % docs/project/EECON49_GFL_GFM_SOURCE_CONTRACT.md, "GFM swing droop and
    % damping".
    else
    % Decoupled GFM swing (PROJECT_DERIVED, this project's own model).  Values
    % corrected 2026-08-13 after the island SSSA surface was measured; the
    % derivation and the withdrawn earlier basis are in
    % docs/project/DECOUPLED_GFM_SOURCE_CONTRACT.md:
    %   R_droop=0.05  5 % P-f droop, the same grid-code band and the same static
    %                 droop as the Dv=20 baseline, so the two structures are
    %                 compared at equal droop.  Unaffected by D_t and wD.
    %   M=0.08        unchanged source-printed inertia (H_v=0.04 s), so the
    %                 comparison is also at equal inertia;
    %   D_t=0.0       measured result, not an omission: in the authenticated
    %                 all-four ISLAND every D_t>0 degrades the margin
    %                 monotonically at every washout corner tested (wD=3..100),
    %                 and SG-online D_t does not move the dominant mode at all
    %                 (1e-6 across the same sweep).  No positive value is
    %                 defensible on this system.  An earlier D_t=20 with wD=3.0
    %                 put the island at +0.336 (unstable) where the coupled
    %                 baseline is -0.483;
    %   wD=50.0       REGFM_B1 Table-1 SOURCE_VERBATIM washout corner, ~13x
    %                 above this island's slowest mode (3.92 rad/s), so a caller
    %                 that does enable D_t keeps the washout pole clear of the
    %                 mode that sets the island margin.
    r.dynamic_params.gfm_decoupled=struct('Lf',0.15,'Rf',0.015,'Cdc',0.10, ...
        'Vdc_ref',1.0,'Imax',1.2,'M',0.08, ...
        'R_droop',0.05,'D_t',0.0,'wD',50.0, ...
        'tauE',0.05,'kQ',0.25,'kE',8.0,'kpV',1.2,'kiV',4.5, ...
        'kpI',0.3,'kiI',4.0);
    end
    r.dynamic_params.dc_source=struct('Tdc',0.10);
elseif ~isempty(gfl_family)
    r.dynamic_params.gfl_family = gfl_family;
end
if strcmp(model_id,'eecon49_dual')
    source='EECON49-P4 Eqs.(6)-(29), Figs.1-2 and parameter table';
    classification=['AC/control=SOURCE_MAPPED; base/reference/parameters=CASE_DEFINED; ' ...
        'DC-source regulator and transfer=PROJECT_DERIVED'];
    details=sprintf(['16-state shared-plant superset; GFL controller owns PLL; ' ...
        'GFM controller owns VSG and no PLL; Mbase=%.0f MVA; default Q=%.9g MVAr; Tdc=0.10 s'], ...
        Mbase,default_Q_MVAr);
elseif strcmp(model_id,'decoupled_dual')
    source=['GFL branch and shared plant: EECON49-P4 Eqs.(6)-(19); GFM swing: ' ...
        'PROJECT_DERIVED decoupled droop/damping/inertia (see ' ...
        'docs/project/DECOUPLED_GFM_SOURCE_CONTRACT.md)'];
    classification=['GFL and shared-plant AC/control=SOURCE_MAPPED; GFM swing ' ...
        '(R_droop/D_t/wD)=PROJECT_DERIVED from measured K; base/reference=CASE_DEFINED; ' ...
        'DC-source regulator and transfer=PROJECT_DERIVED'];
    details=sprintf(['17-state shared-plant superset; GFL controller owns PLL; ' ...
        'GFM controller owns the decoupled VSG (no PLL) with washout state ' ...
        'omega_f last; Mbase=%.0f MVA; default Q=%.9g MVAr; Tdc=0.10 s; ' ...
        'R_droop=0.05, D_t=0.0, wD=50.0, M=0.08'],Mbase,default_Q_MVAr);
else
    source='WECC REGC_A/REEC_A (2014) GFL + REGFM_B1 NREL/TP-5D00-90260 G2 GFM';
    classification='Mbase and initial Q dispatch=CASE_DEFINED; controller defaults=SOURCE_DEFINED/SOURCE_MAPPED';
    details=sprintf(['20-state superset (GFM13+GFL7); Mbase=%.0f MVA; ' ...
        'default Q=%.9g MVAr; kappa=Sbase/Mbase at boundary'],Mbase,default_Q_MVAr);
end
r.provenance = struct( ...
    'model',model_id,'source',source,'classification',classification,'details',details);
end

function q_MVAr = case_ibr_q_dispatch_MVAr(case_data,bus_ids)
%CASE_IBR_Q_DISPATCH_MVAR  Map case-defined PQ injections by external bus ID.
%   bus_data(:,6) is pu on the case's 100-MVA system base.  Reject missing,
%   duplicate, or nonfinite mappings rather than falling back to unity PF.
Sbase = 100.0;
q_MVAr = nan(size(bus_ids));
for k = 1:numel(bus_ids)
    row = find(case_data.bus_data(:,1)==bus_ids(k));
    if numel(row)~=1 || ~isfinite(case_data.bus_data(row,6))
        error('cases:scenario_ieee14_1sg_4ibr:badReactiveDispatch', ...
            'IBR bus %d lacks one finite case-defined Q dispatch.',bus_ids(k));
    end
    q_MVAr(k) = Sbase*case_data.bus_data(row,6);
end
end
