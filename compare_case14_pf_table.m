function T = compare_case14_pf_table()
%COMPARE_CASE14_PF_TABLE Build comparison table: PGAz report vs in-house PF.

pf_init_paths;
c = cases.case_matpower6_case14();
r = pfsolver.powerflow_newton_raphson(c, struct('verbose', false, 'plot_results', false, ...
    'max_iter', 50, 'tolerance', 1e-10, 'enforce_q_limits', false));

pgaz.V = [1.060;1.045;1.010;1.018;1.020;1.070;1.062;1.090;1.056;1.051;1.057;1.055;1.050;1.036];
pgaz.A = [0.000;-4.983;-12.725;-10.313;-8.774;-14.221;-13.360;-13.360;-14.939;-15.097;-14.791;-15.076;-15.156;-16.034];
pgaz.Pg = [232.393;40.000;0.000;0.000;0.000;0.000;0.000;0.000;0.000;0.000;0.000;0.000;0.000;0.000];
pgaz.Qg = [-16.549;43.557;25.075;0;0;12.731;0;17.623;0;0;0;0;0;0];

bus = (1:14).';
T = table(bus, pgaz.V, r.bus_voltage, r.bus_voltage-pgaz.V, ...
    pgaz.A, r.bus_angle_deg, r.bus_angle_deg-pgaz.A, ...
    pgaz.Pg, r.P_generation*100, r.P_generation*100-pgaz.Pg, ...
    pgaz.Qg, r.Q_generation*100, r.Q_generation*100-pgaz.Qg, ...
    'VariableNames', {'Bus','PGAz_V','Ours_V','dV','PGAz_Ang_deg','Ours_Ang_deg','dAng_deg', ...
    'PGAz_Pg_MW','Ours_Pg_MW','dPg_MW','PGAz_Qg_Mvar','Ours_Qg_Mvar','dQg_Mvar'});

outdir = fullfile(pwd,'docs','source','figures','case14_ts');
if ~exist(outdir,'dir'), mkdir(outdir); end
writetable(T, fullfile(outdir,'case14_pf_compare_pgaz_ours.csv'));

fid = fopen(fullfile(outdir,'case14_pf_compare_pgaz_ours.md'),'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid,'# Case14 PF comparison: PGAz vs in-house\n\n');
fprintf(fid,'| Bus | PGAz V | Ours V | dV | PGAz angle | Ours angle | dAngle | PGAz Pg | Ours Pg | dPg | PGAz Qg | Ours Qg | dQg |\n');
fprintf(fid,'|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n');
for k=1:height(T)
    fprintf(fid,'| %d | %.3f | %.6f | %+ .2e | %.3f | %.6f | %+ .2e | %.3f | %.6f | %+ .2e | %.3f | %.6f | %+ .2e |\n', ...
        T.Bus(k), T.PGAz_V(k), T.Ours_V(k), T.dV(k), T.PGAz_Ang_deg(k), T.Ours_Ang_deg(k), T.dAng_deg(k), ...
        T.PGAz_Pg_MW(k), T.Ours_Pg_MW(k), T.dPg_MW(k), T.PGAz_Qg_Mvar(k), T.Ours_Qg_Mvar(k), T.dQg_Mvar(k));
end
fprintf(fid,'\n## Global summary\n\n');
fprintf(fid,'| Quantity | PGAz | Ours | Difference |\n|---|---:|---:|---:|\n');
fprintf(fid,'| Total Pg MW | %.3f | %.6f | %+ .3e |\n', 272.393, r.P_total_gen*100, r.P_total_gen*100-272.393);
fprintf(fid,'| Total Qg Mvar | %.3f | %.6f | %+ .3e |\n', 82.438, r.Q_total_gen*100, r.Q_total_gen*100-82.438);
fprintf(fid,'| Total Ploss MW | %.3f | %.6f | %+ .3e |\n', 13.393, r.P_loss_total*100, r.P_loss_total*100-13.393);
fprintf(fid,'| Total Qloss Mvar | %.3f | %.6f | %+ .3e |\n', 30.122, r.Q_loss_total*100, r.Q_loss_total*100-30.122);

fprintf('\nCase14 PF comparison saved:\n');
fprintf('  %s\n', fullfile(outdir,'case14_pf_compare_pgaz_ours.csv'));
fprintf('  %s\n', fullfile(outdir,'case14_pf_compare_pgaz_ours.md'));
fprintf('\nMax differences vs PGAz rounded report:\n');
fprintf('  max |dV|       = %.6g pu\n', max(abs(T.dV)));
fprintf('  max |dAngle|   = %.6g deg\n', max(abs(T.dAng_deg)));
fprintf('  max |dPg|      = %.6g MW\n', max(abs(T.dPg_MW)));
fprintf('  max |dQg|      = %.6g Mvar\n', max(abs(T.dQg_Mvar)));
end
