function report = check_conversion_contract(case_name, scenario)
%CHECK_CONVERSION_CONTRACT  Verify Ours/PSAT/PGAz use identical inputs for a case.
%   Compares Ybus (Ours vs PGAz, Ours vs PSAT), bus/generator mapping, machine
%   data, totals, branch/transformer counts, fault representation, event grid,
%   timestep, horizon, and integration method. Reference tools only.
if nargin<2, scenario=struct(); end
sc = struct('fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1, ...
    'dt',0.01,'t_end',15.0);
fn = fieldnames(scenario); for k=1:numel(fn), sc.(fn{k})=scenario.(fn{k}); end
root = pf_init_paths;
c = cases.(case_name)();
if ~isfield(c,'machines') || isempty(c.machines)
    gbus = unique(c.mpc.gen(c.mpc.gen(:,8)~=0,1));
    units = struct('gen_id',num2cell(gbus),'bus',num2cell(gbus), ...
        'H',num2cell(5*ones(numel(gbus),1)),'D',num2cell(zeros(numel(gbus),1)), ...
        'Xdp',num2cell(0.3*ones(numel(gbus),1)), ...
        'is_sync_condenser',num2cell(false(numel(gbus),1)));
    c.machines = struct('units',units);
end
bd = c.bus_data; ld = c.line_data; nb = size(bd,1);

% --- Our Ybus (lines + bus shunts on diagonal) ---
Yours = zeros(nb,nb);
for i = 1:size(ld,1)
    fr=ld(i,1); to=ld(i,2); R=ld(i,3); X=ld(i,4); Bh=ld(i,5);
    tap=ld(i,6); if tap==0, tap=1; end; ph=ld(i,7);
    ys=1/(R+1i*X); t=tap*exp(1i*deg2rad(ph)); ysht=1i*Bh;
    Yours(fr,fr)=Yours(fr,fr)+(ys+ysht)/(t*conj(t));
    Yours(to,to)=Yours(to,to)+ys+ysht;
    Yours(fr,to)=Yours(fr,to)-ys/conj(t);
    Yours(to,fr)=Yours(to,fr)-ys/t;
end
for k=1:nb, Yours(k,k)=Yours(k,k)+bd(k,9)+1i*bd(k,10); end

% --- PGAz sys + Ybus ---
pgaz_root = '/home/birds/Documents/PGAz_V1.1.1';
addpath(pgaz_root);
sys = case_to_pgaz_sys(c);
[Ypgaz,~] = pgaz_ybus(sys); Ypgaz = full(Ypgaz);
% PGAz bus order = ABus row order; ensure ascending bus-id order.
% pgaz_ybus already includes AShunt (Gs/Bs divided by baseMVA -> pu), so do
% NOT add it again here.
[~,pord] = sort(sys.ABus(:,1));
Ypgaz = Ypgaz(pord,pord);

% --- PSAT case (via rts24_to_psat_case) + Ybus ---
pc = rts24_to_psat_case(c,'Zf',sc.Zf,'fault_bus',sc.fault_bus, ...
    't_fault',sc.t_fault,'t_clear',sc.t_clear);
psat_root = '/home/birds/Documents/psat-2.1.11-mat/psat';
f = fullfile(psat_root,'tests','contract_tmp.m'); write_case_file(f,pc);
old = pwd; cd(psat_root); %#ok<NASGU>
global Settings Bus DAE clpsat Line Shunt %#ok<NASGU>
command_line_psat=1; psat; clpsat.mesg=0; clpsat.readfile=1; clpsat.pq2z=1;
Settings.lftol=1e-12; Settings.lfmit=200;
runpsat('contract_tmp',fullfile(psat_root,'tests'),'data');
runpsat('pf');
bc = Bus.con; LY = Line.Y; sc_con = Shunt.con;
Ypsat = full(LY); [~,si]=sort(bc(:,1)); Ypsat=Ypsat(si,si);
if ~isempty(sc_con)
    for s=1:size(sc_con,1), b=find(bd(:,1)==sc_con(s,1),1); Ypsat(b,b)=Ypsat(b,b)+sc_con(s,5)+1i*sc_con(s,6); end
end
cd(old); delete(f);

% --- Compare ---
dY_pgaz = max(abs(Yours-Ypgaz),[],'all');
dY_psat = max(abs(Yours-Ypsat),[],'all');
gbus_ours = unique(c.mpc.gen(c.mpc.gen(:,8)~=0,1));
gbus_pgaz = sort(sys.Gen(:,1));
gbus_psat = sort(pc.Syn_con(:,1));
tot_load = sum(bd(:,7))*c.base_values.S_base_MVA;
tot_gen = sum(c.mpc.gen(c.mpc.gen(:,8)~=0,2));
nxfm_ours = sum(abs(ld(:,6)-1)>1e-6);

report = struct();
report.case = case_name;
report.Ybus_max_dY_pgaz = dY_pgaz;
report.Ybus_max_dY_psat = dY_psat;
report.bus_ids_match = isequal(bd(:,1).', sys.ABus(pord,1).');
report.gen_buses_ours = gbus_ours;
report.gen_buses_pgaz = gbus_pgaz;
report.gen_buses_psat = gbus_psat;
report.gen_mapping_match = isequal(gbus_ours(:),gbus_pgaz(:),gbus_psat(:));
report.H = sys.Gen(:,11); report.D = sys.Gen(:,12); report.Xdp = sys.Gen(:,16);
report.tot_load_MW = tot_load; report.tot_gen_MW = tot_gen;
report.nbranch = size(ld,1); report.ntransformer = nxfm_ours;
report.fault_bus = sc.fault_bus;
report.Zf = sc.Zf; report.t_fault = sc.t_fault; report.t_clear = sc.t_clear;
report.dt = sc.dt; report.t_end = sc.t_end;
report.integration = struct('ours','trapezoidal-adaptive','psat','trapezoidal-newton','pgaz','trapezoidal-fix3');
report.event_grid = [0 sc.t_fault sc.t_clear sc.t_end];

fprintf('=== Conversion contract: %s ===\n', case_name);
fprintf('  Ybus max|dY|  Ours-PGAz = %.6e   Ours-PSAT = %.6e\n', dY_pgaz, dY_psat);
fprintf('  bus IDs match: %d ; gen mapping (Ours/PGAz/PSAT) match: %d\n', report.bus_ids_match, report.gen_mapping_match);
fprintf('  gen buses: ours=[%s] pgaz=[%s] psat=[%s]\n', mat2str(gbus_ours.'), mat2str(gbus_pgaz.'), mat2str(gbus_psat.'));
fprintf('  H=%s D=%s Xdp=%s\n', mat2str(report.H.',3), mat2str(report.D.',2), mat2str(report.Xdp.',3));
fprintf('  tot load=%.4f MW  tot gen=%.4f MW  nbranch=%d nxfm=%d\n', tot_load, tot_gen, report.nbranch, report.ntransformer);
fprintf('  fault: bus=%d Zf=%.4f t=[%.2f,%.2f] dt=%.3f t_end=%.1f\n', sc.fault_bus, sc.Zf, sc.t_fault, sc.t_clear, sc.dt, sc.t_end);
fprintf('  integration: ours=%s psat=%s pgaz=%s\n', report.integration.ours, report.integration.psat, report.integration.pgaz);
fprintf('  GATE Ybus: PGAz %s  PSAT %s\n', ternary(dY_pgaz<1e-10,'PASS','FAIL'), ternary(dY_psat<1e-10,'PASS','FAIL'));
end

function s = ternary(c,a,b), if c, s=a; else, s=b; end, end

function write_case_file(f,p)
fid=fopen(f,'w'); if fid<0, error('open'); end
map={'Bus_con','Bus.con','Line_con','Line.con','Shunt_con','Shunt.con','SW_con','SW.con','PV_con','PV.con','PQ_con','PQ.con','Syn_con','Syn.con','Fault_con','Fault.con'};
for k=1:2:numel(map)
 M=p.(map{k}); fmt=repmat('%.10g ',1,size(M,2)); fprintf(fid,'%s=[...\n',map{k+1});
 for r=1:size(M,1), fprintf(fid,' '); fprintf(fid,[fmt '\n'],M(r,:)); end; fprintf(fid,'];\n');
end
n=p.Bus_names; fprintf(fid,'Bus.names={...\n');
for r=1:numel(n), if r<numel(n), fprintf(fid,'''%s'';\n',n{r}); else, fprintf(fid,'''%s''\n',n{r}); end; end
fprintf(fid,'};\n'); fclose(fid);
end
