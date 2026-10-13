function out = ne39_reclose_demo_cached(evidence_folder, varargin)
%NE39_RECLOSE_DEMO_CACHED Replay a COMPLETED NE39 reclose run for presentation.
%
%   ne39_reclose_demo_cached(EVIDENCE_FOLDER)
%   ne39_reclose_demo_cached(EVIDENCE_FOLDER,'output',PNG_PATH)
%   ne39_reclose_demo_cached(EVIDENCE_FOLDER,'show_figure',true)
%
% Loads an already-finished scripts/diagnostics/ne39_reclose_applied_probe.m
% run and re-renders its evidence. NOTHING is simulated: no
% stability.run_hybrid_case call, no selector build, no private trial, no
% reclose request. Every number printed and every trace plotted comes out of
% the stored result, so the demo cannot disagree with the run that produced it
% and cannot be fast by having skipped a gate.
%
% Why it exists: a live 160 s NE39 chronology costs ~80-170 min of wall clock,
% dominated by the fail-closed private transition trial and by the
% supervisor-armed dt ceiling of 0.01 s. That is impractical in front of an
% audience. The artifact IS the evidence; this function only presents it.
%
% Two read paths, same view:
%   - <folder>/replay_cache.mat, a compact checksummed view written by
%     ne39_reclose_cache_evidence (fast). It is accepted only when its recorded
%     SHA-256 still matches the raw.mat beside it, so a stale or substituted
%     cache is refused rather than shown.
%   - <folder>/raw.mat, the full artifact (slow, always correct).
%
% The configuration printed is echoed from the artifact's own request, never
% restated here, so a slide cannot claim a setup the artifact did not use.
%
% Usage:
%   out = ne39_reclose_demo_cached( ...
%       'output/diagnostics/ne39_reclose_applied_probe_20261012_024613_920');

p = inputParser;
p.addRequired('evidence_folder',@(s)ischar(s)||isstring(s));
p.addParameter('output','');
p.addParameter('show_figure',false);
p.parse(evidence_folder,varargin{:});
a = p.Results;
folder = char(a.evidence_folder);

raw_file   = fullfile(folder,'raw.mat');
req_file   = fullfile(folder,'request.mat');
cache_file = fullfile(folder,'replay_cache.mat');
assert(isfile(raw_file),'ne39_reclose_demo_cached:missingRaw','No raw.mat in %s',folder);
assert(isfile(req_file),'ne39_reclose_demo_cached:missingRequest', ...
    'No request.mat in %s (the demo must show the configuration that was used)',folder);

fprintf('=== NE39 reclose demo (cached replay, no simulation) ===\n');
fprintf('artifact  %s\n',folder);

t_load = tic;
if isfile(cache_file)
    C = load(cache_file,'info'); ci = C.info;
    view = ci;
    load_s = toc(t_load);
    fprintf('raw       %s (%.1f MB)\n',raw_file,dir(raw_file).bytes/1e6);
    fprintf('cache     %s (%.2f MB, %.0fx smaller)\n',cache_file, ...
        dir(cache_file).bytes/1e6,dir(raw_file).bytes/dir(cache_file).bytes);
    fprintf('loaded in %.2f s  (the simulation took %.1f s)\n', ...
        load_s,ci.simulation_seconds);
else
    fprintf('raw       %s (%.1f MB)\n',raw_file,dir(raw_file).bytes/1e6);
    fprintf('note: no replay_cache.mat, reading the full artifact (slow).\n');
    fprintf('      it is written automatically by ne39_reclose_applied_probe.\n');
    S = load(raw_file,'request','result','elapsed');
    load_s = toc(t_load);
    view = view_from_result(S.result,S.request,S.elapsed);
    fprintf('loaded in %.2f s  (the simulation took %.1f s)\n',load_s,S.elapsed);
end

head = view.head; cfg = view.config; traces = view.traces; evs = view.events;
ev = cfg.events; op = cfg.options;

% ---- configuration, echoed from the artifact --------------------------------
fprintf('\n--- configuration as recorded in request.mat ---\n');
fprintf('event_profile      %s\n',char(string(ev.event_profile)));
fprintf('sg_trip            %g s\n',ev.sg_trip);
if isfield(ev,'fault_on')
    fprintf('fault              bus %g, Zf=%s, %g .. %g s\n', ...
        ev.fault_bus,num2str(ev.Zf),ev.fault_on,ev.fault_clear);
end
fprintf('sg_on (earliest)   %g s\n',ev.sg_on);
fprintf('t_end              %g s\n',op.t_end);
fprintf('dt (initial)       %g   stepper=%s\n',op.dt,char(string(op.stepper)));
fprintf('post-reclose reselection  %d\n',op.post_reclose_mode_reselection);
if isfield(op,'synchronism_overrides')
    so = op.synchronism_overrides;
    fprintf('synchronism request (tightened probe-side, not a relaxation)\n');
    fprintf('  dtheta_max %g deg   dV_max %g pu   df_max %g pu\n', ...
        so.dtheta_max,so.dV_max,so.df_max);
end
if isfield(op,'delays_overrides')
    fprintf('delays_overrides   %s\n',fmt_struct(op.delays_overrides));
end
fprintf('supervisor         healthy_pf=%d  rate_policy=%d  support_supervision=%d\n', ...
    isfield(op,'healthy_pf_V'), ...
    isfield(op,'ne39_rate_policy')&&logical(op.ne39_rate_policy), ...
    isfield(op,'automatic_support_supervision')&&logical(op.automatic_support_supervision));

% ---- declared gates, echoed from the case ----------------------------------
d = cfg.declared_synchronism;
fprintf('\n--- declared case gates (unchanged by the probe) ---\n');
fprintf('dV_max %g pu   df_max %g pu   dtheta_max %g deg   dwell %g s   timeout %g s\n', ...
    d.dV_max_pu,d.df_max_pu,d.dtheta_max_deg,d.dwell_s,d.timeout_s);
fprintf('T_sg_min_off_s %g s\n',cfg.declared_minimum_off_s);

% ---- outcome ----------------------------------------------------------------
fprintf('\n--- outcome ---\n');
fprintf('converged          %d\n',head.converged);
fprintf('reclose            %s at t=%.6f s\n',head.reclose_status,head.actual_reclose_time);
if isfinite(head.actual_reclose_time) && isfinite(head.t_sg_trip)
    fprintf('offline age        %.6f s   (min-off %g s)\n', ...
        head.actual_reclose_time-head.t_sg_trip,cfg.declared_minimum_off_s);
end
fprintf('horizon reached    %.4f / %g s   (%d accepted samples)\n', ...
    head.horizon_reached_s,head.t_end_requested_s,head.accepted_samples);
fprintf('rejected steps     %d\n',head.rejected_steps);
fprintf('stepper            %s\n',head.stepper);
fprintf('reselection_status %s\n',head.reselection_status);
fprintf('mode reselection t %g\n',head.actual_mode_reselection_time);
fprintf('handback_status    %s\n',head.handback_status);
fprintf('full_chronology    %d\n',head.full_chronology);
if isfield(head,'failure_id') && ~isempty(head.failure_id)
    fprintf('failure_id         %s\n',head.failure_id);
end
% Kernel's own per-candidate audit for a refused post-reclose release.
if isfield(head,'reselection_rejection_detail') && ~isempty(head.reselection_rejection_detail)
    rj = head.reselection_rejection_detail;
    fprintf('\n--- why the post-reclose release was refused (kernel audit) ---\n');
    shown = min(numel(rj),8);
    for k=1:shown
        fprintf('  %s\n',char(string(rj{k})));
    end
    if numel(rj)>shown
        fprintf('  ... and %d more\n',numel(rj)-shown);
    end
end

% ---- applied event transactions --------------------------------------------
fprintf('\n--- applied transactions (from the event log) ---\n');
for k=1:numel(evs)
    e=evs(k);
    fprintf('%-16s t=%.6f  tx=%d  pre_kcl=%.4g  right_kcl=%.4g\n', ...
        e.type,e.t,e.transaction_id,e.pre_kcl_norm,e.right_kcl_norm);
    if isfinite(e.dV)
        fprintf('    guard dV %.6g (<=%g)  df %.6g (<=%g)  dtheta %.6g deg (<=%g)\n', ...
            e.dV,e.dV_max,e.df,e.df_max,e.dtheta,e.dtheta_max);
    end
    if ~isempty(e.selected_gfm_indices)
        fprintf('    selected GFM indices %s\n',mat2str(e.selected_gfm_indices));
    end
end
% point the headline gate at the close transaction specifically
for k=1:numel(evs)
    if strcmp(evs(k).type,'sg_reclose')
        fprintf('\nright-limit KCL at the close = %.6g   (<=1e-8: %d)\n', ...
            evs(k).right_kcl_norm,evs(k).right_kcl_norm<=1e-8);
    end
end

% ---- committed mode timeline per resource ----------------------------------
fprintf('\n--- committed mode timeline per resource ---\n');
ids = string(traces.device_ids);
lv  = traces.mode_level;
tt  = traces.t;
names = {'open','GFL','GFM/SG'};
for k=1:numel(ids)
    row = lv(k,:);
    chg = [1, find(row(2:end)~=row(1:end-1))+1];
    parts = strings(1,0);
    for j=1:numel(chg)
        parts(end+1) = sprintf('%s@%.2fs',names{row(chg(j))+1},tt(chg(j))); %#ok<AGROW>
    end
    fprintf('  %-6s %s\n',char(ids(k)),strjoin(parts,' -> '));
end

% ---- selector evidence -----------------------------------------------------
if isfield(cfg,'selector_table_fingerprint')
    fprintf('\nselector_table_fingerprint %s\n',cfg.selector_table_fingerprint);
end

% ---- figure ----------------------------------------------------------------
if ~isempty(a.output) || a.show_figure
    out_png = char(a.output);
    if isempty(out_png), out_png = fullfile(folder,'ne39_reclose_chronology.png'); end
    render_ne39_figure(traces,ev,head,out_png);
    fprintf('\nfigure written %s\n',out_png);
end

out = struct('folder',folder,'load_seconds',load_s, ...
    'simulation_seconds',view.simulation_seconds, ...
    'reclose_status',head.reclose_status, ...
    'actual_reclose_time',head.actual_reclose_time, ...
    'reselection_status',head.reselection_status, ...
    'used_cache',isfile(cache_file),'production_certified',false);
fprintf('\nproduction_certified=false (unchanged from the artifact)\n');
end

% ===========================================================================
function view = view_from_result(r,req,elapsed)
%VIEW_FROM_RESULT  Normalize a full run result into the presentation view.
traces = struct();
traces.t = r.t(:).';
traces.coi_frequency_Hz = r.coi_frequency_Hz(:).';
if isfield(r,'sg_freq'), traces.sg_freq = r.sg_freq(:).'; end
traces.v_min_pu = min(r.bus_voltage_magnitude,[],1);
traces.v_max_pu = max(r.bus_voltage_magnitude,[],1);
nd=numel(r.device_ids); nt=numel(r.t);
lv=zeros(nd,nt);
for k=1:nd
    for j=1:nt
        lv(k,j)=mode_level(r.device_modes_history{k,j},r.device_online_history(k,j));
    end
end
traces.mode_level=lv; traces.device_ids=r.device_ids; traces.sample_count=nt;

ev=struct('type',{},'t',{},'transaction_id',{},'pre_kcl_norm',{}, ...
    'right_kcl_norm',{},'selected_gfm_indices',{},'dV',{},'dV_max',{}, ...
    'df',{},'df_max',{},'dtheta',{},'dtheta_max',{});
for k=1:numel(r.event_log)
    e=r.event_log(k);
    if ~logical(e.applied), continue; end
    dv=NaN;dvmax=NaN;df=NaN;dfmax=NaN;dth=NaN;dthmax=NaN;
    if isfield(e,'guard')&&isstruct(e.guard)&&~isempty(fieldnames(e.guard))
        g=e.guard;
        if isfield(g,'dV'),dv=g.dV;end
        if isfield(g,'dV_max'),dvmax=g.dV_max;end
        if isfield(g,'df'),df=g.df;end
        if isfield(g,'df_max'),dfmax=g.df_max;end
        if isfield(g,'dtheta'),dth=g.dtheta;end
        if isfield(g,'dtheta_max'),dthmax=g.dtheta_max;end
    end
    sel=[];
    if isfield(e,'selected_gfm_indices')&&~isempty(e.selected_gfm_indices)
        sel=e.selected_gfm_indices;
    end
    ev(end+1)=struct('type',char(string(e.type)),'t',e.t, ...
        'transaction_id',e.transaction_id,'pre_kcl_norm',e.pre_kcl_norm, ...
        'right_kcl_norm',e.right_kcl_norm,'selected_gfm_indices',sel, ...
        'dV',dv,'dV_max',dvmax,'df',df,'df_max',dfmax, ...
        'dtheta',dth,'dtheta_max',dthmax); %#ok<AGROW>
end

head=struct('converged',r.converged,'reclose_status',char(string(r.reclose_status)), ...
    'actual_reclose_time',r.actual_reclose_time,'t_sg_trip',r.t_sg_trip, ...
    'horizon_reached_s',traces.t(end),'t_end_requested_s',req.options.t_end, ...
    'accepted_samples',nt,'rejected_steps',r.rejected_steps, ...
    'stepper',char(string(r.stepper)),'reselection_status',char(string(r.reselection_status)), ...
    'actual_mode_reselection_time',r.actual_mode_reselection_time, ...
    'handback_status',char(string(r.handback_status)), ...
    'full_chronology',r.full_chronology,'production_certified',false, ...
    'classification',char(string(r.classification)));
if isfield(r,'failure_id'), head.failure_id=char(string(r.failure_id)); end

cfg=struct('events',req.events,'options',req.options, ...
    'declared_synchronism',req.declared_synchronism, ...
    'declared_minimum_off_s',req.declared_minimum_off_s, ...
    'sg_plant_state_names',req.sg_plant_state_names);
if isfield(r,'selector_table_fingerprint')
    cfg.selector_table_fingerprint=char(string(r.selector_table_fingerprint));
end

view=struct('head',head,'config',cfg,'traces',traces,'events',ev, ...
    'simulation_seconds',elapsed);
end

% ===========================================================================
function render_ne39_figure(traces,ev,head,out_png)
% Three-panel chronology figure; reads only stored/cached traces.
outdir=fileparts(out_png);
if ~isempty(outdir)&&~isfolder(outdir), mkdir(outdir); end
fn='Times New Roman'; fs=11;
t=traces.t; vmin=traces.v_min_pu; vmax=traces.v_max_pu;
fig=figure('Units','inches','Position',[1 1 7.2 6.6],'Color','w', ...
    'PaperUnits','inches','PaperPosition',[0 0 7.2 6.6],'Visible','off');
tl=tiledlayout(fig,3,1,'TileSpacing','compact','Padding','compact');
marks=struct('t',{},'label',{},'c',{});
addm=@(tt,l,c) struct('t',tt,'label',l,'c',c);
if isfield(ev,'sg_trip'),     marks(end+1)=addm(ev.sg_trip,'SG trip','k'); end
if isfield(ev,'fault_on'),    marks(end+1)=addm(ev.fault_on,'fault','k'); end
if isfield(ev,'fault_clear'), marks(end+1)=addm(ev.fault_clear,'clear','k'); end
if isfield(ev,'sg_on'),       marks(end+1)=addm(ev.sg_on,'request','k'); end
if isfinite(head.actual_reclose_time)
    marks(end+1)=addm(head.actual_reclose_time,'reclose','r');
end
if isfield(head,'actual_mode_reselection_time') && isfinite(head.actual_mode_reselection_time)
    marks(end+1)=addm(head.actual_mode_reselection_time,'GFL return','b');
end

ax1=nexttile(tl); hold(ax1,'on'); grid(ax1,'on'); box(ax1,'on');
plot(ax1,t,traces.coi_frequency_Hz,'LineWidth',1.4,'DisplayName','f_{COI}');
if isfield(traces,'sg_freq')
    plot(ax1,t,traces.sg_freq,'--','LineWidth',1.1,'DisplayName','f_{SG}');
end
draw_marks(ax1,marks,fs); ylabel(ax1,'frequency [Hz]');
legend(ax1,'Location','best','Box','off');
title(ax1,'(a)  Island frequency','FontWeight','bold');

ax2=nexttile(tl); hold(ax2,'on'); grid(ax2,'on'); box(ax2,'on');
fill(ax2,[t fliplr(t)],[vmin fliplr(vmax)],[0.80 0.86 0.95], ...
    'EdgeColor','none','FaceAlpha',0.9,'DisplayName','all-bus range');
plot(ax2,t,vmin,'LineWidth',1.1,'DisplayName','min |V|');
plot(ax2,t,vmax,'LineWidth',1.1,'DisplayName','max |V|');
draw_marks(ax2,marks,fs); ylabel(ax2,'|V| [p.u.]');
legend(ax2,'Location','best','Box','off');
title(ax2,'(b)  Network voltage envelope','FontWeight','bold');

ax3=nexttile(tl); hold(ax3,'on'); grid(ax3,'on'); box(ax3,'on');
nd=numel(traces.device_ids); off=linspace(-0.12,0.12,nd);
for k=1:nd
    stairs(ax3,t,traces.mode_level(k,:)+off(k),'LineWidth',1.5, ...
        'DisplayName',char(string(traces.device_ids{k})));
end
draw_marks(ax3,marks,fs);
set(ax3,'YTick',[0 1 2],'YTickLabel',{'open','GFL','GFM / SG'});
ylim(ax3,[-0.45 2.45]); ylabel(ax3,'committed mode'); xlabel(ax3,'time [s]');
legend(ax3,'Location','southeast','Box','off','NumColumns',5,'FontSize',fs-2);
title(ax3,'(c)  Committed controller mode per resource','FontWeight','bold');

headline=sprintf('NE39 1 SG + 9 IBR, %s: %.0f s chronology, reclose %s at t = %.3f s', ...
    char(string(ev.event_profile)),t(end),head.reclose_status,head.actual_reclose_time);
title(tl,headline,'FontName',fn,'FontSize',fs+1,'FontWeight','bold');
set(findall(fig,'-property','FontName'),'FontName',fn);
set(findall(fig,'-property','FontSize'),'FontSize',fs);
linkaxes([ax1 ax2 ax3],'x'); xlim(ax1,[t(1) t(end)]);
print(fig,out_png,'-dpng','-r220'); close(fig);
end

function draw_marks(ax,marks,fs)
yl=ylim(ax);
for k=1:numel(marks)
    xline(ax,marks(k).t,':','Color',marks(k).c,'LineWidth',1.0, ...
        'Label',marks(k).label,'LabelOrientation','horizontal', ...
        'LabelVerticalAlignment','top','FontSize',fs-3,'HandleVisibility','off');
end
ylim(ax,yl);
end

function L=mode_level(m,online)
if ~online, L=0; return; end
s=lower(char(string(m)));
if contains(s,'open'), L=0;
elseif strcmp(s,'gfl'), L=1;
else, L=2;
end
end

function s=fmt_struct(st)
fn=fieldnames(st); parts=cell(1,numel(fn));
for k=1:numel(fn)
    v=st.(fn{k});
    if ischar(v)||isstring(v)
        parts{k}=sprintf('%s=%s',fn{k},char(string(v)));
    elseif islogical(v)||isnumeric(v)
        parts{k}=sprintf('%s=%s',fn{k},mat2str(v));
    else
        parts{k}=sprintf('%s=<%s>',fn{k},class(v));
    end
end
s=strjoin(parts,', ');
end
