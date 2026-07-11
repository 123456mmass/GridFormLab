function ps = run_psat_case14(scenario)
%RUN_PSAT_CASE14  Run PSAT PF + TD for IEEE case14 (classical), FRESH, in THIS
%   session. Builds the PSAT case from the IN-HOUSE case14 (identical input
%   to the in-house solver) via rts24_to_psat_case, with default classical
%   machines (H=5, D=0, X'd=0.3) matching the in-house classical engine.
%   Reference only (PSAT is not a production dependency).
if nargin<1, scenario=struct(); end
sc = struct('fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1, ...
    'dt',0.01,'t_end',15.0);
fn = fieldnames(scenario); for k=1:numel(fn), sc.(fn{k})=scenario.(fn{k}); end

root = pf_init_paths;
c = cases.case_matpower6_case14();
if ~isfield(c,'machines') || isempty(c.machines)
    gbus = unique(c.mpc.gen(c.mpc.gen(:,8)~=0,1));
    units = struct('gen_id',num2cell(gbus),'bus',num2cell(gbus), ...
        'H',num2cell(5*ones(numel(gbus),1)),'D',num2cell(zeros(numel(gbus),1)), ...
        'Xdp',num2cell(0.3*ones(numel(gbus),1)), ...
        'is_sync_condenser',num2cell(false(numel(gbus),1)));
    c.machines = struct('units',units);
end
pc = rts24_to_psat_case(c,'Zf',sc.Zf,'fault_bus',sc.fault_bus, ...
    't_fault',sc.t_fault,'t_clear',sc.t_clear);

% --- PSAT live driver (mirrors run_psat_rts24) ---
psat_root = '';
for p = {'/home/birds/Documents/psat-2.1.11-mat/psat', ...
         'C:/Users/User/Downloads/psat-2.1.11-mat/psat'}
    if exist(p{1},'dir'), psat_root=p{1}; break; end
end
if ~exist(psat_root,'dir'), error('run_psat_case14:noPSAT','PSAT not found'); end
addpath(genpath(psat_root));
old = pwd; cleanup = onCleanup(@() cd(old)); %#ok<NASGU>
tests_dir = fullfile(psat_root,'tests');
casefile = fullfile(tests_dir,'case14_ours_psat.m');
write_complete_case(casefile, pc);
cd(psat_root);
global Settings Bus Varout Varname DAE clpsat Syn Fault Line PQ Shunt SW PV %#ok<NASGU>
command_line_psat = 1; %#ok<NASGU>
psat;
clpsat.mesg = 0; clpsat.readfile = 1; clpsat.pq2z = 1;
Settings.lftol = 1e-10; Settings.lfmit = 100;   % tight PF tol to match in-house 1e-10
runpsat('case14_ours_psat',tests_dir,'data');
runpsat('pf');
nb = Bus.n;
ps = struct();
ps.pf_angle_deg = DAE.y(1:nb)*180/pi;
ps.pf_vmag = DAE.y(nb+(1:nb));
ps.pf_conv = Settings.conv;
ps.bus_ids = Bus.con(:,1);
ps.syn_bus = Syn.con(:,1);
if ~ps.pf_conv, delete(casefile); error('run_psat_case14:pf','PSAT PF did not converge'); end
Settings.freq = pc.freq; Settings.tstep = sc.dt; Settings.tf = sc.t_end;
Settings.t0 = 0; Settings.method = 2; Settings.dynmit = 30; Settings.dyntol = 1e-6; Settings.fixt = 1;
runpsat('td');
uvars = Varname.uvars; if ~iscell(uvars), uvars = cellstr(uvars); end
dc = find(~cellfun('isempty',regexpi(uvars,'^delta_Syn_')));
oc = find(~cellfun('isempty',regexpi(uvars,'^omega_Syn_')));
pcc = find(~cellfun('isempty',regexpi(uvars,'^p_Syn_')));
vc = find(~cellfun('isempty',regexpi(uvars,'^v_Bus')));
ps.t = Varout.t(:); ps.delta = Varout.vars(:,dc); ps.omega = Varout.vars(:,oc);
ps.Pe_pu = Varout.vars(:,pcc); ps.Vbus = Varout.vars(:,vc);
ps.delta_bus = Syn.con(:,1); ps.pe_bus = Syn.con(:,1);
ps.vbus_ids = zeros(numel(vc),1);
for k=1:numel(vc)
    num = sscanf(uvars{vc(k)},'v_Bus%d'); if isempty(num), num=sscanf(uvars{vc(k)},'V_Bus%d'); end
    ps.vbus_ids(k)=num;
end
ps.td_points = numel(Varout.t); ps.td_tend = Varout.t(end); ps.td_error = Settings.error;
ps.Zf = pc.Zf; ps.fault_bus = pc.fault_bus; ps.t_fault = pc.t_fault; ps.t_clear = pc.t_clear;
delete(casefile);
fprintf('PSAT case14: PF conv=%d, TD pts=%d t_end=%.2f\n',ps.pf_conv,ps.td_points,ps.td_tend);
end

function write_complete_case(filepath, pc)
fid = fopen(filepath,'w'); if fid<0, error('writeFail'); end
fprintf(fid,'%% Auto-generated case14 PSAT case (self-contained, from in-house case14)\n');
write_mat(fid,'Bus.con',pc.Bus_con); write_mat(fid,'Line.con',pc.Line_con);
write_mat(fid,'Shunt.con',pc.Shunt_con); write_mat(fid,'SW.con',pc.SW_con);
write_mat(fid,'PV.con',pc.PV_con); write_mat(fid,'PQ.con',pc.PQ_con);
write_mat(fid,'Syn.con',pc.Syn_con); write_mat(fid,'Fault.con',pc.Fault_con);
write_names(fid,'Bus.names',pc.Bus_names); fclose(fid);
end
function write_mat(fid,name,M)
fmt=repmat('%.10g  ',1,size(M,2));
fprintf(fid,'%s = [ ...\n',name);
for r=1:size(M,1), fprintf(fid,'  '); fprintf(fid,[fmt,'\n'],M(r,:)); end
fprintf(fid,'];\n\n');
end
function write_names(fid,name,names)
fprintf(fid,'%s = { ...\n',name);
for r=1:numel(names)
  if r<numel(names), fprintf(fid,'  ''%s'';\n',names{r}); else, fprintf(fid,'  ''%s''\n',names{r}); end
end
fprintf(fid,'};\n\n');
end
