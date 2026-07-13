function [integrator, method_source, resolved_opt] = resolve_ts_integrator(opt)
%RESOLVE_TS_INTEGRATOR  Resolve and validate a TS integrator name (CORE_ONLY, NOT_ROUTED).
%   [INTEGRATOR, METHOD_SOURCE, RESOLVED_OPT] = RESOLVE_TS_INTEGRATOR(OPT)
%   resolves the TS integrator name from OPT, with backward-compatible alias
%   resolution from the legacy OPT.method field.
%
%   P0 scope (package-only, per plan §2 ownership route):
%   This function is CORE_ONLY / NOT_ROUTED. It is called directly by tests;
%   ts_simulate.m is NOT modified to route through it. Production routing
%   readiness remains NOT_READY until the single-owner integration files are
%   separately resolved.
%
%   Resolution order (silent alias, no deprecation warning — run_ts.m and the
%   catalog set opt.method='trapezoidal'; breaking it would cascade):
%     1. if opt.integrator is present and non-empty -> use it (canonical field)
%     2. else if opt.method is present             -> integrator = lower(opt.method)
%     3. else                                       -> 'trapezoidal' (default)
%
%   P0 registers ONLY 'trapezoidal'. backward_euler/rk4 are added when their
%   phase lands (P4/P5) AFTER P3.5 passes. esdirk32 is NOT registered until
%   the ESDIRK source gate passes; requesting it returns
%   'ts_integrator_step:notYetApproved' from ts_integrator_step (not here —
%   here it is treated as unknown for P0).
%
%   Outputs:
%     INTEGRATOR     - canonical lower-case integrator name actually executed
%     METHOD_SOURCE  - 'default' / 'explicit_integrator' / 'explicit_method_alias'
%     RESOLVED_OPT   - input OPT with opt.method set to INTEGRATOR (so legacy
%                       result.method / plot_ts_result.m keep working) and
%                       opt.integrator set to INTEGRATOR.
%
%   Fail-closed: unknown integrator names ERROR before any step. No silent
%   fallback to 'trapezoidal' for an unrecognized explicit name.

DEFAULT_INTEGRATOR = 'trapezoidal';

if nargin < 1 || isempty(opt)
    opt = struct();
end

has_integrator = isstruct(opt) && isfield(opt, 'integrator') && ~isempty(opt.integrator);
has_method     = isstruct(opt) && isfield(opt, 'method')     && ~isempty(opt.method);

if has_integrator
    raw = opt.integrator;
    method_source = 'explicit_integrator';
elseif has_method
    raw = opt.method;
    method_source = 'explicit_method_alias';
else
    raw = DEFAULT_INTEGRATOR;
    method_source = 'default';
end

if ~ischar(raw) && ~isstring(raw)
    error('resolve_ts_integrator:badType', ...
        'integrator/method must be a string or char vector; got %s.', class(raw));
end

integrator = lower(strtrim(char(raw)));

switch integrator
    case 'trapezoidal'
        % canonical — allowed in P0
    case 'backward_euler'
        % Registered in P4 (after P3.5 coupled-DAE Jacobian contract gate passed).
        % Source verified: NAODE book Section 4.1 eq 4.9; L-stable (Section 8.4.1).
        % FIXED-STEP ONLY in P4: adaptive mode requires the method-specific
        % algebraic adaptive-error definition to be frozen (correction 6). The
        % caller (ts_integrator_step) returns the step handle; the stepper
        % selection is the caller-of-the-step's responsibility and must reject
        % adaptive+BE until frozen.
    case 'rk4'
        % Registered in P5 (after P3.5 passed). Source verified: Sulí & Mayers
        % 2003 p.352 (Butcher tableau via Wikipedia). capability='diagnostic'
        % (BOUNDED stability region, NOT A-stable). FIXED-STEP ONLY in P5
        % (adaptive requires the frozen method-specific algebraic adaptive-error
        % definition, correction 6).
    case 'esdirk32'
        % NOT registered until the ESDIRK source gate passes (sourced tableau
        % + DAE applicability verified). No executable step handle before then.
        error('resolve_ts_integrator:notYetApproved', ...
        ['Integrator ''esdirk32'' is not yet approved. It is registered only ' ...
         'after the ESDIRK source gate passes (exact sourced tableau + DAE ' ...
         'applicability verified). No production scaffold with ' ...
         'EQUATION_LOCATION_PENDING coefficients is created. No executable ' ...
         'step handle before the gate. No silent fallback.']);
    otherwise
        error('resolve_ts_integrator:unknownIntegrator', ...
            ['Unknown TS integrator "%s". P0 allows only ''trapezoidal''. ' ...
             'backward_euler/rk4 are added when their phase lands after P3.5 ' ...
             'passes; esdirk32 after its source gate. No silent fallback.'], ...
            integrator);
end

% Thread the resolved name back into opt so legacy consumers (result.method,
% plot_ts_result.m) keep working when this is eventually wired in.
opt.integrator = integrator;
opt.method = integrator;

resolved_opt = opt;
end
