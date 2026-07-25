function tests = test_ieee14_switch
%TEST_IEEE14_SWITCH  IEEE 14-bus 1-SG + 4-IBR AGSI/AGSI++ mode-switch study
%   using OUR models (Padiyar model-1.1 manual SG via ibr.padiyar_sg_unit +
%   ibr.SwitchableIbr6 reduced-6 IBRs). Falsification tests: composite
%   equilibrium, small-signal stability (meshed single-area, NO AVR/PSS),
%   flat hold, SG-trip index-driven switching, and the demo route.
%   ASSUMED_DIAGNOSTIC study, not a production-readiness claim.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));   % repo root for +ibr classdef
pf_init_paths();
end

function test_build_equilibrium(tc)
sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp");
verifyEqual(tc, sys.sg.nx, 4);                 % manual excitation (NO AVR): 4-state SG
verifyEqual(tc, sys.sg.excitation, 'manual');
verifyEqual(tc, numel(sys.devs), 4);
verifyEqual(tc, sys.sg_bus, 1);
verifyEqual(tc, sys.ibr_buses, [2 3 6 8]);
% composite KCL residual at the equilibrium (tap-aware Ybus + folded loads)
y0 = sys.y0; V = complex(y0(1:2:end), y0(2:2:end));
gc = -sys.Y*V;
gc(sys.sg_bus_position) = gc(sys.sg_bus_position) + sys.sg.current_injection(sys.x_sg0, y0);
for j = 1:4
    gc(sys.ibr_bus_positions(j)) = gc(sys.ibr_bus_positions(j)) ...
        + sys.devs{j}.current_injection(sys.x_ibr0{j}, y0);
end
verifyLessThan(tc, max(abs(gc)), 1e-8);
verifyLessThan(tc, max(abs(sys.sg.f(sys.x_sg0, y0))), 1e-8);
end

function test_sssa_small_signal_stable(tc)
% The meshed single-area IEEE14 (1 SG manual + 4 GFL, NO AVR/PSS) is
% small-signal STABLE at the operating point (no right-half-plane eigenvalue),
% unlike the weak two-area Padiyar composite.
sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp");
r = ibr.padiyar_switch_pf_sssa(sys);
verifyEqual(tc, r.n_unstable, 0);
verifyLessThan(tc, max(real(r.eig)), 1e-4);    % only the ~0 angle-reference mode
end

function test_flat_hold_no_event(tc)
sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp");
o = ibr.padiyar_switch_tds(sys, T=0.3, dt=2e-3, sg_trip_time=99);
verifyTrue(tc, o.newton_all_converged);
verifyLessThan(tc, max(abs(o.Z(:,end)-o.Z(:,1))), 1e-6);   % flat
verifyEqual(tc, o.dev_n_switch, [0 0 0 0]);
end

function test_sg_trip_index_driven_switch(tc)
sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp");
o = ibr.padiyar_switch_tds(sys, T=2.5, dt=2e-3, sg_trip_time=1.0);
verifyTrue(tc, o.newton_all_converged);
verifyFalse(tc, o.diverged);
verifyGreaterThanOrEqual(tc, sum(o.dev_n_switch>=1), 1);    % >=1 IBR forms (index-driven)
verifyTrue(tc, any(o.dev_mode=="GFM"));
verifyGreaterThan(tc, min(o.Vmin), 0.1);                   % island does not fully collapse
ev = o.switch_events;
verifyTrue(tc, ~isempty(ev));
verifyGreaterThanOrEqual(tc, min(ev(ev(:,4)==1,3)), o.agsi_up - 1e-9);   % forms only at/above the up-line
end

function test_demo_route_ieee14(tc)
o = ibr.padiyar_switch_demo(system="ieee14", T=6.0, dt=2e-3, visible=false);
verifyEqual(tc, numel(o.dev_n_switch), 4);
verifyFalse(tc, o.diverged);
verifyEqual(tc, numel(o.fig_paths), 8);
verifyTrue(tc, isfield(o,'sssa') && o.sssa.n_unstable==0);
end

function test_solve_case_route(tc)
% End-to-end: runnable via the solve_case launcher (analysis='ibr',
% case='ieee14_switch'), returning a converged, small-signal-stable result.
r = solve_case('analysis','ibr','case','ieee14_switch', ...
    'options',struct('plot_results',false,'t_end',6.0));
verifyTrue(tc, r.converged);
verifyEqual(tc, numel(r.dev_n_switch), 4);
verifyEqual(tc, r.sssa.n_unstable, 0);            % IEEE14 operating point is stable
verifyGreaterThan(tc, r.Vmin_end, 0.3);
verifyEqual(tc, numel(r.figure_files), 0);        % plot_results=false
end

function test_severe_cleared_fault_recovers_post_clear(tc)
% DEFECT GUARD (SWITCH-2026-07-26-01, H1): a severe but CLEARED fault sags the
% network far below the 0.25 pu collapse floor WHILE it is applied, yet the
% composite recovers after clearing. The switching map must therefore judge
% collapse on the POST-CLEAR minimum voltage; using the all-time minimum
% mislabels a survived fault as a voltage collapse.
sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp");
o = ibr.padiyar_switch_tds(sys, T=3.0, dt=2e-3, sg_trip_time=inf, ...
    fault_on=1.0, fault_clear=1.15, fault_bus=9, fault_Zf=0.02i);
verifyTrue(tc, o.newton_all_converged);
verifyFalse(tc, o.diverged);
during = min(o.Vmin);                                   % includes the fault window
post   = min(o.Vmin(o.tgrid >= 1.15));                  % recovery window only
verifyLessThan(tc, during, 0.25);                       % the sag alone looks like "collapse"
verifyGreaterThan(tc, post, 0.90);                      % but the network fully recovers
verifyGreaterThanOrEqual(tc, sum(o.dev_n_switch), 1);   % AGSI++ did command forming
end

function test_scheduled_event_bus_fails_closed(tc)
% DEFECT GUARD (SWITCH-2026-07-26-01, M3): a SCHEDULED fault/load-step on a bus
% that does not exist in the system must fail closed, never be silently
% relocated to network position 1 (which would disturb a different bus and
% report the result as the requested one).
sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp");
verifyError(tc, @() ibr.padiyar_switch_tds(sys, T=0.1, dt=2e-3, sg_trip_time=inf, ...
    fault_on=0.02, fault_clear=0.06, fault_bus=999), ...
    'ibr:padiyar_switch_tds:faultBus');
verifyError(tc, @() ibr.padiyar_switch_tds(sys, T=0.1, dt=2e-3, sg_trip_time=inf, ...
    step_on=0.02, step_bus=777), ...
    'ibr:padiyar_switch_tds:stepBus');
% A DISABLED event (Inf time) may keep an inapplicable default bus: no error.
o = ibr.padiyar_switch_tds(sys, T=0.1, dt=2e-3, sg_trip_time=99);
verifyTrue(tc, o.newton_all_converged);
end

function test_plot_false_writes_no_figure(tc)
% DEFECT GUARD (SWITCH-2026-07-26-01, M1): plot_results=false must actually
% suppress figure creation and PNG writes, not merely blank the returned list.
od = fullfile(tempname); mkdir(od);
cleanup = onCleanup(@() rmdir(od,'s'));
o = ibr.padiyar_switch_demo(system="ieee14", T=0.3, dt=2e-3, sg_trip_time=99, ...
    fig_dir=string(od), visible=false, plot=false);
verifyEmpty(tc, o.fig_paths);
verifyEqual(tc, numel(dir(fullfile(od,'*.png'))), 0);   % nothing written to disk
verifyEqual(tc, numel(findall(0,'Type','figure')), 0);  % no figure left open
end
