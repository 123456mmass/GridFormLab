function gates = evaluate_validation_gates(ran, contract, mapping, nonconv, timegrid, metrics, tol)
%EVALUATE_VALIDATION_GATES  Pure gate-evaluation logic for three-way validation.
%   No side effects, no tool execution — given the ran-flags, contract/mapping
%   results, non-converged count, time-grid flag, pairwise metrics and
%   predeclared tolerances, returns explicit gate statuses and the aggregate.
%   Missing PGAz / execution error / missing metric / non-converged step all
%   force the corresponding gate (and the aggregate) to FAIL — never a silent
%   optional pass.
%
%   ran:       struct(psat, pgaz)  logical — did each reference tool run?
%   contract:  struct(ybus_pgaz, ybus_psat)  logical — Ybus match?
%   mapping:   struct(psat, pgaz)  logical — gen-bus mapping correct?
%   nonconv:   scalar — in-house non-converged step count (must be 0)
%   timegrid:  logical — time grids equal?
%   metrics:   struct(.pf.(ps_ours|pg_ours|ps_pg).{dV,dAng},
%                      .ts.(ps_ours|pg_ours|ps_pg).{dCOI,domega,dPe,dVm})
%   tol:       struct(.pf.{dV,dAng}, .ts_conv.{...}, .ts_pgaz.{...})

gates = struct();
gates.contract_ybus_pgaz = contract.ybus_pgaz;
gates.contract_ybus_psat = contract.ybus_psat;
gates.gen_mapping_psat = mapping.psat;
gates.gen_mapping_pgaz = mapping.pgaz;
gates.psat_ran = ran.psat;
gates.pgaz_ran = ran.pgaz;
gates.ours_nonconv_zero = (nonconv == 0);
gates.time_grid_equal = timegrid;

% Per-pair metric gates (NaN/missing => FAIL). Converged pair (PSAT-Ours)
% uses the tight tolerance; PGAz-involving pairs use the looser (method-aware)
% tolerance for PGAz's fixed-3-iteration corrector.
gates.ps_metrics_ok   = ran.psat && pf_ok(metrics.pf.ps_ours, tol.pf) && ts_ok(metrics.ts.ps_ours, tol.ts_conv);
gates.pg_metrics_ok   = ran.pgaz && pf_ok(metrics.pf.pg_ours, tol.pf) && ts_ok(metrics.ts.pg_ours, tol.ts_pgaz);
gates.ps_pg_metrics_ok = ran.psat && ran.pgaz && pf_ok(metrics.pf.ps_pg, tol.pf) && ts_ok(metrics.ts.ps_pg, tol.ts_pgaz);

gates.all_gates_pass = all([ ...
    gates.contract_ybus_pgaz, gates.contract_ybus_psat, ...
    gates.gen_mapping_psat, gates.gen_mapping_pgaz, ...
    gates.psat_ran, gates.pgaz_ran, gates.ours_nonconv_zero, ...
    gates.time_grid_equal, gates.ps_metrics_ok, gates.pg_metrics_ok, ...
    gates.ps_pg_metrics_ok]);
end

function ok = ts_ok(m,T)
ok = isfield(m,'dCOI') && isfinite(m.dCOI) && m.dCOI<=T.dCOI && ...
     isfield(m,'domega') && isfinite(m.domega) && m.domega<=T.domega && ...
     isfield(m,'dPe') && isfinite(m.dPe) && m.dPe<=T.dPe && ...
     isfield(m,'dVm') && isfinite(m.dVm) && m.dVm<=T.dVm;
end
function ok = pf_ok(m,T)
ok = isfield(m,'dV') && isfinite(m.dV) && m.dV<=T.dV && ...
     isfield(m,'dAng') && isfinite(m.dAng) && m.dAng<=T.dAng;
end
