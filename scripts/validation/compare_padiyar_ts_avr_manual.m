function report = compare_padiyar_ts_avr_manual(user_opt)
%COMPARE_PADIYAR_TS_AVR_MANUAL Compare Padiyar TS with and without AVR.
%   REPORT = COMPARE_PADIYAR_TS_AVR_MANUAL() runs the same sourced Padiyar
%   two-area case, network event, integration method, and timestep twice.
%   The only model change is excitation mode:
%     AVR    : model='padiyar_1_1_avr'    (dynamic Efd; 5 states/machine)
%     Manual : model='padiyar_1_1_manual' (constant Efd0; 4 states/machine)
%
%   Optional USER_OPT fields override the declared scenario. The default
%   stepper is the canonical fixed-step path so the comparison isolates the
%   excitation model. Set user_opt.stepper='adaptive' for a diagnostic
%   adaptive-grid comparison; this does not establish adaptive tolerance or
%   default-switch readiness.

if nargin < 1 || isempty(user_opt), user_opt = struct(); end
if ~isstruct(user_opt) || ~isscalar(user_opt)
    error('compare_padiyar_ts_avr_manual:options', ...
        'user_opt must be a scalar struct.');
end

pf_init_paths;
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
default_out = fullfile(root,'output','validation','padiyar_avr_manual');

opt = struct('t_end',15.0,'dt',0.01,'fault_enabled',true, ...
    'fault_bus',3,'t_fault',1.0,'t_clear',1.1,'Zf',0+10e-4j, ...
    'method','trapezoidal','stepper','fixed', ...
    'corrector_mode','adaptive','corrector_abs_tol',1e-10, ...
    'corrector_rel_tol',1e-8,'max_corrector_iter',20, ...
    'pm_mode','balanced','verbose',false,'plot_results',false, ...
    'output_dir',default_out,'show_figure',true);
opt = merge_struct(opt,user_opt);
if isfield(opt,'bus_fault') && ~isempty(opt.bus_fault)
    opt.fault_bus = opt.bus_fault;
end

outdir = char(opt.output_dir);
show_figure = logical(opt.show_figure);
solver_opt = rmfield_if_present(opt,{'output_dir','show_figure','bus_fault'});
if ~exist(outdir,'dir'), mkdir(outdir); end

c = cases.case_padiyar_two_area_4m_avr();
avr_opt = solver_opt; avr_opt.model = 'padiyar_1_1_avr';
manual_opt = solver_opt; manual_opt.model = 'padiyar_1_1_manual';

fprintf('\n=== Padiyar TS: AVR vs manual excitation ===\n');
fprintf('Same case/event/method: fault bus %g, Zf=%.4g%+.4gj pu, %.4g--%.4g s, dt=%.4g s, stepper=%s\n', ...
    solver_opt.fault_bus,real(solver_opt.Zf),imag(solver_opt.Zf), ...
    solver_opt.t_fault,solver_opt.t_clear,solver_opt.dt,char(solver_opt.stepper));

avr = stability.ts_simulate(c,avr_opt);
manual = stability.ts_simulate(c,manual_opt);
validate_contract(avr,manual,solver_opt);

% A common union grid is used only for numerical separation metrics. Linear
% interpolation is refused outside either raw trajectory's time coverage.
tg = unique([avr.t(:); manual.t(:)]);
da = interp_no_extrapolate(avr.t,rad2deg(avr.delta),tg);
dm = interp_no_extrapolate(manual.t,rad2deg(manual.delta),tg);
wa = interp_no_extrapolate(avr.t,avr.omega,tg);
wm = interp_no_extrapolate(manual.t,manual.omega,tg);
pa = interp_no_extrapolate(avr.t,avr.Pe_MW,tg);
pm = interp_no_extrapolate(manual.t,manual.Pe_MW,tg);

ra = coi_relative(da,wa,avr.H,avr.gen_buses);
rm = coi_relative(dm,wm,manual.H,manual.gen_buses);
da_rel = ra.delta_rel - ra.delta_rel(1,:);
dm_rel = rm.delta_rel - rm.delta_rel(1,:);

fa = find(avr.bus_ids==solver_opt.fault_bus,1);
fm = find(manual.bus_ids==solver_opt.fault_bus,1);
va = interp_no_extrapolate(avr.t,avr.Vbus(:,fa),tg);
vm = interp_no_extrapolate(manual.t,manual.Vbus(:,fm),tg);

metrics = struct();
metrics.max_coi_relative_angle_separation_deg = max(abs(da_rel-dm_rel),[],'all');
metrics.rms_coi_relative_angle_separation_deg = sqrt(mean((da_rel-dm_rel).^2,'all'));
metrics.max_speed_separation_pu = max(abs(ra.omega_rel-rm.omega_rel),[],'all');
metrics.rms_speed_separation_pu = sqrt(mean((ra.omega_rel-rm.omega_rel).^2,'all'));
metrics.max_electrical_power_separation_MW = max(abs(pa-pm),[],'all');
metrics.rms_electrical_power_separation_MW = sqrt(mean((pa-pm).^2,'all'));
metrics.max_fault_bus_voltage_separation_pu = max(abs(va-vm));
metrics.rms_fault_bus_voltage_separation_pu = sqrt(mean((va-vm).^2));
metrics.avr_min_voltage_pu = min(avr.Vbus,[],'all');
metrics.manual_min_voltage_pu = min(manual.Vbus,[],'all');
metrics.avr_max_speed_deviation_pu = max(abs(avr.omega-1),[],'all');
metrics.manual_max_speed_deviation_pu = max(abs(manual.omega-1),[],'all');

figpath = fullfile(outdir,'padiyar_ts_avr_vs_manual.png');
fig = make_plot(avr,manual,solver_opt,figpath,show_figure);
[omega_figs,omega_figpaths] = make_generator_omega_plots( ...
    avr,manual,solver_opt,outdir,show_figure);
rawpath = fullfile(outdir,'padiyar_ts_avr_vs_manual.mat');
save(rawpath,'avr','manual','solver_opt','metrics','tg');

fprintf('AVR:    initial residual=%.3e, min|V|=%.5f, max|omega-1|=%.3e\n', ...
    avr.initial_dae_residual,metrics.avr_min_voltage_pu,metrics.avr_max_speed_deviation_pu);
fprintf('Manual: initial residual=%.3e, min|V|=%.5f, max|omega-1|=%.3e\n', ...
    manual.initial_dae_residual,metrics.manual_min_voltage_pu,metrics.manual_max_speed_deviation_pu);
fprintf('AVR-vs-manual separation: dCOI=%.5f deg, dOmega=%.3e pu, dPe=%.5f MW, dVfault=%.3e pu\n', ...
    metrics.max_coi_relative_angle_separation_deg,metrics.max_speed_separation_pu, ...
    metrics.max_electrical_power_separation_MW,metrics.max_fault_bus_voltage_separation_pu);
fprintf('Main figure: %s\n',figpath);
for k = 1:numel(omega_figpaths)
    fprintf('Omega G%d:   %s\n',k,omega_figpaths{k});
end
fprintf('Raw:         %s\n',rawpath);

report = struct('case_data',c,'options',solver_opt,'avr',avr, ...
    'manual',manual,'common_time',tg,'metrics',metrics, ...
    'figure',fig,'figure_file',figpath, ...
    'omega_figures',omega_figs,'omega_figure_files',{omega_figpaths}, ...
    'raw_file',rawpath, ...
    'classification','AVR_VS_MANUAL_MODEL_COMPARISON');
end

function validate_contract(a,m,opt)
if ~strcmp(a.excitation,'avr') || ~strcmp(m.excitation,'manual')
    error('compare_padiyar_ts_avr_manual:routing', ...
        'Expected AVR and manual excitation routes.');
end
if ~isequal(a.gen_buses(:),m.gen_buses(:)) || ~isequal(a.bus_ids(:),m.bus_ids(:))
    error('compare_padiyar_ts_avr_manual:mapping', ...
        'AVR/manual bus or generator mappings differ.');
end
for name = {'fault_bus','t_fault','t_clear','Zf'}
    f = name{1};
    if ~isequal(a.(f),m.(f)) || ~isequal(a.(f),opt.(f))
        error('compare_padiyar_ts_avr_manual:scenario', ...
            'AVR/manual scenario mismatch in %s.',f);
    end
end
if abs(a.t(end)-opt.t_end)>1e-12 || abs(m.t(end)-opt.t_end)>1e-12
    error('compare_padiyar_ts_avr_manual:coverage', ...
        'One trajectory does not cover the requested t_end.');
end
end

function fig = make_plot(a,m,opt,path,show_figure)
visibility = 'off'; if show_figure, visibility = 'on'; end
fig = comparison_figure(visibility,'Padiyar AVR vs manual summary',[60 60 1350 850]);
tl = tiledlayout(fig,2,2,'Padding','compact','TileSpacing','compact');
colors = lines(numel(a.gen_buses));

da = rad2deg(a.delta);
dm = rad2deg(m.delta);
ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
plot_pairs(ax,a.t,da,m.t,dm,colors);
event_lines(ax,opt); xlabel(ax,'Time (s)'); ylabel(ax,'Rotor angle \delta_i (deg)');
title(ax,'Generator rotor angles');
generator_labels = compose('G%d @ bus %g',(1:numel(a.gen_buses))',a.gen_buses(:));
legend_handles = gobjects(numel(a.gen_buses)+2,1);
for k=1:numel(a.gen_buses)
    legend_handles(k)=plot(ax,nan,nan,'-','Color',colors(k,:),'LineWidth',1.35);
end
legend_handles(end-1)=plot(ax,nan,nan,'-k','LineWidth',1.35);
legend_handles(end)=plot(ax,nan,nan,'--k','LineWidth',1.05);
legend(ax,legend_handles,[generator_labels;"AVR (solid)";"Manual (dashed)"], ...
    'Location','best');

ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
plot_pairs(ax,a.t,a.omega,m.t,m.omega,colors);
event_lines(ax,opt); xlabel(ax,'Time (s)'); ylabel(ax,'\omega_i (pu)');
title(ax,'Generator rotor speeds');

ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
plot_pairs(ax,a.t,a.Pe_MW,m.t,m.Pe_MW,colors);
event_lines(ax,opt); xlabel(ax,'Time (s)'); ylabel(ax,'P_e (MW)');
title(ax,'Electrical power');

ia=find(a.bus_ids==opt.fault_bus,1); im=find(m.bus_ids==opt.fault_bus,1);
ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
plot(ax,a.t,a.Vbus(:,ia),'-','Color',[.05 .30 .65],'LineWidth',1.6, ...
    'DisplayName','Fault bus AVR');
plot(ax,m.t,m.Vbus(:,im),'--','Color',[.80 .25 .10],'LineWidth',1.5, ...
    'DisplayName','Fault bus manual');
event_lines(ax,opt); xlabel(ax,'Time (s)'); ylabel(ax,'|V| (pu)');
title(ax,sprintf('Fault-bus voltage (bus %g)',opt.fault_bus)); legend(ax,'Location','best');

sgtitle(tl,sprintf('Padiyar model 1.1: AVR vs manual excitation (%s step, Z_f=%.3g%+.3gj pu)', ...
    char(opt.stepper),real(opt.Zf),imag(opt.Zf)),'FontWeight','bold');
exportgraphics(fig,path,'Resolution',220);
end

function [figs,paths] = make_generator_omega_plots(a,m,opt,outdir,show_figure)
%MAKE_GENERATOR_OMEGA_PLOTS One standalone figure per generator.
% Plot the stored rotor-speed state directly. This is omega, not omega-1.
ng = numel(a.gen_buses);
figs = gobjects(ng,1);
paths = cell(ng,1);
visibility = 'off'; if show_figure, visibility = 'on'; end
for k = 1:ng
    figs(k) = comparison_figure(visibility,sprintf('Padiyar omega G%d',k), ...
        [90+35*(k-1) 70+25*(k-1) 920 560]);
    ax = axes(figs(k)); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
    plot(ax,a.t,a.omega(:,k),'-','Color',[.08 .39 .62], ...
        'LineWidth',1.55,'DisplayName','AVR');
    plot(ax,m.t,m.omega(:,k),'--','Color',[.85 .42 .12], ...
        'LineWidth',1.35,'DisplayName','Manual excitation');
    event_lines(ax,opt);
    xlabel(ax,'Time (s)');
    ylabel(ax,sprintf('\\omega_%d (pu)',k));
    title(ax,sprintf('Padiyar generator G%d speed at bus %g: AVR vs manual', ...
        k,a.gen_buses(k)));
    legend(ax,'Location','best');
    paths{k} = fullfile(outdir,sprintf( ...
        'padiyar_ts_omega_g%d_bus_%g_avr_vs_manual.png',k,a.gen_buses(k)));
    exportgraphics(figs(k),paths{k},'Resolution',220);
end
end


function fig = comparison_figure(visibility,name,position)
if usejava('desktop') && strcmp(visibility,'on')
    fig=figure('Visible',visibility,'Name',name,'Color','w', ...
        'WindowStyle','docked');
else
    fig=figure('Visible',visibility,'Name',name,'Color','w', ...
        'Position',position);
end
end

function plot_pairs(ax,ta,ya,tm,ym,colors)
for k=1:size(ya,2)
    plot(ax,ta,ya(:,k),'-','Color',colors(k,:),'LineWidth',1.35, ...
        'HandleVisibility','off');
    plot(ax,tm,ym(:,k),'--','Color',colors(k,:),'LineWidth',1.05, ...
        'HandleVisibility','off');
end
end

function event_lines(ax,opt)
xline(ax,opt.t_fault,'--','Color',[.55 .05 .05], ...
    'HandleVisibility','off');
xline(ax,opt.t_clear,'--','Color',[.55 .05 .05], ...
    'HandleVisibility','off');
end

function out = merge_struct(base,override)
out=base; names=fieldnames(override);
for k=1:numel(names), out.(names{k})=override.(names{k}); end
end

function s = rmfield_if_present(s,names)
for k=1:numel(names)
    if isfield(s,names{k}), s=rmfield(s,names{k}); end
end
end
