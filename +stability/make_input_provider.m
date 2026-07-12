function provider = make_input_provider(kind, spec, schema)
%MAKE_INPUT_PROVIDER  Build a typed input provider (R1/B7).
%   P = MAKE_INPUT_PROVIDER('constant', U0) returns a constant provider.
%   P = MAKE_INPUT_PROVIDER('callback', FN) returns a callback provider
%   where FN = @(t, event_context) U is an EXOGENOUS input function.
%   P = MAKE_INPUT_PROVIDER(KIND, SPEC, SCHEMA) validates against an
%   explicit schema (B7).
%
%   B7 typed schema (construction-validated + no-mutation caller contract):
%   MATLAB structs are MUTABLE; this design does NOT claim enforced
%   immutability (that would require a private-property class, out of
%   scope). Instead: the schema is CONSTRUCTION-VALIDATED, every
%   evaluation is re-validated against the frozen schema, and purity/
%   no-mutation is a CALLER CONTRACT documented here.
%
%   Schema fields (optional; auto-derived from U0 for 'constant'):
%     .class     - 'numeric' | 'logical' | 'struct'
%     .shape     - size vector, or 'scalar'
%     .fields     - cell of required field names (for struct), order-
%                   independent
%     .real_only - true to require real values (default false)
%   When schema is omitted, it is derived from U0 (constant) or defaulted
%   to numeric+finite (callback).
%
%   Binding constraints (R1):
%     - The callback is EXOGENOUS: fn(t, event_context). State-dependent
%       fn(t,x,y,...) is NOT supported.
%     - event_context is the immutable left/right topology+event struct.
%     - Caller no-mutation contract (documented, not enforced): the caller
%       must NOT mutate the provider struct or the returned u between
%       evaluations; side-effect-free, deterministic output, no mutable
%       captured state.
%     - When the provider is ABSENT (strategy.provider = []), the kernel
%       takes the exact legacy path (no u argument).
%
%   Source: project R1/B7 design (docs/project/plans/ibr_interface_foundation.md).
%   Exogenous input convention: standard ODE theory (Duhamel).

switch lower(kind)
case 'constant'
    if nargin < 2, spec = []; end
    if nargin < 3 || isempty(schema)
        schema = derive_schema(spec);
    else
        schema = normalize_schema(schema);
    end
    % Validate u0 against the schema at construction (B7).
    validate_against_schema(spec, schema, 'constant', 0);
    provider = struct('kind','constant','u0',spec,'fn',[],'schema',schema);
case 'callback'
    if nargin < 2 || isempty(spec)
        error('make_input_provider:missingCallback', ...
            'callback provider requires a function handle fn(t,event_context).');
    end
    if ~isa(spec,'function_handle')
        error('make_input_provider:badCallback', ...
            'callback spec must be a function handle.');
    end
    if nargin < 3 || isempty(schema)
        % Default schema: numeric, finite, ANY shape (caller did not declare
        % a shape). Shape/fields validated per-eval only against class +
        % finiteness. This preserves pre-B7 behavior for callbacks that
        % return vectors of unspecified size.
        schema = struct('class','numeric','shape',[],'fields',{{}}, ...
            'real_only',false);
    else
        schema = normalize_schema(schema);
    end
    provider = struct('kind','callback','u0',[],'fn',spec,'schema',schema);
otherwise
    error('make_input_provider:badKind', ...
        'Unknown provider kind "%s" (use ''constant'' or ''callback'').', kind);
end
provider = struct(provider);   % ensure value struct
end

% =========================================================================
function s = derive_schema(u0)
% Auto-derive a schema from a constant u0.
if isempty(u0)
    s = struct('class','numeric','shape',[0 0],'fields',{{}},'real_only',true);
elseif isnumeric(u0)
    s = struct('class','numeric','shape',size(u0),'fields',{{}}, ...
        'real_only',~any(imag(u0(:)) ~= 0));
elseif islogical(u0)
    s = struct('class','logical','shape',size(u0),'fields',{{}},'real_only',true);
elseif isstruct(u0) && isscalar(u0)
    s = struct('class','struct','shape','scalar', ...
        'fields',fieldnames(u0),'real_only',false);
else
    error('make_input_provider:badU0Type', ...
        'constant u0 has unsupported class %s.', class(u0));
end
end

function s = normalize_schema(schema)
% Validate/normalize a caller-supplied schema.
req = {'class','shape','fields','real_only'};
for k = 1:numel(req)
    if ~isfield(schema, req{k})
        error('make_input_provider:badSchema', ...
            'schema missing required field "%s".', req{k});
    end
end
s = schema;
if ~ismatrix(s.shape) && ~ischar(s.shape) && ~isstring(s.shape)
    error('make_input_provider:badSchema', 'schema.shape must be a vector or ''scalar''.');
end
end

function validate_against_schema(u, schema, kind_str, t)
% Validate u against the frozen schema. Used at construction (constant)
% and per-evaluation (callback). Stable error IDs eval_input_provider:schema*.
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
