function init = mixed_ibr_sg_on_gfl_initialize(case_data, dae, event_context, opt)
%MIXED_IBR_SG_ON_GFL_INITIALIZE Mode-aware PF seed for SG-on, all-GFL DAE.
%   This is a PROJECT_DERIVED numerical initializer only.  It does not alter
%   the production GFL/SG ODEs, inputs, KCL, limits, or Newton acceptance
%   gates.  An online GFL controls scheduled P/Q, hence its bus is PQ for this
%   warm-start PF; the online SG remains the sole REF.  The caller still solves
%   and verifies the full nonlinear DAE with all physical KCL rows.

arguments
    case_data struct
    dae struct
    event_context struct
    opt struct = struct()
end

init = struct('applicable',false,'converged',false,'failure_id','', ...
    'failure_reason','','x0',dae.x0,'y0',dae.y0,'u0',dae.u0,'pf',struct(), ...
    'gfl_device_indices',[],'classification','PROJECT_DERIVED');

if ~isfield(case_data,'bus_data') || size(case_data.bus_data,2) < 10
    init.failure_id = 'mixed_ibr_sg_on_gfl_initialize:badCaseSchema';
    init.failure_reason = ['The mode-aware PF seed requires standardized bus_data ' ...
        'generation, load, and shunt columns.'];
    return;
end

nd = numel(dae.devices);
online = false(nd,1); modes = strings(nd,1); is_ibr = false(nd,1);
for k = 1:nd
    dev = dae.devices(k);
    key = matlab.lang.makeValidName(char(dev.device_id),'ReplacementStyle','underscore');
    online(k) = logical(field_or(dev,'initial_online',true));
    modes(k) = string(field_or(dev,'initial_mode',field_or(dev,'mode','')));
    if isfield(event_context,'hybrid_state') && isstruct(event_context.hybrid_state)
        hs = event_context.hybrid_state;
        if isfield(hs,'device_online') && isfield(hs.device_online,key)
            online(k) = logical(hs.device_online.(key));
        end
        if isfield(hs,'device_modes') && isfield(hs.device_modes,key)
            modes(k) = string(hs.device_modes.(key));
        end
    end
    if isfield(dev,'capabilities') && isfield(dev.capabilities,'resource_type')
        is_ibr(k) = strcmpi(dev.capabilities.resource_type,'ibr');
    else
        is_ibr(k) = startsWith(upper(string(dev.device_id)),"IBR");
    end
end

gfl = find(online & is_ibr & strcmpi(modes,'gfl'));
online_ibr = find(online & is_ibr);
if isempty(gfl) || numel(gfl) ~= numel(online_ibr)
    % This narrow helper is intentionally not a fallback for GFM/mixed modes.
    return;
end
if ~any(online & ~is_ibr & ismember(lower(modes),["sg","synchronous"]))
    init.failure_id = 'mixed_ibr_sg_on_gfl_initialize:noOnlineSG';
    init.failure_reason = 'All-GFL mode-aware initialization requires an online SG reference.';
    return;
end

pf_opt = struct('verbose',false,'plot_results',false,'max_iter',50, ...
    'tolerance',1e-10,'enforce_q_limits',false);
if isfield(opt,'pf_opt') && isstruct(opt.pf_opt)
    names = fieldnames(opt.pf_opt);
    for k=1:numel(names), pf_opt.(names{k})=opt.pf_opt.(names{k}); end
end

% composite_dae freezes P and Q loads as admittances at the original PF
% voltage.  A second ordinary constant-power PF is therefore not a KCL-exact
% seed after GFL buses change from PV to PQ.  Re-express the unchanged loads
% as the exact shunts used by composite_dae before solving the mode-aware PF.
base_pf = pfsolver.powerflow_newton_raphson(case_data,pf_opt);
if ~base_pf.converged
    init.failure_id = 'mixed_ibr_sg_on_gfl_initialize:basePfNoConverge';
    init.failure_reason = sprintf('Base PF did not converge: %s.',base_pf.reason);
    return;
end

seed_case = case_data;
for row = 1:size(seed_case.bus_data,1)
    bus_id = seed_case.bus_data(row,1);
    bp = find(base_pf.external_bus_ids == bus_id,1);
    if isempty(bp) || ~isfinite(base_pf.bus_voltage(bp)) || ...
            base_pf.bus_voltage(bp) <= 0
        init.failure_id = 'mixed_ibr_sg_on_gfl_initialize:basePfBusMap';
        init.failure_reason = sprintf( ...
            'Base PF has no finite positive voltage for external bus %g.',bus_id);
        return;
    end
    vm2 = base_pf.bus_voltage(bp)^2;
    seed_case.bus_data(row,9) = seed_case.bus_data(row,9) + ...
        seed_case.bus_data(row,7)/vm2;
    seed_case.bus_data(row,10) = seed_case.bus_data(row,10) - ...
        seed_case.bus_data(row,8)/vm2;
    seed_case.bus_data(row,7:8) = 0;
end
for kk = gfl(:)'
    dev = dae.devices(kk);
    row = find(seed_case.bus_data(:,1) == dev.bus_id,1);
    if isempty(row)
        init.failure_id = 'mixed_ibr_sg_on_gfl_initialize:busMap';
        init.failure_reason = sprintf('GFL device %s bus %g is absent from bus_data.',dev.device_id,dev.bus_id);
        return;
    end
    p_slot = find(strcmpi(string(dev.input_names),'P_ref'),1);
    q_slot = find(strcmpi(string(dev.input_names),'Q_ref'),1);
    if isempty(p_slot) || isempty(q_slot)
        init.failure_id = 'mixed_ibr_sg_on_gfl_initialize:missingInput';
        init.failure_reason = sprintf('GFL device %s requires P_ref and Q_ref inputs.',dev.device_id);
        return;
    end
    % Each IEEE14 IBR is the unique controllable resource at its terminal bus.
    seed_case.bus_data(row,2) = 3;  % PQ: specified P and Q, solved |V|/angle.
    seed_case.bus_data(row,5) = dev.u0(p_slot);
    seed_case.bus_data(row,6) = dev.u0(q_slot);
end

pf = pfsolver.powerflow_newton_raphson(seed_case,pf_opt);
init.applicable = true;
init.pf = pf;
init.gfl_device_indices = gfl(:)';
if ~pf.converged
    init.failure_id = 'mixed_ibr_sg_on_gfl_initialize:pfNoConverge';
    init.failure_reason = sprintf('Mode-aware all-GFL PF did not converge: %s.',pf.reason);
    return;
end

V = pf.bus_voltage(:).*exp(1i*deg2rad(pf.bus_angle_deg(:)));
x = dae.x0;
u = dae.u0;
for kk = find(online(:))'
    dev = dae.devices(kk);
    if ~isfield(dev,'equilibrium_initialize') || ...
            isempty(dev.equilibrium_initialize) || ...
            ~isa(dev.equilibrium_initialize,'function_handle')
        init.failure_id = 'mixed_ibr_sg_on_gfl_initialize:missingInitializer';
        init.failure_reason = sprintf('Online device %s does not expose equilibrium initialization.',dev.device_id);
        return;
    end
    row = find(seed_case.bus_data(:,1) == dev.bus_id,1);
    if is_ibr(kk)
        p_slot = find(strcmpi(string(dev.input_names),'P_ref'),1);
        q_slot = find(strcmpi(string(dev.input_names),'Q_ref'),1);
        P_seed = dev.u0(p_slot); Q_seed = dev.u0(q_slot);
    else
        P_seed = pf.P_generation(row); Q_seed = pf.Q_generation(row);
    end
    try
        x_dev = dev.equilibrium_initialize(V(dev.bus_position),P_seed,Q_seed,event_context);
    catch me
        init.failure_id = 'mixed_ibr_sg_on_gfl_initialize:deviceInitializer';
        init.failure_reason = sprintf('GFL initializer for %s failed: %s',dev.device_id,me.message);
        return;
    end
    xr = dae.device_offsets(kk)+1:dae.device_offsets(kk)+dev.nx;
    if numel(x_dev) ~= dev.nx || any(~isfinite(x_dev))
        init.failure_id = 'mixed_ibr_sg_on_gfl_initialize:invalidDeviceState';
        init.failure_reason = sprintf('GFL initializer for %s returned an invalid state.',dev.device_id);
        return;
    end
    x(xr) = x_dev(:);
    if ~is_ibr(kk)
        ur = dae.u_offsets(kk)+1:dae.u_offsets(kk)+dev.nu;
        z = dev.f(0,x_dev,y_from_voltage(V),[0;0],event_context);
        t_sensitivity = dev.f(0,x_dev,y_from_voltage(V),[1;0],event_context)-z;
        e_sensitivity = dev.f(0,x_dev,y_from_voltage(V),[0;1],event_context)-z;
        if abs(t_sensitivity(2))<eps || abs(e_sensitivity(3))<eps
            init.failure_id = 'mixed_ibr_sg_on_gfl_initialize:controlSensitivity';
            init.failure_reason = sprintf('SG equilibrium-control sensitivity is singular for %s.',dev.device_id);
            return;
        end
        u(ur(1)) = -z(2)/t_sensitivity(2);
        u(ur(2)) = -z(3)/e_sensitivity(3);
    end
end

y = zeros(size(dae.y0));
y(1:2:end) = real(V); y(2:2:end) = imag(V);
init.converged = true;
init.x0 = x;
init.y0 = y;
init.u0 = u;
end

function value = field_or(s,name,default_value)
if isfield(s,name) && ~isempty(s.(name)), value=s.(name); else, value=default_value; end
end

function y = y_from_voltage(V)
y=zeros(2*numel(V),1); y(1:2:end)=real(V); y(2:2:end)=imag(V);
end
