function case_data = case_ieee14bus_eecon49_switch()
%CASE_IEEE14BUS_EECON49_SWITCH  IEEE14 operating case mapped from EECON49 Fig. 4.
%
% SOURCE_DEFINED:
%   - network, loads, voltage base and frequency: cases.case_ieee14bus;
%   - SG at bus 1; IBRs at buses 2,3,6,8;
%   - apparent powers printed in Fig. 4:
%       SG1=134.62 MVA, IBR=[36.31 33.02 50.86 30.64] MVA.
%   - GFL IBRs are PQ resources (not PV voltage controllers).
%
% PROJECT_DERIVED_FIGURE_MATCH:
%   The paper does not publish the separate P/Q dispatch values.  A common
%   positive reactive-power angle phi=0.500345721564827 rad is the positive-Q
%   root for which the in-house PF simultaneously preserves the four printed
%   IBR apparent powers and gives |S_SG1|=134.62 MVA.  The negative-Q root is
%   rejected because the paper describes IBR voltage/reactive support and the
%   original IEEE14 slack absorbs reactive power.  This is an explicit mapping
%   assumption, not a claim that the unpublished source P/Q values are known.
%
% No PF solution is loaded: bus P/Q inputs are frozen below and the project
% Newton-Raphson solver computes all voltages, angles and slack outputs.

case_data = cases.case_ieee14bus();
ibr_buses = [2 3 6 8];
S_ibr_pu = [0.3631 0.3302 0.5086 0.3064];
phi = 0.500345721564827;
P_ibr_pu = S_ibr_pu*cos(phi);
Q_ibr_pu = S_ibr_pu*sin(phi);

ids = case_data.bus_data(:,1);
for k = 1:numel(ibr_buses)
    j = find(ids==ibr_buses(k),1);
    case_data.bus_data(j,2) = 3;       % GFL PQ resource
    case_data.bus_data(j,3) = 1.0;     % flat-start only; solved output
    case_data.bus_data(j,4) = 0.0;
    case_data.bus_data(j,5) = P_ibr_pu(k);
    case_data.bus_data(j,6) = Q_ibr_pu(k);
end

case_data.system_name = 'IEEE 14-Bus EECON49 Figure-4 Switching Case';
case_data.reference_solution = struct(); % baseline MATPOWER solution no longer applies
case_data.eecon49_mapping = struct( ...
    'classification','PROJECT_DERIVED_FIGURE_MATCH', ...
    'source_file','docs/text/EECON49_[Nui].pdf, Figure 4', ...
    'sg_bus',1,'ibr_buses',ibr_buses, ...
    'S_ibr_pu',S_ibr_pu,'S_sg_target_pu',1.3462, ...
    'common_power_angle_rad',phi,'common_power_factor',cos(phi), ...
    'P_ibr_pu',P_ibr_pu,'Q_ibr_pu',Q_ibr_pu);

% EMF6 SG data for the dynamic EECON49 route.  The paper specifies a
% sixth-order SG but does not print its reactance/time-constant table; the
% project therefore reuses the audited IEEE14/Kodsi machine coefficients and
% converts the published H=2.5 s, D=1.0 pu system-base values to the 615-MVA
% machine base used by that source table.  This is explicitly
% PROJECT_DERIVED_SOURCE_MAPPED, not a claim that the omitted paper table is
% known.
scale = 615/100;
% Tpq0=0 is the Kodsi singular limit; this mixed DAE uses the well-posed
% 6-state operational route, so retain the audited 0.033-s q-axis transient
% constant used by the existing Padiyar adapter.
case_data.machines = struct( ...
    'model','emf6', ...
    'base',struct('S_MVA',615,'V_kV',0,'f_Hz',60), ...
    'reactances',struct('Xl',0.2396,'Ra',0.0, ...
        'Xd',0.8979,'Xdp',0.2995,'Xdpp',0.23, ...
        'Xq',0.646,'Xqp',0.646,'Xqpp',0.4), ...
    'time_constants',struct('Tpd0',7.4,'Tppd0',0.03, ...
        'Tpq0',0.033,'Tppq0',0.033), ...
    'exciter',struct('model','constant_field','KA',0,'TA',1), ...
    'units',struct('gen_id','SG1','bus',1,'H',2.5*scale,'D',1.0*scale));
case_data.eecon49_mapping.sg_model = 'Kundur/GENTPJ EMF6; H=2.5 s, D=1.0 pu on 100-MVA system base; coefficients mapped from audited Kodsi table';
case_data.eecon49_mapping.sg_model_classification = 'PROJECT_DERIVED_SOURCE_MAPPED';
case_data.switching_event_contract = struct( ...
    'classification','CASE_DEFINED_FROM_EVENT_SEQUENCE_FIGURE', ...
    'T_end',160.0, ...
    'sg_trip_time',20.0, ...
    'step_on',50.0,'step_factor',0.20,'step_all_loads',true, ...
    'fault_on',85.0,'fault_clear',85.15,'fault_bus',9, ...
    'fault_Zf',0.01+0.01i, ...
    'line_trip_time',110.0,'line_from_bus',6,'line_to_bus',13, ...
    'restore_time',145.0, ...
    'restore_sg',true,'restore_line',true,'restore_base_loads',true);
end
