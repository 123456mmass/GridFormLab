function summary = sssa_load_sweep_tables(points)
%SSSA_LOAD_SWEEP_TABLES  Summary + per-point eigenvalue tables.
%   SUMMARY = stability.sssa_load_sweep_tables(POINTS) builds the summary
%   table (one row per load point) and attaches a complete eigenvalue table
%   per successful point.

n = numel(points);
rows = cell(n,1);
for k = 1:n
    p = points{k};
    row = struct();
    row.Index = k;
    row.LoadIncrease_pct = p.load_percentage;
    row.LoadScale_alpha = p.alpha;
    if isfield(p,'case_audit') && isstruct(p.case_audit)
        row.Total_P_load_MW = option_value(p.case_audit,'after_total_Pd_MW',NaN);
        row.Total_Q_load_MVAr = option_value(p.case_audit,'after_total_Qd_MVAr',NaN);
        if isnan(row.Total_P_load_MW) && isfield(p.case_audit,'after_total_Pload_pu')
            row.Total_P_load_MW = p.case_audit.after_total_Pload_pu * ...
                option_value(p.case_audit,'Sbase_MVA',100.0);
        end
        if isnan(row.Total_Q_load_MVAr) && isfield(p.case_audit,'after_total_Qload_pu')
            row.Total_Q_load_MVAr = p.case_audit.after_total_Qload_pu * ...
                option_value(p.case_audit,'Sbase_MVA',100.0);
        end
    else
        row.Total_P_load_MW = NaN;
        row.Total_Q_load_MVAr = NaN;
    end
    pf = option_field(p,'pf');
    row.PF_converged = option_value(pf,'converged',false);
    row.PF_iterations = option_value(pf,'iterations',NaN);
    row.PF_max_mismatch = option_value(pf,'max_mismatch',NaN);
    eq = option_field(p,'equilibrium');
    row.Equilibrium_converged = option_value(eq,'converged',false);
    row.f_active_inf = NaN;
    row.g_inf = NaN;
    if isfield(eq,'f0') && ~isempty(eq.f0)
        row.f_active_inf = norm(eq.f0,inf);
    elseif isfield(eq,'active_f_residual_norm')
        row.f_active_inf = eq.active_f_residual_norm;
    end
    if isfield(eq,'g0') && ~isempty(eq.g0)
        row.g_inf = norm(eq.g0,inf);
    elseif isfield(eq,'physical_kcl_norm')
        row.g_inf = eq.physical_kcl_norm;
    end
    if isfield(eq,'active_state_indices')
        row.Active_states = numel(eq.active_state_indices);
    elseif isfield(p,'sssa_diag') && isfield(p.sssa_diag,'eigenvalue_count')
        row.Active_states = p.sssa_diag.eigenvalue_count;
    else
        row.Active_states = NaN;
    end
    if isfield(p,'sssa_diag')
        sd = p.sssa_diag;
        row.Eigenvalue_count = option_value(sd,'eigenvalue_count',NaN);
        row.Stable_roots = option_value(sd,'stable_roots',NaN);
        row.Marginal_roots = option_value(sd,'marginal_roots',NaN);
        row.Unstable_roots = option_value(sd,'unstable_roots',NaN);
        row.Max_Real_lambda = option_value(sd,'max_real_eigenvalue',NaN);
        row.Critical_mode_freq_Hz = option_value(sd,'critical_mode_frequency_Hz',NaN);
        row.Critical_mode_damping = option_value(sd,'critical_mode_damping',NaN);
    else
        row.Eigenvalue_count = NaN;
        row.Stable_roots = NaN;
        row.Marginal_roots = NaN;
        row.Unstable_roots = NaN;
        row.Max_Real_lambda = NaN;
        row.Critical_mode_freq_Hz = NaN;
        row.Critical_mode_damping = NaN;
    end
    row.Dominant_device_state = '';
    row.Status = p.status;
    if strcmp(p.status,'FAILED')
        row.Failure_reason = option_value(p,'failure_reason','');
    else
        row.Failure_reason = '';
    end
    rows{k} = row;
end
% Convert cell of structs to a uniform struct array for struct2table.
if ~isempty(rows)
    all_fields = {};
    for k = 1:numel(rows)
        all_fields = union(all_fields, fieldnames(rows{k}));
    end
    for k = 1:numel(rows)
        for f = 1:numel(all_fields)
            if ~isfield(rows{k}, all_fields{f})
                rows{k}.(all_fields{f}) = NaN;
            end
        end
    end
    rows_struct = rows{1};
    for k = 2:numel(rows)
        rows_struct(k) = rows{k};
    end
    summary = struct2table(rows_struct,'AsArray',true);
else
    summary = table();
end
end

function v = option_value(s, name, fallback)
v = fallback;
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
end
end

function v = option_field(s, name)
v = struct();
if isstruct(s) && isfield(s, name) && isstruct(s.(name))
    v = s.(name);
end
end
