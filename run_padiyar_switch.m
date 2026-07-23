function out = run_padiyar_switch(varargin)
%RUN_PADIYAR_SWITCH  One-command launcher for the Padiyar two-area 1-SG + 3-GFL
%   AGSI++ GFL<->GFM mode-switch study (SG trip + synchronized reclose).
%
%   run_padiyar_switch
%       Opens a settings dialog (index mode, SG trip/reclose times, T, dt),
%       then runs and pops up the SEPARATE figures (AGSI, angle, frequency,
%       dq currents, voltage, power) and prints the reference/forming log.
%
%   out = run_padiyar_switch(Name=Value)
%       Skip the dialog and run directly (forwarded to ibr.padiyar_switch_demo):
%       index_mode, sg_trip_time, sg_reclose_time, T, dt, compare.
%
%   Examples:
%       run_padiyar_switch
%       run_padiyar_switch(sg_reclose_time=5, T=9)
%       run_padiyar_switch(index_mode="agsi", compare=true)   % baseline vs AGSI++
%
%   1 SG (bus 11, slack) + 3 GFL IBRs (buses 1,2,12); on SG trip the stressed
%   IBRs whose AGSI crosses the reference line form (GFM); on synchronized
%   reclose the SG re-takes the slack and the IBRs hand the reference back to
%   GFL (which ones revert is decided by the index). AGSI++ switching, no dwell.
%
%   Equivalent programmatic launcher route:
%       solve_case('analysis','ibr','case','padiyar_switch')

pf_init_paths();

if nargin == 0
    opts = ibr.padiyar_switch_dialog("padiyar");
    if isempty(opts)
        fprintf('run_padiyar_switch: cancelled.\n'); out = []; return;
    end
    out = ibr.padiyar_switch_demo(index_mode=opts.index_mode, ...
        sg_trip_time=opts.sg_trip_time, sg_reclose_time=opts.sg_reclose_time, ...
        fault_on=opts.fault_on, fault_clear=opts.fault_clear, fault_bus=opts.fault_bus, ...
        fault_Zf=opts.fault_Zf, step_on=opts.step_on, step_factor=opts.step_factor, ...
        T_d_on=opts.T_d_on, T_d_off=opts.T_d_off, sg_droop_R=opts.sg_droop_R, gfm_ilim=opts.gfm_ilim, ...
        excitation=opts.excitation, ...
        T=opts.T, dt=opts.dt, visible=true);
    return;
end

% programmatic: forward overrides, always show the figures
args = varargin;
drop = false(1, numel(args));
for k = 1:2:numel(args)-1
    if (ischar(args{k}) || isstring(args{k})) && strcmpi(char(args{k}),'visible')
        drop(k) = true; drop(k+1) = true;
    end
end
args(drop) = [];
out = ibr.padiyar_switch_demo(args{:}, visible=true);
end
