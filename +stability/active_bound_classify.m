function regime = active_bound_classify(z, active_x, frozen_x, frozen_x_val, ...
    free_vars, vcon_vars, vcon_ref, ny, u_base, slack_u_idx, all_specs, eq_ctx)
%active_bound_classify  Build regime struct array from z vector.
%  Reconstructs full x/y/u (including solved slack inputs) from z and invokes
%  each constraint's classify_fn. Catches callback exceptions and reports them
%  as a badActiveBoundSpec marker on the offending entry so the caller can
%  fail closed. Output: struct array with fields (dev_idx, local_idx, regime).

n_slack = 0;
if ~isempty(slack_u_idx)
    n_slack = numel(slack_u_idx);
end

% ---- Reconstruct full x and validate dimension ----------------------------
nx_t = numel(active_x) + numel(frozen_x);
if numel(z) < numel(active_x) + numel(free_vars) + n_slack
    error('active_bound_classify:badZLength', ...
        'z length %d too small for active=%d free=%d slack=%d.', ...
        numel(z), numel(active_x), numel(free_vars), n_slack);
end
x_full = zeros(nx_t, 1);
x_full(active_x) = z(1:numel(active_x));
for fi = 1:numel(frozen_x)
    x_full(frozen_x(fi)) = frozen_x_val(fi);
end

% ---- Reconstruct full y ---------------------------------------------------
if ny < 0
    error('active_bound_classify:badNy', 'ny must be non-negative.');
end
y_full = zeros(ny, 1);
nyf = numel(free_vars);
y_free = z(numel(active_x)+1 : numel(active_x)+nyf);
y_full(free_vars) = y_free;
y_full(vcon_vars) = vcon_ref;

% ---- Reconstruct full u including solved slack ----------------------------
u_full = u_base;
if n_slack > 0
    u_full(slack_u_idx) = z(end - n_slack + 1 : end);
end

% ---- Invoke classify_fn for each constraint, fail closed on bad output ----
regime = struct('dev_idx', {}, 'local_idx', {}, 'regime', {});
for dk = 1:numel(all_specs)
    entry = all_specs{dk};
    if isempty(entry), continue; end
    x_dev = x_full(entry.offset+1 : entry.offset+entry.dev_nx);
    u_dev = [];
    if entry.dev_nu > 0
        u_dev = u_full(entry.u_offset+1 : entry.u_offset + entry.dev_nu);
    end
    for sp = 1:numel(entry.specs)
        try
            rg = entry.specs(sp).classify_fn(x_dev, y_full, u_dev, eq_ctx);
        catch me
            rg = sprintf('__BAD_SPEC__:classify dev=%d local=%d: %s', ...
                dk, entry.specs(sp).local_idx, me.message);
        end
        % Accept a char row-vector or a scalar string; otherwise mark bad.
        is_char_row = ischar(rg) && size(rg,1) == 1;
        is_str_scalar = isstring(rg) && isscalar(rg);
        if ~(is_char_row || is_str_scalar)
            rg = sprintf('__BAD_SPEC__:classify dev=%d local=%d non-string', ...
                dk, entry.specs(sp).local_idx);
        else
            rg = char(rg);
            if ~ismember(rg, {'interior','upper','lower'})
                rg = sprintf('__BAD_SPEC__:classify dev=%d local=%d regime=%s', ...
                    dk, entry.specs(sp).local_idx, rg);
            end
        end
        regime(end+1) = struct('dev_idx', dk, ...
            'local_idx', entry.specs(sp).local_idx, ...
            'regime', rg); %#ok<AGROW>
    end
end
end