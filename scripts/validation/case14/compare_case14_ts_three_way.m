function out = compare_case14_ts_three_way()
%COMPARE_CASE14_TS_THREE_WAY  Fresh PSAT vs (optional) PGAz vs Ours for case14 TS.
%   PSAT results are regenerated FRESH in this session via run_psat_case14
%   (no saved .mat). PSAT is the primary reference. PGAz is secondary and
%   runs only if PGAz V1.1.1 is available; otherwise the comparison is
%   PSAT vs Ours (two-way). Compares rotor angles/speeds in the COI frame
%   (inter-machine) plus fault-bus voltage, because each tool uses a
%   different absolute angle reference (PSAT fixes slack; PGAz/Ours float COI).

pf_init_paths;
root = pf_init_paths;
outdir = fullfile(root,'docs','source','figures','case14_ts');
if ~exist(outdir,'dir'), mkdir(outdir); end
tg = (0:0.01:15).';

% --- PSAT (FRESH) ---
ps = run_psat_case14();
dps = rad2deg(interp1(ps.t, ps.delta, tg, 'linear'));
wps = interp1(ps.t, ps.omega, tg, 'linear');
peps = 100*interp1(ps.t, ps.Pe_pu, tg, 'linear');     % MW (base 100)
vps_all = interp1(ps.t, ps.Vbus, tg, 'linear');
[~,ord] = sort(ps.delta_bus);
dps = dps(:,ord); wps = wps(:,ord); peps = peps(:,ord);
gbus_ps = ps.delta_bus(ord);
fi_ps = find(ps.vbus_ids==4,1); vps_fault = vps_all(:,fi_ps);

% --- Ours: production adaptive/event-aware engine ---
c_ours = cases.case_matpower6_case14();
opt = struct('t_end',15.0,'dt',0.01,'fault_bus',4,'t_fault',1.0,'t_clear',1.1, ...
    'Zf',1i*0.1,'method','trapezoidal','corrector_mode','adaptive', ...
    'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8, ...
    'max_corrector_iter',10,'corrector_failure','error', ...
    'pm_mode','balanced','model','classical','verbose',false);
res = stability.ts_simulate(c_ours,opt);
[~,oo] = sort(res.gen_buses);
d_ours = rad2deg(res.delta(:,oo)); w_ours = res.omega(:,oo); pe_ours = res.Pe_MW(:,oo);
gbus_ours = res.gen_buses(oo);
bus_ids_ours = res.pf.external_bus_ids(:);
fi_ours = find(bus_ids_ours==4,1); v_ours_fault = res.Vbus(:,fi_ours);

assert(isequal(gbus_ps(:),gbus_ours(:)), ...
    'Generator bus mapping differs between PSAT and Ours.');

% --- PGAz (OPTIONAL, secondary) ---
have_pg = false;
try
    pgaz_root = '/home/birds/Documents/PGAz_V1.1.1';
    if exist(pgaz_root,'dir')
        addpath(genpath(pgaz_root));
        sys = build_pgaz_sys(fullfile('docs','source','figures','case14_ts','case14_mp_psat.m'));
        optp = struct(); optp.t_end=15.0; optp.dt=0.01; optp.method='trapezoidal'; optp.corrector_iter=3;
        optp.make_plots=false; optp.fault=struct('enable',true,'bus',4,'t_fault',1.0,'t_clear',1.1,'Rf',0.0,'Xf',0.1);
        TS = pgaz_ts(sys,1e-10,50,optp);
        [~,po] = sort(TS.gen_bus);
        d_pg = interp1(TS.t, TS.delta_deg, tg, 'linear'); d_pg = d_pg(:,po);
        w_pg = interp1(TS.t, TS.omega, tg, 'linear'); w_pg = w_pg(:,po);
        pe_pg = interp1(TS.t, TS.Pe_pu*TS.baseMVA, tg, 'linear'); pe_pg = pe_pg(:,po);
        v_pg_all = interp1(TS.t, TS.Vm, tg, 'linear');
        gbus_pg = TS.gen_bus(po); v_pg_fault = v_pg_all(:,4);
        if isequal(gbus_pg(:), gbus_ours(:)), have_pg = true; end
    end
catch
    have_pg = false;
end

% --- COI frame (equal H=5 for case14 classical) ---
H = 5*ones(numel(gbus_ours),1);
coi_ps = sum(H'.*dps,2)/sum(H);   drel_ps = dps - coi_ps;   wrel_ps = wps - mean(wps,2);
coi_our = sum(H'.*d_ours,2)/sum(H); drel_our = d_ours - coi_our; wrel_our = w_ours - mean(w_ours,2);
if have_pg
    coi_pg = sum(H'.*d_pg,2)/sum(H); drel_pg = d_pg - coi_pg; wrel_pg = w_pg - mean(w_pg,2);
end

d_ps_our = max(abs(drel_ps - drel_our),[],'all');
w_ps_our = max(abs(wrel_ps - wrel_our),[],'all');
pe_ps_our = max(abs(peps - pe_ours),[],'all');
v_ps_our = max(abs(vps_fault - v_ours_fault),[],'all');

out = struct();
out.gen_buses = gbus_ours;
out.max = struct('delta_deg_ps_ours',d_ps_our, 'omega_pu_ps_ours',w_ps_our, ...
    'Pe_MW_ps_ours',pe_ps_our, 'Vm_pu_ps_ours',v_ps_our);
out.ours_nonconv = res.nonconverged_step_count;
out.psat_pf_conv = ps.pf_conv;
out.psat_td_points = ps.td_points;
out.pgaz_used = have_pg;

% --- PF comparison ---
pf_ps_ang = ps.pf_angle_deg; pf_ps_v = ps.pf_vmag;
pf_our = res.pf;
out.pf = struct( ...
    'max_dV_ps_ours',max(abs(pf_ps_v-pf_our.bus_voltage)), ...
    'max_dAng_ps_ours',max(abs(pf_ps_ang-pf_our.bus_angle_deg)));
if have_pg
    pf_pg_v = TS.Vm(1,:).'; pf_pg_ang = TS.Va_deg(1,:).';
    out.pf.max_dV_ps_pg = max(abs(pf_ps_v-pf_pg_v));
    out.pf.max_dAng_ps_pg = max(abs(pf_ps_ang-pf_pg_ang));
    out.pf.max_dV_pg_ours = max(abs(pf_pg_v-pf_our.bus_voltage));
    out.pf.max_dAng_pg_ours = max(abs(pf_pg_ang-pf_our.bus_angle_deg));
end

% --- Markdown report ---
fid = fopen(fullfile(outdir,'case14_ts_compare_three_way.md'),'w'); c = onCleanup(@()fclose(fid));
fprintf(fid,'# IEEE 14-bus TS comparison: PSAT vs Ours%s\n\n', ternary(have_pg,' vs PGAz',''));
fprintf(fid,'Scenario: bus 4 three-phase fault, t_fault=1.0 s, t_clear=1.1 s, Zf=0+j0.1 pu, t_end=15 s, dt=0.01 s.\n');
fprintf(fid,'Model: classical (5 generators at buses 1,2,3,6,8; H=5, D=0, x''d=0.3).\n');
fprintf(fid,'PSAT results regenerated FRESH this session (run_psat_case14); PSAT is reference-only. PGAz%s.\n\n', ternary(have_pg,' included as secondary',' not available -> two-way'));
fprintf(fid,'## Power flow\n\n| Pair | Max |dV| (pu) | Max |dAngle| (deg) |\n|---|---:|---:|\n');
fprintf(fid,'| PSAT vs Ours | %.6g | %.6g |\n',out.pf.max_dV_ps_ours,out.pf.max_dAng_ps_ours);
if have_pg
    fprintf(fid,'| PSAT vs PGAz | %.6g | %.6g |\n',out.pf.max_dV_ps_pg,out.pf.max_dAng_ps_pg);
    fprintf(fid,'| PGAz vs Ours | %.6g | %.6g |\n',out.pf.max_dV_pg_ours,out.pf.max_dAng_pg_ours);
end
fprintf(fid,'\n## Transient stability (COI frame)\n\n| Pair | Max |delta_rel| (deg) | Max |omega_rel| (pu) | Max |Pe| (MW) | Max |Vm_bus4| (pu) |\n|---|---:|---:|---:|---:|\n');
fprintf(fid,'| PSAT vs Ours | %.6g | %.6g | %.6g | %.6g |\n',d_ps_our,w_ps_our,pe_ps_our,v_ps_our);
if have_pg
    d_ps_pg=max(abs(drel_ps-drel_pg),[],'all'); w_ps_pg=max(abs(wrel_ps-wrel_pg),[],'all');
    pe_ps_pg=max(abs(peps-pe_pg),[],'all'); v_ps_pg=max(abs(vps_fault-v_pg_fault),[],'all');
    d_pg_our=max(abs(drel_pg-drel_our),[],'all'); w_pg_our=max(abs(wrel_pg-wrel_our),[],'all');
    pe_pg_our=max(abs(pe_pg-pe_ours),[],'all'); v_pg_our=max(abs(v_pg_fault-v_ours_fault),[],'all');
    fprintf(fid,'| PSAT vs PGAz | %.6g | %.6g | %.6g | %.6g |\n',d_ps_pg,w_ps_pg,pe_ps_pg,v_ps_pg);
    fprintf(fid,'| PGAz vs Ours | %.6g | %.6g | %.6g | %.6g |\n',d_pg_our,w_pg_our,pe_pg_our,v_pg_our);
end
fprintf(fid,'\n## Notes\n\n- Ours: production adaptive/event-aware implicit trapezoidal corrector (non-converged steps = %d/%d). PSAT: converged trapezoidal Newton (TD pts=%d).\n', out.ours_nonconv, numel(res.t)-1, out.psat_td_points);
fprintf(fid,'- Rotor angles/speeds compared in the COI frame; electrical power and fault-bus voltage retain physical references.\n');

% --- Plot ---
f = figure('Visible','off','Color','w','Position',[60 60 1350 820]);
tl = tiledlayout(f,2,2,'Padding','compact','TileSpacing','compact');
nexttile; plot(tg,drel_our,'-','LineWidth',1.3); hold on; plot(tg,drel_ps,'--','LineWidth',1.1);
grid on; xlabel('time (s)'); ylabel('COI-relative \delta (deg)');
title('Rotor angle (COI): Ours solid, PSAT dashed'); legend(arrayfun(@(b)sprintf('G@%d',b),gbus_ours,'uni',0),'Location','best');
nexttile; plot(tg,wrel_our,'-','LineWidth',1.3); hold on; plot(tg,wrel_ps,'--','LineWidth',1.1);
grid on; xlabel('time (s)'); ylabel('COI-relative \omega (pu)'); title('Speed (COI): Ours solid, PSAT dashed');
nexttile; plot(tg,d_ours-d_ours(1,:),'.-','LineWidth',0.8); hold on; plot(tg,dps-dps(1,:),'+-','LineWidth',0.8);
grid on; xlabel('time (s)'); ylabel('\delta(t)-\delta(0) (deg)'); title('Absolute angle drift (PSAT-style)');
nexttile; plot(tg,v_ours_fault,'-','LineWidth',1.4); hold on; plot(tg,vps_fault,'--','LineWidth',1.2);
if have_pg, plot(tg,v_pg_fault,':','LineWidth',1.2); end
grid on; xlabel('time (s)'); ylabel('|V| bus 4 (pu)'); title('Fault-bus voltage'); legend('Ours','PSAT',ternary(have_pg,'PGAz',''),'Location','best');
sgtitle(tl, sprintf('Case14 TS: PSAT vs Ours%s (COI frame, fresh PSAT)', ternary(have_pg,' vs PGAz','')));
exportgraphics(f, fullfile(outdir,'case14_ts_compare_three_way.png'),'Resolution',200); close(f);

fprintf('\n=== Case14 TS (COI frame, fresh PSAT) ===\n');
fprintf('PSAT vs Ours : delta %.6g deg, omega %.6g pu, Pe %.6g MW, Vm %.6g pu\n',d_ps_our,w_ps_our,pe_ps_our,v_ps_our);
fprintf('PF: max|dV|=%.3e pu, max|dAng|=%.3e deg ; ours nonconv=%d/%d\n', out.pf.max_dV_ps_ours, out.pf.max_dAng_ps_ours, out.ours_nonconv, numel(res.t)-1);
end

function s = ternary(c,a,b), if c, s=a; else, s=b; end, end

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
  if sys.PV(k,14)~=0, Pg(i)=Pg(i)+sys.PV(k,5); Qmin(i)=sys.PV(k,8); Qmax(i)=sys.PV(k,9); end
end
sys.Pg=Pg/base; sys.Qmax=Qmax/base; sys.Qmin=Qmin/base;
end

function S = run_sandbox(mfile)
old=pwd; c=onCleanup(@()cd(old)); cd(fileparts(mfile)); run(mfile);
vars={'ABus','ALine','Slack','PV','PQ','AShunt','Gen'}; S=struct();
for k=1:numel(vars), if exist(vars{k},'var'), S.(vars{k})=eval(vars{k}); end, end
end
