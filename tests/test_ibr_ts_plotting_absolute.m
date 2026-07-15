function tests = test_ibr_ts_plotting_absolute()
%TEST_IBR_TS_PLOTTING_ABSOLUTE  Physical, absolute-value IBR TS plot contract.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_exactly_two_figures_and_physical_series(testCase)
r = synthetic_result();
out = tempname; mkdir(out);
cleanup = onCleanup(@() cleanup_artifacts(out));
before = findall(groot,'Type','figure');
p = stability.plot_ibr_ts_results(r,struct('output_dir',out,'visible',true));
after = findall(groot,'Type','figure');
testCase.verifyEqual(numel(after)-numel(before),2,'Exactly two figures are created.');
testCase.verifyTrue(isfile(p.freq_plot));
testCase.verifyTrue(isfile(p.power_plot));

axf = findobj(p.freq_fig,'Tag','ibr_frequency_axes');
freq_lines = findobj(axf,'Type','line');
names = string(get(freq_lines,'DisplayName'));
testCase.verifyEqual(numel(freq_lines),2,'SG and active-GFM frequencies only.');
testCase.verifyFalse(any(contains(names,'COI','IgnoreCase',true)),'No COI trace.');
sg_line = freq_lines(strcmp(string(get(freq_lines,'DisplayName')),'SG_A frequency'));
testCase.verifyEqual(sg_line.YData,r.device_frequency_Hz(1,:),'AbsTol',0);

axv = findobj(p.freq_fig,'Tag','ibr_voltage_axes');
voltage_names = string(get(findobj(axv,'Type','line'),'DisplayName'));
testCase.verifyEqual(numel(voltage_names),1, ...
    'Voltage panel contains only the scheduled fault bus.');
testCase.verifyEqual(voltage_names,"|V| fault bus 3");
vline=findobj(axv,'Type','line','DisplayName','|V| fault bus 3');
testCase.verifyEqual(vline.YData,r.bus_voltage_magnitude(2,:),'AbsTol',0);

axp = findobj(p.power_fig,'Tag','ibr_active_power_axes');
axq = findobj(p.power_fig,'Tag','ibr_reactive_power_axes');
axi = findobj(p.power_fig,'Tag','ibr_current_axes');
testCase.verifyEqual(axp.YLabel.String,'P (MW)');
testCase.verifyEqual(axq.YLabel.String,'Q (MVAr)');
testCase.verifyEqual(axi.YLabel.String,'|I| (pu, system base)');
ilim = findobj(axi,'Type','line','DisplayName','IBR_B current limit');
testCase.verifyEqual(ilim.YData,r.device_current_limit_sys(2,:),'AbsTol',0, ...
    'Current limit comes from authoritative result data.');
testCase.verifyFalse(any(abs(ilim.YData-1.5)<eps), ...
    'No fabricated 1.5-pu current-limit line.');
close(p.freq_fig); close(p.power_fig);
end

function test_fault_schedule_owns_voltage_bus(testCase)
r = synthetic_result(); out = tempname; mkdir(out);
cleanup = onCleanup(@() cleanup_artifacts(out));
p = stability.plot_ibr_ts_results(r,struct('output_dir',out,'visible',true));
testCase.verifyEqual(p.voltage_bus_ids,3,'AbsTol',0);
axv = findobj(p.freq_fig,'Tag','ibr_voltage_axes');
names = string(get(findobj(axv,'Type','line'),'DisplayName'));
testCase.verifyEqual(names,"|V| fault bus 3");
close(p.freq_fig); close(p.power_fig);
r.sched.fault_bus=99;
testCase.verifyError(@() stability.plot_ibr_ts_results(r,struct('output_dir',out)), ...
    'plot_ibr_ts_results:badFaultBus');
r=rmfield(r,'sched');
testCase.verifyError(@() stability.plot_ibr_ts_results(r,struct('output_dir',out)), ...
    'plot_ibr_ts_results:missingFaultBus');
end

function test_applied_event_log_is_primary(testCase)
r = synthetic_result(); out = tempname; mkdir(out);
cleanup = onCleanup(@() cleanup_artifacts(out));
% Deliberately contradictory scheduled times must not replace event_log times.
r.events = struct('type',{'fault_on','fault_clear'},'t',{0.11,0.12});
p = stability.plot_ibr_ts_results(r,struct('output_dir',out,'visible',false));
times = [p.event_markers.time];
types = string({p.event_markers.type});
testCase.verifyTrue(any(times==0.2 & types=='fault_on'));
testCase.verifyTrue(any(times==0.4 & types=='fault_clear'));
testCase.verifyTrue(any(times==0.6 & types=='sg_trip'));
testCase.verifyTrue(any(times==0.8 & types=='sg_on_request'));
testCase.verifyTrue(any(times==1.0 & types=='sg_reclose_timeout'));
testCase.verifyFalse(any(times==0.11 | times==0.12), ...
    'Scheduled fallback is ignored when event_log is available.');
testCase.verifyFalse(p.event_markers(end).applied, ...
    'Synchronism timeout remains an explicit non-applied marker.');
testCase.verifyEmpty(p.freq_fig,'Closed figures do not return stale handles.');
testCase.verifyEmpty(p.power_fig,'Closed figures do not return stale handles.');
end

function test_missing_physical_units_fail_closed(testCase)
r = synthetic_result(); r = rmfield(r,'device_P_MW');
testCase.verifyError(@() stability.plot_ibr_ts_results(r,struct()), ...
    'plot_ibr_ts_results:missingField');
end

function test_partial_failed_run_is_plotted_and_labeled(testCase)
r = synthetic_result();
r.converged=false;
r.failure_id='ts_simulate_ibr_hybrid:stepNewton';
r.failure_reason='Composite step failed at t=0.9.';
out=tempname; mkdir(out);
cleanup=onCleanup(@() cleanup_artifacts(out)); %#ok<NASGU>
p=stability.plot_ibr_ts_results(r,struct('output_dir',out,'visible',true));
testCase.verifyTrue(isfile(p.freq_plot));
testCase.verifyTrue(isfile(p.power_plot));
axf=findobj(p.freq_fig,'Tag','ibr_frequency_axes');
testCase.verifySubstring(string(axf.Title.String),'PARTIAL / FAILED CLOSED');
txt=evalc('stability.print_ibr_run_log(r);');
testCase.verifySubstring(txt,'ts_simulate_ibr_hybrid:stepNewton');
testCase.verifySubstring(txt,'Last published time');
close(p.freq_fig); close(p.power_fig);
end

function r = synthetic_result()
t = [0 0.2 0.4 0.6 0.8 1.0];
r = struct(); r.t = t;
r.bus_ids = [1 3 7];
r.device_ids = {'SG_A','IBR_B'};
r.device_bus_ids = [1 7];
r.device_frequency_Hz = [60.00 59.98 59.95 NaN NaN 60.01; ...
    NaN NaN NaN 60.02 60.01 60.00];
r.bus_voltage_magnitude = [1.00 0.91 1.01 1.00 1.00 1.00; ...
    1.02 0.88 1.01 1.01 1.01 1.01; ...
    0.99 0.86 0.98 0.99 1.00 1.00];
r.device_P_MW = [120 125 118 0 0 112; 40 38 42 155 150 45];
r.device_Q_MVAr = [15 25 18 0 0 12; 5 8 6 22 18 7];
r.device_current_magnitude = [1.00 1.08 0.98 0 0 0.95; .42 .45 .47 1.12 1.08 .48];
r.device_current_limit_sys = [NaN NaN NaN NaN NaN NaN; 1.2 1.2 1.2 1.2 1.2 1.2];
r.event_log = struct( ...
    'type',{'fault_on','fault_clear','sg_trip','sg_on','sg_reclose_timeout'}, ...
    't',{0.2,0.4,0.6,0.8,1.0}, ...
    'applied',{true,true,true,true,false}, ...
    'details',{'fault applied','fault cleared','SG tripped', ...
        'reclose request accepted','synchronism dwell timed out'});
for k=1:numel(r.event_log)
    r.event_log(k).pre_kcl_norm=0;
    r.event_log(k).right_kcl_norm=0;
    r.event_log(k).selected_gfm_indices=[];
    r.event_log(k).reference_resource_index=[];
    r.event_log(k).failure_id='';
end
r.sched = struct('fault_bus',3);
end

function cleanup_artifacts(out)
close(findall(groot,'Type','figure','Name','IBR absolute frequency and voltage'));
close(findall(groot,'Type','figure','Name','IBR physical power and current'));
if isfolder(out), rmdir(out,'s'); end
end
