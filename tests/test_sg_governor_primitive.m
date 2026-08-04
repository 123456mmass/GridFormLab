function tests=test_sg_governor_primitive
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function testEquilibriumIsInvariant(testCase)
p=params();
[psv,pm,cmd]=stability.sg_turbine_governor_step(1.0672,1.0672,0,0.1,p);
verifyEqual(testCase,cmd,p.Pref,'AbsTol',0);
verifyEqual(testCase,psv,p.Pref,'AbsTol',1e-14);
verifyEqual(testCase,pm,p.Pref,'AbsTol',1e-14);
end

function testExactStepMatchesFineEulerOracle(testCase)
p=params(); p.Pref=1.0;
Psv0=0.8; Pm0=0.9; dw=0.002; h=0.1;
[psv,pm,cmd]=stability.sg_turbine_governor_step(Psv0,Pm0,dw,h,p);
dt=1e-6; q=Psv0; m=Pm0;
for k=1:round(h/dt)
    q0=q; q=q+dt*(-q+cmd)/p.Tsv;
    m=m+dt*(-m+q0)/p.Tch;
end
verifyEqual(testCase,psv,q,'AbsTol',3e-7);
verifyEqual(testCase,pm,m,'AbsTol',3e-7);
end

function testDroopAndValveLimits(testCase)
p=params(); p.Pref=0.5; p.Pmin=0; p.Pmax=1;
[~,~,high]=stability.sg_turbine_governor_step(0.5,0.5,-1,0.1,p);
[~,~,low]=stability.sg_turbine_governor_step(0.5,0.5,1,0.1,p);
verifyEqual(testCase,high,1,'AbsTol',0);
verifyEqual(testCase,low,0,'AbsTol',0);
end

function p=params
p=struct('Tsv',0.2,'Tch',0.4,'R',0.05,'Pref',1.0672, ...
    'Pmin',0,'Pmax',1.3462);
end
