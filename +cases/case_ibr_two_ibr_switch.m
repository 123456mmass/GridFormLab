function case_data = case_ibr_two_ibr_switch()
%CASE_IBR_TWO_IBR_SWITCH  Two GFL IBRs on a common PCC behind one line to an
%   infinite bus, with an AGSI-based GFL<->GFM mode switch (EECON49-P4 guideline).
%
%   Fresh reduced-6 study fixture (schema two_ibr_switch/1.0). Two
%   ibr.SwitchableIbr6 devices (each wrapping ibr.gfl_reduced6_model and
%   ibr.gfm_reduced6_model) share a common PCC; a temporary weak-grid event
%   lifts the AGSI switching equation across Gamma_on so both switch GFL->GFM,
%   and on recovery AGSI falls below Gamma_off so both switch back GFL. The run
%   uses the project-owned two-device implicit-trapezoidal driver
%   ibr.two_ibr_infbus_tds (no external solver, no legacy dual-mode code).
%
%   The two_ibr_switch struct holds the scenario defaults; every field can be
%   overridden through solve_case options with the same name prefixed by
%   'two_ibr_' (e.g. options.two_ibr_step_dphase_deg), plus t_end and dt.
%
%   Classification: ASSUMED_DIAGNOSTIC study/teaching fixture. The AGSI
%   switching equation follows EECON49-P4 as a design guideline (see
%   ibr.SwitchableIbr6); the reduced GFL/GFM branch equations keep their
%   EECON49-P4 provenance.
case_data = struct();
case_data.schema_version = 'two_ibr_switch/1.0';
case_data.system_name = ['Two GFL IBRs - AGSI GFL<->GFM mode switch ', ...
    '(common PCC, infinite bus)'];
case_data.source = ['Fresh reduced-6 study (EECON49-P4 AGSI guideline): two ', ...
    'ibr.SwitchableIbr6 devices at a common PCC behind one line to an infinite ', ...
    'bus; ibr.two_ibr_infbus_tds driver; ibr.solve_pcc_infbus_equilibrium init.'];
case_data.base_values = struct('S_base_MVA',100.0,'frequency_Hz',60.0);
case_data.two_ibr_switch = struct( ...
    'P_ref',0.20, 'Q_ref',0.0, ...            % per-IBR references (system pu)
    'V_inf',1.0, 'Z_line',0.30i, ...           % infinite bus + line to the PCC
    'AGSI_up',0.65, 'AGSI_down',0.35, ...      % Gamma_on / Gamma_off
    'event_time',1.5, 'recover_time',4.0, ...  % temporary weak-grid window [s]
    'Zline_factor',4.0, ...                    % line weakening x during the event
    'step_dphase_deg',0.0, 'step_dV',0.0, ...  % pure weakening (gentle transients)
    'step_ramp',0.40, ...                      % smooth ramp [s] at onset/recovery
    'T',8.0, 'dt',1e-3, ...                     % horizon / step
    'classification','ASSUMED_DIAGNOSTIC_SOURCE_GUIDED_TWO_IBR_SWITCH');
end
