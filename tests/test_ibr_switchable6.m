function tests = test_ibr_switchable6
%TEST_IBR_SWITCHABLE6  Unit tests for the AGSI-based switchable 2-IBR study
%   (ibr.SwitchableIbr6, ibr.solve_pcc_infbus_equilibrium, ibr.two_ibr_infbus_tds).
%
%   Coverage:
%     - construction, contract, hysteresis/weight validation;
%     - PCC power-balance equilibrium residual;
%     - AGSI is small at the equilibrium (below the down-line);
%     - current-continuous ("bumpless") transfer identity in BOTH directions;
%     - flat baseline: no event => no switch, low AGSI, Newton converges;
%     - temporary weak-grid event => GFL->GFM then (on recovery) GFM->GFL;
%     - latch=true makes the switch one-way.
%
%   The switching equation (AGSI) follows EECON49-P4 as a design guideline; see
%   ibr.SwitchableIbr6. These are falsification tests for the supervisor +
%   driver, not a production-readiness claim.
tests = functiontests(localfunctions);
end

function setupOnce(~)
% Package CLASSES (classdef) in +ibr resolve via the MATLAB PATH, not merely the
% current folder: under the unittest framework the executing folder differs, so
% ibr.SwitchableIbr6 (and the driver's ibr.SwitchableIbr6 argument type) are not
% found by current-folder resolution the way package FUNCTIONS are. Add the repo
% root (parent of this tests/ folder, i.e. the +ibr package parent) to the path.
% This is a local, idempotent test fixture; it does not modify shared pf_init_paths.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
end

function s = setup_common()
s.params = struct();
s.Vinf = 1.0;
s.Zline = 0.30i;
s.Pref = 0.2;
s.Qref = 0.0;
s.d1 = ibr.SwitchableIbr6("IBR1",1,1,1,s.Vinf,s.params,s.Pref,s.Qref);
s.d2 = ibr.SwitchableIbr6("IBR2",1,1,1,s.Vinf,s.params,s.Pref,s.Qref);
s.Vpcc = ibr.solve_pcc_infbus_equilibrium(s.Vinf,s.Zline, ...
    [s.Pref+1i*s.Qref, s.Pref+1i*s.Qref]);
s.x1 = s.d1.gfl_dev.equilibrium_initialize(s.Vpcc,s.Pref,s.Qref,struct());
s.x2 = s.d2.gfl_dev.equilibrium_initialize(s.Vpcc,s.Pref,s.Qref,struct());
s.y = [real(s.Vpcc); imag(s.Vpcc)];
end

function test_construction_and_contract(tc)
s = setup_common();
verifyEqual(tc, s.d1.nx, 6);
verifyEqual(tc, char(s.d1.mode), 'gfl');
verifyTrue(tc, isstruct(s.d1.gfl_dev) && isstruct(s.d1.gfm_dev));
verifyEqual(tc, s.d1.gfl_dev.nx, 6);
verifyEqual(tc, s.d1.gfm_dev.nx, 6);
% AGSI defaults from EECON49-P4 sec 4.1
verifyEqual(tc, s.d1.AGSI_up, 0.65, 'AbsTol', 0);
verifyEqual(tc, s.d1.AGSI_down, 0.35, 'AbsTol', 0);
verifyEqual(tc, s.d1.w_V+s.d1.w_f+s.d1.w_R+s.d1.w_P, 1, 'AbsTol', 1e-12);
end

function test_invalid_config_fails_closed(tc)
% Hysteresis band must have AGSI_down < AGSI_up.
verifyError(tc, @() ibr.SwitchableIbr6("X",1,1,1,1.0,struct(),0.2,0, ...
    AGSI_up=0.4, AGSI_down=0.5), 'ibr:SwitchableIbr6:hysteresis');
% AGSI weights must sum to 1.
verifyError(tc, @() ibr.SwitchableIbr6("X",1,1,1,1.0,struct(),0.2,0, ...
    w_V=0.5, w_f=0.5, w_R=0.5, w_P=0.5), 'ibr:SwitchableIbr6:weights');
end

function test_pcc_equilibrium_residual(tc)
s = setup_common();
% Power-balance identity conj(V)*(V-Vinf)/Z = conj(Stot).
Stot = 2*(s.Pref+1i*s.Qref);
res = conj(s.Vpcc)*(s.Vpcc - s.Vinf)/s.Zline - conj(Stot);
verifyLessThan(tc, abs(res), 1e-10);
% Device injections + line = 0 (KCL) at the equilibrium.
I1 = s.d1.current_injection(s.x1, s.y);
I2 = s.d2.current_injection(s.x2, s.y);
kcl = I1 + I2 - (s.Vpcc - s.Vinf)/s.Zline;
verifyLessThan(tc, abs(kcl), 1e-10);
% Branch RHS ~ 0 at equilibrium (flat).
verifyLessThan(tc, max(abs(s.d1.f(s.x1,s.y))), 1e-9);
end

function test_agsi_low_at_equilibrium(tc)
s = setup_common();
agsi = s.d1.compute_index(s.x1, s.y, 0);
verifyLessThan(tc, agsi, s.d1.AGSI_down);   % below the down-line => calm
verifyGreaterThanOrEqual(tc, agsi, 0);
end

function test_agsipp_two_term_severity_index(tc)
% 2026-08-09 index-definition change: the implemented agsi_pp severity is the
% two-term J_V/J_f index [V f | R P SCR lock GRA] = [0.5 0.5 0 0 0 0 0] with
% bases dV_base=0.10 pu, df_base=0.50 Hz.  The 0.30:0.30 V:f ratio of
% EECON49-P4 sec 4.1 renormalised to sum 1 gives 0.5:0.5.  The five demoted
% stresses (J_R, J_P, J_SCR, J_lock, J_GRA) carry zero weight and remain
% diagnostics; this class does not claim unimplemented hard gates. GRA therefore
% has NO effect on the bounded index unless the explicit gra_override is enabled.
s = setup_common();
d1 = ibr.SwitchableIbr6("GRA1",1,1,1,s.Vinf,s.params,s.Pref,s.Qref, ...
    index_mode="agsi_pp", GRA=1);
d0 = ibr.SwitchableIbr6("GRA0",1,1,1,s.Vinf,s.params,s.Pref,s.Qref, ...
    index_mode="agsi_pp", GRA=0);
x1 = d1.gfl_dev.equilibrium_initialize(s.Vpcc,s.Pref,s.Qref,struct());
x0 = d0.gfl_dev.equilibrium_initialize(s.Vpcc,s.Pref,s.Qref,struct());
w = [d1.w_V d1.w_f d1.w_R d1.w_P d1.w_SCR d1.w_lock d1.w_GRA];
verifyEqual(tc,w,[0.5 0.5 0 0 0 0 0],'AbsTol',1e-15);
verifyEqual(tc,sum(w),1,'AbsTol',1e-12);          % weights still sum to 1
% GRA (weight 0) must not move the bounded index.
verifyLessThan(tc, abs(d0.compute_index(x0,s.y,0)-d1.compute_index(x1,s.y,0)), 1e-12);
verifyFalse(tc,d0.gra_override);
end

function test_agsipp_uses_validated_per_bus_voltage_reference(tc)
% Regression for the actual N-by-2 contract. The old constructor flattened the
% table to a row and compute_agsi then indexed it as if it still had two columns,
% so a per-bus reference was not usable in practice. Independent oracle: with
% |V|=0.95 at bus 6 and V_ref,6=1.05, J_V=1 and J_f=0, hence S=0.5 exactly.
s = setup_common();
y = [0.95;0];
d = ibr.SwitchableIbr6("VREF6",6,1,6,1.0,s.params,s.Pref,s.Qref, ...
    index_mode="agsi_pp", V_ref_per_bus=[2 0.99;6 1.05]);
x = d.gfl_dev.equilibrium_initialize(0.95,s.Pref,s.Qref,struct());
verifyEqual(tc,d.compute_index(x,y,0),0.5,'AbsTol',1e-12);
verifyError(tc,@() ibr.SwitchableIbr6("BAD",6,1,6,1.0,s.params,s.Pref,s.Qref, ...
    index_mode="agsi_pp",V_ref_per_bus=[6 1.05;6 1.04]), ...
    'ibr:SwitchableIbr6:invalidVRefPerBus');
missing = ibr.SwitchableIbr6("MISS",6,1,6,1.0,s.params,s.Pref,s.Qref, ...
    index_mode="agsi_pp",V_ref_per_bus=[2 0.99;3 0.97]);
xm = missing.gfl_dev.equilibrium_initialize(0.95,s.Pref,s.Qref,struct());
verifyError(tc,@() missing.compute_index(xm,y,0), ...
    'ibr:SwitchableIbr6:missingVRefForBus');
end

function test_bumpless_continuity_both_directions(tc)
% A mode transfer re-initialises to the equilibrium delivering the SAME (P,Q)
% at the SAME terminal V; both branches reproduce I = conj((P+jQ)/V), so the
% injected current is continuous whichever direction the switch goes.
s = setup_common();
Vt = 0.97*exp(1i*0.12); Pt = 0.2; Qt = 0.05; yt = [real(Vt);imag(Vt)];
Iexp = conj((Pt+1i*Qt)/Vt);
xg = s.d1.gfl_dev.equilibrium_initialize(Vt,Pt,Qt,struct());
xm = s.d1.gfm_dev.equilibrium_initialize(Vt,Pt,Qt,struct());
Ig = s.d1.gfl_dev.current_injection(0,xg,yt,[Pt;Qt],struct());
Im = s.d1.gfm_dev.current_injection(0,xm,yt,[Pt;Qt],struct());
verifyLessThan(tc, abs(Ig-Iexp), 1e-10);
verifyLessThan(tc, abs(Im-Iexp), 1e-10);
end

function test_flat_baseline_no_switch(tc)
s = setup_common();
o = ibr.two_ibr_infbus_tds(s.d1,s.d2,s.x1,s.x2,s.y,s.Vinf,s.Zline, ...
    T=0.4, dt=1e-3, event_time=inf, recover_time=inf);
verifyTrue(tc, o.newton_all_converged);
verifyEqual(tc, s.d1.n_switch, 0);
verifyEqual(tc, s.d2.n_switch, 0);
verifyLessThan(tc, max(o.index1), s.d1.AGSI_down);   % stays calm
% states essentially frozen at the equilibrium
verifyLessThan(tc, max(abs(o.X1(:,end)-s.x1)), 1e-6);
end

function test_temporary_event_bidirectional_switch(tc)
s = setup_common();
o = ibr.two_ibr_infbus_tds(s.d1,s.d2,s.x1,s.x2,s.y,s.Vinf,s.Zline, ...
    T=6, dt=1e-3, event_time=1.0, recover_time=2.0, ...
    Zline_factor=3.0, step_dphase_deg=60, step_dV=-0.05, newton_max_iter=80);
verifyTrue(tc, o.newton_all_converged);
% Each IBR switches GFL->GFM (up) and then GFM->GFL (down): two transitions.
verifyEqual(tc, s.d1.n_switch, 2);
verifyEqual(tc, s.d2.n_switch, 2);
verifyEqual(tc, char(s.d1.mode), 'gfl');   % back to grid-following after recovery
verifyEqual(tc, char(s.d2.mode), 'gfl');
% up-switch occurs after the event, down-switch after recovery.
ev = o.switch_events;
verifyEqual(tc, size(ev,1), 4);
up1 = ev(find(ev(:,2)==1 & ev(:,4)==1,1),1);
dn1 = ev(find(ev(:,2)==1 & ev(:,4)==0,1),1);
verifyGreaterThanOrEqual(tc, up1, 1.0);
verifyGreaterThan(tc, dn1, 2.0);
verifyGreaterThan(tc, dn1, up1);
% AGSI exceeded the up-line at some point (trigger really happened).
verifyGreaterThanOrEqual(tc, max(o.index1), s.d1.AGSI_up);
% settled near nominal frequency at the end
verifyLessThan(tc, abs(o.f1(end)-60), 0.1);
end

function test_solve_case_route(tc)
% End-to-end: the two-IBR switch case is runnable through the solve_case
% launcher (analysis='ibr', case='two_ibr_switch'), returning a converged
% bidirectional-switch result.
r = solve_case('analysis','ibr','case','two_ibr_switch', ...
    'options',struct('plot_results',false,'t_end',6.0));
verifyTrue(tc, r.converged);
verifyEqual(tc, r.dev1.n_switch, 2);          % GFL->GFM->GFL
verifyEqual(tc, char(r.dev1.final_mode), 'gfl');
verifyEqual(tc, r.dev2.n_switch, 2);
verifyEqual(tc, size(r.switch_events,1), 4);
verifyEqual(tc, r.metadata.device_count, 2);
end

function test_agsipp_no_chatter_and_bounded_index(tc)
% AGSI++ (filtered RoCoF + J_SCR + J_lock) switches cleanly (2 transitions per
% device) with NO dwell, where the baseline AGSI chatters (>2) without dwell,
% and AGSI++ keeps the index bounded (no one-sample RoCoF spike).
o_base = run_switch_cfg("agsi",    0, 0);   % baseline, no dwell -> chatters
o_pp   = run_switch_cfg("agsi_pp", 0, 0);   % AGSI++,  no dwell -> clean
verifyTrue(tc, o_base.newton_all_converged);
verifyTrue(tc, o_pp.newton_all_converged);
verifyGreaterThan(tc, o_base.dev1_n_switch, 2);   % baseline chatters
verifyEqual(tc, o_pp.dev1_n_switch, 2);           % AGSI++ clean 2-switch cycle
verifyEqual(tc, char(o_pp.dev1_mode), 'gfl');
verifyGreaterThanOrEqual(tc,min(o_pp.index1),0);
verifyLessThanOrEqual(tc,max(o_pp.index1),1);     % normalized decision index
verifyGreaterThanOrEqual(tc,min(o_base.index1),0);
verifyLessThanOrEqual(tc,max(o_base.index1),1);   % raw RoCoF stays diagnostic
end

function o = run_switch_cfg(mode, ton, toff)
params = struct(); Vinf = 1.0; Zline = 0.30i; Pref = 0.2; Qref = 0.0;
Vpcc = ibr.solve_pcc_infbus_equilibrium(Vinf, Zline, [Pref+1i*Qref, Pref+1i*Qref]);
d1 = ibr.SwitchableIbr6("IBR1",1,1,1,Vinf,params,Pref,Qref, ...
    index_mode=mode, T_d_on=ton, T_d_off=toff);
d2 = ibr.SwitchableIbr6("IBR2",1,1,1,Vinf,params,Pref,Qref, ...
    index_mode=mode, T_d_on=ton, T_d_off=toff);
x1 = d1.gfl_dev.equilibrium_initialize(Vpcc,Pref,Qref,struct());
x2 = d2.gfl_dev.equilibrium_initialize(Vpcc,Pref,Qref,struct());
y  = [real(Vpcc); imag(Vpcc)];
o = ibr.two_ibr_infbus_tds(d1,d2,x1,x2,y,Vinf,Zline, T=8, dt=1e-3, ...
    event_time=1.5, recover_time=4.0, step_ramp=0.40, Zline_factor=4.0, ...
    step_dphase_deg=0, step_dV=0, newton_max_iter=80);
end

function test_latch_is_one_way(tc)
% With latch=true a device that reaches GFM never returns to GFL.
params = struct(); Vinf = 1.0; Zline = 0.30i; Pref = 0.2; Qref = 0;
d1 = ibr.SwitchableIbr6("IBR1",1,1,1,Vinf,params,Pref,Qref,latch=true);
d2 = ibr.SwitchableIbr6("IBR2",1,1,1,Vinf,params,Pref,Qref,latch=true);
Vpcc = ibr.solve_pcc_infbus_equilibrium(Vinf,Zline,[Pref+1i*Qref,Pref+1i*Qref]);
x1 = d1.gfl_dev.equilibrium_initialize(Vpcc,Pref,Qref,struct());
x2 = d2.gfl_dev.equilibrium_initialize(Vpcc,Pref,Qref,struct());
y = [real(Vpcc); imag(Vpcc)];
o = ibr.two_ibr_infbus_tds(d1,d2,x1,x2,y,Vinf,Zline, ...
    T=6, dt=1e-3, event_time=1.0, recover_time=2.0, ...
    Zline_factor=3.0, step_dphase_deg=60, step_dV=-0.05, newton_max_iter=80);
verifyTrue(tc, o.newton_all_converged);
verifyEqual(tc, char(d1.mode), 'GFM');   % latched: stays GFM after recovery
verifyEqual(tc, d1.n_switch, 1);
verifyEqual(tc, char(d2.mode), 'GFM');
end
