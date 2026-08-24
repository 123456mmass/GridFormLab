function tests = test_ibr_dc_source_thevenin
%TEST_IBR_DC_SOURCE_THEVENIN  Falsification tests for the non-ideal DC source.
%
% The DC-link closure is PROJECT_DERIVED: the EECON49 source publishes the DC
% energy balance but not the law for I_dc. These tests are written to FALSIFY the
% derivation recorded in ibr.dc_source_thevenin_params, not to confirm it, so each
% one checks a property against an independent computation rather than against a
% number copied out of the implementation.
%
% Independent oracles used here:
%   * the equilibrium claim is checked against the device right-hand side itself,
%     not against the closed form that produced E_dc and Idc0;
%   * the 2x2 DC eigenvalues are checked against a central finite-difference
%     Jacobian of the two rows, which never uses the analytic A_dc;
%   * the tau_s -> 0 degeneracy is checked against the resistive model's scalar
%     eigenvalue, so the earlier revision is provably a special case;
%   * the "capacitance now matters" test falsifies the ORIGINAL ideal closure, in
%     which C cancelled out of every residual, so a regression cannot pass.
tests = functiontests(localfunctions);
end

% =========================================================================
function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
tc.TestData.V = 1.02*exp(1i*0.08);
tc.TestData.params = struct('Sbase',100,'Mbase',100,'fbase',60, ...
    'dc_source',struct('Tdc',0.10,'eps_dc',0.10,'Pr',1.0, ...
        'Vdc_max',1.10,'delta_ch',0.02,'Pmax',1.06*1.2, ...
        'source_state',true,'tau_s',0.005,'zeta_target',1/sqrt(2)));
end

function [dev,y,ec] = device(tc,mode,P,Q)
V = tc.TestData.V;
dev = ibr.eecon49_dual_mode_model('IBR_DC',2,1,2,V,tc.TestData.params, ...
    P,Q,abs(V),mode);
y = [real(V);imag(V)];
ec = struct('hybrid_state',struct('device_modes',struct('IBR_DC',mode), ...
    'device_online',struct('IBR_DC',true)));
end

function p = params(tc,P,Q,Cdc,extra)
dc = tc.TestData.params.dc_source;
if nargin >= 5
    f = fieldnames(extra);
    for k = 1:numel(f), dc.(f{k}) = extra.(f{k}); end
end
p = ibr.dc_source_thevenin_params(dc,1.0,Cdc,0.015,1.0,P,Q,tc.TestData.V);
end

function J = dc_jacobian(p,v,i,Pac)
% Central finite-difference Jacobian of the two DC rows. Never touches A_dc.
h = 1e-7;
fv = @(vv,ii) ibr.dc_source_thevenin_rhs(vv,ii,Pac,p);
J = [ (fv(v+h,i)-fv(v-h,i))/(2*h), (fv(v,i+h)-fv(v,i-h))/(2*h) ];
end

% =========================================================================
function test_dispatched_point_is_an_exact_equilibrium_of_the_dc_row(tc)
% E_dc is claimed to be FORCED by the requirement that the dispatched point be an
% equilibrium. The check evaluates the device right-hand side, which is a
% different code path from the closed form that computed E_dc.
for mode = {'gfl','GFM'}
    for PQ = {[0.45 0.08],[0.30 0.15],[0.85 -0.05],[0.10 0.00]}
        P = PQ{1}(1); Q = PQ{1}(2);
        [dev,y,ec] = device(tc,mode{1},P,Q);
        dx = dev.f(0,dev.x0,y,dev.u0,ec);
        verifyLessThan(tc,abs(dx(3)),1e-11, sprintf( ...
            '%s at P=%.2f Q=%.2f: dVdc(0) must vanish, got %.3e', ...
            mode{1},P,Q,dx(3)));
        verifyLessThan(tc,abs(dx(17)),1e-11, sprintf( ...
            '%s at P=%.2f Q=%.2f: dIdc(0) must vanish, got %.3e', ...
            mode{1},P,Q,dx(17)));
        verifyEqual(tc,dev.x0(3),1.0,'AbsTol',0, ...
            'The DC voltage must still start at its declared nominal.');
        pp = params(tc,P,Q,0.10);
        verifyEqual(tc,dev.x0(17),pp.Idc0,'AbsTol',1e-12, ...
            'The source current must start at Pac0/Vdc0.');
    end
end
end

% =========================================================================
function test_both_controller_branches_use_the_same_dc_source(tc)
% If E_dc ever differed between GFL and GFM, a runtime transfer would step
% dVdc/dt even though it preserves V_dc. That must be impossible by construction.
P = 0.45; Q = 0.08;
[gfl,y,ecl] = device(tc,'gfl',P,Q);
[gfm,~,ecm] = device(tc,'GFM',P,Q);
for vdc = [0.85 0.95 1.00 1.05 1.09]
    xl = gfl.x0; xl(3) = vdc;
    xm = gfm.x0; xm(3) = vdc;
    dl = gfl.f(0,xl,y,gfl.u0,ecl);
    dm = gfm.f(0,xm,y,gfm.u0,ecm);
    verifyEqual(tc,dl(3),dm(3),'AbsTol',1e-14, sprintf( ...
        'GFL and GFM disagree on dVdc/dt at V_dc=%.2f.',vdc));
    verifyEqual(tc,dl(17),dm(17),'AbsTol',1e-14, sprintf( ...
        'GFL and GFM disagree on dIdc/dt at V_dc=%.2f.',vdc));
end
end

% =========================================================================
function test_the_dc_pair_is_stable_and_matches_its_analytic_block(tc)
% With the source current a state, the DC circuit is a 2x2, so "bounded" is no
% longer a sign argument on one row -- it is stability of the pair. The pair is
% checked against a finite-difference Jacobian, which never forms A_dc.
for PQ = {[0.45 0.08],[0.30 0.15],[0.85 -0.05]}
    P = PQ{1}(1); Q = PQ{1}(2);
    p = params(tc,P,Q,0.10);
    J = dc_jacobian(p,p.Vdc0,p.Idc0,p.Pac0);
    lam_fd = sort(eig(J),'ComparisonMethod','real');
    lam_an = sort(p.lambda_dc_pair(:),'ComparisonMethod','real');
    verifyEqual(tc,lam_fd,lam_an,'RelTol',1e-5, sprintf( ...
        'Reported DC pair disagrees with the FD Jacobian at P=%.2f.',P));
    verifyLessThan(tc,max(real(lam_fd)),0, ...
        'Both DC eigenvalues must lie in the left half-plane.');
    verifyGreaterThan(tc,p.zeta_dc,0, 'The DC pair must be damped.');
    verifyLessThan(tc,p.tau_s,p.tau_s_stability_max, ...
        'tau_s must stay inside the constant-power-load bound.');
end
end

% =========================================================================
function test_tau_s_to_zero_recovers_the_resistive_model(tc)
% The previous revision had no source state. That is the tau_s -> 0 limit, and it
% must be recovered, otherwise the two revisions are different models rather than
% one model and its limit.
P = 0.45; Q = 0.08;
prev = inf;
for tau = [1e-3 1e-4 1e-5 1e-6]
    p = params(tc,P,Q,0.10,struct('tau_s',tau));
    lam = p.lambda_dc_pair(:);
    [~,i] = max(real(lam));               % the slow root
    err = abs(real(lam(i)) - p.lambda_dc);
    verifyLessThan(tc,err,prev, ...
        'The slow root must approach the resistive eigenvalue as tau_s falls.');
    prev = err;
end
verifyLessThan(tc,prev,1e-2, ...
    'At tau_s = 1e-6 the slow root must match the resistive eigenvalue.');
end

% =========================================================================
function test_a_too_slow_source_fails_closed(tc)
% trace(A_dc) < 0 requires tau_s < C Vdc0^2 / Pac0. A source slower than that
% cannot hold a constant-power load, and the helper must refuse rather than
% publish an unstable link.
P = 0.45; Q = 0.08;
p = params(tc,P,Q,0.10);
verifyError(tc,@() params(tc,P,Q,0.10, ...
    struct('tau_s',p.tau_s_stability_max*1.01)), ...
    'ibr:dc_source_thevenin:tauUnstable');
verifyError(tc,@() params(tc,P,Q,0.10,struct('tau_s',0)), ...
    'ibr:dc_source_thevenin:tau');
end

% =========================================================================
function test_declared_tau_s_meets_the_maximally_flat_criterion(tc)
% tau_s is declared as a component value, but it must agree with the closed-form
% maximally-flat solution it was derived from, and the realised zeta must be the
% target across the dispatch range -- otherwise "one component value serves the
% whole range" is an unchecked claim.
for P = [0.30 0.45 0.90]
    p = params(tc,P,0.08,0.10);
    verifyEqual(tc,p.tau_s,p.tau_s_maxflat,'RelTol',0.05, sprintf( ...
        'Declared tau_s must stay near the maximally-flat value at P=%.2f.',P));
    verifyEqual(tc,p.zeta_dc,p.zeta_target,'AbsTol',0.02, sprintf( ...
        'Realised zeta must meet the target at P=%.2f.',P));
end
end

% =========================================================================
function test_the_link_is_bounded_above_by_the_source_emf(tc)
% The scalar bound V_dc <= E_dc belonged to the resistive model. With the source
% current a state the inductor can overshoot, so what survives is the weaker and
% correct statement: the SOURCE ROW pushes I_dc down whenever V_dc exceeds E_dc,
% which is what makes the pair recover. Checked directly on the rhs.
p = params(tc,0.45,0.08,0.10);
for idc = [0 p.Idc0 2*p.Idc0]
    for over = [1e-9 0.001 0.01 0.10 0.50 1.00]
        v = p.Edc + over;
        dv = ibr.dc_source_thevenin_rhs(v,idc,p.Pac0,p);
        verifyLessThan(tc,dv(2),0, sprintf( ...
            'dIdc must be negative above E_dc: V_dc=%.6f I_dc=%.3f gave %+.3e', ...
            v,idc,dv(2)));
    end
end
end

% =========================================================================
function test_absorption_can_push_the_link_past_the_emf_and_the_chopper(tc)
% Falsifies the claim the reports and the helper comment once made, that the
% chopper is "provably inactive here". The bound of the previous test holds only
% while P_ac >= 0. With P_ac < 0 the load term becomes a CHARGING term, so
% dVdc/dt is positive above E_dc and the link climbs to the chopper threshold.
% Measured instance in the delivered evidence: on the four-GFM pinned arm IBR1
% sits at |i| ~ 1.204 pu absorbing P_ac in [-0.925,-0.747] pu and its link
% exceeds V_dc,max for 94 accepted samples, peaking at 1.103080 pu.
p = params(tc,0.45,0.08,0.10);
for Pac = [-0.20 -0.75 -0.92]
    idc_eq = (p.Edc - (p.Edc+0.01))/p.Rdc;
    dv = ibr.dc_source_thevenin_rhs(p.Edc+0.01,idc_eq,Pac,p); dv = dv(1);
    verifyGreaterThan(tc,dv,0, sprintf( ...
        'Absorbing P_ac=%.2f must charge the link above E_dc, got dVdc=%+.3e.', ...
        Pac,dv));
end
% And the climb genuinely reaches conduction: the equilibrium of the chopper-off
% row at P_ac < 0 is the root of V^2 - Edc*V + Rdc*Pac = 0 above Edc, which for
% these powers exceeds V_dc,max, so the chopper is what stops it.
for Pac = [-0.75 -0.92]
    v_eq = (p.Edc + sqrt(p.Edc^2 - 4*p.Rdc*Pac))/2;
    verifyGreaterThan(tc,v_eq,p.Vdc_max, sprintf( ...
        'At P_ac=%.2f the chopper-off equilibrium %.4f must exceed V_dc,max.', ...
        Pac,v_eq));
    % With the chopper in circuit the rise is arrested below that value.
    % Evaluate on the SLOW MANIFOLD, where the source current has settled to its
    % own row's equilibrium for this voltage. Holding I_dc at its dispatched value
    % instead would ask about a different system: the source would be delivering
    % the wrong current for the voltage it sees.
    idc_eq = (p.Edc - v_eq)/p.Rdc;
    dvq = ibr.dc_source_thevenin_rhs(v_eq,idc_eq,Pac,p);
    verifyLessThan(tc,dvq(1),0, ...
        'The chopper must remove the excess at the chopper-off equilibrium.');
end
% The reported flag is a property of the DISPATCHED point only, and its name says
% so. It must not be read as a statement about every trajectory.
verifyTrue(tc,p.chopper_inactive_by_bound);
verifyEqual(tc,p.chopper_inactive_by_bound,p.Edc<=p.Vdc_max);
end

% =========================================================================
function test_dc_eigenvalue_matches_an_independent_finite_difference(tc)
% Independent oracle for equation (10). A central difference of the rhs never
% touches the analytic expression, so agreement is evidence and not a tautology.
for Cdc = [0.05 0.10 0.20]
    p = params(tc,0.45,0.08,Cdc);
    h = 1e-6;
    dp = ibr.dc_source_thevenin_rhs(p.Vdc0+h,p.Idc0,p.Pac0,p);
    dm = ibr.dc_source_thevenin_rhs(p.Vdc0-h,p.Idc0,p.Pac0,p);
    fd = (dp(1)-dm(1))/(2*h);
    % d(dVdc/dt)/dVdc is +Pac/(C Vdc^2): the constant-power-load term alone,
    % because the resistive path now sits in the SOURCE row, not this one.
    verifyEqual(tc,fd,p.Pac0/(Cdc*p.Vdc0^2),'RelTol',1e-5, sprintf( ...
        'Voltage-row slope disagrees with the CPL term at C=%.2f.',Cdc));
    verifyLessThan(tc,max(real(p.lambda_dc_pair)),0, ...
        'The DC pair must be stable at the dispatched point.');
end
end

% =========================================================================
function test_capacitance_now_enters_the_residual(tc)
% Falsifies the PREVIOUS closure. There, I_dc contained (C/Tdc)(Vdc0-Vdc) and the
% power feed-forward cancelled exactly, so C divided out and dVdc/dt did not
% depend on it at all. Here dVdc/dt must scale as 1/C.
pa = params(tc,0.45,0.08,0.10);
pb = params(tc,0.45,0.08,0.05);
va = ibr.dc_source_thevenin_rhs(1.02,pa.Idc0,pa.Pac0,pa); va = va(1);
vb = ibr.dc_source_thevenin_rhs(1.02,pb.Idc0,pb.Pac0,pb); vb = vb(1);
verifyEqual(tc,vb,2*va,'RelTol',1e-12, ...
    'Halving C_dc must double dVdc/dt; a C-independent rhs is the old ideal closure.');
verifyEqual(tc,pa.Edc,pb.Edc,'AbsTol',0, ...
    'E_dc must not depend on the capacitance.');
end

% =========================================================================
function test_chopper_is_inert_below_its_threshold_and_conducts_above(tc)
p = params(tc,0.45,0.08,0.10);
% The voltage row with the chopper out of circuit. I_dc is a state now, so the
% reference expression uses it rather than the static Thevenin current.
no_chopper = @(v,Pac) (p.Idc0 - Pac/v)/p.Cdc;
for v = [0.90 1.00 p.Vdc_max]
    dvv = ibr.dc_source_thevenin_rhs(v,p.Idc0,p.Pac0,p);
    verifyEqual(tc,dvv(1),no_chopper(v,p.Pac0), ...
        'AbsTol',1e-14, sprintf('Chopper must be inert at V_dc=%.4f.',v));
end
for v = p.Vdc_max + [1e-6 0.01 0.05]
    with = ibr.dc_source_thevenin_rhs(v,p.Idc0,p.Pac0,p); with = with(1);
    verifyLessThan(tc,with,no_chopper(v,p.Pac0), sprintf( ...
        'Chopper must remove energy above the threshold at V_dc=%.4f.',v));
end
% The flag is about the dispatched point, not about every trajectory; the
% absorption test above shows a delivered arm where the chopper does conduct.
verifyTrue(tc,p.chopper_inactive_by_bound, ...
    'E_dc <= Vdc_max must hold at the dispatched point.');
verifyLessThanOrEqual(tc,p.Edc,p.Vdc_max, ...
    'The bound flag must agree with the numbers it summarises.');
end

% =========================================================================
function test_domain_violation_throws_the_identifier_the_stepper_registers(tc)
% stability/ts_step_composite.m classifies this exact identifier as a line-search
% domain rejection. If the identifier changes, a trial that probes V_dc <= 0
% aborts the whole simulation instead of shortening the step.
p = params(tc,0.45,0.08,0.10);
for bad = [0, -0.5, 1e-9]
    verifyError(tc,@() ibr.dc_source_thevenin_rhs(bad,p.Idc0,p.Pac0,p), ...
        'ibr:dc_source_thevenin:dcVoltage', sprintf( ...
        'V_dc=%g must be reported as a domain violation.',bad));
end
verifyError(tc,@() ibr.dc_source_thevenin_rhs(NaN,p.Idc0,p.Pac0,p), ...
    'ibr:dc_source_thevenin:dcVoltage');
end

% =========================================================================
function test_stability_and_reachability_margins_are_reported_and_satisfied(tc)
p = params(tc,0.45,0.08,0.10);
% Constant-power-load condition R_dc < Vdc0^2/Pac0, reported as a margin.
verifyGreaterThan(tc,p.cpl_stability_margin,1, ...
    'The negative incremental resistance of the constant-power load must not win.');
verifyEqual(tc,p.cpl_stability_margin,(p.Vdc0^2/p.Pac0)/p.Rdc,'RelTol',1e-12);
% Reachability of the largest current-limited power, equation (6).
verifyGreaterThan(tc,p.discriminant_margin,1, ...
    'The link must support the largest power the current limiter permits.');
end

% =========================================================================
function test_invalid_declared_parameters_fail_closed(tc)
base = tc.TestData.params.dc_source;
bad = { 'eps_dc',   0,    'ibr:dc_source_thevenin:eps'    ; ...
        'eps_dc',  -0.1,  'ibr:dc_source_thevenin:eps'    ; ...
        'Pr',       0,    'ibr:dc_source_thevenin:Pr'     ; ...
        'Vdc_max',  0,    'ibr:dc_source_thevenin:Vdcmax' ; ...
        'delta_ch', 0,    'ibr:dc_source_thevenin:delta'  ; ...
        'Rch',     -1,    'ibr:dc_source_thevenin:Rch'    };
for k = 1:size(bad,1)
    d = base; d.(bad{k,1}) = bad{k,2};
    verifyError(tc,@() ibr.dc_source_thevenin_params(d,1.0,0.10,0.015,1.0, ...
        0.45,0.08,tc.TestData.V), bad{k,3}, ...
        sprintf('%s=%g must fail closed.',bad{k,1},bad{k,2}));
end
% The capacitance is validated too, and only in the helper, so the models cannot
% silently accept a non-physical link.
verifyError(tc,@() ibr.dc_source_thevenin_params(base,1.0,0,0.015,1.0, ...
    0.45,0.08,tc.TestData.V),'ibr:dc_source_thevenin:Cdc');
verifyError(tc,@() ibr.dc_source_thevenin_params(base,1.0,0.10,0.015,1.0, ...
    0.45,0.08,0),'ibr:dc_source_thevenin:V0');
end
