function tests = test_ieee14_1sg_4ibr_phaseG2
% REGFM_B1 G2 source-equation and active-bound falsification tests.
tests=functiontests(localfunctions);
end

function setupOnce(testCase)
root=fileparts(fileparts(mfilename('fullpath')));
addpath(root,'-begin');
testCase.addTeardown(@() rmpath(root));
end

function test_state_layout_and_angle_identity(testCase)
[d,y]=fixture(struct(),0.4,1.04,0.13);
testCase.verifyEqual(d.nx,13,'AbsTol',0);
testCase.verifyEqual(d.state_names{2},'delta_IT');
testCase.verifyEqual(d.state_names(12:13),{'delta_ITmax','delta_ITmin'});
r=d.reconstruct(0,d.x0,y,d.u0,struct());
testCase.verifyEqual(r.delta_VSM,r.delta_PLL+r.delta_IT_used,'AbsTol',1e-15);
end

function test_initializer_relative_angle_oracle(testCase)
[d,~]=fixture(struct('Mbase',140),0.4,1.04,0.13);
V=1.04*exp(1i*0.13); P=.4; Q=.05;
x=d.equilibrium_initialize(V,P,Q,struct());
kappa=100/140; I=conj((P+1i*Q)/V);
E=V+kappa*(1i*.1)*I;
expected=mod(angle(E)-angle(V)+pi,2*pi)-pi;
testCase.verifyEqual(x(2),expected,'AbsTol',2e-14);
r=d.reconstruct(0,x,y_for(V),d.u0,struct());
testCase.verifyEqual(r.delta_VSM,angle(E),'AbsTol',2e-14);
end

function test_p_priority_oracle(testCase)
[d,y]=fixture(struct('PQFlag',1),0.4,1.0,0);
x=d.x0; x(8)=0.4; x(11)=0.3;
r=d.reconstruct(0,x,y,d.u0,struct());
testCase.verifyEqual(r.IdmaxSS,0.9,'AbsTol',1e-15);
testCase.verifyEqual(r.IqmaxSS,sqrt(1-0.4^2),'AbsTol',1e-15);
end

function test_q_priority_oracle(testCase)
[d,y]=fixture(struct('PQFlag',0),0.4,1.0,0);
x=d.x0; x(8)=0.4; x(11)=0.3;
r=d.reconstruct(0,x,y,d.u0,struct());
testCase.verifyEqual(r.IqmaxSS,0.9,'AbsTol',1e-15);
testCase.verifyEqual(r.IdmaxSS,sqrt(1-0.3^2),'AbsTol',1e-15);
end

function test_voltage_limits_eq10_eq11(testCase)
[d,y]=fixture(struct('PQFlag',1),0.4,1.0,0);
x=d.x0; x(8)=0.4; x(10)=1.0;
r=d.reconstruct(0,x,y,d.u0,struct());
iqmax=sqrt(1-0.4^2);
emin=sqrt((1-iqmax*.1)^2+(0.4*.1)^2);
emax=sqrt((1+iqmax*.1)^2+(0.4*.1)^2);
testCase.verifyEqual(r.Emin_iq_lim,emin,'AbsTol',2e-15);
testCase.verifyEqual(r.Emax_iq_lim,emax,'AbsTol',2e-15);
testCase.verifyGreaterThanOrEqual(r.EVSM_clamped,emin);
testCase.verifyLessThanOrEqual(r.EVSM_clamped,emax);
end

function test_voltage_integrator_antiwindup(testCase)
[d,y]=fixture(struct(),0.4,1.0,0);
x=d.x0; x(4)=10; x(10)=0.9;
dx=d.f(0,x,y,d.u0,struct());
testCase.verifyEqual(dx(4),0,'AbsTol',0);
end

function test_upper_bound_hold_and_release(testCase)
[d,y]=fixture(struct(),0.4,1.0,0);
x=d.x0;
dx=d.f(0,x,y,d.u0,struct());
testCase.verifyEqual(dx(12),0,'AbsTol',0);
x(8)=0.95;
dx=d.f(0,x,y,d.u0,struct());
testCase.verifyLessThan(dx(12),0);
testCase.verifyEqual(dx(12),2*(0.9-0.95),'AbsTol',2e-15);
end

function test_lower_bound_hold(testCase)
[d,y]=fixture(struct('ESFlag',1),0.4,1.0,0);
x=d.x0; x(8)=0.2;
dx=d.f(0,x,y,d.u0,struct());
testCase.verifyEqual(dx(13),0,'AbsTol',0);
end

function test_esflag_zero_freezes_lower_state(testCase)
[d,y]=fixture(struct('ESFlag',0),0.4,1.0,0);
testCase.verifyEqual(d.x0(13),0,'AbsTol',0);
testCase.verifyFalse(ismember(13,d.active_state_indices));
dx=d.f(0,d.x0,y,d.u0,struct());
testCase.verifyEqual(dx(13),0,'AbsTol',0);
spec=d.equilibrium_constraint_specs(d.x0,y,d.u0,struct());
testCase.verifyEqual(numel(spec),3,'AbsTol',0);
end

function test_active_bound_initial_regimes(testCase)
[d,y]=fixture(struct(),0.4,1.0,0);
spec=d.equilibrium_constraint_specs(d.x0,y,d.u0,struct());
labels={spec.description}; regimes=cell(size(labels));
for k=1:numel(spec)
    regimes{k}=spec(k).classify_fn(d.x0,y,d.u0,struct());
end
testCase.verifyEqual(regimes{strcmp(labels,'delta_ITmax')},'upper');
testCase.verifyEqual(regimes{strcmp(labels,'delta_ITmin')},'lower');
testCase.verifyEqual(regimes{strcmp(labels,'delta_IT')},'interior');
end

function test_kf_zero_warns_and_resets(testCase)
testCase.verifyWarning(@() fixture_one(struct('kf',0)), ...
    'ibr:regfm_b1_vsg_model:kfReset');
d=fixture_one(struct('kf',0));
r=d.reconstruct(0,d.x0,y_for(1),d.u0,struct());
testCase.verifyEqual(r.kf,1,'AbsTol',0);
end

function test_bad_kf_and_delta_domain_fail_closed(testCase)
testCase.verifyError(@() fixture_one(struct('kf',-1)), ...
    'ibr:regfm_b1_vsg_model:badParam');
testCase.verifyError(@() fixture_one(struct('XL',2,'ImaxSS',1)), ...
    'ibr:regfm_b1_vsg_model:deltaMaxDomain');
end

function test_global_rotation_invariance(testCase)
[d1,~]=fixture(struct(),0.4,1.04,0.13);
[d2,~]=fixture(struct(),0.4,1.04,0.63);
V1=1.04*exp(1i*.13); V2=1.04*exp(1i*.63);
x1=d1.equilibrium_initialize(V1,.4,.05,struct());
x2=d2.equilibrium_initialize(V2,.4,.05,struct());
I1=d1.current_injection(0,x1,y_for(V1),d1.u0,struct());
I2=d2.current_injection(0,x2,y_for(V2),d2.u0,struct());
testCase.verifyEqual(x2(2),x1(2),'AbsTol',2e-14);
testCase.verifyEqual(I2,I1*exp(1i*.5),'AbsTol',3e-13);
end

function test_no_external_solver(testCase)
root=fileparts(fileparts(mfilename('fullpath')));
src=fileread(fullfile(root,'+ibr','regfm_b1_vsg_model.m'));
for token={'fsolve','lsqnonlin','optimoptions','pinv('}
    testCase.verifyFalse(contains(lower(src),lower(token{1})));
end
end

function [d,y]=fixture(params,P,Vmag,theta)
V=Vmag*exp(1i*theta);
d=ibr.regfm_b1_vsg_model("G",2,2,[1 2],V,params,P,Vmag);
y=y_for(V);
end

function d=fixture_one(params)
[d,~]=fixture(params,.4,1,0);
end

function y=y_for(V)
y=[1;0;real(V);imag(V)];
end
