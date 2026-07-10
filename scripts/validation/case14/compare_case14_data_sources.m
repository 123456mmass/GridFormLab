function S = compare_case14_data_sources()
%COMPARE_CASE14_DATA_SOURCES Compare static/dynamic data availability among PSAT/PGAz/Ours.

pf_init_paths;
pgaz_file = 'C:/Users/User/Downloads/PGAz1.3 (2)/PGAz1.3/Data/case14_mp_test.m';
psat_file = 'C:/Users/User/Downloads/psat-2.1.11-mat/psat/tests/d_014_dyn_mdl.m';
psat_added = 'C:/Users/User/Downloads/psat-2.1.11-mat/psat/tests/d_case14_mp_test_mdl.m';

P = run_sandbox(pgaz_file, {'ABus','ALine','PV','PQ','Slack','AShunt','Gen'});
Q = run_sandbox(psat_file, {'Bus','Line','PV','PQ','SW','Syn','Exc'});
A = run_sandbox(psat_added, {'Bus','Line','PV','PQ','SW','Shunt'});

% Build comparable load vectors MW/Mvar
pgaz_load = aggregate_pgaz_load(P.PQ.con, 14);
psat_load = aggregate_psat_load(Q.PQ.con, 14);
added_load = aggregate_psat_load(A.PQ.con, 14);

Tload = table((1:14)', pgaz_load(:,1), psat_load(:,1), added_load(:,1), ...
    pgaz_load(:,2), psat_load(:,2), added_load(:,2), ...
    'VariableNames', {'Bus','PGAz_Pd_MW','PSAT_d014_Pd_MW','AddedPSAT_Pd_MW', ...
    'PGAz_Qd_Mvar','PSAT_d014_Qd_Mvar','AddedPSAT_Qd_Mvar'});

S = struct();
S.load_table = Tload;
S.pgaz = struct('nline',size(P.ALine.con,1),'ngen',size(P.Gen.con,1),'has_dynamic',false);
S.psat_d014 = struct('nline',size(Q.Line.con,1),'ngen',size(Q.Syn.con,1),'has_dynamic',true, ...
    'syn_buses',Q.Syn.con(:,1));
S.added_psat_case14 = struct('nline',size(A.Line.con,1),'has_dynamic',false);

outdir=fullfile(pwd,'docs','source','figures','case14_ts'); if ~exist(outdir,'dir'), mkdir(outdir); end
writetable(Tload, fullfile(outdir,'case14_data_source_load_compare.csv'));

fid=fopen(fullfile(outdir,'case14_data_source_compare.md'),'w'); c=onCleanup(@()fclose(fid));
fprintf(fid,'# Case14 data-source comparison\n\n');
fprintf(fid,'Important: PSAT built-in `d_014_dyn_mdl.m` is not identical to PGAz/MATPOWER `case14_mp_test.m`.\n\n');
fprintf(fid,'| Source | Lines | Dynamic generators | Notes |\n');
fprintf(fid,'|---|---:|---:|---|\n');
fprintf(fid,'| PGAz `case14_mp_test.m` | %d | 0 dynamic Syn; 5 classical Gen rows for pgaz_ts | MATPOWER/PGAz static case used by our imported case14 |\n',S.pgaz.nline);
fprintf(fid,'| PSAT `d_014_dyn_mdl.m` | %d | %d Syn | Different loads/line data/dynamic parameters; not directly comparable to PGAz case14 TS |\n',S.psat_d014.nline,S.psat_d014.ngen);
fprintf(fid,'| Added PSAT `d_case14_mp_test_mdl.m` | %d | 0 | Static clone of PGAz/MATPOWER case14; dynamic Syn still needed for PSAT TS |\n\n',S.added_psat_case14.nline);

fprintf(fid,'## Load comparison\n\n');
fprintf(fid,'| Bus | PGAz Pd | PSAT d014 Pd | Added PSAT Pd | PGAz Qd | PSAT d014 Qd | Added PSAT Qd |\n');
fprintf(fid,'|---:|---:|---:|---:|---:|---:|---:|\n');
for k=1:height(Tload)
    fprintf(fid,'| %d | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f |\n',Tload.Bus(k),Tload.PGAz_Pd_MW(k),Tload.PSAT_d014_Pd_MW(k),Tload.AddedPSAT_Pd_MW(k),Tload.PGAz_Qd_Mvar(k),Tload.PSAT_d014_Qd_Mvar(k),Tload.AddedPSAT_Qd_Mvar(k));
end
fprintf(fid,'\nFiles saved in %s\n',outdir);

fprintf('\nData-source comparison saved:\n  %s\n', fullfile(outdir,'case14_data_source_compare.md'));
disp(Tload);
end

function S = run_sandbox(mfile, vars)
old=pwd; c=onCleanup(@()cd(old)); cd(fileparts(mfile)); run(mfile); S=struct();
for k=1:numel(vars), if exist(vars{k},'var'), S.(vars{k})=eval(vars{k}); end, end
end

function L = aggregate_pgaz_load(PQ, nb)
L=zeros(nb,2);
for k=1:size(PQ,1)
    if PQ(k,14)~=0
        b=PQ(k,1); L(b,1)=L(b,1)+PQ(k,4); L(b,2)=L(b,2)+PQ(k,5);
    end
end
end

function L = aggregate_psat_load(PQ, nb)
L=zeros(nb,2);
for k=1:size(PQ,1)
    if PQ(k,end)~=0
        b=PQ(k,1); L(b,1)=L(b,1)+PQ(k,4)*100; L(b,2)=L(b,2)+PQ(k,5)*100;
    end
end
end
