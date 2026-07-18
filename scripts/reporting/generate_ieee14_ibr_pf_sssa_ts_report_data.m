function manifest = generate_ieee14_ibr_pf_sssa_ts_report_data()
%GENERATE_IEEE14_IBR_PF_SSSA_TS_REPORT_DATA  Reproducible report evidence.
%   Runs the project-owned mixed-resource PF/equilibrium/SSSA/TS routes and
%   exports numerical results to CSV for native LaTeX/pgfplots rendering.
%   This script does not alter production equations, solver settings, event
%   data, or results.  It deliberately does not run the "Full Analysis"
%   orchestration product.

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
out = fullfile(root,'docs','source','figures','ieee14_ibr_pf_sssa_ts');
if ~isfolder(out), mkdir(out); end

case_data = cases.case_ieee14_1sg_4ibr_auto_vsg();
base_opt = struct('ibr_profile','rms10_profile_b', ...
    'initial_gfm_count',1,'initial_gfl_count',3, ...
    'initial_gfm_indices',2,'initial_reference_resource_index',2, ...
    'plot_results',false,'plot_visible',false,'verbose',false,'pf_verbose',false);

% Independent normal-operation products (no Full Analysis shortcut).
pf = run_product('pf',base_opt,struct('enabled',false));
sssa = run_product('sssa',base_opt,struct('enabled',false));
pf_cmp = run_product('pf_compare',base_opt,struct('enabled',false));
sssa_cmp = run_product('sssa_compare',base_opt,struct('enabled',false));
assert(pf.converged && sssa.converged && pf_cmp.converged && sssa_cmp.converged, ...
    'report:ieee14_ibr:stationaryProduct','A stationary report product failed closed.');

% Fault-only TS: balanced positive-sequence fault, no SG trip transaction.
fault_event = struct('enabled',true,'event_profile','fault_only', ...
    'fault_bus',4,'Zf',1i*0.1,'fault_on',0.10,'fault_clear',0.20, ...
    'sg_trip',0.25,'sg_on',0.28);
fault_opt = merge(base_opt,struct('t_end',0.30,'dt',0.01,'plot_results',true));
fault = run_product('ts',fault_opt,fault_event);

% SG-cycle TS: no fault; automatic selector owns the post-trip GFM set.
sg_event = struct('enabled',true,'event_profile','sg_cycle', ...
    'fault_bus',4,'Zf',1i*0.1,'fault_on',0.05,'fault_clear',0.08, ...
    'sg_trip',0.10,'sg_on',0.20,'automatic_gfm_switching',true, ...
    'selected_gfm_indices',[],'reference_resource_index',[]);
sg_opt = merge(base_opt,struct('t_end',0.30,'dt',0.01, ...
    'plot_results',true,'automatic_gfm_switching',true));
sg_cycle = run_product('ts',sg_opt,sg_event);

% Checkpoint the exact production outputs before presentation-only export.
save(fullfile(out,'raw_report_products.mat'),'pf','sssa','pf_cmp','sssa_cmp', ...
    'fault','sg_cycle','-v7.3');

write_case_tables(case_data,out);
write_pf_tables(pf.pf,case_data,out);
write_resource_table(sssa.equilibrium,case_data,out,'normal_resource_pf.csv');
write_state_inventory(sssa.equilibrium,out);
write_sssa_tables(sssa,out);
write_comparison_tables(pf_cmp,sssa_cmp,out);
write_ts_table(fault,out,'fault_only_ts.csv');
write_ts_table(sg_cycle,out,'sg_cycle_ts.csv');
write_event_table(fault,out,'fault_only_events.csv');
write_event_table(sg_cycle,out,'sg_cycle_events.csv');

manifest = struct('generated_at',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss Z')), ...
    'branch',git_text(root,'rev-parse --abbrev-ref HEAD'), ...
    'commit',git_text(root,'rev-parse HEAD'), ...
    'case_id','ieee14_1sg_4ibr','profile','rms10_profile_b', ...
    'normal_gfm_indices',2,'normal_gfl_indices',[3 4 5], ...
    'fault_converged',logical(fault.converged), ...
    'fault_failure_id',field_or(fault,'failure_id',''), ...
    'fault_failure_reason',field_or(fault,'failure_reason',''), ...
    'sg_cycle_converged',logical(sg_cycle.converged), ...
    'sg_cycle_reclose_status',field_or(sg_cycle,'reclose_status',''), ...
    'sssa_status',sssa.sssa.stability_status, ...
    'sssa_max_real',max(real(sssa.sssa.eigenvalues)), ...
    'normal_active_states',size(sssa.sssa.A,1), ...
    'comparison_active_states',arrayfun(@(p) size(p.sssa.A,1),sssa_cmp.points), ...
    'output_directory',out);
save(fullfile(out,'report_evidence.mat'),'pf','sssa','pf_cmp','sssa_cmp', ...
    'fault','sg_cycle','manifest','-v7.3');
write_manifest(manifest,fullfile(out,'manifest.txt'));
fprintf('Report evidence written to %s\n',out);
end

function r = run_product(product,opt,events)
opt.ibr_analysis = product;
req = wizard.build_request('ibr','ieee14_1sg_4ibr','options',opt,'events',events);
r = wizard.dispatch_analysis(req);
end

function write_case_tables(c,out)
bus=c.mpc.bus;
type_names={ 'PQ','PV','REF','ISOLATED' };
t=table(bus(:,1),string(type_names(bus(:,2))).',bus(:,3),bus(:,4), ...
    bus(:,5),bus(:,6),bus(:,8),bus(:,9),bus(:,10),bus(:,12),bus(:,13), ...
    'VariableNames',{'bus_id','type','Pd_MW','Qd_MVAr','Gs_MW','Bs_MVAr', ...
    'Vm0_pu','Va0_deg','base_kV','Vmax_pu','Vmin_pu'});
writetable(t,fullfile(out,'case_bus_data.csv'));
b=c.mpc.branch;
t=table((1:size(b,1)).',b(:,1),b(:,2),b(:,3),b(:,4),b(:,5),b(:,6), ...
    b(:,9),b(:,10),b(:,11), ...
    'VariableNames',{'branch_index','from_bus','to_bus','r_pu','x_pu','b_pu', ...
    'rateA_MVA','tap','shift_deg','status'});
writetable(t,fullfile(out,'case_line_data.csv'));
end

function write_pf_tables(pf,c,out)
nb=numel(pf.external_bus_ids);
type_names={'PQ','PV','REF','ISOLATED'};
type=type_names(c.mpc.bus(:,2)).';
t=table((1:nb).',pf.external_bus_ids(:),string(type),pf.bus_voltage(:), ...
    pf.bus_voltage_kV(:),pf.bus_angle_deg(:), ...
    'VariableNames',{'bus_position','bus_id','type','V_pu','V_kV','angle_deg'});
writetable(t,fullfile(out,'normal_pf_bus.csv'));
t=table((1:numel(pf.mismatch_history)).',pf.mismatch_history(:), ...
    'VariableNames',{'iteration','max_mismatch_pu'});
writetable(t,fullfile(out,'normal_pf_convergence.csv'));
end

function write_resource_table(eq,c,out,name)
V=complex(eq.y0(1:2:end),eq.y0(2:2:end)); nd=numel(eq.devices);
idx=(1:nd).'; id=strings(nd,1); bus=zeros(nd,1); mode=strings(nd,1);
P=zeros(nd,1); Q=P; Vm=P;
xo=0; uo=0;
for k=1:nd
    d=eq.devices(k); xr=xo+(1:d.nx); ur=uo+(1:d.nu);
    I=d.current_injection(0,eq.x0(xr),eq.y0,eq.u_eq(ur),eq.equilibrium_context);
    rec=d.reconstruct(0,eq.x0(xr),eq.y0,eq.u_eq(ur),eq.equilibrium_context);
    S=V(d.bus_position)*conj(I);
    id(k)=string(d.device_id); bus(k)=d.bus_id; mode(k)=upper(string(rec.mode));
    P(k)=real(S); Q(k)=imag(S); Vm(k)=abs(V(d.bus_position));
    xo=xo+d.nx; uo=uo+d.nu;
end
t=table(idx,id,bus,mode,P,Q,100*P,100*Q,Vm,69*Vm, ...
    'VariableNames',{'device_index','device_id','bus_id','mode','P_pu','Q_pu', ...
    'P_MW','Q_MVAr','V_pu','V_kV'});
writetable(t,fullfile(out,name));
end

function write_state_inventory(eq,out)
nd=numel(eq.devices); rows={}; go=0; apos=0;
for d=1:nd
    dev=eq.devices(d);
    active=dev.active_state_indices;
    for li=1:dev.nx
        gi=go+li; ap=NaN; status='FROZEN_NOT_IN_A';
        if ismember(li,active), apos=apos+1; ap=apos; status='ACTIVE_IN_A'; end
        rows(end+1,:)={gi,d,dev.device_id,dev.bus_id,li,dev.state_names{li},ap,status}; %#ok<AGROW>
    end
    go=go+dev.nx;
end
t=cell2table(rows,'VariableNames',{'global_state','device_index','device_id', ...
    'bus_id','local_state','state_name','A_index','status'});
writetable(t,fullfile(out,'normal_state_inventory.csv'));
end

function write_sssa_tables(r,out)
s=r.sssa; eq=r.equilibrium; m=stability.modal_analysis(s);
active=s.active_state_indices(:); offsets=[0 cumsum([eq.devices.nx])]; n=numel(m.eigenvalues);
mode=(1:n).'; raw=m.raw_eigen_index(:); pair=m.conjugate_pair_id(:);
lr=real(m.eigenvalues(:)); li=imag(m.eigenvalues(:)); f=abs(li)/(2*pi);
zeta=-lr./max(abs(m.eigenvalues(:)),eps); device=strings(n,1); state=strings(n,1);
gidx=zeros(n,1); lidx=zeros(n,1); participation=zeros(n,1);
for k=1:n
    [rho,ri]=max(m.display_ranking(:,k)); gi=active(ri);
    di=find(gi>offsets(1:end-1) & gi<=offsets(2:end),1); loc=gi-offsets(di);
    device(k)=string(eq.devices(di).device_id); state(k)=string(eq.devices(di).state_names{loc});
    gidx(k)=gi; lidx(k)=loc; participation(k)=100*rho;
end
t=table(mode,raw,pair,lr,li,f,zeta,device,gidx,lidx,state,participation, ...
    'VariableNames',{'mode','raw_eigen_index','pair_id','real_1_per_s', ...
    'imag_1_per_s','frequency_Hz','damping_ratio','dominant_device', ...
    'global_state','local_state','dominant_state','participation_percent'});
writetable(t,fullfile(out,'normal_sssa_eigenvalues.csv'));
end

function write_comparison_tables(pf_cmp,sssa_cmp,out)
r=pf_cmp.device_rows; n=numel(r); idx=(1:n).'; id=strings(n,1); bus=zeros(n,1);
P=zeros(n,3); Q=P; V=P;
for k=1:n
    id(k)=string(r(k).device_id); bus(k)=r(k).bus_id;
    P(k,:)=[r(k).pre.P_MW r(k).tripped.P_MW r(k).returned.P_MW];
    Q(k,:)=[r(k).pre.Q_MVAr r(k).tripped.Q_MVAr r(k).returned.Q_MVAr];
    V(k,:)=[r(k).pre.V_pu r(k).tripped.V_pu r(k).returned.V_pu];
end
t=table(idx,id,bus,P(:,1),P(:,2),P(:,3),Q(:,1),Q(:,2),Q(:,3), ...
    V(:,1),V(:,2),V(:,3),'VariableNames',{'index','device_id','bus_id', ...
    'P_pre_MW','P_trip_MW','P_return_MW','Q_pre_MVAr','Q_trip_MVAr', ...
    'Q_return_MVAr','V_pre_pu','V_trip_pu','V_return_pu'});
writetable(t,fullfile(out,'sg_trip_pf_compare.csv'));
p=sssa_cmp.points; label=replace(string({p.label}).','_','-'); active=arrayfun(@(x) size(x.sssa.A,1),p).';
maxreal=arrayfun(@(x) max(real(x.sssa.eigenvalues)),p).';
stable=arrayfun(@(x) x.sssa.root_counts.stable,p).';
marginal=arrayfun(@(x) x.sssa.root_counts.marginal,p).';
unstable=arrayfun(@(x) x.sssa.root_counts.unstable,p).';
t=table(label,active,maxreal,stable,marginal,unstable, ...
    'VariableNames',{'point','active_states','max_real_1_per_s', ...
    'stable_roots','marginal_roots','unstable_roots'});
writetable(t,fullfile(out,'sg_trip_sssa_compare.csv'));
end

function write_ts_table(r,out,name)
n=numel(r.t); ids=matlab.lang.makeValidName(r.device_ids);
t=table(r.t(:),'VariableNames',{'time_s'});
for k=1:numel(ids)
    t.([ids{k} '_angle_deg'])=r.device_angle_deg(k,:).';
    t.([ids{k} '_frequency_Hz'])=r.device_frequency_Hz(k,:).';
    t.([ids{k} '_P_MW'])=r.device_P_MW(k,:).';
    t.([ids{k} '_Q_MVAr'])=r.device_Q_MVAr(k,:).';
    t.([ids{k} '_I_pu'])=r.device_current_magnitude(k,:).';
    bi=find(r.bus_ids==r.device_bus_ids(k),1);
    t.([ids{k} '_V_pu'])=r.bus_voltage_magnitude(bi,:).';
end
fb=find(r.bus_ids==4,1); t.fault_bus4_V_pu=r.bus_voltage_magnitude(fb,:).';
writetable(t,fullfile(out,name));
end

function write_event_table(r,out,name)
if ~isfield(r,'event_log') || isempty(r.event_log)
    writetable(table(),fullfile(out,name)); return;
end
e=r.event_log; n=numel(e); idx=(1:n).'; type=string({e.type}).';
requested=nan(n,1); actual=nan(n,1); applied=false(n,1);
prekcl=nan(n,1); rightkcl=nan(n,1);
for k=1:n
    requested(k)=scalar_field(e(k),'requested_time',field_or(e(k),'time',NaN));
    actual(k)=scalar_field(e(k),'actual_time',field_or(e(k),'time',NaN));
    applied(k)=logical(scalar_field(e(k),'applied',false));
    prekcl(k)=scalar_field(e(k),'pre_kcl_norm',NaN);
    rightkcl(k)=scalar_field(e(k),'right_kcl_norm',NaN);
end
t=table(idx,type,requested,actual,applied,prekcl,rightkcl, ...
    'VariableNames',{'event_index','type','requested_time_s','actual_time_s', ...
    'applied','pre_kcl_norm','right_kcl_norm'});
writetable(t,fullfile(out,name));
end

function out=merge(a,b)
out=a; f=fieldnames(b); for k=1:numel(f), out.(f{k})=b.(f{k}); end
end

function v=field_or(s,name,default)
if isstruct(s) && isfield(s,name) && ~isempty(s.(name)), v=s.(name); else, v=default; end
end

function v=scalar_field(s,name,default)
v=field_or(s,name,default);
if ~(isnumeric(v) || islogical(v)) || ~isscalar(v), v=default; end
end

function s=git_text(root,args)
[status,s]=system(sprintf('git -C "%s" %s',root,args));
if status~=0, s='UNAVAILABLE'; else, s=strtrim(s); end
end

function write_manifest(m,file)
fid=fopen(file,'w'); c=onCleanup(@() fclose(fid)); %#ok<NASGU>
f=fieldnames(m);
for k=1:numel(f)
    v=m.(f{k});
    if isnumeric(v) || islogical(v), text=mat2str(v,16); else, text=char(string(v)); end
    fprintf(fid,'%s=%s\n',f{k},text);
end
end
