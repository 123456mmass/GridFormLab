function point = route_sg(scaled_case, scenario, opt)
%ROUTE_SG  Conventional SG case route adapter for the load sweep.
%   POINT = stability.load_sweep.route_sg(SCALED_CASE, SCENARIO, OPT)
%   delegates to stability.multicase_sssa for ONE operating point. This is a
%   thin adapter that normalizes the output to the common load-sweep point
%   schema. No edits to multicase_sssa.m / multimachine_ssa.m.
%
%   The REF bus injection balances PF mismatch (PF contract). Tm/Efd are
%   equilibrium initialization inputs, NOT a PF redispatch policy.

point = struct();
point.route = 'sg';
point.failure_stage = '';
point.failure_id = '';
point.failure_reason = '';

% --- PF diagnostics -------------------------------------------------------
% Project-owned Newton PF; composite_dae is NOT the PF solver, it consumes
% the PF result. The REF bus injection balances the network mismatch (PF
% contract); Tm/Efd initialize the SG dynamic equilibrium and must NOT be
% described as the PF load-balancing policy.
try
    pf = pfsolver.powerflow_newton_raphson(scaled_case, struct( ...
        'verbose', false, 'plot_results', false, 'max_iter', 50, ...
        'tolerance', 1e-10, 'enforce_q_limits', true));
catch err
    point.failure_stage = 'PF';
    point.failure_id = 'sssa_load_sweep:pf';
    point.failure_reason = err.message;
    point.pf = struct('converged', false, 'failure_reason', err.message);
    point.equilibrium = struct('converged', false, 'failure_reason', err.message);
    return;
end
pf_diag = struct();
pf_diag.converged = pf.converged;
pf_diag.iterations = option_value(pf,'iterations',NaN);
pf_diag.max_mismatch = option_value(pf,'max_mismatch',NaN);
if isfield(pf,'bus_voltage')
    pf_diag.voltage_min_pu = min(abs(pf.bus_voltage));
    pf_diag.voltage_max_pu = max(abs(pf.bus_voltage));
end
if isfield(pf,'P_total_load'), pf_diag.P_total_load_MW = pf.P_total_load; end
if isfield(pf,'Q_total_load'), pf_diag.Q_total_load_MVAr = pf.Q_total_load; end
if isfield(pf,'P_loss_total'), pf_diag.P_loss_MW = pf.P_loss_total; end
if isfield(pf,'Q_loss_total'), pf_diag.Q_loss_MVAr = pf.Q_loss_total; end
if isfield(pf,'q_limit_switching'), pf_diag.q_limit_switching = pf.q_limit_switching; end
point.pf = pf_diag;
if ~pf.converged
    point.failure_stage = 'PF';
    point.failure_id = 'sssa_load_sweep:pfNoConverge';
    point.failure_reason = option_value(pf,'failure_reason', ...
        'Newton PF did not converge');
    point.equilibrium = struct('converged',false,'failure_reason', ...
        point.failure_reason);
    return;
end

% --- SSSA via the existing multicase_sssa dispatcher ----------------------
try
    sssa_opt = struct();
    for k = {'model','excitation','fd_eps','verbose'}
        if isfield(opt, k{1}) && ~isempty(opt.(k{1}))
            sssa_opt.(k{1}) = opt.(k{1});
        end
    end
    sssa_raw = stability.multicase_sssa(scaled_case, sssa_opt);
catch err
    point.failure_stage = 'SSSA_LINEARIZATION';
    point.failure_id = 'sssa_load_sweep:sssa';
    point.failure_reason = err.message;
    point.sssa = [];
    point.equilibrium = struct('converged',false,'failure_reason',err.message);
    return;
end

% Normalize the SG SSSA struct so the load-sweep point schema is uniform
% across routes. multimachine_sssa returns Afull/Ared (not A); expose the
% full-state matrix under sssa.A so the mode matcher can run, and synthesize
% active_state_indices = 1:nx (the full state) so the matcher's active-state
% identity check is meaningful. Raw eigenvalue order is preserved.
sssa = sssa_raw;
if isfield(sssa_raw,'Afull') && ~isfield(sssa_raw,'A')
    sssa.A = sssa_raw.Afull;
end
if isfield(sssa_raw,'eigenvalues') && ~isempty(sssa_raw.eigenvalues)
    lam = sssa_raw.eigenvalues(:);
    sssa.eigenvalues = lam;
    if isfield(sssa,'A') && ~isempty(sssa.A)
        sssa.active_state_indices = (1:size(sssa.A,1)).';
    elseif ~isempty(lam)
        sssa.active_state_indices = (1:numel(lam)).';
    end
end
if isfield(sssa_raw,'state_names'), sssa.state_names = sssa_raw.state_names; end
point.sssa = sssa;

% --- EQUILIBRIUM record (SG) ----------------------------------------------
% SG SSSA does not run a coupled Newton equilibrium like the IEEE14 mixed
% route; the SSSA's x0 IS the equilibrium operating point built inside the
% SG SSSA model. Record the convergence/residual fields that exist. The PF
% converged gate above already enforces network solvability; stability of
% the small-signal model is the SSSA verdict, not an equilibrium verdict.
eq_diag = struct();
eq_diag.converged = true;
eq_diag.residual_norm = option_value(sssa_raw,'newton_residual',NaN);
if isfield(sssa,'A')
    eq_diag.active_state_indices = sssa.active_state_indices;
    eq_diag.physical_kcl_norm = NaN;
end
point.equilibrium = eq_diag;

% --- MODAL_REPORTING ------------------------------------------------------
% SG route does not call stability.modal_analysis here (multimachine_ssa
% already returns mode_shapes/reduced_mode_shapes). The load-sweep mode
% matcher consumes sssa.eigenvalues / sssa.A / sssa.mode_shapes.
point.modal = struct();
end

function value = option_value(s, name, fallback)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = fallback;
end
end
