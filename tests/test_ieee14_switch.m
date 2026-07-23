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
