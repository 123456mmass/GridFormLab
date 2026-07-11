function case_data = case_padiyar_two_area_4m_avr()
%CASE_PADIYAR_TWO_AREA_4M_AVR Padiyar 4-machine, 10-bus two-area case.
%   Primary source: K. R. Padiyar, Power System Dynamics: Stability and
%   Control, 2nd ed., Chapter 9, Section 9.6.1, Tables 9.1--9.4.
%   PDF pages 339--341 (printed pages 326--328).
%
%   Dynamic model: Padiyar model 1.1 (two-axis transient machine) with a
%   single-time-constant AVR. Five states per generator:
%       [delta, omega, E'q, E'd, Efd]
%
%   This is not a sixth-order/subtransient model. No X'' or T'' values are
%   inferred. Table 9.5 is stored only as a secondary published cross-check.

case_data = struct();
case_data.schema_version = 'power_case/1.0';
case_data.system_name = 'Padiyar two-area 4-machine model 1.1 with AVR';
% The source system lineage cited by Padiyar (references 15 and 17) is a
% 60-Hz benchmark. Frequency is fixed here as input provenance; Table 9.5
% eigenvalues are not consulted by the DAE or SSSA computation.
case_data.base_values = struct('S_base_MVA',100,'V_base_kV',1,'frequency_Hz',60);

% [bus type V angle Pg Qg Pl Ql Gsh Bsh Qmin Qmax]
% Internal project bus types: 1=REF, 2=PV, 3=PQ. Bus 11 is the printed
% angle reference and therefore the PF slack. Printed angles are supplied
% as initial values only; the in-house PF recomputes the operating point.
%
% PHYSICAL INPUT (source of truth for the PF solver): bus_data columns
% 3 (Vmag), 4 (angleDeg), 5 (Pgen), 6 (Qgen) are read by pf_prepare_case.
% The operating_point.printed_* fields below are COMPARISON COPIES of
% Padiyar Table 9.2 and must NOT influence solver output. Corrupting them
% must leave the PF result unchanged (see test_pf_reference_independence).
case_data.bus_data = [ ...
    1   2  1.0300    8.2154  7.0000  0  0     0     0  0  -Inf Inf;
    2   2  1.0100   -1.5040  7.0000  0  0     0     0  0  -Inf Inf;
    11  1  1.0300    0.0000  0       0  0     0     0  0  -Inf Inf;
    12  2  1.0100  -10.2051  7.0000  0  0     0     0  0  -Inf Inf;
    101 3  1.0108    3.6615  0       0  0     0     0  0  -Inf Inf;
    102 3  0.9875   -6.2433  0       0  0     0     0  0  -Inf Inf;
    111 3  1.0095   -4.6977  0       0  0     0     0  0  -Inf Inf;
    112 3  0.9850  -14.9443  0       0  0     0     0  0  -Inf Inf;
    3   3  0.9761  -14.4194  0       0  11.59 2.12  0  3  -Inf Inf;
    13  3  0.9716  -23.2922  0       0  15.75 2.88  0  4  -Inf Inf];

% [from to R X B_half tap phase_shift_deg]
% Table 9.1 labels B as line shunt susceptance. It is represented by the
% standard pi model as B/2 at each end; hence the stored B_half=B/2.
case_data.line_data = [ ...
    1   101  0.001  0.012  0       1 0;
    2   102  0.001  0.012  0       1 0;
    3   13   0.022  0.220  0.165   1 0;
    3   13   0.022  0.220  0.165   1 0;
    3   13   0.022  0.220  0.165   1 0;
    3   102  0.002  0.020  0.015   1 0;
    3   102  0.002  0.020  0.015   1 0;
    11  111  0.001  0.012  0       1 0;
    12  112  0.001  0.012  0       1 0;
    13  112  0.002  0.020  0.015   1 0;
    13  112  0.002  0.020  0.015   1 0;
    101 102  0.005  0.050  0.0375  1 0;
    101 102  0.005  0.050  0.0375  1 0;
    111 112  0.005  0.050  0.0375  1 0;
    111 112  0.005  0.050  0.0375  1 0];

% Parameters are printed on the 100-MVA system base.
units = repmat(struct('gen_id','','bus',0,'H',0,'D',0),4,1);
units(1)=struct('gen_id','G1','bus',1, 'H',54,'D',0);
units(2)=struct('gen_id','G2','bus',2, 'H',54,'D',0);
units(3)=struct('gen_id','G3','bus',11,'H',63,'D',0);
units(4)=struct('gen_id','G4','bus',12,'H',63,'D',0);
case_data.machines = struct( ...
    'model','padiyar_1_1_avr', ...
    'base',struct('S_MVA',100,'V_kV',1,'f_Hz',60), ...
    'reactances',struct('Xl',0.022,'Ra',0.00028, ...
        'Xd',0.2,'Xdp',0.033,'Xq',0.19,'Xqp',0.061), ...
    'time_constants',struct('Tpd0',8.0,'Tpq0',0.4), ...
    'exciter',struct('model','single_time_constant_avr','KA',200,'TA',0.02), ...
    'units',units);

% operating_point.printed_* : COMPARISON COPIES of Padiyar Table 9.2
% (published operating point). These are NOT physical inputs. The PF
% solver reads only bus_data(:,3:6). Corrupting printed_* must not change
% PF results (see tests/test_pf_reference_independence.m).
case_data.operating_point = struct( ...
    'load_model','cz_p_cz_q', ...
    'constant_mechanical_power',true, ...
    'printed_bus_ids',[1;2;11;12;101;102;111;112;3;13], ...
    'printed_V',[1.03;1.01;1.03;1.01;1.0108;0.9875;1.0095;0.9850;0.9761;0.9716], ...
    'printed_angle_deg',[8.2154;-1.5040;0;-10.2051;3.6615;-6.2433;-4.6977;-14.9443;-14.4194;-23.2922], ...
    'printed_Pg',[7;7;7.2172;7;0;0;0;0;0;0], ...
    'printed_Qg',[1.3386;1.5920;1.4466;1.8083;0;0;0;0;0;0]);

case_data.reference = struct();
case_data.reference.source = 'Padiyar 2nd ed., Sec. 9.6.1, Tables 9.1--9.5';
case_data.reference.pdf_pages = 338:344;
case_data.reference.printed_pages = 325:331;
case_data.reference.table95_eigenvalues = [ ...
    -39.9893; -39.4922; ...
    -24.5058+1i*20.6749; -24.5058-1i*20.6749; ...
    -25.0383+1i*11.9973; -25.0383-1i*11.9973; ...
    -11.5835; -11.1735; ...
    -0.7594+1i*7.2938; -0.7594-1i*7.2938; ...
    -0.7365+1i*6.6899; -0.7365-1i*6.6899; ...
    -0.0044+1i*4.4444; -0.0044-1i*4.4444; ...
    -4.5727; -4.4802; -4.1121; 0+1i*0.0017; 0-1i*0.0017; -4.2449];

case_data = cases.standardize_case(case_data);
end
