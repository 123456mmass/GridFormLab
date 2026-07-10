function generate_kundur_ex126_report()
%GENERATE_KUNDUR_EX126_REPORT Generate figures/tables for the Ex. 12.6 report.
%   Single source of truth for the report: this script runs the in-house
%   Newton-Raphson power-flow solver on +cases/case_kundur_two_area_classical
%   and reads +stability/kundur_ex126_classical_analysis for the classical
%   small-signal benchmark comparison.

pf_init_paths;
root = pwd;
outdir = fullfile(root, 'docs', 'source', 'figures', 'kundur_ex126');
if ~exist(outdir, 'dir'); mkdir(outdir); end

case_data = cases.case_kundur_two_area_classical();
opts = struct('plot_results', false, 'verbose', false, 'max_iter', 50, ...
    'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, opts);
stab = stability.kundur_ex126_classical_analysis();
% Run the latest validated 6th-order Kundur/GENTPJ SSSA through the common
% multimachine_ssa engine. This is the book-reproduction path used for the
% <0.5% Kundur Table E12.3 benchmark.
ssa6 = stability.kundur_ex126_book_e123_ssa();

save(fullfile(outdir, 'kundur_ex126_results.mat'), 'case_data', 'pf', 'stab', 'ssa6');

make_powerflow_figure(pf, fullfile(outdir, 'powerflow_summary.png'));
make_lineflow_figure(pf, fullfile(outdir, 'line_power_flow.png'));
make_pdelta_figure(pf, fullfile(outdir, 'p_delta_curve.png'));
make_smib_reference_response(fullfile(outdir, 'smib_style_time_response.png'));
make_swing_equation_h_verify_figure(fullfile(outdir, 'swing_equation_h_verify.png'));
make_full_eig_figure(stab, ssa6, fullfile(outdir, 'full_eigenvalue_map.png'));
make_fault_simulation_figure(fullfile(outdir, 'fault_simulation.png'));

write_pf_table(pf, fullfile(outdir, 'table_powerflow_bus.tex'));
write_pf_summary(pf, fullfile(outdir, 'table_powerflow_summary.tex'));
write_stability_compare(stab, ssa6, fullfile(outdir, 'table_stability_compare.tex'));
write_full_e123(stab, ssa6, fullfile(outdir, 'table_e123_reproduction.tex'));
write_sixth_order_eigs(ssa6, fullfile(outdir, 'table_sixth_order_eigenvalues.tex'));
write_ssa_step_diagnostics(pf, ssa6, fullfile(outdir, 'table_ssa_step_diagnostics.tex'));
write_h_verification_table(fullfile(outdir, 'table_h_verification.tex'));

fprintf('Generated Kundur Ex12.6 report assets in %s\n', outdir);
fprintf('Power flow: converged=%d, iterations=%d, minV=%.4f, maxV=%.4f, Ploss=%.4f pu\n', ...
    pf.converged, pf.iterations, min(pf.bus_voltage), max(pf.bus_voltage), pf.P_loss_total);
fprintf('6th-order SSSA: eigenvalues=%d, DAE residual=%.3e\n', ...
    numel(ssa6.eigenvalues), ssa6.newton_residual);
end

function make_powerflow_figure(pf, path)
f = figure('Visible','off','Color','w','Position',[100 100 1100 720]);
tiledlayout(2,2,'Padding','compact','TileSpacing','compact');
bus = pf.external_bus_ids;
nexttile; bar(bus, pf.bus_voltage, 'FaceColor',[0.05 0.42 0.68]); grid on;
yline(1.0,'--','1.0 pu','Color',[0.8 0.2 0.15]); xlabel('Bus'); ylabel('|V| (pu)'); title('Bus Voltage Magnitudes'); style_axes(gca);
nexttile; bar(bus, pf.bus_angle_deg, 'FaceColor',[0.86 0.42 0.12]); grid on; xlabel('Bus'); ylabel('Angle (deg)'); title('Bus Voltage Angles'); style_axes(gca);
nexttile([1 2]); plot(1:pf.iterations, pf.mismatch_history(1:pf.iterations), '-o', 'Color',[0.08 0.25 0.45], 'LineWidth',2, 'MarkerFaceColor',[0.08 0.25 0.45]); grid on;
yline(1e-8,'--','tol = 1e-8','Color',[0.8 0.2 0.15]); xlabel('Iteration'); ylabel('Max mismatch (pu)'); title('Newton--Raphson Convergence'); style_axes(gca);
st = sgtitle('Kundur Example 12.6 Power-Flow Results','FontWeight','bold'); st.Color = [0.10 0.10 0.10];
exportgraphics(f, path, 'Resolution', 200); close(f);
end

function make_lineflow_figure(pf, path)
f = figure('Visible','off','Color','w','Position',[100 100 1100 620]);
endpoints = pf.line_endpoints;
labels = strings(size(endpoints,1),1);
seen = containers.Map('KeyType','char','ValueType','double');
for k = 1:size(endpoints,1)
    base_label = sprintf('%d-%d', endpoints(k,1), endpoints(k,2));
    if isKey(seen, base_label)
        seen(base_label) = seen(base_label) + 1;
    else
        seen(base_label) = 1;
    end
    if seen(base_label) > 1
        labels(k) = sprintf('%s#%d', base_label, seen(base_label));
    else
        labels(k) = base_label;
    end
end
bar(1:numel(labels), pf.line_flow_P(:,1), 'FaceColor',[0.18 0.50 0.25]); grid on;
xticks(1:numel(labels)); xticklabels(labels); xtickangle(35);
ylabel('P from-end (pu on 100 MVA)'); xlabel('Branch'); title('Active Power Flow by Branch');
set(gca,'FontSize',10); style_axes(gca);
exportgraphics(f, path, 'Resolution', 200); close(f);
end

function make_pdelta_figure(pf, path)
% Illustrative power-angle curve for the interarea tie using the solved
% bus-7 to bus-9 angle separation and the 400 MW transfer stated in Ex12.6.
P0 = 4.0; % pu on 100 MVA base = 400 MW
idx7 = find(pf.external_bus_ids == 7, 1); idx9 = find(pf.external_bus_ids == 9, 1);
delta0 = abs(deg2rad(pf.bus_angle_deg(idx7) - pf.bus_angle_deg(idx9)));
if delta0 < deg2rad(3); delta0 = deg2rad(20); end
Pmax_is = P0 / sin(delta0);
% Approximate one-circuit-out condition: equivalent transfer reactance rises,
% therefore Pmax falls. The value is selected so Pm=400 MW remains feasible
% and the operating angle moves to the right, matching Kundur Fig. 13.3 logic.
Pmax_os = 0.58 * Pmax_is;
if Pmax_os <= 1.05 * P0; Pmax_os = 1.18 * P0; end
delta_b = asin(P0 / Pmax_os);
deg = linspace(0, 180, 600);
P_is = Pmax_is * sin(deg2rad(deg));
P_os = Pmax_os * sin(deg2rad(deg));
f = figure('Visible','off','Color','w','Position',[100 100 980 620]);
plot(deg, P_is, 'LineWidth',2.4,'Color',[0 0 0]); hold on;
plot(deg, P_os, 'LineWidth',2.0,'Color',[0.25 0.25 0.25]);
plot(rad2deg(delta0), P0, 'ko', 'MarkerSize',8, 'MarkerFaceColor',[0 0 0]);
plot(rad2deg(delta_b), P0, 'ko', 'MarkerSize',8, 'MarkerFaceColor',[1 1 1]);
yline(P0,'k--','P_m = 400 MW','LineWidth',1.1, 'LabelHorizontalAlignment','left');
xline(rad2deg(delta0),'k--','\delta_a','LineWidth',1.0);
xline(rad2deg(delta_b),'k--','\delta_b','LineWidth',1.0);
text(104, Pmax_is*0.88, 'P_e with both circuits I/S', 'Color',[0 0 0], 'FontWeight','bold');
text(96, Pmax_os*0.86, 'P_e with one circuit O/S', 'Color',[0 0 0], 'FontWeight','bold');
text(rad2deg(delta0)-2, P0+0.20, 'a', 'Color',[0 0 0], 'FontWeight','bold', 'FontSize',12);
text(rad2deg(delta_b)-2, P0+0.20, 'b', 'Color',[0 0 0], 'FontWeight','bold', 'FontSize',12);
hold off; grid on;
xlim([0 180]); ylim([0 max(P_is)*1.08]);
xlabel('\delta (electrical degrees)'); ylabel('P_e (pu on 100 MVA)');
title('Power--Angle Relationship for the Interarea Tie'); style_axes(gca);
exportgraphics(f, path, 'Resolution', 200); close(f);
end

function make_mode_shape_figure(stab, path)
f = figure('Visible','off','Color','w','Position',[100 100 1100 420]);
shapes = {stab.mode_shapes.interarea, stab.mode_shapes.area1, stab.mode_shapes.area2};
titles = {'Interarea mode: Area 1 against Area 2', 'Area 1 local mode: G1 against G2', 'Area 2 local mode: G3 against G4'};
for p = 1:3
    ax = subplot(1,3,p); hold on; axis equal; grid on;
    xlim([-1.35 1.45]); ylim([-1.25 1.25]); xline(0,'k:'); yline(0,'k:');
    v = shapes{p};
    colors = ax.ColorOrder;
    for k = 1:numel(v)
        quiver(0,0,real(v(k)),imag(v(k)),0,'LineWidth',2.2,'MaxHeadSize',0.32,'Color',colors(k,:));
        ang = atan2(imag(v(k)), real(v(k)));
        r = 1.12;
        % place labels in angular sectors to avoid overlap
        if abs(ang) < pi/4 && real(v(k)) > 0
            ha = 'left';   offx =  0.08; offy =  0.04;
        elseif (abs(ang) > 3*pi/4) || (real(v(k)) < 0 && abs(imag(v(k))) < 0.4)
            ha = 'right';  offx = -0.08; offy =  0.04;
        elseif imag(v(k)) >= 0
            ha = 'center'; offx =  0.00; offy =  0.09;
        else
            ha = 'center'; offx =  0.00; offy = -0.09;
        end
        text(real(v(k))*r + offx, imag(v(k))*r + offy, stab.generator_labels{k}, ...
            'FontWeight','bold', 'Color', [0 0 0], 'HorizontalAlignment', ha, 'BackgroundColor','white', 'Margin',1);
    end
    title(titles{p}); xlabel('Real'); ylabel('Imaginary'); style_axes(gca);
end
st = sgtitle('Rotor-Speed Mode Shapes (Classical Manual Excitation)','FontWeight','bold'); st.Color = [0.10 0.10 0.10];
exportgraphics(f, path, 'Resolution', 200); close(f);
end

function make_smib_reference_response(path)
% Reuse the project's classical SMIB code to keep the report's response plot
% consistent with the GUI/standalone stability figures.
c = cases.case_kundur_smib_classical();
w0 = 2*pi*c.base_values.frequency_Hz;
op = smib.smib_classical_init(c.machine, c.network, c.operating);
sys = smib.smib_build_state_matrix('A', struct('H', c.machine.H, 'KD', 10, 'Ks', op.Ks, 'w0', w0));
fig = smib_plot_step_response(sys, struct('visible','off'));
exportgraphics(fig, path, 'Resolution', 200);
close(fig);
end

function make_smib_eig_vs_kd_figure(path)
% Eigenvalue locus of the classical SMIB model as the damping coefficient KD
% is swept from -10 to +20. The plot mimics a typical Kundur-style study of
% the effect of damping torque on swing-mode stability.
c = cases.case_kundur_smib_classical();
w0 = 2*pi*c.base_values.frequency_Hz;
op = smib.smib_classical_init(c.machine, c.network, c.operating);
H = c.machine.H;
Ks = op.Ks;

kd_vals = linspace(-10, 20, 61);
eig_real = nan(size(kd_vals));
eig_imag = nan(size(kd_vals));
for i = 1:numel(kd_vals)
    sys = smib.smib_build_state_matrix('A', struct('H',H,'KD',kd_vals(i),'Ks',Ks,'w0',w0));
    e = eig(sys.A);
    % upper half-plane pair
    e = e(imag(e) >= 0);
    if ~isempty(e)
        e = e(1);
    else
        e = mean(e);
    end
    eig_real(i) = real(e);
    eig_imag(i) = imag(e);
end

f = figure('Visible','off','Color','w','Position',[100 100 900 560]);
ax = axes('Parent', f); hold on; box on; grid on;
% stability regions
yl = [-7 7];
fill([min(eig_real)*1.1 0 0 min(eig_real)*1.1], [yl(1) yl(1) yl(2) yl(2)], ...
    [0.90 0.96 0.90], 'EdgeColor','none', 'FaceAlpha', 0.65);
fill([0 max(eig_real)*1.1 max(eig_real)*1.1 0], [yl(1) yl(1) yl(2) yl(2)], ...
    [0.96 0.90 0.90], 'EdgeColor','none', 'FaceAlpha', 0.65);
% KD locus with color gradient
scatter(eig_real, eig_imag, 55, kd_vals, 'filled', 'MarkerEdgeColor','k','LineWidth',0.5);
plot(eig_real, eig_imag, 'k-','LineWidth',1.2);
plot(eig_real([1 end]), eig_imag([1 end]), 'ko','MarkerFaceColor','y','MarkerSize',8);
xline(0, '--', 'Color', [0.75 0.18 0.18], 'LineWidth', 2);
% annotate KD extremes
for idx = [1 find(kd_vals==0) numel(kd_vals)]
    if eig_imag(idx) >= 0
        text(eig_real(idx)+0.04, eig_imag(idx)+0.15, sprintf('K_D = %d', round(kd_vals(idx))), ...
            'FontWeight','bold', 'Color', [0 0 0], 'FontSize', 11, 'BackgroundColor','white');
    end
end
text(-0.60, -5.5, 'stable region', 'Color', [0.15 0.45 0.15], 'FontWeight', 'bold', 'FontSize', 11);
text(0.45, -5.5, 'unstable region', 'Color', [0.65 0.15 0.15], 'FontWeight', 'bold', 'FontSize', 11);
text(0.10, 0.50, 'stability boundary', 'Color', [0.75 0.18 0.18], 'FontWeight', 'bold', 'FontSize', 11, 'Rotation', 90);
xlabel('Real part  \sigma  (1/s)');
ylabel('Imaginary part  \omega  (rad/s)');
title({'SMIB classical: eigenvalues vs K_D'; 'K_D swept from -10 to 20'}, 'FontWeight','bold');
ylim(yl);
xlim([min(eig_real)-0.15, max(eig_real)+0.15]);
style_axes(gca);
cb = colorbar(ax); cb.Label.String = 'K_D'; cb.Label.Color = [0.1 0.1 0.1]; cb.Color = [0.1 0.1 0.1]; cb.FontSize = 10;
exportgraphics(f, path, 'Resolution', 200); close(f);
end

function write_pf_table(pf, path)
fid = fopen(path, 'w'); cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '\\begin{tabular}{rrrrrr}\n\\toprule\nBus & Type & $|V|$ (pu) & Angle (deg) & $P_G$ (MW) & $Q_G$ (MVAr)\\\\\n\\midrule\n');
for k = 1:numel(pf.external_bus_ids)
    fprintf(fid, '%d & %d & %.4f & %.2f & %.1f & %.1f\\\\\n', pf.external_bus_ids(k), pf.bus_type(k), pf.bus_voltage(k), pf.bus_angle_deg(k), pf.P_generation(k)*100, pf.Q_generation(k)*100);
end
fprintf(fid, '\\bottomrule\n\\end{tabular}\n');
end

function write_pf_summary(pf, path)
fid = fopen(path, 'w'); cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '\\begin{tabular}{lr}\n\\toprule\nQuantity & Value\\\\\n\\midrule\n');
fprintf(fid, 'Converged & %d\\\\\n', pf.converged);
fprintf(fid, 'Iterations & %d\\\\\n', pf.iterations);
fprintf(fid, 'Minimum voltage & %.4f pu\\\\\n', min(pf.bus_voltage));
fprintf(fid, 'Maximum voltage & %.4f pu\\\\\n', max(pf.bus_voltage));
fprintf(fid, 'Total active generation & %.2f MW\\\\\n', pf.P_total_gen*100);
fprintf(fid, 'Total active load & %.2f MW\\\\\n', pf.P_total_load*100);
fprintf(fid, 'Total active loss & %.2f MW\\\\\n', pf.P_loss_total*100);
fprintf(fid, 'Total reactive generation & %.2f MVAr\\\\\n', pf.Q_total_gen*100);
fprintf(fid, 'Shunt reactive injection & %.2f MVAr\\\\\n', pf.Q_shunt_injected_total*100);
fprintf(fid, '\\bottomrule\n\\end{tabular}\n');
end

function write_stability_compare(stab, ssa6, path)
fid = fopen(path, 'w'); cleaner = onCleanup(@() fclose(fid));
% Compact table with frequency and damping percentage errors.
fprintf(fid, '\\begingroup\\scriptsize\\setlength{\\tabcolsep}{3pt}\n');
fprintf(fid, '\\begin{tabular}{l c c r r r r r r p{2.6cm}}\n\\toprule\n');
fprintf(fid, 'Mode & $\\lambda_{\\text{our}}$ & $\\lambda_{\\text{Kundur}}$ & $f_{\\text{our}}$ & $f_{\\text{Kundur}}$ & $\\varepsilon_f$\\%% & $\\zeta_{\\text{our}}$ & $\\zeta_{\\text{Kundur}}$ & $\\varepsilon_\\zeta$\\%% & Dominant state variables\\\\\n');
fprintf(fid, '\\midrule\n');
short_modes = {'Interarea', 'Area 1 local', 'Area 2 local'};
matched = match_sixth_order_modes(ssa6.eigenvalues, stab.modes);
for k = 1:numel(stab.modes)
    m = stab.modes(k);
    lam_our = matched(k);
    lam_ref = m.lambda;
    our_text = sprintf('%.3f$\\pm j$%.2f', real(lam_our), abs(imag(lam_our)));
    ref_text = sprintf('%.3f$\\pm j$%.2f', real(lam_ref), abs(imag(lam_ref)));
    f_our = abs(imag(lam_our)) / (2*pi);
    zeta_our = -real(lam_our) / (abs(lam_our) + eps);
    err_f = abs(f_our - m.book_frequency_Hz) / m.book_frequency_Hz * 100;
    err_zeta = abs(zeta_our - m.book_zeta) / m.book_zeta * 100;
    states = compact_states(m.dominant_states);
    fprintf(fid, '%s & %s & %s & %.3f & %.3f & %.1f & %.3f & %.3f & %.1f & %s\\\\\n', ...
        short_modes{k}, our_text, ref_text, f_our, m.book_frequency_Hz, ...
        err_f, zeta_our, m.book_zeta, err_zeta, latex_escape(states));
end
fprintf(fid, '\\bottomrule\n');
fprintf(fid, '\\multicolumn{10}{l}{\\scriptsize $\\varepsilon_f=|f_{\\text{our}}-f_{\\text{Kundur}}|/f_{\\text{Kundur}}\\times100\\%%$; $\\varepsilon_\\zeta=|\\zeta_{\\text{our}}-\\zeta_{\\text{Kundur}}|/\\zeta_{\\text{Kundur}}\\times100\\%%$.}\\\\\n');
fprintf(fid, '\\multicolumn{10}{l}{\\scriptsize Our modes are selected from the full 4-machine 6th-order Kundur/GENTPJ eigenvalues by nearest oscillation frequency.}\n');
fprintf(fid, '\\end{tabular}\n\\endgroup\n');
end

function matched = match_sixth_order_modes(eigenvalues, ref_modes)
osc = eigenvalues(imag(eigenvalues) > 1e-3);
osc_freq = abs(imag(osc)) / (2*pi);
matched = zeros(numel(ref_modes), 1);
used = false(numel(osc), 1);
for k = 1:numel(ref_modes)
    ref_freq = ref_modes(k).computed_frequency_Hz;
    dist = abs(osc_freq - ref_freq);
    dist(used) = inf;
    [~, idx] = min(dist);
    if isinf(dist(idx))
        matched(k) = NaN;
    else
        matched(k) = osc(idx);
        used(idx) = true;
    end
end
end

function write_full_e123(stab, ssa6, path)
% Full Table E12.3 comparison.  OURS columns are the closest matched
% eigenvalues computed by the current in-house solve; Kundur columns are the
% published reference.  No Kundur values are copied into OURS columns.
fid = fopen(path, 'w'); cleaner = onCleanup(@() fclose(fid));
T = stab.full_table;
[our_match, match_err] = match_e123_rows_to_solver(T, ssa6.eigenvalues(:));
fprintf(fid, '\\begingroup\\scriptsize\\setlength{\\tabcolsep}{2pt}\\renewcommand{\\arraystretch}{0.86}\n');
fprintf(fid, '\\begin{tabularx}{\\textwidth}{@{}r *{7}{r} >{\\raggedright\\arraybackslash}X@{}}\n\\toprule\n');
fprintf(fid, 'No. & Re$_o$ & Im$_o$ & Re$_K$ & Im$_K$ & $f_o$ & $f_K$ & $e_\\lambda$\\%% & Dominant state description\\\\\n');
fprintf(fid, '\\midrule\n');
for k = 1:size(T,1)
    [sigma, omega] = parse_eig_parts(T{k,2}, T{k,3});
    lam_o = our_match(k);
    if abs(imag(lam_o)) < 5e-5
        im_o = '--'; f_o = '--';
    else
        im_o = sprintf('%.3g', abs(imag(lam_o)));
        f_o = sprintf('%.4f', abs(imag(lam_o))/(2*pi));
    end
    if omega == 0
        im_k = '--';
    else
        im_k = latex_num_fmt(omega);
    end
    book_f = T{k,4};
    if strcmp(book_f, '-')
        f_k = '--';
    else
        book_f_val = str2double(book_f);
        if isnan(book_f_val), f_k = book_f;
        else, f_k = sprintf('%.4f', book_f_val); end
    end
    fprintf(fid, '%s & %.3g & %s & %s & %s & %s & %s & %.2f & %s\\\\\n', ...
        T{k,1}, real(lam_o), im_o, latex_num_fmt(sigma), im_k, f_o, f_k, match_err(k), latex_escape(T{k,6}));
end
fprintf(fid, '\\bottomrule\n');
fprintf(fid, '\\multicolumn{9}{@{}p{0.96\\textwidth}@{}}{\\tiny Diagnostic full-spectrum comparison only. OURS columns are actual solved eigenvalues matched to each Kundur row. Large errors in auxiliary/flux/reference rows are shown honestly and are not part of the headline benchmark. The $<0.5\\%%$ claim applies only to rotor-angle rows 4,5; 9,10; and 11,12 (see Table~\\ref{tab:compare}).}\\\\\n');
fprintf(fid, '\\end{tabularx}\n\\endgroup\n');
end

function [matched, err_pct] = match_e123_rows_to_solver(T, eigenvalues)
% Unique nearest-value matching from each compact Kundur row to one positive-
% imaginary (for pairs) or real/near-real (for real rows) in-house eigenvalue.
matched = nan(size(T,1),1);
err_pct = nan(size(T,1),1);
used = false(numel(eigenvalues),1);
for k = 1:size(T,1)
    [sigma, omega] = parse_eig_parts(T{k,2}, T{k,3});
    target = sigma + 1i*max(omega,0);
    cand = ~used;
    if omega > 1e-6
        cand = cand & imag(eigenvalues) >= -1e-8;
    else
        cand = cand & abs(imag(eigenvalues)) < 0.2;
    end
    if ~any(cand), cand = ~used; end
    dist = abs(eigenvalues - target);
    dist(~cand) = inf;
    [~,idx] = min(dist);
    matched(k) = eigenvalues(idx);
    used(idx) = true;
    denom = max(abs(target), 1e-3);
    err_pct(k) = abs(matched(k)-target)/denom*100;
end
end

function write_sixth_order_eigs(ssa6, path)
fid = fopen(path, 'w'); cleaner = onCleanup(@() fclose(fid));
lam = ssa6.eigenvalues(:);
[~, idx] = sort(real(lam), 'descend');
lam = lam(idx);
state_names = cellstr(string(ssa6.state_names(:)));
V = ssa6.mode_shapes;
V = V(:, idx);   % reorder to match sorted eigenvalues
fprintf(fid, '\\begingroup\\scriptsize\\setlength{\\tabcolsep}{4pt}\n');
fprintf(fid, '\\begin{tabular}{r r r r r p{4.5cm}}\n\\toprule\n');
fprintf(fid, 'No. & Re$(\\lambda)$ & Im$(\\lambda)$ & $f$ (Hz) & $\\zeta$ & Dominant state variables\\\\\n');
fprintf(fid, '\\midrule\n');
for k = 1:numel(lam)
    zeta = -real(lam(k)) / (abs(lam(k)) + eps);
    freq = abs(imag(lam(k))) / (2*pi);
    dom = dominant_state_label(V(:,k), state_names, 3);
    fprintf(fid, '%d & %.6f & %.6f & %.4f & %.4f & %s\\\\\n', ...
        k, real(lam(k)), imag(lam(k)), freq, zeta, dom);
end
fprintf(fid, '\\bottomrule\n');
fprintf(fid, '\\multicolumn{6}{l}{\\scriptsize Dominant state variables identified from eigenvector participation.}\n');
fprintf(fid, '\\end{tabular}\n\\endgroup\n');
end

function write_ssa_step_diagnostics(pf, ssa6, path)
fid = fopen(path, 'w'); cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '\\begingroup\\footnotesize\\setlength{\\tabcolsep}{5pt}\n');
fprintf(fid, '\\begin{tabular}{l l l}\n\\toprule\n');
fprintf(fid, 'Step & Check & Result\\\\\n\\midrule\n');
fprintf(fid, '1 & Power-flow operating point & converged=%d, iterations=%d\\\\\n', ...
    pf.converged, pf.iterations);
fprintf(fid, '2 & Full machine state vector & %d machines $\\times$ 6 states = %d states\\\\\n', ...
    ssa6.init.ng, numel(ssa6.init.x0));
fprintf(fid, '3 & DAE equilibrium residual & $\\lVert[f;g]\\rVert_2 = %.3e$\\\\\n', ...
    ssa6.newton_residual);
fprintf(fid, '4 & SSSA solve path & book-reproduction Kundur/GENTPJ via \\texttt{stability.multimachine\\_ssa}\\\\\n');
fprintf(fid, '5 & Full state matrix & $%d\\times%d$ matrix, %d eigenvalues\\\\\n', ...
    size(ssa6.Afull,1), size(ssa6.Afull,2), numel(ssa6.eigenvalues));
fprintf(fid, '6 & COI-reduced state matrix & $%d\\times%d$ matrix after removing the COI angle/speed reference\\\\\n', ...
    size(ssa6.Ared,1), size(ssa6.Ared,2));
fprintf(fid, '\\bottomrule\n\\end{tabular}\\endgroup\n');
end

function [sigma, omega] = parse_eig_parts(real_str, imag_str)
sigma = str2double(char(real_str));
if strcmp(char(imag_str), '-')
    omega = 0;
else
    tmp = strrep(char(imag_str), '+/-', '');
    omega = str2double(tmp);
    if isnan(omega); omega = 0; end
end
if isnan(sigma); sigma = 0; end
end

function s = latex_num_fmt(x)
if x == 0
    s = '0';
else
    s = sprintf('%0.3g', x);
end
end

function make_full_eig_figure(stab, ssa6, path)
%MAKE_FULL_EIG_FIGURE Plot the same matched data used in Table 7.
T = stab.full_table;
ref = zeros(size(T,1),1);
for k = 1:size(T,1)
    [sigma, omega] = parse_eig_parts(T{k,2}, T{k,3});
    ref(k) = sigma + 1i*max(omega,0);
end
[ours, ~] = match_e123_rows_to_solver(T, ssa6.eigenvalues(:));

f = figure('Visible','off','Color','w','Position',[100 100 1100 720]);
ax = axes('Parent', f); hold(ax,'on'); box(ax,'on'); grid(ax,'on');
all_re = [real(ref); real(ours)]; all_im = [imag(ref); -imag(ref); imag(ours); -imag(ours)];
xmin = min(all_re)*1.08; xmax = max(0.5, max(all_re)*1.08);
ymax = max(abs(all_im))*1.15; ymin = -ymax;
fill(ax,[xmin 0 0 xmin],[ymin ymin ymax ymax],[0.90 0.96 0.90],'EdgeColor','none','FaceAlpha',0.45,'HandleVisibility','off');
fill(ax,[0 xmax xmax 0],[ymin ymin ymax ymax],[0.96 0.90 0.90],'EdgeColor','none','FaceAlpha',0.45,'HandleVisibility','off');
xline(ax,0,'--','Color',[0.75 0.18 0.18],'LineWidth',1.4,'HandleVisibility','off');
% plot positive and mirrored negative imaginary members for compact table rows
hRef = plot(ax, real(ref), imag(ref), 'o', 'MarkerSize',8, 'LineWidth',1.3, 'Color',[0.13 0.55 0.82], 'MarkerFaceColor','none');
plot(ax, real(ref), -imag(ref), 'o', 'MarkerSize',8, 'LineWidth',1.3, 'Color',[0.13 0.55 0.82], 'MarkerFaceColor','none','HandleVisibility','off');
hOur = plot(ax, real(ours), imag(ours), 'x', 'MarkerSize',10, 'LineWidth',1.7, 'Color',[0.05 0.05 0.05]);
plot(ax, real(ours), -imag(ours), 'x', 'MarkerSize',10, 'LineWidth',1.7, 'Color',[0.05 0.05 0.05],'HandleVisibility','off');
xlabel(ax,'Real part \sigma (1/s)'); ylabel(ax,'Imaginary part \omega (rad/s)');
title(ax,'Table 7 matched eigenvalues: OURS solved values (x) vs Kundur E12.3 (o)');
legend(ax,[hRef hOur], {'Kundur Table E12.3','OURS actual matched solve'}, 'Location','best');
xlim(ax,[xmin xmax]); ylim(ax,[ymin ymax]); style_axes(ax);
exportgraphics(f, path, 'Resolution', 200); close(f);
end

function make_swing_equation_h_verify_figure(path)
% Verify the H-dependent swing equation used in the latest 6th-order TS engine:
%   d(Deltaomega_i)/dt = (Pm_i - Pe_i - D_i*Deltaomega_i)/(2*Hsys_i)
res = run_latest_kundur_ts(5);
t = res.t(:);
dt = mean(diff(t));
omega_dot_num = zeros(size(res.omega));
for k = 1:size(res.omega,2)
    omega_dot_num(:,k) = gradient(res.omega(:,k), dt);
end
H = res.H_sys(:)';
D = damping_vector(res);
Pm = res.Pm(:)';
rhs = zeros(size(res.omega));
for k = 1:size(res.omega,2)
    rhs(:,k) = (Pm(k) - res.Pe_pu(:,k) - D(k)*res.omega(:,k)) ./ (2*H(k));
end
[fault_on, fault_off] = fault_window(res);
labels = {'G1','G2','G3','G4'};
colors = [0.00 0.28 0.60; 0.82 0.25 0.05; 0.52 0.43 0.00; 0.35 0.16 0.58];
f = figure('Visible','off','Color','w','Position',[80 80 1300 900]);
tl = tiledlayout(f,2,2,'Padding','compact','TileSpacing','compact');
for k = 1:4
    ax = nexttile(tl); hold(ax,'on'); box(ax,'on'); grid(ax,'on');
    plot(ax, t, omega_dot_num(:,k), '-', 'LineWidth',1.6, 'Color',colors(k,:));
    plot(ax, t, rhs(:,k), '--', 'LineWidth',1.25, 'Color',[0 0 0]);
    mark_fault(ax, fault_on, fault_off);
    err = sqrt(mean((omega_dot_num(:,k) - rhs(:,k)).^2));
    title(ax, sprintf('%s: inertia H_{sys}=%.3g s, RMS error=%.2e', labels{k}, H(k), err), 'FontWeight','bold');
    xlabel(ax,'Time (s)'); ylabel(ax,'d\Delta\omega/dt (pu/s)');
    legend(ax, {'slope from simulated $\Delta\omega(t)$','power-imbalance RHS using $H$'}, 'Interpreter','latex', 'Location','best');
    style_axes(ax);
end
st = sgtitle(tl, 'Verification of swing equation using the inertia constant H in the latest 6th-order TS engine', 'FontWeight','bold');
st.Color = [0.10 0.10 0.10];
exportgraphics(f, path, 'Resolution', 220, 'BackgroundColor','white');
close(f);
end

function write_h_verification_table(path)
% Numerical diagnostics for Figure hverify.
res = run_latest_kundur_ts(5);
t = res.t(:);
dt = mean(diff(t));
omega_dot_num = zeros(size(res.omega));
for k = 1:size(res.omega,2)
    omega_dot_num(:,k) = gradient(res.omega(:,k), dt);
end
H = res.H_sys(:)';
D = damping_vector(res);
Pm = res.Pm(:)';
rhs = zeros(size(res.omega));
for k = 1:size(res.omega,2)
    rhs(:,k) = (Pm(k) - res.Pe_pu(:,k) - D(k)*res.omega(:,k)) ./ (2*H(k));
end
labels = {'G1','G2','G3','G4'};
fid = fopen(path, 'w'); cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '\\begingroup\\footnotesize\\setlength{\\tabcolsep}{5pt}\n');
fprintf(fid, '\\begin{tabular}{l r r r}\n\\toprule\n');
fprintf(fid, 'Generator & $H_{\\mathrm{sys}}$ (s) & RMS error (pu/s) & Max error (pu/s)\\\\\n');
fprintf(fid, '\\midrule\n');
for k = 1:4
    e = omega_dot_num(:,k) - rhs(:,k);
    fprintf(fid, '%s & %.3f & %.3e & %.3e\\\\\n', labels{k}, H(k), sqrt(mean(e.^2)), max(abs(e)));
end
fprintf(fid, '\\bottomrule\n');
fprintf(fid, '\\multicolumn{4}{l}{\\scriptsize Error = finite-difference slope of simulated $\\Delta\\omega_i$ minus Kundur swing-equation RHS from the latest TS engine.}\\\\\n');
fprintf(fid, '\\end{tabular}\n\\endgroup\n');
end

function make_fault_simulation_figure(path)
res = run_latest_kundur_ts(5);
t = res.t;
labels = {'G1','G2','G3','G4'};
colors = [0.00 0.28 0.60; 0.82 0.25 0.05; 0.52 0.43 0.00; 0.35 0.16 0.58];
f = figure('Visible','off','Color','w','Position',[80 80 1400 900]);
tl = tiledlayout(f, 2, 2, 'Padding','compact', 'TileSpacing','compact');

[fault_on, fault_off, fault_duration] = fault_window(res);

ax = nexttile(tl); hold(ax,'on'); box(ax,'on'); grid(ax,'on');
delta_rel = res.delta - res.delta(:,1);
% Plot disturbance response: subtract the pre-fault relative angle so every
% curve starts from zero. This is easier to interpret than plotting the
% absolute operating-point angle separation.
delta_dev_deg = rad2deg(delta_rel - delta_rel(1,:));
plot(ax, t, delta_dev_deg(:,2), 'LineWidth',1.9, 'Color',colors(2,:));
plot(ax, t, delta_dev_deg(:,3), 'LineWidth',1.9, 'Color',colors(3,:));
plot(ax, t, delta_dev_deg(:,4), 'LineWidth',1.9, 'Color',colors(4,:));
mark_fault(ax, fault_on, fault_off);
xlabel(ax,'Time (s)'); ylabel(ax,'Rotor angle deviation (deg)');
title(ax,'Rotor angle deviations from pre-fault relative angles');
legend(ax, {'G2-G1','G3-G1','G4-G1'}, 'Location','best', 'TextColor',[0 0 0], 'Color','w');
style_axes(ax);

ax = nexttile(tl); hold(ax,'on'); box(ax,'on'); grid(ax,'on');
for k = 1:4
    plot(ax, t, res.Pgen(:,k), 'LineWidth',1.5, 'Color',colors(k,:));
end
mark_fault(ax, fault_on, fault_off);
xlabel(ax,'Time (s)'); ylabel(ax,'P_{gen} (MW)'); title(ax,'Generator active power');
legend(ax, labels, 'Location','best', 'TextColor',[0 0 0], 'Color','w');
style_axes(ax);

ax = nexttile(tl); hold(ax,'on'); box(ax,'on'); grid(ax,'on');
buses_to_plot = res.bus_ids(:)';
line_styles = {'-','-','-','-','-','-','-','-','-','-','-'};
for kk = 1:numel(buses_to_plot)
    bidx = find(res.bus_ids == buses_to_plot(kk), 1);
    lw = 1.10;
    if buses_to_plot(kk) == res.fault_bus
        lw = 2.25; % highlight the faulted bus
    end
    plot(ax, t, res.Vbus(:,bidx), line_styles{kk}, 'LineWidth',lw);
end
mark_fault(ax, fault_on, fault_off);
xlabel(ax,'Time (s)'); ylabel(ax,'|V| (pu)'); title(ax,'Bus voltage magnitudes (all buses)'); ylim(ax,[0 1.2]);
lgd = legend(ax, compose('Bus %d', buses_to_plot), 'Location','eastoutside', 'TextColor',[0 0 0], 'Color','w');
lgd.NumColumns = 1;
style_axes(ax);

ax = nexttile(tl); hold(ax,'on'); box(ax,'on'); grid(ax,'on');
% Plot the speed variables with the same reference as the angle plot.
% Since d(delta_i-delta_1)/dt = omega_s*(Deltaomega_i-Deltaomega_1),
% these three traces are the derivative-consistent counterparts of G2-G1,
% G3-G1, and G4-G1 in the top-left panel.
omega_rel = res.omega - res.omega(:,1);
plot(ax, t, omega_rel(:,2), 'LineWidth',1.5, 'Color',colors(2,:));
plot(ax, t, omega_rel(:,3), 'LineWidth',1.5, 'Color',colors(3,:));
plot(ax, t, omega_rel(:,4), 'LineWidth',1.5, 'Color',colors(4,:));
mark_fault(ax, fault_on, fault_off);
xlabel(ax,'Time (s)'); ylabel(ax,'\Delta\omega_i-\Delta\omega_1 (pu)'); title(ax,'Relative rotor speed deviations');
legend(ax, {'G2-G1','G3-G1','G4-G1'}, 'Location','best', 'TextColor',[0 0 0], 'Color','w');
style_axes(ax);

st = sgtitle(tl, sprintf('Kundur Two-Area: bus-%d solid 3-phase fault (%.2f--%.2f s), latest TS engine', res.fault_bus, fault_on, fault_off), 'FontWeight','bold');
st.Color = [0.10 0.10 0.10];
exportgraphics(f, path, 'Resolution', 220, 'BackgroundColor','white');
close(f);
end

function res = run_latest_kundur_ts(t_end)
% Latest report transient path: common case-agnostic engine + 6th-order GENTPJ.
if nargin < 1 || isempty(t_end), t_end = 5; end
opt = struct('model','genpj6', 't_end',t_end, 'dt',1e-3, ...
    'fault_bus',8, 't_fault',1.0, 't_clear',1.05, 'Zf',[], ...
    'method','trapezoidal', 'corrector_iter',1, 'load_model','cz', ...
    'verbose',false);
res = stability.ts_simulate(cases.case_kundur_two_area_classical(), opt);
end

function [fault_on, fault_off, fault_duration] = fault_window(res)
if isfield(res,'t_fault')
    fault_on = res.t_fault;
    fault_off = res.t_clear;
elseif isfield(res,'tfault_start')
    fault_on = res.tfault_start;
    fault_off = res.tfault_start + res.tclear;
else
    error('generate_kundur_ex126_report:missingFaultWindow','Transient result has no fault timing fields.');
end
fault_duration = fault_off - fault_on;
end

function D = damping_vector(res)
if isfield(res,'D_sys')
    D = res.D_sys(:)';
else
    D = zeros(1,size(res.omega,2));
end
end

function mark_fault(ax, fault_on, fault_off)
% Short fault windows make xline labels overlap, so use an unobtrusive shaded
% interval plus unlabeled dashed boundaries.
yl = ylim(ax);
p = patch(ax, [fault_on fault_off fault_off fault_on], [yl(1) yl(1) yl(2) yl(2)], ...
    [1.0 0.88 0.88], 'EdgeColor','none', 'FaceAlpha',0.35, 'HandleVisibility','off');
try, uistack(p,'bottom'); catch, end %#ok<CTCH>
ylim(ax, yl);
xline(ax, fault_on, '--', 'Color',[0.70 0.10 0.10], 'LineWidth',1.2, 'HandleVisibility','off');
xline(ax, fault_off, '--', 'Color',[0.70 0.10 0.10], 'LineWidth',1.2, 'HandleVisibility','off');
end

function style_axes(ax)
ax.Color = [1 1 1];
ax.XColor = [0.10 0.10 0.10];
ax.YColor = [0.10 0.10 0.10];
ax.GridColor = [0.82 0.82 0.82];
ax.GridAlpha = 0.55;
ax.LineWidth = 0.9;
ax.FontSize = 10;
ax.Title.Color = [0.10 0.10 0.10];
ax.XLabel.Color = [0.10 0.10 0.10];
ax.YLabel.Color = [0.10 0.10 0.10];
end

function s = latex_escape(s)
s = char(s);
s = strrep(s, '_', '\_');
s = strrep(s, '+/-', '$\pm$');
s = strrep(s, '~', '$\sim$');
s = strrep(s, 'Delta ', '$\Delta$ ');
s = strrep(s, ' and ', ' / ');
s = strrep(s, 'G1, G2 against G3, G4', 'G1,G2 vs G3,G4');
s = strrep(s, 'G1 against G2', 'G1 vs G2');
s = strrep(s, 'G3 against G4', 'G3 vs G4');
end

function s = compact_states(s)
s = char(s);
% normalize common unicode/literal Delta forms
s = regexprep(s, 'Δ\s*omega', '$\\Delta\\omega$');
s = regexprep(s, 'Delta\s*omega', '$\\Delta\\omega$');
s = regexprep(s, 'Δ\s*delta', '$\\Delta\\delta$ ');
s = regexprep(s, 'Delta\s*delta', '$\\Delta\\delta$ ');
s = regexprep(s, ' of ', ' ');
s = regexprep(s, ' against ', ' vs ');
end

function s = dominant_state_label(v, state_names, n_top)
% Return a LaTeX string listing the top n_top most dominant states.
mag = abs(v);
[~, ord] = sort(mag, 'descend');
parts = {};
for j = 1:min(n_top, numel(ord))
    if mag(ord(j)) > 0.05 * mag(ord(1))
        nm = char(state_names{ord(j)});
        % Wrap in math mode for LaTeX table
        parts{end+1} = ['$' nm '$'];
    end
end
if isempty(parts)
    s = 'mixed';
else
    s = strjoin(parts, ', ');
end
end

function s = flux_mode_label(dom)
% Preserve the physical d/q flux interpretation for Kundur Table E12.3
% rows 13--24 while still showing the generator-specific GENTPJ states.
if contains(dom, '_{d,') && contains(dom, '_{q,')
    prefix = 'd/q-axis flux states: ';
elseif contains(dom, '_{q,')
    prefix = 'q-axis flux states: ';
elseif contains(dom, '_{d,')
    prefix = 'd-axis flux states: ';
else
    prefix = 'd/q-axis flux states: ';
end
s = [prefix dom];
end
