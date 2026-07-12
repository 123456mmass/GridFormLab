function adaptive_phase7_cv()
%ADAPTIVE_PHASE7_CV  Tracked aggregate fresh PSAT cross-validation runner.
%   Replaces the untracked /tmp/track_a_phase7_cv.m. Runs the FIXED canonical
%   PSAT baseline FRESH on Case14 and RTS-24 (fault bus 15) and prints the
%   primary PSAT comparison metrics for both. PSAT is a reference tool only
%   (never a production dependency).
%
%   This runner reports the FIXED canonical PSAT baseline. It is NOT adaptive
%   held-out evidence. Adaptive-vs-fixed diagnostics are produced by
%   adaptive_ts_compare_fixed (single shared helper) and aggregated by
%   adaptive_ts_diagnostic.
pf_init_paths;
o14 = run_three_way_validation('case_matpower6_case14');
o24 = run_three_way_validation('case_ieee_rts24_pgaz', struct('fault_bus',15));
fprintf('\n=== PHASE7 FRESH PSAT CV (fixed canonical) ===\n');
fprintf('Case14: psat=%s dCOI=%.4f deg dw=%.3e dPe=%.4f MW all_gates=%s\n', ...
    gate(o14.gates.psat_comparison), o14.ts.ps_ours.dCOI, ...
    o14.ts.ps_ours.domega, o14.ts.ps_ours.dPe, gate(o14.gates.all_gates_pass));
fprintf('RTS24:  psat=%s dCOI=%.4f deg dw=%.3e dPe=%.4f MW all_gates=%s\n', ...
    gate(o24.gates.psat_comparison), o24.ts.ps_ours.dCOI, ...
    o24.ts.ps_ours.domega, o24.ts.ps_ours.dPe, gate(o24.gates.all_gates_pass));
fprintf('================================================\n');
end

function s = gate(c)
if c, s = 'PASS'; else, s = 'FAIL'; end
end
