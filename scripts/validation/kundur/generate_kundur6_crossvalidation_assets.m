function generate_kundur6_crossvalidation_assets()
%GENERATE_KUNDUR6_CROSSVALIDATION_ASSETS Assets for clean OURS/PSAT/BOOK report.
pf_init_paths;
outdir = fullfile(pwd,'docs','source','figures','kundur_ex126');
if ~exist(outdir,'dir'), mkdir(outdir); end

% --- PF: OURS vs PSAT saved operating point ------------------------------
case_data = cases.case_kundur_two_area_classical();
pf = pfsolver.powerflow_newton_raphson(case_data, struct('plot_results',false,'verbose',false, ...
    'max_iter',50,'tolerance',1e-10,'enforce_q_limits',false));
S = load(fullfile(outdir,'psat_kundur6_ts_raw.mat')); ps = S.ps_save;
bus = pf.external_bus_ids(:); [~,op] = ismember(bus, ps.bus_ids(:));
Vps = ps.pf_vmag(op); Aps = ps.pf_angle_deg(op);
Vo = pf.bus_voltage(:); Ao = pf.bus_angle_deg(:);
% remove one global angle offset; slack convention differs
ang_offset = mean(Ao - Aps);
Aps_aligned = Aps + ang_offset;
dV = Vo - Vps(:); dA = Ao - Aps_aligned(:);
write_pf_compare(fullfile(outdir,'table_pf_ours_psat.tex'), bus, Vo, Vps(:), Ao, Aps_aligned(:), dV, dA);
plot_pf_compare(fullfile(outdir,'pf_ours_psat_compare.png'), bus, Vo, Vps(:), dV, dA);

% --- SSSA: actual in-house book-reproduction output vs book and PSAT ------
ssa = stability.kundur_ex126_book_e123_ssa();
book = [-0.111+1i*3.430; -0.492+1i*6.820; -0.506+1i*7.020];
[modes_o, idx_o] = match_modes_to_reference(ssa.eigenvalues, book);
S2 = load(fullfile(outdir,'psat_kundur6_sssa.mat')); ps_ev = S2.ps_ev(:);
[modes_p, ~] = match_modes_to_reference(ps_ev, book);
states = dominant_states_for_indices(ssa.mode_shapes, ssa.state_names, idx_o, 3);
write_sssa_3way(fullfile(outdir,'table_sssa_ours_book_psat.tex'), modes_o, book, modes_p, states);
write_sssa_24(fullfile(outdir,'table_sssa_24_actual.tex'), ssa);

% --- TS: metrics already computed by compare script, regenerate plots -----
out = compare_kundur6_ts_psat_ours();
write_ts_metrics(fullfile(outdir,'table_ts_ours_psat.tex'), out);

fprintf('Generated cross-validation assets in %s\n', outdir);
end

function [modes, idx] = match_modes_to_reference(lambda, ref)
% Unique nearest matching of positive-imaginary oscillatory modes to the three
% Kundur rotor-mode references. This avoids swapping the two local PSAT modes.
osc_idx = find(abs(imag(lambda)) > 0.1 & real(lambda) < 0 & imag(lambda) > 0);
osc = lambda(osc_idx);
modes = zeros(numel(ref),1); idx = zeros(numel(ref),1); used = false(numel(osc),1);
for k=1:numel(ref)
    d = abs(osc - ref(k)); d(used) = inf;
    [~,j] = min(d);
    modes(k) = osc(j); idx(k) = osc_idx(j); used(j) = true;
end
end

function states = dominant_states_for_indices(V, names, idx, ntop)
names = cellstr(string(names(:))); states = strings(numel(idx),1);
for k=1:numel(idx)
    v = abs(V(:,idx(k))); [~,ord] = sort(v,'descend'); parts = {};
    for j=1:min(ntop,numel(ord)), parts{end+1} = latex_escape_name(names{ord(j)}); end %#ok<AGROW>
    states(k) = strjoin(parts, ', ');
end
end

function s = latex_escape_name(s)
s = strrep(char(s),'_','\_');
s = ['$' s '$'];
end

function write_pf_compare(path,bus,Vo,Vp,Ao,Ap,dV,dA)
fid=fopen(path,'w'); c=onCleanup(@()fclose(fid));
fprintf(fid,'\\begingroup\\scriptsize\\setlength{\\tabcolsep}{3pt}\n');
fprintf(fid,'\\begin{tabular}{r r r r r r r}\\toprule\n');
fprintf(fid,'Bus & $V_o$ & $V_{PSAT}$ & $\\Delta V$ & $\\theta_o$ & $\\theta_{PSAT}$ & $\\Delta\\theta$\\\\\\midrule\n');
for k=1:numel(bus)
    fprintf(fid,'%d & %.4f & %.4f & %.4f & %.3f & %.3f & %.3f\\\\\n', bus(k), Vo(k), Vp(k), dV(k), Ao(k), Ap(k), dA(k));
end
fprintf(fid,'\\bottomrule\n');
fprintf(fid,'\\multicolumn{7}{l}{\\scriptsize max $|\\Delta V|=%.4f$ pu, max $|\\Delta\\theta|=%.3f^\\circ$ after removing global slack-angle offset.}\\\\\n', max(abs(dV)), max(abs(dA)));
fprintf(fid,'\\end{tabular}\\endgroup\n');
end

function plot_pf_compare(path,bus,Vo,Vp,dV,dA)
f=figure('Visible','off','Color','w','Position',[80 80 1100 650]);
tl=tiledlayout(f,2,2,'Padding','compact','TileSpacing','compact');
nexttile; plot(bus,Vo,'o-','LineWidth',1.4); hold on; plot(bus,Vp,'s--','LineWidth',1.2); grid on; xlabel('Bus'); ylabel('|V| pu'); title('Voltage magnitude'); legend({'OURS','PSAT'},'Location','best');
nexttile; bar(bus,dV); grid on; xlabel('Bus'); ylabel('OURS-PSAT pu'); title('Voltage error');
nexttile([1 2]); bar(bus,dA); grid on; xlabel('Bus'); ylabel('OURS-PSAT deg'); title('Angle error after slack-offset alignment');
sgtitle(tl,'Power-flow comparison: OURS vs PSAT');
exportgraphics(f,path,'Resolution',200); close(f);
end

function write_sssa_3way(path,o,b,p,states)
labels={'Interarea','Area 1 local','Area 2 local'};
fid=fopen(path,'w'); c=onCleanup(@()fclose(fid));
fprintf(fid,'\\begingroup\\scriptsize\\setlength{\\tabcolsep}{3pt}\n');
fprintf(fid,'\\begin{tabular}{l c c c r r l}\\toprule\n');
fprintf(fid,'Mode & OURS $\\lambda$ & Book $\\lambda$ & PSAT $\\lambda$ & OURS err & PSAT err & Dominant OURS states\\\\\\midrule\n');
for k=1:3
    eo=max(abs([real(o(k)-b(k))/real(b(k)), imag(o(k)-b(k))/imag(b(k))]))*100;
    ep=abs(imag(p(k))-imag(b(k)))/abs(imag(b(k)))*100;
    fprintf(fid,'%s & %s & %s & %s & %.2f\\%% & %.1f\\%% & %s\\\\\n', labels{k}, lamstr(o(k)), lamstr(b(k)), lamstr(p(k)), abs(eo), ep, states(k));
end
fprintf(fid,'\\bottomrule\\end{tabular}\\endgroup\n');
end

function write_sssa_24(path,ssa)
lam=ssa.eigenvalues(:); [~,ord]=sort(real(lam),'descend'); lam=lam(ord); V=ssa.mode_shapes(:,ord); names=cellstr(string(ssa.state_names(:)));
fid=fopen(path,'w'); c=onCleanup(@()fclose(fid));
fprintf(fid,'\\begingroup\\scriptsize\\setlength{\\tabcolsep}{3pt}\\renewcommand{\\arraystretch}{0.86}\n');
fprintf(fid,'\\begin{tabular}{r r r r r p{5.0cm}}\\toprule\n');
fprintf(fid,'No. & Re$(\\lambda)$ & Im$(\\lambda)$ & $f$ Hz & $\\zeta$ & Dominant state variables\\\\\\midrule\n');
for k=1:numel(lam)
    z=-real(lam(k))/(abs(lam(k))+eps); f=abs(imag(lam(k)))/(2*pi);
    dom=dominant_from_vec(V(:,k),names,3);
    fprintf(fid,'%d & %.6f & %.6f & %.4f & %.4f & %s\\\\\n', k, real(lam(k)), imag(lam(k)), f, z, dom);
end
fprintf(fid,'\\bottomrule\\multicolumn{6}{p{0.92\\textwidth}}{\\scriptsize Values are direct eigenvalues of the current 24-state in-house book-reproduction solver output. Positive/near-zero full-matrix reference modes are not used as the headline stability benchmark; rotor-angle benchmark rows are reported separately.}\\\\\n');
fprintf(fid,'\\end{tabular}\\endgroup\n');
end

function s=dominant_from_vec(v,names,ntop)
[~,ord]=sort(abs(v),'descend'); parts={};
for j=1:min(ntop,numel(ord)), parts{end+1}=latex_escape_name(names{ord(j)}); end %#ok<AGROW>
s=strjoin(parts,', ');
end

function write_ts_metrics(path,out)
fid=fopen(path,'w'); c=onCleanup(@()fclose(fid));
fprintf(fid,'\\begin{tabular}{l r}\\toprule\n');
fprintf(fid,'Metric (COI frame) & OURS vs PSAT\\\\\\midrule\n');
fprintf(fid,'max $|\\Delta\\delta_{rel}|$ & %.4f$^\\circ$\\\\\n', out.max.delta_rel_deg);
fprintf(fid,'max $|\\Delta\\omega_{rel}|$ & %.6g pu\\\\\n', out.max.omega_rel_pu);
fprintf(fid,'max $|\\Delta\\delta_{abs}|$ & %.4f$^\\circ$ (reference offset)\\\\\n', out.max.delta_abs_deg);
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function s=lamstr(x)
s=sprintf('$%.3f\\pm j%.3f$', real(x), abs(imag(x)));
end
