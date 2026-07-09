function summary = compare_psat_pgaz_ours_status()
%COMPARE_PSAT_PGAZ_OURS_STATUS Compare available PSAT/PGAz data with in-house cases.
% This is a status/check script; it does not call PSAT/PGAz solvers.

pf_init_paths;
summary = struct();
summary.psat_root = 'C:/Users/User/Downloads/psat-2.1.11-mat/psat';
summary.pgaz_root = 'C:/Users/User/Downloads/PGAz1.3 (2)/PGAz1.3';
summary.findings = {};

psat_case14 = dir(fullfile(summary.psat_root, '**', '*case14*'));
psat_d009 = dir(fullfile(summary.psat_root, '**', 'd_009*_mdl.m'));
pgaz_case14 = dir(fullfile(summary.pgaz_root, '**', 'case14_mp_test.m'));
summary.psat_case14_files = {psat_case14.name};
summary.psat_d009_files = {psat_d009.name};
summary.pgaz_case14_files = {pgaz_case14.name};

if isempty(psat_case14)
    summary.findings{end+1} = 'PSAT tree does not contain a case14 file; direct PSAT-vs-PGAz-vs-ours case14 comparison is not available yet.';
else
    summary.findings{end+1} = 'PSAT case14 candidate files found.';
end
if ~isempty(pgaz_case14)
    summary.findings{end+1} = 'PGAz case14_mp_test.m found and imported as cases.case_matpower6_case14().';
end
if ~isempty(psat_d009)
    summary.findings{end+1} = 'PSAT d_009 files found; this is WSCC/Sauer-Pai 3-machine 9-bus, not case14.';
end

% In-house PF result for imported PGAz/MATPOWER case14
c = cases.case_matpower6_case14();
r = pfsolver.powerflow_newton_raphson(c, struct('verbose', false, 'plot_results', false, ...
    'max_iter', 50, 'tolerance', 1e-10, 'enforce_q_limits', false));
summary.case14_ours = struct('converged', r.converged, 'iterations', r.iterations, ...
    'Pg_MW', r.P_total_gen*100, 'Qg_Mvar', r.Q_total_gen*100, ...
    'Ploss_MW', r.P_loss_total*100, 'Qloss_Mvar', r.Q_loss_total*100, ...
    'V', r.bus_voltage, 'angle_deg', r.bus_angle_deg);
summary.case14_pgaz_report = struct('Pg_MW',272.393,'Qg_Mvar',82.438, ...
    'Ploss_MW',13.393,'Qloss_Mvar',30.122);
summary.case14_pf_diff = struct( ...
    'Pg_MW', summary.case14_ours.Pg_MW - summary.case14_pgaz_report.Pg_MW, ...
    'Qg_Mvar', summary.case14_ours.Qg_Mvar - summary.case14_pgaz_report.Qg_Mvar, ...
    'Ploss_MW', summary.case14_ours.Ploss_MW - summary.case14_pgaz_report.Ploss_MW, ...
    'Qloss_Mvar', summary.case14_ours.Qloss_Mvar - summary.case14_pgaz_report.Qloss_Mvar);

fprintf('\n=== PSAT / PGAz / Ours comparison status ===\n');
for k=1:numel(summary.findings), fprintf('- %s\n', summary.findings{k}); end
fprintf('\ncase14 PF, ours vs PGAz report:\n');
fprintf('  Pg    ours %.3f  PGAz %.3f  diff %+g MW\n', summary.case14_ours.Pg_MW, summary.case14_pgaz_report.Pg_MW, summary.case14_pf_diff.Pg_MW);
fprintf('  Qg    ours %.3f  PGAz %.3f  diff %+g Mvar\n', summary.case14_ours.Qg_Mvar, summary.case14_pgaz_report.Qg_Mvar, summary.case14_pf_diff.Qg_Mvar);
fprintf('  Ploss ours %.3f  PGAz %.3f  diff %+g MW\n', summary.case14_ours.Ploss_MW, summary.case14_pgaz_report.Ploss_MW, summary.case14_pf_diff.Ploss_MW);
fprintf('  Qloss ours %.3f  PGAz %.3f  diff %+g Mvar\n', summary.case14_ours.Qloss_Mvar, summary.case14_pgaz_report.Qloss_Mvar, summary.case14_pf_diff.Qloss_Mvar);
fprintf('\nTS note: current in-house case14 TS is classical demo with default H/Xdp because MATPOWER/PGAz case14 PF file has no synchronous-machine dynamic parameters.\n');
fprintf('         It should not be expected to match PSAT/PGAz dynamic traces unless identical Gen/Syn/Exc data and load model are supplied.\n');
end
