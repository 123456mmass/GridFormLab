function folder=probe_ne39_chronology_design(opt)
%PROBE_NE39_CHRONOLOGY_DESIGN คัดกรอง plant/endpoint ก่อน production ไม่ใช่ replay PASS.
arguments
    opt (1,1) struct = struct()
end
root=pf_init_paths();
folder=fullfile(root,'output','diagnostics', ...
    ['ne39_chronology_design_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(folder);
base=cases.case_ne39_1sg_9ibr();
request=struct('design_options',opt,'classification','PROJECT_DERIVED_SCREENING', ...
    'production_ready',false,'source_sha256',base.source_detail.transcription_sha256);
screen=struct('status','NOT_RUN','reason','','production_ready',false);
save(fullfile(folder,'request.mat'),'request','-v7.3');
timer=tic;
try
    c=cases.ne39_chronology_design(base,opt);
    im=struct('device_id',{'IBR33','IBR37'},'mode',{'gfm','gfm'});
    s=cases.scenario_ne39_tamu_mixed(c,struct('initial_modes',im));
    request.scenario=s;
    [dev,~]=stability.build_mixed_resource_devices(c,s.resources,s.scenario_opt);
    eq=stability.mixed_equilibrium_solve(c,struct('devices',dev), ...
        struct('verbose',false,'tolerance',1e-9,'max_iter',300));
    if ~eq.converged
        error('probe_ne39_chronology_design:sgOn','SG_ON: %s',eq.failure_reason);
    end
    % SG_OFF ครบเก้า GFM โดยใช้ production device และ case-bound DC เดิม.
    off=s.resources; ii=find(strcmp({off.resource_type},'ibr'));
    off(1).initial_online=false; off(1).initial_mode='breaker_open';
    for k=ii, off(k).initial_mode='gfm'; end
    disp=c.dispatch_contract.post_trip.post_trip_Pg_MW;
    [dv,~]=stability.build_mixed_resource_devices(c,off,struct('dispatch',disp));
    dae=stability.composite_dae(c,dv,struct());
    ec=struct('hybrid_state',stability.ts_hybrid_state_init(dv));
    Y0=dae.Ynet;
    pf=pfsolver.powerflow_newton_raphson(c,struct('verbose',false, ...
        'plot_results',false,'tolerance',1e-11,'max_iter',60,'enforce_q_limits',false));
    dY=.2*diag(conj(complex(c.mpc.bus(:,3),c.mpc.bus(:,4))/c.mpc.baseMVA) ...
        ./(pf.bus_voltage.^2+eps));
    Yload=Y0+dY; Yline=Yload-line_stamp(c.mpc,16,17);
    a=steady(dae,ec,ii(1),Y0);
    b=droop_steady(a,dae,ec,ii,Yload,c);
    d=droop_steady(a,dae,ec,ii,Yline,c);
    bounds=struct('v_min',.9,'v_max',1.1,'f_min',59.5,'f_max',60.5);
    eq_dae=stability.composite_dae(c,dev,struct());
    eq_state=struct('x0',eq.x0,'y0',eq.y0,'u_eq',eq.u_eq);
    screen.sg_on=snapshot(eq_state,eq_dae.Ynet,eq_dae,eq.equilibrium_context,s.resources,c,bounds);
    screen.sg_on.converged=eq.converged;
    screen.post_trip=snapshot(a,Y0,dae,ec,s.resources,c,bounds);
    screen.loaded=snapshot(b,Yload,dae,ec,s.resources,c,bounds);
    screen.line_open=snapshot(d,Yline,dae,ec,s.resources,c,bounds);
    screen.load_right=endpoint(a,Y0,Yload,dae,ec,s.resources,c,bounds);
    screen.restore_right=endpoint(d,Yline,Y0,dae,ec,s.resources,c,bounds);
    screen.design=c.chronology_design;
    screen.production_ready=false; % ยังไม่ได้พิสูจน์ dynamics/selector/reclose.
    screen.endpoint_pass=strcmp(screen.load_right.evidence.status,'PASS') && ...
        strcmp(screen.restore_right.evidence.status,'PASS');
    screen.status='SCREENED_NOT_PRODUCTION_CERTIFIED';
    if ~screen.endpoint_pass, screen.reason='INSTANTANEOUS_ENDPOINT_CONSTRAINTS_FAIL'; end
    fprintf('[NE39-design] capacity=%g required=%g M=%g H=%g Dv=%g endpoint_pass=%d\n', ...
        sum([c.study_capability.records.Pmax_MW]),c.chronology_design.Pcapacity_required_MW, ...
        c.chronology_design.M_s,c.chronology_design.H_s,c.chronology_design.Dv,screen.endpoint_pass);
    for name={'post_trip','loaded','line_open','load_right','restore_right'}
        z=screen.(name{1});
        fprintf('%s status=%s V=[%.9g %.9g] KCL=%.3g\n', ...
            name{1},z.evidence.status,z.Vmin,z.Vmax,z.kcl);
        for row=z.evidence.records
            if ~row.pass
                fprintf('FAIL %s %s P=%g Q=%g I=%g\n',row.resource_id,row.failure, ...
                    row.P_MW,row.Q_MVAr,row.I_converter_pu);
            end
        end
    end
catch me
    screen.status='SCREEN_FAILED'; screen.reason=me.message; screen.failure_id=me.identifier;
    fprintf('[NE39-design] failed %s: %s\n',me.identifier,me.message);
end
elapsed=toc(timer);
save(fullfile(folder,'screen.mat'),'request','screen','elapsed','-v7.3');
save(fullfile(folder,'request.mat'),'request','-v7.3');
fprintf('artifact=%s elapsed=%g\n',folder,elapsed);
end

function z=steady(dae,ec,ref,Y)
% ใช้ reduced initializer เดิมกับ Y chronology จริง แล้วตรวจ RHS/KCL จริง.
dae.Ynet=Y;
z=stability.mixed_ibr_reduced_initialize(dae,ec,ref, ...
    struct('tolerance',1e-10,'max_iter',300,'fd_eps',3e-6));
if ~z.converged
    error('probe_ne39_chronology_design:steady','%s',z.failure_reason);
end
rhs=dae.dae_f(0,z.x0,z.y0,z.u_eq,ec);
active=[];
for k=1:numel(dae.devices)
    rec=dae.devices(k).reconstruct(0,z.x0(dae.device_offsets(k)+(1:dae.devices(k).nx)), ...
        z.y0,z.u_eq(dae.u_offsets(k)+(1:dae.devices(k).nu)),ec);
    if rec.online
        active=[active,dae.device_offsets(k)+dae.devices(k).active_state_indices_for_context(ec)]; %#ok<AGROW>
    end
end
if norm(rhs(active),inf)>1e-7
    error('probe_ne39_chronology_design:rhs','steady full active RHS ไม่ผ่าน: %.6g',norm(rhs(active),inf));
end
end

function a=droop_steady(base,dae,ec,ii,Y,c)
% relative equilibrium: u คงเดิม, ทุก GFM หมุนด้วยความถี่ร่วม ไม่ float P_ref ใหม่.
ref=dae.devices(ii(1)).bus_position; free=setdiff(1:numel(base.y0),2*ref);
z0=[base.y0(free);0];
rfn=@(z)droop_residual(z,base,dae,ii,Y,free);
[z,~,ok,norm_r]=stability.composite_newton(z0,rfn, ...
    @(z)stability.ts_jac_y_fd([],z,[],@(x,v,Y)rfn(v)),1e-9,100,false);
if ~ok
    error('probe_ne39_chronology_design:droop','relative equilibrium ไม่ converged: %g',norm_r);
end
[~,y,P,Q]=droop_residual(z,base,dae,ii,Y,free);
a=base; a.y0=y;
for j=1:numel(ii)
    k=ii(j); dev=dae.devices(k); bp=dev.bus_position;
    x=dev.equilibrium_initialize(complex(y(2*bp-1),y(2*bp)),P(j),Q(j),ec);
    slot=find(strcmp(dev.state_names,'gfm_omega_VSG'));
    if ~isscalar(slot), error('probe_ne39_chronology_design:omega','ไม่มี unique GFM speed state'); end
    x(slot)=1+z(end);
    a.x0(dae.device_offsets(k)+(1:dev.nx))=x;
end
rhs=dae.dae_f(0,a.x0,y,a.u_eq,ec); active=[]; theta=[];
for k=ii
    dev=dae.devices(k);
    active=[active,dae.device_offsets(k)+dev.active_state_indices_for_context(ec)]; %#ok<AGROW>
    theta=[theta,dae.device_offsets(k)+find(strcmp(dev.state_names,'gfm_delta_VSG'))]; %#ok<AGROW>
end
rhs(theta)=rhs(theta)-2*pi*c.base_values.frequency_Hz*z(end);
if norm(rhs(active),inf)>1e-7
    error('probe_ne39_chronology_design:droopRhs','rotating-frame active RHS ไม่ผ่าน: %g',norm(rhs(active),inf));
end
a.common_frequency_Hz=c.base_values.frequency_Hz*(1+z(end));
end

function [r,y,P,Q]=droop_residual(z,base,dae,ii,Y,free)
y=zeros(size(base.y0)); y(free)=z(1:end-1); w=z(end);
V=complex(y(1:2:end),y(2:2:end)); I=complex(zeros(size(V)));
P=zeros(numel(ii),1); Q=P;
for j=1:numel(ii)
    k=ii(j); dev=dae.devices(k); p=dev.provenance.branch_params.gfm;
    u=base.u_eq(dae.u_offsets(k)+(1:dev.nu)); b=dev.bus_position;
    P(j)=u(1)-p.Dv*w/p.kappa;
    Q(j)=u(2)+p.kE*(u(3)-abs(V(b)))/(p.kQ*p.kappa);
    I(b)=conj(complex(P(j),Q(j))/V(b));
end
r=Y*V-I; r=reshape([real(r).';imag(r).'],[],1);
end

function z=snapshot(a,Y,dae,ec,resources,c,bounds)
V=complex(a.y0(1:2:end),a.y0(2:2:end));
I=dae.current_injection(0,a.x0,a.y0,a.u_eq,ec);
z=struct('Vmin',min(abs(V)),'Vmax',max(abs(V)),'kcl',norm(Y*V-I,inf), ...
    'evidence',stability.ne39_transition_snapshot(0,a.x0,a.y0,a.u_eq,ec,dae,resources,c,bounds));
end

function z=endpoint(a,Yleft,Yright,dae,ec,resources,c,bounds)
% all-GFM current ไม่ขึ้นกับ y: canonical Newton มี exact linear KCL Jacobian.
Ileft=dae.current_injection(0,a.x0,a.y0,a.u_eq,ec);
g=@(x,y,Y)dae.dae_g(0,x,y,Y,a.u_eq,ec);
jac=@(~,~,Y,~)rectangular(Y);
[y,info]=stability.ts_algebraic_solve(a.x0,a.y0,Yright,g,jac,1e-9);
Iright=dae.current_injection(0,a.x0,y,a.u_eq,ec);
right=a; right.y0=y;
z=snapshot(right,Yright,dae,ec,resources,c,bounds);
z.solver=info; z.current_jump_pu=norm(Iright-Ileft,inf);
z.state_continuity_exact=true; z.input_continuity_exact=true;
z.left_kcl=norm(Yleft*complex(a.y0(1:2:end),a.y0(2:2:end))-Ileft,inf);
z.voltage_right=y; z.state_left=a.x0; z.input_left=a.u_eq;
if z.current_jump_pu>1e-12 || z.kcl>1e-6
    error('probe_ne39_chronology_design:endpoint','endpoint continuity/KCL ไม่ผ่าน');
end
end

function J=rectangular(Y)
nb=size(Y,1); J=zeros(2*nb);
J(1:2:end,1:2:end)=real(Y); J(1:2:end,2:2:end)=-imag(Y);
J(2:2:end,1:2:end)=imag(Y); J(2:2:end,2:2:end)=real(Y);
end

function Y=line_stamp(mpc,from,to)
hit=(mpc.branch(:,1)==from & mpc.branch(:,2)==to) | ...
    (mpc.branch(:,1)==to & mpc.branch(:,2)==from);
if nnz(hit)~=1, error('probe_ne39_chronology_design:line','line ไม่ unique'); end
b=mpc.branch(hit,:); i=find(mpc.bus(:,1)==b(1)); j=find(mpc.bus(:,1)==b(2));
a=b(9); if a==0, a=1; end
a=a*exp(1i*deg2rad(b(10))); ys=1/complex(b(3),b(4));
Y=complex(zeros(size(mpc.bus,1)));
Y(i,i)=(ys+1i*b(5)/2)/abs(a)^2; Y(j,j)=ys+1i*b(5)/2;
Y(i,j)=-ys/conj(a); Y(j,i)=-ys/a;
end
