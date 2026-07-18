function plot_paths = plot_ibr_ts_results(result, plot_opt)
%PLOT_IBR_TS_RESULTS  Two absolute-value analysis figures for mixed SG+IBR TS.
%   Figure 1 contains (top) absolute per-device frequency in Hz for online
%   synchronous generators and active GFM resources and (bottom) bus-voltage
%   magnitude in pu.  Figure 2 contains physical device P (MW), Q (MVAr), and
%   current magnitude (pu on system base), including only current limits
%   supplied by the simulation result.  No COI trace, smoothing, inferred
%   current limit, or row-number-as-bus-ID assumption is used.
%
%   The voltage panel contains exactly one trace: the absolute voltage
%   magnitude at RESULT.sched.fault_bus.  The event schedule is the single
%   owner of both the applied fault bus and the plotted voltage bus.

arguments
    result struct
    plot_opt struct = struct()
end

[t, bus_ids, device_ids, device_bus_ids] = validate_result(result);
[output_dir, visible, prefix, selected_bus_ids, voltage_labels] = parse_options( ...
    plot_opt, bus_ids, result);
if ~isfolder(output_dir), mkdir(output_dir); end

events = event_markers(result);
vis = 'off'; if visible, vis = 'on'; end
colors = lines(numel(device_ids));
status_suffix = run_status_suffix(result);

% -------------------------------------------------------------------------
% Figure 1: absolute frequency and bus-voltage magnitude.
fig1 = figure('Visible',vis,'Name','IBR absolute frequency and voltage', ...
    'Units','pixels','Position',[100 100 1150 760]);
tl1 = tiledlayout(fig1,2,1,'TileSpacing','compact','Padding','compact');

ax_f = nexttile(tl1,1); hold(ax_f,'on'); grid(ax_f,'on');
set(ax_f,'Tag','ibr_frequency_axes');
frequency = result.device_frequency_Hz;
for k = 1:numel(device_ids)
    if any(isfinite(frequency(k,:)))
        plot(ax_f,t,frequency(k,:),'LineWidth',1.35,'Color',colors(k,:), ...
            'DisplayName',sprintf('%s frequency',device_ids{k}));
    end
end
if isempty(findobj(ax_f,'Type','line'))
    text(ax_f,0.5,0.5,'No online SG or active GFM frequency data', ...
        'Units','normalized','HorizontalAlignment','center');
end
ylabel(ax_f,'Frequency (Hz)');
title(ax_f,['Absolute device frequency: online SG and active GFM' status_suffix]);
add_event_lines(ax_f,events,true);
legend(ax_f,'Location','best','Interpreter','none');

ax_v = nexttile(tl1,2); hold(ax_v,'on'); grid(ax_v,'on');
set(ax_v,'Tag','ibr_voltage_axes');
for q = 1:numel(selected_bus_ids)
    id = selected_bus_ids(q);
    row = find(bus_ids == id,1,'first');
    plot(ax_v,t,result.bus_voltage_magnitude(row,:),'LineWidth',1.15, ...
        'DisplayName',voltage_labels{q});
end
xlabel(ax_v,'Time (s)'); ylabel(ax_v,'|V_{bus}| (pu)');
title(ax_v,[sprintf('Fault-bus voltage magnitude (bus %g)',selected_bus_ids) status_suffix]);
add_event_lines(ax_v,events,false);
legend(ax_v,'Location','best','Interpreter','none');

freq_path = fullfile(output_dir,[prefix 'ieee14_ibr_frequency_speed.png']);
saveas(fig1,freq_path);

% -------------------------------------------------------------------------
% Figure 2: physical P, Q, current, and authoritative current limits.
fig2 = figure('Visible',vis,'Name','IBR physical power and current', ...
    'Units','pixels','Position',[130 80 1200 900]);
tl2 = tiledlayout(fig2,3,1,'TileSpacing','compact','Padding','compact');

ax_p = nexttile(tl2,1); hold(ax_p,'on'); grid(ax_p,'on');
set(ax_p,'Tag','ibr_active_power_axes');
for k = 1:numel(device_ids)
    plot(ax_p,t,result.device_P_MW(k,:),'LineWidth',1.15, ...
        'Color',colors(k,:),'DisplayName',sprintf('%s P',device_ids{k}));
end
ylabel(ax_p,'P (MW)'); title(ax_p,['Device active power' status_suffix]);
add_event_lines(ax_p,events,true);
legend(ax_p,'Location','best','Interpreter','none');

ax_q = nexttile(tl2,2); hold(ax_q,'on'); grid(ax_q,'on');
set(ax_q,'Tag','ibr_reactive_power_axes');
for k = 1:numel(device_ids)
    plot(ax_q,t,result.device_Q_MVAr(k,:),'LineWidth',1.15, ...
        'Color',colors(k,:),'DisplayName',sprintf('%s Q',device_ids{k}));
end
ylabel(ax_q,'Q (MVAr)'); title(ax_q,'Device reactive power');
add_event_lines(ax_q,events,false);
legend(ax_q,'Location','best','Interpreter','none');

ax_i = nexttile(tl2,3); hold(ax_i,'on'); grid(ax_i,'on');
set(ax_i,'Tag','ibr_current_axes');
for k = 1:numel(device_ids)
    plot(ax_i,t,result.device_current_magnitude(k,:),'LineWidth',1.15, ...
        'Color',colors(k,:),'DisplayName',sprintf('%s |I|',device_ids{k}));
    limit = result.device_current_limit_sys(k,:);
    if any(isfinite(limit))
        plot(ax_i,t,limit,'--','LineWidth',1.0,'Color',colors(k,:), ...
            'DisplayName',sprintf('%s current limit',device_ids{k}));
    end
end
xlabel(ax_i,'Time (s)'); ylabel(ax_i,'|I| (pu, system base)');
title(ax_i,'Device current magnitude and sourced limits');
add_event_lines(ax_i,events,false);
legend(ax_i,'Location','best','Interpreter','none');

power_path = fullfile(output_dir,[prefix 'ieee14_ibr_voltage_power_current.png']);
saveas(fig2,power_path);

% -------------------------------------------------------------------------
% Figure 3: device electrical/control angles (SG rotor, GFM VSM, GFL PLL).
angle_path = '';
angle_handle = [];
if isfield(result,'device_angle_deg') && ...
        isequal(size(result.device_angle_deg),[numel(device_ids),numel(t)])
    fig3 = figure('Visible',vis,'Name','IBR SG/GFM/GFL angles', ...
        'Units','pixels','Position',[160 120 1150 650]);
    ax_a = axes(fig3); hold(ax_a,'on'); grid(ax_a,'on');
    set(ax_a,'Tag','ibr_angle_axes');
    for k=1:numel(device_ids)
        plot(ax_a,t,result.device_angle_deg(k,:),'LineWidth',1.2, ...
            'Color',colors(k,:),'DisplayName',sprintf('%s angle',device_ids{k}));
    end
    xlabel(ax_a,'Time (s)'); ylabel(ax_a,'Electrical angle (deg)');
    title(ax_a,['SG rotor / GFM VSM / GFL PLL angles' status_suffix]);
    add_event_lines(ax_a,events,true);
    legend(ax_a,'Location','best','Interpreter','none');
    angle_path=fullfile(output_dir,[prefix 'ieee14_ibr_angle.png']);
    saveas(fig3,angle_path);
    if visible, angle_handle=fig3; else, close(fig3); end
end

% Figure 4: all bus-voltage magnitudes (same physical signal class as SG TS).
fig4 = figure('Visible',vis,'Name','IBR bus voltages', ...
    'Units','pixels','Position',[190 140 1150 650]);
ax_va = axes(fig4); hold(ax_va,'on'); grid(ax_va,'on');
set(ax_va,'Tag','ibr_all_voltage_axes');
bus_colors=lines(numel(bus_ids));
for k=1:numel(bus_ids)
    plot(ax_va,t,result.bus_voltage_magnitude(k,:),'LineWidth',1.0, ...
        'Color',bus_colors(k,:),'DisplayName',sprintf('Bus %g',bus_ids(k)));
end
xlabel(ax_va,'Time (s)'); ylabel(ax_va,'|V| (pu)');
title(ax_va,['All bus voltage magnitudes' status_suffix]);
add_event_lines(ax_va,events,true);
legend(ax_va,'Location','eastoutside','Interpreter','none');
voltage_path=fullfile(output_dir,[prefix 'ieee14_ibr_voltage.png']);
saveas(fig4,voltage_path);
if visible, voltage_handle=fig4; else, close(fig4); voltage_handle=[]; end

if visible
    freq_handle = fig1; power_handle = fig2;
else
    close(fig1); close(fig2);
    freq_handle = []; power_handle = [];
end

event_times = marker_time_struct(events);
reclose_status = 'UNKNOWN';
if isfield(result,'reclose_status') && ~isempty(result.reclose_status)
    reclose_status = char(string(result.reclose_status));
end
plot_paths = struct('freq_plot',freq_path,'power_plot',power_path, ...
    'angle_plot',angle_path,'voltage_plot',voltage_path, ...
    'freq_fig',freq_handle,'power_fig',power_handle,'output_dir',output_dir, ...
    'angle_fig',angle_handle,'voltage_fig',voltage_handle, ...
    'event_markers',events,'event_times',event_times, ...
    'reclose_status',reclose_status,'voltage_bus_ids',selected_bus_ids);
end

% =========================================================================
function [t,bus_ids,device_ids,device_bus_ids] = validate_result(result)
required = {'t','bus_ids','device_ids','device_frequency_Hz', ...
    'device_bus_ids','bus_voltage_magnitude','device_P_MW','device_Q_MVAr', ...
    'device_current_magnitude','device_current_limit_sys'};
for k = 1:numel(required)
    if ~isfield(result,required{k}) || isempty(result.(required{k}))
        error('plot_ibr_ts_results:missingField', ...
            'RESULT.%s is required for physical TS plotting.',required{k});
    end
end
t = result.t(:).';
if ~isnumeric(t) || ~isreal(t) || any(~isfinite(t)) || any(diff(t)<0)
    error('plot_ibr_ts_results:badTime','RESULT.t must be finite and nondecreasing.');
end
bus_ids = result.bus_ids(:).';
if ~isnumeric(bus_ids) || ~isreal(bus_ids) || any(~isfinite(bus_ids)) || ...
        numel(unique(bus_ids)) ~= numel(bus_ids)
    error('plot_ibr_ts_results:badBusIds','RESULT.bus_ids must be unique finite numeric IDs.');
end
device_ids = cellstr(string(result.device_ids(:).'));
if numel(unique(device_ids)) ~= numel(device_ids)
    error('plot_ibr_ts_results:badDeviceIds','RESULT.device_ids must be unique.');
end
nt = numel(t); nb = numel(bus_ids); nd = numel(device_ids);
device_bus_ids = result.device_bus_ids(:).';
if ~isnumeric(device_bus_ids) || ~isreal(device_bus_ids) || ...
        numel(device_bus_ids) ~= nd || any(~isfinite(device_bus_ids)) || ...
        any(~ismember(device_bus_ids,bus_ids))
    error('plot_ibr_ts_results:badDeviceBusIds', ...
        'RESULT.device_bus_ids must map every device to one external bus ID.');
end
check_size(result.device_frequency_Hz,[nd,nt],'device_frequency_Hz');
check_size(result.bus_voltage_magnitude,[nb,nt],'bus_voltage_magnitude');
check_size(result.device_P_MW,[nd,nt],'device_P_MW');
check_size(result.device_Q_MVAr,[nd,nt],'device_Q_MVAr');
check_size(result.device_current_magnitude,[nd,nt],'device_current_magnitude');
check_size(result.device_current_limit_sys,[nd,nt],'device_current_limit_sys');
physical_fields = {'bus_voltage_magnitude','device_P_MW','device_Q_MVAr', ...
    'device_current_magnitude'};
for k = 1:numel(physical_fields)
    if any(~isfinite(result.(physical_fields{k})),'all')
        error('plot_ibr_ts_results:nonFinitePhysicalData', ...
            'RESULT.%s contains non-finite values.',physical_fields{k});
    end
end
if any(isinf(result.device_frequency_Hz),'all') || ...
        any(isinf(result.device_current_limit_sys),'all')
    error('plot_ibr_ts_results:nonFinitePhysicalData', ...
        'Frequency/current-limit matrices may use NaN for inactive/unavailable values, not Inf.');
end
end

function check_size(value,expected,name)
if ~isnumeric(value) || ~isequal(size(value),expected)
    error('plot_ibr_ts_results:badSize','RESULT.%s must have size %s.', ...
        name,mat2str(expected));
end
end

function [output_dir,visible,prefix,selected,labels] = parse_options(opt,bus_ids,result)
output_dir = fullfile('output','plots');
if isfield(opt,'output_dir') && ~isempty(opt.output_dir)
    output_dir = char(string(opt.output_dir));
end
visible = false;
if isfield(opt,'visible') && ~isempty(opt.visible)
    if ~isscalar(opt.visible) || ~(islogical(opt.visible) || ...
            (isnumeric(opt.visible) && isfinite(opt.visible) && any(opt.visible==[0 1])))
        error('plot_ibr_ts_results:badVisible','plot_opt.visible must be one logical scalar.');
    end
    visible = logical(opt.visible);
end
prefix = '';
if isfield(opt,'prefix') && ~isempty(opt.prefix)
    prefix = [char(string(opt.prefix)) '_'];
end
if ~isfield(result,'sched') || ~isstruct(result.sched) || ...
        ~isfield(result.sched,'fault_bus')
    error('plot_ibr_ts_results:missingFaultBus', ...
        'RESULT.sched.fault_bus is required as the voltage-plot bus owner.');
end
selected = result.sched.fault_bus;
if ~isnumeric(selected) || ~isscalar(selected) || ~isreal(selected) || ...
        ~isfinite(selected) || ~ismember(selected,bus_ids)
    error('plot_ibr_ts_results:badFaultBus', ...
        'RESULT.sched.fault_bus must be one external ID in RESULT.bus_ids.');
end
labels = {sprintf('|V| fault bus %g',selected)};
end

function events = event_markers(result)
events = struct('time',{},'label',{},'applied',{},'type',{});
if isfield(result,'event_log') && isstruct(result.event_log) && ~isempty(result.event_log)
    for k = 1:numel(result.event_log)
        e = result.event_log(k);
        if ~isfield(e,'t') || ~isscalar(e.t) || ~isfinite(e.t) || ...
                ~isfield(e,'type') || ~isfield(e,'applied')
            continue;
        end
        applied = logical(e.applied);
        type = char(string(e.type));
        if strcmpi(type,'sg_on')
            % SG_ON commits only the reclose *request*.  The breaker closes
            % later under a distinct SG_RECLOSE transaction after the
            % synchronism dwell succeeds.  Keep those two physical events
            % visually distinct even when the request itself was accepted.
            status = 'accepted';
            if ~applied
                status = 'rejected';
                if isfield(e,'details') && ~isempty(e.details)
                    status = char(string(e.details));
                end
            end
            events(end+1) = struct('time',e.t, ...
                'label',sprintf('sg on request (%s)',status), ...
                'applied',applied,'type','sg_on_request'); %#ok<AGROW>
        elseif strcmpi(type,'sg_reclose_timeout')
            events(end+1) = struct('time',e.t, ...
                'label','sg reclose timeout','applied',false, ...
                'type','sg_reclose_timeout'); %#ok<AGROW>
        elseif applied
            label = strrep(type,'_',' ');
            events(end+1) = struct('time',e.t,'label',label, ...
                'applied',true,'type',type); %#ok<AGROW>
        end
    end
end
% Backward-compatible fallback only when no authoritative event log exists.
if isempty(events) && isfield(result,'events') && isstruct(result.events)
    for k = 1:numel(result.events)
        if isfield(result.events(k),'t') && isfinite(result.events(k).t) && ...
                isfield(result.events(k),'type')
            type = char(string(result.events(k).type));
            events(end+1) = struct('time',result.events(k).t, ...
                'label',[strrep(type,'_',' ') ' (scheduled)'], ...
                'applied',false,'type',type); %#ok<AGROW>
        end
    end
end
end

function add_event_lines(ax,events,with_labels)
if isempty(events), return; end
yl = ylim(ax);
for k = 1:numel(events)
    if events(k).applied
        style = '--'; color = [0.25 0.25 0.25];
    else
        style = ':'; color = [0.55 0.25 0.25];
    end
    xline(ax,events(k).time,style,'Color',color,'LineWidth',0.9, ...
        'HandleVisibility','off');
    if with_labels
        text(ax,events(k).time,yl(2),[' ' events(k).label], ...
            'Rotation',90,'VerticalAlignment','top','FontSize',7, ...
            'Interpreter','none','Clipping','on');
    end
end
end

function values = marker_time_struct(events)
values = struct();
for k = 1:numel(events)
    key = matlab.lang.makeValidName(events(k).type,'ReplacementStyle','underscore');
    if isfield(values,key)
        old = values.(key);
        values.(key) = [old events(k).time];
    else
        values.(key) = events(k).time;
    end
end
end

function suffix = run_status_suffix(result)
suffix='';
if isfield(result,'converged') && ~logical(result.converged)
    suffix=' -- PARTIAL / FAILED CLOSED';
end
end
