function paths = plot_ibr_ts_results(result,opt)
%PLOT_IBR_TS_RESULTS Create two analysis figures from audited TS outputs.
%   Figure 1 contains actual SG/GFM/COI frequency and resource-bus voltage.
%   Figure 2 contains device P/Q in MW/MVAr and current in system-base pu with
%   per-device source-model current limits. Applied/requested events come from
%   result.event_log; no signal, limit, event, or unit is fabricated.

arguments
    result struct
    opt struct = struct()
end
outdir=value(opt,'output_dir','output/plots');
visible=logical(value(opt,'visible',false));
prefix=char(value(opt,'prefix',''));
if ~isempty(prefix), prefix=[prefix '_']; end
if ~isfolder(outdir), mkdir(outdir); end
required={'t','device_frequency_Hz','coi_frequency_Hz','bus_voltage_magnitude', ...
    'bus_ids','device_bus_ids','device_ids','device_P_MW','device_Q_MVAr', ...
    'device_current_magnitude','device_current_limit_sys','event_log'};
for k=1:numel(required)
    if ~isfield(result,required{k})
        error('plot_ibr_ts_results:missingData','RESULT lacks %s.',required{k});
    end
end
t=result.t(:)';
if any(diff(t)<0), error('plot_ibr_ts_results:badTime','RESULT.t must be nondecreasing.'); end
vis=ternary(visible,'on','off');

f1=figure('Visible',vis,'Color','w','Name','IBR frequency and voltage', ...
    'Position',[80 80 1180 760]);
tl=tiledlayout(f1,2,1,'TileSpacing','compact','Padding','compact');
ax1=nexttile(tl); hold(ax1,'on'); grid(ax1,'on');
for d=1:numel(result.device_ids)
    if any(isfinite(result.device_frequency_Hz(d,:)))
        plot(ax1,t,result.device_frequency_Hz(d,:),'LineWidth',1.35, ...
            'DisplayName',sprintf('%s frequency',result.device_ids{d}));
    end
end
if any(isfinite(result.coi_frequency_Hz))
    plot(ax1,t,result.coi_frequency_Hz,'k--','LineWidth',1.7,'DisplayName','COI frequency');
end
add_event_markers(ax1,result.event_log);
ylabel(ax1,'Frequency (Hz)'); title(ax1,'SG/GFM and inertia-weighted COI frequency');
legend(ax1,'Location','bestoutside');

ax2=nexttile(tl); hold(ax2,'on'); grid(ax2,'on');
resource_buses=unique(result.device_bus_ids,'stable');
if isfield(result,'sched') && isfield(result.sched,'fault_bus')
    resource_buses=unique([resource_buses,result.sched.fault_bus],'stable');
end
for bus=resource_buses
    row=find(result.bus_ids==bus,1);
    if isempty(row)
        error('plot_ibr_ts_results:busMap','External bus ID %g is absent from result.bus_ids.',bus);
    end
    plot(ax2,t,result.bus_voltage_magnitude(row,:),'LineWidth',1.2, ...
        'DisplayName',sprintf('|V| bus %g',bus));
end
add_event_markers(ax2,result.event_log);
xlabel(ax2,'Time (s)'); ylabel(ax2,'Voltage magnitude (pu)');
title(ax2,'Resource and fault-bus voltages'); legend(ax2,'Location','bestoutside');
title(tl,'Mixed SG+IBR transient response: frequency and voltage');
paths.freq_plot=fullfile(outdir,[prefix 'ibr_frequency_voltage.png']);
exportgraphics(f1,paths.freq_plot,'Resolution',160);
if ~visible, close(f1); end

f2=figure('Visible',vis,'Color','w','Name','IBR power and current', ...
    'Position',[100 100 1180 820]);
tl2=tiledlayout(f2,2,1,'TileSpacing','compact','Padding','compact');
ax3=nexttile(tl2); hold(ax3,'on'); grid(ax3,'on');
for d=1:numel(result.device_ids)
    plot(ax3,t,result.device_P_MW(d,:),'LineWidth',1.25, ...
        'DisplayName',sprintf('%s P (MW)',result.device_ids{d}));
    plot(ax3,t,result.device_Q_MVAr(d,:),'--','LineWidth',1.0, ...
        'DisplayName',sprintf('%s Q (MVAr)',result.device_ids{d}));
end
add_event_markers(ax3,result.event_log);
ylabel(ax3,'Power (MW / MVAr)'); title(ax3,'Device terminal power, S=V conj(I)');
legend(ax3,'Location','bestoutside');

ax4=nexttile(tl2); hold(ax4,'on'); grid(ax4,'on');
for d=1:numel(result.device_ids)
    plot(ax4,t,result.device_current_magnitude(d,:),'LineWidth',1.25, ...
        'DisplayName',sprintf('%s |I|',result.device_ids{d}));
    lim=result.device_current_limit_sys(d,:);
    if any(isfinite(lim))
        plot(ax4,t,lim,':','LineWidth',1.1, ...
            'DisplayName',sprintf('%s sourced limit',result.device_ids{d}));
    end
end
add_event_markers(ax4,result.event_log);
xlabel(ax4,'Time (s)'); ylabel(ax4,'Current (pu, system base)');
title(ax4,'Device current and model-owned limits'); legend(ax4,'Location','bestoutside');
title(tl2,'Mixed SG+IBR transient response: power and current');
paths.power_plot=fullfile(outdir,[prefix 'ibr_power_current.png']);
exportgraphics(f2,paths.power_plot,'Resolution',160);
if ~visible, close(f2); end

paths.output_dir=outdir;
paths.event_times=[result.event_log.t];
if isfield(result,'reclose_status'), paths.reclose_status=result.reclose_status; else, paths.reclose_status=''; end
end

function add_event_markers(ax,logs)
for k=1:numel(logs)
    if ~isfinite(logs(k).t), continue; end
    label=strrep(logs(k).type,'_',' ');
    if ~logs(k).applied, label=[label ' (not applied)']; end
    xline(ax,logs(k).t,'-.',label,'Color',[0.35 0.35 0.35], ...
        'LabelOrientation','aligned','HandleVisibility','off');
end
end

function v=value(s,name,default)
v=default; if isfield(s,name) && ~isempty(s.(name)), v=s.(name); end
end

function v=ternary(c,a,b)
if c, v=a; else, v=b; end
end
