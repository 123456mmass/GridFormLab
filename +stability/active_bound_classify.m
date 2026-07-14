function regime = active_bound_classify(z, active_x, frozen_x, frozen_x_val, ...
    free_vars, vcon_vars, vcon_ref, ny, u_base, slack_u_id, all_specs, eq_ctx)
% active_bound_classify  Build regime struct array from z vector.
%  Output: struct array with fields (dev_idx, local_idx, regime).

% reassign track_v, slack inp to a know how many there are
n_slack = 0;
if ~isempty(slack_u_idx)
    n_slack = numel(slack_u_idx);
end

% reconstruct full x
nx_t = numel(active_x) + numel(frozen_x);
x_full = zeros(nx_t, 1);
x_full(active_x) = z(1:numel(active_x));
for fi = 1:numel(frozen_x)
    x_full(frozen_x(fi)) = frozen_x_val(fi);
end

% reconstruct full y
y_full = zeros(ny, 1);
nyf = numel(free_vars);
y_free = z(numel(active_x)+1 : numel(active_x)+nyf);
y_full(free_vars) = y_free;
y_full(vcon_vars) = vcon_ref;

% reconstruct full u including solved slack uno
u_full = u_base;
if n_slack > 0
    u_full(slack_u_idx) = z(end - n_slack + 1 : end);
end

regime = [];
for dk = 1:numel(all_specs)
    entry = all_specs{dk};
    if isempty(entry), continue; end
    x_dev = x_full(entry.offset+1 : entry.offset+entry.dev_nx);
    u_dev = [];
    if entry.dev_nu > 0
        u_dev = u_full(entry.u_offset+1 : entry.u_offset + entry.dev_nu);
    end
    for sp = 1:numel(entry.specs)
        rg = entry.specs(sp).classify_fn(x_dev, y_full, u_dev, eq_ctx);
        regime(end+1) = struct('dev_idx', dk, ...
            'local_idx', entry.specs(sp).local_idx, ...
            'regime', rg); %#ok<AGROW>
    end
end
end