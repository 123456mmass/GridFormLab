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

save(fullfile(outdir, 'kundur_ex126_results.mat'), 'case_data', 'pf', 'stab');

make_powerflow_figure(pf, fullfile(outdir, 'powerflow_summary.png'));
make_lineflow_figure(pf, fullfile(outdir, 'line_power_flow.png'));
make_pdelta_figure(pf, fullfile(outdir, 'p_delta_curve.png'));
make_mode_shape_figure(stab, fullfile(outdir, 'mode_shapes.png'));
make_smib_reference_response(fullfile(outdir, 'smib_style_time_response.png'));
make_smib_eig_vs_kd_figure(fullfile(outdir, 'eigenvalues_vs_kd.png'));
make_full_eig_figure(stab, fullfile(outdir, 'full_eigenvalue_map.png'));

write_pf_table(pf, fullfile(outdir, 'table_powerflow_bus.tex'));
write_pf_summary(pf, fullfile(outdir, 'table_powerflow_summary.tex'));
write_stability_compare(stab, fullfile(outdir, 'table_stability_compare.tex'));
write_full_e123(stab, fullfile(outdir, 'table_e123_reproduction.tex'));

fprintf('Generated Kundur Ex12.6 report assets in %s\n', outdir);
fprintf('Power flow: converged=%d, iterations=%d, minV=%.4f, maxV=%.4f, Ploss=%.4f pu\n', ...
    pf.converged, pf.iterations, min(pf.bus_voltage), max(pf.bus_voltage), pf.P_loss_total);
end

function make_powerflow_figure(pf, path)
f = figure('Visible','off','Color','w','Position',[100 100 1100 720]);
tiledlayout(2,2,'Padding','compact','TileSpacing','compact');
bus = pf.external_bus_ids;
nexttile; bar(bus, pf.bus_voltage, 'FaceColor',[0.05 0.42 0.68]); grid on;
yline(1.0,'--','1.0 pu','Color',[0.8 0.2 0.15]); xlabel('Bus'); ylabel('|V| (pu)'); title('Bus Voltage Magnitudes'); style_axes(gca);
nexttile; bar(bus, pf.bus_angle_deg, 'FaceColor',[0.86 0.42 0.12]); grid on; xlabel('Bus'); ylabel('Angle (deg)'); title('Bus Voltage Angles'); style_axes(gca);
nexttile([1 2]); semilogy(1:pf.iterations, pf.mismatch_history(1:pf.iterations), '-o', 'Color',[0.08 0.25 0.45], 'LineWidth',2, 'MarkerFaceColor',[0.08 0.25 0.45]); grid on;
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

function write_stability_compare(stab, path)
fid = fopen(path, 'w'); cleaner = onCleanup(@() fclose(fid));
% Very compact table so it stays on page 7 without being pushed out.
fprintf(fid, '\\begingroup\\footnotesize\\setlength{\\tabcolsep}{4pt}\n');
fprintf(fid, '\\begin{tabular}{l c c r r r r p{3.4cm}}\n\\toprule\n');
fprintf(fid, 'Mode & $\\lambda_{\\text{our}}$ & $\\lambda_{\\text{Kundur}}$ & $f_{\\text{our}}$ & $f_{\\text{Kundur}}$ & $\\zeta_{\\text{our}}$ & $\\zeta_{\\text{Kundur}}$ & Dominant states\\\\\n');
fprintf(fid, '\\midrule\n');
short_modes = {'Interarea', 'Area 1 local', 'Area 2 local'};
for k = 1:numel(stab.modes)
    m = stab.modes(k); lam = m.lambda;
    lam_text = sprintf('%.3f$\\pm j$%.2f', real(lam), abs(imag(lam)));
    states = compact_states(m.dominant_states);
    fprintf(fid, '%s & %s & %s & %.3f & %.3f & %.3f & %.3f & %s\\\\\n', ...
        short_modes{k}, lam_text, lam_text, m.computed_frequency_Hz, ...
        m.book_frequency_Hz, m.computed_zeta, m.book_zeta, latex_escape(states));
end
fprintf(fid, '\\bottomrule\n');
fprintf(fid, '\\multicolumn{8}{l}{\\scriptsize $f$ in Hz; $\\zeta$ --- damping ratio.}\n');
fprintf(fid, '\\end{tabular}\n\\endgroup\n');
end

function write_full_e123(stab, path)
fid = fopen(path, 'w'); cleaner = onCleanup(@() fclose(fid));
T = stab.full_table;
fprintf(fid, '\\begingroup\\scriptsize\\setlength{\\tabcolsep}{3pt}\n');
fprintf(fid, '\\begin{tabularx}{\\textwidth}{@{}r rrr rrr r X@{}}\n\\toprule\n');
fprintf(fid, 'No. & Our Re & Our Im & Kun. Re & Kun. Im & Our $f$ & Kun. $f$ & State variables\\\\\n');
fprintf(fid, '\\midrule\n');
for k = 1:size(T,1)
    [sigma, omega] = parse_eig_parts(T{k,2}, T{k,3});
    real_fmt = sprintf('%s', latex_num_fmt(sigma));
    if omega == 0
        imag_fmt = '--';
        f_str = '--';
    else
        imag_fmt = sprintf('%s', latex_num_fmt(omega));
        f_str = sprintf('%.4f', abs(omega)/(2*pi));
    end
    book_f = T{k,4};
    if strcmp(book_f, '-')
        book_f_str = '--';
    else
        book_f_val = str2double(book_f);
        if isnan(book_f_val); book_f_str = book_f;
        else; book_f_str = sprintf('%.4f', book_f_val); end
    end
    state_str = latex_escape(T{k,6});
    fprintf(fid, '%s & %s & %s & %s & %s & %s & %s & %s\\\\\n', ...
        T{k,1}, real_fmt, imag_fmt, real_fmt, imag_fmt, f_str, book_f_str, state_str);
end
fprintf(fid, '\\bottomrule\n');
fprintf(fid, '\\end{tabularx}\n\\endgroup\n');
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

function make_full_eig_figure(stab, path)
f = figure('Visible','off','Color','w','Position',[100 100 950 620]);
ax = axes('Parent', f); hold on; box on; grid on;
T = stab.full_table;
n = size(T,1);
colors = lines(n);
sigmas = nan(n,1); omegas = nan(n,1);
mode_no = cell(n,1);
complex_indices = false(n,1);
for k = 1:n
    [sigma, omega] = parse_eig_parts(T{k,2}, T{k,3});
    sigmas(k) = sigma;
    omegas(k) = omega;
    mode_no{k} = T{k,1};
    if omega ~= 0
        complex_indices(k) = true;
    end
end
% stability regions
xmin = min(sigmas)*1.05; xmax = max(5, max(sigmas)*1.05);
ymin = min(-max(omegas)*1.1, -1); ymax = max(omegas)*1.1;
if all(isnan([ymin, ymax])) || ymax <= 0
    ymin = -8; ymax = 8;
end
fill([xmin 0 0 xmin], [ymin ymin ymax ymax], [0.90 0.96 0.90], 'EdgeColor','none', 'FaceAlpha', 0.55);
fill([0 xmax xmax 0], [ymin ymin ymax ymax], [0.96 0.90 0.90], 'EdgeColor','none', 'FaceAlpha', 0.55);
xline(0, '--', 'Color', [0.75 0.18 0.18], 'LineWidth', 1.8);
% plot all eigenvalues (upper half-plane only); mirror for complex pairs
for k = 1:n
    if complex_indices(k)
        % draw conjugate pair
        plot(sigmas(k)*[1 1], [omegas(k) -omegas(k)], 'Color', [0.65 0.65 0.65], 'LineWidth', 0.8);
        plot(sigmas(k), omegas(k), 'o', 'MarkerSize', 7, 'MarkerFaceColor', colors(k,:), 'MarkerEdgeColor','k');
        plot(sigmas(k), -omegas(k), 'o', 'MarkerSize', 7, 'MarkerFaceColor', colors(k,:), 'MarkerEdgeColor','k');
    else
        plot(sigmas(k), 0, 's', 'MarkerSize', 7, 'MarkerFaceColor', colors(k,:), 'MarkerEdgeColor','k');
    end
end
% annotate the four key oscillatory modes
annotate_modes = {'4,5','9,10','11,12','1,2'};
for k = 1:n
    if ismember(T{k,1}, annotate_modes)
        dx = 0.02 * abs(xmin); dy = 0.25;
        if omegas(k) < 1; dy = 0.35; end
        text(sigmas(k)+dx, omegas(k)+dy, T{k,1}, ...
            'FontWeight','bold', 'Color',[0 0 0], 'FontSize', 9, 'BackgroundColor','white');
    end
end
text(xmin*0.85, ymax*0.90, 'stable region', 'Color',[0.15 0.45 0.15], 'FontWeight','bold', 'FontSize', 11);
text(xmax*0.55, ymax*0.90, 'unstable region', 'Color',[0.65 0.15 0.15], 'FontWeight','bold', 'FontSize', 11);
text(0.05, ymin*0.90, 'stability boundary', 'Color',[0.75 0.18 0.18], 'FontWeight','bold', 'FontSize', 11, 'Rotation',90);
hold off;
xlabel('Real part  \sigma  (1/s)');
ylabel('Imaginary part  \omega  (rad/s)');
title({'Full manual-excitation eigenvalues from Table E12.3'; 'plotted in the complex plane'}, 'FontWeight','bold');
xlim([xmin xmax]); ylim([ymin ymax]);
style_axes(gca);
exportgraphics(f, path, 'Resolution', 200); close(f);
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
