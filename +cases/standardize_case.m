function c = standardize_case(c)
%STANDARDIZE_CASE Enforce the project-wide network case contract.
% Canonical exchange: MATPOWER v2 (.mpc). Human view: .tables.
% Compatibility arrays are fixed-width numeric matrices:
%   bus_data  [bus type Vm Va Pg Qg Pd Qd Gsh Bsh Qmin Qmax] (12 cols)
%   line_data [from to R X Bhalf tap phase_deg]                (7 cols)

if ~isfield(c,'bus_data') || ~isfield(c,'line_data')
    error('standardize_case:notNetworkCase', ...
        'A standard network case requires bus_data and line_data.');
end
if ~isfield(c,'system_name') || isempty(c.system_name)
    c.system_name='Unnamed network case';
end
if ~isfield(c,'base_values') || isempty(c.base_values)
    c.base_values=struct('S_base_MVA',100,'V_base_kV',0,'frequency_Hz',60);
end
if ~isfield(c.base_values,'S_base_MVA'), c.base_values.S_base_MVA=100; end
if ~isfield(c.base_values,'V_base_kV'), c.base_values.V_base_kV=0; end
if ~isfield(c.base_values,'frequency_Hz'), c.base_values.frequency_Hz=60; end

% Fixed-width compatibility matrices.
switch size(c.bus_data,2)
    case 8
        c.bus_data(:,9:10)=0; c.bus_data(:,11)=-Inf; c.bus_data(:,12)=Inf;
    case 10
        c.bus_data(:,11)=-Inf; c.bus_data(:,12)=Inf;
    case 12
    otherwise
        error('standardize_case:busColumns','bus_data must have 8, 10, or 12 columns.');
end
switch size(c.line_data,2)
    case 4
        c.line_data(:,5)=0; c.line_data(:,6)=1; c.line_data(:,7)=0;
    case 5
        c.line_data(:,6)=1; c.line_data(:,7)=0;
    case 6
        c.line_data(:,7)=0;
    case 7
    otherwise
        error('standardize_case:lineColumns','line_data must have 4--7 columns.');
end

if ~isfield(c,'mpc') || isempty(c.mpc)
    c.mpc=legacy_to_mpc(c);
else
    c.mpc=normalize_mpc(c.mpc);
end
c.case_kind='network';
c.schema_version='power_case/1.0';
c.formats.canonical_power_flow='MATPOWER v2';
c.formats.human_readable='MATLAB tables';
c.formats.compatibility={'bus_data','line_data'};
c.columns.bus_data={'bus','internal_type','Vmag_pu','angle_deg','Pgen_pu', ...
    'Qgen_pu','Pload_pu','Qload_pu','Gsh_pu','Bsh_pu','Qmin_pu','Qmax_pu'};
c.columns.line_data={'from','to','R_pu','X_pu','Bhalf_pu','tap','phase_deg'};
c.columns.internal_bus_types=struct('slack_REF',1,'PV',2,'PQ',3);
c.columns.matpower_bus_types=struct('PQ',1,'PV',2,'REF_slack',3,'isolated',4);

% Phase E: parallel human-readable bus-role descriptor.  This is a
% presentation/labelling field ONLY and never feeds the PF equations, so the
% 12-column bus_data numeric contract (and the numeric type in col 2) is
% unchanged.  The GFM/GFL designations distinguish inverter resources from
% plain PV/PQ load/generation buses of the same numeric type.  Options:
% 'REF' | 'PV' | 'PQ' | 'GFM' | 'GFL'.
if ~isfield(c,'bus_role') || isempty(c.bus_role)
    c.bus_role = default_bus_role(c);
end
if numel(c.bus_role) ~= size(c.bus_data,1)
    error('standardize_case:busRoleCount', ...
        'bus_role must have one entry per network bus (%d expected).', ...
        size(c.bus_data,1));
end
c.columns.bus_role = {'REF','PV','PQ','GFM','GFL'};

c.tables=readable_tables(c);
end

function role = default_bus_role(c)
% Derive the default role label from the numeric internal type.  A case that
% describes GFM/GFL resources sets c.bus_role explicitly and overrides these.
nb = size(c.bus_data,1);
role = repmat("PQ",nb,1);
role(c.bus_data(:,2)==1) = "REF";
role(c.bus_data(:,2)==2) = "PV";
end

function m=legacy_to_mpc(c)
S=c.base_values.S_base_MVA; b=c.bus_data; l=c.line_data; nb=size(b,1);
mt=ones(nb,1); mt(b(:,2)==1)=3; mt(b(:,2)==2)=2;
basekv=c.base_values.V_base_kV*ones(nb,1);
if isfield(c,'machines') && isstruct(c.machines) && ...
        isfield(c.machines,'units') && isfield(c.machines,'base')
    for k=1:numel(c.machines.units)
        j=find(b(:,1)==c.machines.units(k).bus,1);
        if ~isempty(j), basekv(j)=c.machines.base.V_kV; end
    end
end
m=struct('version','2','baseMVA',S);
m.bus=[b(:,1),mt,b(:,7)*S,b(:,8)*S,b(:,9)*S,b(:,10)*S, ...
    ones(nb,1),b(:,3),b(:,4),basekv,ones(nb,1),1.1*ones(nb,1),0.9*ones(nb,1)];
gi=find(b(:,2)<=2); ng=numel(gi); m.gen=zeros(ng,21);
m.gen(:,1)=b(gi,1); m.gen(:,2)=b(gi,5)*S; m.gen(:,3)=b(gi,6)*S;
m.gen(:,4)=b(gi,12)*S; m.gen(:,5)=b(gi,11)*S;
m.gen(:,6)=b(gi,3); m.gen(:,7)=S; m.gen(:,8)=1;
m.gen(:,9)=max(m.gen(:,2),0)+10*S; m.gen(:,10)=0;
nl=size(l,1); m.branch=zeros(nl,13);
m.branch(:,1:5)=[l(:,1:4),2*l(:,5)];
m.branch(:,9)=l(:,6); m.branch(abs(m.branch(:,9)-1)<eps,9)=0;
m.branch(:,10)=l(:,7); m.branch(:,11)=1;
m.branch(:,12)=-360; m.branch(:,13)=360;
m.gencost=[];
if isfield(c,'bus_names'), m.bus_name=c.bus_names; else, m.bus_name=compose('Bus %g',b(:,1)); end
m.case_name=c.system_name;
end

function m=normalize_mpc(m)
m.version='2';
if size(m.bus,2)<13, m.bus(:,end+1:13)=0; end
if size(m.gen,2)<21, m.gen(:,end+1:21)=0; end
if size(m.branch,2)<13, m.branch(:,end+1:13)=0; end
if ~isfield(m,'gencost'), m.gencost=[]; end
end

function t=readable_tables(c)
t.bus=array2table(c.bus_data,'VariableNames', ...
    {'Bus','Type','Vm_pu','Va_deg','Pg_pu','Qg_pu','Pd_pu','Qd_pu', ...
     'Gsh_pu','Bsh_pu','Qmin_pu','Qmax_pu'});
tn=repmat("PQ",height(t.bus),1); tn(t.bus.Type==1)="REF"; tn(t.bus.Type==2)="PV";
t.bus.TypeName=categorical(tn,["REF","PV","PQ"]);
t.bus=movevars(t.bus,'TypeName','After','Type');
if isfield(c,'bus_role') && numel(c.bus_role)==height(t.bus)
    t.bus.BusRole=string(c.bus_role);
    t.bus=movevars(t.bus,'BusRole','After','TypeName');
end
t.branch=array2table(c.line_data,'VariableNames', ...
    {'FromBus','ToBus','R_pu','X_pu','Bhalf_pu','Tap','Phase_deg'});
t.matpower_bus=array2table(c.mpc.bus(:,1:13),'VariableNames', ...
    {'BUS_I','BUS_TYPE','PD_MW','QD_MVAr','GS_MW','BS_MVAr','BUS_AREA', ...
     'VM_pu','VA_deg','BASE_KV','ZONE','VMAX_pu','VMIN_pu'});
t.matpower_gen=array2table(c.mpc.gen(:,1:21),'VariableNames', ...
    {'GEN_BUS','PG_MW','QG_MVAr','QMAX_MVAr','QMIN_MVAr','VG_pu', ...
     'MBASE_MVA','GEN_STATUS','PMAX_MW','PMIN_MW','PC1','PC2','QC1MIN', ...
     'QC1MAX','QC2MIN','QC2MAX','RAMP_AGC','RAMP_10','RAMP_30','RAMP_Q','APF'});
t.matpower_branch=array2table(c.mpc.branch(:,1:13),'VariableNames', ...
    {'F_BUS','T_BUS','BR_R_pu','BR_X_pu','BR_B_pu','RATE_A','RATE_B', ...
     'RATE_C','TAP','SHIFT_deg','BR_STATUS','ANGMIN_deg','ANGMAX_deg'});
if isfield(c,'machines') && isstruct(c.machines) && isfield(c.machines,'units')
    u=c.machines.units;
    t.machine=table(string({u.gen_id})',[u.bus]',[u.H]',[u.D]', ...
        'VariableNames',{'Generator','Bus','H_s','D_pu'});
end
end
