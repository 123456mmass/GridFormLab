function tests = test_emf6_contract()
%TEST_EMF6_CONTRACT Equation-derived contract tests for the unified EMF6 model.
%   These tests verify the operational EMF6 model (stability.emf6_dae /
%   stability.synchronous_emf6_ssa) from its equations, not from Kundur
%   Table E12.3. Tolerances are declared up front from numerical precision,
%   integration order, timestep and equation scaling -- they are not relaxed
%   after seeing a result.
%
%   Categories (required by the project task):
%     1. No-fault equilibrium (f, g and trajectory drift ~ 0)
%     2. SSSA / TS share the same emf6_dae (same residual on same input)
%     3. Initialization consistency (initializer output zeroes runtime DAE)
%     4. Torque / power identity (sign, current convention, stator loss)
%     5. Reference-angle invariance (common rotor+network rotation)
%     7. Regression (classical Case14 / RTS-24 baselines undisturbed)
%   Category 6 (production dependency guard) lives in
%   test_no_external_solver_dependency.m.

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function [c,dae] = emf6_fixture(load_model)
% Shared fixture: the Kundur 12.6 case and its unified EMF6 DAE.
if nargin < 1, load_model = 'cz'; end
c = cases.kundur_ex126_book_case();
dae = stability.emf6_dae(c, struct('load_model',load_model));
end

% Tolerances (declared up front).
%   EQ_TOL  : equilibrium residual. The initializer solves angle init to
%             1e-10 (nonlinear_newton) and the DAE residual is ~1e-14, so
%             1e-10 is conservative.
%   DRIFT_TOL: no-fault trapezoidal drift. Starting at a machine-precision
%             equilibrium with a tight algebraic solve (1e-12), the implicit
%             trapezoidal rule accumulates only round-off (~1e-12); 1e-9 is
%             conservative for a multi-second run.
%   ROUND_TOL: analytic invariance / identity. These hold to machine
%             precision; 1e-10 is conservative.

function test_1_no_fault_equilibrium(testCase)
% (1) No fault, no topology change. The operating point must be an
% equilibrium: max|f| and max|g| below tolerance, and the simulated state,
% voltage, speed and generator power must not drift.
[c,dae] = emf6_fixture('cz');
EQ_TOL = 1e-10;  DRIFT_TOL = 1e-9;
f0 = dae.dae_f(dae.init.x0, dae.init.y0);
g0 = dae.dae_g(dae.init.x0, dae.init.y0, dae.Ynet);
testCase.verifyLessThan(norm(f0,inf), EQ_TOL, 'differential residual max|f|');
testCase.verifyLessThan(norm(g0,inf), EQ_TOL, 'algebraic residual max|g|');
% Run a no-fault TS on the same equation set.
opt = struct('model','emf6','t_end',2.0,'dt',0.01,'fault_bus',8, ...
    't_fault',99,'t_clear',99.1,'Zf',1i*0.1,'method','trapezoidal', ...
    'corrector_mode','fixed','corrector_iter',2,'load_model','cz','verbose',false);
r = stability.ts_simulate(c, opt);
testCase.verifyEqual(r.nonconverged_step_count, 0, 'no-fault steps must converge');
testCase.verifyLessThan(max(abs(r.delta(end,:) - r.delta(1,:)),[],'all'), DRIFT_TOL, ...
    'rotor-angle drift');
testCase.verifyLessThan(max(abs(r.omega),[],'all'), DRIFT_TOL, 'speed-deviation drift');
testCase.verifyLessThan(max(abs(r.Vbus(end,:) - r.Vbus(1,:)),[],'all'), DRIFT_TOL, ...
    'bus-voltage drift');
testCase.verifyLessThan(max(abs(r.Pe_pu(end,:) - r.Pe_pu(1,:)),[],'all'), DRIFT_TOL, ...
    'generator power drift');
end

function test_2_sssa_and_ts_share_emf6_dae(testCase)
% (2) SSSA and TS must call the SAME emf6_dae. Proved by comparing residuals
% on the SAME (x, y) input -- including a perturbed state -- not by file name.
[c,dae] = emf6_fixture('cz');
ssa = stability.synchronous_emf6_ssa(c, struct('load_model','cz'));
% Same residual at the operating point (both built from emf6_dae's equations).
rf_s = norm(ssa.dae_f(dae.init.x0, dae.init.y0), inf);
rf_d = norm(dae.dae_f(dae.init.x0, dae.init.y0), inf);
testCase.verifyEqual(rf_s, rf_d, 'AbsTol', 1e-13);
% Identical output on a PERTURBED state (proves the equations, not just the
% equilibrium, are the same function).
rng(0,'twister');
xp = dae.init.x0 + 1e-3*randn(numel(dae.init.x0),1);
yp = dae.init.y0 + 1e-3*randn(numel(dae.init.y0),1);
testCase.verifyEqual(norm(ssa.dae_f(xp,yp) - dae.dae_f(xp,yp),inf), 0, 'AbsTol', 1e-13);
testCase.verifyEqual(norm(ssa.dae_g(xp,yp,dae.Ynet) - dae.dae_g(xp,yp,dae.Ynet),inf), 0, 'AbsTol', 1e-13);
% TS reports its initial residual from the same handles.
opt = struct('model','emf6','t_end',0.02,'dt',0.01,'fault_bus',8, ...
    't_fault',1,'t_clear',1.1,'Zf',1i*0.1,'method','trapezoidal', ...
    'corrector_mode','fixed','corrector_iter',1,'load_model','cz','verbose',false);
r = stability.ts_simulate(c, opt);
combined = norm([dae.dae_f(dae.init.x0,dae.init.y0); ...
                 dae.dae_g(dae.init.x0,dae.init.y0,dae.Ynet)], inf);
testCase.verifyEqual(r.initial_dae_residual, combined, 'AbsTol', 1e-12, ...
    'TS initial residual must equal the shared DAE residual');
testCase.verifyEqual(r.engine, 'stability.synchronous_emf6_ssa');
testCase.verifyEqual(r.model_key, 'emf6');
end

function test_3_initialization_consistency(testCase)
% (3) The operating point returned by the initializer must zero the RUNTIME
% DAE residual. The initializer and the runtime use one equation set.
[~,dae] = emf6_fixture('cz');
EQ_TOL = 1e-10;
init = dae.init;
% Runtime residual at the initializer's (x0, y0), using the runtime handles.
rf = norm(dae.dae_f(init.x0, init.y0), inf);
rg = norm(dae.dae_g(init.x0, init.y0, dae.Ynet), inf);
testCase.verifyLessThan(rf, EQ_TOL, 'runtime differential residual at init');
testCase.verifyLessThan(rg, EQ_TOL, 'runtime algebraic residual at init');
% The initializer used the in-house Newton solver (not fsolve).
testCase.verifyTrue(isfield(init,'newton_iterations') && init.newton_iterations >= 0);
% Independent consistency: the EMF6 terminal real power (network frame,
% from init Id/Iq) must equal the PF-solved generation at each generator bus.
% (init.Tm is the same formula as electrical_power, so Pe0==Tm would be
% circular; instead we cross-check against the independent PF result.)
Pe_net = zeros(init.ng,1);
for k=1:init.ng
    b=init.bus_idx(k); V=complex(init.y0(2*b-1),init.y0(2*b));
    delta=init.x0((k-1)*6+1);
    Ig=stability.kundur_book_network_current(init.Id(k),init.Iq(k),delta);
    Pe_net(k)=real(V*conj(Ig));
end
testCase.verifyLessThan(max(abs(Pe_net - dae.pf.P_generation(init.bus_idx))), EQ_TOL, ...
    'EMF6 terminal Pe == PF generation (independent of init.Tm)');
end

function test_4_torque_power_identity(testCase)
% (4) Torque / power identity from INDEPENDENT calculations (not circular
% with init.Tm or the swing equation):
%   (a) frame invariance:  Vd*Id+Vq*Iq  ==  real(V*conj(Ig))
%       (dq-frame power vs network-phasor power; Ig = kundur_book_network_current)
%   (b) stator copper loss: Te = (Vd*Id+Vq*Iq) + Ra*(Id^2+Iq^2)
%       where Te = dae.electrical_power (direct electrical torque)
%   (c) PF consistency: real(V*conj(Ig)) ~= pf.P_generation  (EMF6 vs PF solver)
%   (d) sign: generator injects real power (>0 into network)
[c,dae] = emf6_fixture('cc_p_cz_q');
ROUND_TOL = 1e-10;
init = dae.init;
Ra = c.machines.reactances.Ra * (c.base_values.S_base_MVA/c.machines.base.S_MVA);
Te_dae = dae.electrical_power(init.x0, init.y0);   % direct electrical torque
Pe_dq = zeros(init.ng,1); Pe_net = zeros(init.ng,1); Te_loss = zeros(init.ng,1);
for k = 1:init.ng
    b = init.bus_idx(k);
    V = complex(init.y0(2*b-1), init.y0(2*b));
    delta = init.x0((k-1)*6+1);
    [Vd,Vq] = stability.kundur_book_dq(V, delta);
    Ig = stability.kundur_book_network_current(init.Id(k), init.Iq(k), delta);
    Pe_dq(k)  = Vd*init.Id(k) + Vq*init.Iq(k);          % dq-frame terminal power
    Pe_net(k) = real(V*conj(Ig));                        % network-frame terminal power
    Te_loss(k) = Ra*(init.Id(k)^2 + init.Iq(k)^2);       % stator copper loss
end
% (a) frame invariance: dq and network frames give the same terminal power.
testCase.verifyLessThan(max(abs(Pe_dq - Pe_net)), ROUND_TOL, ...
    'Pe(dq frame) == Pe(network frame)');
% (b) stator copper loss: air-gap torque = terminal power + stator loss.
testCase.verifyLessThan(max(abs(Te_dae - (Pe_dq + Te_loss))), ROUND_TOL, ...
    'Te = Pe_terminal + Ra*(Id^2+Iq^2) (stator loss accounted)');
% (c) independent PF consistency: network terminal Pe == PF-solved generation.
testCase.verifyLessThan(max(abs(Pe_net - dae.pf.P_generation(init.bus_idx))), ROUND_TOL, ...
    'terminal Pe == PF generation (independent solver)');
% (d) sign convention: generators inject real power into the network.
testCase.verifyTrue(all(Pe_net > 0), 'generator current positive into network');
end

function test_5_reference_angle_invariance(testCase)
% (5) A common rotation of all rotor angles AND all network phasors must
% leave the physical outputs (differential residual, electrical torque)
% unchanged. This is the reference-frame invariance of the DAE.
[~,dae] = emf6_fixture('cz');
ROUND_TOL = 1e-10;
x0 = dae.init.x0; y0 = dae.init.y0;
dphi = 0.27;  % arbitrary rotation (rad)
xp = x0;
xp(1:6:end) = x0(1:6:end) + dphi;            % rotate every rotor angle
V = complex(y0(1:2:end), y0(2:2:end));
Vr = V * exp(1i*dphi);                        % rotate every network phasor
yp = y0; yp(1:2:end) = real(Vr); yp(2:2:end) = imag(Vr);
% Differential residual is invariant (Te, flux ODEs unchanged).
testCase.verifyLessThan(norm(dae.dae_f(xp,yp) - dae.dae_f(x0,y0), inf), ROUND_TOL, ...
    'differential residual invariant under common rotation');
% Electrical power/torque is invariant.
Pe0 = dae.electrical_power(x0, y0);
Pe1 = dae.electrical_power(xp, yp);
testCase.verifyLessThan(max(abs(Pe1 - Pe0)), ROUND_TOL, ...
    'electrical power invariant under common rotation');
% Algebraic residual stays ~0 under the rotation (g was ~0 at equilibrium).
testCase.verifyLessThan(norm(dae.dae_g(xp,yp,dae.Ynet), inf), ROUND_TOL, ...
    'algebraic residual stays zero under common rotation');
end

function test_7_classical_regression_undisturbed(testCase)
% (7) The EMF6 work must not disturb the validated classical Case14 / RTS-24
% TS baselines. The classical path is untouched; here we confirm its
% structural properties hold (converged, all adaptive steps converge,
% bounded, no-fault zero drift).
% Case14 (MATPOWER case14), classical.
opt14 = struct('t_end',4,'dt',0.01,'fault_bus',4,'t_fault',1.0,'t_clear',1.1, ...
    'Zf',1i*0.1,'pm_mode','pgaz','corrector_mode','adaptive', ...
    'max_corrector_iter',10,'verbose',false);
r14 = stability.ts_simulate(cases.case_matpower6_case14(), opt14);
testCase.verifyTrue(r14.pf.converged, 'case14 PF converged');
testCase.verifyEqual(r14.model, 'classical', 'case14 must use the classical path');
testCase.verifyEqual(r14.nonconverged_step_count, 0, 'case14 all steps converged');
% Faulted run: angles swing but must stay finite and bounded.
testCase.verifyTrue(all(isfinite(r14.delta(:))) && all(isfinite(r14.Vbus(:))), 'finite');
H = r14.H(:).'; dcoi = sum(H.*r14.delta,2)/sum(H); drel = r14.delta - dcoi;
testCase.verifyLessThan(max((max(drel)-min(drel))*180/pi), 360, 'bounded COI-relative swing');
% No-fault equilibrium for the classical case14 path.
opt14nf = opt14; opt14nf.t_fault = 99; opt14nf.t_clear = 99.1; opt14nf.t_end = 2;
r14nf = stability.ts_simulate(cases.case_matpower6_case14(), opt14nf);
testCase.verifyLessThan(max(abs(r14nf.delta(end,:) - r14nf.delta(1,:))), 1e-10, ...
    'case14 no-fault delta drift');
testCase.verifyLessThan(max(abs(r14nf.omega(end,:) - 1)), 1e-10, ...
    'case14 no-fault omega drift');
% RTS-24, classical adaptive, bus-15 fault.
opt24 = struct('t_end',5,'dt',0.01,'fault_bus',15,'t_fault',1.0,'t_clear',1.1, ...
    'Zf',0+0.1j,'method','trapezoidal','corrector_mode','adaptive', ...
    'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8, ...
    'max_corrector_iter',10,'verbose',false);
r24 = stability.ts_simulate(cases.case_ieee_rts24_pgaz(), opt24);
testCase.verifyTrue(r24.pf.converged, 'RTS-24 PF converged');
testCase.verifyEqual(r24.nonconverged_step_count, 0, 'RTS-24 all steps converged');
testCase.verifyLessThan(r24.max_corrector_residual, 1e-6, 'RTS-24 small residual');
% No-fault equilibrium for the classical path.
opt24nf = opt24; opt24nf.t_fault = 99; opt24nf.t_clear = 99.1; opt24nf.t_end = 2;
r24nf = stability.ts_simulate(cases.case_ieee_rts24_pgaz(), opt24nf);
testCase.verifyLessThan(max(abs(r24nf.delta(end,:) - r24nf.delta(1,:))), 1e-10, ...
    'RTS-24 no-fault delta drift');
testCase.verifyLessThan(max(abs(r24nf.omega(end,:) - 1)), 1e-10, ...
    'RTS-24 no-fault omega drift');
end
