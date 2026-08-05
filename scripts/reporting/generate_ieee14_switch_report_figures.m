function out = generate_ieee14_switch_report_figures(opts)
%GENERATE_IEEE14_SWITCH_REPORT_FIGURES Reproduce publishable IEEE14 evidence.
%   The source-data profile is simulated by the production all-KCL hybrid
%   engine: six-state EMF6 SG, registered full-state dual-mode IBR devices,
%   exact event landing, synchronism guard, and coordinated SG handback.
%   AGSI++ is reconstructed from the accepted raw production signals using
%   the project seven equally weighted terms.  It is evidence for the index;
%   the SG-trip and SG-reference-handback transactions remain explicitly
%   separate CASE_DEFINED overrides.  A seeded band-limited display-only
%   measurement ripple is drawn beside the raw trace and never feeds the
%   solver, AGSI, timers, gates, or mode decisions.

arguments
    opts.reuse_cache (1,1) logical = false
end

pf_init_paths();
outdir = fullfile('docs','source','figures','switch_ieee14');
if ~exist(outdir,'dir'), mkdir(outdir); end

sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp", ...
    case_profile="eecon49_figure4", sg_H=2.5, sg_D=1.0, ...
    T_d_on=0.10, T_d_off=1.0);
write_pf_tables(sys.pf,outdir);
T_end_contract=sys.switching_event_contract.T_end;
production_cache=fullfile('output','diagnostics','regfm_post_trip_probe.mat');
figure_cache=fullfile('output','diagnostics', ...
    sprintf('ieee14_switch_%g_exact.mat',T_end_contract));
reuse_ok=false;
if opts.reuse_cache && exist(production_cache,'file')
    cached=load(production_cache,'r'); r=cached.r;
    % Phase G guard: a cache produced under a shorter horizon must never be
    % presented as evidence for the current contract.  Fail closed instead of
    % silently reusing a truncated trajectory.
    reuse_ok = r.converged && r.t(end) >= T_end_contract - 1e-9;
    if ~reuse_ok
        error('generate_ieee14_switch_report_figures:staleCacheHorizon', ...
            ['Cached run ends at %.6f s but the case contract requires %g s. ', ...
             'Rerun with reuse_cache=false to regenerate the trajectory.'], ...
            r.t(end),T_end_contract);
    end
end
if ~reuse_ok
    [scenario,opt]=production_request();
    r=stability.run_hybrid_case(scenario,opt);
    if ~r.converged || r.t(end)<T_end_contract
        error('generate_ieee14_switch_report_figures:productionRun', ...
            'Production run failed closed at %.6f s (required %g s): %s %s', ...
            r.t(end),T_end_contract,string(r.failure_id),string(r.failure_reason));
    end
    cachedir=fileparts(production_cache);
    if ~exist(cachedir,'dir'), mkdir(cachedir); end
    save(production_cache,'r','-v7.3');
end
out=adapt_production_result(r,sys);
o=out; save(figure_cache,'o','-v7.3');
out.pf=sys.pf;
out.event_contract=sys.switching_event_contract;
T_end=T_end_contract;
out.requested_horizon_s=T_end;
out.bo_controller_added=false;
out.presentation_noise=struct('kind','seeded band-limited measurement ripple overlay', ...
    'seed_base',4901,'affects_solver_or_switching',false);
if out.diverged || ~out.newton_all_converged || out.tgrid(end)<T_end
    out.dynamic_status='DIAGNOSTIC_PREFIX_ONLY_FAIL_CLOSED';
    figure_title=sprintf('Diagnostic raw prefix to %.3f s (requested %g s; fail-closed)', ...
        out.tgrid(end),T_end);
else
    out.dynamic_status=sprintf('FULL_%g_S_GATE_PASSED',T_end);
    figure_title=sprintf('Production all-KCL response: full %g-s chronology',T_end);
end
write_event_table(out,outdir);
tag=sprintf('%g',T_end);
supervisor_figure(out,outdir,['ieee14_switch_' tag '_supervisor.png'],figure_title);
electrical_figure(out,outdir,['ieee14_switch_' tag '_electrical.png'],figure_title);
angle_figure(out,outdir,['ieee14_switch_' tag '_angles.png']);
timeline_figure(out,outdir,['ieee14_switch_' tag '_timeline.png']);
fprintf('IEEE14_SWITCH_REPORT_FIGURES_DONE: %s [%s]\n',outdir,out.dynamic_status);
end

function [s,opt]=production_request()
s=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
ev=struct('enabled',true,'event_profile','chronology', ...
    'sg_trip',20,'load_step',50,'load_step_factor',0.20, ...
    'fault_on',85,'fault_clear',85.15,'fault_bus',9,'Zf',0.01+0.01i, ...
    'line_trip',110,'line_from_bus',6,'line_to_bus',13, ...
    'restore_time',145,'sg_on',145,'coordinated_handback',true, ...
    'selected_gfm_indices',2:5,'reference_resource_index',2, ...
    'automatic_gfm_switching',true, ...
    'delays_overrides',struct('timeout_s',5,'dwell_s',0.5));
% Phase G: horizon extended 160 -> 200 s so the trajectory covers the SG
% reclose (observed near 147.175 s for the 145.000 s request) plus a settling
% window after handback.  Taken from the case contract rather than restated
% here, so the case file remains the single owner of the event schedule.
opt=struct('t_end',s.case_data.switching_event_contract.T_end, ...
    'dt',0.0125,'verbose',false, ...
    'ibr_events',ev,'plot_results',false);
end

function o=adapt_production_result(r,sys)
% Reporting adapter only: no reconstructed signal feeds a production gate.
t=r.t(:); nt=numel(t); nibr=4; didx=2:5;
V=complex(r.y_traj(1:2:end,:),r.y_traj(2:2:end,:));
buspos=zeros(1,nibr);
for j=1:nibr
    buspos(j)=find(r.bus_ids==r.device_bus_ids(didx(j)),1);
end
Vibr=V(buspos,:).'; busang=unwrap(angle(Vibr),[],1);
busfreq=angle_frequency(t,busang,60);

devs=r.equilibrium.devices;
xoff=[0 cumsum([devs.nx])];
modes=string(r.device_modes_history(didx,:)).';
angle_ibr=busang; f_ibr=busfreq;
for j=1:nibr
    d=devs(didx(j)); names=string(d.state_names);
    iw=find(names=="gfm_omega_m",1);
    ipll=find(names=="gfm_delta_PLL",1);
    iit=find(names=="gfm_delta_IT",1);
    xr=r.x_traj(xoff(didx(j))+(1:d.nx),:).';
    isgfm=strcmpi(modes(:,j),"gfm");
    if ~isempty(iw), f_ibr(isgfm,j)=60*(1+xr(isgfm,iw)); end
    if ~isempty(ipll) && ~isempty(iit)
        angle_ibr(isgfm,j)=xr(isgfm,ipll)+xr(isgfm,iit);
    end
end

Iibr=r.device_currents(didx,:).';
Idq=Iibr.*exp(-1i*angle_ibr);
sg_delta=r.x_traj(1,:).'; sg_omega=r.x_traj(2,:).';
sg_id=zeros(nt,1); sg_iq=zeros(nt,1);
sg=devs(1); uoff=[0 cumsum([devs.nu])];
for k=1:nt
    rec=sg.reconstruct(t(k),r.x_traj(1:sg.nx,k),r.y_traj(:,k), ...
        r.u_history(uoff(1)+(1:sg.nu),k),r.event_context_history{k});
    sg_id(k)=rec.Id; sg_iq(k)=rec.Iq;
end

sgonline=logical(r.device_online_history(1,:)).';
gra=sgonline | any(strcmpi(modes,"gfm"),2);
GRA=repmat(double(gra),1,nibr);
% Reference ownership is read from the accepted hybrid-state history.  It is
% deliberately not inferred from "the first GFM", because mode and reference
% ownership are different contracts when several GFM units are online.
ref_code=-ones(nt,1);
for k=1:nt
    hs=struct();
    if isfield(r,'event_context_history') && numel(r.event_context_history)>=k && ...
            isstruct(r.event_context_history{k}) && ...
            isfield(r.event_context_history{k},'hybrid_state')
        hs=r.event_context_history{k}.hybrid_state;
    end
    if isfield(hs,'reference_owner_indices') && ~isempty(hs.reference_owner_indices)
        owner=hs.reference_owner_indices(1);
        if owner==1
            ref_code(k)=0;                  % SG device index
        elseif any(owner==didx)
            ref_code(k)=find(didx==owner,1); % IBR1..IBR4
        end
    elseif sgonline(k)
        ref_code(k)=0;
    end
end

index=zeros(nt,nibr); raw_index=zeros(nt,nibr);
for j=1:nibr
    d=sys.devs{j}; Vmag=abs(Vibr(:,j));
    rocof=filtered_rate(t,f_ibr(:,j),d.rocof_tau);
    Jv=abs(Vmag-d.V_ref)/d.dV_base;
    Jf=abs(f_ibr(:,j)-d.f0)/d.df_base;
    Jr=abs(rocof)/d.dR_base;
    Jp=abs(d.u(1)-r.device_P_pu(didx(j),:).')/d.dP_base;
    Jscr=max(0,d.SCR_crit/max(d.grid_scr,1e-9)-1)*ones(nt,1);
    vq=abs(imag(Vibr(:,j).*exp(-1i*angle_ibr(:,j))));
    Jlock=vq/d.dvq_base; Jgra=1-GRA(:,j);
    raw=(Jv+Jf+Jr+Jp+Jscr+Jlock+Jgra)/7;
    raw_index(:,j)=raw; index(:,j)=min(1,max(0,raw));
end

o=struct(); o.tgrid=t; o.ibr_buses=r.device_bus_ids(didx);
o.index=index; o.index_raw=raw_index; o.GRA=GRA; o.ref_code=ref_code;
o.mode=double(strcmpi(modes,"gfm"));
o.P_ibr=r.device_P_pu(didx,:).'; o.Q_ibr=r.device_Q_pu(didx,:).';
o.id_ibr=real(Idq); o.iq_ibr=imag(Idq); o.f_ibr=f_ibr;
o.ang_ibr=wrap_pi(angle_ibr-busang); o.Vbus=abs(Vibr); o.Vmin=min(abs(V),[],1).';
o.sg_P=r.device_P_pu(1,:).'; o.sg_Q=r.device_Q_pu(1,:).';
o.sg_id=sg_id; o.sg_iq=sg_iq; o.f_sg=60*(1+sg_omega);
sgbp=find(r.bus_ids==r.device_bus_ids(1),1);
o.sg_delta=wrap_pi(sg_delta-unwrap(angle(V(sgbp,:))).');
o.sg_bus=r.device_bus_ids(1);
o.agsi_up=sys.devs{1}.AGSI_up; o.agsi_down=sys.devs{1}.AGSI_down;
o.sg_trip_time=r.sched.sg_trip; o.step_on=r.sched.load_step;
o.fault_on=r.sched.fault_on; o.fault_clear=r.sched.fault_clear;
o.line_trip_time=r.sched.line_trip; o.sg_reclose_time=r.sched.restore_time;
o.actual_reclose_time=r.actual_reclose_time;
o.diverged=~r.converged; o.newton_all_converged=r.converged;
if isfield(r,'accepted_residual_per_step') && any(isfinite(r.accepted_residual_per_step))
    o.max_step_residual=max(r.accepted_residual_per_step(isfinite(r.accepted_residual_per_step)));
else
    o.max_step_residual=max(r.residual_per_step);
end
o.max_attempt_residual=max(r.residual_per_step); o.subdivision_depth=r.subdivision_depth;
o.failure_id=r.failure_id; o.event_log=r.event_log; o.sample_side=r.sample_side(:);
o.reclose_status=r.reclose_status; o.reselection_status=r.reselection_status;
o.last_synchronism_guard=r.last_synchronism_guard;
o.production_result_fingerprint=r.fingerprint;
end

function f=angle_frequency(t,a,f0)
f=f0*ones(size(a));
for j=1:size(a,2)
    last=0;
    for k=2:numel(t)
        h=t(k)-t(k-1);
        if h>10*eps(max(1,abs(t(k))))
            last=(a(k,j)-a(k-1,j))/(2*pi*h);
        end
        f(k,j)=f0+last;
    end
    if numel(t)>1, f(1,j)=f(2,j); end
end
end

function rf=filtered_rate(t,f,tau)
rf=zeros(size(f)); raw=0;
for k=2:numel(t)
    h=t(k)-t(k-1);
    if h>10*eps(max(1,abs(t(k))))
        raw=(f(k)-f(k-1))/h;
        a=min(1,h/tau); rf(k)=rf(k-1)+a*(raw-rf(k-1));
    else
        rf(k)=rf(k-1);
    end
end
end

function a=wrap_pi(a)
a=mod(a+pi,2*pi)-pi;
end

function write_event_table(o,outdir)
fid=fopen(fullfile(outdir,'table_event_timeline.tex'),'w');
cleaner=onCleanup(@()fclose(fid));
fprintf(fid,'%% Generated from the accepted production event log.\n');
fprintf(fid,'\\begin{tabularx}{\\textwidth}{@{}r p{0.15\\textwidth} p{0.14\\textwidth} p{0.19\\textwidth} X@{}}\\toprule\n');
fprintf(fid,'Time (s) & Event / index & Timer & Mode before $\\to$ after & Reason \\\\ \\midrule\n');
for k=1:numel(o.event_log)
    e=o.event_log(k); left=find(abs(o.tgrid-e.t)<1e-9 & ~strcmp(o.sample_side,'right'),1,'last');
    right=find(abs(o.tgrid-e.t)<1e-9 & strcmp(o.sample_side,'right'),1,'last');
    if isempty(left), left=find(o.tgrid<=e.t,1,'last'); end
    if isempty(right), right=find(o.tgrid>=e.t,1,'first'); end
    mb=mode_word(o.mode(left,:)); ma=mode_word(o.mode(right,:));
    idx=max(o.index(left,:)); timer='--';
    if strcmp(e.type,'sg_trip'), timer='reference-loss guard'; end
    if strcmp(e.type,'sg_reclose'), timer='0.5-s sync dwell'; end
    reason=event_reason(e.type);
    fprintf(fid,'%.3f & %s / %.3f & %s & %s $\\to$ %s & %s \\\\\n', ...
        e.t,event_label(e.type),idx,timer,mb,ma,reason);
end
fprintf(fid,'\\bottomrule\\end{tabularx}\n'); clear cleaner
end

function s=event_label(type)
switch type
    case 'sg_trip', s='SG trip';
    case 'load_step', s='load step';
    case 'fault_on', s='fault on';
    case 'fault_clear', s='fault clear';
    case 'line_trip', s='line trip';
    case 'topology_restore', s='topology restore';
    case 'sg_on', s='SG close request';
    case 'sg_reclose', s='SG reclose';
    otherwise, s=strrep(type,'_',' ');
end
end

function s=event_reason(type)
switch type
    case 'sg_trip', s='SG opened; atomic all-GFM reference-security commit';
    case 'load_step', s='base constant-impedance load increased';
    case 'fault_on', s='bus-9 shunt fault applied';
    case 'fault_clear', s='fault admittance removed';
    case 'line_trip', s='line 6--13 opened';
    case 'topology_restore', s='base load and line restored';
    case 'sg_on', s='earliest close request; guard monitored';
    case 'sg_reclose', s='guard passed; SG reference handback';
    otherwise, s=strrep(type,'_','\_');
end
end

function s=mode_word(m)
if all(m==0), s='all GFL'; elseif all(m==1), s='all GFM'; else, s='mixed'; end
end

function supervisor_figure(o,outdir,filename,figure_title)
t=o.tgrid; buses=o.ibr_buses; c=lines(numel(buses));
f=figure('Color','w','Units','inches','Position',[1 1 5.90 6.35], ...
    'Visible','off','DefaultAxesFontName','Times New Roman', ...
    'DefaultAxesFontSize',11,'DefaultTextFontName','Times New Roman', ...
    'DefaultTextFontSize',11,'DefaultLegendFontName','Times New Roman', ...
    'DefaultLegendFontSize',10);
tl=tiledlayout(f,4,2,'TileSpacing','compact','Padding','compact');
title(tl,figure_title, ...
    'FontName','Times New Roman','FontSize',11,'FontWeight','bold');

ax=nexttile(tl,[1 2]); hold(ax,'on');
for j=1:numel(buses)
    plot(ax,t,o.index(:,j),'Color',c(j,:),'LineWidth',1.0, ...
        'DisplayName',sprintf('IBR%d (bus %d)',j,buses(j)));
end
yline(ax,o.agsi_up,'k-','\Gamma_{on}','LineWidth',1.0,'HandleVisibility','off');
yline(ax,o.agsi_down,'k--','\Gamma_{off}','LineWidth',1.0,'HandleVisibility','off');
ylabel(ax,'AGSI++ [-]'); event_lines(ax,o,true); grid(ax,'on'); box(ax,'on');
legend(ax,'Location','northoutside','NumColumns',4);

ax=nexttile(tl); stairs(ax,t,o.GRA(:,1),'k-','LineWidth',1.3); grid(ax,'on'); box(ax,'on');
ylim(ax,[-0.1 1.1]); yticks(ax,[0 1]); yticklabels(ax,{'missing','available'});
ylabel(ax,'GRA'); event_lines(ax,o,false);

ax=nexttile(tl); stairs(ax,t,o.ref_code,'Color',[.35 .15 .55],'LineWidth',1.8); grid(ax,'on'); box(ax,'on');
ylim(ax,[-1.2 4.2]); yticks(ax,-1:4); yticklabels(ax,{'none','SG','IBR1','IBR2','IBR3','IBR4'});
ylabel(ax,'reference owner'); title(ax,'Reference owner','FontSize',11);
if any(o.ref_code==1)
    kk=find(o.ref_code==1); tm=mean([t(kk(1)) t(kk(end))]);
    text(ax,tm,1.45,'IBR1 is reference leader','HorizontalAlignment','center', ...
        'Color',[.35 .15 .55],'FontWeight','bold','FontSize',10);
end
event_lines(ax,o,false);

for j=1:numel(buses)
    ax=nexttile(tl); lw=1.4; if j==1, lw=2.0; end
    stairs(ax,t,o.mode(:,j),'Color',c(j,:),'LineWidth',lw); grid(ax,'on'); box(ax,'on');
    ylim(ax,[-0.1 1.1]); yticks(ax,[0 1]); yticklabels(ax,{'GFL','GFM'});
    ylabel(ax,sprintf('IBR%d bus %d',j,buses(j)));
    if j==1, title(ax,'Reference leader while SG is open','FontSize',10); end
    event_lines(ax,o,false);
    if j>2, xlabel(ax,'time (s)'); end
end
export_figure(f,outdir,filename);
end

function response_figure(o,outdir,filename,figure_title)
t=o.tgrid; buses=o.ibr_buses; c=lines(numel(buses));
f=figure('Color','w','Units','inches','Position',[1 1 5.90 5.15], ...
    'Visible','off','DefaultAxesFontName','Times New Roman', ...
    'DefaultAxesFontSize',11,'DefaultTextFontName','Times New Roman', ...
    'DefaultTextFontSize',11,'DefaultLegendFontName','Times New Roman', ...
    'DefaultLegendFontSize',9);
tl=tiledlayout(f,2,2,'TileSpacing','compact','Padding','compact');
title(tl,figure_title, ...
    'FontName','Times New Roman','FontSize',11,'FontWeight','bold');
h=panel(nexttile(tl),t,o.P_ibr,c,buses,'P (pu)','(a) Active power');
panel(nexttile(tl),t,o.Q_ibr,c,buses,'Q (pu)','(b) Reactive power');
panel(nexttile(tl),t,o.Vbus,c,buses,'|V| (pu)','(c) PCC voltage');
panel(nexttile(tl),t,o.f_ibr,c,buses,'f (Hz)','(d) PLL / virtual-rotor frequency');
for ax=findall(f,'Type','axes').'
    event_lines(ax,o,false); xlabel(ax,'time (s)');
end
lg=legend(h, ...
    arrayfun(@(j)sprintf('IBR%d bus %d',j,buses(j)),1:numel(buses),'UniformOutput',false), ...
    'Orientation','horizontal','NumColumns',4);
lg.Layout.Tile='south';
set(lg,'FontName','Times New Roman','FontSize',9);
export_figure(f,outdir,filename);
end

function electrical_figure(o,outdir,filename,figure_title) %#ok<INUSD>
t=o.tgrid; buses=o.ibr_buses; c=lines(numel(buses));
f=figure('Color','w','Units','inches','Position',[1 1 5.90 7.60], ...
    'Visible','off','DefaultAxesFontName','Times New Roman', ...
    'DefaultAxesFontSize',11,'DefaultTextFontName','Times New Roman', ...
    'DefaultTextFontSize',11,'DefaultLegendFontName','Times New Roman', ...
    'DefaultLegendFontSize',9);
tl=tiledlayout(f,4,2,'TileSpacing','compact','Padding','compact');
title(tl,'Production response -- raw result plus display-only measurement ripple', ...
    'FontName','Times New Roman','FontSize',11,'FontWeight','bold');
ax=nexttile(tl); h=panel_noise(ax,t,o.P_ibr,c,'P (pu)','(a) Active power',8e-3,4901);
hsg=sg_overlay(ax,t,o.sg_P,8e-3,4911);
ax=nexttile(tl); panel_noise(ax,t,o.Q_ibr,c,'Q (pu)','(b) Reactive power',8e-3,4902);
sg_overlay(ax,t,o.sg_Q,8e-3,4912);
ax=nexttile(tl); panel_noise(ax,t,o.id_ibr,c,'i_d (pu)','(c) d-axis current',8e-3,4903);
sg_overlay(ax,t,o.sg_id,8e-3,4913);
ax=nexttile(tl); panel_noise(ax,t,o.iq_ibr,c,'i_q (pu)','(d) q-axis current',8e-3,4904);
sg_overlay(ax,t,o.sg_iq,8e-3,4914);
ax=nexttile(tl); panel_noise(ax,t,o.f_ibr,c,'f (Hz)','(e) PCC / virtual-rotor frequency',3e-2,4905);
sg_overlay(ax,t,o.f_sg,3e-2,4915);
ax=nexttile(tl); panel_noise(ax,t,o.ang_ibr*180/pi,c,'angle (deg)','(f) device-to-PCC angle',3e-1,4906);
sg_overlay(ax,t,o.sg_delta*180/pi,3e-1,4916);
panel_noise(nexttile(tl),t,o.Vbus,c,'|V| (pu)','(g) PCC voltage',3e-3,4907);
panel_noise(nexttile(tl),t,o.Vmin,[.15 .15 .15],'min |V| (pu)','(h) Network minimum voltage',3e-3,4908);
for ax=findall(f,'Type','axes').'
    event_lines(ax,o,false); xlabel(ax,'time (s)');
end
names=arrayfun(@(j)sprintf('IBR%d bus %d',j,buses(j)), ...
    1:numel(buses),'UniformOutput',false);
lg=legend([h hsg],[names {sprintf('SG bus %d',o.sg_bus)}], ...
    'Orientation','horizontal','NumColumns',5);
lg.Layout.Tile='south'; set(lg,'FontName','Times New Roman','FontSize',9);
export_figure(f,outdir,filename);
end

function angle_figure(o,outdir,filename)
t=o.tgrid; buses=o.ibr_buses; c=lines(numel(buses));
f=figure('Color','w','Units','inches','Position',[1 1 5.90 3.90], ...
    'Visible','off','DefaultAxesFontName','Times New Roman', ...
    'DefaultAxesFontSize',11,'DefaultTextFontName','Times New Roman', ...
    'DefaultTextFontSize',11,'DefaultLegendFontName','Times New Roman', ...
    'DefaultLegendFontSize',9);
tl=tiledlayout(f,2,1,'TileSpacing','compact','Padding','compact');
title(tl,'Device-to-PCC electrical-angle detail (wrapped reporting coordinates)', ...
    'FontName','Times New Roman','FontSize',11,'FontWeight','bold');
ax=nexttile(tl); plot(ax,t,o.sg_delta*180/pi,'k--','LineWidth',0.9); grid(ax,'on'); box(ax,'on');
ylabel(ax,'SG angle (deg)'); title(ax,'(a) SG rotor-to-terminal angle','FontSize',11);
event_lines(ax,o,false);
ax=nexttile(tl); hold(ax,'on');
for j=1:numel(buses), plot(ax,t,o.ang_ibr(:,j)*180/pi,'Color',c(j,:),'LineWidth',0.8); end
grid(ax,'on'); box(ax,'on'); ylabel(ax,'IBR angle (deg)'); xlabel(ax,'time (s)');
title(ax,'(b) IBR internal/PCC-frame angle','FontSize',11); event_lines(ax,o,false);
lg=legend(ax,arrayfun(@(j)sprintf('IBR%d bus %d',j,buses(j)),1:numel(buses),'UniformOutput',false), ...
    'Orientation','horizontal','NumColumns',4,'Location','southoutside');
set(lg,'FontName','Times New Roman','FontSize',9);
export_figure(f,outdir,filename);
end

function timeline_figure(o,outdir,filename)
% Phase H: single-row horizontal event timeline.  The markers are taken from
% the accepted event log (the same source as the numeric Table 3 record), so
% the diagram is a visual companion to the table, not a separate schedule.
ev=o.event_log;
kinds=string({ev.type});
modeK={'sg_trip','sg_reclose','sg_on'};
% Vertical lane per event: 1 = reference/mode events, 2 = disturbances.
lane=zeros(1,numel(ev));
for k=1:numel(ev)
    if any(strcmp(kinds(k),modeK)), lane(k)=1; else, lane(k)=2; end
end
% Spread events that land within 0.4 s of one another onto an open lane so the
% markers do not overlap (the 0.15-s fault window is the dense cluster).
for i=1:numel(ev)
    for j=i+1:numel(ev)
        if abs(ev(i).t-ev(j).t)<0.4 && lane(i)==lane(j)
            lane(j)=3-lane(j);
        end
    end
end
yrange=[0 3];
f=figure('Color','w','Units','inches','Position',[1 1 8.90 2.10], ...
    'Visible','off','DefaultAxesFontName','Times New Roman', ...
    'DefaultAxesFontSize',12,'DefaultTextFontName','Times New Roman', ...
    'DefaultTextFontSize',12);
ax=gca(f);
hold(ax,'on');
plot(ax,[0 o.event_contract.T_end],[1 1],'k-','LineWidth',1.8);
xlim(ax,[0 o.event_contract.T_end]); ylim(ax,yrange);
ax.YTick=1; ax.YTickLabel={'model'};
xlabel(ax,'time (s)');
title(ax,'IEEE 14-bus switching event timeline','FontName','Times New Roman','FontSize',12);
cmap=[0.13 0.43 0.78; 0.84 0.30 0.24];
for k=1:numel(ev)
    l=lane(k);
    plot(ax,ev(k).t,l,'o','MarkerFaceColor',cmap(mod(l-1,2)+1,:), ...
        'MarkerEdgeColor','k','MarkerSize',7);
    text(ax,ev(k).t,l+0.32,sprintf('%s: %.3f s',event_label(kinds(k)),ev(k).t), ...
        'HorizontalAlignment','center','VerticalAlignment','bottom', ...
        'FontName','Times New Roman','FontSize',7,'Color',[0.1 0.1 0.1]);
end
hold(ax,'off'); box(ax,'on');
export_figure(f,outdir,filename);
end

function export_figure(f,outdir,filename)
% Write the report raster at 1:1 physical size and an editable MATLAB .fig
% companion beside it, so panels can be reopened and adjusted without rerunning
% the 200-s transient.  Presentation only: no solver or gate reads these files.
exportgraphics(f,fullfile(outdir,filename),'Resolution',220);
[~,stem]=fileparts(filename);
savefig(f,fullfile(outdir,[stem '.fig']));
close(f);
end

function h=panel_noise(ax,t,y,c,ylab,ttl,sigma,seed)
hold(ax,'on'); grid(ax,'on'); box(ax,'on');
rr=display_ripple(t,size(y,2),sigma,seed);
for j=1:size(y,2)
    % The solid trace is the unmodified production result.  The dotted trace
    % is an explicitly labelled measurement-style presentation layer.
    h(j)=plot(ax,t,y(:,j),'Color',c(j,:),'LineWidth',0.95); %#ok<AGROW>
    plot(ax,t,y(:,j)+rr(:,j),':','Color',c(j,:),'LineWidth',0.55, ...
        'HandleVisibility','off');
end
ylabel(ax,ylab); title(ax,ttl,'FontSize',11,'FontWeight','bold');
end

function h=sg_overlay(ax,t,y,sigma,seed)
h=plot(ax,t,y,'k--','LineWidth',1.05);
rr=display_ripple(t,1,sigma,seed);
plot(ax,t,y+rr,'k:','LineWidth',0.55,'HandleVisibility','off');
end

function r=display_ripple(t,nc,sigma,seed)
% Band-limited, continuous-in-time display ripple.  Equal timestamps receive
% equal perturbations, so the presentation layer cannot create vertical
% event spikes.  It is never returned to the solver or supervisory logic.
stream=RandStream('mt19937ar','Seed',seed);
r=zeros(numel(t),nc);
freq=[0.43 0.79 1.31];
for j=1:nc
    phase=2*pi*rand(stream,1,numel(freq));
    amp=randn(stream,1,numel(freq)); amp=amp/max(norm(amp),eps);
    for q=1:numel(freq)
        r(:,j)=r(:,j)+amp(q)*sin(2*pi*freq(q)*t+phase(q));
    end
end
r=sigma*r;
end

function h=panel(ax,t,y,c,buses,ylab,ttl)
hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for j=1:numel(buses), h(j)=plot(ax,t,y(:,j),'Color',c(j,:),'LineWidth',0.85); end %#ok<AGROW>
ylabel(ax,ylab); title(ax,ttl,'FontSize',11,'FontWeight','bold');
end

function event_lines(ax,o,show_labels)
if nargin<3, show_labels=false; end
if show_labels
    labels={'SG trip','load +20%','fault','clear','line 6-13 trip','restore','close'};
else
    labels=repmat({''},1,7);
end
xline(ax,o.sg_trip_time,':',labels{1},'Color',[.15 .15 .15],'LineWidth',0.8, ...
    'LabelVerticalAlignment','bottom','HandleVisibility','off');
xline(ax,o.step_on,':',labels{2},'Color',[.55 .15 .55],'LineWidth',0.8, ...
    'LabelVerticalAlignment','top','HandleVisibility','off');
xline(ax,o.fault_on,':',labels{3},'Color',[.75 .10 .10],'LineWidth',0.8, ...
    'LabelVerticalAlignment','top','HandleVisibility','off');
xline(ax,o.fault_clear,':',labels{4},'Color',[.75 .10 .10],'LineWidth',0.8, ...
    'LabelVerticalAlignment','bottom','HandleVisibility','off');
xline(ax,o.line_trip_time,':',labels{5},'Color',[.80 .45 .05],'LineWidth',0.8, ...
    'LabelVerticalAlignment','top','HandleVisibility','off');
xline(ax,o.sg_reclose_time,':',labels{6},'Color',[.10 .35 .65],'LineWidth',0.8, ...
    'LabelVerticalAlignment','bottom','HandleVisibility','off');
if isfinite(o.actual_reclose_time)
    xline(ax,o.actual_reclose_time,'-.',labels{7},'Color',[.05 .50 .38],'LineWidth',0.9, ...
        'LabelVerticalAlignment','top','HandleVisibility','off');
end
if isfield(o,'requested_horizon_s') && o.tgrid(end)<o.requested_horizon_s
    xline(ax,o.tgrid(end),'r-','validity exit','LineWidth',1.0, ...
        'LabelVerticalAlignment','middle','HandleVisibility','off');
end
xlim(ax,[o.tgrid(1) o.tgrid(end)]);
end

function write_pf_tables(pf,outdir)
bus=table(pf.external_bus_ids(:),pf.bus_type(:),pf.bus_voltage(:), ...
    pf.bus_angle_deg(:),pf.P_generation(:),pf.Q_generation(:), ...
    pf.P_load(:),pf.Q_load(:),'VariableNames', ...
    {'bus','type','V_pu','angle_deg','Pg_pu','Qg_pu','Pl_pu','Ql_pu'});
writetable(bus,fullfile(outdir,'pf_bus_results.csv'));
fid=fopen(fullfile(outdir,'table_pf_bus_results.tex'),'w'); cleaner=onCleanup(@()fclose(fid));
fprintf(fid,'%% Generated by scripts/reporting/generate_ieee14_switch_report_figures.m.\n');
fprintf(fid,'\\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}rlrrrrrr@{}}\\toprule\nBus & Type & $|V|$ & $\\theta$ (deg) & $P_g$ & $Q_g$ & $P_L$ & $Q_L$ \\\\ \\midrule\n');
for k=1:height(bus)
    v=[bus.V_pu(k),bus.angle_deg(k),bus.Pg_pu(k),bus.Qg_pu(k),bus.Pl_pu(k),bus.Ql_pu(k)];
    v(abs(v)<0.5e-5)=0; % suppress signed zero at the published precision
    fprintf(fid,'%d & %s & %.5f & %.4f & %.5f & %.5f & %.5f & %.5f \\\\\n', ...
        bus.bus(k),type_name(bus.type(k)),v(1),v(2),v(3),v(4),v(5),v(6));
end
fprintf(fid,'\\bottomrule\\end{tabular*}\n'); clear cleaner

ep=pf.line_endpoints; line=table((1:size(ep,1)).',ep(:,1),ep(:,2), ...
    pf.line_flow_P(:),pf.line_flow_Q(:),pf.line_loss_P(:),pf.line_loss_Q(:), ...
    'VariableNames',{'line','from_bus','to_bus','P_from_pu','Q_from_pu','P_loss_pu','Q_loss_pu'});
writetable(line,fullfile(outdir,'pf_line_results.csv'));
fid=fopen(fullfile(outdir,'table_pf_line_results.tex'),'w'); cleaner=onCleanup(@()fclose(fid));
fprintf(fid,'%% Generated by scripts/reporting/generate_ieee14_switch_report_figures.m.\n');
fprintf(fid,'\\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}rrrrrrr@{}}\\toprule\nLine & From & To & $P_{from}$ & $Q_{from}$ & $P_{loss}$ & $Q_{loss}$ \\\\ \\midrule\n');
for k=1:height(line)
    v=[line.P_from_pu(k),line.Q_from_pu(k),line.P_loss_pu(k),line.Q_loss_pu(k)];
    v(abs(v)<0.5e-6)=0; % suppress signed zero at the published precision
    fprintf(fid,'%d & %d & %d & %.6f & %.6f & %.6f & %.6f \\\\\n', ...
        line.line(k),line.from_bus(k),line.to_bus(k),v(1),v(2),v(3),v(4));
end
fprintf(fid,'\\bottomrule\\end{tabular*}\n'); clear cleaner
end

function s=type_name(t)
if t==1, s='REF'; elseif t==2, s='PV'; elseif t==3, s='PQ'; else, s='?'; end
end
