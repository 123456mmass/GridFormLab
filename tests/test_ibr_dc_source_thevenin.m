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
%     not against the closed form that produced E_dc;
%   * the eigenvalue claim (10) is checked against a central finite difference of
%     dVdc/dt with respect to V_dc, which never uses the analytic formula;
%   * the "capacitance now matters" test falsifies the PREVIOUS closure, in which
%     C cancelled out of every residual, so a regression to it cannot pass.
tests = functiontests(localfunctions);
end

% =========================================================================
function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
tc.TestData.V = 1.02*exp(1i*0.08);
tc.TestData.params = struct('Sbase',100,'Mbase',100,'fbase',60, ...
    'dc_source',struct('Tdc',0.10,'eps_dc',0.10,'Pr',1.0, ...
        'Vdc_max',1.10,'delta_ch',0.02,'Pmax',1.06*1.2));
end

function [dev,y,ec] = device(tc,mode,P,Q)
V = tc.TestData.V;
dev = ibr.eecon49_dual_mode_model('IBR_DC',2,1,2,V,tc.TestData.params, ...
    P,Q,abs(V),mode);
y = [real(V);imag(V)];
ec = struct('hybrid_state',struct('device_modes',struct('IBR_DC',mode), ...
    'device_online',struct('IBR_DC',true)));
end

function p = params(tc,P,Q,Cdc)
p = ibr.dc_source_thevenin_params(tc.TestData.params.dc_source,1.0,Cdc, ...
    0.015,1.0,P,Q,tc.TestData.V);
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
        verifyEqual(tc,dev.x0(3),1.0,'AbsTol',0, ...
            'The DC state must still start at its declared nominal.');
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
end
end

% =========================================================================
function test_the_link_is_bounded_above_by_the_source_emf(tc)
% Proposition: for V_dc > E_dc every term is negative when P_ac >= 0, so
% V_dc(t) <= max(V_dc(0),E_dc) for all t. Checked directly on the rhs.
p = params(tc,0.45,0.08,0.10);
for Pac = [0 0.10 0.45 1.00 1.27]
    for over = [1e-9 0.001 0.01 0.10 0.50 1.00]
        v = p.Edc + over;
        dv = ibr.dc_source_thevenin_rhs(v,Pac,p);
        verifyLessThan(tc,dv,0, sprintf( ...
            'dVdc must be negative above E_dc: V_dc=%.6f P_ac=%.2f gave %+.3e', ...
            v,Pac,dv));
    end
end
end

% =========================================================================
function test_dc_eigenvalue_matches_an_independent_finite_difference(tc)
% Independent oracle for equation (10). A central difference of the rhs never
% touches the analytic expression, so agreement is evidence and not a tautology.
for Cdc = [0.05 0.10 0.20]
    p = params(tc,0.45,0.08,Cdc);
    h = 1e-6;
    fd = (ibr.dc_source_thevenin_rhs(p.Vdc0+h,p.Pac0,p) - ...
          ibr.dc_source_thevenin_rhs(p.Vdc0-h,p.Pac0,p))/(2*h);
    verifyEqual(tc,fd,p.lambda_dc,'RelTol',1e-6, sprintf( ...
        'Analytic lambda_dc disagrees with the finite difference at C=%.2f.',Cdc));
    verifyLessThan(tc,p.lambda_dc,0, ...
        'The DC mode must be stable at the dispatched point.');
end
end

% =========================================================================
function test_capacitance_now_enters_the_residual(tc)
% Falsifies the PREVIOUS closure. There, I_dc contained (C/Tdc)(Vdc0-Vdc) and the
% power feed-forward cancelled exactly, so C divided out and dVdc/dt did not
% depend on it at all. Here dVdc/dt must scale as 1/C.
pa = params(tc,0.45,0.08,0.10);
pb = params(tc,0.45,0.08,0.05);
va = ibr.dc_source_thevenin_rhs(1.02,pa.Pac0,pa);
vb = ibr.dc_source_thevenin_rhs(1.02,pb.Pac0,pb);
verifyEqual(tc,vb,2*va,'RelTol',1e-12, ...
    'Halving C_dc must double dVdc/dt; a C-independent rhs is the old ideal closure.');
verifyEqual(tc,pa.Edc,pb.Edc,'AbsTol',0, ...
    'E_dc must not depend on the capacitance.');
end

% =========================================================================
function test_chopper_is_inert_below_its_threshold_and_conducts_above(tc)
p = params(tc,0.45,0.08,0.10);
no_chopper = @(v,Pac) ((p.Edc-v)/p.Rdc - Pac/v)/p.Cdc;
for v = [0.90 1.00 p.Vdc_max]
    verifyEqual(tc,ibr.dc_source_thevenin_rhs(v,p.Pac0,p),no_chopper(v,p.Pac0), ...
        'AbsTol',1e-14, sprintf('Chopper must be inert at V_dc=%.4f.',v));
end
for v = p.Vdc_max + [1e-6 0.01 0.05]
    with = ibr.dc_source_thevenin_rhs(v,p.Pac0,p);
    verifyLessThan(tc,with,no_chopper(v,p.Pac0), sprintf( ...
        'Chopper must remove energy above the threshold at V_dc=%.4f.',v));
end
% And the derivation's inactivity claim for THIS dispatch is checkable.
verifyTrue(tc,p.chopper_inactive_by_bound, ...
    'E_dc <= Vdc_max is the stated reason the chopper never conducts here.');
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
    verifyError(tc,@() ibr.dc_source_thevenin_rhs(bad,p.Pac0,p), ...
        'ibr:dc_source_thevenin:dcVoltage', sprintf( ...
        'V_dc=%g must be reported as a domain violation.',bad));
end
verifyError(tc,@() ibr.dc_source_thevenin_rhs(NaN,p.Pac0,p), ...
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
