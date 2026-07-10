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
        result=pfsolver.powerflow_newton_raphson(case_data,opt);
        print_pf_checks(result,opt);
    case 'sssa'
        opt=merge_options(entry.options,user_opt);
        result=stability.multicase_sssa(case_data,opt);
        print_sssa_checks(result);
    case 'ts'
        opt=merge_options(entry.options,user_opt);
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
switch analysis
    case 'pf'
        r=[item('ieee5','IEEE 5-bus',@cases.case_ieee5bus); ...
           item('ieee14','IEEE 14-bus',@cases.case_ieee14bus); ...
           item('matpower14','MATPOWER case14',@cases.case_matpower6_case14); ...
           item('case9','WSCC/MATPOWER case9',@cases.case_matpower6_case9); ...
           item('ieee30','IEEE 30-bus (Saadat)',@cases.case_saadat_ieee30bus); ...
           item('ieee300','IEEE 300-bus',@cases.case_ieee300bus); ...
           item('rts24','IEEE RTS 24-bus (RTS-1996)',@cases.case_ieee_rts24_pgaz); ...
           item('kundur','Kundur Example 12.6',@cases.kundur_ex126_book_case)];
    case 'sssa'
        r=[item('kundur_emf6','Kundur - operational EMF6', ...
                @cases.kundur_ex126_book_case,struct('model','emf6')); ...
           item('kundur_flux6','Kundur - primitive flux6', ...
                @cases.kundur_ex126_book_case,struct('model','flux6')); ...
           item('sauer_pai','Sauer-Pai Example 8.3', ...
                @cases.sauer_pai_ex83_case,struct())];
    case 'ts'
        base=struct('t_end',15,'dt',0.01,'t_fault',1,'t_clear',1.1, ...
            'Zf',1i*0.1,'method','trapezoidal','corrector_iter',1,'verbose',true);
        base.plot_results=true;
        a=base; a.model='emf6'; a.fault_bus=8;
        b=base; b.model='classical'; b.fault_bus=4;
        c=base; c.model='classical'; c.fault_bus=7;
        d=base; d.model='classical'; d.fault_bus=15;
        d.t_end=15; d.dt=0.01; d.t_fault=1.0; d.t_clear=1.1; d.Zf=1i*0.1;
        r=[item('kundur_emf6','Kundur - operational EMF6', ...
                @cases.kundur_ex126_book_case,a); ...
           item('case14','MATPOWER case14 - classical', ...
                @cases.case_matpower6_case14,b); ...
           item('case9','WSCC/MATPOWER case9 - classical', ...
                @cases.case_matpower6_case9,c); ...
           item('rts24','IEEE RTS 24-bus - classical', ...
                @cases.case_ieee_rts24_pgaz,d)];
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
lam=r.eigenvalues(:);
fprintf('\n---------------- SSSA VERIFICATION --------------\n');
fprintf('Dynamic states  : %d\n',numel(lam));
if isfield(r,'newton_residual'), fprintf('DAE residual    : %.3e\n',r.newton_residual); end
fprintf('Max real(lambda): %+.6e 1/s\n',max(real(lam)));
fprintf('Unstable roots  : %d\n',sum(real(lam)>1e-7));
fprintf('\n%4s %14s %14s %10s %10s\n','No','Real','Imag','f_Hz','zeta');
for k=1:numel(lam)
    f=abs(imag(lam(k)))/(2*pi); z=-real(lam(k))/(abs(lam(k))+eps);
    fprintf('%4d %+14.6e %+14.6e %10.5f %10.5f\n',k,real(lam(k)),imag(lam(k)),f,z);
end
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
d=r.delta-mean(r.delta,2); d=d-d(1,:);
fprintf('Max COI angle   : %.6f deg\n',max(abs(rad2deg(d)),[],'all'));
if isfield(r,'initial_dae_residual')
    fprintf('Initial residual: %.3e\n',r.initial_dae_residual);
end
if isfield(r,'figure_file'), fprintf('Figure file    : %s\n',r.figure_file); end
end

function [fig,png]=plot_ts_result(r,label,root,case_id)
t=r.t(:); ng=size(r.delta,2); colors=lines(ng);
if isfield(r,'gen_buses'), gb=r.gen_buses(:); else, gb=(1:ng)'; end
labels=compose('G%d@Bus%d',(1:ng)',gb);
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
mark_fault(ax,r); xlabel(ax,'Time (s)'); ylabel(ax,'Delta delta (deg)');
title(ax,'Rotor-angle deviations'); legend(ax,labels,'Location','best');

ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for k=1:ng, plot(ax,t,wd(:,k),'LineWidth',1.3,'Color',colors(k,:)); end
mark_fault(ax,r); xlabel(ax,'Time (s)'); ylabel(ax,'Delta omega (pu)');
title(ax,'Generator speed deviations'); legend(ax,labels,'Location','best');

ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for k=1:ng, plot(ax,t,r.Pe_MW(:,k),'LineWidth',1.3,'Color',colors(k,:)); end
mark_fault(ax,r); xlabel(ax,'Time (s)'); ylabel(ax,'P_e (MW)');
title(ax,'Electrical air-gap power'); legend(ax,labels,'Location','best');

if isfield(r,'bus_ids'), bus_ids=r.bus_ids(:); else, bus_ids=r.pf.external_bus_ids(:); end
fi=find(bus_ids==r.fault_bus,1); if isempty(fi), fi=1; end
ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
plot(ax,t,r.Vbus(:,fi),'k','LineWidth',1.8);
plot(ax,t,min(r.Vbus,[],2),'r--','LineWidth',1.3);
mark_fault(ax,r); xlabel(ax,'Time (s)'); ylabel(ax,'|V| (pu)');
title(ax,'Fault-bus and minimum voltage');
legend(ax,{sprintf('Bus %g',bus_ids(fi)),'Minimum |V|'},'Location','best');

sgtitle(tl,sprintf('%s: bus %g fault, %.3f-%.3f s', ...
    label,r.fault_bus,r.t_fault,r.t_clear),'FontWeight','bold');
outdir=fullfile(root,'output','figures','ts');
if ~exist(outdir,'dir'), mkdir(outdir); end
png=fullfile(outdir,sprintf('%s_%s.png',datestr(now,'yyyymmdd_HHMMSS'),case_id));
exportgraphics(fig,png,'Resolution',180);
fprintf('Saved TS figure: %s\n',png);
end

function mark_fault(ax,r)
xline(ax,r.t_fault,'r--','Fault','HandleVisibility','off');
xline(ax,r.t_clear,'r--','Clear','HandleVisibility','off');
end
