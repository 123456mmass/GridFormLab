function ps = run_psat_case14_ts_compare()
%RUN_PSAT_CASE14_TS_COMPARE Run PSAT case14 dynamic case (matpower2psat-generated)
% and export PF + TD results for PSAT/PGAz/Ours comparison.

psat_root = 'C:/Users/User/Downloads/psat-2.1.11-mat/psat';
addpath(genpath(psat_root));
old = pwd;
cleanup = onCleanup(@() cd(old));
cd(psat_root);

global Settings Path clpsat DAE Bus Varout Fault Syn Varname
command_line_psat = 1; %#ok<NASGU>
psat;
clpsat.mesg = 0;
clpsat.readfile = 1;
clpsat.pq2z = 1;

% Load matpower2psat-generated dynamic case + PF.
runpsat('d_case14_mp_psat_dyn_mdl',[Path.psat,'tests'],'data');
runpsat('pf');

nb = Bus.n;
ps = struct();
ps.pf_angle_deg = DAE.y(1:nb)*180/pi;
ps.pf_vmag       = DAE.y(nb+(1:nb));
ps.pf_conv       = Settings.conv;
ps.bus_ids       = Bus.con(:,1);

% TD settings matching PGAz/Ours scenario.
Settings.freq = 60;
Settings.fixt = 1;
Settings.tstep = 0.01;
Settings.tf = 15;
Settings.t0 = 0;
Settings.method = 2;   % trapezoidal (matches PGAz/Ours)
Settings.dynmit = 20;
Settings.dyntol = 1e-5;
runpsat('td');

% Extract state variables: delta_Syn_i and omega_Syn_i.
uvars = Varname.uvars;
ps.t = Varout.t;
ps.vars = Varout.vars;
ps.n = DAE.n;
ps.m = DAE.m;
ps.td_points = numel(Varout.t);
ps.td_tend = Varout.t(end);
ps.td_error = Settings.error;
ps.td_deltat = Settings.deltat;
ps.uvars = uvars;

% Locate delta_Syn and omega_Syn columns.
delta_cols = find(~cellfun('isempty',regexpi(uvars,'^delta_Syn_\d')));
omega_cols = find(~cellfun('isempty',regexpi(uvars,'^omega_Syn_\d')));
ps.delta = Varout.vars(:,delta_cols);   % rad
ps.omega = Varout.vars(:,omega_cols);   % pu
ps.delta_bus = Syn.con(:,1);

% Bus voltage magnitudes during TD (theta_Bus then V_Bus).
v_cols = nb + (1:nb);  % after angle block? locate explicitly
vmag_cols = find(~cellfun('isempty',regexpi(uvars,'^V_Bus_\d')));
if isempty(vmag_cols)
    vmag_cols = find(~cellfun('isempty',regexpi(uvars,'^v_Bus')));
end
ps.Vbus = Varout.vars(:,vmag_cols);

outdir = fullfile(old,'docs','source','figures','case14_ts');
if ~exist(outdir,'dir'), mkdir(outdir); end
% Strip PSAT objects before saving to avoid loadobj warnings.
ps_save = ps;
save(fullfile(outdir,'psat_case14_ts_raw.mat'),'ps_save');
fprintf('Saved PSAT raw TS: %s\n', fullfile(outdir,'psat_case14_ts_raw.mat'));
fprintf('PSAT PF conv=%d, TD points=%d t_end=%.3f error=%g\n',ps.pf_conv,ps.td_points,ps.td_tend,ps.td_error);
end
