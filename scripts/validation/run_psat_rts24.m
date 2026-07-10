function ps = run_psat_rts24(psat_case)
%RUN_PSAT_RTS24  Run PSAT PF + TS for RTS-24 using ONLY converted matrices.
%   Writes a COMPLETE, self-contained PSAT case file containing ALL
%   matrices from rts24_to_psat_case() (Bus.con, Line.con, Shunt.con,
%   SW.con, PV.con, PQ.con, Syn.con, Fault.con, Bus.names).
%   Does NOT call any external PSAT case file — all data is from the converter.
%
%   This ensures PSAT solves from the EXACT SAME network input as the
%   in-house solver — a true apples-to-apples cross-validation.
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

% --- Write the COMPLETE self-contained PSAT case file -----------------------
tests_dir = fullfile(psat_root, 'tests');
casefile = fullfile(tests_dir, 'rts24_ours_psat.m');
write_complete_case(casefile, psat_case);

cd(psat_root);
command_line_psat = 1; %#ok<NASGU>
psat;
clpsat.mesg = 0; clpsat.readfile = 1; clpsat.pq2z = 1;  % PQ -> constant Z

runpsat('rts24_ours_psat', tests_dir, 'data');

runpsat('pf');

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

% Pe generator bus mapping: PSAT variable names use machine INDEX
% (p_Syn_1, p_Syn_2, ...), NOT bus ID. Map through Syn.con(:,1).
ps.pe_bus = Syn.con(:,1);

ps.td_points = numel(Varout.t);
ps.td_tend   = Varout.t(end);
ps.td_error  = Settings.error;
ps.Zf = psat_case.Zf;
ps.fault_bus = psat_case.fault_bus;
ps.t_fault = psat_case.t_fault;
ps.t_clear = psat_case.t_clear;
ps.Sbase = psat_case.Sbase;

delete(casefile);
fprintf('PSAT RTS-24: PF conv=%d iter=%d, TD pts=%d t_end=%.2f err=%g\n', ...
    ps.pf_conv, ps.pf_iter, ps.td_points, ps.td_tend, ps.td_error);
end

% =========================================================================
function write_complete_case(filepath, pc)
% Write a COMPLETE self-contained PSAT case file with ALL matrices.
% All data comes from the converter struct — no external case file.
fid = fopen(filepath, 'w');
if fid < 0, error('run_psat_rts24:writeFail','Cannot write %s', filepath); end
fprintf(fid, '%% Auto-generated RTS-24 PSAT case (self-contained)\n');
fprintf(fid, '%% ALL matrices from rts24_to_psat_case(). No external case file.\n');
write_mat(fid, 'Bus.con',   pc.Bus_con);
write_mat(fid, 'Line.con',  pc.Line_con);
write_mat(fid, 'Shunt.con', pc.Shunt_con);
write_mat(fid, 'SW.con',    pc.SW_con);
write_mat(fid, 'PV.con',    pc.PV_con);
write_mat(fid, 'PQ.con',    pc.PQ_con);
write_mat(fid, 'Syn.con',   pc.Syn_con);
write_mat(fid, 'Fault.con', pc.Fault_con);
write_names(fid, 'Bus.names', pc.Bus_names);
fclose(fid);
end

function write_mat(fid, name, M)
    fmt = repmat('%.10g  ', 1, size(M,2));
    fprintf(fid, '%s = [ ...\n', name);
    for r = 1:size(M,1)
        fprintf(fid, '  ');
        fprintf(fid, [fmt, '\n'], M(r,:));
    end
    fprintf(fid, '];\n\n');
end

function write_names(fid, name, names)
    fprintf(fid, '%s = { ...\n', name);
    for r = 1:numel(names)
        if r < numel(names)
            fprintf(fid, '  ''%s'';\n', names{r});
        else
            fprintf(fid, '  ''%s''\n', names{r});
        end
    end
    fprintf(fid, '};\n\n');
end
