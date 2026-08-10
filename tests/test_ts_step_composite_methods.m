function tests=test_ts_step_composite_methods
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function testDefaultRemainsCanonicalTrapezoidal(testCase)
a=7.0; h=0.08; x0=1.25;
dae=scalar_dae(a);
s=stability.ts_step_composite(x0,0,h,dae,0,zeros(0,1),struct(),1,struct());
oracle=x0*(1-a*h/2)/(1+a*h/2);
verifyTrue(testCase,s.converged);
verifyEqual(testCase,s.x_full,oracle,'AbsTol',2e-11);
verifyEqual(testCase,s.y_full,0,'AbsTol',2e-12);
end

function testBackwardEulerRestartStepMatchesClosedForm(testCase)
a=7.0; h=0.08; x0=1.25;
dae=scalar_dae(a);
opt=struct('integration_method','backward_euler');
s=stability.ts_step_composite(x0,0,h,dae,0,zeros(0,1),struct(),1,opt);
oracle=x0/(1+a*h);
verifyTrue(testCase,s.converged);
verifyEqual(testCase,s.x_full,oracle,'AbsTol',2e-11);
verifyEqual(testCase,s.y_full,0,'AbsTol',2e-12);
end

function testInvalidMethodFailsClosed(testCase)
dae=scalar_dae(1);
verifyError(testCase,@() stability.ts_step_composite(1,0,0.1,dae,0, ...
    zeros(0,1),struct(),1,struct('integration_method','explicit_euler')), ...
    'ts_step_composite:badIntegrationMethod');
end

function testLinearKclPredictorDoesNotChangeClosedFormSolution(testCase)
a=7.0; h=0.08; x0=1.25;
dae=scalar_dae(a);
oracle=x0*(1-a*h/2)/(1+a*h/2);
% Tighten only this closed-form oracle solve; the production default and
% acceptance gate remain unchanged at their declared values.
opt=struct('state_predictor','linear_kcl','x_predictor',9.0, ...
    'newton_tol',1e-12);
s=stability.ts_step_composite(x0,0,h,dae,0,zeros(0,1),struct(),1,opt);
verifyTrue(testCase,s.converged);
verifyEqual(testCase,s.x_full,oracle,'AbsTol',2e-11);
end

function testInvalidPredictorFailsClosed(testCase)
dae=scalar_dae(1);
verifyError(testCase,@() stability.ts_step_composite(1,0,0.1,dae,0, ...
    zeros(0,1),struct(),1,struct('state_predictor','quadratic')), ...
    'ts_step_composite:badStatePredictor');
end

function dae=scalar_dae(a)
dae=struct();
dae.devices=repmat(struct(),0,1);
dae.dae_f=@(~,x,~,~,~) -a*x;
dae.dae_g=@(~,~,y,~,~,~) y;
end
