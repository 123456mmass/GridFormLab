function case_data = case_ibr_ieee14_switch()
%CASE_IBR_IEEE14_SWITCH  IEEE 14-bus network with 1 SG (bus 1) and 4 switchable
%   GFL/GFM IBRs (buses 2,3,6,8); AGSI++ index-driven GFL<->GFM mode switching on
%   an SG trip and synchronized reclose (reference handback).
%
%   Fresh study fixture (schema ieee14_switch/1.0), using the SAME models as the
%   Padiyar 4-machine study: the SG uses Padiyar model-1.1 dynamics with
%   manual (constant-field, NO AVR) excitation (ibr.padiyar_sg_unit, Kodsi Gen1
%   data base-converted); the IBRs use ibr.SwitchableIbr6 with the AGSI++
%   switching equation. The meshed single-area IEEE14 operating point is
%   small-signal STABLE (unlike the weak two-area Padiyar case), so the study
%   satisfies the "no AVR / no PSS, 1 SG + 4 IBR" constraint and remains stable.
%   Classification: ASSUMED_DIAGNOSTIC study fixture; project code only.
%
%   Scenario defaults in ieee14_switch can be overridden through solve_case
%   options: ieee14_index_mode, ieee14_sg_trip_time, ieee14_sg_reclose_time,
%   t_end, dt.
case_data = struct();
case_data.schema_version = 'ieee14_switch/1.0';
case_data.system_name = ['IEEE 14-bus: 1 SG (bus 1, manual/no-AVR) + 4 GFL IBRs ', ...
    '(buses 2,3,6,8), AGSI++ GFL<->GFM mode switch'];
case_data.source = ['MATPOWER 6.0 case14 network + Kodsi TR 2003-3 Gen1 dynamics ', ...
    '(Padiyar model-1.1 manual via ibr.padiyar_sg_unit); IBRs = ', ...
    'ibr.SwitchableIbr6 (AGSI++, EECON49-P4 guideline).'];
case_data.base_values = struct('S_base_MVA',100,'frequency_Hz',60);
case_data.ieee14_switch = struct( ...
    'index_mode','agsi_pp', ...
    'sg_trip_time',1.0, 'sg_reclose_time',4.0, ...
    'T',10.0, 'dt',2e-3, ...
    'classification','ASSUMED_DIAGNOSTIC_IEEE14_1SG_4IBR_SWITCH');
end
