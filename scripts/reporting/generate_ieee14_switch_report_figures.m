function out = generate_ieee14_switch_report_figures(opts)
%GENERATE_IEEE14_SWITCH_REPORT_FIGURES Reproduce publishable IEEE14 evidence.
%   The full-state profile is simulated by the production all-KCL hybrid
%   engine: six-state EMF6 SG, registered full-state dual-mode IBR devices,
%   exact event landing, synchronism guard, and two-phase SG handback.
%   The per-IBR index is reconstructed from accepted raw production signals as
%   S=sat(0.5*J_V+0.5*J_f), using the healthy SG-online PF voltage at each bus.
%   The SG-trip transaction commits the authenticated selector result. Reclose returns
%   reference ownership to the SG without changing IBR modes; each remaining
%   GFM then releases independently after S<Gamma_off for T_d_off. Figures
%   contain raw accepted signals only: no synthetic ripple, smoothing, or
%   filtering is applied.

arguments
    opts.reuse_cache (1,1) logical = false
end

pf_init_paths();
outdir = fullfile('docs','source','figures','switch_ieee14');
if ~exist(outdir,'dir'), mkdir(outdir); end

sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp", ...
    case_profile="eecon49_figure4", sg_H=2.5, sg_D=1.0, ...
    T_d_on=0.10, T_d_off=1.0);
% PF tables carry Q_min/Q_max (pf struct), P_max (from the case), and the
% bus_role labels so inverter buses read as GFL rather than plain PQ.
case_for_tables = cases.case_ieee14bus_eecon49_switch();
lim = pf_limit_table(case_for_tables);
write_pf_tables(sys.pf,outdir,lim,case_for_tables.bus_role);
% The presentation run is the user-approved 250-s diagnostic horizon. The
% physical case/event chronology is unchanged; only the observation endpoint
% is extended beyond the case's historical 200-s report default.
T_end_contract=250.0;
production_cache=fullfile('output','diagnostics','engine_release_result.mat');
figure_cache=fullfile('output','diagnostics', ...
    sprintf('ieee14_switch_%g_exact.mat',T_end_contract));
reuse_ok=false;
if opts.reuse_cache && exist(production_cache,'file')
    cached=load(production_cache,'r'); r=cached.r;
    % Phase G guard: a cache produced under a shorter horizon must never be
    % presented as evidence for the current contract.  Fail closed instead of
    % silently reusing a truncated trajectory.
    cache_types=string({r.equilibrium.devices(2:5).device_type});
    horizon_ok=r.converged && r.t(end) >= T_end_contract - 1e-9;
    model_ok=all(cache_types=="ibr_eecon49_dual");
    reuse_ok=horizon_ok && model_ok;
    if ~horizon_ok
        error('generate_ieee14_switch_report_figures:staleCacheHorizon', ...
            ['Cached run ends at %.6f s but the case contract requires %g s. ', ...
             'Rerun with reuse_cache=false to regenerate the trajectory.'], ...
            r.t(end),T_end_contract);
    elseif ~model_ok
        error('generate_ieee14_switch_report_figures:staleCacheModel', ...
            'Cached run uses IBR type(s) %s, not the current production model.', ...
            strjoin(unique(cache_types),','));
    end
    selector_cache=fullfile('output','diagnostics','automatic_selector_table.mat');
    if ~exist(selector_cache,'file')
        error('generate_ieee14_switch_report_figures:missingSelectorEvidence', ...
            'Generate the authenticated SSSA/selector tables before the report figures.');
    end
    sd=load(selector_cache,'tbl');
    transient_selector_fp='';
    if isfield(r,'selector_table_fingerprint')
        transient_selector_fp=char(r.selector_table_fingerprint);
    elseif isfield(r,'metadata') && isstruct(r.metadata) && ...
            isfield(r.metadata,'selector_table_fingerprint')
        % Older wrapper revisions preserved the exact production fingerprint
        % in metadata but omitted the additive top-level copy.
        transient_selector_fp=char(r.metadata.selector_table_fingerprint);
    end
    if isempty(transient_selector_fp) || ...
            ~isfield(sd.tbl,'selector_table_fingerprint') || ...
            ~strcmp(transient_selector_fp,char(sd.tbl.selector_table_fingerprint))
        error('generate_ieee14_switch_report_figures:selectorFingerprintMismatch', ...
            'Transient and SSSA selector evidence do not share one authenticated fingerprint.');
    end
end
if ~reuse_ok
    [scenario,opt]=production_request(sys,T_end_contract);
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
out.presentation_noise=struct('kind','none', ...
    'seed_base',NaN,'affects_solver_or_switching',false);
if out.diverged || ~out.newton_all_converged || out.tgrid(end)<T_end
    out.dynamic_status='DIAGNOSTIC_PREFIX_ONLY_FAIL_CLOSED';
    figure_title=sprintf('Diagnostic raw prefix to %.3f s (requested %g s; fail-closed)', ...
        out.tgrid(end),T_end);
else
    out.dynamic_status=sprintf('FULL_%g_S_GATE_PASSED',T_end);
    figure_title=sprintf('Production all-KCL response: full %g-s chronology',T_end);
end
write_event_table(out,outdir);
write_run_summary(out,outdir);
tag=sprintf('%g',T_end);
event_timeline_figure(out,outdir,'ieee14_switch_250_event_timeline.png');
supervisor_figure(out,outdir,['ieee14_switch_' tag '_supervisor.png'],figure_title);
electrical_figure(out,outdir,['ieee14_switch_' tag '_electrical.png'],figure_title);
angle_figure(out,outdir,['ieee14_switch_' tag '_angles.png']);
fprintf('IEEE14_SWITCH_REPORT_FIGURES_DONE: %s [%s]\n',outdir,out.dynamic_status);
end

function [s,opt]=production_request(sys,T_end_contract)
s=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
ev=struct('enabled',true,'event_profile','chronology', ...
    'sg_trip',20,'load_step',50,'load_step_factor',0.20, ...
    'fault_on',85,'fault_clear',85.15,'fault_bus',9,'Zf',0.01+0.01i, ...
    'line_trip',110,'line_from_bus',6,'line_to_bus',13, ...
    'restore_time',145,'sg_on',145,'coordinated_handback',false, ...
    'automatic_gfm_switching',true, ...
    'delays_overrides',struct('timeout_s',20,'dwell_s',0.5));
% Reporting horizon only. All event times remain owned by the case/event
% contract above and are identical to the baseline chronology.
% Step size: the physically-correct reduced converter model (command-delay
% states removed, v_del=v_cmd; defect TD-2026-08-12-01) no longer carries the
% retired placeholder T_d=0.02 s lag that had incidentally low-pass-filtered
% the commanded voltage into the stiff AC-filter current dynamics.  At the
% bolted bus-9 fault (Zf=0.01+0.01i) the discontinuous command jump now needs
% dt<=0.05 to resolve; a fixed-dt sweep confirms dt=0.10 stalls at fault onset
% while dt in {0.05,0.02,0.01,0.005} all integrate to t_end.  dt=0.05 is a
% NUMERICAL_METHOD accuracy/stability choice, not model tuning.
opt=struct('t_end',T_end_contract, ...
    'dt',0.05,'verbose',false, ...
    'ibr_events',ev,'plot_results',false, ...
    'max_step_subdivisions',9, ...
    'state_predictor','linear_kcl', ...
    'automatic_support_supervision',true, ...
    'severity_gamma_on',0.65,'severity_gamma_off',0.35, ...
    'severity_T_d_on',0.10,'severity_T_d_off',1.00, ...
    'healthy_pf_V',sys.pf.bus_voltage(:).', ...
    'healthy_pf_bus_ids',sys.pf.external_bus_ids(:).');
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
uoff=[0 cumsum([devs.nu])];
modes=string(r.device_modes_history(didx,:)).';
angle_ibr=busang; f_ibr=busfreq;
for j=1:nibr
    d=devs(didx(j));
    xr=r.x_traj(xoff(didx(j))+(1:d.nx),:).';
    ui=uoff(didx(j))+(1:d.nu);
    for k=1:nt
        rec=d.reconstruct(t(k),xr(k,:).',r.y_traj(:,k), ...
            r.u_history(ui,k),r.event_context_history{k});
        if isfield(rec,'gfm')
            angle_ibr(k,j)=rec.gfm.delta_VSM;
            f_ibr(k,j)=60*(1+rec.gfm.omega_m);
        elseif isfield(rec,'gfl')
            angle_ibr(k,j)=rec.gfl.delta_PLL;
            f_ibr(k,j)=rec.gfl.f_hz;
        end
    end
end

Iibr=r.device_currents(didx,:).';
Idq=Iibr.*exp(-1i*angle_ibr);
sg_delta=r.x_traj(1,:).'; sg_omega=r.x_traj(2,:).';
sg_id=zeros(nt,1); sg_iq=zeros(nt,1);
sg=devs(1);
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
    ibr_bus_id=r.device_bus_ids(didx(j));
    ref_idx=find(sys.pf.external_bus_ids==ibr_bus_id);
    if numel(ref_idx)~=1
        error('generate_ieee14_switch_report_figures:healthyPfReference', ...
            'IBR bus %d does not map uniquely to the healthy PF profile.',ibr_bus_id);
    end
    vref=sys.pf.bus_voltage(ref_idx);
    Jv=abs(Vmag-vref)/d.dV_base;
    if ~isfield(r,'coi_frequency_Hz') || numel(r.coi_frequency_Hz)~=nt || ...
            any(~isfinite(r.coi_frequency_Hz(:)))
        error('generate_ieee14_switch_report_figures:coiFrequency', ...
            'The production trajectory lacks complete finite COI-frequency evidence.');
    end
    Jf=abs(r.coi_frequency_Hz(:)-d.f0)/d.df_base;
    Jr=abs(rocof)/d.dR_base;
    Jp=abs(d.u(1)-r.device_P_pu(didx(j),:).')/d.dP_base;
    Jscr=max(0,d.SCR_crit/max(d.grid_scr,1e-9)-1)*ones(nt,1);
    vq=abs(imag(Vibr(:,j).*exp(-1i*angle_ibr(:,j))));
    Jlock=vq/d.dvq_base; Jgra=1-GRA(:,j);
    % 2026-08-09: the implemented per-IBR supervisor index (ibr.SwitchableIbr6,
    % index_mode='agsi_pp') is the two-term severity S=0.5*J_V+0.5*J_f on bases
    % dV=0.10 pu / df=0.50 Hz (the frozen equal V/f weighting). The other
    % five former terms are measured diagnostics with zero weight; applicable
    % admissibility checks remain separate, never tradeable severity terms.
    % The previous equal 1/7 average diluted J_V/J_f and is NOT what the engine
    % evaluates.  Keep the raw stress (weighted sum) as a diagnostic field.
    raw=0.5*Jv+0.5*Jf;
    raw_index(:,j)=raw; index(:,j)=min(1,max(0,raw));
end

o=struct(); o.tgrid=t; o.ibr_buses=r.device_bus_ids(didx);
o.index=index; o.index_raw=raw_index; o.GRA=GRA; o.ref_code=ref_code;
o.mode=double(strcmpi(modes,"gfm"));
o.final_gfm_positions=find(strcmpi(modes(end,:),"gfm"));
o.final_gfm_buses=o.ibr_buses(o.final_gfm_positions);
o.P_ibr=r.device_P_pu(didx,:).'; o.Q_ibr=r.device_Q_pu(didx,:).';
o.id_ibr=real(Idq); o.iq_ibr=imag(Idq); o.f_ibr=f_ibr;
o.ang_ibr=wrap_pi(angle_ibr-busang); o.Vbus=abs(Vibr); o.Vmin=min(abs(V),[],1).';
o.sg_P=r.device_P_pu(1,:).'; o.sg_Q=r.device_Q_pu(1,:).';
o.sg_id=sg_id; o.sg_iq=sg_iq; o.f_sg=60*(1+sg_omega);
sgbp=find(r.bus_ids==r.device_bus_ids(1),1);
o.sg_delta=wrap_pi(sg_delta-unwrap(angle(V(sgbp,:))).');
o.f_coi=r.coi_frequency_Hz(:);
o.VnetworkMin=min(abs(V),[],1).';
o.VnetworkMax=max(abs(V),[],1).';
o.sg_bus=r.device_bus_ids(1);
o.agsi_up=sys.devs{1}.AGSI_up; o.agsi_down=sys.devs{1}.AGSI_down;
o.sg_trip_time=r.sched.sg_trip; o.step_on=r.sched.load_step;
o.fault_on=r.sched.fault_on; o.fault_clear=r.sched.fault_clear;
o.line_trip_time=r.sched.line_trip; o.sg_reclose_time=r.sched.restore_time;
o.actual_reclose_time=r.actual_reclose_time;
o.actual_mode_reselection_time=r.actual_mode_reselection_time;
release_mask=strcmp({r.event_log.type},'sg_reselection') & [r.event_log.applied];
o.release_times=[r.event_log(release_mask).t];
all_gfl=find(t>=o.actual_reclose_time & all(strcmpi(modes,"gfl"),2),1);
o.final_all_gfl_time=NaN;
if ~isempty(all_gfl), o.final_all_gfl_time=t(all_gfl); end
o.diverged=~r.converged; o.newton_all_converged=r.converged;
if isfield(r,'accepted_residual_per_step') && any(isfinite(r.accepted_residual_per_step))
    o.max_step_residual=max(r.accepted_residual_per_step(isfinite(r.accepted_residual_per_step)));
else
    o.max_step_residual=max(r.residual_per_step);
end
o.max_attempt_residual=max(r.residual_per_step); o.subdivision_depth=r.subdivision_depth;
o.domain_rejected_trials=r.domain_rejected_trials;
o.failure_id=r.failure_id; o.event_log=r.event_log; o.sample_side=r.sample_side(:);
o.reclose_status=r.reclose_status; o.reselection_status=r.reselection_status;
o.handback_status='not available'; o.handback_duration_s=NaN;
o.handback_complete_time=NaN;
if isfield(r,'handback_status'), o.handback_status=char(string(r.handback_status)); end
if isfield(r,'handback_duration_s'), o.handback_duration_s=r.handback_duration_s; end
if isfield(r,'handback_complete_time'), o.handback_complete_time=r.handback_complete_time; end
o.last_synchronism_guard=r.last_synchronism_guard;
o.reclose_guard=struct();
reclose_event=find(strcmp({r.event_log.type},'sg_reclose') & [r.event_log.applied],1,'last');
if ~isempty(reclose_event) && isfield(r.event_log(reclose_event),'guard')
    o.reclose_guard=r.event_log(reclose_event).guard;
end
o.production_result_fingerprint=r.fingerprint;
end

function write_run_summary(o,outdir)
fid=fopen(fullfile(outdir,'run_summary.tex'),'w');
cleaner=onCleanup(@()fclose(fid));
fprintf(fid,'%% Generated from output/diagnostics/engine_release_result.mat.\n');
fprintf(fid,'\\newcommand{\\RunEnd}{%.3f}\n',o.tgrid(end));
fprintf(fid,'\\newcommand{\\RunVMin}{%.6f}\n',min(o.VnetworkMin));
fprintf(fid,'\\newcommand{\\RunVMax}{%.6f}\n',max(o.VnetworkMax));
fprintf(fid,'\\newcommand{\\RunFMin}{%.6f}\n',min(o.f_coi));
fprintf(fid,'\\newcommand{\\RunFMax}{%.6f}\n',max(o.f_coi));
fprintf(fid,'\\newcommand{\\RunSubdivision}{%d}\n',o.subdivision_depth);
fprintf(fid,'\\newcommand{\\RunDomainRejects}{%d}\n',o.domain_rejected_trials);
fprintf(fid,'\\newcommand{\\RunResidual}{%s}\n',latex_scientific(o.max_step_residual));
fprintf(fid,'\\newcommand{\\RunReclose}{%s}\n',latex_scalar(o.actual_reclose_time));
fprintf(fid,'\\newcommand{\\RunFirstRelease}{%s}\n',latex_scalar(o.actual_mode_reselection_time));
fprintf(fid,'\\newcommand{\\RunRelease}{%s}\n',latex_scalar(o.final_all_gfl_time));
fprintf(fid,'\\newcommand{\\RunFinalRelease}{%s}\n',latex_scalar(o.final_all_gfl_time));
fprintf(fid,'\\newcommand{\\RunFinalGFMCount}{%d}\n',numel(o.final_gfm_positions));
fprintf(fid,'\\newcommand{\\RunFinalGFMBuses}{%s}\n', ...
    latex_vector(o.final_gfm_buses));
fprintf(fid,'\\newcommand{\\RunHandbackDuration}{%s}\n', ...
    latex_scalar(o.handback_duration_s));
fprintf(fid,'\\newcommand{\\RunHandbackComplete}{%s}\n', ...
    latex_scalar(o.handback_complete_time));
rt=nan(1,4); rt(1:min(4,numel(o.release_times)))=o.release_times(1:min(4,numel(o.release_times)));
names={'One','Two','Three','Four'};
for k=1:4
    fprintf(fid,'\\newcommand{\\RunRelease%s}{%s}\n',names{k},latex_scalar(rt(k)));
end
g=o.reclose_guard;
if isempty(fieldnames(g))
    error('generate_ieee14_switch_report_figures:missingRecloseGuard', ...
        'Successful reclose evidence lacks its committed transaction guard.');
end
fprintf(fid,'\\newcommand{\\RunSyncDV}{%.6f}\n',g.dV);
fprintf(fid,'\\newcommand{\\RunSyncDF}{%.6f}\n',g.df);
fprintf(fid,'\\newcommand{\\RunSyncDTheta}{%.6f}\n',g.dtheta);
if ~isfield(g,'prospective') || ~isstruct(g.prospective) || ...
        ~isfield(g.prospective,'passes')
    error('generate_ieee14_switch_report_figures:missingProspectiveAudit', ...
        'Successful reclose evidence lacks the prospective SG-close audit.');
end
p=g.prospective;
fprintf(fid,'\\newcommand{\\RunProsI}{%.6f}\n',p.I_abs_pu);
fprintf(fid,'\\newcommand{\\RunProsP}{%.6f}\n',p.P_pu);
fprintf(fid,'\\newcommand{\\RunProsQ}{%.6f}\n',p.Q_pu);
fprintf(fid,'\\newcommand{\\RunProsS}{%.6f}\n',p.S_abs_pu);
fprintf(fid,'\\newcommand{\\RunProsTorque}{%.6f}\n',p.torque_mismatch_pu);
fprintf(fid,'\\newcommand{\\RunProsImax}{%.6f}\n',p.current_limit_system_pu);
fprintf(fid,'\\newcommand{\\RunProsSmax}{%.6f}\n',p.rating_system_pu);
clear cleaner
end

function s=latex_scientific(v)
if ~isfinite(v), s='not available'; return; end
if v==0, s='$0$'; return; end
e=floor(log10(abs(v))); a=v/10^e;
s=sprintf('$%.4f\\times10^{%d}$',a,e);
end

function s=latex_scalar(v)
if isfinite(v), s=sprintf('%.3f',v); else, s='not reached'; end
end

function s=latex_vector(v)
if isempty(v), s='none'; return; end
s=strjoin(arrayfun(@(z)sprintf('%g',z),v,'UniformOutput',false),', ');
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
    if strcmp(e.type,'gfm_support_augment'), timer='0.1-s severity dwell'; end
    if strcmp(e.type,'gfm_support_release'), timer='1.0-s severity dwell'; end
    if strcmp(e.type,'sg_reclose'), timer='0.5-s sync dwell'; end
    if strcmp(e.type,'sg_reselection'), timer='1.0-s severity dwell'; end
    reason=event_reason(e.type);
    fprintf(fid,'%.3f & %s / %.3f & %s & %s $\\to$ %s & %s \\\\\n', ...
        e.t,event_label(e.type),idx,timer,mb,ma,reason);
end
fprintf(fid,'\\bottomrule\\end{tabularx}\n'); clear cleaner
end

function event_timeline_figure(o,outdir,filename)
% Presentation diagram derived only from the accepted event/mode history.
trip_t=log_event_time(o.event_log,'sg_trip');
support_t=log_event_time(o.event_log,'gfm_support_augment');
if ~isfinite(support_t), support_t=trip_t; end
trip_n=mode_count_at(o,trip_t); support_n=mode_count_at(o,support_t);
release_n=numel(o.release_times);
final_buses=latex_vector(o.final_gfm_buses);
labels={ ...
    sprintf('Initial\n0 s\nSG + 4 GFL'), ...
    sprintf('SG trip\n%s s\n%d GFM',fmt_time(trip_t),trip_n), ...
    sprintf('J_V/J_f support\n%s s\n%d GFM',fmt_time(support_t),support_n), ...
    sprintf('Load step\n%s s\n+20%%',fmt_time(o.step_on)), ...
    sprintf('Bus fault\n%s--%s s\nclear accepted',fmt_time(o.fault_on),fmt_time(o.fault_clear)), ...
    sprintf('Line trip\n%s s\n6--13 open',fmt_time(o.line_trip_time)), ...
    sprintf('Restore/request\n%s s\nbase topology',fmt_time(o.sg_reclose_time)), ...
    sprintf('SG reclose\n%s s\nC1 transfer',fmt_time(o.actual_reclose_time)), ...
    sprintf('Staged release\n%d transaction(s)\nfinal %d GFM: bus %s', ...
        release_n,numel(o.final_gfm_positions),final_buses)};

xy=[.65 3.00; 2.00 3.00; 3.35 3.00; ...
    3.35 1.85; 2.00 1.85; .65 1.85; ...
    .65 .70; 2.00 .70; 3.35 .70];
colors=[.10 .35 .70; .55 .20 .65; .20 .45 .80; ...
    .55 .20 .55; .78 .12 .12; .85 .48 .05; ...
    .10 .45 .75; .05 .55 .35; .15 .55 .20];
f=figure('Color','w','Units','inches','Position',[1 1 6.20 4.35], ...
    'Visible','off','DefaultAxesFontName','Times New Roman', ...
    'DefaultAxesFontSize',11,'DefaultTextFontName','Times New Roman', ...
    'DefaultTextFontSize',11);
ax=axes(f,'Position',[.03 .08 .94 .82]); hold(ax,'on'); axis(ax,'off');
xlim(ax,[0 4]); ylim(ax,[.20 3.55]); axis(ax,'manual');
title(ax,'Automatic GFL/GFM chronology from the accepted event log', ...
    'FontName','Times New Roman','FontSize',11,'FontWeight','bold');
for k=1:8
    timeline_arrow(ax,xy(k,:),xy(k+1,:));
end
r=.20;
for k=1:9
    face=.88+.12*colors(k,:);
    rectangle(ax,'Position',[xy(k,1)-r xy(k,2)-r 2*r 2*r], ...
        'Curvature',[1 1],'FaceColor',face,'EdgeColor',colors(k,:), ...
        'LineWidth',1.8);
    text(ax,xy(k,1),xy(k,2),sprintf('%d',k),'HorizontalAlignment','center', ...
        'VerticalAlignment','middle','FontWeight','bold','Color',colors(k,:));
    text(ax,xy(k,1),xy(k,2)-.27,labels{k},'HorizontalAlignment','center', ...
        'VerticalAlignment','top','FontSize',11,'Interpreter','tex');
end
export_figure(f,outdir,filename);
end

function timeline_arrow(ax,p0,p1)
d=p1-p0; u=d/norm(d); a=p0+.24*u; b=p1-.24*u; v=b-a;
quiver(ax,a(1),a(2),v(1),v(2),0,'Color',[.10 .30 .70], ...
    'LineWidth',1.3,'MaxHeadSize',.35,'AutoScale','off');
end

function t=log_event_time(log,type)
t=NaN; q=find(strcmp({log.type},type) & [log.applied],1,'first');
if ~isempty(q), t=log(q).t; end
end

function n=mode_count_at(o,t)
n=NaN; if ~isfinite(t), return; end
q=find(abs(o.tgrid-t)<1e-9 & strcmp(o.sample_side,'right'),1,'last');
if isempty(q), q=find(o.tgrid>=t-1e-9,1); end
if ~isempty(q), n=sum(o.mode(q,:)>0.5); end
end

function s=fmt_time(t)
if isfinite(t), s=sprintf('%.3f',t); else, s='not reached'; end
end

function s=event_label(type)
switch type
    case 'sg_trip', s='SG trip';
    case 'gfm_support_augment', s='GFM support add';
    case 'gfm_support_release', s='GFM support release';
    case 'load_step', s='load step';
    case 'fault_on', s='fault on';
    case 'fault_clear', s='fault clear';
    case 'line_trip', s='line trip';
    case 'topology_restore', s='topology restore';
    case 'sg_on', s='SG close request';
    case 'sg_reclose', s='SG reclose';
    case 'sg_reselection', s='severity release';
    otherwise, s=strrep(type,'_',' ');
end
end

function s=event_reason(type)
switch type
    case 'sg_trip', s='SG opened; authenticated selected-GFM transaction committed';
    case 'gfm_support_augment', s='SG-off severity high; feasible strict superset committed';
    case 'gfm_support_release', s='SG-off severity healthy; feasible nonempty subset committed';
    case 'load_step', s='base constant-impedance load increased';
    case 'fault_on', s='bus-9 shunt fault applied';
    case 'fault_clear', s='fault admittance removed';
    case 'line_trip', s='line 6--13 opened';
    case 'topology_restore', s='base load and line restored';
    case 'sg_on', s='earliest close request; guard monitored';
    case 'sg_reclose', s='guard passed; SG owns reference; IBR modes unchanged';
    case 'sg_reselection', s='severity, authenticated SG-online SSSA/reserve and KCL guards passed';
    otherwise, s=strrep(type,'_','\_');
end
end

function s=mode_word(m)
n=sum(m==1);
if n==0
    s='all GFL';
elseif n==numel(m)
    s='all GFM';
else
    s=sprintf('%d GFM / %d GFL',n,numel(m)-n);
end
end

function supervisor_figure(o,outdir,filename,figure_title)
t=o.tgrid; buses=o.ibr_buses; c=lines(numel(buses));
f=figure('Color','w','Units','inches','Position',[1 1 5.90 5.30], ...
    'Visible','off','DefaultAxesFontName','Times New Roman', ...
    'DefaultAxesFontSize',11,'DefaultTextFontName','Times New Roman', ...
    'DefaultTextFontSize',11,'DefaultLegendFontName','Times New Roman', ...
    'DefaultLegendFontSize',11);
tl=tiledlayout(f,3,2,'TileSpacing','compact','Padding','compact');
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
ibr_refs=unique(o.ref_code(o.ref_code>0)).';
for j=ibr_refs
    kk=find(o.ref_code==j); tm=mean([t(kk(1)) t(kk(end))]);
    text(ax,tm,max(-0.8,j-0.35),sprintf('IBR%d is reference leader',j), ...
        'HorizontalAlignment','center','Color',[.35 .15 .55], ...
        'FontWeight','bold','FontSize',11);
end
event_lines(ax,o,false);

% Single combined mode panel. Plot the exact 0/1 coordinates without display
% offsets; coincident device histories intentionally overlap.
ax=nexttile(tl,[1 2]); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
styles={'-','--',':','-.'};
lws=[2.0 1.6 1.9 1.6];
offs=zeros(1,numel(buses));
h=gobjects(1,numel(buses));
for j=1:numel(buses)
    h(j)=stairs(ax,t,o.mode(:,j)+offs(j),styles{j},'Color',c(j,:), ...
        'LineWidth',lws(j),'DisplayName',sprintf('IBR%d bus %d',j,buses(j)));
end
ylim(ax,[-0.22 1.22]); yticks(ax,[0 1]); yticklabels(ax,{'GFL','GFM'});
ylabel(ax,'device mode'); xlabel(ax,'time (s)');
title(ax,'Committed IBR modes','FontSize',11);
event_lines(ax,o,false);
lg=legend(ax,h,'Orientation','horizontal','NumColumns',4,'Location','northoutside');
set(lg,'FontName','Times New Roman','FontSize',11);
export_figure(f,outdir,filename);
end

function response_figure(o,outdir,filename,figure_title)
t=o.tgrid; buses=o.ibr_buses; c=lines(numel(buses));
f=figure('Color','w','Units','inches','Position',[1 1 5.90 5.15], ...
    'Visible','off','DefaultAxesFontName','Times New Roman', ...
    'DefaultAxesFontSize',11,'DefaultTextFontName','Times New Roman', ...
    'DefaultTextFontSize',11,'DefaultLegendFontName','Times New Roman', ...
    'DefaultLegendFontSize',11);
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
lg.Layout.Tile='north';
set(lg,'FontName','Times New Roman','FontSize',11);
export_figure(f,outdir,filename);
end

function electrical_figure(o,outdir,filename,figure_title) %#ok<INUSD>
t=o.tgrid; buses=o.ibr_buses; c=lines(numel(buses));
f=figure('Color','w','Units','inches','Position',[1 1 5.90 7.60], ...
    'Visible','off','DefaultAxesFontName','Times New Roman', ...
    'DefaultAxesFontSize',11,'DefaultTextFontName','Times New Roman', ...
    'DefaultTextFontSize',11,'DefaultLegendFontName','Times New Roman', ...
    'DefaultLegendFontSize',11);
tl=tiledlayout(f,4,2,'TileSpacing','compact','Padding','compact');
title(tl,'Production response -- raw accepted result', ...
    'FontName','Times New Roman','FontSize',11,'FontWeight','bold');
ax=nexttile(tl); h=panel_raw(ax,t,o.P_ibr,c,'P (pu)','(a) Active power');
hsg=sg_raw(ax,t,o.sg_P);
ax=nexttile(tl); panel_raw(ax,t,o.Q_ibr,c,'Q (pu)','(b) Reactive power');
sg_raw(ax,t,o.sg_Q);
ax=nexttile(tl); panel_raw(ax,t,o.id_ibr,c,'i_d (pu)','(c) d-axis current');
sg_raw(ax,t,o.sg_id);
ax=nexttile(tl); panel_raw(ax,t,o.iq_ibr,c,'i_q (pu)','(d) q-axis current');
sg_raw(ax,t,o.sg_iq);
ax=nexttile(tl); panel_raw(ax,t,o.f_ibr,c,'f (Hz)','(e) PCC / virtual-rotor frequency');
sg_raw(ax,t,o.f_sg);
ax=nexttile(tl); panel_raw(ax,t,o.ang_ibr*180/pi,c,'angle (deg)','(f) device-to-PCC angle');
sg_raw(ax,t,o.sg_delta*180/pi);
panel_raw(nexttile(tl),t,o.Vbus,c,'|V| (pu)','(g) PCC voltage');
panel_raw(nexttile(tl),t,o.Vmin,[.15 .15 .15],'min |V| (pu)','(h) Network minimum voltage');
for ax=findall(f,'Type','axes').'
    event_lines(ax,o,false); xlabel(ax,'time (s)');
end
names=arrayfun(@(j)sprintf('IBR%d bus %d',j,buses(j)), ...
    1:numel(buses),'UniformOutput',false);
lg=legend([h hsg],[names {sprintf('SG bus %d',o.sg_bus)}], ...
    'Orientation','horizontal','NumColumns',5);
lg.Layout.Tile='north'; set(lg,'FontName','Times New Roman','FontSize',11);
export_figure(f,outdir,filename);
end

function angle_figure(o,outdir,filename)
t=o.tgrid; buses=o.ibr_buses; c=lines(numel(buses));
f=figure('Color','w','Units','inches','Position',[1 1 5.90 3.90], ...
    'Visible','off','DefaultAxesFontName','Times New Roman', ...
    'DefaultAxesFontSize',11,'DefaultTextFontName','Times New Roman', ...
    'DefaultTextFontSize',11,'DefaultLegendFontName','Times New Roman', ...
    'DefaultLegendFontSize',11);
tl=tiledlayout(f,2,1,'TileSpacing','compact','Padding','compact');
title(tl,'Device-to-PCC electrical-angle detail (wrapped reporting coordinates)', ...
    'FontName','Times New Roman','FontSize',11,'FontWeight','bold');
ax=nexttile(tl); plot(ax,t,o.sg_delta*180/pi,'k--','LineWidth',0.9); grid(ax,'on'); box(ax,'on');
ylabel(ax,'SG angle (deg)'); title(ax,'(a) SG rotor-to-terminal angle','FontSize',11);
event_lines(ax,o,false);
ax=nexttile(tl); hold(ax,'on');
h=gobjects(1,numel(buses));
for j=1:numel(buses)
    h(j)=plot(ax,t,o.ang_ibr(:,j)*180/pi,'Color',c(j,:),'LineWidth',0.8, ...
        'DisplayName',sprintf('IBR%d bus %d',j,buses(j)));
end
grid(ax,'on'); box(ax,'on'); ylabel(ax,'IBR angle (deg)'); xlabel(ax,'time (s)');
title(ax,'(b) IBR internal/PCC-frame angle','FontSize',11); event_lines(ax,o,false);
% Attach the legend to the tiled layout, not to panel (b), so it sits at the
% very top of the figure instead of between the two panels.
lg=legend(h,'Orientation','horizontal','NumColumns',4);
lg.Layout.Tile='north';
set(lg,'FontName','Times New Roman','FontSize',11);
export_figure(f,outdir,filename);
end


function export_figure(f,outdir,filename)
% Write the report raster at 1:1 physical size and an editable MATLAB .fig
% companion beside it, so panels can be reopened and adjusted without rerunning
% the 250-s transient. Presentation only: no solver or gate reads these files.
exportgraphics(f,fullfile(outdir,filename),'Resolution',220);
[~,stem]=fileparts(filename);
savefig(f,fullfile(outdir,[stem '.fig']));
close(f);
end

function h=panel_raw(ax,t,y,c,ylab,ttl)
hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for j=1:size(y,2)
    % Low-alpha markers expose the density of the actual accepted samples.
    % They are not noise, smoothing, interpolation, or a synthetic envelope.
    scatter(ax,t,y(:,j),4,c(j,:),'filled','MarkerFaceAlpha',0.08, ...
        'MarkerEdgeAlpha',0.08,'HandleVisibility','off');
    h(j)=plot(ax,t,y(:,j),'Color',c(j,:),'LineWidth',0.60); %#ok<AGROW>
end
ylabel(ax,ylab); title(ax,ttl,'FontSize',11,'FontWeight','bold');
end

function h=sg_raw(ax,t,y)
scatter(ax,t,y,4,[.10 .10 .10],'filled','MarkerFaceAlpha',0.07, ...
    'MarkerEdgeAlpha',0.07,'HandleVisibility','off');
h=plot(ax,t,y,'k--','LineWidth',0.75);
end

function h=panel(ax,t,y,c,buses,ylab,ttl)
hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for j=1:numel(buses), h(j)=plot(ax,t,y(:,j),'Color',c(j,:),'LineWidth',0.85); end %#ok<AGROW>
ylabel(ax,ylab); title(ax,ttl,'FontSize',11,'FontWeight','bold');
end

function event_lines(ax,o,show_labels)
if nargin<3, show_labels=false; end
if show_labels
    labels={'SG trip','load +20%','fault','clear','line 6-13 trip','restore','close','release'};
else
    labels=repmat({''},1,8);
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
if isfinite(o.actual_mode_reselection_time)
    xline(ax,o.actual_mode_reselection_time,'--',labels{8},'Color',[.15 .55 .15],'LineWidth',0.9, ...
        'LabelVerticalAlignment','bottom','HandleVisibility','off');
end
if isfield(o,'requested_horizon_s') && o.tgrid(end)<o.requested_horizon_s
    xline(ax,o.tgrid(end),'r-','validity exit','LineWidth',1.0, ...
        'LabelVerticalAlignment','middle','HandleVisibility','off');
end
xlim(ax,[o.tgrid(1) o.tgrid(end)]);
end


% write_pf_tables lives in scripts/reporting/write_pf_tables.m so the tables
% can be regenerated without re-running the full transient.
