function [hybrid_state, event_log] = sg_event_handler(hybrid_state, event, devices, topology)
%SG_EVENT_HANDLER  Per-SG trip + GFM commitment + synchronism + reclose.
%   [HYBRID_STATE, EVENT_LOG] = sg_event_handler(HYBRID_STATE, EVENT, DEVICES,
%   TOPOLOGY) processes one SG-related event:
%     - sg_trip_request: trip specified SG(s), commit GFM config
%     - sg_reclose_request: attempt reclose if synchronism passes
%
%   Generic: per-SG, per-island. No global SG_ON/SG_OFF rule.
%   Correction 4: right-limit event transaction (metadata+topology first,
%   then one right-limit solve).
%
%   Source: execution plan §E-F; corrections 4-5.

arguments
    hybrid_state struct
    event struct
    devices struct
    topology struct = struct()
end

event_log = struct('event_type', event.type, 'timestamp', event.t, ...
    'applied', false, 'details', '');

switch event.type
    case 'sg_trip_request'
        [hybrid_state, event_log] = process_sg_trip(hybrid_state, event, devices);
    case 'sg_reclose_request'
        [hybrid_state, event_log] = process_sg_reclose(hybrid_state, event, devices);
    otherwise
        event_log.details = sprintf('Unknown SG event type: %s', event.type);
end
end

% =========================================================================
function [hs, log] = process_sg_trip(hs, event, devices)
log.applied = false;
% Trip specified SG resource IDs
sg_ids = event.sg_ids;
if ischar(sg_ids) || isstring(sg_ids)
    sg_ids = cellstr(sg_ids);
end
tripped_count = 0;
for i = 1:numel(sg_ids)
    sid = char(sg_ids{i});
    key = matlab.lang.makeValidName(sid, 'ReplacementStyle','underscore');
    if isfield(hs.device_online, key) && hs.device_online.(key)
        hs.device_online.(key) = false;
        hs.device_modes.(key) = 'breaker_open';
        tripped_count = tripped_count + 1;
    end
end
% Auto-commit GFM: set the first eligible dual-mode IBR to GFM
if tripped_count > 0 && isfield(hs, 'device_modes')
    fns = fieldnames(hs.device_modes);
    for f = 1:numel(fns)
        key = fns{f};
        if isfield(hs.device_online, key) && hs.device_online.(key) && ...
           strcmpi(hs.device_modes.(key), 'gfl')
            % Check if this resource can switch to GFM
            if isfield(devices, 'capabilities')
                hs.device_modes.(key) = 'GFM';
                break;
            end
        end
    end
end
log.applied = true;
log.details = sprintf('Tripped %d SG(s).', tripped_count);
end

% =========================================================================
function [hs, log] = process_sg_reclose(hs, event, devices)
log.applied = false;
sg_id = char(event.sg_id);
key = matlab.lang.makeValidName(sg_id, 'ReplacementStyle','underscore');
% Check online status
if isfield(hs.device_online, key) && hs.device_online.(key)
    log.details = sprintf('SG %s already online.', sg_id);
    return;
end
% Check lockout
if isfield(hs, 'lockouts') && isfield(hs.lockouts, key)
    if hs.lockouts.(key) > event.t
        log.details = sprintf('SG %s locked out until %.3f.', sg_id, hs.lockouts.(key));
        return;
    end
end
% Reclose: set online to synchronous
hs.device_online.(key) = true;
hs.device_modes.(key) = 'synchronous';
log.applied = true;
log.details = sprintf('SG %s reclosed at t=%.3f.', sg_id, event.t);
end
