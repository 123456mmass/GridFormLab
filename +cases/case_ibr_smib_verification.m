function case_data = case_ibr_smib_verification(kind)
%CASE_IBR_SMIB_VERIFICATION  Source-frozen one-converter/infinite-bus case.
%   This is a diagnostic verification case, not a power_case network used by
%   the production Newton PF.  The selected converter is connected to an
%   ideal algebraic infinite bus through Z_line and is evaluated by the
%   project-owned SMIB equilibrium, SSSA, and TDS oracles.

kind = lower(char(kind));
switch kind
    case 'gfl_rms10'
        label = 'GFL-RMS10 - Single Infinite Bus Verification';
        frequency = 60.0;
        device_type = 'ibr_gfl_rms10';
    case 'gfm_no_pll'
        label = 'GFM-VSG No-PLL - Single Infinite Bus Verification';
        frequency = 50.0;
        device_type = 'ibr_gfm_vsg_no_pll';
    otherwise
        error('cases:case_ibr_smib_verification:unknownKind', ...
            'Unknown SMIB verification kind %s.', kind);
end

case_data = struct();
case_data.schema_version = 'smib_verification/1.0';
case_data.system_name = label;
case_data.source = ['Source-frozen diagnostic fixture used by ', ...
    'ibr.smib_sssa_oracle and ibr.smib_tds_oracle'];
case_data.base_values = struct('S_base_MVA',100.0, ...
    'frequency_Hz',frequency);
case_data.smib_verification = struct( ...
    'kind',kind, 'device_type',device_type, 'device_id',upper(kind), ...
    'V_terminal',1.0+0i, 'P_terminal_pu',0.40, ...
    'Q_terminal_pu',0.10, 'Z_line_pu',0.02+0.20i, ...
    'classification','ASSUMED_DIAGNOSTIC_SOURCE_FROZEN_FIXTURE', ...
    'events_supported',false);
end
