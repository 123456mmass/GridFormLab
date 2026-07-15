function indices = ts_dynamic_state_indices(dae,event_context)
%TS_DYNAMIC_STATE_INDICES Resolve the authenticated composite TS state map.
%   INDICES = stability.ts_dynamic_state_indices(DAE,EVENT_CONTEXT) asks each
%   device for its runtime dynamic-state indices, maps them into the composite
%   state vector, and removes source-defined frozen singular states. The same
%   helper is used by the no-event and event-aware composite TS routes.

arguments
    dae struct
    event_context struct = struct()
end

indices = [];
for k = 1:numel(dae.devices)
    dev = dae.devices(k);
    if isfield(dev,'dynamic_state_indices_for_context') && ...
            isa(dev.dynamic_state_indices_for_context,'function_handle')
        local = dev.dynamic_state_indices_for_context(event_context);
    elseif isfield(dev,'active_state_indices_for_context') && ...
            isa(dev.active_state_indices_for_context,'function_handle')
        local = dev.active_state_indices_for_context(event_context);
    else
        is_online = true;
        if isfield(event_context,'hybrid_state') && ...
                isstruct(event_context.hybrid_state) && ...
                isfield(event_context.hybrid_state,'device_online')
            key = matlab.lang.makeValidName(char(dev.device_id), ...
                'ReplacementStyle','underscore');
            if isfield(event_context.hybrid_state.device_online,key)
                is_online = logical( ...
                    event_context.hybrid_state.device_online.(key));
            end
        end
        if ~is_online
            local = [];
        elseif isfield(dev,'active_state_indices')
            local = dev.active_state_indices;
        else
            local = 1:dev.nx;
        end
    end

    local = local(:)';
    if ~isnumeric(local) || ~isreal(local) || any(~isfinite(local)) || ...
            any(local~=fix(local)) || any(local<1) || any(local>dev.nx) || ...
            numel(unique(local))~=numel(local)
        error('ts_dynamic_state_indices:badDeviceDynamicStates', ...
            'Device %s returned invalid dynamic-state indices.',dev.device_id);
    end
    if isfield(dev,'frozen_state_indices') && ...
            ~isempty(dev.frozen_state_indices)
        local = setdiff(local,dev.frozen_state_indices(:)','stable');
    end
    indices = [indices,dae.device_offsets(k)+local]; %#ok<AGROW>
end

if numel(unique(indices))~=numel(indices)
    error('ts_dynamic_state_indices:duplicateGlobalState', ...
        'Device runtime maps produced duplicate composite state indices.');
end
end
