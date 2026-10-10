% Backup figures for the v15 deck, all from the delivered scenario cache
% output/diagnostics/ieee14_scenario_suite/sg_fault_cycle160.mat.
% Pure cache reader: nothing is simulated or re-solved. Style follows
% figure-style-contract (Helvetica, tex interpreter, dashed grid, box off).
%
%   backup_b1_switch_zoom.png   IBR2 i_d, i_q (top) and V_dc (bottom), +-0.5 s
%                               around the GFL->GFM commitment at t = 22.0887 s.
%   backup_b5_fault_current.png |I| per IBR with the I_max = 1.20 pu rule
%                               (top) and |V| at faulted bus 9 (bottom),
%                               t = 59.5..61.0 s.
%   backup_b6_return.png        mode m_i of IBR2 (top, with T_minimum_hold and
%                               T_lockout windows) and |V| at buses 1/2
%                               (bottom), t = 98..120 s.
%
% Run from the repository root with the project on the MATLAB path.
function generate_backup_bslides_figures()
cache = fullfile('output','diagnostics','ieee14_scenario_suite','sg_fault_cycle160.mat');
S = load(cache);
r = S.result;
t = r.t(:);
odir = fullfile('docs','source','figures','ieee14_scenario_suite');

names = cellfun(@char, r.device_ids, 'UniformOutput', false);
k2 = find(strcmp(names,'IBR2'),1);          % device column of deck IBR_1
iabs = r.device_current_magnitude.';        % [samples x 5], SG1 + 4 IBR
Vbus = r.bus_voltage_magnitude.';           % [samples x 14]
b9 = find(r.bus_ids == 9, 1);
b1 = find(r.bus_ids == 1, 1);
b2 = find(r.bus_ids == 2, 1);

% IBR2 states inside the composite state vector (SG1 six, then four 17-state
% IBRs in device order; verified against the stored state names).
devs = r.equilibrium.devices;
base = sum(cellfun(@numel, {devs(1:k2-1).state_names}));
sn = devs(k2).state_names;
col = @(nm) base + find(strcmp(sn,nm),1);
x = r.x_traj;
if size(x,2) == numel(t), x = x.'; end
i_d = x(:,col('i_d')); i_q = x(:,col('i_q')); vdc = x(:,col('V_dc'));

mode = strings(numel(t),1);
mh = r.device_modes_history;                % [5 x samples] cell
for i = 1:numel(t), mode(i) = string(mh{k2,i}); end
is_gfm = mode == "GFM";

t_switch = 22.088670861705086;              % event_log gfm_support_augment
t_trip = r.t_sg_trip;                       % 20 s
t_release = 25.302555368221647;             % event_log gfm_support_release
t_reclose = r.actual_reclose_time;          % 102.3627 s
t_reselect = 116.2379148446256;             % event_log sg_reselection
Imax = 1.20;

FN = 'Helvetica'; fs = 10;

% ---- B1: switching zoom ----------------------------------------------------
f1 = figure('Color','w','Units','inches','Position',[1 1 6.2 4.4]);
tl = tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
nexttile; hold on
plot(t, i_d, '-', 'LineWidth', 1.0);
plot(t, i_q, '-', 'LineWidth', 1.0);
xline(t_trip, ':', 'LineWidth', 1.0);
xline(t_switch, '-.', 'LineWidth', 1.0);
xline(t_release, ':', 'LineWidth', 1.0);
xlim([t_switch-0.5 t_switch+0.5]);
ylabel('current (pu)');
legend({'$i_d$','$i_q$'}, 'Interpreter','latex','Location','southeast','Box','off');
set(gca,'FontName',FN,'FontSize',fs,'TickLabelInterpreter','tex', ...
    'XGrid','on','YGrid','on','GridLineStyle','--','Box','off','TickDir','out');
title('IBR$_1$ around the GFL$\rightarrow$GFM commitment at $t=22.0887$ s', ...
    'Interpreter','latex','FontSize',fs);
nexttile; hold on
plot(t, vdc, '-', 'LineWidth', 1.0);
xline(t_trip, ':', 'LineWidth', 1.0);
xline(t_switch, '-.', 'LineWidth', 1.0);
xline(t_release, ':', 'LineWidth', 1.0);
xlim([t_switch-0.5 t_switch+0.5]);
ylabel('$V_{dc}$ (pu)','Interpreter','latex');
xlabel('$t$ (s)','Interpreter','latex');
set(gca,'FontName',FN,'FontSize',fs,'TickLabelInterpreter','tex', ...
    'XGrid','on','YGrid','on','GridLineStyle','--','Box','off','TickDir','out');
exportgraphics(f1, fullfile(odir,'backup_b1_switch_zoom.png'), 'Resolution', 300);
close(f1);

% ---- B5: fault current vs I_max and bus-9 voltage --------------------------
f5 = figure('Color','w','Units','inches','Position',[1 1 6.2 4.4]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
nexttile; hold on
for k = 2:5
    plot(t, iabs(:,k), '-', 'LineWidth', 1.0);
end
yline(Imax, '--', 'LineWidth', 1.0);
xline(60, ':', 'LineWidth', 1.0);
xline(60.15, ':', 'LineWidth', 1.0);
xlim([59.5 61.0]); ylim([0 1.5]);
ylabel('$|I|$ (pu)','Interpreter','latex');
legend({'IBR$_1$','IBR$_2$','IBR$_3$','IBR$_4$','$I_{max}$'}, ...
    'Interpreter','latex','Location','northeast','Box','off');
set(gca,'FontName',FN,'FontSize',fs,'TickLabelInterpreter','tex', ...
    'XGrid','on','YGrid','on','GridLineStyle','--','Box','off','TickDir','out');
title('converter currents during the 150 ms bus-9 fault', 'Interpreter','latex','FontSize',fs);
nexttile; hold on
plot(t, Vbus(:,b9), '-', 'LineWidth', 1.0);
xline(60, ':', 'LineWidth', 1.0);
xline(60.15, ':', 'LineWidth', 1.0);
xlim([59.5 61.0]);
ylabel('$|V_9|$ (pu)','Interpreter','latex');
xlabel('$t$ (s)','Interpreter','latex');
set(gca,'FontName',FN,'FontSize',fs,'TickLabelInterpreter','tex', ...
    'XGrid','on','YGrid','on','GridLineStyle','--','Box','off','TickDir','out');
exportgraphics(f5, fullfile(odir,'backup_b5_fault_current.png'), 'Resolution', 300);
close(f5);

% ---- B6: return to GFL ------------------------------------------------------
f6 = figure('Color','w','Units','inches','Position',[1 1 6.2 4.4]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
nexttile; hold on
yy = double(is_gfm);
stairs(t, yy, '-', 'LineWidth', 1.2);
xline(100, ':', 'LineWidth', 1.0);
xline(t_reclose, ':', 'LineWidth', 1.0);
xline(t_reselect, '-.', 'LineWidth', 1.0);
xp = [t_reselect-1.0 t_reselect t_reselect t_reselect-1.0];
patch(xp, [0 0 1.25 1.25], [0.85 0.90 1.0], 'EdgeColor','none', 'FaceAlpha', 0.8);
text(t_reselect-0.5, 1.12, '$T_{hold}$', 'Interpreter','latex','FontSize',fs-1, ...
    'HorizontalAlignment','right');
xp = [t_reselect t_reselect+2.0 t_reselect+2.0 t_reselect];
patch(xp, [0 0 1.25 1.25], [1.0 0.88 0.85], 'EdgeColor','none', 'FaceAlpha', 0.8);
text(t_reselect+1.0, 1.12, '$T_{lock}$', 'Interpreter','latex','FontSize',fs-1, ...
    'HorizontalAlignment','center');
xlim([98 120]); ylim([-0.1 1.25]); yticks([0 1]); yticklabels({'GFL','GFM'});
set(gca,'FontName',FN,'FontSize',fs,'TickLabelInterpreter','tex', ...
    'XGrid','on','YGrid','on','GridLineStyle','--','Box','off','TickDir','out');
title('IBR$_1$ mode through the SG return (dotted: offer, reclose; dash-dot: reselect)', ...
    'Interpreter','latex','FontSize',fs);
nexttile; hold on
plot(t, Vbus(:,b1), '-', 'LineWidth', 1.0);
plot(t, Vbus(:,b2), '-', 'LineWidth', 1.0);
xline(100, ':', 'LineWidth', 1.0);
xline(t_reclose, ':', 'LineWidth', 1.0);
xline(t_reselect, '-.', 'LineWidth', 1.0);
xlim([98 120]);
ylabel('$|V|$ (pu)','Interpreter','latex');
xlabel('$t$ (s)','Interpreter','latex');
legend({'bus 1','bus 2'}, 'Interpreter','latex','Location','southeast','Box','off');
set(gca,'FontName',FN,'FontSize',fs,'TickLabelInterpreter','tex', ...
    'XGrid','on','YGrid','on','GridLineStyle','--','Box','off','TickDir','out');
exportgraphics(f6, fullfile(odir,'backup_b6_return.png'), 'Resolution', 300);
close(f6);

fprintf('backup figures written to %s\n', odir);
end
