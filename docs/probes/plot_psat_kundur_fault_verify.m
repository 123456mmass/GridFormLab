function plot_psat_kundur_fault_verify()
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
outdir = fullfile(root, 'docs', 'source', 'figures', 'kundur_ex126');
load(fullfile(outdir, 'psat_kundur_fault_verify.mat'), 't', 'delta_deg_rel', 'omega_dev');
fig = figure('Visible','off','Color','w','Position',[100 100 1100 460]);
tiledlayout(fig,1,2,'Padding','compact','TileSpacing','compact');
ax1 = nexttile; plot(ax1,t,delta_deg_rel(:,2:end),'LineWidth',1.4); grid(ax1,'on');
xlabel(ax1,'Time (s)'); ylabel(ax1,'Rotor angle relative to G1 (deg)');
title(ax1,'PSAT Kundur fault: rotor angles'); legend(ax1,{'G2-G1','G3-G1','G4-G1'},'Location','best');
ax2 = nexttile; plot(ax2,t,omega_dev,'LineWidth',1.4); grid(ax2,'on');
xlabel(ax2,'Time (s)'); ylabel(ax2,'\Delta\omega (pu)');
title(ax2,'PSAT Kundur fault: speed deviations'); legend(ax2,{'G1','G2','G3','G4'},'Location','best');
sgtitle(fig,'PSAT verification: built-in Kundur two-area fault, trapezoidal integration');
exportgraphics(fig, fullfile(outdir, 'psat_kundur_fault_verify.png'), 'Resolution', 200);
close(fig);
end
