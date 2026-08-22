function summary = generate_ieee14_handback_comparison()
%GENERATE_IEEE14_HANDBACK_COMPARISON Raw baseline/improved handback evidence.
% Reporting-only producer. No value computed here feeds PF, SSSA, TDS, a
% selector, a controller, or an acceptance decision in the production path.

pf_init_paths();
baseline_file = fullfile('output','diagnostics', ...
    'engine_release_400s_baseline.mat');
improved_file = fullfile('output','diagnostics', ...
    'engine_release_250s_improved_result.mat');
out_dir = fullfile('output','diagnostics');
tex_dir = fullfile('docs','source','figures','switch_ieee14');
if ~exist(tex_dir,'dir'), mkdir(tex_dir); end

baseline = load_result(baseline_file);
improved = load_result(improved_file);
if ~improved.converged || isempty(improved.t) || improved.t(end) < 250-1e-9
    error('generate_ieee14_handback_comparison:improvedIncomplete', ...
        'Improved evidence is not a converged 250-s result.');
end

detail = struct();
detail.schema = 'ieee14_handback_comparison/1.0';
detail.classification = struct( ...
    'model_inputs','CASE_DEFINED', ...
    'metrics','ASSUMED_DIAGNOSTIC', ...
    'raw_trajectory_policy','NUMERICAL_METHOD');
detail.baseline = summarize_run(baseline,'baseline');
detail.improved = summarize_run(improved,'improved');
detail.pre_request = pre_request_comparison(baseline,improved,145.0);
detail.windows = compare_windows(detail.baseline,detail.improved,[20 60]);
detail.gates = evaluate_frozen_gates(detail);
detail.baseline_file = baseline_file;
detail.improved_file = improved_file;
detail.generated_utc = char(datetime('now','TimeZone','UTC', ...
    'Format','yyyy-MM-dd''T''HH:mm:ssXXX'));

comparison_figure(detail,fullfile(tex_dir,'handback_before_after.png'));
summary=compact_summary(detail);
save(fullfile(out_dir,'engine_release_handback_comparison.mat'), ...
    'summary','-v7.3');
write_json(summary,fullfile(out_dir,'engine_release_handback_comparison.json'));
write_log(summary,fullfile(out_dir,'engine_release_handback_comparison.log'));
write_tex(summary,fullfile(tex_dir,'handback_comparison_summary.tex'), ...
    fullfile(tex_dir,'handback_comparison_macros.tex'));
fprintf('IEEE14_HANDBACK_COMPARISON_DONE: %s\n', ...
    fullfile(out_dir,'engine_release_handback_comparison.mat'));
end

function s=compact_summary(s)
% Keep machine-readable evidence compact; raw trajectories remain solely in
% the two authenticated source artifacts named in this record.
drop={'t','V','V0','f','Vmin','Vmax','mode_t','modes','sg_online'};
for run={'baseline','improved'}
    name=run{1};
    for k=1:numel(drop)
        if isfield(s.(name),drop{k}), s.(name)=rmfield(s.(name),drop{k}); end
    end
end
end

function r = load_result(file)
if ~exist(file,'file')
    error('generate_ieee14_handback_comparison:missingArtifact', ...
        'Required artifact is missing: %s',file);
end
s=load(file,'r');
if ~isfield(s,'r') || ~isstruct(s.r)
    error('generate_ieee14_handback_comparison:badArtifact', ...
        'Artifact %s does not contain result struct r.',file);
end
r=s.r;
required={'t','y_traj','device_P_pu','device_Q_pu','device_currents', ...
    'coi_frequency_Hz','device_modes_history','device_online_history', ...
    'sample_side','event_log'};
for k=1:numel(required)
    if ~isfield(r,required{k})
        error('generate_ieee14_handback_comparison:missingField', ...
            '%s lacks required field %s.',file,required{k});
    end
end
end

function o = summarize_run(r,label)
[t,keep]=right_continuous_samples(r.t,r.sample_side);
Y=r.y_traj(:,keep);
V=complex(Y(1:2:end,:),Y(2:2:end,:));
Vmag=abs(V).';
f=r.coi_frequency_Hz(keep).';
if isfield(r,'actual_reclose_time')
    tr=r.actual_reclose_time;
else
    tr=event_time(r.event_log,'sg_reclose');
end
if ~isfinite(tr), tr=event_time(r.event_log,'sg_reclose'); end

V0=abs(complex(r.y_traj(1:2:end,1),r.y_traj(2:2:end,1))).';
o=struct('label',label,'converged',logical(r.converged), ...
    't_end',t(end),'t',t,'V',Vmag,'V0',V0,'f',f, ...
    'Vmin',min(Vmag,[],2),'Vmax',max(Vmag,[],2), ...
    'reclose_time',tr);
o.closing=closing_audit(r,tr);
o.mode_t=t;
o.modes=string(r.device_modes_history(2:5,keep)).';
o.sg_online=logical(r.device_online_history(1,keep)).';
o.windows=window_metrics(o,[20 60]);
o.settling_1s=settling_time(o,1.0);
o.settling_10s=settling_time(o,10.0);
o.checkpoints=checkpoint_metrics(o,[200 225 250]);
if isfield(r,'accepted_residual_per_step')
    z=r.accepted_residual_per_step;
    z=z(isfinite(z));
    if isempty(z), o.max_accepted_residual=NaN; else, o.max_accepted_residual=max(z); end
else
    o.max_accepted_residual=NaN;
end
if isfield(r,'subdivision_depth'), o.subdivision_depth=r.subdivision_depth; else, o.subdivision_depth=NaN; end
if isfield(r,'domain_rejected_trials'), o.domain_rejected_trials=r.domain_rejected_trials; else, o.domain_rejected_trials=NaN; end
o.release_events=event_times(r.event_log,'sg_reselection',true);
end

function [t,keep] = right_continuous_samples(t0,side)
% At duplicate event times, retain the committed right limit. Otherwise
% retain the last accepted sample. No interpolation, smoothing or filtering.
t0=t0(:); side=string(side(:));
[ut,~,grp]=unique(t0,'stable');
keep=zeros(numel(ut),1);
for k=1:numel(ut)
    q=find(grp==k);
    qr=q(side(q)=="right");
    if isempty(qr), keep(k)=q(end); else, keep(k)=qr(end); end
end
t=t0(keep);
end

function a = closing_audit(r,tr)
a=struct('available',false,'t',tr,'delta_P',NaN,'delta_Q',NaN, ...
    'delta_I',NaN,'delta_u_norm',NaN,'P_left',NaN,'P_right',NaN, ...
    'Q_left',NaN,'Q_right',NaN,'I_left',NaN,'I_right',NaN);
if ~isfinite(tr), return; end
tol=1e-9;
left=find(abs(r.t-tr)<=tol & string(r.sample_side)~="right",1,'last');
right=find(abs(r.t-tr)<=tol & string(r.sample_side)=="right",1,'last');
if isempty(left) || isempty(right), return; end
a.available=true;
a.P_left=r.device_P_pu(1,left); a.P_right=r.device_P_pu(1,right);
a.Q_left=r.device_Q_pu(1,left); a.Q_right=r.device_Q_pu(1,right);
a.I_left=abs(r.device_currents(1,left)); a.I_right=abs(r.device_currents(1,right));
a.delta_P=abs(a.P_right-a.P_left);
a.delta_Q=abs(a.Q_right-a.Q_left);
a.delta_I=abs(a.I_right-a.I_left);
if isfield(r,'u_history')
    a.delta_u_norm=norm(r.u_history(:,right)-r.u_history(:,left),inf);
end
end

function w = window_metrics(o,durations)
w=repmat(struct('duration',NaN,'complete',false,'peak_V',NaN, ...
    'peak_f',NaN,'iae_V',NaN,'iae_f',NaN,'tv_V',NaN,'tv_f',NaN), ...
    1,numel(durations));
for j=1:numel(durations)
    d=durations(j); w(j).duration=d;
    if ~isfinite(o.reclose_time) || o.t(end)<o.reclose_time+d-1e-9, continue; end
    q=o.t>=o.reclose_time-1e-12 & o.t<=o.reclose_time+d+1e-12;
    tw=o.t(q); vdev=max(abs(o.V(q,:)-o.V0),[],2); fdev=abs(o.f(q)-60);
    w(j).complete=true;
    w(j).peak_V=max(vdev); w(j).peak_f=max(fdev);
    w(j).iae_V=trapz(tw,vdev); w(j).iae_f=trapz(tw,fdev);
    w(j).tv_V=sum(abs(diff(vdev))); w(j).tv_f=sum(abs(diff(o.f(q))));
end
end

function s = settling_time(o,dwell)
% Earliest post-reclose time after which all bus voltages and COI frequency
% remain in the diagnostic band through the accepted end of the trajectory.
s=struct('dwell',dwell,'settled',false,'time',NaN, ...
    'absolute_time',NaN,'status','NOT_SETTLED_BY_END');
if ~isfinite(o.reclose_time), s.status='NO_RECLOSE'; return; end
inside=all(abs(o.V-o.V0)<=0.01,2) & abs(o.f-60)<=0.1;
q=find(o.t>=o.reclose_time & inside);
for kk=1:numel(q)
    k=q(kk);
    if o.t(end)-o.t(k)<dwell-1e-9, continue; end
    if all(inside(k:end))
        s.settled=true; s.absolute_time=o.t(k);
        s.time=o.t(k)-o.reclose_time; s.status='SETTLED_THROUGH_END';
        return;
    end
end
end

function c = checkpoint_metrics(o,times)
c=repmat(struct('requested_time',NaN,'available',false,'time',NaN, ...
    'Vmin',NaN,'Vmax',NaN,'f',NaN,'n_gfm',NaN),1,numel(times));
for j=1:numel(times)
    c(j).requested_time=times(j);
    k=find(o.t>=times(j)-1e-9,1);
    if isempty(k), continue; end
    c(j).available=true; c(j).time=o.t(k);
    c(j).Vmin=o.Vmin(k); c(j).Vmax=o.Vmax(k); c(j).f=o.f(k);
    c(j).n_gfm=sum(o.modes(k,:)=="gfm");
end
end

function p = pre_request_comparison(a,b,t_request)
[ta,ka]=right_continuous_samples(a.t,a.sample_side);
[tb,kb]=right_continuous_samples(b.t,b.sample_side);
common=intersect(ta(ta<t_request),tb(tb<t_request),'stable');
p=struct('request_time',t_request,'n_common',numel(common), ...
    'max_abs_y',NaN,'max_abs_x',NaN,'max_abs_P',NaN, ...
    'max_abs_Q',NaN,'max_abs_I',NaN,'comparison_tolerance',NaN, ...
    'identical_to_contract',false);
if isempty(common), return; end
[~,ia]=ismember(common,ta); [~,ib]=ismember(common,tb);
ia=ka(ia); ib=kb(ib);
p.max_abs_y=max(abs(a.y_traj(:,ia)-b.y_traj(:,ib)),[],'all');
p.max_abs_x=max(abs(a.x_traj(:,ia)-b.x_traj(:,ib)),[],'all');
p.max_abs_P=max(abs(a.device_P_pu(:,ia)-b.device_P_pu(:,ib)),[],'all');
p.max_abs_Q=max(abs(a.device_Q_pu(:,ia)-b.device_Q_pu(:,ib)),[],'all');
p.max_abs_I=max(abs(a.device_currents(:,ia)-b.device_currents(:,ib)),[],'all');
ra=max_finite_accepted_residual(a); rb=max_finite_accepted_residual(b);
tol=max([100*eps(max(1,max(abs([a.x_traj(:);b.x_traj(:)])))), ...
    10*ra,10*rb]);
p.comparison_tolerance=tol;
p.identical_to_contract=all([p.max_abs_y p.max_abs_x p.max_abs_P ...
    p.max_abs_Q p.max_abs_I]<=tol);
end

function v=max_finite_accepted_residual(r)
v=0;
if isfield(r,'accepted_residual_per_step')
    z=r.accepted_residual_per_step; z=z(isfinite(z));
    if ~isempty(z), v=max(z); end
end
end

function c = compare_windows(a,b,durations)
c=repmat(struct('duration',NaN,'available',false, ...
    'peak_V_change',NaN,'peak_f_change',NaN,'iae_V_change',NaN, ...
    'iae_f_change',NaN,'tv_V_change',NaN,'tv_f_change',NaN),1,numel(durations));
for j=1:numel(durations)
    c(j).duration=durations(j);
    wa=a.windows(j); wb=b.windows(j);
    if ~(wa.complete && wb.complete), continue; end
    c(j).available=true;
    names={'peak_V','peak_f','iae_V','iae_f','tv_V','tv_f'};
    for k=1:numel(names)
        c(j).([names{k} '_change'])=wb.(names{k})-wa.(names{k});
    end
end
end

function g = evaluate_frozen_gates(s)
g=struct();
g.pre_request_equal=s.pre_request.identical_to_contract;
ca=s.baseline.closing; cb=s.improved.closing;
g.closing_available=ca.available && cb.available;
g.closing_nonincrease=false; g.closing_one_strictly_reduced=false;
if g.closing_available
    av=[ca.delta_P ca.delta_Q ca.delta_I]; bv=[cb.delta_P cb.delta_Q cb.delta_I];
    g.closing_nonincrease=all(bv<=av+1e-12);
    g.closing_one_strictly_reduced=any(bv<av-1e-12);
end
g.window_nonincrease=false(1,numel(s.windows));
g.window_one_peak_or_iae_reduced=false(1,numel(s.windows));
for j=1:numel(s.windows)
    w=s.windows(j);
    if ~w.available, continue; end
    q=[w.peak_V_change w.peak_f_change w.iae_V_change ...
        w.iae_f_change w.tv_V_change w.tv_f_change];
    g.window_nonincrease(j)=all(q<=1e-12);
    g.window_one_peak_or_iae_reduced(j)=any(q(1:4)<-1e-12);
end
g.pass=g.pre_request_equal && g.closing_nonincrease && ...
    g.closing_one_strictly_reduced && all(g.window_nonincrease) && ...
    all(g.window_one_peak_or_iae_reduced);
end

function comparison_figure(s,file)
f=figure('Color','w','Units','inches','Position',[1 1 6.2 5.4], ...
    'Visible','off','DefaultAxesFontName','Times New Roman', ...
    'DefaultAxesFontSize',11,'DefaultTextFontName','Times New Roman', ...
    'DefaultTextFontSize',11,'DefaultLegendFontName','Times New Roman', ...
    'DefaultLegendFontSize',11);
tl=tiledlayout(f,3,1,'TileSpacing','compact','Padding','compact');
title(tl,'Raw accepted response relative to each SG reclose', ...
    'FontName','Times New Roman','FontSize',11,'FontWeight','bold');
names={'Baseline','Improved'}; R={s.baseline,s.improved}; C={[.45 .45 .45],[.00 .35 .70]};
ax=nexttile(tl); hold(ax,'on');
for k=1:2
    q=R{k}.t>=R{k}.reclose_time-5 & R{k}.t<=min(R{k}.t(end),R{k}.reclose_time+60);
    plot(ax,R{k}.t(q)-R{k}.reclose_time,R{k}.Vmin(q),'Color',C{k}, ...
        'LineWidth',1,'DisplayName',names{k});
end
ylabel(ax,'min |V| (pu)'); grid(ax,'on'); box(ax,'on'); legend(ax,'Location','best');
ax=nexttile(tl); hold(ax,'on');
for k=1:2
    q=R{k}.t>=R{k}.reclose_time-5 & R{k}.t<=min(R{k}.t(end),R{k}.reclose_time+60);
    plot(ax,R{k}.t(q)-R{k}.reclose_time,R{k}.f(q),'Color',C{k},'LineWidth',1);
end
ylabel(ax,'COI f (Hz)'); grid(ax,'on'); box(ax,'on');
ax=nexttile(tl); hold(ax,'on');
for k=1:2
    q=R{k}.mode_t>=R{k}.reclose_time-5 & R{k}.mode_t<=min(R{k}.mode_t(end),R{k}.reclose_time+60);
    stairs(ax,R{k}.mode_t(q)-R{k}.reclose_time,sum(R{k}.modes(q,:)=="gfm",2), ...
        'Color',C{k},'LineWidth',1.2);
end
ylabel(ax,'GFM count'); xlabel(ax,'time from SG reclose (s)');
ylim(ax,[-.2 4.2]); yticks(ax,0:4); grid(ax,'on'); box(ax,'on');
exportgraphics(f,file,'Resolution',300); close(f);
end

function write_tex(s,file,macro_file)
fid=fopen(macro_file,'w'); guard=onCleanup(@()fclose(fid));
fprintf(fid,'%% Generated from raw accepted baseline and improved trajectories.\n');
fprintf(fid,'\\newcommand{\\CmpBaselineEnd}{%.3f}\n',s.baseline.t_end);
fprintf(fid,'\\newcommand{\\CmpImprovedEnd}{%.3f}\n',s.improved.t_end);
fprintf(fid,'\\newcommand{\\CmpBaselineReclose}{%s}\n',tex_num(s.baseline.reclose_time));
fprintf(fid,'\\newcommand{\\CmpImprovedReclose}{%s}\n',tex_num(s.improved.reclose_time));
fprintf(fid,'\\newcommand{\\CmpBaselineDU}{%s}\n',tex_sci(s.baseline.closing.delta_u_norm));
fprintf(fid,'\\newcommand{\\CmpImprovedDU}{%s}\n',tex_sci(s.improved.closing.delta_u_norm));
fprintf(fid,'\\newcommand{\\CmpImprovedSettleOne}{%s}\n',settle_tex(s.improved.settling_1s));
fprintf(fid,'\\newcommand{\\CmpImprovedSettleTen}{%s}\n',settle_tex(s.improved.settling_10s));
fprintf(fid,'\\newcommand{\\CmpGateStatus}{%s}\n',ternary(s.gates.pass,'PASS','FAIL-CLOSED'));
clear guard

fid=fopen(file,'w'); guard=onCleanup(@()fclose(fid));
fprintf(fid,'%% Generated raw accepted before/after metrics.\n');
fprintf(fid,'\\begin{tabular}{@{}lrrrr@{}}\\toprule\n');
fprintf(fid,'Window & Metric & Baseline & Improved & Change \\\\ \\midrule\n');
for j=1:numel(s.windows)
    d=s.windows(j).duration; a=s.baseline.windows(j); b=s.improved.windows(j);
    fields={'peak_V','peak_f','iae_V','iae_f','tv_V','tv_f'};
    labels={'peak $|\\Delta V|$ (pu)','peak $|\\Delta f|$ (Hz)', ...
        '$\\mathrm{IAE}_V$ (pu s)','$\\mathrm{IAE}_f$ (Hz s)', ...
        '$\\mathrm{TV}_V$ (pu)','$\\mathrm{TV}_f$ (Hz)'};
    for k=1:numel(fields)
        fprintf(fid,'%g s & %s & %s & %s & %s \\\\ \n',d,labels{k}, ...
            tex_sci(a.(fields{k})),tex_sci(b.(fields{k})), ...
            tex_sci(b.(fields{k})-a.(fields{k})));
    end
end
fprintf(fid,'\\bottomrule\\end{tabular}\n'); clear guard
end

function write_log(s,file)
fid=fopen(file,'w'); guard=onCleanup(@()fclose(fid));
fprintf(fid,'schema=%s generated_utc=%s\n',s.schema,s.generated_utc);
fprintf(fid,'baseline converged=%d end=%.6f reclose=%.6f\n', ...
    s.baseline.converged,s.baseline.t_end,s.baseline.reclose_time);
fprintf(fid,'improved converged=%d end=%.6f reclose=%.6f\n', ...
    s.improved.converged,s.improved.t_end,s.improved.reclose_time);
fprintf(fid,'pre_request_equal=%d max_y=%.12g max_x=%.12g\n', ...
    s.pre_request.identical_to_contract,s.pre_request.max_abs_y,s.pre_request.max_abs_x);
fprintf(fid,'pre_request_tolerance=%.12g\n',s.pre_request.comparison_tolerance);
fprintf(fid,'gate=%s\n',ternary(s.gates.pass,'PASS','FAIL_CLOSED'));
for j=1:numel(s.windows)
    w=s.windows(j);
    fprintf(fid,['window=%.0f available=%d d_peak_V=%.12g d_peak_f=%.12g ' ...
        'd_IAE_V=%.12g d_IAE_f=%.12g d_TV_V=%.12g d_TV_f=%.12g\n'], ...
        w.duration,w.available,w.peak_V_change,w.peak_f_change, ...
        w.iae_V_change,w.iae_f_change,w.tv_V_change,w.tv_f_change);
end
clear guard
end

function write_json(s,file)
fid=fopen(file,'w'); guard=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(s,'PrettyPrint',true)); clear guard
end

function t=event_time(log,type)
t=NaN; q=find(strcmp({log.type},type) & [log.applied],1,'last');
if ~isempty(q), t=log(q).t; end
end

function t=event_times(log,type,applied)
q=strcmp({log.type},type);
if applied, q=q & [log.applied]; end
t=[log(q).t];
end

function s=tex_sci(v)
if ~isfinite(v), s='--'; return; end
if v==0, s='$0$'; return; end
e=floor(log10(abs(v))); a=v/10^e;
s=sprintf('$%+.4f\\times10^{%d}$',a,e);
end

function s=tex_num(v)
if isfinite(v), s=sprintf('%.3f',v); else, s='not reached'; end
end

function s=settle_tex(x)
if x.settled, s=sprintf('%.3f',x.time); else, s='NOT\\_SETTLED\\_BY\\_250S'; end
end

function y=ternary(q,a,b)
if q, y=a; else, y=b; end
end
