function u = eval_input_provider(provider, t, event_context)
%EVAL_INPUT_PROVIDER  Pure evaluation entry point for an input provider (R1).
%   U = EVAL_INPUT_PROVIDER(PROVIDER, T, EVENT_CONTEXT) returns the input
%   vector/struct at time T under the immutable EVENT_CONTEXT. This is the
%   ONLY evaluation entry point. The function is PURE: it does not mutate the
%   provider and has no side effects.
%
%   Validation (on every evaluation):
%     - constant: returns provider.u0 exactly.
%     - callback: calls provider.fn(t, event_context); validates that the
%       output is finite and (for vector outputs) has consistent type/size.
%
%   Rejected adaptive trials may append diagnostics but MUST NOT mutate the
%   provider; this function never writes to the provider.
%
%   Source: project R1 design. Exogenous input convention.

if isempty(provider)
    u = [];   % absent provider => legacy path (caller must not reach here)
    return;
end

switch lower(provider.kind)
case 'constant'
    u = provider.u0;
case 'callback'
    u = provider.fn(t, event_context);
    % Validate output: finite, and record type/size for consistency checks.
    if isnumeric(u)
        if ~all(isfinite(u(:)))
            error('eval_input_provider:nonFinite', ...
                'Callback provider returned non-finite input at t=%.6g.', t);
        end
    elseif isstruct(u)
        % Struct inputs: validate each numeric field is finite.
        fn = fieldnames(u);
        for k = 1:numel(fn)
            v = u.(fn{k});
            if isnumeric(v) && ~all(isfinite(v(:)))
                error('eval_input_provider:nonFiniteField', ...
                    'Callback provider field ''%s'' is non-finite at t=%.6g.', fn{k}, t);
            end
        end
    else
        error('eval_input_provider:badType', ...
            'Callback provider returned unsupported type %s at t=%.6g.', class(u), t);
    end
otherwise
    error('eval_input_provider:badKind', ...
        'Unknown provider kind "%s".', provider.kind);
end
end
