function out = run_two_ibr_switch(varargin)
%RUN_TWO_IBR_SWITCH  One-command launcher for the two-IBR AGSI GFL<->GFM
%   mode-switch study (NO IEEE14 wizard menus).
%
%   run_two_ibr_switch
%       Opens a small SETTINGS DIALOG pre-filled with the clear default
%       scenario. Edit any value, press OK, and the 4-panel figure pops up
%       (Cancel aborts). Two grid-following (GFL) IBRs share a common PCC
%       behind one line to an infinite bus; a temporary weak-grid event lifts
%       the AGSI switching equation across Gamma_on so both switch GFL->GFM, and
%       when the grid recovers AGSI falls below Gamma_off so both switch back.
%
%   out = run_two_ibr_switch(Name=Value)
%       Skip the dialog and run directly with the given overrides (forwarded to
%       ibr.two_ibr_switch_demo): P_ref, Q_ref, V_inf, Z_line, AGSI_up,
%       AGSI_down, event_time, recover_time, Zline_factor, step_dphase_deg,
%       step_dV, step_ramp, T, dt.
%
%   Examples:
%       run_two_ibr_switch                     % settings dialog, then run
%       run_two_ibr_switch(Zline_factor=5)     % skip dialog: weaker grid
%       run_two_ibr_switch(recover_time=5, T=9)
%
%   OUT is the time-domain output struct (tgrid, index1/2 = AGSI, ref lines,
%   f1/2, Vmag, P/Q, switch_events, ...); the figure is saved to
%   output/diagnostics/two_ibr_switch_demo.png.
%
%   Equivalent programmatic launcher route: solve_case('analysis','ibr',
%   'case','two_ibr_switch'). Switching uses the EECON49-P4 AGSI equation as a
%   design guideline (see ibr.SwitchableIbr6). Project code only.

pf_init_paths();

if nargin == 0
    % --- interactive settings dialog -------------------------------------
    opts = ibr.two_ibr_switch_dialog();
    if isempty(opts)
        fprintf('run_two_ibr_switch: cancelled.\n');
        out = [];
        return;
    end
    nv = struct_to_namevalue(opts);
    out = ibr.two_ibr_switch_demo(nv{:}, visible=true, save_fig=true);
    return;
end

% --- programmatic: forward overrides, always show + save the figure ------
args = varargin;
drop = false(1, numel(args));
for k = 1:2:numel(args)-1
    if (ischar(args{k}) || isstring(args{k})) && ...
            any(strcmpi(char(args{k}), {'visible','save_fig'}))
        drop(k) = true; drop(k+1) = true;
    end
end
args(drop) = [];
out = ibr.two_ibr_switch_demo(args{:}, visible=true, save_fig=true);
end

% =========================================================================
function nv = struct_to_namevalue(s)
fn = fieldnames(s);
nv = cell(1, 2*numel(fn));
for k = 1:numel(fn)
    nv{2*k-1} = fn{k};
    nv{2*k}   = s.(fn{k});
end
end
