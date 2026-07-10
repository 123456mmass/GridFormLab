function tests=test_emf6_model
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_state_equations_and_equilibrium(testCase)
c=cases.kundur_ex126_book_case();
r=stability.synchronous_emf6_ssa(c,struct('load_model','cz'));
testCase.verifyEqual(r.state_layout.names, ...
    {'delta','omega','Eqp','Edp','Eqpp','Edpp'});
testCase.verifyLessThan(r.newton_residual,1e-9);
testCase.verifyEqual(r.coefficients.c_d,30*ones(4,1),'AbsTol',1e-12);
testCase.verifyEqual(r.coefficients.d_d,31*ones(4,1),'AbsTol',1e-12);
testCase.verifyEqual(r.coefficients.c_q,(23/6)*ones(4,1),'AbsTol',1e-12);
testCase.verifyEqual(r.coefficients.d_q,(29/6)*ones(4,1),'AbsTol',1e-12);
end

function test_ts_uses_same_emf6_dae(testCase)
c=cases.kundur_ex126_book_case();
o=struct('model','emf6','t_end',0.02,'dt',0.01, ...
    'fault_bus',8,'t_fault',1,'t_clear',1.1,'Zf',1i*0.1, ...
    'method','trapezoidal','corrector_iter',1,'load_model','cz','verbose',false);
r=stability.ts_simulate(c,o);
testCase.verifyEqual(r.model_key,'emf6');
testCase.verifyEqual(r.engine,'stability.synchronous_emf6_ssa');
testCase.verifyLessThan(r.initial_dae_residual,1e-9);
testCase.verifyLessThan(max(abs(r.delta-r.delta(1,:)),[],'all'),1e-10);
testCase.verifyLessThan(max(abs(r.omega),[],'all'),1e-10);
end
