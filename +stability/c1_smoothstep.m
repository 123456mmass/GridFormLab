function [alpha, alpha_dot, s] = c1_smoothstep(t, t0, T)
%C1_SMOOTHSTEP  C1 handback schedule with exact endpoint derivatives.
%   [ALPHA,ALPHA_DOT,S] = stability.c1_smoothstep(TIME,T0,DURATION)
%   evaluates the project-derived cubic smoothstep
%       s = clamp((TIME-T0)/DURATION,0,1)
%       alpha = 3*s^2 - 2*s^3.
%   ALPHA is monotone on [0,1], and ALPHA_DOT is exactly zero outside and at
%   both endpoints.  TIME may be a finite scalar or array; T0 and DURATION
%   are finite scalars and DURATION must be positive.  This function carries
%   no electrical equations and never resets a physical state; callers use
%   ALPHA only for declared reference/support commands before an atomic mode
%   transfer.

if ~isnumeric(t) || any(~isfinite(t(:)))
    error('stability:c1_smoothstep:badTime', ...
        'time must contain only finite numeric values.');
end
if ~isnumeric(t0) || ~isscalar(t0) || ~isfinite(t0)
    error('stability:c1_smoothstep:badStart', ...
        't0 must be one finite numeric scalar.');
end
if ~isnumeric(T) || ~isscalar(T) || ~isfinite(T) || T <= 0
    error('stability:c1_smoothstep:badDuration', ...
        'T must be one finite positive numeric scalar.');
end
s = (t-t0)./T;
s = min(1,max(0,s));
alpha = 3*s.^2-2*s.^3;
alpha_dot = (6*s-6*s.^2)./T;
% The clamp makes the derivative expression nonzero for out-of-window s
% unless it is explicitly masked.  Exact zero outside the transition is part
% of the C1 contract and is important at event-grid landings.
inside = (t>=t0) & (t<=t0+T);
alpha_dot(~inside) = 0;
end
