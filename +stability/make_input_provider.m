function provider = make_input_provider(kind, spec)
%MAKE_INPUT_PROVIDER  Build an immutable, side-effect-free input provider (R1).
%   P = MAKE_INPUT_PROVIDER('constant', U0) returns a constant provider that
%   always returns U0.
%   P = MAKE_INPUT_PROVIDER('callback', FN) returns a callback provider where
%   FN = @(t, event_context) U is an EXOGENOUS input function (no state
%   dependence). The provider is evaluated via stability.eval_input_provider.
%
%   Binding constraints (R1):
%     - The provider is IMMUTABLE. make_input_provider does not capture mutable
%       counters, RNG state, or persistent state.
%     - The callback is EXOGENOUS: fn(t, event_context). State-dependent
%       fn(t,x,y,...) is NOT supported (would couple inputs to the trajectory).
%     - event_context is the immutable left/right topology+event struct.
%     - When the provider is ABSENT (strategy.provider = []), the kernel takes
%       the exact legacy path (no u argument). A present provider activates
%       the separate provider-aware path.
%
%   Source: project R1 design (docs/project/plans/ibr_interface_foundation.md).
%   Exogenous input convention: standard ODE theory (Duhamel).

switch lower(kind)
case 'constant'
    if nargin < 2, spec = []; end
    provider = struct('kind','constant','u0',spec,'fn',[]);
case 'callback'
    if nargin < 2 || isempty(spec)
        error('make_input_provider:missingCallback', ...
            'callback provider requires a function handle fn(t,event_context).');
    end
    if ~isa(spec,'function_handle')
        error('make_input_provider:badCallback', ...
            'callback spec must be a function handle.');
    end
    provider = struct('kind','callback','u0',[],'fn',spec);
otherwise
    error('make_input_provider:badKind', ...
        'Unknown provider kind "%s" (use ''constant'' or ''callback'').', kind);
end
% Mark immutable (struct is value-typed in MATLAB; this is documentation).
provider = struct(provider);   % ensure value struct
end
