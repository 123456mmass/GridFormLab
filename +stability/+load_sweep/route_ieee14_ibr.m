function point = route_ieee14_ibr(scaled_case, scenario, opt)
%ROUTE_IEEE14_IBR  IEEE14 mixed SG/GFM/GFL route adapter for the load sweep.
%   POINT = stability.load_sweep.route_ieee14_ibr(SCALED_CASE, SCENARIO, OPT)
%   delegates to the shared ibr_sssa_route helper (pure route, no equation
%   duplication). The GFM/GFL device map is fixed at scenario selection time
%   and used unchanged at every load point; the same map is applied at every
%   load level. Do not auto-switch GFM/GFL to make a load point converge.

point = stability.load_sweep.ibr_sssa_route(scaled_case, scenario, opt);
point.route = 'ieee14_ibr';

% Record PF diagnostics from the equilibrium's internal composite_dae PF.
% composite_dae is NOT the PF solver; it consumes the PF result. The REF bus
% injection balances PF mismatch (PF contract). Tm/Efd are equilibrium
% initialization inputs, NOT a PF redispatch policy.
if isfield(point,'equilibrium') && isstruct(point.equilibrium)
    eq = point.equilibrium;
    pf_diag = struct();
    pf_diag.converged = option_value(eq,'converged',false);
    pf_diag.iterations = option_value(eq,'iterations',NaN);
    pf_diag.residual_norm = option_value(eq,'residual_norm',NaN);
    pf_diag.physical_kcl_norm = option_value(eq,'physical_kcl_norm',NaN);
    pf_diag.rcond = option_value(eq,'rcond',NaN);
    pf_diag.f_active_inf = option_value(eq,'f_active_inf',NaN);
    if isfield(eq,'active_state_indices')
        pf_diag.active_state_indices = eq.active_state_indices;
    end
    if isfield(eq,'frozen_state_indices')
        pf_diag.frozen_state_indices = eq.frozen_state_indices;
    end
    if isfield(eq,'reference') && isstruct(eq.reference)
        pf_diag.reference = eq.reference;
    end
    point.pf = pf_diag;
end
end

function value = option_value(s, name, fallback)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = fallback;
end
end
