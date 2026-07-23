function out = run_ieee14_switch(varargin)
%RUN_IEEE14_SWITCH  One-command launcher for the IEEE 14-bus 1-SG + 4-IBR
%   AGSI++ GFL<->GFM mode-switch study (SG@bus1 Padiyar-1.1 manual/NO-AVR +
%   4 reduced-6 IBRs @ buses 2,3,6,8), using the SAME models as the Padiyar
%   4-machine study. Small-signal STABLE at the operating point (meshed
%   single-area network; no weak inter-area tie).
%
%   run_ieee14_switch
%       Opens the settings dialog (disturbance method, times, index, dwell,
%       governor, current limit), then runs and pops up the SEPARATE tabbed
%       figures (AGSI, angle, frequency, i_d, i_q, |V|, P, Q incl. the SG) and
%       prints the PF + SSSA + reference/forming log.
%
%   out = run_ieee14_switch(Name=Value)
%       Skip the dialog (forwarded to ibr.padiyar_switch_demo with
%       system="ieee14"): index_mode, sg_trip_time, sg_reclose_time, fault_*,
%       step_*, T_d_on/off, sg_droop_R, gfm_ilim, excitation, T, dt, compare.
%
%   Examples:
%       run_ieee14_switch
%       run_ieee14_switch(sg_reclose_time=5, T=10)
%       run_ieee14_switch(index_mode="agsi", compare=true)

pf_init_paths();

if nargin == 0
    opts = ibr.padiyar_switch_dialog("ieee14");
    if isempty(opts)
        fprintf('run_ieee14_switch: cancelled.\n'); out = []; return;
    end
    out = ibr.padiyar_switch_demo(system="ieee14", index_mode=opts.index_mode, ...
        sg_trip_time=opts.sg_trip_time, sg_reclose_time=opts.sg_reclose_time, ...
        fault_on=opts.fault_on, fault_clear=opts.fault_clear, fault_bus=opts.fault_bus, ...
        fault_Zf=opts.fault_Zf, step_on=opts.step_on, step_factor=opts.step_factor, ...
        T_d_on=opts.T_d_on, T_d_off=opts.T_d_off, sg_droop_R=opts.sg_droop_R, gfm_ilim=opts.gfm_ilim, ...
        excitation=opts.excitation, T=opts.T, dt=opts.dt, visible=true);
    return;
end

% programmatic: force system=ieee14, drop any visible override
args = varargin;
drop = false(1, numel(args));
for k = 1:2:numel(args)-1
    if (ischar(args{k}) || isstring(args{k})) && any(strcmpi(char(args{k}), {'visible','system'}))
        drop(k) = true; drop(k+1) = true;
    end
end
args(drop) = [];
out = ibr.padiyar_switch_demo(args{:}, system="ieee14", visible=true);
end
