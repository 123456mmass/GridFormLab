function bundle = validate_ts_bundle(bundle)
%VALIDATE_TS_BUNDLE  Top-level TS bundle validator (R2).
%   Validates bundle.ts (strategy via internal validate_ts_strategy, x0, y0,
%   topology, mapping, metadata) and bundle.sssa.model (via validate_sssa_model
%   when present). A TS strategy does NOT double as an SSSA model — they are
%   separately validated capabilities.
%
%   Bundle contract:
%     bundle.ts.strategy   - step strategy (validated by validate_ts_strategy)
%     bundle.ts.x0         - initial differential state
%     bundle.ts.y0         - initial shared network y
%     bundle.ts.topology   - struct(Ypre, Yfault, Ypost)
%     bundle.ts.mapping    - struct(bus_ids, gen_buses)
%     bundle.ts.metadata   - {device_id, device_type, bus_id, provenance, ...}
%     bundle.sssa.model    - SSSA model struct (validated by validate_sssa_model)
%     bundle.metadata      - dispatch provenance (no function handles)
%
%   Source: project R2 design.

if ~isstruct(bundle)
    error('validate_ts_bundle:badType', 'bundle must be a struct.');
end
if ~isfield(bundle,'ts')
    error('validate_ts_bundle:missingTs', 'bundle.ts is required.');
end
ts = bundle.ts;
ts_required = {'strategy','x0','y0','topology','mapping'};
for k = 1:numel(ts_required)
    if ~isfield(ts, ts_required{k})
        error('validate_ts_bundle:missingTsField', ...
            'bundle.ts missing required field "%s".', ts_required{k});
    end
end
% Validate the step strategy via the internal validator.
ts.strategy = stability.validate_ts_strategy(ts.strategy);
% x0/y0 finite.
if ~isnumeric(ts.x0) || ~all(isfinite(ts.x0(:)))
    error('validate_ts_bundle:badX0', 'bundle.ts.x0 must be finite numeric.');
end
if ~isnumeric(ts.y0) || ~all(isfinite(ts.y0(:)))
    error('validate_ts_bundle:badY0', 'bundle.ts.y0 must be finite numeric.');
end
% topology: Ypre/Yfault/Ypost present and square.
topo = ts.topology;
topo_fields = {'Ypre','Yfault','Ypost'};
for k = 1:numel(topo_fields)
    if ~isfield(topo, topo_fields{k})
        error('validate_ts_bundle:missingTopo', ...
            'bundle.ts.topology missing "%s".', topo_fields{k});
    end
    Y = topo.(topo_fields{k});
    if ~isempty(Y) && (~ismatrix(Y) || size(Y,1) ~= size(Y,2))
        error('validate_ts_bundle:badTopo', ...
            'topology.%s must be square (or empty).', topo_fields{k});
    end
end
% mapping: bus_ids and gen_buses present.
mp = ts.mapping;
if ~isfield(mp,'bus_ids') || ~isfield(mp,'gen_buses')
    error('validate_ts_bundle:missingMapping', ...
        'bundle.ts.mapping must have bus_ids and gen_buses.');
end
% SSSA model (optional but validated when present).
if isfield(bundle,'sssa') && isfield(bundle.sssa,'model') && ~isempty(bundle.sssa.model)
    bundle.sssa.model = stability.validate_sssa_model(bundle.sssa.model);
end
bundle.ts = ts;
end
