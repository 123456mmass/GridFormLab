function tests=test_ibr_eecon49_dual_mode_hotpath
%WS-B regression + hotpath guard for ibr.eecon49_dual_mode_model.
%
% The WS-B refactor made three bit-preserving changes inside the device wrapper:
%   * resolve_status now returns a PRECOMPUTED canonical default mode (immutable
%     metadata hoisted at construction) instead of re-canonicalising the default
%     text on every call;
%   * canonical_mode has a verbatim fast path for the three canonical spellings
%     and only falls through to lower/strtrim/char for every other accepted
%     input;
%   * validate_state replaces ismember(numel(x),[16 17]) with a direct size
%     comparison.
%
% None of these may change f, current_injection, the FD Jacobian, the limiter
% regime, reconstruct or the transfer, and none may narrow the accepted input
% set or the error identifiers. Every numeric check below is an EXACT
% comparison (AbsTol 0) against the UNCHANGED standalone branch models, which
% are the independent oracle for the composed residual/current; the invalid
% input checks pin the exact error identifiers.
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function testRandomStatesMatchBranchCompositionAndJacobian(testCase)
% f, current and the FD Jacobian of the dual wrapper equal the branch-model
% composition, exactly, over random finite states and for both layouts.
rng(20261008,'twister');
for src=[false true]
    for md={'gfl','GFM'}
        [dev,V,y,ec,params]=fixture(md{1},src);
        branch=branch_for(md{1},V,params);
        [rm,bm,act,bact]=maps(md{1},dev.nx);
        for k=1:12
            x=dev.x0+0.05*randn(dev.nx,1);
            bx=branch_input(md{1},x);
            dd=dev.f(0,x,y,dev.u0,ec);
            db=branch.f(0,bx,y,dev.u0(1:2),ec);
            verifyEqual(testCase,dd(rm),db(bm),'AbsTol',0, ...
                sprintf('%s src=%d RHS mismatch',md{1},src));
            % every coordinate outside the live branch's map is identically zero
            inactive=setdiff(1:dev.nx,act);
            verifyEqual(testCase,dd(inactive),zeros(numel(inactive),1),'AbsTol',0);
            verifyEqual(testCase,dev.current_injection(0,x,y,dev.u0,ec), ...
                branch.current_injection(0,bx,y,dev.u0(1:2),ec),'AbsTol',0);
        end
        Jd=fd_jac(@(xx) dev.f(0,xx,y,dev.u0,ec),dev.x0,dev.nx);
        Jb=fd_jac(@(xx) branch.f(0,xx,y,dev.u0(1:2),ec), ...
            branch_input(md{1},dev.x0),branch.nx);
        verifyEqual(testCase,Jd(rm,act),Jb(bm,bact),'AbsTol',0, ...
            sprintf('%s src=%d FD Jacobian mismatch',md{1},src));
    end
end
end

function testOfflineAndTrippedProduceZeroContribution(testCase)
[dev,~,y,~,~]=fixture('gfl',true);
x=dev.x0;
ecOff=struct('hybrid_state',struct('device_modes',struct('IBR_TEST','gfl'), ...
    'device_online',struct('IBR_TEST',false)));
verifyEqual(testCase,dev.f(0,x,y,dev.u0,ecOff),zeros(dev.nx,1),'AbsTol',0);
verifyEqual(testCase,dev.current_injection(0,x,y,dev.u0,ecOff),0,'AbsTol',0);
verifyEmpty(testCase,dev.active_state_indices_for_context(ecOff));
verifyEmpty(testCase,dev.limiter_regime(0,x,y,dev.u0,ecOff));
ecTrip=struct('hybrid_state',struct('device_modes',struct('IBR_TEST','tripped'), ...
    'device_online',struct('IBR_TEST',true)));
verifyEqual(testCase,dev.f(0,x,y,dev.u0,ecTrip),zeros(dev.nx,1),'AbsTol',0);
verifyEqual(testCase,dev.current_injection(0,x,y,dev.u0,ecTrip),0,'AbsTol',0);
verifyEmpty(testCase,dev.active_state_indices_for_context(ecTrip));
verifyEmpty(testCase,dev.limiter_regime(0,x,y,dev.u0,ecTrip));
end

function testTransferPreservesPortAndDcCoordinates(testCase)
[dev,V,y,ecG,~]=fixture('gfl',true);
ecM=struct('hybrid_state',struct('device_modes',struct('IBR_TEST','GFM'), ...
    'device_online',struct('IBR_TEST',true)));
xe=dev.equilibrium_initialize(V,0.45,0.08,ecG);
I0=dev.current_injection(0,xe,y,dev.u0,ecG);
[xr,info]=dev.mode_transfer_state(xe,y,dev.u0,ecG,'GFM',ecM);
verifyEqual(testCase,xr(3),xe(3),'AbsTol',0);
verifyEqual(testCase,xr(17),xe(17),'AbsTol',0);
verifyEqual(testCase,info.I_right,info.I_left,'AbsTol',1e-10);
verifyEqual(testCase,info.Vdc_right,info.Vdc_left,'AbsTol',0);
verifyEqual(testCase,dev.current_injection(0,xr,y,dev.u0,ecM),I0,'AbsTol',1e-10);
end

function testRuntimeModeSpellingsStillAccepted(testCase)
% canonical_mode's fast path must not narrow the accepted spelling set: the
% historical lower/strtrim/char path still accepts every non-canonical case.
for spelling={'gfl','GFM','tripped','gfm','GFL','GFm',' GFM ','tripped '}
    [dev,~,y,~,~]=fixture('gfl',true);
    ec=struct('hybrid_state',struct('device_modes',struct('IBR_TEST',spelling{1}), ...
        'device_online',struct('IBR_TEST',true)));
    dx=dev.f(0,dev.x0,y,dev.u0,ec);
    if strcmpi(strtrim(spelling{1}),'tripped')
        verifyEqual(testCase,dx,zeros(dev.nx,1),'AbsTol',0);
    else
        verifyGreaterThan(testCase,norm(dx,inf),0);
    end
end
end

function testInvalidInputsKeepTheirErrorIDs(testCase)
[dev,~,y,ec,~]=fixture('gfl',true);
x=dev.x0;
verifyErrId(testCase,@() dev.f(0,x(1:15),y,dev.u0,ec), ...
    'ibr:eecon49_dual_mode_model:badState');
xx=x; xx(2)=NaN;
verifyErrId(testCase,@() dev.f(0,xx,y,dev.u0,ec), ...
    'ibr:eecon49_dual_mode_model:badState');
verifyErrId(testCase,@() dev.f(0,x,y,[1;2],ec), ...
    'ibr:eecon49_dual_mode_model:badInput');
verifyErrId(testCase,@() dev.f(0,x,y,[0.4;0.1;-1],ec), ...
    'ibr:eecon49_dual_mode_model:badInput');
ecBad=struct('hybrid_state',struct('device_modes',struct('IBR_TEST','bogus'), ...
    'device_online',struct('IBR_TEST',true)));
verifyErrId(testCase,@() dev.f(0,x,y,dev.u0,ecBad), ...
    'ibr:eecon49_dual_mode_model:badRuntimeMode');
ecNum=struct('hybrid_state',struct('device_modes',struct('IBR_TEST',7), ...
    'device_online',struct('IBR_TEST',true)));
verifyErrId(testCase,@() dev.f(0,x,y,dev.u0,ecNum), ...
    'ibr:eecon49_dual_mode_model:badRuntimeMode');
ecOnl=struct('hybrid_state',struct('device_modes',struct('IBR_TEST','gfl'), ...
    'device_online',struct('IBR_TEST',[1 0])));
verifyErrId(testCase,@() dev.f(0,x,y,dev.u0,ecOnl), ...
    'ibr:eecon49_dual_mode_model:badRuntimeOnline');
end

function testHotpathWarmMedianMicrobenchmark(testCase)
% Warm-median self time of the device RHS. This is a diagnostic guard, not a
% tight budget: it fails only if the per-call cost leaves the microsecond range
% (i.e. a hotpath regression several orders of magnitude wide).
[dev,~,y,ec,~]=fixture('gfl',true);
x=dev.x0;
f=@() dev.f(0,x,y,dev.u0,ec);
for k=1:25, f(); end
reps=7; n=300; per=zeros(1,reps);
for r=1:reps
    t0=tic; for k=1:n, f(); end
    per(r)=toc(t0)/n;
end
us=median(per)*1e6;
fprintf('\n[WS-B] eecon49_dual dev.f warm median = %.1f us/call\n',us);
verifyLessThan(testCase,us,5000);
end

% ------------------------------------------------------------------------
function [dev,V,y,ec,params]=fixture(md,src)
V=1.02*exp(1i*0.08);
if src, dc=struct('source_state',true); else, dc=struct('Tdc',0.10); end
params=struct('Sbase',100,'Mbase',100,'fbase',60,'dc_source',dc);
dev=ibr.eecon49_dual_mode_model('IBR_TEST',2,1,2,V,params,0.45,0.08,abs(V),md);
y=[real(V);imag(V)];
ec=struct('hybrid_state',struct('device_modes',struct('IBR_TEST',md), ...
    'device_online',struct('IBR_TEST',true)));
end

function branch=branch_for(md,V,params)
if strcmp(md,'gfl')
    branch=ibr.gfl_eecon49_full_model('IBR_TEST',2,1,2,V,params,0.45,0.08);
else
    branch=ibr.gfm_eecon49_full_model('IBR_TEST',2,1,2,V,params,0.45,0.08,abs(V));
end
end

function b=branch_input(md,x)
% Same coordinate maps the dual wrapper threads into each branch.
switch md
case 'gfl'
    b=[x(1:9);0];
case 'GFM'
    b=[x(1:3);x(10:16)];
end
if numel(x)>=17, b(11)=x(17); end
end

function [rm,bm,act,bact]=maps(md,nx)
% Dual row/col index -> branch row/col index for the live branch.
src=nx>=17;
switch md
case 'gfl'
    rm=1:9; bm=1:9; act=1:9; bact=1:9;
case 'GFM'
    rm=[1:3 10:16]; bm=[1:3 4:10]; act=[1:3 10:16]; bact=[1:3 4:10];
end
if src
    rm=[rm 17]; bm=[bm 11]; act=[act 17]; bact=[bact 11];
end
end

function J=fd_jac(fn,x,nx)
ep=3e-6; f0=fn(x); J=zeros(numel(f0),nx);
for j=1:nx
    xp=x; xp(j)=xp(j)+ep; J(:,j)=(fn(xp)-f0)/ep;
end
end

function verifyErrId(testCase,f,id)
threw=false;
try
    f();
catch me
    threw=true;
    verifyEqual(testCase,me.identifier,id);
end
verifyTrue(testCase,threw, ...
    sprintf('Expected identifier %s but no error was raised.',id));
end
