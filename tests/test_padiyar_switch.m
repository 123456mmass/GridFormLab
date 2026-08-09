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
% the slack and the IBRs hand the reference back and revert to their scheduled GFL
% dispatch. The network is restored (no collapse).
% 2026-08-09 index-definition change (aggr. AGSI severity now the 2-term J_V/J_f
% index): the restored post-reclose operating point of this NO-governor/NO-AVR
% manual SG carries a steady frequency offset of +0.35 Hz (EMF6 field constant,
% Pm frozen at the pre-trip torque), so J_f = 0.35/0.50 = 0.69 keeps the 2-term
% severity at [~0.68, ~0.65, ~0.33] -- above Gamma_off=0.35 for the two stronger
% buses (2 and 3) but just below it for the weakest-bus IBR (bus 12, V~1.00 pu,
% J_V~0.01).  An index-driven supervisor therefore correctly KEEPS those two IBRs
% forming (their J_f still measures a real frequency error) and hands only the
% weakest bus back to GFL.  The old equal 1/7 average diluted J_V/J_f by the five
% mostly-zero stress terms (raw 0.20/0.19 vs the 0.35 down-line), so the previous
% test could assert ">=2 return to GFL" only because the diluted index falsely
% reported a calm reference.  The corrected contract is: reference ownership
% returns to the SG (ref_code 0), the network restores, and at least one IBR
% hands back only when its OWN local severity actually falls below Gamma_off.
sys = ibr.build_padiyar_switch_system(index_mode="agsi_pp");
o = ibr.padiyar_switch_tds(sys, T=6.0, dt=2e-3, sg_trip_time=1.0, sg_reclose_time=4.0);
verifyTrue(tc, o.newton_all_converged);
verifyGreaterThan(tc, o.Vmin(end), 0.9);           % network restored (no collapse)
% At least the weakest-bus IBR (large electrical distance, V~1.00 pu) sees a
% severity below Gamma_off and hands back; the two stronger buses may keep
% forming while their measured J_f still exceeds the band (see comment above).
verifyGreaterThanOrEqual(tc, sum(o.dev_mode=="gfl"), 1);
% every IBR forms at the trip (each crossed the up-line to GFM); forming after
% reclose is not a trip-time event so n_switch may exceed 1 on a handed-back dev.
verifyTrue(tc, all(o.dev_n_switch>=1));
verifyTrue(tc, any(o.dev_n_switch>=2));            % at least one full form+handback cycle
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
% The solve_case route shares one composite instance with the TDS so its
% switch_events are the same [3x4] as in the direct run (measured: form only).
% With the 2-term severity the two strong buses stay forming post-reclose while
% the SG holds the reference (see test_sg_reclose_restores_gfl); every IBR forms
% at the trip (n_switch>=1), the network restores, and no IBR collapses.
verifyTrue(tc, all(r.dev_n_switch>=1));          % every IBR forms at the trip
verifyTrue(tc, all(r.dev_modes=="GFM"));         % formed island sustained until end
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
