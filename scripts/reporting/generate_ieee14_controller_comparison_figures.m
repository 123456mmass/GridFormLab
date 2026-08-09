function compact = generate_ieee14_controller_comparison_figures()
%GENERATE_IEEE14_CONTROLLER_COMPARISON_FIGURES Raw three-arm evidence figures.
pf_init_paths();
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
adir=fullfile(root,'output','diagnostics','ieee14_controller_compare');
fdir=fullfile(root,'docs','source','figures','ieee14_controller_compare');
if ~exist(fdir,'dir'), mkdir(fdir); end
sys=ibr.build_ieee14_switch_system(index_mode="agsi_pp", ...
    case_profile="eecon49_figure4",sg_H=2.5,sg_D=1.0,T_d_on=0.10,T_d_off=1.0);

b=load(fullfile(root,'output','diagnostics','regfm_post_trip_probe.mat'),'r');
legacy=adapt(b.r,sys); clear b
q=load(fullfile(adir,'et_fcsps_160_raw.mat'),'result'); et=adapt(q.result,sys);
et_audit=q.result.controller_audit; clear q
q=load(fullfile(adir,'bo_replay_160_raw.mat'),'result'); bo=adapt(q.result,sys);
bo_audit=q.result.controller_audit; clear q

methods={'Legacy selector','ET-FCSPS','BO replay'}; O={legacy,et,bo};
diffs=struct('et_vs_legacy',maxdiff(et,legacy), ...
    'bo_vs_legacy',maxdiff(bo,legacy),'bo_vs_et',maxdiff(bo,et));
writetable(struct2table([diffs.et_vs_legacy,diffs.bo_vs_legacy,diffs.bo_vs_et]), ...
    fullfile(adir,'trajectory_differences.csv'));

comparison_figure(O,methods,fullfile(fdir,'controller_comparison_system.png'));
mode_figure(O,methods,fullfile(fdir,'controller_comparison_modes.png'));
response_figure(et,fullfile(fdir,'controller_et_fcsps_raw_response.png'));
candidate_figure(et_audit,bo_audit,fullfile(fdir,'controller_candidate_costs.png'));
compact=struct('legacy',legacy,'et',et,'bo',bo,'diffs',diffs, ...
    'et_audit',compact_audit(et_audit),'bo_audit',compact_audit(bo_audit));
save(fullfile(adir,'comparison_compact.mat'),'compact','-v7.3');
fprintf('CONTROLLER_COMPARISON_FIGURES_DONE: %s\n',fdir);
end

function o=adapt(r,sys)
t=r.t(:); didx=2:5; nibr=4; nt=numel(t);
V=complex(r.y_traj(1:2:end,:),r.y_traj(2:2:end,:)); buspos=zeros(1,nibr);
for j=1:nibr, buspos(j)=find(r.bus_ids==r.device_bus_ids(didx(j)),1); end
Vibr=V(buspos,:).'; busang=unwrap(angle(Vibr),[],1);
fibr=angle_frequency(t,busang,60); modes=string(r.device_modes_history(didx,:)).';
devs=r.equilibrium.devices; xoff=[0 cumsum([devs.nx])];
for j=1:nibr
    d=devs(didx(j)); names=string(d.state_names); iw=find(names=="gfm_omega_m",1);
    xr=r.x_traj(xoff(didx(j))+(1:d.nx),:).'; g=strcmpi(modes(:,j),"gfm");
    if ~isempty(iw), fibr(g,j)=60*(1+xr(g,iw)); end
end
I=r.device_currents(didx,:).'; Idq=I.*exp(-1i*busang);
sgonline=logical(r.device_online_history(1,:)).'; gra=sgonline|any(strcmpi(modes,"gfm"),2);
index=zeros(nt,nibr);
for j=1:nibr
    d=sys.devs{j}; rocof=filtered_rate(t,fibr(:,j),d.rocof_tau);
    Jv=abs(abs(Vibr(:,j))-d.V_ref)/d.dV_base;
    Jf=abs(fibr(:,j)-d.f0)/d.df_base; Jr=abs(rocof)/d.dR_base;
    Jp=abs(d.u(1)-r.device_P_pu(didx(j),:).')/d.dP_base;
    Jscr=max(0,d.SCR_crit/max(d.grid_scr,1e-9)-1)*ones(nt,1);
    Jlock=abs(imag(Vibr(:,j).*exp(-1i*busang(:,j))))/d.dvq_base;
    index(:,j)=min(1,max(0,0.5*Jv+0.5*Jf));   % 2-term severity (see switch report)
end
ref=-ones(nt,1);
for k=1:nt
    hs=r.event_context_history{k}.hybrid_state;
    if isfield(hs,'reference_owner_indices') && ~isempty(hs.reference_owner_indices)
        owner=hs.reference_owner_indices(1); if owner==1, ref(k)=0; elseif any(owner==didx), ref(k)=find(didx==owner,1); end
    end
end
o=struct('t',t,'agsi',index,'mode',double(strcmpi(modes,"gfm")), ...
    'P',r.device_P_pu(didx,:).','Q',r.device_Q_pu(didx,:).', ...
    'id',real(Idq),'iq',imag(Idq),'f',fibr,'angle',wrap_pi(busang-busang(:,1)), ...
    'V',abs(Vibr),'Vmin',min(abs(V),[],1).','ref',ref,'gra',double(gra), ...
    'sgP',r.device_P_pu(1,:).','sgQ',r.device_Q_pu(1,:).', ...
    'sgf',r.device_frequency_Hz(1,:).','sgangle',r.x_traj(1,:).', ...
    'imax',max(r.device_current_magnitude./r.device_current_limit_sys,[],1,'omitnan').', ...
    'events',[20,50,85,85.15,110,145,r.actual_reclose_time]);
end

function comparison_figure(O,names,file)
f=figure('Visible','off','Color','w','Units','inches','Position',[1 1 6.4 7.2]);
tl=tiledlayout(f,4,1,'TileSpacing','compact','Padding','compact'); C=lines(3);
fields={'Vmin','sgf','imax'}; yl={'min |V| (pu)','SG f (Hz)','max |I|/I_{max}'};
for p=1:3
    ax=nexttile(tl); hold(ax,'on');
    for k=1:3, plot(ax,O{k}.t,O{k}.(fields{p}),'Color',C(k,:),'LineWidth',1.0); end
    grid(ax,'on'); box(ax,'on'); ylabel(ax,yl{p}); xlim(ax,[0 160]); event_lines(ax,O{1}.events);
end
ax=nexttile(tl); hold(ax,'on');
for k=1:3, stairs(ax,O{k}.t,O{k}.ref,'Color',C(k,:),'LineWidth',1.0); end
grid(ax,'on'); box(ax,'on'); ylabel(ax,'reference'); xlabel(ax,'time (s)');
yticks(ax,0:4); yticklabels(ax,{'SG','IBR1','IBR2','IBR3','IBR4'}); xlim(ax,[0 160]); event_lines(ax,O{1}.events);
legend(ax,names,'Location','southoutside','Orientation','horizontal'); title(tl,'Raw production comparison: identical case, chronology and solver');
style(f); exportgraphics(f,file,'Resolution',240); close(f);
end

function mode_figure(O,names,file)
f=figure('Visible','off','Color','w','Units','inches','Position',[1 1 6.4 6.8]);
tl=tiledlayout(f,3,4,'TileSpacing','compact','Padding','compact'); C=lines(4);
for i=1:3, for j=1:4
    ax=nexttile(tl); stairs(ax,O{i}.t,O{i}.mode(:,j),'Color',C(j,:),'LineWidth',1.1);
    ylim(ax,[-.1 1.1]); yticks(ax,[0 1]); yticklabels(ax,{'GFL','GFM'}); xlim(ax,[0 160]); grid(ax,'on'); box(ax,'on'); event_lines(ax,O{i}.events);
    title(ax,sprintf('%s\nIBR%d',names{i},j)); if i==3, xlabel(ax,'time (s)'); end
end, end
title(tl,'Committed mode timelines (raw discrete states)'); style(f); exportgraphics(f,file,'Resolution',240); close(f);
end

function response_figure(o,file)
f=figure('Visible','off','Color','w','Units','inches','Position',[1 1 6.4 8.2]);
tl=tiledlayout(f,4,2,'TileSpacing','compact','Padding','compact'); C=lines(4);
data={o.agsi,o.P,o.Q,o.id,o.iq,o.f,o.angle*180/pi,o.V};
ttl={'AGSI++','P (pu)','Q (pu)','i_d (pu)','i_q (pu)','f (Hz)','angle (deg)','|V| (pu)'};
for p=1:8
    ax=nexttile(tl); hold(ax,'on'); for j=1:4, plot(ax,o.t,data{p}(:,j),'Color',C(j,:),'LineWidth',0.8); end
    if p==2, plot(ax,o.t,o.sgP,'k--','LineWidth',1.0); end
    if p==3, plot(ax,o.t,o.sgQ,'k--','LineWidth',1.0); end
    if p==6, plot(ax,o.t,o.sgf,'k--','LineWidth',1.0); end
    grid(ax,'on'); box(ax,'on'); ylabel(ax,ttl{p}); xlim(ax,[0 160]); event_lines(ax,o.events);
    if p>=7, xlabel(ax,'time (s)'); end
end
lgd=legend(ax,{'IBR1','IBR2','IBR3','IBR4'},'Location','southoutside','Orientation','horizontal');
title(tl,'ET-FCSPS raw accepted production signals - 160 s'); style(f); lgd.FontSize=9; exportgraphics(f,file,'Resolution',240); close(f);
end

function candidate_figure(et,bo,file)
c=et.decision.candidates; ok=[c.metrics_pass]; x=[c(ok).ordinal]; J=[c(ok).cost];
f=figure('Visible','off','Color','w','Units','inches','Position',[1 1 6.4 3.8]);
ax=axes(f); stem(ax,x,J,'filled','Color',[.10 .40 .75],'LineWidth',1.0); hold(ax,'on');
sample=bo.bo.sampled_indices; sample=sample([c(sample).metrics_pass]);
scatter(ax,[c(sample).ordinal],[c(sample).cost],55,[.85 .25 .10],'o','LineWidth',1.4);
[~,w]=min(J); scatter(ax,x(w),J(w),80,[.10 .60 .25],'p','filled');
grid(ax,'on'); box(ax,'on'); xlabel(ax,'canonical candidate ordinal'); ylabel(ax,'dimensionless cost J');
title(ax,'ET exhaustive feasible costs and BO-revealed candidates');
legend(ax,{'ET feasible cost','BO revealed','selected minimum'},'Location','best'); style(f); exportgraphics(f,file,'Resolution',240); close(f);
end

function d=maxdiff(a,b)
fields={'agsi','mode','P','Q','id','iq','f','angle','V','Vmin','ref','sgP','sgQ','sgf'}; d=struct();
for k=1:numel(fields), z=a.(fields{k})-b.(fields{k}); z=z(isfinite(z)); if isempty(z), v=0; else, v=max(abs(z)); end; d.(fields{k})=v; end
end
function a=compact_audit(a), a=rmfield(a,'trial_table'); if isfield(a,'decision'), a.decision=rmfield(a.decision,'candidates'); end, end
function event_lines(ax,e), for k=1:numel(e), if isfinite(e(k)), xline(ax,e(k),':','Color',[.55 .55 .55],'HandleVisibility','off'); end, end, end
function style(f), set(findall(f,'Type','axes'),'FontName','Times New Roman','FontSize',11); set(findall(f,'Type','text'),'FontName','Times New Roman','FontSize',11); end
function f=angle_frequency(t,a,f0), f=f0*ones(size(a)); for j=1:size(a,2), for k=2:numel(t), h=t(k)-t(k-1); if h>eps, f(k,j)=f0+(a(k,j)-a(k-1,j))/(2*pi*h); else, f(k,j)=f(k-1,j); end, end, f(1,j)=f(2,j); end, end
function r=filtered_rate(t,f,tau), r=zeros(size(f)); for k=2:numel(t), h=t(k)-t(k-1); if h>eps, raw=(f(k)-f(k-1))/h; a=min(1,h/tau); r(k)=r(k-1)+a*(raw-r(k-1)); else, r(k)=r(k-1); end, end, end
function a=wrap_pi(a), a=mod(a+pi,2*pi)-pi; end
