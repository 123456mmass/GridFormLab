function build_psat_case14_dynamic()
%BUILD_PSAT_CASE14_DYNAMIC Convert MATPOWER6 case14 to PSAT via matpower2psat,
% then append classical Syn.con + Fault.con for TS comparison.

root = 'C:/Users/User/Desktop/IBR/Power-flow';
psat_root = 'C:/Users/User/Downloads/psat-2.1.11-mat/psat';
tmpdir = fullfile(root,'docs','source','figures','case14_ts');
if ~exist(tmpdir,'dir'), mkdir(tmpdir); end

% --- 1. Build trimmed old-MATPOWER-format mpc file ---
addpath('C:/Users/User/Downloads/matpower6.0/matpower6.0');
mpc = case14;
mpc.bus    = mpc.bus(:,1:13);
mpc.gen    = mpc.gen(:,1:10);
mpc.branch = mpc.branch(:,1:11);
% Ensure slack bus angle 0 and remove extra fields.
if isfield(mpc,'bus_name'), mpc = rmfield(mpc,'bus_name'); end

tmpcase = fullfile(tmpdir,'case14_mp_psat.m');
fid = fopen(tmpcase,'w'); c = onCleanup(@()fclose(fid));
fprintf(fid,'function mpc = case14_mp_psat\n');
fprintf(fid,'mpc.baseMVA = %g;\n', mpc.baseMVA);
fprintf(fid,'mpc.bus = [\n');
for k=1:size(mpc.bus,1)
    fprintf(fid,'  %d %d %g %g %g %g %d %g %g %g %d %g %g;\n', mpc.bus(k,:));
end
fprintf(fid,'];\nmpc.gen = [\n');
for k=1:size(mpc.gen,1)
    fprintf(fid,'  %d %g %g %g %g %g %g %d %g %g;\n', mpc.gen(k,:));
end
fprintf(fid,'];\nmpc.branch = [\n');
for k=1:size(mpc.branch,1)
    fprintf(fid,'  %d %d %g %g %g %g %g %g %g %g %d;\n', mpc.branch(k,:));
end
fprintf(fid,'];\n');
fclose(fid);

% --- 2. Run matpower2psat ---
old = pwd; cleanup = onCleanup(@() cd(old));
addpath(genpath(psat_root));
cd(psat_root);
global Settings Path clpsat
command_line_psat = 1; %#ok<NASGU>
psat; clpsat.mesg = 0;
check = matpower2psat('case14_mp_psat.m', tmpdir);
if ~check, error('matpower2psat conversion failed.'); end
genfile = fullfile(tmpdir,'d_case14_mp_psat.m');
disp('--- Generated static PSAT case (head) ---');
copyfile(genfile, fullfile(tmpdir,'d_case14_mp_psat_static_view.m'));

% --- 3. Append dynamic Syn.con + Fault.con ---
static_txt = fileread(genfile);
target = fullfile(psat_root,'tests','d_case14_mp_psat_dyn_mdl.m');
fid = fopen(target,'w'); c2 = onCleanup(@()fclose(fid));
fprintf(fid,'%s', static_txt);
fprintf(fid,'\n%% --- Appended dynamic data for PSAT/PGAz/Ours TS comparison ---\n');
fprintf(fid,'%% Classical generators: H=5 (M=10), D=0, x''d=0.3, buses 1,2,3,6,8.\n');
fprintf(fid,'Syn.con = [ ...\n');
genrows = [1; 2; 3; 6; 8];
for k=1:numel(genrows)
    % Vn must match matpower2psat Bus.con Vn (=1 when source baseKV=0), so that
    % PSAT Settings.conv base conversion leaves X'd = 0.3 unchanged.
    fprintf(fid,'  %d 100 1 60 2 0 0 0.3 0.3 0 1 0 0.3 0.3 0 1 0 10 0 0 0 1 1 0.002 0 0 1 1;\n', genrows(k));
end
fprintf(fid,'];\n\n');
fprintf(fid,'%% Fault: bus 4, t_fault=1.0 s, t_clear=1.1 s, Zf = 0 + j0.1 pu.\n');
fprintf(fid,'Fault.con = [ ...\n');
fprintf(fid,'  4 100 1 60 1.0 1.1 0 0.1;\n');
fprintf(fid,'];\n');
fclose(fid);

fprintf('Built dynamic PSAT case:\n  %s\n', target);
disp('--- Static portion (Line.con head) ---');
end
