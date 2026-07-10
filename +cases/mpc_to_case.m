function case_data = mpc_to_case(mpc, varargin)
%MPC_TO_CASE Convert any MATPOWER mpc struct to the project case format.
%   CASE_DATA = mpc_to_case(MPC) returns a case struct usable by
%   pfsolver.powerflow_newton_raphson and stability.ts_simulate.
%
%   This is the shared converter extracted from case_matpower6_case14 so any
%   MATPOWER case (case9, case14, case30, ...) can be loaded and run by the
%   general TS engine with no engine changes.
%
%   Optional: mpc_to_case(MPC, 'system_name', NAME).

bus = mpc.bus; gen = mpc.gen; br = mpc.branch; base = mpc.baseMVA;
nb = size(bus,1);
Pgen = zeros(nb,1); Qgen = zeros(nb,1);
for k = 1:size(gen,1)
    if gen(k,8) ~= 0
        idx = find(bus(:,1) == gen(k,1), 1);
        Pgen(idx) = Pgen(idx) + gen(k,2)/base;
        Qgen(idx) = Qgen(idx) + gen(k,3)/base;
    end
end
% MATPOWER bus types: 3 slack, 2 PV, 1 PQ. Project: 1 slack, 2 PV, 3 PQ.
type = bus(:,2); proj_type = 3*ones(nb,1); proj_type(type == 3) = 1; proj_type(type == 2) = 2;
V0 = ones(nb,1); V0(proj_type == 1 | proj_type == 2) = bus(proj_type == 1 | proj_type == 2, 8);
A0 = zeros(nb,1);
case_data = struct();
case_data.system_name = 'MATPOWER case';
if nargin > 1
    for k=1:2:numel(varargin)
        if strcmpi(varargin{k},'system_name'), case_data.system_name = varargin{k+1}; end
    end
end
case_data.base_values = struct('S_base_MVA', base, 'V_base_kV', 0, 'frequency_Hz', 60);
case_data.bus_data = [bus(:,1), proj_type, V0, A0, Pgen, Qgen, bus(:,3)/base, bus(:,4)/base, bus(:,5)/base, bus(:,6)/base];
tap = br(:,9); tap(tap == 0) = 1;
case_data.line_data = [br(:,1), br(:,2), br(:,3), br(:,4), br(:,5)/2, tap, br(:,10)];
case_data.generator_buses = gen(gen(:,8)~=0,1);
case_data.bus_names = [];
if isfield(mpc,'bus_name'), case_data.bus_names = mpc.bus_name; end
case_data.mpc = mpc;
case_data = cases.standardize_case(case_data);
end
