function u = eval_input_provider(provider, t, event_context)
%EVAL_INPUT_PROVIDER  Pure evaluation entry point for an input provider (R1/B7).
%   U = EVAL_INPUT_PROVIDER(PROVIDER, T, EVENT_CONTEXT) returns the input
%   vector/struct at time T under the immutable EVENT_CONTEXT. This is the
%   ONLY evaluation entry point. The function is PURE: it does not mutate
%   the provider and has no side effects.
%
%   B7 validation (on EVERY evaluation, against the frozen schema stored at
%   construction in make_input_provider):
%     - constant: returns provider.u0 exactly (already construction-validated).
%     - callback: calls provider.fn(t, event_context); validates the output
%       against provider.schema (class, shape, field set, real/complex policy,
%       finiteness). Rejects missing/extra fields, changing class/shape,
%       sparse/unsupported values, nonfinite. Stable error IDs
%       eval_input_provider:schema*.
%
%   No-mutation caller contract (B7): the caller must NOT mutate the provider
%   struct or the returned u between evaluations; purity is a documented
%   contract, not a runtime guarantee (MATLAB structs are mutable).
%
%   Rejected adaptive trials may append diagnostics but MUST NOT mutate the
%   provider; this function never writes to the provider.
%
%   Source: project R1/B7 design. Exogenous input convention.

if isempty(provider)
    u = [];   % absent provider => legacy path (caller must not reach here)
    return;
end

switch lower(provider.kind)
case 'constant'
    u = provider.u0;
case 'callback'
    u = provider.fn(t, event_context);
    % B7: validate against the frozen schema on EVERY evaluation.
    schema = provider.schema;
    if isempty(schema)
        % Pre-B7 provider without schema: legacy finiteness-only check.
        if isnumeric(u) && ~all(isfinite(u(:)))
            error('eval_input_provider:nonFinite', ...
                'Callback provider returned non-finite input at t=%.6g.', t);
        end
    else
        validate_against_schema(u, schema, 'callback', t);
    end
otherwise
    error('eval_input_provider:badKind', ...
        'Unknown provider kind "%s".', provider.kind);
end
end

% =========================================================================
function validate_against_schema(u, schema, kind_str, t)
% Re-validate u against the frozen schema on every evaluation (B7).
switch schema.class
case 'numeric'
    if ~isnumeric(u)
        error('eval_input_provider:schemaClass', ...
            '%s provider returned class %s, expected numeric (t=%.6g).', kind_str, class(u), t);
    end
    if isempty(schema.shape)
        % shape=[] means ANY shape (caller did not declare). Skip shape check.
    elseif ischar(schema.shape) || isstring(schema.shape)
        if ~strcmpi(schema.shape, 'scalar') || ~isscalar(u)
            error('eval_input_provider:schemaShape', ...
                '%s provider returned non-scalar numeric, expected scalar (t=%.6g).', kind_str, t);
        end
    else
        if ~isequal(size(u), schema.shape)
            error('eval_input_provider:schemaShape', ...
                '%s provider returned size [%s], expected [%s] (t=%.6g).', ...
                kind_str, num2str(size(u)), num2str(schema.shape), t);
        end
    end
    if ~all(isfinite(u(:)))
        error('eval_input_provider:nonFinite', ...
            '%s provider returned non-finite input (t=%.6g).', kind_str, t);
    end
    if schema.real_only && any(imag(u(:)) ~= 0)
        error('eval_input_provider:schemaComplex', ...
            '%s provider returned complex values, expected real (t=%.6g).', kind_str, t);
    end
case 'logical'
    if ~islogical(u)
        error('eval_input_provider:schemaClass', ...
            '%s provider returned class %s, expected logical (t=%.6g).', kind_str, class(u), t);
    end
case 'struct'
    if ~isstruct(u) || ~isscalar(u)
        error('eval_input_provider:schemaClass', ...
            '%s provider returned non-scalar struct, expected scalar struct (t=%.6g).', kind_str, t);
    end
    got = fieldnames(u);
    if numel(got) ~= numel(schema.fields) || ~all(ismember(schema.fields, got))
        error('eval_input_provider:schemaFields', ...
            '%s provider field set mismatch (expected {%s}, got {%s}) at t=%.6g.', ...
            kind_str, strjoin(schema.fields,','), strjoin(got,','), t);
    end
    for k = 1:numel(schema.fields)
        v = u.(schema.fields{k});
        if isnumeric(v) && ~all(isfinite(v(:)))
            error('eval_input_provider:nonFiniteField', ...
                '%s provider field ''%s'' is non-finite at t=%.6g.', kind_str, schema.fields{k}, t);
        end
    end
otherwise
    error('eval_input_provider:badSchemaClass', ...
        'schema.class "%s" not supported.', schema.class);
end
end
