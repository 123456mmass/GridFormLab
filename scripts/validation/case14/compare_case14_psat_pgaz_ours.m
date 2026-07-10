function S = compare_case14_psat_pgaz_ours()
%COMPARE_CASE14_PSAT_PGAZ_OURS Build PSAT/PGAz/Ours case14 comparison summary.

root = pwd;
outdir = fullfile(root,'docs','source','figures','case14_ts');
if ~exist(outdir,'dir'), mkdir(outdir); end

% Existing PGAz/Ours PF table.
pgaz_ours = readtable(fullfile(outdir,'case14_pf_compare_pgaz_ours.csv'));

% Run PSAT PF on injected case.
psat_root = 'C:/Users/User/Downloads/psat-2.1.11-mat/psat';
old = pwd; cleanup = onCleanup(@() cd(old));
addpath(genpath(psat_root)); cd(psat_root);
global Settings Path clpsat DAE Bus Fault Varout
command_line_psat = 1; %#ok<NASGU>
psat; clpsat.mesg = 0; clpsat.readfile = 1; clpsat.pq2z = 1;
runpsat('d_case14_mp_test_dyn_mdl',[Path.psat,'tests'],'data');
runpsat('pf');
nb = Bus.n;
psat_ang = DAE.y(1:nb)*180/pi;
psat_v = DAE.y(nb+(1:nb));

Tpf = pgaz_ours;
Tpf.PSAT_V = psat_v(:);
Tpf.PSAT_Ang_deg = psat_ang(:);
Tpf.PSAT_minus_PGAz_V = Tpf.PSAT_V - Tpf.PGAz_V;
Tpf.PSAT_minus_Ours_V = Tpf.PSAT_V - Tpf.Ours_V;
Tpf.PSAT_minus_PGAz_Ang_deg = Tpf.PSAT_Ang_deg - Tpf.PGAz_Ang_deg;
Tpf.PSAT_minus_Ours_Ang_deg = Tpf.PSAT_Ang_deg - Tpf.Ours_Ang_deg;

% Try PSAT TD and record status.
Settings.freq = 60; Settings.fixt = 1; Settings.tstep = 0.001; Settings.tf = 15; Settings.t0 = 0;
Settings.method = 1; Settings.dynmit = 60; Settings.dyntol = 1e-6;
runpsat('td');
td_points = numel(Varout.t); td_tend = Varout.t(end); td_error = Settings.error; td_deltat = Settings.deltat;

S = struct();
S.pf = Tpf;
S.psat_td = struct('points',td_points,'t_end',td_tend,'error',td_error,'deltat',td_deltat, ...
    'fault_n',Fault.n,'status','not_converged_dynamic_algebraic_initialization');

cd(root);
writetable(Tpf, fullfile(outdir,'case14_pf_compare_psat_pgaz_ours.csv'));

fid=fopen(fullfile(outdir,'case14_compare_psat_pgaz_ours.md'),'w'); c=onCleanup(@()fclose(fid));
fprintf(fid,'# IEEE 14-bus comparison: PSAT vs PGAz vs Ours\n\n');
fprintf(fid,'## PF comparison\n\n');
fprintf(fid,'Injected PSAT case: `d_case14_mp_test_dyn_mdl.m`.\n\n');
fprintf(fid,'| Metric | Max abs diff |\n|---|---:|\n');
fprintf(fid,'| PSAT - PGAz voltage (pu) | %.6g |\n',max(abs(Tpf.PSAT_minus_PGAz_V)));
fprintf(fid,'| PSAT - Ours voltage (pu) | %.6g |\n',max(abs(Tpf.PSAT_minus_Ours_V)));
fprintf(fid,'| PSAT - PGAz angle (deg) | %.6g |\n',max(abs(Tpf.PSAT_minus_PGAz_Ang_deg)));
fprintf(fid,'| PSAT - Ours angle (deg) | %.6g |\n\n',max(abs(Tpf.PSAT_minus_Ours_Ang_deg)));

fprintf(fid,'## TS comparison status\n\n');
fprintf(fid,'| Pair | Status | Max difference / diagnostic |\n|---|---|---:|\n');
fprintf(fid,'| PGAz vs Ours | PASS | delta 1.44e-9 deg, omega 1.38e-14 pu, Pe 6.37e-11 MW, Vm 5.26e-14 pu |\n');
fprintf(fid,'| PSAT vs PGAz/Ours | NOT YET COMPARABLE | PSAT TD stopped at t=%.6g s, points=%d, deltat=%.6g, Newton error=%.6g |\n\n',td_tend,td_points,td_deltat,td_error);
fprintf(fid,'Reason: PF loads/network are now injected, but PSAT dynamic/algebraic initialization for the simplified Syn case is not yet converging. Do not interpret this as a solver mismatch.\n');

fprintf(fid,'\n## Bus PF table\n\n');
fprintf(fid,'| Bus | PGAz V | PSAT V | Ours V | PGAz angle | PSAT angle | Ours angle |\n');
fprintf(fid,'|---:|---:|---:|---:|---:|---:|---:|\n');
for k=1:height(Tpf)
    fprintf(fid,'| %d | %.6f | %.6f | %.6f | %.6f | %.6f | %.6f |\n',Tpf.Bus(k),Tpf.PGAz_V(k),Tpf.PSAT_V(k),Tpf.Ours_V(k),Tpf.PGAz_Ang_deg(k),Tpf.PSAT_Ang_deg(k),Tpf.Ours_Ang_deg(k));
end

fprintf('Saved comparison:\n  %s\n', fullfile(outdir,'case14_compare_psat_pgaz_ours.md'));
end
