function r = discover_cases(analysis_id)
%DISCOVER_CASES  Lazy enumeration of case entries for an analysis.
%   r = wizard.discover_cases(analysis_id) returns a struct array of case
%   entries compatible with the requested analysis. This is PURE and LAZY
%   (correction #8): it calls the catalog functions and attaches loaders as
%   function handles, but it does NOT execute PF/equilibrium, load solved
%   states, or invoke any solver merely to populate the case-selection page.
%
%   Mirrors the case_registry(analysis) logic in solve_case.m:227-242:
%     - pf/sssa/ts: cases.network_case_catalog() (14 generic entries)
%     - sssa additionally: 'sauer_pai' (Sauer-Pai Example 8.3)
%     - ibr: 'ieee14_1sg_4ibr' (Kodsi SG1 + dual-mode IBRs)
%
%   Each entry has:
%     id          - stable case ID (char, lowercased)
%     label       - human-readable display name (char)
%     loader      - zero-arg function handle returning power_case/1.0
%                   (or the IBR scenario for 'ibr')
%     options     - case-defined default options struct for this analysis
%     analysis    - the analysis this entry was discovered for
%     schema      - expected schema version (filled lazily by caller if needed;
%                   left empty here to avoid loading the case)
%
%   Compatibility: an entry is included only if its option field (or IBR
%   specialization) is compatible with the analysis. Fail closed for duplicate
%   IDs, malformed entries, or missing required fields.
%
%   See also: wizard.ANALYSIS_REGISTRY, cases.network_case_catalog.

analysis_id = lower(char(analysis_id));
registry = wizard.analysis_registry();
idx = find(strcmp(analysis_id, {registry.id}), 1);
if isempty(idx)
    % Preserve the original solve_case error identifier (characterization gate).
    error('solve_case:analysis', 'Unknown analysis %s.', analysis_id);
end
entry = registry(idx);
option_field = entry.option_field;

switch analysis_id
    case 'pf'
        catalog = cases.network_case_catalog();
        r = items_from_catalog(catalog, 'pf_options', analysis_id);
    case 'sssa'
        catalog = cases.network_case_catalog();
        r = items_from_catalog(catalog, 'sssa_options', analysis_id);
        r(end+1,1) = item('sauer_pai', 'Sauer-Pai Example 8.3', ...
            @cases.sauer_pai_ex83_case, struct(), analysis_id); %#ok<AGROW>
    case 'ts'
        catalog = cases.network_case_catalog();
        r = items_from_catalog(catalog, 'ts_options', analysis_id);
    case 'ibr'
        r = item('ieee14_1sg_4ibr', ...
            'IEEE14 1-SG + 4-IBR (Kodsi SG1 + dual-mode IBRs)', ...
            @cases.case_ieee14_1sg_4ibr_auto_vsg, wizard.defaults_for_method('ibr'), ...
            analysis_id);
        smib_opt = struct('ibr_analysis','full', ...
            't_end',0.05,'dt',1e-3,'verbose',true, ...
            'plot_results',true,'plot_visible',true, ...
            'ibr_events',struct('enabled',false), ...
            'smib_fault_on',0.0,'smib_fault_clear',0.0,'smib_fault_Zf',1i*0.1, ...
            'smib_step_on',0.0,'smib_step_dV',-0.10,'smib_step_dphase_deg',20.0);
        r(end+1,1) = item('gfl_rms10_smib', ...
            'GFL-RMS10 - Single Infinite Bus Verification', ...
            @cases.case_ibr_smib_gfl_rms10, smib_opt, analysis_id);
        r(end+1,1) = item('gfm_no_pll_smib', ...
            'GFM-VSG No-PLL - Single Infinite Bus Verification', ...
            @cases.case_ibr_smib_gfm_no_pll, smib_opt, analysis_id);
        % Sakimoto 9-state VSG (no PLL/AVR/PSS): slow ~1.9 Hz electromechanical
        % swing, so a longer TDS horizon is used by default to show it settle.
        sakimoto_opt = smib_opt; sakimoto_opt.t_end = 2.0;
        r(end+1,1) = item('gfm_vsm_sakimoto_smib', ...
            'GFM-VSM Sakimoto (no PLL/AVR/PSS) - Single Infinite Bus Verification', ...
            @cases.case_ibr_smib_gfm_vsm_sakimoto, sakimoto_opt, analysis_id);
        % Reduced 6-state EECON49 models (2 states per block). GFL: PLL complex
        % mode ~0.34 Hz; GFM: electromechanical swing ~10.8 Hz (low inertia).
        red6_opt = smib_opt; red6_opt.t_end = 2.0;
        r(end+1,1) = item('gfl_reduced6_smib', ...
            'GFL 6-state (reduced, EECON49) - Single Infinite Bus Verification', ...
            @cases.case_ibr_smib_gfl_reduced6, red6_opt, analysis_id);
        r(end+1,1) = item('gfm_reduced6_smib', ...
            'GFM 6-state (reduced VSG, EECON49) - Single Infinite Bus Verification', ...
            @cases.case_ibr_smib_gfm_reduced6, red6_opt, analysis_id);
        % Loaded-IBR cases (smib_loaded_ibr/1.0): single GFL/GFM to infinite
        % bus with a shunt load swept at constant power factor. The default
        % IBR product for these is the load sweep; the load sweep is also
        % available for IEEE14 mixed under analysis='ibr'.
        loaded_opt = smib_opt;
        loaded_opt.ibr_analysis = 'sssa_load_sweep';
        loaded_opt.sssa_load_sweep_enabled = true;
        loaded_opt.sssa_load_percentages = [0 20 40 60 80];
        loaded_opt.sssa_load_scaling_policy = 'constant_power_factor';
        loaded_opt.sssa_mode_tracking = true;
        loaded_opt.sssa_save_plots = true;
        loaded_opt.sssa_plot_visible = true;
        r(end+1,1) = item('gfl_rms10_loaded_smib', ...
            'GFL-RMS10 Loaded SMIB (single converter, load sweep)', ...
            @cases.case_ibr_smib_loaded_gfl_rms10, loaded_opt, analysis_id);
        r(end+1,1) = item('gfm_no_pll_loaded_smib', ...
            'GFM-VSG No-PLL Loaded SMIB (single converter, load sweep)', ...
            @cases.case_ibr_smib_loaded_gfm_no_pll, loaded_opt, analysis_id);
        % Two-IBR AGSI GFL<->GFM mode switch (common PCC, infinite bus). Fresh
        % reduced-6 study: the switching decision uses the EECON49-P4 AGSI
        % equation vs Gamma_on/Gamma_off (see ibr.SwitchableIbr6). Event-free
        % w.r.t. the wizard event system (ibr_events disabled) -- the weak-grid
        % disturbance is a self-contained scenario configured by two_ibr_* opts.
        switch_opt = struct('ibr_analysis','full', ...
            't_end',8.0,'dt',1e-3,'verbose',true, ...
            'plot_results',true,'plot_visible',true, ...
            'ibr_events',struct('enabled',false), ...
            'two_ibr_P_ref',0.20,'two_ibr_Q_ref',0.0, ...
            'two_ibr_V_inf',1.0,'two_ibr_Z_line',0.30i, ...
            'two_ibr_AGSI_up',0.65,'two_ibr_AGSI_down',0.35, ...
            'two_ibr_event_time',1.5,'two_ibr_recover_time',4.0, ...
            'two_ibr_Zline_factor',4.0, ...
            'two_ibr_step_dphase_deg',0.0,'two_ibr_step_dV',0.0, ...
            'two_ibr_step_ramp',0.40);
        r(end+1,1) = item('two_ibr_switch', ...
            'Two GFL IBRs - AGSI GFL<->GFM mode switch (infinite bus)', ...
            @cases.case_ibr_two_ibr_switch, switch_opt, analysis_id);
        % Padiyar two-area, 1 SG (bus 11) + 3 GFL IBRs (buses 1,2,12): AGSI++
        % index-driven GFL<->GFM switch on an SG trip and synchronized reclose.
        padiyar_opt = struct('ibr_analysis','full', ...
            't_end',8.0,'dt',2e-3,'verbose',true, ...
            'plot_results',true,'plot_visible',false, ...
            'ibr_events',struct('enabled',false), ...
            'padiyar_index_mode','agsi_pp', ...
            'padiyar_sg_trip_time',1.0,'padiyar_sg_reclose_time',4.0);
        r(end+1,1) = item('padiyar_switch', ...
            'Padiyar two-area: 1 SG + 3 GFL IBRs - AGSI++ GFL<->GFM switch (SG trip/reclose)', ...
            @cases.case_ibr_padiyar_switch, padiyar_opt, analysis_id);
    otherwise
        error('wizard:discover_cases:unknownAnalysis', ...
            'Unknown analysis ID %s.', analysis_id);
end

% Fail closed on duplicate IDs.
ids = {r.id};
[~,~,ic] = unique(ids);
if numel(unique(ic)) ~= numel(ids)
    error('wizard:discover_cases:duplicateId', ...
        'Duplicate case IDs discovered for analysis %s.', analysis_id);
end
end

function r = items_from_catalog(catalog, option_field, analysis_id)
r = repmat(item('','','',struct(),analysis_id), 0, 1);
for k = 1:numel(catalog)
    e = catalog(k);
    if ~isfield(e, option_field)
        continue;  % entry has no options for this analysis -> skip
    end
    r(end+1,1) = item(lower(char(e.id)), char(e.label), e.loader, ...
        e.(option_field), analysis_id); %#ok<AGROW>
end
end

function s = item(id, label, loader, options, analysis_id)
if nargin < 5, analysis_id = ''; end
if nargin < 4, options = struct(); end
s = struct('id', id, 'label', label, 'loader', loader, ...
    'options', options, 'analysis', analysis_id, 'schema', '');
end
