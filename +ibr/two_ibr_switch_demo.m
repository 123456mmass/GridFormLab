function out = two_ibr_switch_demo(opts)
%TWO_IBR_SWITCH_DEMO  Practice demo: two GFL IBRs on a common PCC behind one
%   line to an infinite bus. A TEMPORARY weak-grid event lifts the AGSI
%   switching equation across its up-line (Gamma_on), latching each IBR into
%   GFM; when the grid recovers and AGSI falls below the down-line (Gamma_off)
%   for the dwell time, each IBR switches BACK to GFL.
%
%   OUT = ibr.two_ibr_switch_demo() runs the default scenario, makes a 4-panel
%   figure (AGSI vs Gamma_on/Gamma_off + switch markers; frequency; PCC voltage;
%   P and Q), saves it under output/diagnostics, and returns the TDS output.
%
%   OUT = ibr.two_ibr_switch_demo(Name=Value) overrides the scenario. Knobs:
%   P_ref, Q_ref, V_inf, Z_line, AGSI_up, AGSI_down, event_time, recover_time,
%   Zline_factor, step_dphase_deg, step_dV, T, dt, save_fig, fig_path.
%
%   Switching uses the EECON49-P4 AGSI equation (see ibr.SwitchableIbr6);
%   classification ASSUMED_DIAGNOSTIC study/teaching demo (paper as guideline).

arguments
    opts.P_ref (1,1) double = 0.2
    opts.Q_ref (1,1) double = 0.0
    opts.V_inf (1,1) double = 1.0
    opts.Z_line (1,1) double = 0.30i
    opts.AGSI_up (1,1) double = 0.65
    opts.AGSI_down (1,1) double = 0.35
    opts.index_mode (1,1) string = "agsi_pp"
    opts.T_d_on (1,1) double = 0.0
    opts.T_d_off (1,1) double = 0.0
    opts.event_time (1,1) double = 1.5
    opts.recover_time (1,1) double = 4.0
    opts.Zline_factor (1,1) double = 4.0
    opts.step_dphase_deg (1,1) double = 0
    opts.step_dV (1,1) double = 0.0
    opts.step_ramp (1,1) double = 0.40
    opts.T (1,1) double = 8.0
    opts.dt (1,1) double = 1e-3
    opts.save_fig (1,1) logical = true
    opts.fig_path (1,1) string = ""
    opts.visible (1,1) logical = false
end

params = struct();   % frozen EECON49-P4 gains inside each reduced-6 model

% --- Build two switchable IBRs at a common PCC (bus_position=1) -------------
bus_ids = 1;  bus_id = 1;  bp = 1;
V0 = opts.V_inf;
dev1 = ibr.SwitchableIbr6("IBR1", bus_id, bp, bus_ids, V0, params, ...
    opts.P_ref, opts.Q_ref, index_mode=opts.index_mode, ...
    T_d_on=opts.T_d_on, T_d_off=opts.T_d_off, AGSI_up=opts.AGSI_up, AGSI_down=opts.AGSI_down);
dev2 = ibr.SwitchableIbr6("IBR2", bus_id, bp, bus_ids, V0, params, ...
    opts.P_ref, opts.Q_ref, index_mode=opts.index_mode, ...
    T_d_on=opts.T_d_on, T_d_off=opts.T_d_off, AGSI_up=opts.AGSI_up, AGSI_down=opts.AGSI_down);

% --- Consistent pre-event PCC equilibrium ----------------------------------
S1 = complex(opts.P_ref, opts.Q_ref);
S2 = complex(opts.P_ref, opts.Q_ref);
Vpcc = ibr.solve_pcc_infbus_equilibrium(opts.V_inf, opts.Z_line, [S1, S2]);
x1_0 = dev1.gfl_dev.equilibrium_initialize(Vpcc, opts.P_ref, opts.Q_ref, struct());
x2_0 = dev2.gfl_dev.equilibrium_initialize(Vpcc, opts.P_ref, opts.Q_ref, struct());
y0 = [real(Vpcc); imag(Vpcc)];

% --- Run --------------------------------------------------------------------
out = ibr.two_ibr_infbus_tds(dev1, dev2, x1_0, x2_0, y0, opts.V_inf, opts.Z_line, ...
    T=opts.T, dt=opts.dt, event_time=opts.event_time, recover_time=opts.recover_time, ...
    step_ramp=opts.step_ramp, Zline_factor=opts.Zline_factor, ...
    step_dphase_deg=opts.step_dphase_deg, step_dV=opts.step_dV, ...
    newton_tol=1e-9, newton_max_iter=80, fd_eps=1e-6);
out.Vpcc0 = Vpcc;

% --- Plot -------------------------------------------------------------------
fig = figure('Color','w','Position',[80 60 1000 780], ...
    'Visible', matlab.lang.OnOffSwitchState(opts.visible));
tl = tiledlayout(fig,4,1,'TileSpacing','compact','Padding','compact');
title(tl, sprintf(['Two GFL IBRs, AGSI-based GFL<->GFM switch  (event %.1f-%.1fs: ' ...
    'Z_{line} x%.1f, \\Delta\\theta=%g^\\circ, \\DeltaV=%g)'], opts.event_time, ...
    opts.recover_time, opts.Zline_factor, opts.step_dphase_deg, opts.step_dV), ...
    'Interpreter','tex');

t = out.tgrid;
c1 = [0.85 0.33 0.10];   % IBR1 (orange)
c2 = [0.00 0.45 0.74];   % IBR2 (blue)

% Panel 1: AGSI switching equation vs the two reference lines
ax1 = nexttile(tl); hold(ax1,'on'); grid(ax1,'on');
plot(ax1, t, out.index1, '-', 'Color', c1, 'LineWidth', 1.5, 'DisplayName','AGSI IBR1');
plot(ax1, t, out.index2, '--', 'Color', c2, 'LineWidth', 1.5, 'DisplayName','AGSI IBR2');
yline(ax1, out.agsi_up, 'k-', 'LineWidth', 1.3, 'Label','\Gamma_{on}=0.65', ...
    'LabelHorizontalAlignment','left', 'DisplayName','\Gamma_{on} (up)');
yline(ax1, out.agsi_down, 'k--', 'LineWidth', 1.1, 'Label','\Gamma_{off}=0.35', ...
    'LabelHorizontalAlignment','left', 'DisplayName','\Gamma_{off} (down)');
mark_event(ax1, opts.event_time, opts.recover_time);
mark_switches(ax1, out);
ylabel(ax1,'AGSI'); legend(ax1,'Location','northeast');
ylim(ax1,[0 2]);   % clip momentary RoCoF spikes; the dwell T_d,on rejects them
title(ax1,'AGSI switching equation vs reference lines (\Gamma_{on}, \Gamma_{off})  [axis clipped to 2]');

% Panel 2: frequency (PLL in GFL, VSG rotor in GFM)
ax2 = nexttile(tl); hold(ax2,'on'); grid(ax2,'on');
plot(ax2, t, out.f1, '-', 'Color', c1, 'LineWidth', 1.3, 'DisplayName','f IBR1');
plot(ax2, t, out.f2, '--', 'Color', c2, 'LineWidth', 1.3, 'DisplayName','f IBR2');
mark_event(ax2, opts.event_time, opts.recover_time); mark_switches(ax2, out);
ylabel(ax2,'f (Hz)'); legend(ax2,'Location','best'); title(ax2,'PLL / VSG frequency');

% Panel 3: PCC voltage magnitude
ax3 = nexttile(tl); hold(ax3,'on'); grid(ax3,'on');
plot(ax3, t, out.Vmag, '-', 'Color', [0.2 0.2 0.2], 'LineWidth', 1.3);
mark_event(ax3, opts.event_time, opts.recover_time); mark_switches(ax3, out);
ylabel(ax3,'|V_{pcc}| (pu)'); title(ax3,'Common PCC voltage');

% Panel 4: P and Q
ax4 = nexttile(tl); hold(ax4,'on'); grid(ax4,'on');
plot(ax4, t, out.P1, '-', 'Color', c1, 'LineWidth', 1.2, 'DisplayName','P IBR1');
plot(ax4, t, out.P2, '--', 'Color', c2, 'LineWidth', 1.2, 'DisplayName','P IBR2');
plot(ax4, t, out.Q1, '-.', 'Color', c1, 'LineWidth', 1.0, 'DisplayName','Q IBR1');
plot(ax4, t, out.Q2, ':', 'Color', c2, 'LineWidth', 1.2, 'DisplayName','Q IBR2');
mark_event(ax4, opts.event_time, opts.recover_time); mark_switches(ax4, out);
ylabel(ax4,'P, Q (pu)'); xlabel(ax4,'time (s)'); legend(ax4,'Location','best');
title(ax4,'Active / reactive power');

% --- Save -------------------------------------------------------------------
if opts.save_fig
    if strlength(opts.fig_path) > 0
        fpath = char(opts.fig_path);
    else
        outdir = fullfile('output','diagnostics');
        if ~exist(outdir,'dir'); mkdir(outdir); end
        fpath = fullfile(outdir,'two_ibr_switch_demo.png');
    end
    exportgraphics(fig, fpath, 'Resolution', 130);
    out.fig_path = fpath;
    fprintf('SWITCH_DEMO figure saved: %s\n', fpath);
end
if ~opts.visible
    close(fig);
end

% --- Console summary --------------------------------------------------------
fprintf('SWITCH_DEMO: dev1 n_switch=%d last=%.3f mode=%s; dev2 n_switch=%d last=%.3f mode=%s\n', ...
    dev1.n_switch, dev1.last_switch_time, dev1.mode, dev2.n_switch, dev2.last_switch_time, dev2.mode);
if ~isempty(out.switch_events)
    fprintf('SWITCH_DEMO events [t, dev, AGSI, ->GFM?]:\n');
    disp(out.switch_events);
end
fprintf('SWITCH_DEMO: newton_all_converged=%d; peak AGSI1=%.3f (Gamma_on=%.2f)\n', ...
    out.newton_all_converged, max(out.index1), out.agsi_up);
end

% =========================================================================
function mark_event(ax, te, tr)
if isfinite(te)
    xline(ax, te, 'Color', [0.5 0.5 0.5], 'LineStyle', ':', 'LineWidth', 1.0, ...
        'HandleVisibility','off');
end
if isfinite(tr)
    xline(ax, tr, 'Color', [0.5 0.5 0.5], 'LineStyle', ':', 'LineWidth', 1.0, ...
        'HandleVisibility','off');
end
end

% =========================================================================
function mark_switches(ax, out)
ev = out.switch_events;
if isempty(ev); return; end
for r = 1:size(ev,1)
    if size(ev,2) >= 4 && ev(r,4) == 1
        col = [0.80 0.10 0.10];   % -> GFM (red)
    else
        col = [0.10 0.60 0.20];   % -> GFL (green)
    end
    xline(ax, ev(r,1), 'Color', col, 'LineStyle', '-', 'LineWidth', 1.6, ...
        'Alpha', 0.5, 'HandleVisibility','off');
end
end
