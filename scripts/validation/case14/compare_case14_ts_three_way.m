function out = compare_case14_ts_three_way()
%COMPARE_CASE14_TS_THREE_WAY  Fresh three-way (Ours + PSAT + PGAz) validation
%   for IEEE case14. Delegates to run_three_way_validation (all three tools run
%   FRESH this session; no saved .mat). PSAT is the PRIMARY required
%   cross-validation reference; PGAz is a SECONDARY DIAGNOSTIC only (never a
%   required gate, never a basis for relaxing tolerance). PSAT/PGAz are
%   reference tools only (never production deps). Also writes a markdown
%   report + plot to docs/source/figures/case14_ts/.

root = pf_init_paths;
o = run_three_way_validation('case_matpower6_case14');
outdir = fullfile(root,'docs','source','figures','case14_ts');
if ~exist(outdir,'dir'), mkdir(outdir); end

fid = fopen(fullfile(outdir,'case14_ts_compare_three_way.md'),'w'); c = onCleanup(@()fclose(fid));
g = o.gates;
fprintf(fid,'# IEEE 14-bus TS three-way: PSAT vs PGAz vs Ours (FRESH)\n\n');
fprintf(fid,'Scenario: bus-4 3-ph fault, Zf=0+j0.1 pu, t_fault=1.0 s, t_clear=1.1 s, dt=0.01 s, t_end=15 s.\n');
fprintf(fid,'Model: classical (gens 1,2,3,6,8; H=5, D=0, x''d=0.3). All three tools run FRESH this session.\n');
fprintf(fid,'PSAT/PGAz are reference tools only. Generators mapped by bus ID; angles/speeds in COI frame.\n\n');
fprintf(fid,'## Contract (Ybus machine precision)\n\n| Pair | max|dY| | Gate |\n|---|---:|---:|\n');
fprintf(fid,'| Ours-PSAT | %.3e | %s |\n', o.contract.Ybus_max_dY_psat, gate(g.contract_ybus_psat));
fprintf(fid,'| Ours-PGAz | %.3e | %s |\n\n', o.contract.Ybus_max_dY_pgaz, gate(g.contract_ybus_pgaz));
fprintf(fid,'## Power flow (pairwise)\n\n| Pair | max|dV| (pu) | max|dAng| (deg) |\n|---|---:|---:|\n');
fprintf(fid,'| PSAT-Ours | %.6e | %.6e |\n', o.pf.ps_ours.dV, o.pf.ps_ours.dAng);
fprintf(fid,'| PGAz-Ours | %.6e | %.6e |\n', o.pf.pg_ours.dV, o.pf.pg_ours.dAng);
fprintf(fid,'| PSAT-PGAz | %.6e | %.6e |\n\n', o.pf.ps_pg.dV, o.pf.ps_pg.dAng);
fprintf(fid,'## Transient stability (COI frame, pairwise)\n\n| Pair | max|dCOI| (deg) | max|dw| (pu) | max|dPe| (MW) | max|dVm bus4| (pu) |\n|---|---:|---:|---:|---:|\n');
fprintf(fid,'| PSAT-Ours | %.6f | %.6e | %.6f | %.6e |\n', o.ts.ps_ours.dCOI, o.ts.ps_ours.domega, o.ts.ps_ours.dPe, o.ts.ps_ours.dVm);
fprintf(fid,'| PGAz-Ours | %.6f | %.6e | %.6f | %.6e |\n', o.ts.pg_ours.dCOI, o.ts.pg_ours.domega, o.ts.pg_ours.dPe, o.ts.pg_ours.dVm);
fprintf(fid,'| PSAT-PGAz | %.6f | %.6e | %.6f | %.6e |\n\n', o.ts.ps_pg.dCOI, o.ts.ps_pg.domega, o.ts.ps_pg.dPe, o.ts.ps_pg.dVm);
fprintf(fid,'## Gates\n\n| Gate | Status |\n|---|---:|\n');
fprintf(fid,'| contract_ybus_pgaz | %s |\n', gate(g.contract_ybus_pgaz));
fprintf(fid,'| contract_ybus_psat | %s |\n', gate(g.contract_ybus_psat));
fprintf(fid,'| gen_mapping_pgaz | %s |\n', gate(g.gen_mapping_pgaz));
fprintf(fid,'| psat_execution | %s (td=%g) |\n', gate(g.psat_execution), o.psat.td_points);
fprintf(fid,'| pgaz_execution | %s (nt=%g; fixed ci=%d, residual unavailable) |\n', ...
    gate(g.pgaz_execution), o.pgaz.nt, o.pgaz.corrector_iter);
fprintf(fid,'| ours_convergence | %s (nonconv=%d) |\n', gate(g.ours_convergence), o.ours_nonconv);
fprintf(fid,'| comparison_grid_valid | %s |\n', gate(g.comparison_grid_valid));
fprintf(fid,'| event_grid_valid | %s |\n', gate(g.event_grid_valid));
fprintf(fid,'| psat_comparison (primary) | %s |\n', gate(g.psat_comparison));
fprintf(fid,'| pgaz_comparison (diagnostic) | %s |\n', gate(g.pgaz_comparison));
fprintf(fid,'| ALL_GATES_PASS | %s |\n\n', gate(g.all_gates_pass));
fprintf(fid,'Primary PSAT tolerance: PF dV<1e-6, dAng<1e-4; TS dCOI<0.05 deg, dw<1e-4 pu, dPe<0.1 MW, dVm<1e-3 pu.\n');
fprintf(fid,'PGAz is reported as a secondary diagnostic. Completion is not described as residual convergence, and its larger trajectory difference is not hidden by a relaxed tolerance.\n');

out = o;
fprintf('\nReport: %s\n', fullfile(outdir,'case14_ts_compare_three_way.md'));
end

function s = gate(c), if c, s='PASS'; else, s='FAIL'; end, end
