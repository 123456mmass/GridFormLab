function ps = run_psat_rts24(psat_case)
%RUN_PSAT_RTS24  Run PSAT PF + TS for RTS-24 cross-validation.
%   Uses the PSAT d_024_mdl network as base (same IEEE RTS-24 system),
%   then overlays the in-house Syn.con (classical, aggregated H/D/X'd)
%   and Fault.con (Zf = 0 + j0.1).  PSAT solves PF and TS independently.
%
%   Network data agreement: the d_024_mdl line impedances are rounded
%   versions of the PGAz source data.  The max input difference is
%   reported in ps.network_diff_max for transparency.
%
%   Load model: Settings.pq2z = 1 converts PQ loads to constant impedance
%   at the PF operating point, matching the in-house classical TS engine
%   which freezes load admittance at the pre-fault PF solution.
%
%   REFERENCE-ONLY runner -- never used by production solvers.

global Settings Bus Varout Varname DAE clpsat Syn Fault Line

psat_root = 'C:/Users/User/Downloads/psat-2.1.11-mat/psat';
if ~exist(psat_root,'dir')
    error('run_psat_rts24:noPSAT','PSAT not found at %s', psat_root);
end
addpath(genpath(psat_root));
old = pwd; cleanup = onCleanup(@() cd(old)); %#ok<NASGU>

% --- Write the combined PSAT case file -------------------------------------
% Uses d_024_mdl network (verified same IEEE RTS-24) + our Syn/Fault.
tests_dir = fullfile(psat_root, 'tests');
casefile = fullfile(tests_dir, 'rts24_ours_psat.m');
write_combined_case(casefile, psat_case);

cd(psat_root);
command_line_psat = 1; %#ok<NASGU>
psat;
clpsat.mesg = 0; clpsat.readfile = 1; clpsat.pq2z = 1;  % PQ -> constant Z

runpsat('rts24_ours_psat', tests_dir, 'data');

runpsat('pf');

% --- Report network input difference (after PF setup populates Line struct) ---
ps.network_diff_max = report_network_diff(Bus.con, Line.con, psat_case);

ps.pf_conv = Settings.conv;
ps.pf_iter = Settings.iter;
nb = Bus.n;
ps.bus_ids = Bus.con(:,1);
ps.pf_Vm     = DAE.y(nb+1:2*nb);
ps.pf_Va     = DAE.y(1:nb);          % rad
ps.pf_Va_deg = ps.pf_Va * 180/pi;

if ~ps.pf_conv
    warning('run_psat_rts24:pfNotConv','PSAT PF did not converge.');
    delete(casefile);
    return;
end

% --- Transient stability ---------------------------------------------------
Settings.freq = psat_case.freq;
Settings.tstep = 0.01;
Settings.tf    = 15;
Settings.t0    = 0;
Settings.method = 2;         % trapezoidal
Settings.dynmit = 30;
Settings.dyntol = 1e-6;
Settings.fixt = 1;

runpsat('td');

uvars = Varname.uvars;
if ~iscell(uvars), uvars = cellstr(uvars); end
ps.t    = Varout.t(:);
ps.vars = Varout.vars;

dc = find(~cellfun('isempty',regexpi(uvars,'^delta_Syn_')));
oc = find(~cellfun('isempty',regexpi(uvars,'^omega_Syn_')));
ps.delta = Varout.vars(:,dc);   % rad
ps.omega = Varout.vars(:,oc);   % pu
ps.syn_bus = Syn.con(:,1);

vc = find(~cellfun('isempty',regexpi(uvars,'^v_Bus')));
pcc = find(~cellfun('isempty',regexpi(uvars,'^p_Syn_')));
ps.Vbus  = Varout.vars(:,vc);
ps.Pe_pu = Varout.vars(:,pcc);

% Voltage bus mapping from names
v_names = uvars(vc);
ps.vbus_ids = zeros(numel(vc),1);
for k=1:numel(vc)
    num = sscanf(v_names{k}, 'v_Bus%d');
    if isempty(num), num = sscanf(v_names{k}, 'V_Bus%d'); end
    ps.vbus_ids(k) = num;
end

ps.td_points = numel(Varout.t);
ps.td_tend   = Varout.t(end);
ps.td_error  = Settings.error;
ps.Zf = psat_case.Zf;
ps.fault_bus = psat_case.fault_bus;
ps.t_fault = psat_case.t_fault;
ps.t_clear = psat_case.t_clear;

delete(casefile);
fprintf('PSAT RTS-24: PF conv=%d iter=%d, TD pts=%d t_end=%.2f err=%g\n', ...
    ps.pf_conv, ps.pf_iter, ps.td_points, ps.td_tend, ps.td_error);
end

% =========================================================================
function write_combined_case(filepath, pc)
% Write a PSAT case file that extends d_024_mdl with our Syn.con and Fault.con.
fid = fopen(filepath, 'w');
if fid < 0, error('run_psat_rts24:writeFail','Cannot write %s', filepath); end
fprintf(fid, '%% Auto-generated RTS-24 PSAT case (from in-house case_data)\n');
fprintf(fid, '%% Network = d_024_mdl (same IEEE RTS-24); Syn/Fault from case_data\n');
fprintf(fid, 'd_024_mdl;\n');
fprintf(fid, 'clear Supply Demand;\n');
write_mat(fid, 'Syn.con',   pc.Syn_con);
write_mat(fid, 'Fault.con', pc.Fault_con);
fclose(fid);
end

function write_mat(fid, name, M)
fprintf(fid, '%s = [ ...\n', name);
for r = 1:size(M,1)
    fprintf(fid, '  ');
    for c = 1:size(M,2)
        fprintf(fid, '%.10g  ', M(r,c));
    end
    if r < size(M,1), fprintf(fid, ';\n'); else, fprintf(fid, '\n'); end
end
fprintf(fid, '];\n');
end

% =========================================================================
function diff_max = report_network_diff(bus_con, line_con, pc)
% Report max input difference between PSAT d_024 network and our case_data.
% Line R/X/B differences come from rounding in the d_024_mdl file.
bd = pc.Bus_con_ref;  % our bus_data reference (set by caller if available)
if ~isfield(pc, 'Line_con_ref')
    diff_max = struct('max_R_pct', NaN, 'max_X_pct', NaN, 'max_B_pct', NaN);
    return;
end
% Compare line impedances
our_lines = pc.Line_con_ref;  % [from to R X B_half tap phase]
psat_R = line_con(:,8);
psat_X = line_con(:,9);
psat_B = line_con(:,10);  % total
our_R = our_lines(:,3);
our_X = our_lines(:,4);
our_B = 2*our_lines(:,5);  % total
% Match by from-to bus pair
n = size(our_lines,1);
dR = zeros(n,1); dX = zeros(n,1); dB = zeros(n,1);
for k = 1:n
    f = our_lines(k,1); t = our_lines(k,2);
    idx = find(line_con(:,1)==f & line_con(:,2)==t, 1);
    if isempty(idx), idx = find(line_con(:,1)==t & line_con(:,2)==f, 1); end
    if ~isempty(idx)
        dR(k) = abs(psat_R(idx) - our_R(k)) / max(abs(our_R(k)), 1e-10);
        dX(k) = abs(psat_X(idx) - our_X(k)) / max(abs(our_X(k)), 1e-10);
        dB(k) = abs(psat_B(idx) - our_B(k)) / max(abs(our_B(k)), 1e-10);
    end
end
diff_max = struct( ...
    'max_R_pct', 100*max(dR), ...
    'max_X_pct', 100*max(dX), ...
    'max_B_pct', 100*max(dB));
fprintf('Network input diff (d_024 vs case_data): max R=%.3f%%, X=%.3f%%, B=%.3f%%\n', ...
    diff_max.max_R_pct, diff_max.max_X_pct, diff_max.max_B_pct);
end
