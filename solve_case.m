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
interactive=isempty(analysis)||isempty(case_id);
case_selection_interactive=isempty(case_id);

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

pf_opt=struct(); sssa_opt=struct(); ts_opt=struct();
switch analysis
    case 'pf'
        pf_defaults=struct('verbose',true,'plot_results',true, ...
            'max_iter',50,'tolerance',1e-10,'enforce_q_limits',true, ...
            'q_limit_tolerance',1e-6,'max_q_limit_switches',20);
        pf_opt=merge_options(pf_defaults,user_opt);
        if case_selection_interactive
            [pf_opt,accepted]=prompt_pf_options(pf_opt,entry.label);
            if ~accepted, result=[]; return; end
        end
    case 'sssa'
        sssa_opt=merge_options(entry.options,user_opt);
        if case_selection_interactive
            [sssa_opt,accepted]=prompt_sssa_options(case_data,sssa_opt,entry.label);
            if ~accepted, result=[]; return; end
        end
    case 'ts'
        ts_opt=merge_options(entry.options,user_opt);
        if case_selection_interactive
            [ts_opt,accepted]=prompt_ts_options(case_data,ts_opt,entry.label);
            if ~accepted, result=[]; return; end
        end
end

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
        opt=pf_opt;
        print_run_options(opt);
        result=pfsolver.powerflow_newton_raphson(case_data,opt);
        print_pf_checks(result,opt);
    case 'sssa'
        opt=sssa_opt;
        print_run_options(opt);
        result=stability.multicase_sssa(case_data,opt);
        result=annotate_sssa_result(result,opt);
        print_sssa_checks(result);
    case 'ts'
        opt=ts_opt;
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
        % The Kundur Example 12.6 case is already in the catalog with
        % sssa_options.model='emf6' (the operational sixth-order model).
        % The historical primitive-flux and Sauer-Pai flux variants have
        % been moved to legacy/ and are no longer offered here.
        r=[r; item('sauer_pai','Sauer-Pai Example 8.3', ...
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

function [opt,accepted]=prompt_pf_options(opt,case_label)
prompts={ ...
    'Maximum Newton iterations'; ...
    'Power-mismatch tolerance (pu)'; ...
    'Enforce generator Q limits (true/false)'; ...
    'Q-limit violation tolerance (pu)'; ...
    'Maximum PV-to-PQ switching rounds'; ...
    'Verbose output (true/false)'; ...
    'Plot results (true/false)'};
defaults={num_text(opt.max_iter),num_text(opt.tolerance), ...
    logical_text(opt.enforce_q_limits),num_text(opt.q_limit_tolerance), ...
    num_text(opt.max_q_limit_switches),logical_text(opt.verbose), ...
    logical_text(opt.plot_results)};
accepted=false;
while true
    answer=inputdlg(prompts,sprintf('PF settings — %s',case_label), ...
        repmat([1 58],numel(prompts),1),defaults,struct('Resize','on'));
    if isempty(answer), return; end
    [candidate,message]=parse_pf_dialog(opt,answer);
    if isempty(message)
        opt=candidate; accepted=true; return;
    end
    errordlg(message,'Invalid PF settings','modal');
    defaults=answer;
end
end

function [opt,message]=parse_pf_dialog(opt,a)
message='';
values=cellfun(@str2double,a([1 2 4 5]));
if any(~isfinite(values))
    message='All numeric PF settings must be finite numbers.';
    return;
end
opt.max_iter=values(1); opt.tolerance=values(2);
opt.q_limit_tolerance=values(3); opt.max_q_limit_switches=values(4);
[opt.enforce_q_limits,ok_q]=parse_logical_text(a{3});
[opt.verbose,ok_verbose]=parse_logical_text(a{6});
[opt.plot_results,ok_plot]=parse_logical_text(a{7});
if opt.max_iter<1 || opt.max_iter~=fix(opt.max_iter)
    message='Maximum Newton iterations must be a positive integer.';
elseif opt.tolerance<=0 || opt.q_limit_tolerance<=0
    message='PF and Q-limit tolerances must be positive.';
elseif opt.max_q_limit_switches<0 || ...
        opt.max_q_limit_switches~=fix(opt.max_q_limit_switches)
    message='Maximum Q-limit switching rounds must be a nonnegative integer.';
elseif ~ok_q || ~ok_verbose || ~ok_plot
    message='Logical PF settings must be true/false or 1/0.';
end
end

function [opt,accepted]=prompt_sssa_options(case_data,opt,case_label)
opt=sssa_dialog_defaults(case_data,opt);
prompts={ ...
    'Dynamic model (classical, emf6, padiyar_1_1_avr/manual, or blank)'; ...
    'Finite-difference step fd_eps'; ...
    'Stability decision tolerance (1/s)'; ...
    'Equilibrium tolerance (EMF6)'; ...
    'Maximum equilibrium Newton iterations (EMF6)'; ...
    'Load model (EMF6)'};
defaults={char(opt.model),num_text(opt.fd_eps), ...
    num_text(opt.stability_tolerance),num_text(opt.equilibrium_tolerance), ...
    num_text(opt.newton_max_iterations),char(opt.load_model)};
accepted=false;
while true
    answer=inputdlg(prompts,sprintf('SSSA settings — %s',case_label), ...
        repmat([1 68],numel(prompts),1),defaults,struct('Resize','on'));
    if isempty(answer), return; end
    [candidate,message]=parse_sssa_dialog(opt,answer);
    if isempty(message)
        opt=candidate; accepted=true; return;
    end
    errordlg(message,'Invalid SSSA settings','modal');
    defaults=answer;
end
end

function opt=sssa_dialog_defaults(case_data,opt)
if ~isfield(opt,'model'), opt.model=''; end
model=char(opt.model);
if ~isfield(opt,'fd_eps') || isempty(opt.fd_eps)
    if strcmpi(model,'emf6'), opt.fd_eps=3e-6; else, opt.fd_eps=1e-6; end
end
if ~isfield(opt,'stability_tolerance') || isempty(opt.stability_tolerance)
    opt.stability_tolerance=1e-7;
end
if ~isfield(opt,'equilibrium_tolerance') || isempty(opt.equilibrium_tolerance)
    opt.equilibrium_tolerance=1e-10;
end
if ~isfield(opt,'newton_max_iterations') || isempty(opt.newton_max_iterations)
    opt.newton_max_iterations=300;
end
if ~isfield(opt,'load_model') || isempty(opt.load_model)
    if isfield(case_data,'operating_point') && ...
            isfield(case_data.operating_point,'load_model')
        opt.load_model=case_data.operating_point.load_model;
    else
        opt.load_model='cz_p_cz_q';
    end
end
end

function [opt,message]=parse_sssa_dialog(opt,a)
message='';
values=cellfun(@str2double,a(2:5));
if any(~isfinite(values))
    message='All numeric SSSA settings must be finite numbers.';
    return;
end
opt.model=lower(strtrim(a{1}));
opt.fd_eps=values(1); opt.stability_tolerance=values(2);
opt.equilibrium_tolerance=values(3); opt.newton_max_iterations=values(4);
opt.load_model=strtrim(a{6});
valid_models={'','classical','emf6','padiyar_1_1_avr','padiyar_1_1_manual'};
if ~any(strcmp(opt.model,valid_models))
    message='Unsupported SSSA model selection.';
elseif opt.fd_eps<=0 || opt.stability_tolerance<=0 || ...
        opt.equilibrium_tolerance<=0
    message='SSSA finite-difference and tolerance values must be positive.';
elseif opt.newton_max_iterations<1 || ...
        opt.newton_max_iterations~=fix(opt.newton_max_iterations)
    message='Maximum equilibrium Newton iterations must be a positive integer.';
elseif isempty(opt.load_model)
    message='Load model must not be empty.';
end
end

function [opt,accepted]=prompt_ts_options(case_data,opt,case_label)
% Ask for TS settings only after the case and its external bus IDs are known.
if ~isfield(opt,'pm_mode') || isempty(opt.pm_mode), opt.pm_mode='balanced'; end
bus_ids=case_bus_ids(case_data);
if ~isfield(opt,'fault_bus') || isempty(opt.fault_bus) || ...
        ~ismember(opt.fault_bus,bus_ids)
    opt.fault_bus=bus_ids(1);
end
if ~isfield(opt,'corrector_iter') || isempty(opt.corrector_iter)
    fixed_iter_default=3;
else
    fixed_iter_default=opt.corrector_iter;
end

bus_text=format_bus_ids(bus_ids);
prompts={ ...
    'Simulation end time t_end (s)'; ...
    'Nominal integration step dt (s)'; ...
    sprintf('Fault bus: external ID (valid: %s)',bus_text); ...
    'Fault application time t_fault (s)'; ...
    'Fault clearing time t_clear (s)'; ...
    'Fault resistance Rf (pu)'; ...
    'Fault reactance Xf (pu)'; ...
    'Integration method (trapezoidal)'; ...
    'Stepper (fixed or adaptive)'; ...
    'Corrector mode (adaptive or fixed)'; ...
    'Corrector absolute tolerance'; ...
    'Corrector relative tolerance'; ...
    'Maximum adaptive-corrector iterations'; ...
    'Fixed corrector iterations'; ...
    'Mechanical-power mode'; ...
    'Verbose output (true/false)'; ...
    'Plot results (true/false)'};
defaults={num_text(opt.t_end),num_text(opt.dt),num_text(opt.fault_bus), ...
    num_text(opt.t_fault),num_text(opt.t_clear),num_text(real(opt.Zf)), ...
    num_text(imag(opt.Zf)),char(opt.method),char(opt.stepper), ...
    char(opt.corrector_mode),num_text(opt.corrector_abs_tol), ...
    num_text(opt.corrector_rel_tol),num_text(opt.max_corrector_iter), ...
    num_text(fixed_iter_default),char(opt.pm_mode), ...
    logical_text(opt.verbose),logical_text(opt.plot_results)};

accepted=false;
while true
    answer=inputdlg(prompts,sprintf('TS settings — %s',case_label), ...
        repmat([1 62],numel(prompts),1),defaults,struct('Resize','on'));
    if isempty(answer), return; end
    [candidate,message]=parse_ts_dialog(opt,answer,bus_ids);
    if isempty(message)
        opt=candidate;
        accepted=true;
        return;
    end
    errordlg(message,'Invalid TS settings','modal');
    defaults=answer;
end
end

function [opt,message]=parse_ts_dialog(opt,a,bus_ids)
message='';
values=cellfun(@str2double,a([1:7 11:14]));
if any(~isfinite(values))
    message='All numeric TS settings must be finite numbers.';
    return;
end
opt.t_end=values(1); opt.dt=values(2); opt.fault_bus=values(3);
opt.t_fault=values(4); opt.t_clear=values(5);
opt.Zf=values(6)+1i*values(7);
opt.corrector_abs_tol=values(8); opt.corrector_rel_tol=values(9);
opt.max_corrector_iter=values(10); fixed_iter=values(11);
opt.method=lower(strtrim(a{8}));
opt.stepper=lower(strtrim(a{9}));
opt.corrector_mode=lower(strtrim(a{10}));
opt.pm_mode=lower(strtrim(a{15}));
[opt.verbose,ok_verbose]=parse_logical_text(a{16});
[opt.plot_results,ok_plot]=parse_logical_text(a{17});

if opt.t_end<=0 || opt.dt<=0
    message='t_end and dt must be positive.';
elseif opt.t_fault<0 || opt.t_clear<=opt.t_fault || opt.t_clear>opt.t_end
    message='Require 0 <= t_fault < t_clear <= t_end.';
elseif opt.fault_bus~=fix(opt.fault_bus) || ~ismember(opt.fault_bus,bus_ids)
    message=sprintf('Fault bus must be one of these external IDs: %s.', ...
        format_bus_ids(bus_ids));
elseif ~strcmp(opt.method,'trapezoidal')
    message='This launcher currently supports method=trapezoidal only.';
elseif ~any(strcmp(opt.stepper,{'fixed','adaptive'}))
    message='Stepper must be fixed or adaptive.';
elseif ~any(strcmp(opt.corrector_mode,{'fixed','adaptive'}))
    message='Corrector mode must be fixed or adaptive.';
elseif opt.corrector_abs_tol<=0 || opt.corrector_rel_tol<=0
    message='Corrector tolerances must be positive.';
elseif opt.max_corrector_iter<1 || opt.max_corrector_iter~=fix(opt.max_corrector_iter)
    message='Maximum corrector iterations must be a positive integer.';
elseif fixed_iter<1 || fixed_iter~=fix(fixed_iter)
    message='Fixed corrector iterations must be a positive integer.';
elseif ~ok_verbose || ~ok_plot
    message='verbose and plot_results must be true/false or 1/0.';
else
    if strcmp(opt.corrector_mode,'fixed'), opt.corrector_iter=fixed_iter; end
end
end

function ids=case_bus_ids(c)
if isfield(c,'mpc') && isfield(c.mpc,'bus')
    ids=c.mpc.bus(:,1);
elseif isfield(c,'bus_data')
    ids=c.bus_data(:,1);
else
    error('solve_case:busIds','Selected case does not expose bus IDs.');
end
ids=unique(ids(:),'stable');
end

function text=format_bus_ids(ids)
ids=ids(:).';
if numel(ids)<=24
    text=strjoin(compose('%g',ids),', ');
else
    text=sprintf('%s, ... (%d buses total)', ...
        strjoin(compose('%g',ids(1:20)),', '),numel(ids));
end
end

function text=num_text(value)
text=sprintf('%.12g',value);
end

function text=logical_text(value)
if value, text='true'; else, text='false'; end
end

function [value,ok]=parse_logical_text(text)
switch lower(strtrim(text))
    case {'true','1','yes','on'}
        value=true; ok=true;
    case {'false','0','no','off'}
        value=false; ok=true;
    otherwise
        value=false; ok=false;
end
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
if ~r.converged
    msg = 'Power flow did not converge.';
    if isfield(r,'reason'), msg = sprintf('%s\n  reason: %s', msg, r.reason); end
    if isfield(r,'finite_status'), msg = sprintf('%s\n  finite_status: %s', msg, r.finite_status); end
    if isfield(r,'iterations'), msg = sprintf('%s\n  iterations: %d', msg, r.iterations); end
    if isfield(r,'max_mismatch'), msg = sprintf('%s\n  max_mismatch: %.3e pu', msg, r.max_mismatch); end
    error('solve_case:pf', msg);
end
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
