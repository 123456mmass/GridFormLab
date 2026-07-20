function data = sssa_load_sweep_plot_data(points,mode_tracking)
%SSSA_LOAD_SWEEP_PLOT_DATA  Pure plot-data adapter for SSSA load sweeps.
%   DATA = stability.sssa_load_sweep_plot_data(POINTS,MODE_TRACKING) copies
%   raw eigenvalues and accepted-equilibrium diagnostics into a renderer-ready
%   structure.  It never changes ordering, filters roots, or feeds results back
%   into PF/equilibrium/SSSA.  Tracked modal coordinates are constructed only
%   from the cumulative raw-index map published by the mode matcher.

success_idx = find(cellfun(@(p) strcmp(p.status,'SUCCESS'),points));
n = numel(success_idx);
data = struct();
data.success_indices = success_idx(:).';
data.load_percentages = NaN(n,1);
data.load_scales = NaN(n,1);
data.eigenvalues = cell(n,1);
data.max_real_eigenvalue = NaN(n,1);
data.voltage_min_pu = NaN(n,1);
data.f_active_inf = NaN(n,1);
data.g_inf = NaN(n,1);
data.i_d_pu_inverter = NaN(n,1);
data.i_q_pu_inverter = NaN(n,1);
data.P_pu_system = NaN(n,1);
data.Q_pu_system = NaN(n,1);
data.P_MW = NaN(n,1);
data.Q_MVAr = NaN(n,1);
data.device_id = cell(n,1);
data.device_type = cell(n,1);
data.current_source = cell(n,1);

for k = 1:n
    p = points{success_idx(k)};
    data.load_percentages(k) = p.load_percentage;
    data.load_scales(k) = p.alpha;
    if isfield(p,'sssa') && isstruct(p.sssa) && isfield(p.sssa,'eigenvalues')
        lam = p.sssa.eigenvalues(:);
        data.eigenvalues{k} = lam;
        if ~isempty(lam), data.max_real_eigenvalue(k) = max(real(lam)); end
    else
        data.eigenvalues{k} = [];
    end
    if isfield(p,'pf') && isstruct(p.pf)
        data.voltage_min_pu(k) = option_value(p.pf,'voltage_min_pu',NaN);
        if isnan(data.voltage_min_pu(k)) && isfield(p.pf,'bus_voltage')
            data.voltage_min_pu(k) = min(abs(p.pf.bus_voltage));
        end
    end
    if isfield(p,'equilibrium') && isstruct(p.equilibrium)
        eq = p.equilibrium;
        if isfield(eq,'f0') && ~isempty(eq.f0)
            data.f_active_inf(k) = norm(eq.f0,inf);
        elseif isfield(eq,'residual_norm')
            data.f_active_inf(k) = eq.residual_norm;
        end
        if isfield(eq,'g0') && ~isempty(eq.g0)
            data.g_inf(k) = norm(eq.g0,inf);
        elseif isfield(eq,'physical_kcl_norm')
            data.g_inf(k) = eq.physical_kcl_norm;
        end
    end
    if isfield(p,'operating_point') && isstruct(p.operating_point)
        op = p.operating_point;
        data.i_d_pu_inverter(k) = option_value(op,'i_d_pu_inverter',NaN);
        data.i_q_pu_inverter(k) = option_value(op,'i_q_pu_inverter',NaN);
        data.P_pu_system(k) = option_value(op,'P_pu_system',NaN);
        data.Q_pu_system(k) = option_value(op,'Q_pu_system',NaN);
        data.P_MW(k) = option_value(op,'P_MW',NaN);
        data.Q_MVAr(k) = option_value(op,'Q_MVAr',NaN);
        data.device_id{k} = option_value(op,'device_id','');
        data.device_type{k} = option_value(op,'device_type','');
        data.current_source{k} = option_value(op,'current_source','');
    end
end

data.tracked_segments = {};
if isstruct(mode_tracking) && isfield(mode_tracking,'segments')
    for s = 1:numel(mode_tracking.segments)
        seg = mode_tracking.segments{s};
        if ~isfield(seg,'available') || ~seg.available || ...
                ~isfield(seg,'tracked_indices') || isempty(seg.tracked_indices)
            continue;
        end
        idx = seg.point_indices(:).';
        tracked = seg.tracked_indices;
        if size(tracked,1) ~= numel(idx)
            error('sssa_load_sweep_plot_data:trackedShape', ...
                'tracked_indices row count must equal segment point count.');
        end
        nmodes = size(tracked,2);
        lambda = NaN(numel(idx),nmodes);
        pct = NaN(numel(idx),1);
        for k = 1:numel(idx)
            p = points{idx(k)};
            raw = p.sssa.eigenvalues(:);
            map = tracked(k,:);
            if numel(raw) ~= nmodes || any(map < 1) || any(map > numel(raw))
                error('sssa_load_sweep_plot_data:trackedIndex', ...
                    'Tracked modal index is outside the raw spectrum.');
            end
            lambda(k,:) = raw(map).';
            pct(k) = p.load_percentage;
        end
        data.tracked_segments{end+1,1} = struct( ...
            'point_indices',idx,'load_percentages',pct, ...
            'raw_indices',tracked,'eigenvalues',lambda); %#ok<AGROW>
    end
end
end

function v = option_value(s,name,fallback)
v = fallback;
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    v = s.(name);
end
end
