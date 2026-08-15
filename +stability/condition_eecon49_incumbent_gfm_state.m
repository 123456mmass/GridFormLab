function [x_out, audit] = condition_eecon49_incumbent_gfm_state( ...
    t, x_in, candidate, dae, before_modes, after_modes, y, u, event_context)
%CONDITION_EECON49_INCUMBENT_GFM_STATE Map dependent PI memory to a new certificate.
%   A support transaction can change the authenticated destination operating
%   point while a device remains GFM. The ordinary mode-transfer callback is
%   correctly skipped for that incumbent, but its outer voltage-loop memory
%   then still belongs to the previous configuration. For the EECON49 dual
%   model, only gfm_xi_Vd/gfm_xi_Vq are destination-equilibrium controller
%   coordinates; physical current, Vdc, angle, speed, E, and current-loop
%   integrators remain event-left states.
%
%   This helper copies exactly those two named coordinates from the candidate's
%   fingerprint-covered eq_x0 for every before-GFM AND after-GFM EECON49 dual
%   device. It is pure: failure throws before the caller publishes its local
%   transaction copies. Other device families are byte-identical no-ops.

current_tol = 1e-10; % Existing EECON49 mode-transfer terminal-port contract.

if ~isnumeric(x_in) || ~isvector(x_in) || any(~isfinite(x_in(:))) || ...
        ~isstruct(dae) || ~isfield(dae,'devices') || ...
        ~isfield(dae,'device_offsets') || ~isfield(dae,'u_offsets')
    error('stability:condition_eecon49_incumbent_gfm_state:badRuntimeState', ...
        'The composite state and DAE ownership maps must be finite and complete.');
end
x_in = x_in(:);
nd = numel(dae.devices);
if numel(dae.device_offsets) ~= nd || numel(dae.u_offsets) ~= nd || ...
        ~iscell(before_modes) || ~iscell(after_modes) || ...
        numel(before_modes) ~= nd || numel(after_modes) ~= nd
    error('stability:condition_eecon49_incumbent_gfm_state:badModeMap', ...
        'Before/after modes and DAE offsets must align with dae.devices.');
end

incumbent = false(1,nd);
for k = 1:nd
    dev = dae.devices(k);
    supported = isfield(dev,'device_type') && ...
        strcmpi(char(dev.device_type),'ibr_eecon49_dual');
    incumbent(k) = supported && strcmpi(char(before_modes{k}),'gfm') && ...
        strcmpi(char(after_modes{k}),'gfm');
end
indices = find(incumbent);
audit = struct('applied',false, ...
    'classification','PROJECT_DERIVED', ...
    'device_indices',indices, ...
    'device_ids',{{}}, ...
    'state_names',{{'gfm_xi_Vd','gfm_xi_Vq'}}, ...
    'global_state_indices',[], ...
    'max_current_jump',0, ...
    'current_tolerance',current_tol);
x_out = x_in;
if isempty(indices)
    return;
end

if ~isstruct(candidate) || ~isscalar(candidate) || ...
        ~isfield(candidate,'eq_x0') || ~isnumeric(candidate.eq_x0) || ...
        ~isvector(candidate.eq_x0) || numel(candidate.eq_x0) ~= numel(x_in) || ...
        any(~isfinite(candidate.eq_x0(:)))
    error('stability:condition_eecon49_incumbent_gfm_state:badCertificateState', ...
        ['An EECON49 incumbent requires one finite authenticated eq_x0 matching ' ...
         'the full composite state vector.']);
end
if ~isnumeric(y) || ~isvector(y) || any(~isfinite(y(:))) || ...
        ~isnumeric(u) || ~isvector(u) || any(~isfinite(u(:))) || ...
        ~isstruct(event_context) || ~isscalar(event_context) || ...
        ~isfield(event_context,'hybrid_state') || ...
        ~isfield(event_context.hybrid_state,'device_modes') || ...
        ~isfield(event_context.hybrid_state,'device_online')
    error('stability:condition_eecon49_incumbent_gfm_state:badRuntimeState', ...
        'Current-continuity evaluation requires finite y/u and a complete right context.');
end
y = y(:);
u = u(:);
if isfield(dae,'y0') && numel(y) ~= numel(dae.y0)
    error('stability:condition_eecon49_incumbent_gfm_state:badRuntimeState', ...
        'The algebraic state does not match the composite DAE.');
end
if isfield(dae,'u0') && numel(u) ~= numel(dae.u0)
    error('stability:condition_eecon49_incumbent_gfm_state:badRuntimeState', ...
        'The input state does not match the composite DAE.');
end
certificate_x = candidate.eq_x0(:);
allowed = false(size(x_in));
ids = cell(1,numel(indices));
global_indices = zeros(numel(indices),2);
max_jump = 0;

for q = 1:numel(indices)
    k = indices(q);
    dev = dae.devices(k);
    required = {'device_id','nx','nu','state_names','current_injection'};
    for r = 1:numel(required)
        if ~isfield(dev,required{r})
            error('stability:condition_eecon49_incumbent_gfm_state:badDeviceLayout', ...
                'EECON49 incumbent device %d lacks %s.',k,required{r});
        end
    end
    if ~isa(dev.current_injection,'function_handle') || ...
            numel(dev.state_names) ~= dev.nx
        error('stability:condition_eecon49_incumbent_gfm_state:badDeviceLayout', ...
            'Device %s has an invalid state/current contract.',dev.device_id);
    end
    key = matlab.lang.makeValidName(char(dev.device_id), ...
        'ReplacementStyle','underscore');
    hs = event_context.hybrid_state;
    if ~isfield(hs.device_modes,key) || ...
            ~strcmpi(char(hs.device_modes.(key)),'gfm') || ...
            ~isfield(hs.device_online,key) || ...
            ~isscalar(hs.device_online.(key)) || ...
            ~logical(hs.device_online.(key))
        error('stability:condition_eecon49_incumbent_gfm_state:badRightContext', ...
            'Device %s is not an online GFM in the right event context.',dev.device_id);
    end

    local = zeros(1,2);
    wanted = {'gfm_xi_Vd','gfm_xi_Vq'};
    for j = 1:2
        hit = find(strcmp(dev.state_names,wanted{j}));
        if numel(hit) ~= 1
            error('stability:condition_eecon49_incumbent_gfm_state:badDeviceLayout', ...
                'Device %s must own exactly one state named %s.', ...
                dev.device_id,wanted{j});
        end
        local(j) = hit;
    end
    xr = dae.device_offsets(k) + (1:dev.nx);
    ur = dae.u_offsets(k) + (1:dev.nu);
    if isempty(xr) || xr(1) < 1 || xr(end) > numel(x_in) || ...
            (~isempty(ur) && (ur(1) < 1 || ur(end) > numel(u)))
        error('stability:condition_eecon49_incumbent_gfm_state:badDeviceLayout', ...
            'Device %s offsets exceed the composite state/input vectors.',dev.device_id);
    end
    gi = dae.device_offsets(k) + local;
    allowed(gi) = true;

    try
        current_before = dev.current_injection( ...
            t,x_out(xr),y,u(ur),event_context);
    catch me
        error('stability:condition_eecon49_incumbent_gfm_state:currentEvaluation', ...
            'Current evaluation failed for %s before conditioning: %s: %s', ...
            dev.device_id,me.identifier,me.message);
    end
    if ~isnumeric(current_before) || ~isscalar(current_before) || ...
            ~isfinite(current_before)
        error('stability:condition_eecon49_incumbent_gfm_state:nonfiniteCurrent', ...
            'Device %s returned a non-finite pre-conditioning current.',dev.device_id);
    end

    x_out(gi) = certificate_x(gi);
    try
        current_after = dev.current_injection( ...
            t,x_out(xr),y,u(ur),event_context);
    catch me
        error('stability:condition_eecon49_incumbent_gfm_state:currentEvaluation', ...
            'Current evaluation failed for %s after conditioning: %s: %s', ...
            dev.device_id,me.identifier,me.message);
    end
    if ~isnumeric(current_after) || ~isscalar(current_after) || ...
            ~isfinite(current_after)
        error('stability:condition_eecon49_incumbent_gfm_state:nonfiniteCurrent', ...
            'Device %s returned a non-finite post-conditioning current.',dev.device_id);
    end
    jump = abs(current_after-current_before);
    if jump > current_tol
        error('stability:condition_eecon49_incumbent_gfm_state:currentContinuity', ...
            ['Conditioning device %s changed terminal current by %.3g, which ' ...
             'exceeds the existing %.3g transfer contract.'], ...
            dev.device_id,jump,current_tol);
    end

    ids{q} = char(dev.device_id);
    global_indices(q,:) = gi;
    max_jump = max(max_jump,jump);
end

if ~isequaln(x_out(~allowed),x_in(~allowed))
    error('stability:condition_eecon49_incumbent_gfm_state:stateOwnership', ...
        'Conditioning changed a coordinate outside gfm_xi_Vd/gfm_xi_Vq.');
end
if any(~isfinite(x_out))
    error('stability:condition_eecon49_incumbent_gfm_state:badCertificateState', ...
        'Conditioning produced a non-finite composite state.');
end

audit.applied = true;
audit.device_ids = ids;
audit.global_state_indices = global_indices;
audit.max_current_jump = max_jump;
end
