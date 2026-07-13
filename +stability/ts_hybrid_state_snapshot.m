function snapshot = ts_hybrid_state_snapshot(hybrid_state)
%TS_HYBRID_STATE_SNAPSHOT  Immutable deep-copy snapshot for threading (Phase 2).
%   snapshot = ts_hybrid_state_snapshot(hybrid_state) returns a deep copy of
%   the hybrid_state struct, suitable for threading through event_context as
%   an IMMUTABLE snapshot. Devices/providers read the snapshot but never
%   mutate it; the TS driver remains the SOLE owner and mutator of the live
%   hybrid_state.
%
%   MATLAB struct assignment is copy-on-write, so a plain assignment already
%   produces a value copy. This function additionally validates that no
%   function handles are present in the struct (no hidden mutation paths
%   through captured closures), then returns the copy.
%
%   Source: project Phase 2 design (user correction 2). PROJECT_DERIVED.
%   In-house MATLAB struct semantics; no external dependency.

arguments
    hybrid_state struct
end

if isempty(hybrid_state)
    snapshot = struct();
    return;
end

assert_no_handles(hybrid_state, 'hybrid_state');
% Deep copy via struct() reconstruction of each field. MATLAB assignment is
% already copy-on-write, but explicit reconstruction guarantees independence
% for nested structs and avoids any shared-cell-edge aliasing.
snapshot = deep_copy_struct(hybrid_state);
end

% =========================================================================
function s = deep_copy_struct(s)
if isstruct(s)
    if isstruct(s) && ~isempty(fieldnames(s))
        out = struct();
        fns = fieldnames(s);
        for i = 1:numel(fns)
            out.(fns{i}) = deep_copy_struct(s.(fns{i}));
        end
        s = out;
    end
elseif iscell(s)
    out = cell(size(s));
    for i = 1:numel(s)
        out{i} = deep_copy_struct(s{i});
    end
    s = out;
end
% Numeric/logical/char/string scalars: assignment is a value copy.
end

% =========================================================================
function assert_no_handles(s, name)
if isa(s, 'function_handle')
    error('ts_hybrid_state_snapshot:noHandles', ...
        ['Field "%s" contains a function_handle. hybrid_state must hold ' ...
         'METADATA ONLY (no handles) so devices/providers cannot mutate ' ...
         'mode state through captured closures.'], name);
end
if isstruct(s)
    fns = fieldnames(s);
    for i = 1:numel(fns)
        assert_no_handles(s.(fns{i}), [name '.' fns{i}]);
    end
elseif iscell(s)
    for i = 1:numel(s)
        assert_no_handles(s{i}, sprintf('%s{%d}', name, i));
    end
end
end
