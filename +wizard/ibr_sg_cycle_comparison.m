function result = ibr_sg_cycle_comparison(case_data, scenario, selection, opt, include_sssa, output_root, case_id)
%IBR_SG_CYCLE_COMPARISON  Three-point SG trip/return PF and SSSA comparison.
%   This reporting/orchestration helper solves three independent stationary
%   operating points with the existing mixed-resource production equations:
%     PRE_TRIP   - SG online; caller-selected initial GFM/GFL composition.
%     SG_TRIPPED - SG breaker open; all capable IBRs in GFM mode and the
%                  CASE_DEFINED post-trip dispatch applied.
%     SG_RETURNED- SG online and reference restored at Phase-1 reclose; IBRs
%                  remain in post-trip GFM modes and dispatch is preserved.
%
%   The helper does not simulate a fault, bypass the synchronism guard, or
%   claim that the physical reclose transaction succeeds.  It is an indexed
%   operating-point comparison.  Each point is re-solved with
%   stability.mixed_equilibrium_solve; optional SSSA differentiates those
%   exact equations through stability.composite_sssa_model.

arguments
    case_data struct
    scenario struct
    selection struct
    opt struct = struct()
    include_sssa (1,1) logical = false
    output_root char = ''
    case_id char = 'ieee14_1sg_4ibr'
end

labels = {'PRE_TRIP','SG_TRIPPED','SG_RETURNED'};
[specs, build_note] = operating_point_specs(case_data, scenario);
points = repmat(empty_point(), 1, 3);
for k = 1:3
    points(k) = solve_point(case_data, specs(k), opt, include_sssa, labels{k});
end

result = struct();
result.ibr_analysis = ternary(include_sssa, 'sssa_compare', 'pf_compare');
result.analysis_classification = 'PROJECT_DERIVED_OPERATING_POINT_COMPARISON';
result.sequence = labels;
result.sequence_note = build_note;
result.points = points;
result.device_rows = device_comparison_rows(points, case_data);
result.bus_rows = bus_comparison_rows(points, case_data);
result.state_rows = state_comparison_rows(points);
result.spectrum_rows = spectrum_comparison_rows(points);
result.mode_pairing_policy = ['Independent deterministic display order at each operating point; ' ...
    'rows are NOT cross-operating-point eigenmode matches.'];
result.converged = all([points.equilibrium_converged]) && ...
    (~include_sssa || all([points.sssa_converged]));
result.failure_id = '';
result.failure_reason = '';
if ~result.converged
    bad = find(~[points.equilibrium_converged] | ...
        (include_sssa & ~[points.sssa_converged]), 1);
    result.failure_id = 'wizard:ibr_sg_cycle_comparison:operatingPoint';
    result.failure_reason = sprintf('%s failed closed: %s', ...
        points(bad).label, points(bad).failure_reason);
end

result.pf = [];
result.equilibrium = [];
result.sssa = [];
result.ts = [];
result.selector_log = selection;
n_eq_iter = sum(arrayfun(@(p) p.equilibrium.iterations, ...
    points([points.equilibrium_converged])));
result.execution_summary = struct( ...
    'pf_stage_invocations', 3*numel(points), ...
    'pf_stage_names', {{'device_factory_warm_start','equilibrium_dae_warm_start','comparison_point'}}, ...
    'equilibrium_invocations', numel(points), ...
    'equilibrium_newton_iterations', n_eq_iter, ...
    'sssa_invocations', double(include_sssa)*sum([points.equilibrium_converged]), ...
    'selector_candidate_evaluations', selection.candidate_count, ...
    'ts_invocations', 0, 'ts_step_attempts', 0, 'ts_accepted_steps', 0, ...
    'ts_newton_iterations', 0, 'event_transactions', 0);

result.figure_files = {};
if option_value(opt, 'plot_results', true) && any([points.equilibrium_converged])
    result.figure_files = comparison_plot(result.device_rows, opt, output_root, case_id);
end
print_comparison(result, case_data, include_sssa);
end

function [specs, note] = operating_point_specs(case_data, scenario)
if ~isfield(case_data,'dispatch_contract') || ...
        ~isfield(case_data.dispatch_contract,'post_trip') || ...
        ~isfield(case_data.dispatch_contract.post_trip,'post_trip_Pg_MW')
    error('wizard:ibr_sg_cycle_comparison:missingDispatch', ...
        'The case must provide dispatch_contract.post_trip.post_trip_Pg_MW.');
end
post_dispatch = case_data.dispatch_contract.post_trip.post_trip_Pg_MW;
resources_pre = scenario.resources;
pre_opt = scenario.scenario_opt;

is_sg = arrayfun(@(r) strcmpi(char(r.resource_type),'sg'), resources_pre);
is_ibr = arrayfun(@(r) strcmpi(char(r.resource_type),'ibr'), resources_pre);
if sum(is_sg) ~= 1 || ~any(is_ibr)
    error('wizard:ibr_sg_cycle_comparison:resourceMap', ...
        'Comparison requires exactly one SG and at least one IBR resource.');
end

resources_trip = resources_pre;
resources_trip(is_sg).initial_online = false;
resources_trip(is_sg).initial_mode = 'breaker_open';
for k = find(is_ibr)
    if ~any(strcmpi(string(resources_trip(k).supported_modes),'gfm'))
        error('wizard:ibr_sg_cycle_comparison:unsupportedTripMode', ...
            'Resource %s cannot provide the required post-trip GFM mode.', ...
            char(resources_trip(k).resource_id));
    end
    resources_trip(k).initial_mode = 'gfm';
end
trip_opt = pre_opt;
trip_opt.dispatch = post_dispatch;

resources_return = resources_pre;
resources_return(is_sg).initial_online = true;
resources_return(is_sg).initial_mode = 'synchronous';
for k = find(is_ibr)
    resources_return(k).initial_mode = 'gfm';
end
return_opt = pre_opt;
return_opt.dispatch = post_dispatch;

specs = repmat(struct('resources',[],'scenario_opt',struct(), ...
    'selected_gfm_indices',[],'reference_resource_index',[]), 1, 3);
specs(1).resources = resources_pre;
specs(1).scenario_opt = pre_opt;
if isfield(scenario,'config') && isstruct(scenario.config)
    if isfield(scenario.config,'selected_gfm_indices')
        specs(1).selected_gfm_indices = scenario.config.selected_gfm_indices;
    end
    if isfield(scenario.config,'reference_resource_index')
        specs(1).reference_resource_index = scenario.config.reference_resource_index;
    end
end
specs(2).resources = resources_trip;
specs(2).scenario_opt = trip_opt;
specs(2).selected_gfm_indices = find(is_ibr);
specs(2).reference_resource_index = specs(2).selected_gfm_indices(1);
specs(3).resources = resources_return;
specs(3).scenario_opt = return_opt;
note = ['No fault is required. SG_TRIPPED uses the case post-trip dispatch and all capable IBRs as GFM. ' ...
    'SG_RETURNED is the Phase-1 reclose operating point: SG reference ownership returns while IBRs remain in post-trip GFM modes and preserve post-trip dispatch.'];
end

function point = solve_point(case_data, spec, opt, include_sssa, label)
point = empty_point();
point.label = label;
try
    [devices, dev_meta] = stability.build_mixed_resource_devices( ...
        case_data, spec.resources, spec.scenario_opt);
catch me
    point.failure_id = me.identifier;
    point.failure_reason = me.message;
    return;
end
config = struct('devices', devices, ...
    'resource_ids', {{spec.resources.resource_id}});
if ~isempty(spec.selected_gfm_indices)
    config.selected_gfm_indices = spec.selected_gfm_indices;
    config.n_gfm_required = numel(spec.selected_gfm_indices);
    config.reference_resource_index = spec.reference_resource_index;
end
eq_opt = struct('verbose', logical(option_value(opt,'verbose',false)), ...
    'tolerance', option_value(opt,'equilibrium_tolerance',1e-8), ...
    'max_iter', option_value(opt,'newton_max_iterations',300), ...
    'load_model', option_value(opt,'load_model','cz_p_cz_q'));
eq = stability.mixed_equilibrium_solve(case_data, config, eq_opt);
point.equilibrium = eq;
point.equilibrium_converged = logical(eq.converged);
point.device_build = dev_meta;
if ~eq.converged
    point.failure_id = eq.failure_id;
    point.failure_reason = eq.failure_reason;
    return;
end
point.snapshot = equilibrium_snapshot(eq, case_data);
if include_sssa
    try
        sssa_opt = struct('full_kcl',true,'u_eq',eq.u_eq, ...
            'event_context',eq.equilibrium_context, ...
            'active_state_indices',eq.active_state_indices, ...
            'fd_eps',option_value(opt,'fd_eps',3e-6));
        sssa = stability.composite_sssa_model(eq.devices,eq.x0,eq.y0,case_data,sssa_opt);
        point.sssa = classify_sssa(sssa,option_value(opt,'stability_tolerance',1e-7));
        point.sssa_converged = true;
        point.modal = modal_snapshot(point.sssa,eq);
    catch me
        point.failure_id = me.identifier;
        point.failure_reason = me.message;
    end
end
end

function snap = equilibrium_snapshot(eq, case_data)
devices = eq.devices;
nd = numel(devices);
V = eq.y0(1:2:end) + 1i*eq.y0(2:2:end);
Sbase = case_data.mpc.baseMVA;
base_kV = NaN;
if isfield(case_data,'base_values') && isfield(case_data.base_values,'V_base_kV')
    base_kV = case_data.base_values.V_base_kV;
end
rows = repmat(struct('resource_index',0,'device_index',0,'device_id','', ...
    'bus_position',0,'bus_id',0,'device_type','','mode','','online',false, ...
    'P_pu',NaN,'Q_pu',NaN,'P_MW',NaN,'Q_MVAr',NaN, ...
    'V_pu',NaN,'V_kV',NaN,'angle_deg',NaN), nd, 1);
xoff=0; uoff=0;
for k=1:nd
    dev=devices(k); xr=xoff+(1:dev.nx); ur=uoff+(1:dev.nu);
    rec=dev.reconstruct(0,eq.x0(xr),eq.y0,eq.u_eq(ur),eq.equilibrium_context);
    I=dev.current_injection(0,eq.x0(xr),eq.y0,eq.u_eq(ur),eq.equilibrium_context);
    S=V(dev.bus_position)*conj(I);
    rows(k).resource_index=k; rows(k).device_index=k;
    rows(k).device_id=char(dev.device_id); rows(k).bus_position=dev.bus_position;
    rows(k).bus_id=dev.bus_id; rows(k).device_type=char(dev.device_type);
    rows(k).mode=char(rec.mode); rows(k).online=logical(rec.online);
    rows(k).P_pu=real(S); rows(k).Q_pu=imag(S);
    rows(k).P_MW=real(S)*Sbase; rows(k).Q_MVAr=imag(S)*Sbase;
    rows(k).V_pu=abs(V(dev.bus_position));
    rows(k).V_kV=rows(k).V_pu*base_kV;
    rows(k).angle_deg=rad2deg(angle(V(dev.bus_position)));
    xoff=xoff+dev.nx; uoff=uoff+dev.nu;
end
snap = struct('devices',rows,'bus_ids',case_data.mpc.bus(:,1), ...
    'V_pu',abs(V),'V_kV',abs(V)*base_kV,'angle_deg',rad2deg(angle(V)), ...
    'physical_kcl_norm',eq.physical_kcl_norm, ...
    'active_state_count',numel(eq.active_state_indices));
end

function s = classify_sssa(s,tol)
lam=s.eigenvalues(:); nu=sum(real(lam)>tol); ns=sum(real(lam)<-tol); nm=numel(lam)-nu-ns;
if nu>0, status='UNSTABLE'; elseif nm>0, status='MARGINAL'; else, status='ASYMPTOTICALLY STABLE'; end
s.execution_converged=true; s.stability_status=status; s.stability_tolerance=tol;
s.root_counts=struct('stable',ns,'marginal',nm,'unstable',nu);
end

function rows = modal_snapshot(sssa,eq)
m=stability.modal_analysis(sssa); active=sssa.active_state_indices(:);
rows=repmat(struct('display_mode_number',0,'raw_eigen_index',0,'pair_id',0, ...
    'lambda',NaN,'frequency_Hz',NaN,'damping_ratio',NaN, ...
    'dominant_reduced_state_index',0,'dominant_global_state_index',0, ...
    'dominant_device_index',0,'dominant_device_id','', ...
    'dominant_local_state_index',0,'dominant_state_name','', ...
    'participation_percent',NaN),numel(m.eigenvalues),1);
offsets=[0 cumsum([eq.devices.nx])];
for k=1:numel(m.eigenvalues)
    [rho,ri]=max(m.display_ranking(:,k)); gi=active(ri);
    dk=find(gi>offsets(1:end-1) & gi<=offsets(2:end),1); li=gi-offsets(dk);
    lam=m.eigenvalues(k);
    rows(k)=struct('display_mode_number',m.display_mode_number(k), ...
        'raw_eigen_index',m.raw_eigen_index(k),'pair_id',m.conjugate_pair_id(k), ...
        'lambda',lam,'frequency_Hz',abs(imag(lam))/(2*pi), ...
        'damping_ratio',-real(lam)/(abs(lam)+eps), ...
        'dominant_reduced_state_index',ri,'dominant_global_state_index',gi, ...
        'dominant_device_index',dk,'dominant_device_id',char(eq.devices(dk).device_id), ...
        'dominant_local_state_index',li, ...
        'dominant_state_name',char(eq.devices(dk).state_names{li}), ...
        'participation_percent',100*rho);
end
end

function rows = device_comparison_rows(points,case_data)
nd=max(arrayfun(@(p) snapshot_device_count(p),points));
rows=repmat(struct('index',0,'resource_index',0,'device_index',0,'device_id','', ...
    'bus_position',0,'bus_id',0,'pre',struct(),'tripped',struct(),'returned',struct(), ...
    'delta_trip_from_pre',struct(),'delta_return_from_pre',struct()),nd,1);
for k=1:nd
    vals=cell(1,3);
    for j=1:3
        if points(j).equilibrium_converged, vals{j}=points(j).snapshot.devices(k);
        else, vals{j}=missing_device_value(k); end
    end
    rows(k).index=k; rows(k).resource_index=vals{1}.resource_index;
    rows(k).device_index=vals{1}.device_index; rows(k).device_id=vals{1}.device_id;
    rows(k).bus_position=vals{1}.bus_position; rows(k).bus_id=vals{1}.bus_id;
    rows(k).pre=vals{1}; rows(k).tripped=vals{2}; rows(k).returned=vals{3};
    rows(k).delta_trip_from_pre=delta_value(vals{2},vals{1});
    rows(k).delta_return_from_pre=delta_value(vals{3},vals{1});
end
if isempty(rows) && ~isempty(case_data), rows=rows([]); end
end

function rows = bus_comparison_rows(points,case_data)
ids=case_data.mpc.bus(:,1); nb=numel(ids);
rows=repmat(struct('index',0,'bus_position',0,'bus_id',0, ...
    'pre',struct(),'tripped',struct(),'returned',struct(), ...
    'delta_trip_from_pre',struct(),'delta_return_from_pre',struct()),nb,1);
for k=1:nb
    vals=cell(1,3);
    for j=1:3
        if points(j).equilibrium_converged
            vals{j}=struct('V_pu',points(j).snapshot.V_pu(k), ...
                'V_kV',points(j).snapshot.V_kV(k),'angle_deg',points(j).snapshot.angle_deg(k));
        else
            vals{j}=struct('V_pu',NaN,'V_kV',NaN,'angle_deg',NaN);
        end
    end
    rows(k).index=k; rows(k).bus_position=k; rows(k).bus_id=ids(k);
    rows(k).pre=vals{1}; rows(k).tripped=vals{2}; rows(k).returned=vals{3};
    rows(k).delta_trip_from_pre=bus_delta(vals{2},vals{1});
    rows(k).delta_return_from_pre=bus_delta(vals{3},vals{1});
end
end

function rows = state_comparison_rows(points)
ok=find([points.equilibrium_converged],1); if isempty(ok), rows=struct([]); return; end
devs=points(ok).equilibrium.devices; nx=sum([devs.nx]);
rows=repmat(struct('global_state_index',0,'device_index',0,'device_id','', ...
    'local_state_index',0,'state_name','','pre_A_index',NaN, ...
    'tripped_A_index',NaN,'returned_A_index',NaN),nx,1);
g=0;
for d=1:numel(devs)
    for li=1:devs(d).nx
        g=g+1; rows(g).global_state_index=g; rows(g).device_index=d;
        rows(g).device_id=char(devs(d).device_id); rows(g).local_state_index=li;
        rows(g).state_name=char(devs(d).state_names{li});
        for p=1:3
            if points(p).equilibrium_converged
                ai=find(points(p).equilibrium.active_state_indices==g,1);
                if ~isempty(ai)
                    fld={'pre_A_index','tripped_A_index','returned_A_index'};
                    rows(g).(fld{p})=ai;
                end
            end
        end
    end
end
end

function rows = spectrum_comparison_rows(points)
n=max(arrayfun(@(p) numel(p.modal),points));
rows=repmat(struct('display_row',0,'pairing_status','NOT_MODE_MATCHED', ...
    'pre',struct(),'tripped',struct(),'returned',struct()),n,1);
for k=1:n
    rows(k).display_row=k;
    names={'pre','tripped','returned'};
    for p=1:3
        if numel(points(p).modal)>=k, rows(k).(names{p})=points(p).modal(k);
        else, rows(k).(names{p})=struct(); end
    end
end
end

function files = comparison_plot(rows,opt,root,case_id)
files={}; if isempty(rows), return; end
if isempty(root), root=pwd; end
outdir=fullfile(root,'output','plots'); if ~isfolder(outdir), mkdir(outdir); end
visible='off'; if option_value(opt,'plot_visible',false), visible='on'; end
labels=arrayfun(@(r) sprintf('%s@Bus%d',r.device_id,r.bus_id),rows,'UniformOutput',false);
P=zeros(numel(rows),3); Q=P; V=P;
for k=1:numel(rows)
    P(k,:)=[rows(k).pre.P_MW rows(k).tripped.P_MW rows(k).returned.P_MW];
    Q(k,:)=[rows(k).pre.Q_MVAr rows(k).tripped.Q_MVAr rows(k).returned.Q_MVAr];
    V(k,:)=[rows(k).pre.V_pu rows(k).tripped.V_pu rows(k).returned.V_pu];
end
fig=figure('Visible',visible,'Color','w','Name','IBR SG trip/return comparison');
tl=tiledlayout(fig,3,1,'TileSpacing','compact','Padding','compact');
titles={'Active-power injection P_e (MW)','Reactive-power injection Q (MVAr)','Terminal-bus voltage |V| (pu)'};
data={P,Q,V};
for j=1:3
    ax=nexttile(tl); bar(ax,data{j},'grouped'); grid(ax,'on'); ylabel(ax,titles{j});
    ax.XTick=1:numel(labels); ax.XTickLabel=labels; ax.XTickLabelRotation=20;
    if j==1, legend(ax,{'Pre-trip','SG tripped','SG returned'},'Location','best'); end
end
title(tl,'SG Trip / Return Operating-Point Comparison');
stamp=char(datetime('now','Format','yyyyMMdd_HHmmss'));
file=fullfile(outdir,sprintf('%s_%s_sg_cycle_compare.png',stamp,case_id));
exportgraphics(fig,file,'Resolution',180); files={file};
end

function print_comparison(result,case_data,include_sssa)
fprintf('\n================ SG TRIP / RETURN COMPARISON ================\n');
fprintf('Class : %s\n',result.analysis_classification);
fprintf('Note  : %s\n',result.sequence_note);
fprintf('\nOPERATING-POINT STATUS\n');
for k=1:3
    p=result.points(k);
    fprintf('  %-11s equilibrium=%d active=%d KCL=%.3e',p.label,p.equilibrium_converged, ...
        active_count(p),kcl_value(p));
    if include_sssa, fprintf(' SSSA=%d',p.sssa_converged); end
    if ~isempty(p.failure_reason), fprintf(' reason=%s',p.failure_reason); end
    fprintf('\n');
end
fprintf('\nDEVICE PF COMPARISON (one indexed row; values from solved equilibria)\n');
fprintf('Idx Device@Bus  Pre P/Q/V        Tripped P/Q/V    Returned P/Q/V   dP(trip) dP(return)\n');
for k=1:numel(result.device_rows)
    r=result.device_rows(k);
    fprintf('%3d %-11s %7.2f/%7.2f/%.4f %7.2f/%7.2f/%.4f %7.2f/%7.2f/%.4f %+8.2f %+9.2f\n', ...
        r.index,sprintf('%s@%d',r.device_id,r.bus_id), ...
        r.pre.P_MW,r.pre.Q_MVAr,r.pre.V_pu, ...
        r.tripped.P_MW,r.tripped.Q_MVAr,r.tripped.V_pu, ...
        r.returned.P_MW,r.returned.Q_MVAr,r.returned.V_pu, ...
        r.delta_trip_from_pre.P_MW,r.delta_return_from_pre.P_MW);
end
fprintf('\nBUS VOLTAGE COMPARISON\n');
fprintf('Idx BusPos BusID   Pre pu/kV       Tripped pu/kV   Returned pu/kV   dVtrip    dVreturn\n');
for k=1:numel(result.bus_rows)
    r=result.bus_rows(k);
    fprintf('%3d %6d %5d  %.5f/%7.3f  %.5f/%7.3f  %.5f/%7.3f  %+8.5f %+9.5f\n', ...
        r.index,r.bus_position,r.bus_id,r.pre.V_pu,r.pre.V_kV, ...
        r.tripped.V_pu,r.tripped.V_kV,r.returned.V_pu,r.returned.V_kV, ...
        r.delta_trip_from_pre.V_pu,r.delta_return_from_pre.V_pu);
end
if include_sssa
    fprintf('\nSSSA OPERATING-POINT SUMMARY\n');
    for k=1:3
        p=result.points(k);
        if p.sssa_converged
            fprintf('  %-11s states=%d status=%-23s maxReal=%+.4e 1/s\n', ...
                p.label,size(p.sssa.A,1),p.sssa.stability_status,max(real(p.sssa.eigenvalues)));
        else
            fprintf('  %-11s NOT_AVAILABLE\n',p.label);
        end
    end
    fprintf('\nSTATE INDEX COMPARISON (A index; NaN = inactive at that point)\n');
    fprintf('Global Device Local State                 Pre Trip Return\n');
    for k=1:numel(result.state_rows)
        r=result.state_rows(k);
        fprintf('%6d %-6s %5d %-21s %4s %4s %6s\n',r.global_state_index,r.device_id, ...
            r.local_state_index,r.state_name,index_text(r.pre_A_index), ...
            index_text(r.tripped_A_index),index_text(r.returned_A_index));
    end
    fprintf('\nFULL EIGENVALUE TABLES (one table per operating point)\n');
    fprintf('Cross-point policy: %s. Equal Mode numbers do NOT identify the same physical mode.\n', ...
        result.mode_pairing_policy);
    for p=1:3
        print_modal_table(result.points(p));
    end
end
if ~isempty(result.figure_files), fprintf('Comparison plot: %s\n',result.figure_files{1}); end
fprintf('Base: %.6g MVA; voltage base mapping from case metadata.\n',case_data.mpc.baseMVA);
end

function p=empty_point()
p=struct('label','','equilibrium_converged',false,'sssa_converged',false, ...
    'equilibrium',empty_equilibrium(),'sssa',struct(),'modal',struct([]), ...
    'snapshot',struct(),'device_build',struct(),'failure_id','','failure_reason','');
end
function e=empty_equilibrium()
e=struct('converged',false,'iterations',0,'active_state_indices',[], ...
    'physical_kcl_norm',inf,'failure_id','','failure_reason','');
end
function n=snapshot_device_count(p), n=0; if p.equilibrium_converged, n=numel(p.snapshot.devices); end, end
function v=missing_device_value(k), v=struct('resource_index',k,'device_index',k,'device_id',sprintf('DEVICE%d',k),'bus_position',0,'bus_id',0,'device_type','','mode','UNAVAILABLE','online',false,'P_pu',NaN,'Q_pu',NaN,'P_MW',NaN,'Q_MVAr',NaN,'V_pu',NaN,'V_kV',NaN,'angle_deg',NaN); end
function d=delta_value(a,b), d=struct('P_pu',a.P_pu-b.P_pu,'Q_pu',a.Q_pu-b.Q_pu,'P_MW',a.P_MW-b.P_MW,'Q_MVAr',a.Q_MVAr-b.Q_MVAr,'V_pu',a.V_pu-b.V_pu,'V_kV',a.V_kV-b.V_kV,'angle_deg',a.angle_deg-b.angle_deg); end
function d=bus_delta(a,b), d=struct('V_pu',a.V_pu-b.V_pu,'V_kV',a.V_kV-b.V_kV,'angle_deg',a.angle_deg-b.angle_deg); end
function v=option_value(s,n,d), v=d; if isfield(s,n)&&~isempty(s.(n)), v=s.(n); end, end
function y=ternary(c,a,b), if c, y=a; else, y=b; end, end
function n=active_count(p), n=0; if p.equilibrium_converged, n=numel(p.equilibrium.active_state_indices); end, end
function v=kcl_value(p), v=inf; if p.equilibrium_converged, v=p.equilibrium.physical_kcl_norm; end, end
function s=index_text(v), if isnan(v), s='-'; else, s=sprintf('%d',v); end, end
function print_modal_table(point)
fprintf('\n[%s] %d active-state eigenvalues\n',point.label,numel(point.modal));
fprintf('Mode    Real(1/s)    Imag(1/s)     f(Hz)    zeta  Device  State                 Global Local\n');
fprintf('----  -----------  -----------  --------  ------  ------  --------------------  ------ -----\n');
for k=1:numel(point.modal)
    m=point.modal(k);
    fprintf('%4d  %+11.3e  %+11.3e  %8.3e  %+6.3f  %-6s  %-20s  %6d %5d\n', ...
        m.display_mode_number,real(m.lambda),imag(m.lambda),m.frequency_Hz, ...
        m.damping_ratio,m.dominant_device_id,m.dominant_state_name, ...
        m.dominant_global_state_index,m.dominant_local_state_index);
end
end
