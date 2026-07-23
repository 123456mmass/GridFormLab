function case_data = case_ibr_padiyar_switch()
%CASE_IBR_PADIYAR_SWITCH  Padiyar two-area network with 1 SG (bus 11) and 3
%   switchable GFL/GFM IBRs (buses 1,2,12); AGSI++ index-driven GFL<->GFM mode
%   switching on an SG trip and synchronized reclose (reference handback).
%
%   Fresh study fixture (schema padiyar_switch/1.0). The SG uses the Padiyar
%   model-1.1(+AVR) dynamics (ibr.padiyar_sg_unit, reusing the audited
%   stability.padiyar_model11_dae network/parameters); the IBRs use
%   ibr.SwitchableIbr6 with the AGSI++ switching equation (EECON49-P4 guideline).
%   Classification: ASSUMED_DIAGNOSTIC study fixture; project code only.
%
%   Scenario defaults in padiyar_switch can be overridden through solve_case
%   options: padiyar_index_mode, padiyar_sg_trip_time, padiyar_sg_reclose_time,
%   t_end, dt.
case_data = struct();
case_data.schema_version = 'padiyar_switch/1.0';
case_data.system_name = ['Padiyar two-area: 1 SG (bus 11) + 3 GFL IBRs ', ...
    '(buses 1,2,12), AGSI++ GFL<->GFM mode switch'];
case_data.source = ['Padiyar 2nd ed. Sec. 9.6.1 network + model 1.1/AVR SG ', ...
    '(via stability.padiyar_model11_dae / ibr.padiyar_sg_unit); IBRs = ', ...
    'ibr.SwitchableIbr6 (AGSI++, EECON49-P4 guideline).'];
case_data.base_values = struct('S_base_MVA',100,'frequency_Hz',60);
case_data.padiyar_switch = struct( ...
    'index_mode','agsi_pp', ...
    'sg_trip_time',1.0, 'sg_reclose_time',4.0, ...
    'T',8.0, 'dt',2e-3, ...
    'classification','ASSUMED_DIAGNOSTIC_PADIYAR_1SG_3GFL_SWITCH');
end
