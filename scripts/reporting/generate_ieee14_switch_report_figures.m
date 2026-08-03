function out = generate_ieee14_switch_report_figures()
%GENERATE_IEEE14_SWITCH_REPORT_FIGURES Reproduce the audited IEEE14 TDS figures.
%   OUT = GENERATE_IEEE14_SWITCH_REPORT_FIGURES() runs the frozen 50 s
%   diagnostic scenario used by report_ieee14_switch_{th,en}.tex and writes
%   the AGSI, binary-mode, angle, frequency, current, voltage, P and Q plots
%   beneath docs/source/figures/switch_ieee14.
%
%   This reporting producer changes no model equation, threshold, dwell,
%   event or numerical result.  The discrete mode timeline is taken directly
%   from OUT.mode and OUT.switch_events; it is not inferred from the AGSI plot.

pf_init_paths();
outdir = fullfile('docs','source','figures','switch_ieee14');
if ~exist(outdir,'dir'), mkdir(outdir); end

out = ibr.padiyar_switch_demo( ...
    system="ieee14", index_mode="agsi_pp", ...
    sg_trip_time=6.0, sg_reclose_time=9.0, ...
    T=50.0, dt=2e-3, ...
    fault_on=1.0, fault_clear=1.15, fault_bus=4, fault_Zf=0.1i, ...
    T_d_on=0.5, T_d_off=1.0, ...
    fig_dir=string(outdir), visible=false, plot=true);

fprintf('IEEE14_SWITCH_REPORT_FIGURES_DONE: %s\n', outdir);
end
