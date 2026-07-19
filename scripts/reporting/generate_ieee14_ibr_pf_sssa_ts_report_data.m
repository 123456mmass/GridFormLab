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
    'initial_gfm_count',0,'initial_gfl_count',4, ...
    'initial_gfm_indices',[],'initial_reference_resource_index',[], ...
    'plot_results',false,'plot_visible',false,'verbose',false,'pf_verbose',false);

% Independent all-GFL normal-operation products (no Full Analysis shortcut).
pf = run_product('pf',base_opt,struct('enabled',false));
sssa = run_product('sssa',base_opt,struct('enabled',false));
ts = run_product('ts',merge(base_opt,struct('t_end',15.0, ...
    'plot_results',true,'plot_visible',false)),struct('enabled',false));
assert(pf.converged && sssa.converged && ts.converged, ...
    'report:ieee14_ibr:stationaryProduct','A stationary report product failed closed.');

% Checkpoint the exact production outputs before presentation-only export.
save(fullfile(out,'raw_report_products.mat'),'pf','sssa','ts','-v7.3');

write_case_tables(case_data,out);
eq_tables=write_equilibrium_tables(sssa.equilibrium,pf.pf,case_data,out);
write_resource_table(sssa.equilibrium,case_data.mpc.baseMVA,out,'normal_resource_pf.csv');
write_state_inventory(sssa.equilibrium,out);
write_sssa_table(sssa,out,'normal_sssa_eigenvalues.csv');
write_ts_table(ts,out,'normal_event_free_ts.csv');

manifest = struct('generated_at',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss Z')), ...
    'branch',git_text(root,'rev-parse --abbrev-ref HEAD'), ...
    'commit',git_text(root,'rev-parse HEAD'), ...
    'case_id','ieee14_1sg_4ibr','model_inventory','dual_rms10_inventory', ...
    'normal_mode','SG1_PLUS_FOUR_GFL_RMS10', ...
    'normal_gfl_indices',[2 3 4 5], ...
    'sssa_status',sssa.sssa.stability_status, ...
    'sssa_max_real',max(real(sssa.sssa.eigenvalues)), ...
    'normal_active_states',size(sssa.sssa.A,1), ...
    'equilibrium_residual',sssa.equilibrium.residual_norm, ...
    'physical_kcl_norm',sssa.equilibrium.physical_kcl_norm, ...
    'reported_power_balance_norm',eq_tables.balance_norm, ...
    'reported_total_generation_pu',eq_tables.total_generation_pu, ...
    'reported_total_load_pu',eq_tables.total_load_pu, ...
    'ts_converged',logical(ts.converged), ...
    'ts_final_time',ts.t(end), ...
    'ts_accepted_steps',numel(ts.t)-1, ...
    'output_directory',out);
save(fullfile(out,'report_evidence.mat'),'pf','sssa','ts','manifest','-v7.3');
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

function metrics=write_equilibrium_tables(eq,pf_anchor,c,out)
V=complex(eq.y0(1:2:end),eq.y0(2:2:end));
bus_ids=c.mpc.bus(:,1); nb=numel(bus_ids); base=c.mpc.baseMVA;
type=repmat("PQ",nb,1); type(c.mpc.bus(:,2)==3)="REF";
t=table((1:nb).',bus_ids,string(type),abs(V),69*abs(V),rad2deg(angle(V)), ...
    'VariableNames',{'bus_position','bus_id','type','V_pu','V_kV','angle_deg'});
writetable(t,fullfile(out,'normal_pf_bus.csv'));

resources=equilibrium_resource_rows(eq,base);
Sgen=complex(zeros(nb,1));
for k=1:height(resources)
    bp=find(bus_ids==resources.bus_id(k),1);
    Sgen(bp)=Sgen(bp)+resources.P_pu(k)+1i*resources.Q_pu(k);
end
Vanchor=pf_anchor.bus_voltage(:).*exp(1i*deg2rad(pf_anchor.bus_angle_deg(:)));
Sload0=(c.mpc.bus(:,3)+1i*c.mpc.bus(:,4))/base;
Sload=Sload0.*(abs(V).^2./abs(Vanchor).^2);
t=table(bus_ids,real(Sgen),imag(Sgen),real(Sload),imag(Sload), ...
    real(Sgen-Sload),imag(Sgen-Sload), ...
    'VariableNames',{'bus_id','P_gen_pu','Q_gen_pu','P_load_pu', ...
    'Q_load_pu','P_net_pu','Q_net_pu'});
writetable(t,fullfile(out,'normal_pf_power.csv'));

seed_pf=eq.initialization.sg_on_all_gfl.pf;
t=table((1:numel(seed_pf.mismatch_history)).',seed_pf.mismatch_history(:), ...
    'VariableNames',{'iteration','max_mismatch_pu'});
writetable(t,fullfile(out,'normal_pf_convergence.csv'));

[Sf,St]=branch_terminal_power(c.mpc,V,bus_ids);
br=c.mpc.branch;
t=table((1:size(br,1)).',br(:,1),br(:,2),real(Sf),imag(Sf), ...
    real(Sf+St),imag(Sf+St), ...
    'VariableNames',{'line','from_bus','to_bus','P_from_pu','Q_from_pu', ...
    'P_loss_pu','Q_loss_pu'});
writetable(t,fullfile(out,'normal_pf_line_flow.csv'));

Sshunt=(-c.mpc.bus(:,5)+1i*c.mpc.bus(:,6))/base.*abs(V).^2;
balance=sum(Sgen)+sum(Sshunt)-sum(Sload)-sum(Sf+St);
assert(abs(balance)<1e-8,'report:ieee14_ibr:equilibriumPowerBalance', ...
    'All-GFL equilibrium report balance is %.3e pu.',abs(balance));
metrics=struct('balance_norm',abs(balance), ...
    'total_generation_pu',sum(real(Sgen)), ...
    'total_load_pu',sum(real(Sload)), ...
    'total_branch_loss_pu',sum(real(Sf+St)));
end

function write_resource_table(eq,base,out,name)
t=equilibrium_resource_rows(eq,base);
writetable(t,fullfile(out,name));
end

function t=equilibrium_resource_rows(eq,base)
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
t=table(idx,id,bus,mode,P,Q,base*P,base*Q,Vm,69*Vm, ...
    'VariableNames',{'device_index','device_id','bus_id','mode','P_pu','Q_pu', ...
    'P_MW','Q_MVAr','V_pu','V_kV'});
assert(isequal(cellstr(t.mode),{'SG';'GFL';'GFL';'GFL';'GFL'}), ...
    'report:ieee14_ibr:modeMap','Report equilibrium is not SG1 plus four GFL resources.');
end

function [Sf,St]=branch_terminal_power(mpc,V,bus_ids)
br=mpc.branch; nl=size(br,1); Sf=complex(zeros(nl,1)); St=Sf;
for k=1:nl
    if br(k,11)==0, continue; end
    i=find(bus_ids==br(k,1),1); j=find(bus_ids==br(k,2),1);
    tap=br(k,9); if tap==0, tap=1; end
    a=tap*exp(1i*deg2rad(br(k,10)));
    ys=1/(br(k,3)+1i*br(k,4)); ysh=1i*br(k,5)/2;
    If=((ys+ysh)/(a*conj(a)))*V(i)-(ys/conj(a))*V(j);
    It=(ys+ysh)*V(j)-(ys/a)*V(i);
    Sf(k)=V(i)*conj(If); St(k)=V(j)*conj(It);
end
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

function write_sssa_table(r,out,name)
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
writetable(t,fullfile(out,name));
end

function write_ts_table(r,out,name)
ids=matlab.lang.makeValidName(r.device_ids);
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
writetable(t,fullfile(out,name));
end

function out=merge(a,b)
out=a; f=fieldnames(b); for k=1:numel(f), out.(f{k})=b.(f{k}); end
end

function s=git_text(root,args)
[status,s]=system(sprintf('git -C "%s" %s',root,args));
if status~=0, s='UNAVAILABLE'; else, s=strtrim(s); end
end

function write_manifest(m,file)
fid=fopen(file,'w'); c=onCleanup(@() fclose(fid));
f=fieldnames(m);
for k=1:numel(f)
    v=m.(f{k});
    if isnumeric(v) || islogical(v), text=mat2str(v,16); else, text=char(string(v)); end
    fprintf(fid,'%s=%s\n',f{k},text);
end
end
