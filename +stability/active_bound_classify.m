function regime = active_bound_classify(z, active_x, frozen_x, frozen_x_val, ...
    free_vars, vcon_vars, vcon_ref, ny, u_base, all_specs, eq_ctx)
% active_bound_classify  Build regime struct array from z vector.
%  Output: struct array with fields (dev_idx, local_idx, regime).

nx = numel(active_x) + numel(frozen_x);
x_full = zeros(nx, 1);
x_full(active_x) = z(1:numel(active_x));
for fi = 1:numel(frozen_x)
    x_full(frozen_x(fi)) = frozen_x_val(fi);
end

y_full = zeros(ny, 1);
nyf = numel(free_vars);
y_free = z(numel(active_x)+1 : numel(active_x)+nyf);
y_full(free_vars) = y_free;
y_full(vcon_vars) = vcon_ref;

regime = [];
for dk = 1:numel(all_specs)
    entry = all_specs{dk};
    if isempty(entry), continue; end
    x_dev = x_full(entry.offset+1 : entry.offset+entry.dev_nx);
    u_dev = [];
    if entry.dev_nu > 0
        u_dev = u_base(entry.u_offset+1 : entry.u_offset+entry.dev_nu);
    end
    for sp = 1:numel(entry.specs)
        rg = entry.specs(sp).classify_fn(x_dev, y_full, u_dev, eq_ctx);
        regime(end+1) = struct('dev_idx', dk, ...
            'local_idx', entry.specs(sp).local_idx, ...
            'regime', rg); %#ok<AGROW>
    end
end
end