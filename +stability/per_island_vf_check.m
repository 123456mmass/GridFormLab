function [has_vf, failing_island_ids, vf_bus_positions] = ...
    per_island_vf_check(Y, mpc, devices, hs_candidate, sg_id)
%PER_ISLAND_VF_CHECK  Online voltage-forming source per energized island.
%   [HAS_VF, FAILING_ISLAND_IDS, VF_BUS_POSITIONS] = per_island_vf_check(
%   Y, MPC, DEVICES, HS_CANDIDATE, SG_ID) checks that EVERY energized island
%   retains at least one online voltage-forming resource after the SG breaker
%   opens. A global "any device is VF" check is insufficient: if island A has
%   a GFM but island B does not, island B is left without a reference and the
%   simulation is physically invalid.
%
%   Inputs:
%     Y            - network admittance matrix (nb x nb)
%     mpc          - MATPOWER-style case struct (bus + branch)
%     devices      - device struct array from the composite DAE
%     hs_candidate - candidate hybrid_state snapshot (device_online +
%                    device_modes already updated for the SG breaker open)
%     sg_id        - device ID of the tripped SG (excluded from VF sources)
%
%   Outputs:
%     has_vf            - true iff every energized island has >=1 online VF
%     failing_island_ids - island IDs that are energized but lack a VF source
%     vf_bus_positions  - internal bus positions of online VF resources
%
%   This is a PURE function: no algebraic solve, no composite-DAE dependency.
%   It combines stability.island_components (Ybus BFS) with the device
%   online/mode snapshot. Classification: PROJECT_DERIVED per-island
%   eligibility; reuses island_components (NUMERICAL_METHOD BFS).
%
%   Source: C1 corrective extraction (user-approved validation-closure plan).

arguments
    Y (:,:) double
    mpc struct
    devices struct
    hs_candidate struct
    sg_id
end

% Build online VF bus positions (excluding the tripped SG device).
vf_bus_positions = [];
for k = 1:numel(devices)
    dev = devices(k);
    if strcmpi(char(dev.device_id), char(sg_id)), continue; end
    key = matlab.lang.makeValidName(char(dev.device_id), ...
        'ReplacementStyle','underscore');
    online_k = isfield(hs_candidate,'device_online') && ...
        isfield(hs_candidate.device_online,key) && ...
        logical(hs_candidate.device_online.(key));
    mode_k = '';
    if isfield(hs_candidate,'device_modes') && ...
            isfield(hs_candidate.device_modes,key)
        mode_k = char(hs_candidate.device_modes.(key));
    end
    if online_k && is_voltage_forming_mode(dev, mode_k)
        vf_bus_positions(end+1) = dev.bus_position; %#ok<AGROW>
    end
end

islands = stability.island_components(Y, mpc, ...
    struct('online_vf_positions', vf_bus_positions));

has_vf = true;
failing_island_ids = [];
for m = 1:numel(islands)
    if islands(m).energized && ~islands(m).has_online_vf_source
        has_vf = false;
        failing_island_ids(end+1) = islands(m).island_id; %#ok<AGROW>
    end
end
end

% =========================================================================
function tf = is_voltage_forming_mode(dev, mode)
%IS_VOLTAGE_FORMING_MODE  True if the device mode is voltage-forming.
tf = false;
if isempty(mode), return; end
if strcmpi(mode,'synchronous'), tf=true; return; end
if isfield(dev,'capabilities') && isstruct(dev.capabilities) && ...
        isfield(dev.capabilities,'voltage_forming_modes')
    vf = string(dev.capabilities.voltage_forming_modes);
    tf = any(strcmpi(vf, lower(mode)));
end
end
