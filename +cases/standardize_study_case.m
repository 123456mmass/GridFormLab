function c = standardize_study_case(c, kind)
%STANDARDIZE_STUDY_CASE Contract for non-bus-branch study/benchmark cases.
% This deliberately does not fabricate a MATPOWER network.

arguments
    c struct
    kind (1,:) char
end
allowed={'economic_dispatch','smib','dynamic_benchmark'};
if ~any(strcmp(kind,allowed))
    error('standardize_study_case:kind','Unknown case kind %s.',kind);
end
if ~isfield(c,'system_name') || isempty(c.system_name)
    if isfield(c,'name'), c.system_name=c.name;
    else, c.system_name='Unnamed study case'; end
end
if ~isfield(c,'name') || isempty(c.name), c.name=c.system_name; end
c.case_kind=kind;
c.schema_version='study_case/1.0';
c.formats.canonical=kind;
c.formats.human_readable='MATLAB tables';
if ~isfield(c,'reference') && ~isfield(c,'source')
    c.source='Project-generated or source recorded by the owning loader';
end

t=struct();
switch kind
    case 'economic_dispatch'
        d=c.opf_data; n=numel(d.generator_ids);
        t.generator=table(d.generator_ids(:),d.cost(:,1),d.cost(:,2),d.cost(:,3), ...
            d.P_min_MW(:),d.P_max_MW(:),'VariableNames', ...
            {'Generator','Cost_a','Cost_b','Cost_c','Pmin_MW','Pmax_MW'});
        t.demand=table(d.P_demand_MW,'VariableNames',{'Demand_MW'});
    case 'smib'
        names={'base_values','machine','network','operating','k_constants','exciter','pss'};
        for k=1:numel(names)
            name=names{k};
            if isfield(c,name) && isstruct(c.(name)) && isscalar(c.(name))
                try, t.(name)=struct2table(c.(name),'AsArray',true); catch, end
            end
        end
    case 'dynamic_benchmark'
        if isfield(c,'V') && isfield(c,'theta')
            nb=numel(c.V); role=repmat("PQ",nb,1);
            role(c.gen_buses)="GEN";
            t.bus=table((1:nb)',categorical(role),c.V(:),c.theta(:), ...
                'VariableNames',{'Bus','Role','V_pu','Theta_rad'});
        end
        if all(isfield(c,{'gen_buses','H','D'}))
            ng=numel(c.gen_buses);
            t.generator=table(c.gen_buses(:),c.H(:),c.D(:), ...
                'VariableNames',{'Bus','H_s','D_pu'});
            fields={'Xd','Xdp','Xq','Xqp','Tdo','Tqo'};
            for j=1:numel(fields)
                if isfield(c,fields{j}) && numel(c.(fields{j}))==ng
                    t.generator.(fields{j})=c.(fields{j})(:);
                end
            end
        end
        if isfield(c,'raw')
            if isfield(c.raw,'buses'), t.raw_bus=struct2table(c.raw.buses); end
            if isfield(c.raw,'loads'), t.raw_load=struct2table(c.raw.loads); end
        end
        if isfield(c,'dyn') && isfield(c.dyn,'generators')
            t.dynamic_generator=struct2table(c.dyn.generators);
        end
end
c.tables=t;
end
