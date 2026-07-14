function all_specs = active_bound_collect(dae, x_full, y_full, u_base, eq_context)
%active_bound_collect  Gather active-bound constraint specs from every device.
%   all_specs = active_bound_collect(dae, x_full, y_full, u_base, eq_context)
%
%   Returns a cell array indexed by device position in dae.devices.  Each entry
%   that declares equilibrium_constraint_specs gets a struct with fields:
%     .offset   — global x-offset of this device
%     .u_offset — global reserved-offset
%     .dev_nu   — number of inputs for this device
%     .dev_nx   — number of states
%     .specs    — list returned by dev.equilibrium_constraint_specs(…)
%   Devices without the callback yield an empty [] entry.
%
%   If NO device declares constraints the result is the empty [] (not a cell
%   share).  The caller uses isempty(all_specs) to skip the active-bound path.

nd = numel(dae.devices);
all_specs = cell(nd, 1);
has_any = false;

for dk = 1:nd
    dev = dae.devices(dk);
    if ~isfield(dev, 'equilibrium_constraint_specs') || ...
            isempty(dev.equilibrium_constraint_specs) || ...
            ~isa(dev.equilibrium_constraint_specs, 'function_handle')
        continue;
    end

    xoff = dae.device_offsets(dk);
    uoff = dae.u_offsets(dk);

    x_dev = x_full(xoff+1 : xoff + dev.nx);
    u_dev = [];
    if dev.nu > 0
        u_dev = u_base(uoff+1 : uoff + dev.nu);
    end

    c_list = dev.equilibrium_constraint_specs(x_dev, y_full, u_dev, eq_context);

    if isempty(c_list)
        continue;
    end

    entry.offset   = xoff;
    entry.u_offset = uoff;
    entry.dev_nu   = dev.nu;
    entry.dev_nx   = dev.nx;
    entry.specs    = c_list;

    all_specs{dk} = entry;
    has_any = true;
end

if ~has_any
    all_specs = [];
end
end