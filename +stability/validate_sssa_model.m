function model = validate_sssa_model(model)
%VALIDATE_SSSA_MODEL  SSSA capability validator (R2).
%   Validates the SSSA model struct consumed by stability.multimachine_ssa.
%   This is a SEPARATE capability from the TS step strategy (validate_ts_
%   strategy); one does NOT double as the other.
%
%   Required fields:
%     .x0, .y0   - equilibrium state/algebraic vectors
%     .f, .g     - function handles f(x,y), g(x,y)
%
%   Optional fields (validated for type if present):
%     .Jxx,.Jxy,.Jyx,.Jyy - precomputed Jacobian blocks
%     .fd_eps             - finite-difference step
%     .free_y             - algebraic variables to retain (legacy)
%     .vcon_vars,.vcon_rows,.vcon_eq - R4 voltage constraints (mutually
%                                      exclusive with nonempty free_y)
%     .reduction          - 'none' (default) or 'coi'
%     .state_names        - cell array
%
%   Source: project R2/R4 design; SSSA_CONTRACT.md.

required = {'x0','y0','f','g'};
for k = 1:numel(required)
    if ~isfield(model, required{k})
        error('validate_sssa_model:missingField', ...
            'SSSA model missing required field "%s".', required{k});
    end
end
if ~isa(model.f,'function_handle') || ~isa(model.g,'function_handle')
    error('validate_sssa_model:badHandle', 'f and g must be function handles.');
end
if ~isnumeric(model.x0) || ~all(isfinite(model.x0(:)))
    error('validate_sssa_model:badX0', 'x0 must be finite numeric.');
end
if ~isnumeric(model.y0) || ~all(isfinite(model.y0(:)))
    error('validate_sssa_model:badY0', 'y0 must be finite numeric.');
end
% R4: free_y and vcon are STRICTLY field-level mutually exclusive.
has_freey = isfield(model,'free_y') && ~isempty(model.free_y);
has_vcon  = isfield(model,'vcon_vars') || isfield(model,'vcon_rows') || isfield(model,'vcon_eq');
if has_freey && has_vcon
    error('validate_sssa_model:exclusiveOwnership', ...
        'free_y and vcon_* are strictly mutually exclusive.');
end
% If any vcon field present, require the COMPLETE vcon set.
if has_vcon
    vcon_fields = {'vcon_vars','vcon_rows','vcon_eq'};
    for k = 1:numel(vcon_fields)
        if ~isfield(model, vcon_fields{k})
            error('validate_sssa_model:partialVcon', ...
                'vcon requires the COMPLETE set: vcon_vars, vcon_rows, vcon_eq.');
        end
    end
end
model = model;
end
