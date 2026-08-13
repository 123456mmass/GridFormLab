function tests=test_ibr_decoupled_dual_mode_model
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function testExactStateOwnershipAndMetadata(testCase)
% The decoupled dual model is the 16-state shared-plant layout with ONE state
% appended: the GFM transient-damping washout omega_f, index 17.  Appending it
% last is a contract decision, so this test pins both the 17-name list and the
% fact that names 1:16 are byte-equal to the baseline layout.  Independent
% oracle: ibr.device_contract_metadata resolves 'decoupled_dual' only on an
% exact (device_type, nx, nu, state_names, input_names) match, so a reordered
% or truncated list fails closed instead of silently registering.
[dev,~,~,~,~]=fixture('gfl');
expected={'i_d','i_q','V_dc', ...
    'gfl_delta_PLL','gfl_xi_PLL','gfl_xi_P','gfl_xi_Q', ...
    'gfl_xi_Id','gfl_xi_Iq', ...
    'gfm_delta_VSG','gfm_omega_VSG','gfm_E','gfm_xi_Vd','gfm_xi_Vq', ...
    'gfm_xi_Id','gfm_xi_Iq','gfm_omega_f'};
verifyEqual(testCase,dev.nx,17);
verifyEqual(testCase,dev.state_names,expected);
verifyEqual(testCase,dev.device_type,'ibr_decoupled_dual');
verifyEqual(testCase,dev.active_state_indices,1:9);
verifyEmpty(testCase,dev.frozen_state_indices);
% GFL owns the PLL; the GFM branch must not carry one.
verifyTrue(testCase,any(contains(string(dev.state_names(4:9)),'PLL')));
verifyFalse(testCase,any(contains(string(dev.state_names(10:17)),'PLL', ...
    'IgnoreCase',true)));
meta=ibr.device_contract_metadata(dev);
verifyEqual(testCase,meta.contract_id,'decoupled_dual');
verifyEqual(testCase,numel(meta.state_metadata),17);
verifyEqual(testCase,{meta.state_metadata(10:17).state_branch},repmat({'gfm'},1,8));
verifyEqual(testCase,meta.state_metadata(17).state_name,'gfm_omega_f');
verifyEqual(testCase,meta.state_metadata(17).state_symbol,'omega_f');
% The washout state and the swing rows are project-derived, not source-mapped.
verifyEqual(testCase,meta.state_metadata(17).equation_classification, ...
    'PROJECT_DERIVED');
verifyEqual(testCase,meta.state_metadata(11).equation_classification, ...
    'PROJECT_DERIVED');
verifyEqual(testCase,dev.input_names,{'P_ref','Q_ref','E_ref'});
verifyEqual(testCase,{meta.input_metadata.input_name},{'P_ref','Q_ref','E_ref'});
% Names 1:16 must match the baseline contract exactly.
bmeta=ibr.device_contract_metadata(baseline_fixture('gfl'));
verifyEqual(testCase,{meta.state_metadata(1:16).state_name}, ...
    {bmeta.state_metadata.state_name});
end

function testActiveMapsAndBranchRhsMatchStandaloneModels(testCase)
% The dual wrapper must be pure assembly: in GFM it forwards to the 11-state
% ibr.gfm_decoupled_full_model and in GFL to the 10-state
% ibr.gfl_eecon49_full_model, with the inactive branch rows exactly zero.
% Independent oracle: the standalone factories, called directly on the sliced
% state.  AbsTol 0 -- assembly must not perturb a single bit.
[dg,V,y,ecg,params]=fixture('GFM');
[dl,~,~,ecl,~]=fixture('gfl');
verifyEqual(testCase,dg.active_state_indices,[1:3 10:17]);
verifyEqual(testCase,dl.active_state_indices,1:9);
sg=ibr.gfm_decoupled_full_model('IBR_TEST',2,1,2,V,params,0.45,0.08,abs(V));
sl=ibr.gfl_eecon49_full_model('IBR_TEST',2,1,2,V,params,0.45,0.08);
verifyEqual(testCase,sg.nx,11);
verifyEqual(testCase,sl.nx,10);
rng(4);
for k=1:40
    x=dg.x0+0.05*randn(17,1); x(3)=0.9+0.2*rand;
    u=[0.45+0.15*randn;0.08+0.15*randn;abs(V)];
    dmm=dg.f(0,x,y,u,ecg);
    ref=sg.f(0,[x(1:3);x(10:17)],y,u,ecg);
    verifyEqual(testCase,dmm(1:3),ref(1:3),'AbsTol',0);
    verifyEqual(testCase,dmm(10:17),ref(4:11),'AbsTol',0);
    verifyEqual(testCase,dmm(4:9),zeros(6,1),'AbsTol',0);
    verifyEqual(testCase,dg.current_injection(0,x,y,u,ecg), ...
        sg.current_injection(0,[x(1:3);x(10:17)],y,u,ecg),'AbsTol',0);
    dll=dl.f(0,x,y,u,ecl);
    refl=sl.f(0,[x(1:9);0],y,u(1:2),ecl);
    verifyEqual(testCase,dll(1:3),refl(1:3),'AbsTol',0);
    verifyEqual(testCase,dll(4:9),refl(4:9),'AbsTol',0);
    verifyEqual(testCase,dll(10:17),zeros(8,1),'AbsTol',0);
end
end

function testEquilibriumAppendsTrackedWashoutAndIgnoresSwingGains(testCase)
% The equilibrium vector must be independent of R_droop, D_t, wD and M, exactly
% as the baseline equilibrium is independent of Dv and M: at any equilibrium
% omega=omega_f=1 so the washout term is identically zero.  Independent oracle:
% the baseline dual equilibrium, which this must reproduce on states 1:16.
[dev,V,~,~,~]=fixture('GFM');
base=baseline_fixture('GFM');
verifyEqual(testCase,dev.x0(1:16),base.x0,'AbsTol',0);
verifyEqual(testCase,dev.x0(17),1,'AbsTol',0);
for R=[0.02 0.05 0.12]
    for Dt=[0 7 55]
        for wD=[1.5 3 40]
            for M=[0.08 0.5]
                p=params_with(R,Dt,wD,M);
                d2=ibr.decoupled_dual_mode_model('IBR_TEST',2,1,2,V,p, ...
                    0.45,0.08,abs(V),"GFM");
                verifyEqual(testCase,d2.x0,dev.x0,'AbsTol',0);
            end
        end
    end
end
end

function testGfmAmplitudeUsesExternalErefNotMeasuredMagnitude(testCase)
% The GFM amplitude state must be driven by the external E_ref input, not by
% the measured terminal magnitude.  Equation oracle at fixed x,y: raising only
% E_ref by dEref changes dot(E) by exactly +(kE/tauE)*dEref.  E is state 12 in
% the 17-state layout, unchanged from the baseline index.
[dev,~,y,ec,params]=fixture('GFM');
x=dev.x0; u=dev.u0;
dx0=dev.f(0,x,y,u,ec);
dEref=0.013;
u1=u; u1(3)=u1(3)+dEref;
dx1=dev.f(0,x,y,u1,ec);
kE=params.gfm_decoupled.kE; tauE=params.gfm_decoupled.tauE;
verifyEqual(testCase,dx1(12)-dx0(12),kE*dEref/tauE,'AbsTol',1e-12);
end

function testTransferIntoGfmEntersWashoutTracked(testCase)
% On entry to GFM the washout state must be initialized TRACKED
% (omega_f = omega_VSG) so the transient-damping term D_t*(omega-omega_f) is
% exactly zero at the transfer instant.  Leaving omega_f at 1 while omega is
% carried from the PLL would inject a step torque D_t*(omega_PLL-1) that no
% source or derivation justifies.  Independent oracle: evaluate the GFM RHS at
% the produced right state and at the same state with omega_f forced back to 1;
% the difference in d(omega)/dt is the injected step, and it must be nonzero
% (so the test is live) while the tracked state itself gives zero contribution.
V=1.02*exp(1i*0.08); y=[real(V);imag(V)];
p=params_with(0.05,40.0,3.0,0.08);
dl=ibr.decoupled_dual_mode_model('IBR_TEST',2,1,2,V,p,0.45,0.08,abs(V),"gfl");
dg=ibr.decoupled_dual_mode_model('IBR_TEST',2,1,2,V,p,0.45,0.08,abs(V),"GFM");
ecl=context('gfl'); ecg=context('GFM');
xl=dl.x0; xl(5)=xl(5)+0.02;             % nonzero PLL integrator -> omega ~= 1
[xr,info]=dl.mode_transfer_state(xl,y,dl.u0,ecl,'GFM',ecl,1e-8);
verifyEqual(testCase,xr(17),xr(11),'AbsTol',0, ...
    'washout state must enter tracked');
verifyTrue(testCase,abs(xr(11)-1)>1e-9, ...
    'the carried GFM speed must differ from 1 or this oracle is vacuous');
verifyEqual(testCase,info.gfm_indices,10:17);
verifyLessThanOrEqual(testCase,abs(info.I_right-info.I_left),1e-8);
f_tracked=dg.f(0,xr,y,dg.u0,ecg);
xun=xr; xun(17)=1;
f_untracked=dg.f(0,xun,y,dg.u0,ecg);
Dt=p.gfm_decoupled.D_t; M=p.gfm_decoupled.M;
% The injected step is exactly -D_t*(omega-1)/M in the swing row.
verifyEqual(testCase,f_untracked(11)-f_tracked(11), ...
    -Dt*(xr(11)-1)/M,'AbsTol',1e-12);
verifyTrue(testCase,abs(f_untracked(11)-f_tracked(11))>1e-6, ...
    'tracked entry must remove a numerically significant step torque');
end

function testHandbackKeepsFrozenGfmBlockIncludingWashout(testCase)
% Handing a GFM device back to GFL must freeze the whole GFM block, including
% the appended washout state, and must preserve the terminal current.
V=1.02*exp(1i*0.08); y=[real(V);imag(V)];
[dg,~,~,ecg,~]=fixture('GFM');
xg=dg.x0; xg(11)=1.004; xg(17)=1.004;
[xr,info]=dg.mode_transfer_state(xg,y,dg.u0,ecg,'gfl',ecg,1e-8);
verifyEqual(testCase,xr(10:17),xg(10:17),'AbsTol',0);
verifyLessThanOrEqual(testCase,abs(info.I_right-info.I_left),1e-8);
verifyEqual(testCase,info.gfl_indices,4:9);
end

function testFailClosedOnBadStateAndBadSwingParameters(testCase)
% The 17-state ABI and the swing-parameter domain must fail closed, not fall
% back.  R_droop=0 removes the only steady-state P-omega characteristic and
% wD=0 freezes omega_f so the washout degenerates into unbounded proportional
% damping; D_t<0 is anti-damping.  A 16-state vector must be rejected rather
% than silently interpreted as the baseline layout.
[dev,V,y,ec,~]=fixture('GFM');
verifyError(testCase,@()dev.f(0,dev.x0(1:16),y,dev.u0,ec), ...
    'ibr:decoupled_dual_mode_model:badState');
verifyError(testCase,@()dev.f(0,[dev.x0;0],y,dev.u0,ec), ...
    'ibr:decoupled_dual_mode_model:badState');
for bad={{'R_droop',0},{'wD',0},{'D_t',-1},{'M',0}}
    p=params_with(0.05,20.0,3.0,0.08);
    p.gfm_decoupled.(bad{1}{1})=bad{1}{2};
    verifyError(testCase,@()ibr.decoupled_dual_mode_model('IBR_TEST',2,1,2, ...
        V,p,0.45,0.08,abs(V),"GFM"),'ibr:gfm_decoupled:params', ...
        sprintf('%s=%g must be rejected',bad{1}{1},bad{1}{2}));
end
end

function testReconstructPublishesWashoutAndSwingParameters(testCase)
% Report and diagnostic consumers read the reconstruct payload, so the washout
% state and the three independent coefficients must be published, and H_system
% must keep its baseline meaning 0.5*M/kappa.
[dev,~,y,ec,params]=fixture('GFM');
out=dev.reconstruct(0,dev.x0,y,dev.u0,ec);
verifyTrue(testCase,isfield(out,'gfm'));
g=out.gfm;
verifyEqual(testCase,g.omega_f,dev.x0(17),'AbsTol',0);
verifyEqual(testCase,g.omega_washout_deviation,dev.x0(11)-dev.x0(17),'AbsTol',0);
verifyEqual(testCase,g.R_droop,params.gfm_decoupled.R_droop,'AbsTol',0);
verifyEqual(testCase,g.D_t,params.gfm_decoupled.D_t,'AbsTol',0);
verifyEqual(testCase,g.wD,params.gfm_decoupled.wD,'AbsTol',0);
verifyEqual(testCase,g.Dv_static_equivalent,1/params.gfm_decoupled.R_droop, ...
    'AbsTol',1e-12);
verifyEqual(testCase,g.H_system,0.5*params.gfm_decoupled.M/1.0,'AbsTol',1e-15);
verifyFalse(testCase,isfield(g,'omega_PLL_pu'), ...
    'the GFM branch must not publish a PLL frequency');
end

% -------------------------------------------------------------------------
function [dev,V,y,ec,params]=fixture(mode)
V=1.02*exp(1i*0.08);
params=params_with(0.05,20.0,3.0,0.08);
dev=ibr.decoupled_dual_mode_model('IBR_TEST',2,1,2,V,params,0.45,0.08, ...
    abs(V),mode);
y=[real(V);imag(V)];
ec=context(mode);
end

function dev=baseline_fixture(mode)
V=1.02*exp(1i*0.08);
params=struct('Sbase',100,'Mbase',100,'fbase',60, ...
    'dc_source',struct('Tdc',0.10));
dev=ibr.eecon49_dual_mode_model('IBR_TEST',2,1,2,V,params,0.45,0.08, ...
    abs(V),mode);
end

function p=params_with(R,Dt,wD,M)
p=struct('Sbase',100,'Mbase',100,'fbase',60, ...
    'dc_source',struct('Tdc',0.10));
p.gfm_decoupled=struct('Lf',0.15,'Rf',0.015,'Cdc',0.10, ...
    'Vdc_ref',1.0,'Imax',1.2,'M',M,'R_droop',R,'D_t',Dt,'wD',wD, ...
    'tauE',0.05,'kQ',0.25,'kE',8.0,'kpV',1.2,'kiV',4.5,'kpI',0.3,'kiI',4.0);
end

function ec=context(mode)
ec=struct('hybrid_state',struct( ...
    'device_modes',struct('IBR_TEST',char(mode)), ...
    'device_online',struct('IBR_TEST',true)));
end
