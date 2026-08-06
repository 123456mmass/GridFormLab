function lim = pf_limit_table(c)
%PF_LIMIT_TABLE Per-bus reactive and active limits for the PF report table.
%   Q_min/Q_max come from the 12-column bus_data contract (cols 11/12,
%   SOURCE_DEFINED from mpc.gen Qmax/Qmin MVAr divided by the system base).
%   P_max comes from mpc.gen column 9 (Pmax MW) divided by the same base.
%   Buses with no generator keep NaN so the table can print a dash.
nb = size(c.bus_data,1);
ids = c.bus_data(:,1);
base = c.base_values.S_base_MVA;
Qmin_pu = c.bus_data(:,11);
Qmax_pu = c.bus_data(:,12);
Qmin_pu(~isfinite(Qmin_pu)) = NaN;
Qmax_pu(~isfinite(Qmax_pu)) = NaN;
Pmax_pu = NaN(nb,1);
for k = 1:size(c.mpc.gen,1)
    j = find(ids==c.mpc.gen(k,1),1);
    if ~isempty(j), Pmax_pu(j) = c.mpc.gen(k,9)/base; end
end
lim = table(ids,Qmin_pu,Qmax_pu,Pmax_pu, ...
    'VariableNames',{'bus','Qmin_pu','Qmax_pu','Pmax_pu'});
end
