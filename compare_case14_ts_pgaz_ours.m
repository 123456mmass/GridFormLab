function out = compare_case14_ts_pgaz_ours()
%COMPARE_CASE14_TS_PGAZ_OURS Run and compare case14 TS: PGAz pgaz_ts vs in-house.

pf_init_paths;
pgaz_root = 'C:/Users/User/Downloads/PGAz1.3 (2)/PGAz1.3';
pgaz_case = fullfile(pgaz_root,'Data','case14_mp_test.m');
addpath(genpath(pgaz_root));

sys = build_pgaz_sys_from_case(pgaz_case);
opt = struct();
opt.t_end = 15.0; opt.dt = 0.01; opt.method = 'trapezoidal'; opt.corrector_iter = 3; opt.make_plots = false;
opt.fault = struct('enable',true,'bus',4,'t_fault',1.0,'t_clear',1.1,'Rf',0.0,'Xf',0.1);

fprintf('\nRunning PGAz TS...\n');
TS_pgaz = pgaz_ts(sys, 1e-10, 50, opt);

fprintf('\nRunning in-house TS in PGAz-compatible mode...\n');
TS_ours = stability.case14_ts_classical(struct('t_end',15.0,'dt',0.01,'fault_bus',4, ...
    't_fault',1.0,'t_clear',1.1,'Zf',1i*0.1,'method','trapezoidal', ...
    'corrector_iter',3,'pm_mode','pgaz','verbose',true));

% Align variables. PGAz delta is absolute rotor angle in deg; ours same.
D_ours = rad2deg(TS_ours.delta);
W_ours = TS_ours.omega;
Pe_ours = TS_ours.Pe_MW;
Vm_ours = TS_ours.Vbus;

D_pgaz = TS_pgaz.delta_deg;
W_pgaz = TS_pgaz.omega;
Pe_pgaz = TS_pgaz.Pe_pu * TS_pgaz.baseMVA;
Vm_pgaz = TS_pgaz.Vm;

delta_err = D_ours - D_pgaz;
omega_err = W_ours - W_pgaz;
Pe_err = Pe_ours - Pe_pgaz;
Vm_err = Vm_ours - Vm_pgaz;

out = struct();
out.TS_pgaz = TS_pgaz; out.TS_ours = TS_ours;
out.max = struct('delta_deg',max(abs(delta_err),[],'all'), ...
    'omega_pu',max(abs(omega_err),[],'all'), ...
    'Pe_MW',max(abs(Pe_err),[],'all'), ...
    'Vm_pu',max(abs(Vm_err),[],'all'));
out.final = table(TS_pgaz.gen_bus(:), D_pgaz(end,:).', D_ours(end,:).', delta_err(end,:).', ...
    W_pgaz(end,:).', W_ours(end,:).', omega_err(end,:).', ...
    Pe_pgaz(end,:).', Pe_ours(end,:).', Pe_err(end,:).', ...
    'VariableNames', {'GenBus','PGAz_delta_deg','Ours_delta_deg','dDelta_deg', ...
    'PGAz_omega','Ours_omega','dOmega','PGAz_Pe_MW','Ours_Pe_MW','dPe_MW'});

outdir = fullfile(pwd,'docs','source','figures','case14_ts');
if ~exist(outdir,'dir'), mkdir(outdir); end
writetable(out.final, fullfile(outdir,'case14_ts_compare_pgaz_ours_final.csv'));
write_markdown(out, fullfile(outdir,'case14_ts_compare_pgaz_ours.md'));
make_compare_plot(TS_pgaz, TS_ours, fullfile(outdir,'case14_ts_compare_pgaz_ours.png'));

fprintf('\n=== Case14 TS PGAz vs Ours ===\n');
fprintf('max |delta| = %.6g deg\n', out.max.delta_deg);
fprintf('max |omega| = %.6g pu\n', out.max.omega_pu);
fprintf('max |Pe|    = %.6g MW\n', out.max.Pe_MW);
fprintf('max |Vm|    = %.6g pu\n', out.max.Vm_pu);
disp(out.final);
fprintf('Saved comparison files in %s\n', outdir);
end

function sys = build_pgaz_sys_from_case(mfile)
S = run_case_sandbox(mfile);
sys = struct();
sys.meta.case_file = mfile;
sys.ABus = S.ABus.con; sys.ALine = S.ALine.con; sys.Slack = S.Slack.con;
sys.PV = S.PV.con; sys.PQ = S.PQ.con; sys.Gen = S.Gen.con;
if isfield(S,'AShunt'), sys.AShunt = S.AShunt.con; else, sys.AShunt = []; end
sys.baseMVA = sys.Slack(1,2); sys.nbus = size(sys.ABus,1); sys.nline = size(sys.ALine,1); sys.nshunt=size(sys.AShunt,1);
% Apply PV/Gen consistency (minimal copy of PGAz importer behavior)
for k=1:size(sys.PV,1)
    bus_i=sys.PV(k,1); gen_rows=find(sys.Gen(:,1)==bus_i); gen_on=~isempty(gen_rows)&&any(sys.Gen(gen_rows,25)~=0);
    if gen_on, sys.PV(k,14)=1; if sys.ABus(bus_i,2)~=1, sys.ABus(bus_i,2)=2; end
    else, sys.PV(k,14)=0; if sys.ABus(bus_i,2)~=1, sys.ABus(bus_i,2)=0; end
    end
end
sys.idx.slack=find(sys.ABus(:,2)==1); sys.idx.pv=find(sys.ABus(:,2)==2); sys.idx.pq=find(sys.ABus(:,2)==0);
sys.idx.ang=setdiff((1:sys.nbus)',sys.idx.slack); sys.idx.vm=sys.idx.pq;
% Preprocess PF data
nb=sys.nbus; base=sys.baseMVA;
sys.Vm0=sys.ABus(:,4); sys.Va0=deg2rad(sys.ABus(:,5));
slk=sys.Slack(1,1); sys.Vm0(slk)=sys.Slack(1,4); sys.Va0(slk)=deg2rad(sys.Slack(1,5));
for k=1:size(sys.PV,1), i=sys.PV(k,1); if sys.PV(k,14)~=0 && sys.ABus(i,2)==2, sys.Vm0(i)=sys.PV(k,4); end, end
Pl=zeros(nb,1); Ql=zeros(nb,1); for k=1:size(sys.PQ,1), i=sys.PQ(k,1); if sys.PQ(k,9)~=0, Pl(i)=Pl(i)+sys.PQ(k,4); Ql(i)=Ql(i)+sys.PQ(k,5); end, end
sys.Pl=Pl/base; sys.Ql=Ql/base;
Pg=zeros(nb,1); Qmin=-inf(nb,1); Qmax=inf(nb,1);
for k=1:size(sys.PV,1)
    i=sys.PV(k,1);
    if sys.PV(k,14)~=0
        Pg(i)=Pg(i)+sys.PV(k,5);      % PGAz PV.con col 5 = Pg MW
        Qmin(i)=sys.PV(k,8);          % col 8 = Qmin Mvar
        Qmax(i)=sys.PV(k,9);          % col 9 = Qmax Mvar
    end
end
sys.Pg=Pg/base; sys.Qmax=Qmax/base; sys.Qmin=Qmin/base;
end

function S = run_case_sandbox(mfile)
old=pwd; c=onCleanup(@()cd(old)); cd(fileparts(mfile)); run(mfile);
vars={'ABus','ALine','Slack','PV','PQ','AShunt','Gen'}; S=struct();
for k=1:numel(vars), if exist(vars{k},'var'), S.(vars{k})=eval(vars{k}); end, end
end

function write_markdown(out,path)
fid=fopen(path,'w'); c=onCleanup(@()fclose(fid));
fprintf(fid,'# Case14 TS comparison: PGAz vs in-house\n\n');
fprintf(fid,'## Max absolute differences over all samples\n\n');
fprintf(fid,'| Signal | Max abs diff |\n|---|---:|\n');
fprintf(fid,'| delta (deg) | %.8g |\n',out.max.delta_deg);
fprintf(fid,'| omega (pu) | %.8g |\n',out.max.omega_pu);
fprintf(fid,'| Pe (MW) | %.8g |\n',out.max.Pe_MW);
fprintf(fid,'| Vm (pu) | %.8g |\n\n',out.max.Vm_pu);
fprintf(fid,'## Final generator values\n\n');
fprintf(fid,'| Gen bus | PGAz delta | Ours delta | dDelta | PGAz omega | Ours omega | dOmega | PGAz Pe | Ours Pe | dPe |\n');
fprintf(fid,'|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n');
T=out.final;
for k=1:height(T)
    fprintf(fid,'| %d | %.6f | %.6f | %+ .3e | %.8f | %.8f | %+ .3e | %.6f | %.6f | %+ .3e |\n', ...
        T.GenBus(k),T.PGAz_delta_deg(k),T.Ours_delta_deg(k),T.dDelta_deg(k),T.PGAz_omega(k),T.Ours_omega(k),T.dOmega(k),T.PGAz_Pe_MW(k),T.Ours_Pe_MW(k),T.dPe_MW(k));
end
end

function make_compare_plot(TS_pgaz, TS_ours, path)
f=figure('Visible','off','Color','w','Position',[80 80 1300 850]); tl=tiledlayout(f,2,2,'Padding','compact','TileSpacing','compact');
t=TS_pgaz.t; D_ours=rad2deg(TS_ours.delta); Pe_ours=TS_ours.Pe_MW;
nexttile; plot(t,TS_pgaz.delta_deg,'-','LineWidth',1.0); hold on; plot(t,D_ours,'--','LineWidth',1.0); grid on; title('Rotor angle: PGAz solid, ours dashed'); ylabel('deg'); xlabel('s');
nexttile; plot(t,TS_pgaz.omega,'-','LineWidth',1.0); hold on; plot(t,TS_ours.omega,'--','LineWidth',1.0); grid on; title('Speed: PGAz solid, ours dashed'); ylabel('pu'); xlabel('s');
nexttile; plot(t,TS_pgaz.Pe_pu*TS_pgaz.baseMVA,'-','LineWidth',1.0); hold on; plot(t,Pe_ours,'--','LineWidth',1.0); grid on; title('Pe: PGAz solid, ours dashed'); ylabel('MW'); xlabel('s');
nexttile; plot(t,TS_pgaz.Vm(:,4),'-k','LineWidth',1.4); hold on; plot(t,TS_ours.Vbus(:,4),'--r','LineWidth',1.4); grid on; title('Fault bus 4 voltage'); ylabel('pu'); xlabel('s'); legend('PGAz','ours');
sgtitle(tl,'Case14 TS comparison: PGAz vs in-house'); exportgraphics(f,path,'Resolution',200); close(f);
end
