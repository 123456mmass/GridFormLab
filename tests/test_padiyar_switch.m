function tests = test_padiyar_switch
%TEST_PADIYAR_SWITCH  Padiyar two-area 1-SG + 3-GFL AGSI/AGSI++ mode-switch study
%   (ibr.build_padiyar_switch_system, ibr.padiyar_sg_unit, ibr.padiyar_switch_tds).
%   Falsification tests: composite equilibrium, flat hold (no event), SG-trip
%   index-driven switching, and AGSI++ boundedness vs the baseline. ASSUMED
%   DIAGNOSTIC study, not a production-readiness claim.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));   % repo root for +ibr classdef
pf_init_paths();
end

function test_build_equilibrium(tc)
sys = ibr.build_padiyar_switch_system(index_mode="agsi_pp");
verifyEqual(tc, sys.sg.nx, 5);          % Padiyar two-area default excitation="avr": 5-state SG
verifyEqual(tc, sys.sg.excitation, 'avr');
verifyEqual(tc, numel(sys.devs), 3);
verifyEqual(tc, sys.sg_bus, 11);
verifyEqual(tc, sys.ibr_buses, [1 2 12]);
% composite KCL residual at the equilibrium
y0 = sys.y0; V = complex(y0(1:2:end), y0(2:2:end));
gc = -sys.Y*V;
gc(sys.sg_bus_position) = gc(sys.sg_bus_position) + sys.sg.current_injection(sys.x_sg0, y0);
for j=1:3
    gc(sys.ibr_bus_positions(j)) = gc(sys.ibr_bus_positions(j)) ...
        + sys.devs{j}.current_injection(sys.x_ibr0{j}, y0);
end
verifyLessThan(tc, max(abs(gc)), 1e-8);
verifyLessThan(tc, max(abs(sys.sg.f(sys.x_sg0, y0))), 1e-6);
for j=1:3
    verifyLessThan(tc, max(abs(sys.devs{j}.f(sys.x_ibr0{j}, y0))), 1e-8);
end
end

function test_flat_hold_no_event(tc)
sys = ibr.build_padiyar_switch_system(index_mode="agsi_pp");
o = ibr.padiyar_switch_tds(sys, T=0.3, dt=2e-3, sg_trip_time=99);
verifyTrue(tc, o.newton_all_converged);
verifyLessThan(tc, max(abs(o.Z(:,end)-o.Z(:,1))), 1e-6);   % flat
verifyEqual(tc, o.dev_n_switch, [0 0 0]);
end

function test_sg_trip_index_driven_switch(tc)
sys = ibr.build_padiyar_switch_system(index_mode="agsi_pp");
o = ibr.padiyar_switch_tds(sys, T=2.0, dt=2e-3, sg_trip_time=1.0);
verifyTrue(tc, o.newton_all_converged);
% at least one IBR crosses the ref line and switches to GFM (index-driven)
verifyGreaterThanOrEqual(tc, sum(o.dev_n_switch>=1), 1);
verifyTrue(tc, any(o.dev_mode=="GFM"));
% island survives (voltage does not collapse)
verifyGreaterThan(tc, min(o.Vmin), 0.5);
% every recorded switch really had AGSI at/above the up-line
ev = o.switch_events;
verifyTrue(tc, ~isempty(ev));
verifyGreaterThanOrEqual(tc, min(ev(ev(:,4)==1,3)), o.agsi_up - 1e-9);
end

function test_sg_reclose_restores_gfl(tc)
% SG trip -> IBRs form (GFM); SG reclose -> synchronized handback: the SG re-takes
% the slack (carrying its scheduled load) and the IBRs hand the reference back and
% revert to their scheduled GFL dispatch. The network is restored (no collapse).
% Note: with no SG governor a small steady frequency offset remains, so the
% weakest-bus IBR may re-form; the study only requires a stable restored grid
% with the reference handed back to the SG and most IBRs returned to GFL.
sys = ibr.build_padiyar_switch_system(index_mode="agsi_pp");
o = ibr.padiyar_switch_tds(sys, T=6.0, dt=2e-3, sg_trip_time=1.0, sg_reclose_time=4.0);
verifyTrue(tc, o.newton_all_converged);
verifyGreaterThan(tc, o.Vmin(end), 0.9);           % network restored (no collapse)
verifyGreaterThanOrEqual(tc, sum(o.dev_mode=="gfl"), 2);   % >=2 IBRs hand back to GFL
% every IBR forms at the trip (each crossed the up-line)
verifyTrue(tc, all(o.dev_n_switch>=2));
% reference: SG slack (0) -> island forming IBR (>=1) -> SG slack again (0)
verifyEqual(tc, o.ref_code(find(o.tgrid>=0.5,1)), 0);
verifyGreaterThanOrEqual(tc, o.ref_code(find(o.tgrid>=2.5,1)), 1);
verifyEqual(tc, o.ref_code(find(o.tgrid>=5.0,1)), 0);
end

function test_solve_case_route(tc)
% End-to-end: runnable via the solve_case launcher (analysis='ibr',
% case='padiyar_switch'), returning a converged SG-trip+reclose switch result.
r = solve_case('analysis','ibr','case','padiyar_switch', ...
    'options',struct('plot_results',false,'t_end',6.0));
verifyTrue(tc, r.converged);
verifyEqual(tc, numel(r.dev_n_switch), 3);
verifyTrue(tc, all(r.dev_n_switch>=2));          % each IBR forms then hands back
verifyGreaterThan(tc, r.Vmin_end, 0.9);          % restored
verifyEqual(tc, numel(r.figure_files), 0);       % plot_results=false
end

function test_agsi_decision_index_is_bounded(tc)
sysp = ibr.build_padiyar_switch_system(index_mode="agsi_pp");
op = ibr.padiyar_switch_tds(sysp, T=2.0, dt=2e-3, sg_trip_time=1.0);
sysb = ibr.build_padiyar_switch_system(index_mode="agsi");
ob = ibr.padiyar_switch_tds(sysb, T=2.0, dt=2e-3, sg_trip_time=1.0);
verifyTrue(tc, op.newton_all_converged && ob.newton_all_converged);
% Both routes publish the normalized decision index.  The unbounded raw
% weighted stress remains available only from compute_agsi diagnostics.
verifyGreaterThanOrEqual(tc,min(op.index(:)),0);
verifyLessThanOrEqual(tc,max(op.index(:)),1);
verifyGreaterThanOrEqual(tc,min(ob.index(:)),0);
verifyLessThanOrEqual(tc,max(ob.index(:)),1);
end
