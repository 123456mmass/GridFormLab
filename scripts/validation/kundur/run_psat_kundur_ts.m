function ps = run_psat_kundur_ts()
%RUN_PSAT_KUNDUR_TS Run PSAT d_kundur1_mdl (6th-order) PF+TD and export results.

psat_root = 'C:/Users/User/Downloads/psat-2.1.11-mat/psat';
addpath(genpath(psat_root));
old = pwd; cleanup = onCleanup(@() cd(old));
cd(psat_root);

global Settings Path clpsat DAE Bus Varout Fault Syn Varname
command_line_psat = 1; %#ok<NASGU>
psat; clpsat.mesg = 0; clpsat.readfile = 1; clpsat.pq2z = 1;

runpsat('d_kundur1_mdl',[Path.psat,'tests'],'data');
runpsat('pf');

nb = Bus.n;
ps = struct();
ps.pf_angle_deg = DAE.y(1:nb)*180/pi;
ps.pf_vmag = DAE.y(nb+(1:nb));
ps.pf_conv = Settings.conv;
ps.bus_ids = Bus.con(:,1);

% TD: PSAT d_kundur1_mdl fault = bus 8, 1.0-1.05 s, solid (built in file).
Settings.freq = 60; Settings.fixt = 1; Settings.tstep = 0.001; Settings.tf = 10;
Settings.t0 = 0; Settings.method = 2; Settings.dynmit = 30; Settings.dyntol = 1e-6;
runpsat('td');

uvars = Varname.uvars;
ps.t = Varout.t;
ps.vars = Varout.vars;
ps.n = DAE.n; ps.m = DAE.m;
ps.td_points = numel(Varout.t); ps.td_tend = Varout.t(end);
ps.td_error = Settings.error; ps.td_deltat = Settings.deltat;

dc = find(~cellfun('isempty',regexpi(uvars,'^delta_Syn_\d')));
oc = find(~cellfun('isempty',regexpi(uvars,'^omega_Syn_\d')));
ps.delta = Varout.vars(:,dc);   % rad
ps.omega = Varout.vars(:,oc);
ps.delta_bus = Syn.con(:,1);
ps.uvars = uvars;

outdir = fullfile(old,'docs','source','figures','kundur_ex126');
if ~exist(outdir,'dir'), mkdir(outdir); end
ps_save = ps;
save(fullfile(outdir,'psat_kundur6_ts_raw.mat'),'ps_save');
fprintf('PSAT Kundur6: PF conv=%d, TD points=%d t_end=%.3f err=%g\n', ...
    ps.pf_conv, ps.td_points, ps.td_tend, ps.td_error);
end
