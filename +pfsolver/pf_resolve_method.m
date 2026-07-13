function [method_name, method_source] = pf_resolve_method(opt)
%PF_RESOLVE_METHOD  Resolve and validate a PF method name (CORE_ONLY, NOT_ROUTED).
%   [METHOD_NAME, METHOD_SOURCE] = PF_RESOLVE_METHOD(OPT) reads OPT.pf_method
%   (default 'newton_raphson') and validates it against the allowed set.
%
%   P0 scope (package-only, per plan §2 ownership route):
%   This function is CORE_ONLY / NOT_ROUTED. It is called directly by tests;
%   solve_case.m is NOT modified to route through it. Production routing
%   readiness remains NOT_READY until the single-owner integration files are
%   separately resolved.
%
%   Allowed methods (P0 ships ONLY newton_raphson; fdpf_xb/fdpf_bx/bfs are
%   added when their phase lands AND their source gate passes):
%     'newton_raphson'  (canonical, bit-identical to direct call)
%
%   Outputs:
%     METHOD_NAME    - canonical lower-case method name actually executed
%     METHOD_SOURCE  - 'default' (field absent/empty) or 'explicit' (user-set)
%
%   Fail-closed: unknown method names ERROR before any solve.
%   No silent fallback to newton_raphson for an unrecognized explicit name.

DEFAULT_METHOD = 'newton_raphson';

if nargin < 1 || isempty(opt)
    opt = struct();
end

if isstruct(opt) && isfield(opt, 'pf_method') && ~isempty(opt.pf_method)
    raw = opt.pf_method;
    method_source = 'explicit';
else
    raw = DEFAULT_METHOD;
    method_source = 'default';
end

if ~ischar(raw) && ~isstring(raw)
    error('pf_resolve_method:badType', ...
        'pf_method must be a string or char vector; got %s.', class(raw));
end

method_name = lower(strtrim(char(raw)));

switch method_name
    case 'newton_raphson'
        % canonical — allowed (P0)
    case {'fdpf_xb', 'fdpf_bx'}
        % Registered in P1 (after source-gate verified: Stott-Alsac 1974 +
        % van Amerongen 1989). Both variants share the FDPF solver.
    case 'bfs'
        % Registered in P2 (after BFS source-gate verified: Shirmohammadi 1988).
        % Phase-1 radial minimal capability (PQ-only, unity tap, no shunt/charging).
    otherwise
        error('pf_resolve_method:unknownMethod', ...
            ['Unknown PF method "%s". Allowed: newton_raphson, fdpf_xb, ' ...
             'fdpf_bx. bfs is added when P2 lands. No silent fallback.'], method_name);
end
end
