function md = ts_method_metadata(integrator, integrator_source, dispatch)
%TS_METHOD_METADATA  Phase-2 TS method provenance metadata (additive).
%   MD = TS_METHOD_METADATA(INTEGRATOR, INTEGRATOR_SOURCE, DISPATCH) returns a
%   struct recording the executed integrator, implementation provenance
%   (method_source), selector provenance (selection_source), capability, and
%   RK4 diagnostic flag. Shared by every TS route (classical/EMF6/Padiyar/
%   bundle) so metadata is uniform.
%
%   method_source (implementation provenance string) and selection_source
%   (default/explicit_integrator/explicit_method_alias selector provenance)
%   are DISTINCT. RK4 is diagnostic-only (bounded stability region, not
%   A-stable); it is never the production default.
%
%   Fields (all additive; field-existence tests, not exact-struct equality):
%     method_requested, method_executed, dispatch_requested, method_source,
%     selection_source, capability, runtime_diagnostic, fallback_used, dispatch.
switch integrator
    case 'trapezoidal'
        method_source = 'in-house trapezoidal (ts_step_kernel)';
        capability = 'production'; runtime_diag = false;
    case 'backward_euler'
        method_source = 'in-house backward_euler (NAODE Sec 4.1 eq 4.9, L-stable)';
        capability = 'production'; runtime_diag = false;
    case 'rk4'
        method_source = 'in-house rk4 (Suli & Mayers 2003 p.352)';
        capability = 'diagnostic'; runtime_diag = true;
    otherwise
        method_source = integrator; capability = 'production'; runtime_diag = false;
end
md = struct( ...
    'method_requested', integrator, ...
    'method_executed', integrator, ...
    'dispatch_requested', integrator, ...
    'method_source', method_source, ...
    'selection_source', integrator_source, ...
    'capability', capability, ...
    'runtime_diagnostic', runtime_diag, ...
    'fallback_used', false, ...
    'dispatch', dispatch);
end
