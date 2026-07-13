function step_fn = ts_integrator_step(opt)
%TS_INTEGRATOR_STEP  Return a TS integrator step function handle (CORE_ONLY, NOT_ROUTED).
%   STEP_FN = TS_INTEGRATOR_STEP(OPT) resolves the integrator name and returns
%   a function handle to the single-step kernel. The handle has signature:
%       STEP = STEP_FN(STRATEGY, X, Y, H, Y_ADM, OPT)
%   matching the strategy-form entry of stability.ts_step_kernel.
%
%   P0 scope (package-only, per plan §2 ownership route):
%   This factory is CORE_ONLY / NOT_ROUTED. It is called directly by tests;
%   ts_simulate.m / ts_adaptive_driver.m are NOT modified to route through
%   it. Production routing readiness remains NOT_READY until the single-owner
%   integration files are separately resolved.
%
%   P0 registers ONLY 'trapezoidal' (returns @stability.ts_step_kernel). A
%   direct call through this factory with 'trapezoidal' is bit-identical
%   (AbsTol=0) to calling stability.ts_step_kernel directly.
%
%   backward_euler / rk4 are registered only when their phase lands (P4/P5)
%   AFTER the P3.5 coupled-DAE Jacobian contract gate passes. Before then,
%   requesting them ERRORS with 'ts_integrator_step:notYetApproved'.
%
%   esdirk32 is NOT registered until the ESDIRK source gate passes (exact
%   sourced tableau + DAE applicability verified). Requesting it returns
%   'ts_integrator_step:notYetApproved' with NO executable step handle. No
%   production scaffold file carrying EQUATION_LOCATION_PENDING coefficients
%   is created.
%
%   Fail-closed: unknown names ERROR. No silent fallback to trapezoidal.

[integrator, ~, ~] = stability.resolve_ts_integrator(opt);

switch integrator
    case 'trapezoidal'
        step_fn = @stability.ts_step_kernel;
    case 'backward_euler'
        % Registered in P4 (after P3.5 coupled-DAE Jacobian contract gate passed).
        % FIXED-STEP ONLY: adaptive BE requires the frozen method-specific
        % algebraic adaptive-error definition (correction 6). The factory returns
        % the step handle; callers that request stepper='adaptive' with
        % integrator='backward_euler' must fail closed (adaptiveNotFrozen) until
        % the definition is frozen. This factory does NOT enforce the stepper
        % gate (it has no opt.stepper context here); the stepper gate lives in
        % the eventual routing layer (NOT_ROUTED in P4).
        step_fn = @stability.ts_step_be;
    case 'rk4'
        % Registered in P5 (after P3.5 passed). Source: Sulí & Mayers 2003 p.352.
        % capability='diagnostic' (BOUNDED stability region, NOT A-stable).
        % FIXED-STEP ONLY in P5 (adaptive requires frozen algebraic adaptive-error
        % definition, correction 6).
        step_fn = @stability.ts_step_rk4;
    case 'esdirk32'
        % NOT registered until the ESDIRK source gate passes.
        error('ts_integrator_step:notYetApproved', ...
        ['Integrator ''esdirk32'' is not yet approved. It is registered only ' ...
         'after the ESDIRK source gate passes (exact sourced tableau + DAE ' ...
         'applicability verified). No executable step handle before the gate. ' ...
         'No production scaffold with EQUATION_LOCATION_PENDING coefficients. ' ...
         'No silent fallback.']);
    otherwise
        % resolve_ts_integrator already guards unknown names, but keep this
        % for defense-in-depth.
        error('ts_integrator_step:unknownIntegrator', ...
            'Unknown TS integrator "%s". No silent fallback.', integrator);
end
end
