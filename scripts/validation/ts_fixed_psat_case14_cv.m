function ts_fixed_psat_case14_cv()
%TS_FIXED_PSAT_CASE14_CV  Tracked Case14 FIXED canonical PSAT cross-validation.
%   Replaces the untracked /tmp/track_a_case14_cv.m. Renamed for terminology
%   honesty: this runner executes the FIXED canonical PSAT baseline, not an
%   adaptive comparison. Calls run_three_way_validation FRESH (no saved
%   trajectories) on Case14 and prints the primary PSAT comparison metrics.
%   PSAT is a reference tool only (never a production dependency).
%
%   This is the FIXED canonical PSAT baseline (the production engine runs
%   fixed-step by default after the honesty closure). It is NOT adaptive
%   held-out evidence; adaptive-vs-fixed diagnostics are produced by
%   adaptive_ts_compare_fixed and adaptive_ts_diagnostic.
pf_init_paths;
o = run_three_way_validation('case_matpower6_case14');
g = o.gates;
fprintf('\n=== CASE14 FRESH PSAT CV (fixed canonical) ===\n');
fprintf('psat_execution=%s td=%g\n', gate(g.psat_execution), o.psat.td_points);
fprintf('ours_convergence=%s nonconv=%d\n', gate(g.ours_convergence), o.ours_nonconv);
fprintf('psat_comparison(primary)=%s\n', gate(g.psat_comparison));
fprintf('all_gates_pass=%s\n', gate(g.all_gates_pass));
fprintf('PF dV=%.3e dAng=%.3e deg\n', o.pf.ps_ours.dV, o.pf.ps_ours.dAng);
fprintf('TS dCOI=%.4f deg dw=%.3e dPe=%.4f MW dVm=%.3e\n', ...
    o.ts.ps_ours.dCOI, o.ts.ps_ours.domega, o.ts.ps_ours.dPe, o.ts.ps_ours.dVm);
fprintf('================================================\n');
end

function s = gate(c)
if c, s = 'PASS'; else, s = 'FAIL'; end
end
