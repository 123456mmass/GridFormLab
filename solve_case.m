function result = solve_case(varargin)
%SOLVE_CASE Interactive in-house PF / SSSA / TS launcher.
%   RESULT = SOLVE_CASE() opens analysis and case selection dialogs.
%   RESULT = SOLVE_CASE('analysis',ID,'case',ID,'options',OPT) is the
%   non-interactive form used by automation. Production calculations use
%   only project solvers; no Optimization Toolbox solver is called.

root=pf_init_paths();
p=inputParser;
addParameter(p,'analysis','',@(x)ischar(x)||isstring(x));
addParameter(p,'case','',@(x)ischar(x)||isstring(x));
addParameter(p,'options',struct(),@isstruct);
parse(p,varargin{:});
analysis=lower(char(p.Results.analysis));
case_id=lower(char(p.Results.case));
user_opt=p.Results.options;
interactive=isempty(analysis);

analyses=struct( ...
    'id',{'pf','sssa','ts'}, ...
    'label',{'Power Flow - in-house Newton-Raphson', ...
             'Small-Signal Stability Analysis (SSSA)', ...
             'Transient Stability (TS)'});
if isempty(analysis)
    analysis=choose_item('เลือกการวิเคราะห์',{analyses.label},{analyses.id});
    if isempty(analysis), result=[]; return; end
end
if ~any(strcmp(analysis,{analyses.id}))
    error('solve_case:analysis','Unknown analysis %s.',analysis);
end

registry=case_registry(analysis);
if isempty(case_id)
    case_id=choose_item('เลือกเคส',{registry.label},{registry.id});
    if isempty(case_id), result=[]; return; end
end
idx=find(strcmp(case_id,{registry.id}),1);
if isempty(idx), error('solve_case:case','Case %s is not supported for %s.',case_id,analysis); end
entry=registry(idx); case_data=entry.loader();

logdir=fullfile(root,'output','logs');
if ~exist(logdir,'dir'), mkdir(logdir); end
stamp=datestr(now,'yyyymmdd_HHMMSS');
logfile=fullfile(logdir,sprintf('%s_%s_%s.log',stamp,analysis,case_id));
diary(logfile); diary_cleanup=onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('\n============================================================\n');
fprintf('IN-HOUSE ANALYSIS LAUNCHER\n');
fprintf('Analysis : %s\n',upper(analysis));
fprintf('Case     : %s\n',entry.label);
fprintf('Time     : %s\n',datestr(now,31));
fprintf('Log      : %s\n',logfile);
fprintf('Engine   : project MATLAB code only (no external solver)\n');
fprintf('============================================================\n');
print_case_manifest(case_data);

switch analysis
    case 'pf'
        opt=merge_options(struct('verbose',true,'plot_results',true, ...
            'max_iter',50,'tolerance',1e-10,'enforce_q_limits',true),user_opt);
        print_run_options(opt);
        result=pfsolver.powerflow_newton_raphson(case_data,opt);
        print_pf_checks(result,opt);
    case 'sssa'
        opt=merge_options(entry.options,user_opt);
        print_run_options(opt);
        result=stability.multicase_sssa(case_data,opt);
        result=annotate_sssa_result(result,opt);
        print_sssa_checks(result);
    case 'ts'
        opt=merge_options(entry.options,user_opt);
        print_run_options(opt);
        result=stability.ts_simulate(case_data,opt);
        if ~isfield(opt,'plot_results') || opt.plot_results
            [fig,png]=plot_ts_result(result,entry.label,root,case_id);
            result.figure=fig;
            result.figure_file=png;
        end
        print_ts_checks(result);
end

result.launcher=struct('analysis',analysis,'case_id',case_id, ...
    'case_label',entry.label,'log_file',logfile);
fprintf('\nSTATUS: COMPLETE\n');
fprintf('Saved log: %s\n',logfile);
diary('off');
if interactive
    msgbox(sprintf('รันเสร็จแล้ว\n%s\n\nLog:\n%s',entry.label,logfile), ...
        'solve_case','modal');
end
end

function r=case_registry(analysis)
catalog=cases.network_case_catalog();
switch analysis
    case 'pf'
        r=items_from_catalog(catalog,'pf_options');
    case 'sssa'
        r=items_from_catalog(catalog,'sssa_options');
        % Additional model/benchmark variants remain available alongside
        % the one default SSSA entry provided for every network case.
        r=[r; item('kundur_flux6','Kundur - primitive flux6', ...
                @cases.kundur_ex126_book_case,struct('model','flux6')); ...
           item('sauer_pai','Sauer-Pai Example 8.3', ...
                @cases.sauer_pai_ex83_case,struct())];
    case 'ts'
        r=items_from_catalog(catalog,'ts_options');
end
end

function r=items_from_catalog(catalog,option_field)
r=repmat(item('','','',struct()),0,1);
for k=1:numel(catalog)
    r(end+1,1)=item(catalog(k).id,catalog(k).label, ...
        catalog(k).loader,catalog(k).(option_field)); %#ok<AGROW>
end
end

function s=item(id,label,loader,options)
if nargin<4, options=struct(); end
s=struct('id',id,'label',label,'loader',loader,'options',options);
end

function id=choose_item(prompt,labels,ids)
[k,ok]=listdlg('PromptString',prompt,'SelectionMode','single', ...
    'ListString',labels,'ListSize',[430 260]);
if ok, id=ids{k}; else, id=''; end
end

function out=merge_options(defaults,user)
out=defaults; names=fieldnames(user);
for k=1:numel(names), out.(names{k})=user.(names{k}); end
end

function print_case_manifest(c)
if isfield(c,'schema_version'), fprintf('Schema   : %s\n',c.schema_version); end
if isfield(c,'base_values')
    fprintf('Base     : %.6g MVA, %.6g Hz\n', ...
        c.base_values.S_base_MVA,c.base_values.frequency_Hz);
end
if isfield(c,'bus_data')
    fprintf('Network  : %d buses, %d branches\n', ...
        size(c.bus_data,1),size(c.line_data,1));
end
end

function print_run_options(opt)
fprintf('\n---------------- RUN SETTINGS -------------------\n');
names=fieldnames(opt);
for k=1:numel(names)
    name=names{k}; value=opt.(name);
    if islogical(value) && isscalar(value)
        text=mat2str(value);
    elseif isnumeric(value) && isscalar(value)
        if isreal(value)
            text=sprintf('%.12g',value);
        else
            text=sprintf('%.12g %+.12gj',real(value),imag(value));
        end
    elseif ischar(value) || (isstring(value) && isscalar(value))
        text=char(value);
    elseif isempty(value)
        text='[]';
    elseif isnumeric(value) || islogical(value)
        text=mat2str(value);
    else
        text=sprintf('<%s %s>',class(value),mat2str(size(value)));
    end
    fprintf('%-20s: %s\n',name,text);
end
end

function print_pf_checks(r,opt)
fprintf('\n---------------- PF VERIFICATION ----------------\n');
fprintf('Converged       : %d\n',r.converged);
if isfield(r,'iterations'), fprintf('Iterations      : %d\n',r.iterations); end
if isfield(r,'max_mismatch'), fprintf('Max mismatch    : %.3e pu\n',r.max_mismatch); end
if isfield(r,'P_loss_total'), fprintf('P loss          : %.6g pu\n',r.P_loss_total); end
if isfield(r,'Q_loss_total'), fprintf('Q loss          : %.6g pu\n',r.Q_loss_total); end
fprintf('Voltage range   : %.6f .. %.6f pu\n',min(r.bus_voltage),max(r.bus_voltage));
fprintf('Angle range     : %.6f .. %.6f deg\n',min(r.bus_angle_deg),max(r.bus_angle_deg));
fprintf('Tolerance       : %.3e\n',opt.tolerance);
if ~r.converged, error('solve_case:pf','Power flow did not converge.'); end
end

function print_sssa_checks(r)
fprintf('\n---------------- SSSA VERIFICATION --------------\n');
fprintf('Dynamic states  : %d\n',numel(r.state_names));
fprintf('Stability status: %s\n',r.stability_status);
fprintf('Decision tol.   : %.3e 1/s\n',r.stability_tolerance);
fprintf('Root counts     : stable=%d, marginal=%d, unstable=%d\n', ...
    r.root_counts.stable,r.root_counts.marginal,r.root_counts.unstable);
if isfield(r,'metadata') && isfield(r.metadata,'plugin')
    fprintf('Model plugin    : %s\n',r.metadata.plugin);
end
if isfield(r,'metadata') && isfield(r.metadata,'dynamic_data_source')
    fprintf('Dynamic source  : %s\n',r.metadata.dynamic_data_source);
end
if isfield(r,'newton_residual'), fprintf('DAE residual    : %.3e\n',r.newton_residual); end
fprintf('\nSTATE INVENTORY\n');
for k=1:numel(r.state_names)
    fprintf('  x(%-3d) %s\n',k,r.state_names{k});
end
if isfield(r,'reduced_eigenvalues')
    lam=r.reduced_eigenvalues(:);
    fprintf('\nEigenvalue set  : COI-reduced (%d modes)\n',numel(lam));
else
    lam=r.eigenvalues(:);
    fprintf('\nEigenvalue set  : full (%d modes)\n',numel(lam));
end
if isempty(lam)
    fprintf('Max real(lambda): N/A (no relative modes)\n');
else
    fprintf('Max real(lambda): %+.6e 1/s\n',max(real(lam)));
end
fprintf('\n%4s %14s %14s %10s %10s\n','No','Real','Imag','f_Hz','zeta');
for k=1:numel(lam)
    f=abs(imag(lam(k)))/(2*pi); z=-real(lam(k))/(abs(lam(k))+eps);
    fprintf('%4d %+14.6e %+14.6e %10.5f %10.5f\n',k,real(lam(k)),imag(lam(k)),f,z);
end
end

function r=annotate_sssa_result(r,opt)
if ~isfield(r,'state_names') || isempty(r.state_names)
    r.state_names=arrayfun(@(k)sprintf('x%d',k),1:size(r.Afull,1), ...
        'UniformOutput',false).';
else
    r.state_names=r.state_names(:);
end
if isfield(r,'reduced_eigenvalues')
    lam=r.reduced_eigenvalues(:);
else
    lam=r.eigenvalues(:);
end
tol=1e-7;
if isfield(opt,'stability_tolerance'), tol=opt.stability_tolerance; end
nu=sum(real(lam)>tol); ns=sum(real(lam)<-tol); nm=numel(lam)-nu-ns;
if isempty(lam)
    status='NOT APPLICABLE - NO RELATIVE MODES';
elseif nu>0
    status='UNSTABLE';
elseif nm>0
    status='MARGINAL';
else
    status='ASYMPTOTICALLY STABLE';
end
r.stability_status=status;
r.stability_tolerance=tol;
r.root_counts=struct('stable',ns,'marginal',nm,'unstable',nu);
end

function print_ts_checks(r)
fprintf('\n---------------- TS VERIFICATION ----------------\n');
fprintf('Samples         : %d\n',numel(r.t));
fprintf('Time range      : %.4f .. %.4f s\n',r.t(1),r.t(end));
fprintf('Minimum voltage : %.6f pu\n',min(r.Vbus,[],'all'));
if isfield(r,'omega_is_deviation') && r.omega_is_deviation
    wd=r.omega;
else
    wd=r.omega-1;
end
fprintf('Max |Delta w|   : %.6e pu\n',max(abs(wd),[],'all'));
% COI-relative rotor angles (H-weighted centre of inertia).
ng=size(r.delta,2);
if isfield(r,'H') && numel(r.H)==ng && any(r.H>0)
    Hw=r.H(:).';
else
    Hw=ones(1,ng);
end
delta_coi=(r.delta.*Hw).*sum(1./Hw);  % = sum(H_k*delta_k)/sum(H_k)
delta_coi=sum(r.delta.*Hw,2)./sum(Hw);
d_coi=rad2deg(r.delta-delta_coi);            % COI-relative angle (deg)
fprintf('Max COI-rel ang : %.4f deg\n',max(abs(d_coi),[],'all'));
% Maximum pairwise rotor-angle separation (deg).
maxpair=0;
for i=1:ng
    for j=i+1:ng
        sep=abs(rad2deg(r.delta(:,i)-r.delta(:,j)));
        maxpair=max(maxpair,max(sep));
    end
end
fprintf('Max pair separ. : %.4f deg\n',maxpair);
% Final-window trend (last 10% of simulation).
t_final=r.t(end);
win=r.t>=0.9*t_final;
if any(win)
    d_final=d_coi(win,:);
    trend_deg=max(d_final(end,:))-max(d_final(1,:));
    fprintf('Final-window dCOI trend: %+.4f deg\n',trend_deg);
end
% Post-fault voltage recovery.
t_post=r.t>=r.t_clear+0.1;
if any(t_post)
    fprintf('Post-fault Vmin : %.6f pu (t>=%.2fs)\n',min(r.Vbus(t_post,:),[],'all'),r.t_clear+0.1);
end
if isfield(r,'initial_dae_residual')
    fprintf('Initial residual: %.3e\n',r.initial_dae_residual);
end
if isfield(r,'figure_file'), fprintf('Figure file    : %s\n',r.figure_file); end
end

function [fig,png]=plot_ts_result(r,label,root,case_id)
t=r.t(:); ng=size(r.delta,2); colors=lines(ng);
if isfield(r,'gen_buses'), gb=r.gen_buses(:); else, gb=(1:ng)'; end
labels=compose('G%d@Bus%d',(1:ng)',gb);
% Match the established case14/Kundur display convention and PSAT's
% delta_Syn variables: each machine angle relative to its own pre-fault
% value.  COI-relative/pairwise quantities remain verification metrics in
% print_ts_checks; they are intentionally not used for this plot.
delta_deg=rad2deg(r.delta-r.delta(1,:));
if isfield(r,'omega_is_deviation') && r.omega_is_deviation
    wd=r.omega;
else
    wd=r.omega-1;
end

fig=figure('Name',['TS - ' label],'Color','w','Position',[70 70 1300 820]);
tl=tiledlayout(fig,2,2,'Padding','compact','TileSpacing','compact');

ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for k=1:ng, plot(ax,t,delta_deg(:,k),'LineWidth',1.4,'Color',colors(k,:)); end
mark_fault(ax,r); xlabel(ax,'Time (s)');
ylabel(ax,'\Delta\delta_i = \delta_i-\delta_i(0) (deg)');
title(ax,'Absolute rotor-angle deviations (PSAT delta\_Syn style)');
legend(ax,labels,'Location','best');

ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for k=1:ng, plot(ax,t,wd(:,k),'LineWidth',1.3,'Color',colors(k,:)); end
mark_fault(ax,r); xlabel(ax,'Time (s)'); ylabel(ax,'Delta omega (pu)');
title(ax,'Generator speed deviations'); legend(ax,labels,'Location','best');

ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for k=1:ng, plot(ax,t,r.Pe_MW(:,k),'LineWidth',1.3,'Color',colors(k,:)); end
mark_fault(ax,r); xlabel(ax,'Time (s)'); ylabel(ax,'P_e (MW)');
title(ax,'Electrical power (classical air-gap)');
legend(ax,labels,'Location','best');

if isfield(r,'bus_ids'), bus_ids=r.bus_ids(:); else, bus_ids=r.pf.external_bus_ids(:); end
fi=find(bus_ids==r.fault_bus,1); if isempty(fi), fi=1; end
ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
plot(ax,t,r.Vbus(:,fi),'k','LineWidth',1.8);
plot(ax,t,min(r.Vbus,[],2),'r--','LineWidth',1.3);
mark_fault(ax,r); xlabel(ax,'Time (s)'); ylabel(ax,'|V| (pu)');
title(ax,'Fault-bus and minimum voltage');
legend(ax,{sprintf('Bus %g',bus_ids(fi)),'Minimum |V|'},'Location','best');
ylim(ax,[0 1.2]);

sgtitle(tl,sprintf(['%s: bus %g fault, Z_f = %.3g%+.3gj pu, ' ...
    '%s, dt=%.4f s'],label,r.fault_bus,real(r.Zf),imag(r.Zf), ...
    r.method,r.dt),'FontWeight','bold');
outdir=fullfile(root,'output','figures','ts');
if ~exist(outdir,'dir'), mkdir(outdir); end
png=fullfile(outdir,sprintf('%s_%s.png',datestr(now,'yyyymmdd_HHMMSS'),case_id));
exportgraphics(fig,png,'Resolution',180);
fprintf('Saved TS figure: %s\n',png);
end

function mark_fault(ax,r)
xline(ax,r.t_fault,'--','Fault on','Color',[0.75 0.1 0.1], ...
    'LineWidth',1.1,'LabelOrientation','horizontal','HandleVisibility','off');
xline(ax,r.t_clear,'--','Fault cleared','Color',[0.75 0.1 0.1], ...
    'LineWidth',1.1,'LabelOrientation','horizontal','HandleVisibility','off');
end
