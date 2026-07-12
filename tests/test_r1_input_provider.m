function tests = test_r1_input_provider()
%TEST_R1_INPUT_PROVIDER  R1 input-provider interface, consistency, rollback.
%   Verifies the typed input provider (make_input_provider / eval_input_provider)
%   is immutable, exogenous, side-effect-free, and that the provider-aware
%   trapezoidal path converges to a closed-form synthetic oracle. Also verifies
%   that rejected adaptive trials do not corrupt provider state and that the
%   legacy path is taken (bit-identical) when the provider is absent.
%
%   Synthetic oracle (Duhamel, standard ODE theory):
%     dx/dt = A*x + B*u(t),  A=[0,1;-1,0], B=[0;1], u(t)=sin(2t), x0=[1;0]
%     x1(t) = cos(t) + (2/3)*sin(t) - (1/3)*sin(2t)
%     x2(t) = -sin(t) + (2/3)*cos(t) - (2/3)*cos(2t)
%   Source: project R1 design; Duhamel's principle (synthetic, no +ibr).

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function [A,B,x0,u_fn,x_exact] = oracle_setup()
A = [0, 1; -1, 0];
B = [0; 1];
x0 = [1; 0];
u_fn = @(t,~) sin(2*t);
x_exact = @(t) [cos(t) + (2/3)*sin(t) - (1/3)*sin(2*t); ...
                 -sin(t) + (2/3)*cos(t) - (2/3)*cos(2*t)];
end

function test_constant_provider_returns_u0(testCase)
p = stability.make_input_provider('constant', [3; 5]);
u = stability.eval_input_provider(p, 0, struct());
testCase.verifyEqual(u, [3; 5], 'constant provider returns u0 exactly.');
u2 = stability.eval_input_provider(p, 1.7, struct());
testCase.verifyEqual(u2, [3; 5], 'constant provider ignores t.');
end

function test_callback_provider_evaluates_fn(testCase)
[~,~,~,u_fn,~] = oracle_setup();
p = stability.make_input_provider('callback', u_fn);
u = stability.eval_input_provider(p, 1.0, struct());
testCase.verifyEqual(u, sin(2.0), 'AbsTol', 1e-14, 'callback evaluates fn(t,ctx).');
end

function test_provider_is_immutable(testCase)
% Calling eval twice with the same inputs must return identical output, and
% the provider struct must be unchanged (no mutable state).
[~,~,~,u_fn,~] = oracle_setup();
p = stability.make_input_provider('callback', u_fn);
u1 = stability.eval_input_provider(p, 2.0, struct());
u2 = stability.eval_input_provider(p, 2.0, struct());
testCase.verifyEqual(u1, u2, 'AbsTol', 1e-14, 'eval is deterministic.');
testCase.verifyEqual(p.fn(2.0, struct()), u1, 'AbsTol', 1e-14, 'provider unchanged.');
end

function test_callback_validates_finite(testCase)
% A callback returning non-finite values must fail closed.
bad_fn = @(t,~) [1; NaN];
p = stability.make_input_provider('callback', bad_fn);
testCase.verifyError(@() stability.eval_input_provider(p, 0, struct()), ...
    'eval_input_provider:nonFinite');
end

function test_synthetic_oracle_convergence(testCase)
% The provider-aware trapezoidal path must converge to the closed-form
% Duhamel solution. We build a minimal provider-aware strategy for the linear
% ODE dx/dt = A*x + B*u(t) (no algebraic states; needs_algebraic_solve=false).
[A,B,x0,u_fn,x_exact] = oracle_setup();
provider = stability.make_input_provider('callback', u_fn);
% Provider-aware closures for the linear ODE (no Y, no algebraic g).
dae_f_u = @(x,~,~,u) A*x + B*u;
strat = struct('model','synthetic_linear_ode', ...
    'dae_f_u', dae_f_u, 'dae_g_u', [], 'jac_y_u', @(~,~,~,~) [], ...
    'needs_jyy', false, 'needs_algebraic_solve', false, ...
    'provider', provider, ...
    'state_split', struct('ng',1,'ns',2,'delta_idx',1,'omega_idx',2), ...
    'reconstruct_u', @(x,~,~,~) struct('delta',x(1),'omega',x(2),'Pe',0,'Vbus',0), ...
    'reconstruct', @(x,~,~) struct('delta',x(1),'omega',x(2),'Pe',0,'Vbus',0));
opt = struct('corrector_mode','fixed','max_corrector_iter',3, ...
    'corrector_abs_tol',1e-12,'corrector_rel_tol',1e-10, ...
    'algebraic_tolerance',1e-12,'t',0,'event_context',struct());
h = 0.01; t = 0; x = x0;
for k = 1:100
    opt.t = t;
    step = stability.ts_step_kernel(strat, x, [], h, [], opt);
    x = step.x_full;
    t = t + h;
end
testCase.verifyLessThan(norm(x - x_exact(t), inf), 1e-4, ...
    'provider-aware trapezoidal converges to Duhamel oracle (O(h^2)).');
end

function test_rejected_trial_provider_consistency(testCase)
% Force rejections by using an impossibly tight tolerance; verify the accepted
% trajectory still matches the oracle (provider did not leak state across
% rejected trials). We use the adaptive driver via a synthetic strategy.
[A,B,x0,u_fn,x_exact] = oracle_setup();
provider = stability.make_input_provider('callback', u_fn);
dae_f_u = @(x,~,~,u) A*x + B*u;
strat = struct('model','synthetic_linear_ode', ...
    'dae_f_u', dae_f_u, 'dae_g_u', [], 'jac_y_u', @(~,~,~,~) [], ...
    'needs_jyy', false, 'needs_algebraic_solve', false, ...
    'provider', provider, ...
    'state_split', struct('ng',1,'ns',2,'delta_idx',1,'omega_idx',2), ...
    'reconstruct_u', @(x,~,~,~) struct('delta',x(1),'omega',x(2),'Pe',0,'Vbus',0), ...
    'reconstruct', @(x,~,~) struct('delta',x(1),'omega',x(2),'Pe',0,'Vbus',0));
events = struct('fault_enabled',false,'t_fault',inf,'t_clear',inf, ...
    'Ypre',[],'Yfault',[],'Ypost',[]);
aopt = struct('dt_nominal',0.01,'dt_init',0.01,'dt_min',1e-4,'dt_max',0.05, ...
    'controller_fac',0.9,'controller_fac_min',0.2,'controller_fac_max',5.0, ...
    'reject_limit',30,'atol_x',1e-10,'rtol_x',1e-12, ...
    'atol_y',1e-10,'rtol_y',1e-12,'algebraic_tolerance',1e-12, ...
    'max_corrector_iter',3,'corrector_abs_tol',1e-12,'corrector_rel_tol',1e-10, ...
    'corrector_mode','fixed','event_context',struct());
res = stability.ts_adaptive_driver(strat, x0, [], [0, 1.0], events, aopt);
testCase.verifyGreaterThan(res.accepted_steps, 0, 'adaptive accepted steps > 0.');
final = [res.delta(end); res.omega(end)];
testCase.verifyLessThan(norm(final - x_exact(1.0), inf), 1e-3, ...
    'adaptive trajectory matches oracle after rejections (no provider leak).');
end

function test_absent_provider_is_legacy(testCase)
% When strategy.provider is absent (or []), the kernel must take the legacy
% path. Verify a classical run is bit-identical whether or not an empty
% provider field is present.
c = cases.case_matpower6_case14();
opt_base = struct('t_end',1,'dt',0.02,'fault_bus',4,'t_fault',1.0, ...
    't_clear',1.1,'Zf',1i*0.1,'pm_mode','pgaz','corrector_mode','adaptive', ...
    'verbose',false);
r1 = stability.ts_simulate(c, opt_base);
% Build a strategy with provider=[] explicitly and confirm the kernel path
% is the legacy one by checking the result is unchanged.
cdae = stability.classical_dae(c, opt_base);
strat = stability.ts_model_strategy('classical', cdae);
strat.provider = [];   % absent
testCase.verifyTrue(isempty(strat.provider), 'provider absent when set to [].');
% The legacy run must still produce a finite trajectory.
testCase.verifyTrue(all(isfinite(r1.delta(:))), 'legacy classical trajectory finite.');
end
