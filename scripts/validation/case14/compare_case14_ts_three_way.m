function out = compare_case14_ts_three_way()
%COMPARE_CASE14_TS_THREE_WAY PSAT vs PGAz vs Ours for case14 TS.
% Compares rotor angles and speeds in the COI frame (inter-machine), plus
% fault-bus voltage. Absolute angles are not compared because each tool uses
% a different angle reference (PSAT fixes slack angle; PGAz/Ours float COI).

pf_init_paths;
outdir = fullfile(pwd,'docs','source','figures','case14_ts');
if ~exist(outdir,'dir'), mkdir(outdir); end

% Common time grid.
tg = (0:0.01:15).';

% --- PSAT ---
S = load(fullfile(outdir,'psat_case14_ts_raw.mat'));
ps = S.ps_save;
dps = rad2deg(interp1(ps.t, ps.delta, tg, 'linear'));  % PSAT stores delta in rad -> deg
wps = interp1(ps.t, ps.omega, tg, 'linear');
peps = 100*interp1(ps.t, ps.Pe_pu, tg, 'linear');
vps_all = interp1(ps.t, ps.Vbus, tg, 'linear');
gbus_ps = ps.delta_bus;
[~,ord] = sort(gbus_ps);
dps = dps(:,ord); wps = wps(:,ord); peps = peps(:,ord);
gbus_ps = gbus_ps(ord);
fi_ps = find(ps.bus_ids==4,1);
vps_fault = vps_all(:,fi_ps);

% --- Ours: production adaptive/event-aware engine ---
c_ours = cases.case_matpower6_case14();
opt = struct('t_end',15.0,'dt',0.01,'fault_bus',4,'t_fault',1.0,'t_clear',1.1, ...
    'Zf',1i*0.1,'method','trapezoidal','corrector_mode','adaptive', ...
    'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8, ...
    'max_corrector_iter',10,'corrector_failure','error', ...
    'pm_mode','balanced','model','classical','verbose',false);
res = stability.ts_simulate(c_ours,opt);
[~,oo] = sort(res.gen_buses);
d_ours = rad2deg(res.delta(:,oo)); w_ours = res.omega(:,oo);
pe_ours = res.Pe_MW(:,oo);
gbus_ours = res.gen_buses(oo);
if isfield(res,'bus_ids'), bus_ids_ours=res.bus_ids(:); else, bus_ids_ours=res.pf.external_bus_ids(:); end
fi_ours = find(bus_ids_ours==4,1);
v_ours_fault = res.Vbus(:,fi_ours);

% --- PGAz ---
pgaz_root = 'C:/Users/User/Downloads/PGAz1.3 (2)/PGAz1.3';
addpath(genpath(pgaz_root));
sys = build_pgaz_sys(fullfile(pgaz_root,'Data','case14_mp_test.m'));
optp = struct(); optp.t_end=15.0; optp.dt=0.01; optp.method='trapezoidal'; optp.corrector_iter=3;
optp.make_plots=false; optp.fault=struct('enable',true,'bus',4,'t_fault',1.0,'t_clear',1.1,'Rf',0.0,'Xf',0.1);
TS = pgaz_ts(sys,1e-10,50,optp);
[~,po] = sort(TS.gen_bus);
d_pg = interp1(TS.t, TS.delta_deg, tg, 'linear');
w_pg = interp1(TS.t, TS.omega, tg, 'linear');
pe_pg = interp1(TS.t, TS.Pe_pu*TS.baseMVA, tg, 'linear');
v_pg_all = interp1(TS.t, TS.Vm, tg, 'linear');
d_pg = d_pg(:,po); w_pg = w_pg(:,po); pe_pg = pe_pg(:,po);
gbus_pg = TS.gen_bus(po);
v_pg_fault = v_pg_all(:,4);

assert(isequal(gbus_ps(:),gbus_ours(:),gbus_pg(:)), ...
    'Generator bus mapping differs between PSAT, PGAz and Ours.');

% --- COI frame (equal H=5) ---
H = 5*ones(5,1);
coi_ps = sum(H'.*dps,2)/sum(H);   drel_ps = dps - coi_ps;   wrel_ps = wps - mean(wps,2);
coi_our = sum(H'.*d_ours,2)/sum(H); drel_our = d_ours - coi_our; wrel_our = w_ours - mean(w_ours,2);
coi_pg  = sum(H'.*d_pg,2)/sum(H);   drel_pg  = d_pg - coi_pg;    wrel_pg  = w_pg - mean(w_pg,2);

% --- Differences ---
d_ps_our = max(abs(drel_ps - drel_our),[],'all');
d_ps_pg  = max(abs(drel_ps - drel_pg),[],'all');
d_pg_our = max(abs(drel_pg - drel_our),[],'all');
w_ps_our = max(abs(wrel_ps - wrel_our),[],'all');
w_ps_pg  = max(abs(wrel_ps - wrel_pg),[],'all');
w_pg_our = max(abs(wrel_pg - wrel_our),[],'all');
pe_ps_our = max(abs(peps - pe_ours),[],'all');
pe_ps_pg  = max(abs(peps - pe_pg),[],'all');
pe_pg_our = max(abs(pe_pg - pe_ours),[],'all');
v_ps_our = max(abs(vps_fault - v_ours_fault),[],'all');
v_ps_pg  = max(abs(vps_fault - v_pg_fault),[],'all');
v_pg_our = max(abs(v_pg_fault - v_ours_fault),[],'all');

out = struct();
out.max = struct('delta_deg',[d_ps_our d_ps_pg d_pg_our], ...
    'omega_pu',[w_ps_our w_ps_pg w_pg_our], ...
    'Pe_MW',[pe_ps_our pe_ps_pg pe_pg_our], ...
    'Vm_pu',[v_ps_our v_ps_pg v_pg_our]);
out.gen_buses = gbus_ours;

% --- PF comparison ---
pf_ps_ang = ps.pf_angle_deg; pf_ps_v = ps.pf_vmag;
pf_our = res.pf;
pf_our_v = pf_our.bus_voltage; pf_our_ang = pf_our.bus_angle_deg;
pf_pg_v = TS.Vm(1,:).'; pf_pg_ang = TS.Va_deg(1,:).';
out.pf = struct( ...
    'max_dV_ps_ours',max(abs(pf_ps_v-pf_our_v)), ...
    'max_dAng_ps_ours',max(abs(pf_ps_ang-pf_our_ang)), ...
    'max_dV_ps_pg',max(abs(pf_ps_v-pf_pg_v)), ...
    'max_dAng_ps_pg',max(abs(pf_ps_ang-pf_pg_ang)), ...
    'max_dV_pg_ours',max(abs(pf_pg_v-pf_our_v)), ...
    'max_dAng_pg_ours',max(abs(pf_pg_ang-pf_our_ang)));

% --- Markdown report ---
fid = fopen(fullfile(outdir,'case14_ts_compare_three_way.md'),'w'); c = onCleanup(@()fclose(fid));
fprintf(fid,'# IEEE 14-bus TS comparison: PSAT vs PGAz vs Ours\n\n');
fprintf(fid,'Scenario: bus 4 three-phase fault, t_fault=1.0 s, t_clear=1.1 s, Zf=0+j0.1 pu, t_end=15 s, dt=0.01 s.\n');
fprintf(fid,'Model: classical (5 generators at buses 1,2,3,6,8; H=5, D=0, x''d=0.3).\n');
fprintf(fid,'Rotor angles/speeds compared in the COI frame (inter-machine) because each tool uses a different absolute angle reference (PSAT fixes the slack angle; PGAz/Ours float the COI).\n\n');
fprintf(fid,'## Power flow\n\n');
fprintf(fid,'| Pair | Max |dV| (pu) | Max |dAngle| (deg) |\n|---|---:|---:|\n');
fprintf(fid,'| PSAT vs Ours | %.6g | %.6g |\n',out.pf.max_dV_ps_ours,out.pf.max_dAng_ps_ours);
fprintf(fid,'| PSAT vs PGAz | %.6g | %.6g |\n',out.pf.max_dV_ps_pg,out.pf.max_dAng_ps_pg);
fprintf(fid,'| PGAz vs Ours | %.6g | %.6g |\n\n',out.pf.max_dV_pg_ours,out.pf.max_dAng_pg_ours);
fprintf(fid,'## Transient stability (COI frame)\n\n');
fprintf(fid,'| Pair | Max |delta_rel| (deg) | Max |omega_rel| (pu) | Max |Pe| (MW) | Max |Vm_bus4| (pu) |\n|---|---:|---:|---:|---:|\n');
fprintf(fid,'| PSAT vs Ours | %.6g | %.6g | %.6g | %.6g |\n',d_ps_our,w_ps_our,pe_ps_our,v_ps_our);
fprintf(fid,'| PSAT vs PGAz | %.6g | %.6g | %.6g | %.6g |\n',d_ps_pg,w_ps_pg,pe_ps_pg,v_ps_pg);
fprintf(fid,'| PGAz vs Ours | %.6g | %.6g | %.6g | %.6g |\n\n',d_pg_our,w_pg_our,pe_pg_our,v_pg_our);
fprintf(fid,'## Notes\n\n');
fprintf(fid,'- Ours uses the production adaptive/event-aware implicit trapezoidal corrector; PSAT uses its converged trapezoidal Newton iteration; PGAz uses three fixed predictor-corrector iterations.\n');
fprintf(fid,'- Rotor-angle trajectories are compared in the COI frame, while electrical power and fault-bus voltage retain their physical references.\n');
fprintf(fid,'- The scenario is angle-stable (inter-machine swings are bounded); the absolute COI drifts because no governor/AGC is modelled.\n');

% --- Plot ---
f = figure('Visible','off','Color','w','Position',[60 60 1350 820]);
tl = tiledlayout(f,2,2,'Padding','compact','TileSpacing','compact');
nexttile; plot(tg,drel_our,'-','LineWidth',1.3); hold on; plot(tg,drel_ps,'--','LineWidth',1.1);
grid on; xlabel('time (s)'); ylabel('COI-relative \delta (deg)');
title('Rotor angle (COI): Ours solid, PSAT dashed'); legend(arrayfun(@(b)sprintf('G@%d',b),gbus_ours,'uni',0),'Location','best');
nexttile; plot(tg,drel_pg,'-','LineWidth',1.3); hold on; plot(tg,drel_our,'--','LineWidth',1.1);
grid on; xlabel('time (s)'); ylabel('COI-relative \delta (deg)');
title('Rotor angle (COI): PGAz solid, Ours dashed'); legend(arrayfun(@(b)sprintf('G@%d',b),gbus_ours,'uni',0),'Location','best');
nexttile; plot(tg,wrel_our,'-','LineWidth',1.3); hold on; plot(tg,wrel_ps,'--','LineWidth',1.1);
grid on; xlabel('time (s)'); ylabel('COI-relative \omega (pu)'); title('Speed (COI): Ours solid, PSAT dashed');
nexttile; plot(tg,v_ours_fault,'-','LineWidth',1.4); hold on; plot(tg,vps_fault,'--','LineWidth',1.2); plot(tg,v_pg_fault,':','LineWidth',1.2);
grid on; xlabel('time (s)'); ylabel('|V| bus 4 (pu)'); title('Fault-bus voltage'); legend('Ours','PSAT','PGAz','Location','best');
sgtitle(tl,'Case14 TS three-way: PSAT vs PGAz vs Ours (COI frame)');
exportgraphics(f, fullfile(outdir,'case14_ts_compare_three_way.png'),'Resolution',200); close(f);

fprintf('Saved:\n  %s\n  %s\n', fullfile(outdir,'case14_ts_compare_three_way.md'), fullfile(outdir,'case14_ts_compare_three_way.png'));
fprintf('\n=== Three-way TS (COI frame) ===\n');
fprintf('PSAT vs Ours : delta %.6g deg, omega %.6g pu, Vm %.6g pu\n',d_ps_our,w_ps_our,v_ps_our);
fprintf('PSAT vs PGAz : delta %.6g deg, omega %.6g pu, Vm %.6g pu\n',d_ps_pg,w_ps_pg,v_ps_pg);
fprintf('PGAz vs Ours : delta %.6g deg, omega %.6g pu, Vm %.6g pu\n',d_pg_our,w_pg_our,v_pg_our);
fprintf('Pe max error : PSAT/Ours %.6g MW, PSAT/PGAz %.6g MW, PGAz/Ours %.6g MW\n', ...
    pe_ps_our,pe_ps_pg,pe_pg_our);
end

function sys = build_pgaz_sys(mfile)
S = run_sandbox(mfile);
sys = struct();
sys.ABus=S.ABus.con; sys.ALine=S.ALine.con; sys.Slack=S.Slack.con; sys.PV=S.PV.con; sys.PQ=S.PQ.con; sys.Gen=S.Gen.con;
if isfield(S,'AShunt'), sys.AShunt=S.AShunt.con; else, sys.AShunt=[]; end
sys.baseMVA=sys.Slack(1,2); sys.nbus=size(sys.ABus,1);
for k=1:size(sys.PV,1)
  bi=sys.PV(k,1); gr=find(sys.Gen(:,1)==bi); on=~isempty(gr)&&any(sys.Gen(gr,25)~=0);
  if on, sys.PV(k,14)=1; if sys.ABus(bi,2)~=1, sys.ABus(bi,2)=2; end
  else, sys.PV(k,14)=0; if sys.ABus(bi,2)~=1, sys.ABus(bi,2)=0; end, end
end
sys.idx.slack=find(sys.ABus(:,2)==1); sys.idx.pv=find(sys.ABus(:,2)==2); sys.idx.pq=find(sys.ABus(:,2)==0);
sys.idx.ang=setdiff((1:sys.nbus)',sys.idx.slack); sys.idx.vm=sys.idx.pq;
nb=sys.nbus; base=sys.baseMVA;
sys.Vm0=sys.ABus(:,4); sys.Va0=deg2rad(sys.ABus(:,5));
slk=sys.Slack(1,1); sys.Vm0(slk)=sys.Slack(1,4); sys.Va0(slk)=deg2rad(sys.Slack(1,5));
for k=1:size(sys.PV,1), i=sys.PV(k,1); if sys.PV(k,14)~=0&&sys.ABus(i,2)==2, sys.Vm0(i)=sys.PV(k,4); end, end
Pl=zeros(nb,1); Ql=zeros(nb,1);
for k=1:size(sys.PQ,1), i=sys.PQ(k,1); if sys.PQ(k,9)~=0, Pl(i)=Pl(i)+sys.PQ(k,4); Ql(i)=Ql(i)+sys.PQ(k,5); end, end
sys.Pl=Pl/base; sys.Ql=Ql/base;
Pg=zeros(nb,1); Qmin=-inf(nb,1); Qmax=inf(nb,1);
for k=1:size(sys.PV,1)
  i=sys.PV(k,1);
  if sys.PV(k,14)~=0
    Pg(i)=Pg(i)+sys.PV(k,5); Qmin(i)=sys.PV(k,8); Qmax(i)=sys.PV(k,9);
  end
end
sys.Pg=Pg/base; sys.Qmax=Qmax/base; sys.Qmin=Qmin/base;
end

function S = run_sandbox(mfile)
old=pwd; c=onCleanup(@()cd(old)); cd(fileparts(mfile)); run(mfile);
vars={'ABus','ALine','Slack','PV','PQ','AShunt','Gen'}; S=struct();
for k=1:numel(vars), if exist(vars{k},'var'), S.(vars{k})=eval(vars{k}); end, end
end
