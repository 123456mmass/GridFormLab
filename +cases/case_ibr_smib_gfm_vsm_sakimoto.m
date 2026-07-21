function case_data = case_ibr_smib_gfm_vsm_sakimoto()
%CASE_IBR_SMIB_GFM_VSM_SAKIMOTO  GFM VSM Sakimoto (no-PLL/no-AVR/no-PSS)
%   single-infinite-bus verification case.
%
%   Source-frozen diagnostic fixture (schema smib_verification/1.0), separate
%   from the 4-state gfm_no_pll case. The 9-state Sakimoto current-controlled
%   VSG (ibr.gfm_vsm_sakimoto_model) is connected to an ideal algebraic
%   infinite bus through Z_line and evaluated by the project-owned SMIB
%   equilibrium, SSSA, and TDS oracles (ibr.smib_sssa_oracle / smib_tds_oracle),
%   which are generic over dev.nx.
%
%   omega_b/60 Hz matches Sakimoto Fig.6 "377/s" (no 50->60 Hz remap).
case_data = struct();
case_data.schema_version = 'smib_verification/1.0';
case_data.system_name = 'GFM-VSM-Sakimoto (no PLL/AVR/PSS) - Single Infinite Bus Verification';
case_data.source = ['Source-frozen diagnostic fixture used by ', ...
    'ibr.smib_sssa_oracle and ibr.smib_tds_oracle; device ', ...
    'ibr.gfm_vsm_sakimoto_model (Sakimoto 2015)'];
case_data.base_values = struct('S_base_MVA',100.0,'frequency_Hz',60.0);
case_data.smib_verification = struct( ...
    'kind','gfm_vsm_sakimoto', 'device_type','ibr_gfm_vsm_sakimoto', ...
    'device_id','GFM_VSM_SAKIMOTO', ...
    'V_terminal',1.0+0i, 'P_terminal_pu',0.40, ...
    'Q_terminal_pu',0.10, 'Z_line_pu',0.02+0.20i, ...
    'classification','ASSUMED_DIAGNOSTIC_SOURCE_FROZEN_FIXTURE', ...
    'events_supported',false);
end
