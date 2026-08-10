function tests=test_ibr_eecon49_dual_mode_model
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function testExactStateOwnershipAndMetadata(testCase)
[dev,~,~,~,~]=fixture('gfl');
expected={'i_d','i_q','V_dc', ...
    'gfl_delta_PLL','gfl_xi_PLL','gfl_xi_P','gfl_xi_Q', ...
    'gfl_xi_Id','gfl_xi_Iq','gfl_Vd_del','gfl_Vq_del', ...
    'gfm_delta_VSG','gfm_omega_VSG','gfm_E','gfm_xi_Vd','gfm_xi_Vq', ...
    'gfm_xi_Id','gfm_xi_Iq','gfm_Vd_del','gfm_Vq_del'};
verifyEqual(testCase,dev.state_names,expected);
verifyEqual(testCase,dev.active_state_indices,1:11);
verifyEmpty(testCase,dev.frozen_state_indices);
verifyTrue(testCase,any(contains(string(dev.state_names(4:11)),'PLL')));
verifyFalse(testCase,any(contains(string(dev.state_names(12:20)),'PLL','IgnoreCase',true)));
meta=ibr.device_contract_metadata(dev);
verifyEqual(testCase,meta.contract_id,'eecon49_dual');
verifyEqual(testCase,numel(meta.state_metadata),20);
verifyEqual(testCase,{meta.state_metadata(12:20).state_branch},repmat({'gfm'},1,9));
verifyEqual(testCase,dev.input_names,{'P_ref','Q_ref','E_ref'});
verifyEqual(testCase,{meta.input_metadata.input_name},{'P_ref','Q_ref','E_ref'});
end

function testGfmAmplitudeUsesExternalErefNotMeasuredMagnitude(testCase)
[dev,~,y,ec,params]=fixture('GFM');
x=dev.x0;
u=dev.u0;
dx0=dev.f(0,x,y,u,ec);

% Independent equation oracle at fixed x,y: changing only E_ref by dEref
% changes dot(E) by +(kE/tauE)*dEref.  The measured |V| is not that input.
dEref=0.013;
u1=u; u1(3)=u1(3)+dEref;
dx1=dev.f(0,x,y,u1,ec);
kE=8.0; tauE=0.05;
if isfield(params,'gfm_eecon49')
    if isfield(params.gfm_eecon49,'kE'), kE=params.gfm_eecon49.kE; end
    if isfield(params.gfm_eecon49,'tauE'), tauE=params.gfm_eecon49.tauE; end
end
verifyEqual(testCase,dx1(14)-dx0(14),kE*dEref/tauE,'AbsTol',1e-12);

% A rigid rotation changes neither |V| nor the direct amplitude reference.
% With x held fixed it may change measured P/Q, but cannot impersonate the
% exact E_ref coefficient above.
phi=0.019;
Vr=complex(y(1),y(2))*exp(1i*phi);
dxr=dev.f(0,x,[real(Vr);imag(Vr)],u,ec);
verifyGreaterThan(testCase,abs((dxr(14)-dx0(14))-kE*dEref/tauE),1e-6);
end

function testBranchRhsAndCurrentMatchStandaloneModels(testCase)
for mode={'gfl','GFM'}
    [dev,V,y,ec,params]=fixture(mode{1});
    if strcmp(mode{1},'gfl')
        branch=ibr.gfl_eecon49_full_model('IBR_TEST',2,1,2,V,params,0.45,0.08);
        bx=[dev.x0(1:11);0];
        expected_idx=1:11;
        branch_idx=1:11;
        inactive_idx=12:20;
    else
        branch=ibr.gfm_eecon49_full_model('IBR_TEST',2,1,2,V,params,0.45,0.08);
        bx=[dev.x0(1:3);dev.x0(12:20)];
        expected_idx=[1:3 12:20];
        branch_idx=1:12;
        inactive_idx=4:11;
    end
    dd=dev.f(0,dev.x0,y,dev.u0,ec);
    db=branch.f(0,bx,y,dev.u0(1:2),ec);
    verifyEqual(testCase,dd(expected_idx),db(branch_idx),'AbsTol',1e-13);
    verifyEqual(testCase,dd(inactive_idx),zeros(numel(inactive_idx),1),'AbsTol',0);
    verifyEqual(testCase,dev.current_injection(0,dev.x0,y,dev.u0,ec), ...
        branch.current_injection(0,bx,y,dev.u0(1:2),ec),'AbsTol',1e-13);
    verifyLessThan(testCase,norm(dd,inf),1e-9);
end
end

function testDcEnergyStateRestoresAfterPerturbation(testCase)
for mode={'gfl','GFM'}
    [dev,~,y,ec]=fixture(mode{1});
    x=dev.x0;
    x(3)=x(3)+0.01;
    dx=dev.f(0,x,y,dev.u0,ec);
    verifyLessThan(testCase,dx(3),0, ...
        sprintf('%s DC regulator must restore a positive V_dc perturbation.',mode{1}));
    x(3)=dev.x0(3)-0.01;
    dx=dev.f(0,x,y,dev.u0,ec);
    verifyGreaterThan(testCase,dx(3),0, ...
        sprintf('%s DC regulator must restore a negative V_dc perturbation.',mode{1}));
end
end

function testGfmLimiterAntiWindupActsOnVoltageLoop(testCase)
[dev,V,y,ec]=fixture('GFM');
x=dev.x0;
x(15)=2.0; % large voltage-loop integral drives positive d current limiting

% Outward voltage error and positive limiter residual must hold xi_Vd.
x(14)=abs(V)+0.10;
dx=dev.f(0,x,y,dev.u0,ec);
[idref,~]=limited_reference(1.20*0.10+4.50*x(15),4.50*x(16),1.20);
verifyEqual(testCase,dx(15),0,'AbsTol',0);
verifyEqual(testCase,dx(17),idref-x(1),'AbsTol',1e-12);
verifyGreaterThan(testCase,abs(dx(17)),1e-3, ...
    'The unclamped inner current PI must continue integrating current error.');

% Reversing only the voltage error releases the same saturated outer loop.
x(14)=abs(V)-0.10;
dx=dev.f(0,x,y,dev.u0,ec);
verifyEqual(testCase,dx(15),-0.10,'AbsTol',2e-14);
end

function testGflLimiterAntiWindupActsOnPowerLoop(testCase)
[dev,V,y,ec]=fixture('gfl');
x=dev.x0;
x(6)=2.0; % large P-loop integral drives positive d current limiting
Pinv=real(V*conj(dev.current_injection(0,x,y,dev.u0,ec)));

% Outward active-power error must hold xi_P, while xi_Id follows e_Id.
u=dev.u0; u(1)=Pinv+0.10;
dx=dev.f(0,x,y,u,ec);
eP=u(1)-Pinv;
[idref,~]=limited_reference(0.80*eP+2.50*x(6), ...
    -(0.80*(u(2)-imag(V*conj(dev.current_injection(0,x,y,u,ec))))+2.50*x(7)),1.20);
verifyEqual(testCase,dx(6),0,'AbsTol',0);
verifyEqual(testCase,dx(8),idref-x(1),'AbsTol',1e-12);
verifyGreaterThan(testCase,abs(dx(8)),1e-3, ...
    'The unclamped inner current PI must continue integrating current error.');

% An inward P error must release xi_P despite the still-saturated reference.
u(1)=Pinv-0.10;
dx=dev.f(0,x,y,u,ec);
verifyEqual(testCase,dx(6),-0.10,'AbsTol',2e-14);
end

function testCurrentReferenceLimitDoesNotClipPhysicalFilterState(testCase)
for mode={'gfl','GFM'}
    [dev,~,y,ec]=fixture(mode{1});
    x=dev.x0;
    x(1)=1.30; x(2)=-0.20;
    I=dev.current_injection(0,x,y,dev.u0,ec);
    theta=x(4);
    if strcmpi(mode{1},'GFM'), theta=x(12); end
    expected=complex(x(1),x(2))*exp(1i*theta);
    verifyEqual(testCase,I,expected,'AbsTol',1e-13);
    verifyGreaterThan(testCase,abs(I),1.20, ...
        'The command limiter must not algebraically clip the L-filter state.');
end
end

function testGfmAngleIsVsgOwnedWithoutPll(testCase)
[dev,~,y,ec,params]=fixture('GFM');
x=dev.x0;
x(13)=1.01;
dx1=dev.f(0,x,y,dev.u0,ec);
phi=0.07;
V=complex(y(1),y(2))*exp(1i*phi);
y2=[real(V);imag(V)];
dx2=dev.f(0,x,y2,dev.u0,ec);
wb=2*pi*params.fbase;
verifyEqual(testCase,dx1(12),wb*(x(13)-1),'AbsTol',1e-12);
verifyEqual(testCase,dx2(12),dx1(12),'AbsTol',1e-12);
end

function testGflPllRespondsToQAxisVoltage(testCase)
[dev,~,y,ec]=fixture('gfl');
x=dev.x0;
dx0=dev.f(0,x,y,dev.u0,ec);
V=complex(y(1),y(2))*exp(1i*0.01);
dx1=dev.f(0,x,[real(V);imag(V)],dev.u0,ec);
verifyGreaterThan(testCase,abs(dx1(4)-dx0(4)),1e-12);
verifyGreaterThan(testCase,abs(dx1(5)-dx0(5)),1e-12);
end

function testBidirectionalTransferPreservesTerminalPortAndVdc(testCase)
[dev,V,y,ecgfl]=fixture('gfl');
ecgfm=context('GFM');
xgfl=dev.equilibrium_initialize(V,0.45,0.08,ecgfl);
I0=dev.current_injection(0,xgfl,y,dev.u0,ecgfl);
[xgfm,info1]=dev.mode_transfer_state(xgfl,y,dev.u0,ecgfl,'GFM',ecgfm);
I1=dev.current_injection(0,xgfm,y,dev.u0,ecgfm);
verifyEqual(testCase,I1,I0,'AbsTol',1e-10);
verifyEqual(testCase,xgfm(3),xgfl(3),'AbsTol',0);
verifyEqual(testCase,info1.P_right,info1.P_left,'AbsTol',1e-10);
verifyEqual(testCase,info1.Q_right,info1.Q_left,'AbsTol',1e-10);
[xback,info2]=dev.mode_transfer_state(xgfm,y,dev.u0,ecgfm,'gfl',ecgfl);
I2=dev.current_injection(0,xback,y,dev.u0,ecgfl);
verifyEqual(testCase,I2,I1,'AbsTol',1e-10);
verifyEqual(testCase,xback(3),xgfm(3),'AbsTol',0);
verifyEqual(testCase,info2.P_right,info2.P_left,'AbsTol',1e-10);
verifyEqual(testCase,info2.Q_right,info2.Q_left,'AbsTol',1e-10);
end

function testRigidFrameCovariance(testCase)
[dev,V,y,ec]=fixture('gfl');
x=dev.equilibrium_initialize(V,0.45,0.08,ec);
I=dev.current_injection(0,x,y,dev.u0,ec);
phi=0.31;
Vr=V*exp(1i*phi);
yr=[real(Vr);imag(Vr)];
xr=dev.equilibrium_initialize(Vr,0.45,0.08,ec);
Ir=dev.current_injection(0,xr,yr,dev.u0,ec);
verifyEqual(testCase,Ir,I*exp(1i*phi),'AbsTol',1e-10);
verifyEqual(testCase,Vr*conj(Ir),V*conj(I),'AbsTol',1e-10);
end

function testProductionProfileBuildsAndSolves(testCase)
s=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
[devices,~]=stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
verifyEqual(testCase,{s.resources(2:5).model_id},repmat({'eecon49_dual'},1,4));
for k=2:5
    verifyEqual(testCase,devices(k).device_type,'ibr_eecon49_dual');
    verifyEqual(testCase,devices(k).nx,20);
    verifyEqual(testCase,s.resources(k).ratings.Mbase,100,'AbsTol',0);
    verifyFalse(testCase,any(contains(string(devices(k).state_names(12:20)),'PLL','IgnoreCase',true)));
end
eq=stability.mixed_equilibrium_solve(s.case_data,struct('devices',devices),struct('verbose',false));
verifyTrue(testCase,eq.converged,eq.failure_reason);
verifyLessThan(testCase,eq.residual_norm,1e-8);
end

function testSourceFullStateScrProfileDoesNotBorrowWeccThreshold(testCase)
s=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
scr=stability.ibr_scr_metrics(s.case_data,s.resources,struct(),struct());
for k=2:5
    verifyEqual(testCase,scr.per_resource(k).scr_profile, ...
        'not_applicable_full_state_source_model');
    verifyFalse(testCase,scr.per_resource(k).eligible_for_scr);
    verifyTrue(testCase,scr.per_resource(k).pass);
end
end

function [dev,V,y,ec,params]=fixture(mode)
V=1.02*exp(1i*0.08);
params=struct('Sbase',100,'Mbase',100,'fbase',60, ...
    'dc_source',struct('Tdc',0.10));
dev=ibr.eecon49_dual_mode_model('IBR_TEST',2,1,2,V,params,0.45,0.08,abs(V),mode);
y=[real(V);imag(V)];
ec=context(mode);
end

function ec=context(mode)
ec=struct('hybrid_state',struct('device_modes',struct('IBR_TEST',mode), ...
    'device_online',struct('IBR_TEST',true)));
end

function [d,q]=limited_reference(d,q,imax)
r=hypot(d,q);
if r>imax
    d=d*imax/r;
    q=q*imax/r;
end
end
