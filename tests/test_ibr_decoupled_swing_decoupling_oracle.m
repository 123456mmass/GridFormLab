function tests=test_ibr_decoupled_swing_decoupling_oracle
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function testZeroTransientDampingReproducesBaselineExactly(testCase)
% The decoupled swing must reduce EXACTLY to the coupled baseline when the
% transient-damping coefficient is zero and the droop is matched, i.e.
%   M dom/dt = kP - Pinv - (1/R)(om-1) - 0*(om-om_f)   ==   ... - Dv(om-1)
% for Dv = 1/R.  This is the implementation oracle for the whole model: the
% independent reference is ibr.gfm_eecon49_full_model, an unmodified file.
% AbsTol 0 -- any difference means the new swing block is not the declared
% equation.  omega_f is deliberately perturbed away from omega to prove the
% first ten rows do not read it when D_t=0.
Dv=20.0; V0=1.02; P=0.40; Q=0.15; E=1.02;
b=ibr.gfm_eecon49_full_model('B',2,1,[2 3],V0,base_params(Dv),P,Q,E);
d=ibr.gfm_decoupled_full_model('D',2,1,[2 3],V0, ...
    dec_params(1/Dv,0.0,50.0,0.08),P,Q,E);
verifyEqual(testCase,d.nx,11);
verifyEqual(testCase,d.state_names{11},'omega_f');
verifyEqual(testCase,d.provenance.omega_f_index,11);
verifyEqual(testCase,d.x0(1:10),b.x0,'AbsTol',0);
verifyEqual(testCase,d.x0(11),1,'AbsTol',0);
rng(7); evaluated=0;
for k=1:200
    xb=b.x0+0.08*randn(10,1); xb(3)=0.9+0.2*rand;
    xd=[xb;1+0.10*randn];
    y=[1.00+0.05*randn;0.05*randn];
    u=[P+0.2*randn;Q+0.2*randn;E];
    try
        fb=b.f(0,xb,y,u,struct()); fd=d.f(0,xd,y,u,struct());
    catch
        continue;
    end
    evaluated=evaluated+1;
    verifyEqual(testCase,fd(1:10),fb,'AbsTol',0);
    verifyEqual(testCase,fd(11),50.0*(xd(5)-xd(11)),'AbsTol',0);
end
verifyGreaterThan(testCase,evaluated,100, ...
    'the random sweep must actually evaluate the models');
end

function testSteadyStateDroopIsRAloneForEveryDampingSetting(testCase)
% Droop knob oracle.  Pinv does not depend on omega, so the exact steady-state
% speed follows from 0 = kappa*Pref - Pinv - (1/R)(om-1) with om_f = om.  If
% D_t or wD leaked into the steady state, this residual would not vanish and
% the slope d(om_ss)/d(kappa*Pref) would not equal R.
V0=1.02; P=0.40; Q=0.15; E=1.02; y0=[V0;0]; u0=[P;Q;E];
d0=ibr.gfm_decoupled_full_model('D',2,1,[2 3],V0, ...
    dec_params(0.05,20.0,3.0,0.08),P,Q,E);
kap=d0.provenance.params.kappa;
xs=d0.x0; th=xs(4);
Vph=complex(y0(1),y0(2)); Isys=complex(xs(1),xs(2))*exp(1i*th)/kap;
Pinv=kap*real(Vph*conj(Isys));
for R=[0.02 0.05 0.10]
    for Dt=[0 5 20 80]
        for wD=[1 3 10 60]
            d=ibr.gfm_decoupled_full_model('D',2,1,[2 3],V0, ...
                dec_params(R,Dt,wD,0.08),P,Q,E);
            om=1+R*(kap*u0(1)-Pinv);
            x=xs; x(5)=om; x(11)=om;
            f=d.f(0,x,y0,u0,struct());
            verifyEqual(testCase,f(5),0,'AbsTol',1e-12, ...
                sprintf('R=%g D_t=%g wD=%g: steady state must satisfy the droop law',R,Dt,wD));
            dP=1e-6; om2=1+R*(kap*(u0(1)+dP)-Pinv);
            verifyEqual(testCase,(om2-om)/(kap*dP),R,'AbsTol',1e-9);
        end
    end
end
end

function testJacobianRowsEqualTheDeclaredSwingEquations(testCase)
% Structural oracle: the four Jacobian entries that define the decoupled swing
% must equal the declared coefficients, for every parameter combination.  This
% is stronger than mode tracking, which is unreliable here because the swing
% pair is over-damped at this plant's measured synchronising coefficient.
%   d(dom)/d(om)   = -(1/R + D_t)/M
%   d(dom)/d(om_f) = +D_t/M
%   d(dom_f)/d(om) = +wD
%   d(dom_f)/d(om_f) = -wD
%   d(dth)/d(om)   = omega_b
% and row 11 must read nothing except omega and omega_f.
V0=1.02; P=0.40; Q=0.15; E=1.02; y0=[V0;0]; u0=[P;Q;E];
for R=[0.02 0.05 0.10]
    for Dt=[0 5 40 200]
        for wD=[1 3 25]
            M=0.08;
            d=ibr.gfm_decoupled_full_model('D',2,1,[2 3],V0, ...
                dec_params(R,Dt,wD,M),P,Q,E);
            J=central_jacobian(d,d.x0,y0,u0);
            wb=d.provenance.params.omega_b;
            verifyEqual(testCase,J(5,5),-(1/R+Dt)/M,'RelTol',2e-6);
            verifyEqual(testCase,J(11,5),wD,'RelTol',2e-6);
            verifyEqual(testCase,J(11,11),-wD,'RelTol',2e-6);
            verifyEqual(testCase,J(4,5),wb,'RelTol',2e-6);
            if Dt==0
                verifyEqual(testCase,J(5,11),0,'AbsTol',1e-9);
            else
                verifyEqual(testCase,J(5,11),Dt/M,'RelTol',2e-6);
            end
            others=J(11,:); others([5 11])=0;
            verifyEqual(testCase,others,zeros(1,11),'AbsTol',1e-9, ...
                'the washout row must depend only on omega and omega_f');
        end
    end
end
end

function testWashoutIsDynamicallyInertAtZeroTransientDamping(testCase)
% The declared swing characteristic polynomial is
%   M s^3 + (M wD + 1/R + D_t) s^2 + ((1/R) wD + K wb) s + K wb wD.
% At D_t = 0 it must factor as (s + wD) * (M s^2 + (1/R) s + K wb): the washout
% state contributes one real pole at -wD and the remaining pair is exactly the
% baseline swing.  This is the mathematical statement of "the damping knob is
% off"; the full-system counterpart is asserted in
% test_ieee14_decoupled_full_state.
wb=2*pi*60; M=0.08;
for R=[0.02 0.05 0.10]
    for wD=[1 3 25 60]
        for K=[0.05 0.1135 0.1862 0.5]
            r3=sortc(roots([M, M*wD+1/R, wD/R+K*wb, K*wb*wD]));
            r2=sortc([-wD; roots([M, 1/R, K*wb])]);
            verifyEqual(testCase,r3,r2,'AbsTol',1e-8);
        end
    end
end
end

function testThreeKnobsActOnThreeSeparateProperties(testCase)
% Knob-separation oracle on the declared polynomial:
%   * M alone sets the undamped natural frequency wn = sqrt(K wb / M);
%   * R alone sets the steady-state droop (asserted directly above) and the
%     D_t = 0 damping;
%   * D_t alone moves the damping ratio while droop and M are held.
% zeta(D_t) is monotone over the usable band here but is NOT monotone in
% general, so a design value must be solved on the exact polynomial rather than
% from the small-D_t approximation zeta ~= [1/R + D_t g(wn)]/(2 sqrt(M K wb)).
wb=2*pi*60; K=0.1135; R=0.05; wD=3.0;
for M=[0.02 0.08 0.5 5.0]
    wn=sqrt(K*wb/M);
    q=roots([M, 1/R, K*wb]);
    verifyEqual(testCase,sqrt(prod(abs(q))),wn,'RelTol',1e-9);
end
z=[]; Dts=[5 10 20 40 80 150];
for Dt=Dts
    z(end+1)=swing_zeta(0.08,R,Dt,wD,K,wb); %#ok<AGROW>
end
verifyTrue(testCase,all(isfinite(z)));
verifyTrue(testCase,all(diff(z)<0), ...
    'D_t must move the damping ratio monotonically over the design band');
verifyGreaterThan(testCase,max(z)-min(z),0.3, ...
    'D_t must have real authority over the damping ratio');
% Same sweep, unchanged droop: the static characteristic is R for all of them.
d1=ibr.gfm_decoupled_full_model('D',2,1,[2 3],1.02,dec_params(R,5,wD,0.08),0.4,0.15,1.02);
d2=ibr.gfm_decoupled_full_model('D',2,1,[2 3],1.02,dec_params(R,150,wD,0.08),0.4,0.15,1.02);
verifyEqual(testCase,d1.provenance.params.Dv_static_equivalent, ...
    d2.provenance.params.Dv_static_equivalent,'AbsTol',0);
verifyEqual(testCase,d1.provenance.params.Dv_static_equivalent,1/R,'AbsTol',1e-12);
end

function testCoupledBaselineCannotMeetBothTargetsButDecoupledCan(testCase)
% Contribution oracle, stated on this plant's MEASURED synchronising
% coefficient K = 0.1135..0.1862 pu/rad (full-KCL Schur-reduced SSSA of the
% all-GFM SG-online configuration; reproduced by chk_decoupled_ksync_tmp).
% Targets frozen before the numbers: 5 % P-f droop (grid-code band) and swing
% damping ratio 1/sqrt(2) at the unchanged source-printed M = 0.08.
%   coupled baseline: zeta = Dv/(2 sqrt(M K wb)) and droop = 1/Dv are ONE
%     number, so 5 % droop forces zeta > 4 and zeta = 1/sqrt(2) forces droop
%     near 30-38 %.  Neither point satisfies both targets.
%   decoupled: R = 0.05 with wD = 3.0 and D_t = 20.0 holds 5 % droop and
%     zeta ~= 1/sqrt(2) across the whole measured K range.
% This test fails if the production defaults or the swing equation stop
% delivering that property.
wb=2*pi*60; M=0.08; Ks=[0.1135 0.1862]; ztgt=1/sqrt(2);
for K=Ks
    z_at_5pct=(1/0.05)/(2*sqrt(M*K*wb));
    verifyGreaterThan(testCase,z_at_5pct,2.0, ...
        'the coupled baseline at 5 % droop must be far past critical damping');
    Dv_for_target=2*ztgt*sqrt(M*K*wb);
    verifyGreaterThan(testCase,100/Dv_for_target,10, ...
        'the coupled baseline would need a droop far outside the 3-5 % band');
    z_dec=swing_zeta(M,0.05,20.0,3.0,K,wb);
    verifyEqual(testCase,z_dec,ztgt,'AbsTol',0.02, ...
        'the production decoupled defaults must hold zeta ~= 1/sqrt(2)');
end
% The production defaults of the device itself must be the designed values.
d=ibr.gfm_decoupled_full_model('D',2,1,[2 3],1.02, ...
    struct('Sbase',100,'Mbase',100,'fbase',60, ...
        'dc_source',struct('Tdc',0.10)),0.4,0.15,1.02);
p=d.provenance.params;
verifyEqual(testCase,p.R_droop,0.05,'AbsTol',0);
verifyEqual(testCase,p.D_t,20.0,'AbsTol',0);
verifyEqual(testCase,p.wD,3.0,'AbsTol',0);
verifyEqual(testCase,p.M,0.08,'AbsTol',0);
% wD must stay well below the swing frequency, or the washout would remove the
% authority of D_t at exactly the frequency it is meant to damp.
for K=Ks
    wn=sqrt(K*wb/p.M);
    verifyLessThan(testCase,p.wD/wn,0.2);
    verifyGreaterThan(testCase,wn^2/(wn^2+p.wD^2),0.98);
end
end

% -------------------------------------------------------------------------
function p=base_params(Dv)
p=struct('Sbase',100,'Mbase',100,'fbase',60,'dc_source',struct('Tdc',0.10));
p.gfm_eecon49=struct('Lf',0.15,'Rf',0.015,'Cdc',0.10,'Vdc_ref',1.0, ...
    'Imax',1.2,'M',0.08,'Dv',Dv,'tauE',0.05,'kQ',0.25,'kE',8.0, ...
    'kpV',1.2,'kiV',4.5,'kpI',0.3,'kiI',4.0);
end

function p=dec_params(R,Dt,wD,M)
p=struct('Sbase',100,'Mbase',100,'fbase',60,'dc_source',struct('Tdc',0.10));
p.gfm_decoupled=struct('Lf',0.15,'Rf',0.015,'Cdc',0.10,'Vdc_ref',1.0, ...
    'Imax',1.2,'M',M,'R_droop',R,'D_t',Dt,'wD',wD,'tauE',0.05, ...
    'kQ',0.25,'kE',8.0,'kpV',1.2,'kiV',4.5,'kpI',0.3,'kiI',4.0);
end

function J=central_jacobian(dev,x,y,u)
n=numel(x); J=zeros(n,n);
for i=1:n
    h=1e-6*max(1,abs(x(i)));
    xp=x; xp(i)=xp(i)+h; xm=x; xm(i)=xm(i)-h;
    J(:,i)=(dev.f(0,xp,y,u,struct())-dev.f(0,xm,y,u,struct()))/(2*h);
end
end

function z=swing_zeta(M,R,Dt,wD,K,wb)
rr=roots([M, M*wD+1/R+Dt, wD/R+K*wb, K*wb*wD]);
cp=rr(imag(rr)>1e-9);
if isempty(cp), z=Inf; return; end
[~,ix]=max(real(cp)); lam=cp(ix);
z=-real(lam)/abs(lam);
end

function r=sortc(r)
[~,ix]=sortrows([real(r(:)) imag(r(:))]); r=r(ix);
end
