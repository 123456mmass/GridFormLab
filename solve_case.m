function result = solve_case(varargin)
%SOLVE_CASE Interactive in-house PF / SSSA / TS / IBR launcher.
%   RESULT = SOLVE_CASE() opens analysis and case selection dialogs.
%   RESULT = SOLVE_CASE('analysis',ID,'case',ID,'options',OPT) is the
%   non-interactive form. Production: project solvers only; no external solver.

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
    'id',{'pf','sssa','ts','ibr'}, ...
    'label',{'Power Flow - in-house project solver (method via pf_method)', ...
             'Small-Signal Stability Analysis (SSSA)', ...
             'Transient Stability (TS)', ...
             'IBR Simulation - mixed-resource transient stability'});
if isempty(analysis)
    analysis=choose_item('Select analysis',{analyses.label},{analyses.id});
    if isempty(analysis), result=[]; return; end
end
if ~any(strcmp(analysis,{analyses.id}))
    error('solve_case:analysis','Unknown analysis %s.',analysis);
end

registry=case_registry(analysis);
if isempty(case_id)
    case_id=choose_item('Select case',{registry.label},{registry.id});
    if isempty(case_id), result=[]; return; end
end
idx=find(strcmp(case_id,{registry.id}),1);
if isempty(idx), error('solve_case:case','Case %s not supported for %s.',case_id,analysis); end
entry=registry(idx); case_data=entry.loader();

pf_opt=struct(); sssa_opt=struct(); ts_opt=struct(); ibr_opt=struct();
switch analysis
    case 'pf'
        pf_defaults=struct('verbose',true,'plot_results',true, ...
            'max_iter',50,'tolerance',1e-10,'enforce_q_limits',true, ...
            'q_limit_tolerance',1e-6,'max_q_limit_switches',20);
        pf_opt=merge_options(pf_defaults,user_opt);
        if case_selection_interactive
            [pf_opt,accepted]=prompt_pf_method(case_data,pf_opt,entry.label);
            if ~accepted, result=[]; return; end
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
            [ts_opt,accepted]=prompt_ts_integrator(ts_opt,entry.label);
            if ~accepted, result=[]; return; end
            [ts_opt,accepted]=prompt_ts_options(case_data,ts_opt,entry.label);
            if ~accepted, result=[]; return; end
        end
    case 'ibr'
        ibr_opt=merge_options(entry.options,user_opt);
        if case_selection_interactive
            [ibr_opt,accepted]=prompt_ibr_options(case_data,ibr_opt,entry.label);
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
        opt=pf_opt; print_run_options(opt);
        % Phase-2: resolve the PF method through the project-owned strategy.
        % pf_resolve_method returns [canonical_name, selection_source];
        % pf_method_strategy returns .solve (wraps the canonical NR verbatim
        % for 'newton_raphson' -> bit-identical) and .method_source (impl
        % provenance string). No silent fallback: unknown names error before
        % any solve.
        [pf_method_name, pf_selection_source] = pfsolver.pf_resolve_method(opt);
        pf_strat = pfsolver.pf_method_strategy(pf_method_name);
        result = pf_strat.solve(case_data, opt);
        % Additive metadata enrichment (fill-if-missing). FDPF/BFS already set
        % metadata.method_executed ('XB'/'BX'/'bfs'), method_source, capability,
        % fallback_used, full_ac_mismatch -> never clobber. NR lacks all of
        % these -> fill here. method_source (impl provenance) is distinct from
        % selection_source (default/explicit selector provenance).
        if ~isfield(result, 'metadata')
            result.metadata = struct();
        end
        if ~isfield(result.metadata, 'method_executed')
            result.metadata.method_requested = pf_method_name;
            result.metadata.method_executed  = pf_method_name;
            result.metadata.dispatch_requested = pf_method_name;
            result.metadata.method_source    = pf_strat.method_source;
            result.metadata.selection_source = pf_selection_source;
            result.metadata.capability       = pf_strat.capability;
            result.metadata.fallback_used    = false;
            % NR full_ac_mismatch sourced from the existing max_mismatch
            % (powerflow_newton_raphson.m attach_failure_fields); not recomputed.
            if isfield(result, 'max_mismatch')
                result.metadata.full_ac_mismatch = result.max_mismatch;
            end
        else
            % FDPF/BFS path: they already record method_executed/method_source/
            % capability/fallback_used/full_ac_mismatch. Only add the canonical
            % dispatch_requested and selection_source (selector provenance),
            % which they do not set. Preserve their method_requested as-is
            % (NOT uniform across NR/XB/BX/bfs).
            if ~isfield(result.metadata, 'dispatch_requested')
                result.metadata.dispatch_requested = pf_method_name;
            end
            if ~isfield(result.metadata, 'selection_source')
                result.metadata.selection_source = pf_selection_source;
            end
        end
        print_pf_checks(result,opt);
    case 'sssa'
        opt=sssa_opt; print_run_options(opt);
        result=stability.multicase_sssa(case_data,opt);
        result=annotate_sssa_result(result,opt);
        print_sssa_checks(result);
    case 'ts'
        opt=ts_opt; print_run_options(opt);
        result=stability.ts_simulate(case_data,opt);
        if ~isfield(opt,'plot_results') || opt.plot_results
            [fig,png]=plot_ts_result(result,entry.label,root,case_id);
            result.figure=fig; result.figure_file=png;
        end
        print_ts_checks(result);
    case 'ibr'
        opt=ibr_opt; print_run_options(opt);
        result = run_ibr_analysis(case_data, opt, entry.label, root, case_id);
end

result=annotate_launcher_execution(analysis,result);
if ~strcmp(analysis,'ibr'), print_launcher_execution(result.execution_summary); end

result.launcher=struct('analysis',analysis,'case_id',case_id, ...
    'case_label',entry.label,'log_file',logfile);
run_ok=~isfield(result,'converged') || logical(result.converged);
if run_ok, fprintf('\nSTATUS: COMPLETE\n'); else, fprintf('\nSTATUS: FAILED CLOSED\n'); end
fprintf('Saved log: %s\n',logfile);
diary('off');
if interactive
    msgbox(sprintf('Run complete\n%s\n\nLog:\n%s',entry.label,logfile), ...
        'solve_case','modal');
end
end

% =========================================================================
function result = run_ibr_analysis(case_data, opt, label, root, case_id)
% The IBR launcher is a thin case-profile adapter. Device construction,
% equilibrium, events, TS, index status, and rollback remain generic owners.
scenario_opt=struct();
if isfield(opt,'ibr_dispatch') && ~isempty(opt.ibr_dispatch)
    scenario_opt.dispatch=opt.ibr_dispatch;
end
base=cases.scenario_ieee14_1sg_4ibr(scenario_opt);
[scenario,selection]=stability.ibr_configure_scenario(base,opt);
if ~selection.ready
    result=struct('converged',false,'metadata',struct( ...
        'failure','solve_case:ibr:initialSelection', ...
        'error',selection.failure_reason),'selector_log',selection, ...
        'execution_summary',selection_failure_summary(selection));
    fprintf('\nIBR initial configuration rejected (no fallback).\n');
    stability.print_ibr_run_log(result);
    return;
end

% Programmatic callers may pass the normalized nested event struct directly.
% Interactive fields are converted to the same ABI here.
if ~isfield(opt,'ibr_events') || ~isstruct(opt.ibr_events)
    opt.ibr_events=event_struct_from_flat(opt);
end
result=stability.run_hybrid_case(scenario,opt);
result.selector_log=selection;
if isfield(result,'execution_summary')
    result.execution_summary.selector_candidate_evaluations=selection.candidate_count;
    result.execution_summary.sssa_invocations=selection.sssa_evaluations;
end
stability.print_ibr_run_log(result);

if result.converged && (~isfield(opt,'plot_results') || opt.plot_results)
    p=stability.plot_ibr_ts_results(result,struct( ...
        'output_dir',fullfile(root,'output','plots'),'visible', ...
        logical(option_value(opt,'plot_visible',false)),'prefix',case_id));
    result.figure_files={p.freq_plot,p.power_plot};
    fprintf('IBR plots (%s):\n  %s\n  %s\n',label,p.freq_plot,p.power_plot);
end
end

% =========================================================================
function r=case_registry(analysis)
catalog=cases.network_case_catalog();
switch analysis
    case 'pf'
        r=items_from_catalog(catalog,'pf_options');
    case 'sssa'
        r=items_from_catalog(catalog,'sssa_options');
        r=[r; item('sauer_pai','Sauer-Pai Example 8.3', ...
                @cases.sauer_pai_ex83_case,struct())];
    case 'ts'
        r=items_from_catalog(catalog,'ts_options');
    case 'ibr'
        r = [item('ieee14_1sg_4ibr','IEEE14 1-SG + 4-IBR (Kodsi SG1 + dual-mode IBRs)', ...
            @cases.case_ieee14_1sg_4ibr_auto_vsg, ibr_defaults())];
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

function [methods,labels]=pf_method_choices(case_data)
%PF_METHOD_CHOICES  Capability-aware PF method list (pure helper, no UI).
%   Returns the canonical method names and human-readable labels offered to a
%   user. BFS is included ONLY for radial cases (detected via case_is_radial);
%   it fails closed at run time for meshed networks, so it is hidden from the
%   picker for meshed cases. NR/FDPF-XB/FDPF-BX are always offered.
methods = {'newton_raphson','fdpf_xb','fdpf_bx'};
labels = {'Newton-Raphson (default)', ...
          'FDPF-XB (Stott-Alsac 1974)', ...
          'FDPF-BX (van Amerongen 1989)'};
if case_is_radial(case_data)
    methods{end+1} = 'bfs';
    labels{end+1} = 'BFS radial (Shirmohammadi 1988)';
end
end

function integrators=ts_integrator_choices()
%TS_INTEGRATOR_CHOICES  TS integrator list (pure helper, no UI).
%   Returns the canonical integrator names. trapezoidal is the default and
%   the only adaptive-capable integrator. RK4 is diagnostic-only.
integrators = {'trapezoidal','backward_euler','rk4'};
end

function tf = case_is_radial(case_data)
%CASE_IS_RADIAL  Minimal BFS Phase-1 capability pre-check (no throw).
%   Returns true if the case satisfies the defining radial conditions
%   (num_lines == num_buses-1 AND no PV buses). This is a UI HINT to hide bfs
%   from the picker; the authoritative fail-closed check remains
%   pf_validate_radial_topology inside powerflow_bfs.m at run time.
try
    model = pf_prepare_case(case_data);
    tf = (model.num_lines == model.num_buses - 1) && isempty(model.pv_buses);
catch
    tf = false;   % if the case cannot even be prepared, do not offer BFS
end
end

function [opt,accepted]=prompt_pf_method(case_data,opt,case_label)
%PROMPT_PF_METHOD  PF method dropdown picker (listdlg) before the settings.
%   Capability-aware: bfs is hidden when the case is meshed. The chosen
%   method flows into opt.pf_method, consumed by pf_resolve_method at
%   dispatch (Phase-2). accepted=false on cancel (caller aborts).
[methods,labels]=pf_method_choices(case_data);
cur='newton_raphson';
if isfield(opt,'pf_method')&&~isempty(opt.pf_method), cur=opt.pf_method; end
init=find(strcmp(cur,methods),1); if isempty(init), init=1; end
[sel,ok]=listdlg('PromptString',sprintf('Select PF method - %s',case_label), ...
    'SelectionMode','single','ListString',labels,'InitialValue',init, ...
    'ListSize',[360 200]);
if ~ok, opt=opt; accepted=false; return; end
opt.pf_method=methods{sel}; accepted=true;
end

function [opt,accepted]=prompt_ts_integrator(opt,case_label)
%PROMPT_TS_INTEGRATOR  TS integrator dropdown picker (listdlg) before settings.
%   trapezoidal is default + the only adaptive-capable integrator. RK4 is
%   diagnostic (bounded stability). The chosen integrator flows into
%   opt.integrator/opt.method, consumed by resolve_ts_integrator (Phase-2).
integrators=ts_integrator_choices();
labels={'Trapezoidal (default, adaptive-capable)', ...
        'Backward Euler (L-stable, fixed only)', ...
        'RK4 (diagnostic, fixed only)'};
cur='trapezoidal';
if isfield(opt,'integrator')&&~isempty(opt.integrator), cur=opt.integrator; end
if isfield(opt,'method')&&~isempty(opt.method)&&~any(strcmp(cur,integrators))
    cur=opt.method;
end
init=find(strcmp(cur,integrators),1); if isempty(init), init=1; end
[sel,ok]=listdlg('PromptString',sprintf('Select TS integrator - %s',case_label), ...
    'SelectionMode','single','ListString',labels,'InitialValue',init, ...
    'ListSize',[380 200]);
if ~ok, opt=opt; accepted=false; return; end
opt.integrator=integrators{sel}; opt.method=integrators{sel}; accepted=true;
end

function out=merge_options(defaults,user)
out=defaults; names=fieldnames(user);
for k=1:numel(names), out.(names{k})=user.(names{k}); end
end

function opt=ibr_defaults()
opt=struct('t_end',0.10,'dt',0.01,'verbose',false, ...
    'plot_results',true,'plot_visible',false, ...
    'initial_gfm_count',0,'initial_gfl_count',4,'initial_gfm_indices',[], ...
    'initial_reference_resource_index',[], ...
    'ibr_events',struct('enabled',true,'fault_bus',4,'Zf',1i*0.1, ...
        'fault_on',0.02,'fault_clear',0.03,'sg_trip',0.04,'sg_on',0.06, ...
        'selected_gfm_indices',2:5,'reference_resource_index',2));
end

function ev=event_struct_from_flat(opt)
required={'events_enabled','fault_bus','Zf','fault_on','fault_clear', ...
    'sg_trip','sg_on','post_trip_gfm_indices','post_trip_reference_resource_index'};
for k=1:numel(required)
    if ~isfield(opt,required{k})
        error('solve_case:ibr:eventOptions','Missing options.%s.',required{k});
    end
end
ev=struct('enabled',logical(opt.events_enabled),'fault_bus',opt.fault_bus, ...
    'Zf',opt.Zf,'fault_on',opt.fault_on,'fault_clear',opt.fault_clear, ...
    'sg_trip',opt.sg_trip,'sg_on',opt.sg_on, ...
    'selected_gfm_indices',opt.post_trip_gfm_indices, ...
    'reference_resource_index',opt.post_trip_reference_resource_index);
end

function summary=selection_failure_summary(selection)
summary=struct('pf_stage_invocations',3*selection.equilibrium_evaluations, ...
    'pf_stage_names',{{'selector_candidate_device/equilibrium/sssa_warm_starts'}}, ...
    'equilibrium_invocations',selection.equilibrium_evaluations, ...
    'equilibrium_newton_iterations',0, ...
    'sssa_invocations',selection.sssa_evaluations, ...
    'selector_candidate_evaluations',selection.candidate_count, ...
    'ts_invocations',0,'ts_step_attempts',0,'ts_accepted_steps',0, ...
    'ts_newton_iterations',0,'event_transactions',0);
end

function result=annotate_launcher_execution(analysis,result)
if isfield(result,'execution_summary'), return; end
summary=struct('pf_invocations',0,'sssa_invocations',0,'ts_invocations',0, ...
    'solver_iterations',0,'linearized_state_count',0,'eigenvalue_count',0, ...
    'ts_step_count',0);
switch analysis
    case 'pf'
        summary.pf_invocations=1;
        if isfield(result,'iterations'), summary.solver_iterations=result.iterations; end
    case 'sssa'
        summary.sssa_invocations=1;
        if isfield(result,'newton_iterations'), summary.solver_iterations=result.newton_iterations; end
        if isfield(result,'Afull'), summary.linearized_state_count=size(result.Afull,1); end
        if isfield(result,'eigenvalues'), summary.eigenvalue_count=numel(result.eigenvalues); end
    case 'ts'
        summary.ts_invocations=1;
        if isfield(result,'accepted_steps'), summary.ts_step_count=result.accepted_steps;
        elseif isfield(result,'t'), summary.ts_step_count=max(0,numel(result.t)-1); end
end
result.execution_summary=summary;
end

function print_launcher_execution(q)
fprintf('\n---------------- LAUNCHER WORK COUNTS --------------------\n');
fprintf('PF / SSSA / TS invocations : %d / %d / %d\n', ...
    q.pf_invocations,q.sssa_invocations,q.ts_invocations);
fprintf('Solver iterations          : %d\n',q.solver_iterations);
fprintf('Linearized states / roots  : %d / %d\n', ...
    q.linearized_state_count,q.eigenvalue_count);
fprintf('TS accepted steps          : %d\n',q.ts_step_count);
end

function [opt,accepted]=prompt_ibr_options(case_data,opt,case_label)
base=cases.scenario_ieee14_1sg_4ibr();
ids={base.resources.resource_id}; eligible=find(strcmp({base.resources.resource_type},'ibr'));
bus_text=format_bus_ids(case_bus_ids(case_data));
prompts={'t_end (s)';'dt (s)'; ...
    sprintf('Initial GFM count [0..%d]',numel(eligible)); ...
    sprintf('Initial GFL count [0..%d] (GFM+GFL=%d)',numel(eligible),numel(eligible)); ...
    sprintf('Initial GFM resource indices (eligible %s; blank=count selector)',mat2str(eligible)); ...
    'Initial GFM reference index (blank=automatic)'; ...
    'Enable IBR fault/trip events (true/false)'; ...
    sprintf('Fault bus (valid external IDs: %s)',bus_text);'Fault R (pu)';'Fault X (pu)'; ...
    'fault_on (s)';'fault_clear (s)';'sg_trip (s)';'sg_on request (s)'; ...
    'Post-trip GFM indices';'Post-trip reference index'; ...
    'Plot two audited IBR figures (true/false)';'Visible figures (true/false)'; ...
    'Verbose output (true/false)'};
ev=opt.ibr_events;
defaults={num_text(opt.t_end),num_text(opt.dt),num_text(opt.initial_gfm_count), ...
    num_text(opt.initial_gfl_count),index_text(opt.initial_gfm_indices),index_text(opt.initial_reference_resource_index), ...
    logical_text(ev.enabled),num_text(ev.fault_bus),num_text(real(ev.Zf)), ...
    num_text(imag(ev.Zf)),num_text(ev.fault_on),num_text(ev.fault_clear), ...
    num_text(ev.sg_trip),num_text(ev.sg_on),index_text(ev.selected_gfm_indices), ...
    num_text(ev.reference_resource_index),logical_text(opt.plot_results), ...
    logical_text(opt.plot_visible),logical_text(opt.verbose)};
accepted=false;
while true
    answer=inputdlg(prompts,sprintf('IBR settings - %s',case_label), ...
        repmat([1 72],numel(prompts),1),defaults,struct('Resize','on'));
    if isempty(answer), return; end
    [candidate,message]=parse_ibr_dialog(opt,answer,case_bus_ids(case_data),eligible,ids);
    if isempty(message), opt=candidate; accepted=true; return; end
    errordlg(message,'Invalid IBR settings','modal'); defaults=answer;
end
end

function [opt,message]=parse_ibr_dialog(opt,a,bus_ids,eligible,resource_ids)
message=''; nums=cellfun(@str2double,a([1 2 3 4 8:14 16]));
if any(~isfinite(nums)), message='All required numeric IBR settings must be finite.'; return; end
opt.t_end=nums(1); opt.dt=nums(2); opt.initial_gfm_count=nums(3); opt.initial_gfl_count=nums(4);
[initial,ok_i]=parse_index_text(a{5}); [iref,ok_ir]=parse_optional_scalar(a{6});
[enabled,ok_e]=parse_logical_text(a{7});
ev=struct('enabled',enabled,'fault_bus',nums(5),'Zf',nums(6)+1i*nums(7), ...
    'fault_on',nums(8),'fault_clear',nums(9),'sg_trip',nums(10), ...
    'sg_on',nums(11),'reference_resource_index',nums(12));
[post,ok_p]=parse_index_text(a{15}); ev.selected_gfm_indices=post;
[opt.plot_results,ok_plot]=parse_logical_text(a{17});
[opt.plot_visible,ok_vis]=parse_logical_text(a{18});
[opt.verbose,ok_verbose]=parse_logical_text(a{19});
if opt.t_end<=0 || opt.dt<=0, message='t_end and dt must be positive.';
elseif opt.initial_gfm_count<0 || opt.initial_gfm_count~=fix(opt.initial_gfm_count) || ...
        opt.initial_gfm_count>numel(eligible), message='Initial GFM count is out of range.';
elseif opt.initial_gfl_count<0 || opt.initial_gfl_count~=fix(opt.initial_gfl_count) || ...
        opt.initial_gfm_count+opt.initial_gfl_count~=numel(eligible)
    message=sprintf('Initial GFM+GFL counts must equal %d.',numel(eligible));
elseif ~ok_i || any(~ismember(initial,eligible)) || numel(unique(initial))~=numel(initial)
    message=sprintf('Initial indices must be unique members of %s (%s).',mat2str(eligible),strjoin(resource_ids(eligible),','));
elseif ~isempty(initial) && numel(initial)~=opt.initial_gfm_count
    message='Initial count must equal the explicit initial-index count.';
elseif ~ok_ir || (~isempty(iref) && ~ismember(iref,initial))
    message='Initial reference must belong to explicit initial GFM indices.';
elseif ~ok_e || ~ok_plot || ~ok_vis || ~ok_verbose
    message='Logical settings must be true/false.';
elseif enabled && (~ismember(ev.fault_bus,bus_ids) || abs(ev.Zf)<eps)
    message='Fault bus must be a valid external ID and Zf must be nonzero.';
elseif enabled && ~(ev.fault_on<ev.fault_clear && ev.fault_clear<=ev.sg_trip && ...
        ev.sg_trip<ev.sg_on && ev.sg_on<=opt.t_end)
    message='Require fault_on < fault_clear <= sg_trip < sg_on <= t_end.';
elseif enabled && (~ok_p || isempty(post) || any(~ismember(post,eligible)) || ...
        numel(unique(post))~=numel(post) || ~ismember(ev.reference_resource_index,post))
    message='Post-trip indices must be unique eligible resources and include the reference.';
end
if ~isempty(message), return; end
opt.initial_gfm_indices=initial;
opt.initial_reference_resource_index=iref;
opt.ibr_events=ev;
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
    answer=inputdlg(prompts,sprintf('PF settings - %s',case_label), ...
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
    message='All numeric PF settings must be finite numbers.'; return;
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
elseif opt.max_q_limit_switches<0 || opt.max_q_limit_switches~=fix(opt.max_q_limit_switches)
    message='Maximum Q-limit switching rounds must be a nonnegative integer.';
elseif ~ok_q || ~ok_verbose || ~ok_plot
    message='Logical PF settings must be true/false or 1/0.';
end
end

function [opt,accepted]=prompt_sssa_options(case_data,opt,case_label)
opt=sssa_dialog_defaults(case_data,opt);
prompts={'Dynamic model';'Finite-difference fd_eps';'Stability tol (1/s)';...
    'Equilibrium tol';'Max Newton iter';'Load model'};
defaults={char(opt.model),num_text(opt.fd_eps),num_text(opt.stability_tolerance),...
    num_text(opt.equilibrium_tolerance),num_text(opt.newton_max_iterations),char(opt.load_model)};
accepted=false;
while true
    answer=inputdlg(prompts,sprintf('SSSA - %s',case_label),...
        repmat([1 68],6,1),defaults,struct('Resize','on'));
    if isempty(answer), return; end
    [candidate,message]=parse_sssa_dialog(opt,answer);
    if isempty(message), opt=candidate; accepted=true; return; end
    errordlg(message,'Invalid SSSA','modal'); defaults=answer;
end
end

function opt=sssa_dialog_defaults(case_data,opt)
if ~isfield(opt,'model'), opt.model=''; end
model=char(opt.model);
if ~isfield(opt,'fd_eps')||isempty(opt.fd_eps)
    if strcmpi(model,'emf6'), opt.fd_eps=3e-6; else, opt.fd_eps=1e-6; end
end
if ~isfield(opt,'stability_tolerance')||isempty(opt.stability_tolerance), opt.stability_tolerance=1e-7; end
if ~isfield(opt,'equilibrium_tolerance')||isempty(opt.equilibrium_tolerance), opt.equilibrium_tolerance=1e-10; end
if ~isfield(opt,'newton_max_iterations')||isempty(opt.newton_max_iterations), opt.newton_max_iterations=300; end
if ~isfield(opt,'load_model')||isempty(opt.load_model)
    if isfield(case_data,'operating_point')&&isfield(case_data.operating_point,'load_model')
        opt.load_model=case_data.operating_point.load_model;
    else, opt.load_model='cz_p_cz_q'; end
end
end

function [opt,message]=parse_sssa_dialog(opt,a)
message=''; values=cellfun(@str2double,a(2:5));
if any(~isfinite(values)), message='All numeric settings must be finite.'; return; end
opt.model=lower(strtrim(a{1})); opt.fd_eps=values(1); opt.stability_tolerance=values(2);
opt.equilibrium_tolerance=values(3); opt.newton_max_iterations=values(4); opt.load_model=strtrim(a{6});
valid_models={'','classical','emf6','padiyar_1_1_avr','padiyar_1_1_manual'};
if ~any(strcmp(opt.model,valid_models)), message='Unsupported SSSA model.';
elseif opt.fd_eps<=0||opt.stability_tolerance<=0||opt.equilibrium_tolerance<=0
    message='Tolerances must be positive.';
elseif opt.newton_max_iterations<1||opt.newton_max_iterations~=fix(opt.newton_max_iterations)
    message='Newton iter must be positive integer.';
elseif isempty(opt.load_model), message='Load model must not be empty.'; end
end

function [opt,accepted]=prompt_ts_options(case_data,opt,case_label)
if ~isfield(opt,'pm_mode')||isempty(opt.pm_mode), opt.pm_mode='balanced'; end
bus_ids=case_bus_ids(case_data);
if ~isfield(opt,'fault_bus')||isempty(opt.fault_bus)||~ismember(opt.fault_bus,bus_ids)
    opt.fault_bus=bus_ids(1);
end
if ~isfield(opt,'corrector_iter')||isempty(opt.corrector_iter), fixed_iter_default=3;
else, fixed_iter_default=opt.corrector_iter; end
bus_text=format_bus_ids(bus_ids);
prompts={'t_end (s)';'dt (s)';sprintf('Fault bus (valid: %s)',bus_text);'t_fault (s)';...
    't_clear (s)';'Rf (pu)';'Xf (pu)';'Method';'Stepper';'Corrector mode';...
    'Abs tol';'Rel tol';'Max corr iter';'Fixed corr iter';'Pm mode';'Verbose';'Plot'};
defaults={num_text(opt.t_end),num_text(opt.dt),num_text(opt.fault_bus),...
    num_text(opt.t_fault),num_text(opt.t_clear),num_text(real(opt.Zf)),...
    num_text(imag(opt.Zf)),char(opt.method),char(opt.stepper),...
    char(opt.corrector_mode),num_text(opt.corrector_abs_tol),...
    num_text(opt.corrector_rel_tol),num_text(opt.max_corrector_iter),...
    num_text(fixed_iter_default),char(opt.pm_mode),logical_text(opt.verbose),logical_text(opt.plot_results)};
accepted=false;
while true
    answer=inputdlg(prompts,sprintf('TS - %s',case_label),repmat([1 62],17,1),defaults,struct('Resize','on'));
    if isempty(answer), return; end
    [candidate,message]=parse_ts_dialog(opt,answer,bus_ids);
    if isempty(message), opt=candidate; accepted=true; return; end
    errordlg(message,'Invalid TS','modal'); defaults=answer;
end
end

function [opt,message]=parse_ts_dialog(opt,a,bus_ids)
message=''; values=cellfun(@str2double,a([1:7 11:14]));
if any(~isfinite(values)), message='All numeric settings must be finite.'; return; end
opt.t_end=values(1); opt.dt=values(2); opt.fault_bus=values(3);
opt.t_fault=values(4); opt.t_clear=values(5); opt.Zf=values(6)+1i*values(7);
opt.corrector_abs_tol=values(8); opt.corrector_rel_tol=values(9);
opt.max_corrector_iter=values(10); fixed_iter=values(11);
opt.method=lower(strtrim(a{8})); opt.stepper=lower(strtrim(a{9}));
opt.corrector_mode=lower(strtrim(a{10})); opt.pm_mode=lower(strtrim(a{15}));
[opt.verbose,ok_verbose]=parse_logical_text(a{16});
[opt.plot_results,ok_plot]=parse_logical_text(a{17});
if opt.t_end<=0||opt.dt<=0, message='t_end and dt must be positive.';
elseif opt.t_fault<0||opt.t_clear<=opt.t_fault||opt.t_clear>opt.t_end
    message='Require 0<=t_fault<t_clear<=t_end.';
elseif opt.fault_bus~=fix(opt.fault_bus)||~ismember(opt.fault_bus,bus_ids)
    message=sprintf('Fault bus must be: %s.',format_bus_ids(bus_ids));
elseif ~any(strcmp(opt.method,{'trapezoidal','backward_euler','rk4'}))
    message='Method must be trapezoidal, backward_euler, or rk4.';
elseif strcmp(opt.stepper,'adaptive') && any(strcmp(opt.method,{'backward_euler','rk4'}))
    message='Adaptive stepper requires trapezoidal (BE/RK4 are fixed-step only).';
elseif ~any(strcmp(opt.stepper,{'fixed','adaptive'})), message='Stepper: fixed/adaptive.';
elseif ~any(strcmp(opt.corrector_mode,{'fixed','adaptive'})), message='Corrector: fixed/adaptive.';
elseif opt.corrector_abs_tol<=0||opt.corrector_rel_tol<=0, message='Tolerances positive.';
elseif opt.max_corrector_iter<1||opt.max_corrector_iter~=fix(opt.max_corrector_iter)
    message='Max corr iter positive integer.';
elseif fixed_iter<1||fixed_iter~=fix(fixed_iter), message='Fixed corr iter positive integer.';
elseif ~ok_verbose||~ok_plot, message='verbose/plot must be true/false.';
else if strcmp(opt.corrector_mode,'fixed'), opt.corrector_iter=fixed_iter; end
end
end

function ids=case_bus_ids(c)
if isfield(c,'mpc')&&isfield(c.mpc,'bus'), ids=c.mpc.bus(:,1);
elseif isfield(c,'bus_data'), ids=c.bus_data(:,1);
else error('solve_case:busIds','No bus IDs.'); end
ids=unique(ids(:),'stable');
end

function text=format_bus_ids(ids)
ids=ids(:).';
if numel(ids)<=24, text=strjoin(compose('%g',ids),', ');
else text=sprintf('%s,... (%d buses)',strjoin(compose('%g',ids(1:20)),', '),numel(ids)); end
end

function text=num_text(value), text=sprintf('%.12g',value); end
function text=index_text(value)
if isempty(value), text=''; else, text=strjoin(compose('%d',reshape(value,1,[])),','); end
end
function [value,ok]=parse_index_text(text)
text=strtrim(text);
if isempty(text), value=[]; ok=true; return; end
parts=regexp(text,'[,;\s]+','split'); value=str2double(parts);
ok=all(isfinite(value)) && all(value==fix(value));
if ok, value=reshape(value,1,[]); else, value=[]; end
end
function [value,ok]=parse_optional_scalar(text)
if isempty(strtrim(text)), value=[]; ok=true; return; end
value=str2double(text); ok=isscalar(value)&&isfinite(value)&&value==fix(value);
if ~ok, value=[]; end
end
function text=logical_text(value), if value, text='true'; else, text='false'; end; end
function [value,ok]=parse_logical_text(text)
switch lower(strtrim(text))
    case {'true','1','yes','on'}, value=true; ok=true;
    case {'false','0','no','off'}, value=false; ok=true;
    otherwise, value=false; ok=false;
end
end

function value=option_value(s,name,default)
value=default; if isfield(s,name)&&~isempty(s.(name)), value=s.(name); end
end

function print_case_manifest(c)
if isfield(c,'schema_version'), fprintf('Schema   : %s\n',c.schema_version); end
if isfield(c,'base_values'), fprintf('Base     : %.6g MVA, %.6g Hz\n',c.base_values.S_base_MVA,c.base_values.frequency_Hz); end
if isfield(c,'bus_data'), fprintf('Network  : %d buses, %d branches\n',size(c.bus_data,1),size(c.line_data,1)); end
end

function print_run_options(opt)
fprintf('\n---------------- RUN SETTINGS -------------------\n');
names=fieldnames(opt);
for k=1:numel(names)
    name=names{k}; value=opt.(name);
    if islogical(value)&&isscalar(value), text=mat2str(value);
    elseif isnumeric(value)&&isscalar(value)
        if isreal(value), text=sprintf('%.12g',value); else, text=sprintf('%.12g %+.12gj',real(value),imag(value)); end
    elseif ischar(value)||(isstring(value)&&isscalar(value)), text=char(value);
    elseif isempty(value), text='[]';
    else, text=sprintf('<%s %s>',class(value),mat2str(size(value))); end
    fprintf('%-20s: %s\n',name,text);
end
end

function print_pf_checks(r,opt)
fprintf('\n---------------- PF VERIFICATION ----------------\n');
fprintf('Converged       : %d\n',r.converged);
if isfield(r,'iterations'), fprintf('Iterations      : %d\n',r.iterations); end
if isfield(r,'max_mismatch'), fprintf('Max mismatch    : %.3e pu\n',r.max_mismatch); end
% Phase-2: report the executed method (additive, optional fields).
if isfield(r,'metadata')
    if isfield(r.metadata,'method_executed')
        fprintf('Method executed : %s\n',r.metadata.method_executed);
    end
    if isfield(r.metadata,'dispatch_requested')
        fprintf('Dispatch req    : %s\n',r.metadata.dispatch_requested);
    end
end
fprintf('Voltage range   : %.6f .. %.6f pu\n',min(r.bus_voltage),max(r.bus_voltage));
fprintf('Angle range     : %.6f .. %.6f deg\n',min(r.bus_angle_deg),max(r.bus_angle_deg));
fprintf('Tolerance       : %.3e\n',opt.tolerance);
if ~r.converged
    msg='Power flow did not converge.';
    if isfield(r,'reason'), msg=sprintf('%s\n  reason: %s',msg,r.reason); end
    error('solve_case:pf', msg);
end
end

function print_sssa_checks(r)
fprintf('\n---------------- SSSA VERIFICATION --------------\n');
fprintf('Dynamic states  : %d\n',numel(r.state_names));
fprintf('Stability status: %s\n',r.stability_status);
fprintf('Decision tol.   : %.3e 1/s\n',r.stability_tolerance);
if isfield(r,'reduced_eigenvalues') && ...
        numel(r.reduced_eigenvalues) < numel(r.eigenvalues)
    fprintf('Decision basis  : COI-relative set (%d roots)\n', ...
        numel(r.reduced_eigenvalues));
else
    fprintf('Decision basis  : full state eigenvalue set (%d roots)\n', ...
        numel(r.eigenvalues));
end
fprintf('Root counts     : stable=%d, marginal=%d, unstable=%d\n',r.root_counts.stable,r.root_counts.marginal,r.root_counts.unstable);
if isfield(r,'newton_residual'), fprintf('DAE residual    : %.3e\n',r.newton_residual); end
fprintf('\nSTATE INVENTORY\n');
for k=1:numel(r.state_names), fprintf('  x(%-3d) %s\n',k,r.state_names{k}); end
lam=r.eigenvalues(:);
fprintf('\nFULL STATE EIGENVALUES\n');
fprintf('Eigenvalue set  : %d roots\n',numel(lam));
fprintf('Max real(lambda): %+.6e 1/s\n',max(real(lam)));
[lam_table, mode_labels, display_order] = sssa_table_display_order(r, lam);
fprintf('Display order   : %s\n',display_order);
A_tbl = r.Afull;
snm = r.state_names;
print_eigenvalue_table(A_tbl, snm, lam_table, mode_labels);
end

function r=annotate_sssa_result(r,opt)
if ~isfield(r,'state_names')||isempty(r.state_names)
    r.state_names=arrayfun(@(k)sprintf('x%d',k),1:size(r.Afull,1),'UniformOutput',false).';
else, r.state_names=r.state_names(:); end
if isfield(r,'reduced_eigenvalues'), lam=r.reduced_eigenvalues(:); else, lam=r.eigenvalues(:); end
tol=1e-7; if isfield(opt,'stability_tolerance'), tol=opt.stability_tolerance; end
nu=sum(real(lam)>tol); ns=sum(real(lam)<-tol); nm=numel(lam)-nu-ns;
if isempty(lam), status='NOT APPLICABLE - NO RELATIVE MODES';
elseif nu>0, status='UNSTABLE'; elseif nm>0, status='MARGINAL';
else, status='ASYMPTOTICALLY STABLE'; end
r.stability_status=status; r.stability_tolerance=tol; r.root_counts=struct('stable',ns,'marginal',nm,'unstable',nu);
end

function print_ts_checks(r)
fprintf('\n---------------- TS VERIFICATION ----------------\n');
fprintf('Samples         : %d\n',numel(r.t));
fprintf('Time range      : %.4f .. %.4f s\n',r.t(1),r.t(end));
fprintf('Minimum voltage : %.6f pu\n',min(r.Vbus,[],'all'));
if isfield(r,'omega_is_deviation')&&r.omega_is_deviation, wd=r.omega; else, wd=r.omega-1; end
fprintf('Max |Delta w|   : %.6e pu\n',max(abs(wd),[],'all'));
% Phase-2: report the executed integrator (additive, optional field).
if isfield(r,'integrator')
    fprintf('Integrator      : %s\n',r.integrator);
end
end


% =========================================================================
function print_eigenvalue_table(A, state_names, lam, mode_labels)
%PRINT_EIGENVALUE_TABLE  Eigenvalues with f(Hz)/zeta + dominant state
%   using participation factors (scale-invariant left×right product).
if nargin<3||isempty(A)||isempty(lam), return; end
if nargin<4||isempty(mode_labels), mode_labels=cell(numel(lam),1); end
nx=size(A,1); lam=lam(:); nms=state_names(:);
mode_labels=mode_labels(:);
if nx~=numel(lam)||nx~=numel(nms)||nx~=numel(mode_labels), return; end
[V,Dval]=eig(A); W=V\eye(size(V)); d=diag(Dval);
perm=zeros(nx,1); tag=false(nx,1);
for i=1:nx
  for j=1:nx
    if ~tag(j)&&abs(d(j)-lam(i))<1e-6, perm(i)=j; tag(j)=true; break; end
  end, end
if any(perm==0), perm=(1:nx)'; end
fprintf('\n  No  Dominant state              Real (1/s)   Imag (1/s)       f(Hz)       zeta  Mode\n');
for i=1:nx
  pc=perm(i); re_i=real(lam(i)); im_i=imag(lam(i));
  pf_vals=abs(V(:,pc).*W(pc,:).'); [~,bi]=max(pf_vals); lbl=char(nms{bi});
  fhz=abs(im_i)/(2*pi); zet=-re_i/(abs(lam(i))+eps);
  cm=mode_labels{i};
  if isempty(cm), cm=mode_comment(lbl,abs(im_i)); end
  fprintf('  %02d  %-24s %+11.2e %+11.2e %11.2e %10.2e  %s\n', ...
      i,lbl,re_i,im_i,fhz,zet,cm);
end
end

function [lam_table, mode_labels, description] = sssa_table_display_order(r, lam)
%SSSA_TABLE_DISPLAY_ORDER  Presentation-only ordering for launcher output.
%   Native eigensolver order has no physical or published-row meaning. A
%   model wrapper may attach validated diagnostic display metadata after its
%   eigenproblem is complete. The launcher never reads a reference target.
lam=lam(:); n=numel(lam);
lam_table=lam; mode_labels=cell(n,1);
description='computed eigensolver order';
if ~isfield(r,'launcher_eigenvalue_display') || ...
        ~isstruct(r.launcher_eigenvalue_display)
    return;
end
md=r.launcher_eigenvalue_display;
required={'order','mode_labels','description','diagnostic_only'};
if ~all(isfield(md,required)) || ~isequal(md.diagnostic_only,true)
    return;
end
order=md.order(:);
labels=md.mode_labels(:);
if numel(order)~=n || numel(labels)~=n || ...
        any(~isfinite(order)) || any(order~=fix(order)) || ...
        ~isequal(sort(order),(1:n).') || ...
        ~(ischar(md.description) || (isstring(md.description) && isscalar(md.description)))
    return;
end
lam_table=lam(order);
mode_labels=labels;
description=char(md.description);
end

function cm = mode_comment(lbl, om_b)
s = lower(lbl);
if contains(s,'omega')
    if om_b > 1e-8
        cm = 'electro-mec';
    else, cm = 'rotor damp'; end
elseif contains(s,'delta')
    if om_b > 1e-8
        cm = 'electro-mec';
    else, cm = 'rotor relax'; end
elseif contains(s,'efd'), cm = 'exciter fld';
elseif contains(s,'eqp')||contains(s,'edp'), cm = 'transient';
elseif contains(s,'eq')||contains(s,'ed'), cm = 'field-trans';
elseif contains(s,'_{q')||contains(s,'_{d'), cm = 'field-trans';
elseif contains(s,'vr')||contains(s,'v_r'), cm = 'exciter reg';
elseif contains(s,'r_f'), cm = 'exciter stab';
else, cm = '';
end
end
