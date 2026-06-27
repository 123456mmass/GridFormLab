function plot_empty_state(app)
%PLOT_EMPTY_STATE Clear all axes with placeholder messages.

axes_cfg = {
    'ax_voltage', 'Voltage Profile', 'Run PF or CPF to see voltage results';
    'ax_conv',    'Convergence',     'Iteration history appears here';
    'ax_cpf',     'CPF / PV Curve',  'CPF nose curve appears here';
    'ax_opf',     'OPF Dispatch',    'Economic dispatch chart appears here';
    'ax_smib_plane', 'SMIB s-plane', 'Eigenvalues appear after an SMIB run';
    'ax_smib_step',  'SMIB Response', 'Time-domain response appears after an SMIB run';
};

for i = 1:size(axes_cfg, 1)
    ax_name = axes_cfg{i, 1};
    title_text = axes_cfg{i, 2};
    sub_text = axes_cfg{i, 3};

    if isfield(app, ax_name) && ~isempty(app.(ax_name)) && isvalid(app.(ax_name))
        ax = app.(ax_name);
        cla(ax);
        ax.Color = [0.985 0.990 1.000];
        ax.XTick = [];
        ax.YTick = [];
        ax.XLim = [0 1];
        ax.YLim = [0 1];
        text(ax, 0.5, 0.58, title_text, ...
            'HorizontalAlignment', 'center', 'FontName', 'Segoe UI', ...
            'FontSize', 13, 'FontWeight', 'bold', 'Color', [0.09 0.13 0.20]);
        text(ax, 0.5, 0.42, sub_text, ...
            'HorizontalAlignment', 'center', 'FontName', 'Segoe UI', ...
            'FontSize', 9, 'Color', [0.39 0.45 0.55]);
        title(ax, '');
        box(ax, 'on');
    end
end
end
