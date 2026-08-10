function tests=test_sg_offline_synchronizer_step
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function testGridSpeedEquilibriumIsInvariant(tc)
o=frozen_options();
wg=0.044;
Peq=o.D*wg;
[Psv1,Pm1,command,a]=stability.sg_offline_synchronizer_step( ...
    Peq,Peq,wg,wg,0,0.1,o);
tc.verifyEqual(command,Peq,'AbsTol',1e-15);
tc.verifyEqual(Psv1,Peq,'AbsTol',1e-15);
tc.verifyEqual(Pm1,Peq,'AbsTol',1e-15);
tc.verifyEqual(a.e_omega,0,'AbsTol',0);
tc.verifyEqual(a.e_theta,0,'AbsTol',0);
end

function testDerivedGainsAndExactLagUpdate(tc)
o=frozen_options();
Psv=0.12; Pm=0.08; ws=-0.01; wg=0.03; eth=0.2; h=0.1;
[Psv1,Pm1,command,a]=stability.sg_offline_synchronizer_step( ...
    Psv,Pm,ws,wg,eth,h,o);
Kw=4*o.H*o.zeta*o.omega_n-o.D;
Kt=2*o.H*o.omega_n^2/o.omega_0;
raw=o.D*wg+Kw*(wg-ws)+Kt*eth;
cmd=min(o.Pmax,max(o.Pmin,raw));
esv=exp(-h/o.Tsv); ech=exp(-h/o.Tch);
Psv_oracle=cmd+(Psv-cmd)*esv;
Pm_oracle=cmd+(Pm-cmd)*ech+ ...
    (Psv-cmd)*o.Tsv/(o.Tsv-o.Tch)*(esv-ech);
tc.verifyEqual(a.K_omega,Kw,'AbsTol',0);
tc.verifyEqual(a.K_theta,Kt,'AbsTol',0);
tc.verifyEqual(command,cmd,'AbsTol',0);
tc.verifyEqual(Psv1,Psv_oracle,'AbsTol',10*eps);
tc.verifyEqual(Pm1,Pm_oracle,'AbsTol',10*eps);
end

function testFrozenLinearizedControllerIncludingActuatorLagsIsStable(tc)
o=frozen_options();
Kw=4*o.H*o.zeta*o.omega_n-o.D;
Kt=2*o.H*o.omega_n^2/o.omega_0;
% Independent linearization in [e_theta,e_omega,dPsv,dPm].
A=[0,o.omega_0,0,0; ...
   0,-o.D/(2*o.H),0,-1/(2*o.H); ...
   Kt/o.Tsv,Kw/o.Tsv,-1/o.Tsv,0; ...
   0,0,1/o.Tch,-1/o.Tch];
lambda=eig(A);
tc.verifyLessThan(max(real(lambda)),-0.5);
end

function testCommandSaturatesWithoutChangingErrors(tc)
o=frozen_options();
[~,~,hi,a_hi]=stability.sg_offline_synchronizer_step( ...
    0,0,-1,1,pi,0.1,o);
[~,~,lo,a_lo]=stability.sg_offline_synchronizer_step( ...
    0,0,1,-1,-pi,0.1,o);
tc.verifyEqual(hi,o.Pmax,'AbsTol',0);
tc.verifyEqual(lo,o.Pmin,'AbsTol',0);
tc.verifyGreaterThan(a_hi.command_raw,o.Pmax);
tc.verifyLessThan(a_lo.command_raw,o.Pmin);
end

function o=frozen_options()
o=struct('H',2.5,'D',1.0,'omega_0',2*pi*60,'omega_n',0.8, ...
    'zeta',1.0,'Tsv',0.2,'Tch',0.4,'Pmin',0,'Pmax',1.3462);
end
