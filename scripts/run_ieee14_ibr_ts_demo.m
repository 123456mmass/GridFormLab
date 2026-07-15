function [result,plot_paths] = run_ieee14_ibr_ts_demo(opt)
%RUN_IEEE14_IBR_TS_DEMO Configurable IEEE14 1SG+4IBR event demonstration.
%   OPT may set normal-operation initial_gfm_count/initial_gfm_indices and
%   the independent fault_on, fault_clear, sg_trip, sg_on event times.

arguments
    opt struct = struct()
end
root=pf_init_paths();
defaults=struct('t_end',15.0,'dt',0.01,'verbose',false, ...
    'initial_gfm_count',0,'initial_gfl_count',4,'initial_gfm_indices',[], ...
    'initial_reference_resource_index',[], ...
    'automatic_gfm_switching',true, ...
    'plot_results',true,'plot_visible',true,'plot_prefix','ieee14_ibr', ...
    'ibr_events',struct('enabled',true,'fault_bus',4,'Zf',1i*0.1, ...
        'fault_on',3.0,'fault_clear',3.1,'sg_trip',5.0,'sg_on',8.0, ...
        'selected_gfm_indices',2:5,'reference_resource_index',2));
opt=merge_struct(defaults,opt);
opt.ibr_events=merge_struct(defaults.ibr_events,opt.ibr_events);

base=cases.scenario_ieee14_1sg_4ibr();
[scenario,selection]=stability.ibr_configure_scenario(base,opt);
if ~selection.ready
    error('run_ieee14_ibr_ts_demo:initialSelection', ...
        'Initial GFM selector rejected the request: %s -- %s', ...
        selection.failure_id,selection.failure_reason);
end

fprintf('\nIEEE14 1SG+4IBR EVENT DEMO\n');
fprintf('t_end=%.6g dt=%.6g; events fault %.6g/%.6g, SG trip/on %.6g/%.6g\n', ...
    opt.t_end,opt.dt,opt.ibr_events.fault_on,opt.ibr_events.fault_clear, ...
    opt.ibr_events.sg_trip,opt.ibr_events.sg_on);
fprintf('Normal GFM indices=%s; post-trip GFM indices=%s, ref=%d\n', ...
    mat2str(selection.selected_gfm_indices), ...
    mat2str(opt.ibr_events.selected_gfm_indices), ...
    opt.ibr_events.reference_resource_index);

result=stability.run_hybrid_case(scenario,opt);
result.selector_log=selection;
stability.print_ibr_run_log(result);
if ~result.converged
    reason=''; if isfield(result.metadata,'error'), reason=result.metadata.error; end
    error('run_ieee14_ibr_ts_demo:simulation', ...
        'IBR event simulation failed closed: %s',reason);
end

plot_paths=struct('freq_plot','','power_plot','');
if opt.plot_results
    plot_paths=stability.plot_ibr_ts_results(result,struct( ...
        'output_dir',fullfile(root,'output','plots'), ...
        'visible',opt.plot_visible,'prefix',opt.plot_prefix));
    fprintf('Plots:\n  %s\n  %s\n',plot_paths.freq_plot,plot_paths.power_plot);
end
end

function out=merge_struct(base,over)
out=base; names=fieldnames(over);
for k=1:numel(names), out.(names{k})=over.(names{k}); end
end
