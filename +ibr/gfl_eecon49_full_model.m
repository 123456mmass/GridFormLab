function dev = gfl_eecon49_full_model(device_id,bus_id,bus_position,bus_ids,V0,params,P_ref,Q_ref)
%GFL_EECON49_FULL_MODEL  EECON49 source-mapped GFL plant/controller.
% State order (10-state switching superset):
% [i_d i_q V_dc theta_PLL xi_PLL xi_P xi_Q xi_Id xi_Iq z_pad].
% The first nine states are the source blocks (AC filter, DC link, PLL,
% outer P/Q PI, inner current PI); z_pad is an inactive zero state so GFL and
% GFM share a fixed 10-state transfer ABI.
%
% Command/actuation-delay reduction (PROJECT_DERIVED, owner-set 2026-08-12).
% The source's command-delay lag T_d*v_del_dot = v_cmd - v_del carries the
% physical digital-VSC actuation delay T_d = 1.5/f_sw ~= 0.3 ms (f_sw = 5 kHz).
% That is >300x below the phasor-engine step dt = 0.10 s, so by singular
% perturbation the fast lag collapses onto its slow manifold v_del = v_cmd. The
% two delay states are removed algebraically and the AC current dynamics use
% the commanded voltage v_cmd (vcd/vcq) directly. This standard model-order
% reduction (T_d << dt) leaves both the equilibrium and the retained-state
% dynamics unchanged, and removes the ~530 Hz pole the RMS network model cannot
% resolve. See defect TD-2026-08-12-01.
%
% Source parameters are EECON49-P4, including kp_Idq=0.30 and ki_Idq=4.00.

arguments
    device_id (1,1) string
    bus_id (1,1) double
    bus_position (1,1) double
    bus_ids (1,:) double
    V0 (1,1) double
    params struct
    P_ref (1,1) double
    Q_ref (1,1) double
end
if ~isfinite(V0) || abs(V0)<=0, error('ibr:gfl_eecon49:badV0','V0 must be finite and nonzero.'); end
Sbase=100; Mbase=100; fbase=60;
if isfield(params,'Sbase'), Sbase=params.Sbase; end
if isfield(params,'Mbase'), Mbase=params.Mbase; end
if isfield(params,'fbase'), fbase=params.fbase; end
g=struct(); if isfield(params,'gfl_eecon49') && isstruct(params.gfl_eecon49), g=params.gfl_eecon49; end
dc=struct(); if isfield(params,'dc_source') && isstruct(params.dc_source), dc=params.dc_source; end
Lf=getv(g,'Lf',0.15); Rf=getv(g,'Rf',0.015); Cdc=getv(g,'Cdc',0.10);
Vdc_ref=getv(g,'Vdc_ref',1.0); Imax=getv(g,'Imax',1.2);
kpPLL=getv(g,'kpPLL',1.20); kiPLL=getv(g,'kiPLL',5.00);
kpP=getv(g,'kpP',0.80); kiP=getv(g,'kiP',2.50); kpQ=getv(g,'kpQ',0.80); kiQ=getv(g,'kiQ',2.50);
kpI=getv(g,'kpI',0.30); kiI=getv(g,'kiI',4.00);
omega_b=2*pi*fbase; kappa=Sbase/Mbase;
dq_power_scale=1;
validateattributes([Lf Rf Cdc Vdc_ref kpPLL kiPLL kpP kiP kpQ kiQ kpI kiI omega_b kappa],{'double'},{'finite'});
if Lf<=0 || Cdc<=0 || Vdc_ref<=0 || Imax<=0, error('ibr:gfl_eecon49:params','invalid positive parameter.'); end

% Non-ideal DC source. The closure, the forced value of Edc, the derivation of
% Rdc from the declared regulation, the boundedness proof and the reported
% stiffness all live in ibr.dc_source_thevenin_params. Both controller branches
% call the same helper with the same arguments, so Edc is identical in GFL and
% GFM and a runtime transfer introduces no step in dVdc/dt.
dcp=ibr.dc_source_thevenin_params(dc,Vdc_ref,Cdc,Rf,kappa,P_ref,Q_ref,V0);

Vmag=abs(V0); th0=angle(V0);
id0=kappa*P_ref/Vmag;
iq0=-kappa*Q_ref/Vmag;
% Index 11 is the DC-source current state, present only when the case asks for it
% (dc_source.source_state). It is APPENDED so that every previously published
% index (1..10) keeps its meaning; the layout is versioned by extension, not
% renumbered, and models that keep the tau_s -> 0 limit see the unchanged
% 10-state device.
nx_dev=10; if dcp.source_state, nx_dev=11; end
x0=[id0;iq0;Vdc_ref;th0;0;id0/kiP;-iq0/kiQ;0;0;0];
if dcp.source_state, x0(11)=dcp.Idc0; end
u0=[P_ref;Q_ref];
% Runtime limiter-regime key. The current limiter and its anti-windup are
% BRANCH SWITCHES recomputed inside every residual evaluation (:94, :115-116),
% so a coupled Newton solve whose FD perturbations straddle the switching
% surface assembles Jacobian columns from two different equations. The solver
% may therefore FREEZE the branch for the duration of one solve and reclassify
% outside it (the active-set pattern stability.active_bound_run already uses
% for the equilibrium solve). The freeze is read from
% event_context.limiter_freeze.<key>; absent, every expression below is the
% historical one, evaluated in the same order.
limiter_key=matlab.lang.makeValidName(char(device_id), ...
    'ReplacementStyle','underscore');
f=@(t,x,y,u,ec) rhs(x,y,u,bus_position,kappa,omega_b,Lf,Rf,Cdc,Vdc_ref,Imax,dcp, ...
    kpPLL,kiPLL,kpP,kiP,kpQ,kiQ,kpI,kiI,limiter_freeze(ec,limiter_key), ...
    anti_windup_blend(ec));
current=@(t,x,y,u,ec) current_out(x,y,bus_position,kappa,Imax);
power=@(t,x,y,u,ec) real(busv(y,bus_position)*conj(current(0,x,y,u,struct())));
recon=@(t,x,y,u,ec) reconstruct(x,y,u,bus_position,kappa,omega_b,Lf,Rf,Cdc,Vdc_ref,Imax,kpPLL,kiPLL,kpP,kiP,kpQ,kiQ,kpI,kiI);
eq=@(V,P,Q,ec) equilibrium(V,P,Q,kappa,Vdc_ref,Lf,Rf,kiP,kiQ,dcp);
% Regime oracle for the outer active-set loop: the UNFROZEN branch decision at
% this state. It is produced by the same arithmetic path as the RHS (second
% output of rhs) so the two can never drift apart.
regime=@(t,x,y,u,ec) regime_only(x,y,u,bus_position,kappa,omega_b,Lf,Rf,Cdc, ...
    Vdc_ref,Imax,dcp,kpPLL,kiPLL,kpP,kiP,kpQ,kiQ,kpI,kiI,anti_windup_blend(ec));
dev=struct('name',char(device_id),'device_id',char(device_id),'bus_id',bus_id, ...
    'bus_position',bus_position,'bus_ids',bus_ids(:).','device_type','ibr_gfl_eecon49_full', ...
    'mode','gfl','nx',nx_dev,'nu',2,'state_names',{state_names_for(nx_dev)}, ...
    'input_names',{{'P_ref','Q_ref'}},'x0',x0,'u0',u0,'f',f,'current_injection',current, ...
    'electrical_power',power,'reconstruct',recon,'equilibrium_initialize',eq, ...
    'active_state_indices',@(ec) active_for(nx_dev), ...
    'limiter_regime',regime,'limiter_regime_key',limiter_key, ...
    'provenance',struct('model','EECON49_GFL_FULL_STATE_MAPPED', ...
    'source','EECON49-P4 eq.(6)-(19) and parameter table; command-delay eq.(20)-(21) reduced (T_d<<dt)','source_classification','SOURCE_MAPPED', ...
    'params',struct('Sbase',Sbase,'Mbase',Mbase,'fbase',fbase,'omega_b',omega_b, ...
        'Lf',Lf,'Rf',Rf,'Cdc',Cdc,'Vdc_ref',Vdc_ref,'Imax',Imax,'dc_source',dcp, ...
        'kpPLL',kpPLL,'kiPLL',kiPLL,'kpP',kpP,'kiP',kiP,'kpQ',kpQ,'kiQ',kiQ,'kpI',kpI,'kiI',kiI, ...
        'kappa',kappa,'dq_power_scale',dq_power_scale), ...
    'readiness','SOURCE_IMPLEMENTED_PENDING_FULL_IBR_GATES'));
end

function [dx,reg]=rhs(x,y,u,bp,k,wb,L,R,C,Vdc0,Imax,dcp,kppl,kipl,kpp,kip,kpq,kiq,kpi,kii,frz,awb)
if nargin<21, frz=[]; end
if nargin<22 || isempty(awb), awb=0; end
V=busv(y,bp); id=x(1); iq=x(2);
vdc=x(3); th=x(4); xiPLL=x(5); xiP=x(6); xiQ=x(7); xiId=x(8); xiIq=x(9);
Vdq=V*exp(-1i*th); vd=real(Vdq); vq=imag(Vdq); I=complex(id,iq)*exp(1i*th)/k; S=V*conj(I); Pinv=k*real(S); Qinv=k*imag(S);
dw=kppl*vq+kipl*xiPLL; w=1+dw/wb; eP=k*u(1)-Pinv; eQ=k*u(2)-Qinv;
    idref_raw=kpp*eP+kip*xiP; iqref_raw=-(kpq*eQ+kiq*xiQ);
    [idref,iqref,sat]=limit_i(idref_raw,iqref_raw,Imax);
    ri_d=idref_raw-idref; ri_q=iqref_raw-iqref;
% Unfrozen branch decision at this state, reported for the outer active-set
% loop. conditional_hold stays the SINGLE owner of the anti-windup predicate
% and now also returns which way it went. A freeze overrides ONLY these two
% integrator rows; the clipped references idref/iqref and therefore every other
% row are computed from the live limiter exactly as before.
[dh_d,hold_d]=conditional_hold(eP,kip,ri_d,sat,Imax,awb);
[dh_q,hold_q]=conditional_hold(eQ,-kiq,ri_q,sat,Imax,awb);
reg=struct('sat',sat,'hold_d',hold_d,'hold_q',hold_q);
if ~isempty(frz)
    if frz.hold_d, dh_d=0; else, dh_d=eP; end
    if frz.hold_q, dh_q=0; else, dh_q=eQ; end
end
ed=idref-id; eq=iqref-iq; vcd=vd+R*id-w*L*iq+kpi*ed+kii*xiId; vcq=vq+R*iq+w*L*id+kpi*eq+kii*xiIq;
% PROJECT_DERIVED DC-source closure. The source specifies the energy balance
% but no I_dc law. The project supplies a non-ideal source: an EMF behind its
% internal resistance, with an overvoltage chopper. P_ac is the converter-side
% power, i.e. the bus power plus the filter loss, which is what the DC bus
% actually has to supply.
P_ac=vcd*id+vcq*iq;
% With no source state, I_dc is the static Thevenin current, which is exactly the
% tau_s -> 0 limit of the two-row circuit.
if dcp.source_state, idc=x(11); else, idc=(dcp.Edc-vdc)/dcp.Rdc; end
dc_rows=ibr.dc_source_thevenin_rhs(vdc,idc,P_ac,dcp);
% Command-delay states reduced (T_d << dt, slow manifold v_del = v_cmd): the
% inner-loop commanded voltage vcd/vcq drives the AC current dynamics directly.
dx=zeros(numel(x),1); dx(1)=(vcd-vd-R*id+w*L*iq)/(L/wb); dx(2)=(vcq-vq-R*iq-w*L*id)/(L/wb);
    dx(3)=dc_rows(1); dx(4)=dw; dx(5)=vq;
    if dcp.source_state, dx(11)=dc_rows(2); end
    % The P/Q integrators generate the current reference clipped by Imax;
    % their limiter residual therefore owns conditional anti-windup.  The
    % q-axis direction gain is -kiq because iqref_raw uses the project Q sign.
    dx(6)=dh_d;
    dx(7)=dh_q;
    dx(8)=ed; dx(9)=eq;
dx(10)=0;
if any(~isfinite(dx)), error('ibr:gfl_eecon49:nonfinite','non-finite RHS.'); end
end

function reg=regime_only(x,y,u,bp,k,wb,L,R,C,Vdc0,Imax,dcp, ...
    kppl,kipl,kpp,kip,kpq,kiq,kpi,kii,awb)
%REGIME_ONLY  The UNFROZEN limiter branch at this state, for the outer loop.
[~,reg]=rhs(x,y,u,bp,k,wb,L,R,C,Vdc0,Imax,dcp, ...
    kppl,kipl,kpp,kip,kpq,kiq,kpi,kii,[],awb);
end

function out=reconstruct(x,y,u,bp,k,wb,L,R,C,Vdc0,Imax,kppl,kipl,kpp,kip,kpq,kiq,kpi,kii)
V=busv(y,bp); th=x(4); Vdq=V*exp(-1i*th); id=x(1); iq=x(2); I=complex(id,iq)*exp(1i*th)/k; S=V*conj(I); dw=kppl*imag(Vdq)+kipl*x(5);
out=struct('i_d',id,'i_q',iq,'Vdc',x(3),'delta_PLL',th,'xi_PLL',x(5),'xi_P',x(6),'xi_Q',x(7),'xi_Id',x(8),'xi_Iq',x(9), ...
    'v_d',real(Vdq),'v_q',imag(Vdq),'omega_PLL',wb+dw,'omega_PLL_pu',1+dw/wb,'f_hz',(wb+dw)/(2*pi), ...
    'I_sys',I,'I_inv',I*k,'I_dq',complex(id,iq),'Pe',real(S),'Qe',imag(S),'P_inv_meas',k*real(S),'Q_inv_meas',k*imag(S), ...
    'Vbus',abs(V),'Vbus_phasor',V,'P_ref_inv',k*u(1),'Q_ref_inv',k*u(2),'Imax',Imax,'current_limited',abs(complex(id,iq))>=Imax-1e-9,'readiness','SOURCE_IMPLEMENTED_PENDING_FULL_IBR_GATES');
end

function x=equilibrium(V,P,Q,k,Vdc,L,R,kiP,kiQ,dcp) %#ok<INUSD>
if abs(V)<=0, error('ibr:gfl_eecon49:eq','low voltage.'); end
th=angle(V); id=k*P/abs(V); iq=-k*Q/abs(V);
x=[id;iq;Vdc;th;0;id/kiP;-iq/kiQ;0;0;0];
if dcp.source_state, x(11)=dcp.Idc0; end
end

function n=state_names_for(nx)
n={'i_d','i_q','V_dc','theta_PLL','xi_PLL','xi_P','xi_Q','xi_Id','xi_Iq','z_pad'};
if nx>=11, n{11}='I_dc'; end
end

function a=active_for(nx)
a=1:9; if nx>=11, a=[1:9 11]; end
end

function I=current_out(x,y,bp,k,Imax) %#ok<INUSD>
busv(y,bp); I=complex(x(1),x(2))*exp(1i*x(4))/k;
end
function V=busv(y,bp), V=complex(y(2*bp-1),y(2*bp)); if abs(V)<1e-8, error('ibr:gfl_eecon49:lowV','low voltage.'); end, end
function v=getv(s,n,d), if isfield(s,n)&&~isempty(s.(n)), v=s.(n); else, v=d; end, end
function [a,b,sat]=limit_i(a,b,m), r=hypot(a,b); sat=r>m; if sat, a=a*m/r; b=b*m/r; end, end
function [d,held]=conditional_hold(e,direction_gain,limiter_residual,limited,m,blend)
%CONDITIONAL_HOLD  Anti-windup on the outer PI: hold when the limiter is active
%   and the integrator is driving further into the limit. HELD reports the
%   branch taken, so the solver can freeze it without duplicating the predicate.
%
%   BLEND (default 0) is a declared NUMERICAL_METHOD regularization of the
%   switch, not a change of control law. With blend = 0 this is the historical
%   hard switch, expression for expression. With blend > 0 the hold engages
%   CONTINUOUSLY over a band of width blend*m in the limiter residual:
%
%       s = min(1, |ri| / (blend*m)),   d = e*(1-s)
%
%   Outside that band the two forms are identical: |ri| >= blend*m gives s = 1
%   and d = 0, and a non-windup direction gives d = e either way. Inside it the
%   RHS is Lipschitz instead of jumping by |e|.
%
%   WHY THIS IS REQUIRED, not cosmetic. The hard switch admits states where
%   NEITHER branch is self-consistent: solved with the hold on, the solution
%   lands where the limiter is inactive; solved with it off, the solution lands
%   where the limiter is active and winding up. Measured at the sg_fault_bus9
%   wall (tmp/mt/probe_live.log): IBR2's hold pair 2-cycles (0,0) -> (1,1)
%   -> (0,0) for as many outer passes as are allowed, and the root of either
%   pure branch misses the true switched residual by 1.879e-06. That is a
%   sliding mode: the trajectory must travel ALONG r = Imax, and its velocity
%   there is a convex combination of the two branch velocities, which the hard
%   switch cannot represent at any step size. Lowering dt_min from 0.05/2^13 to
%   0.05/2^18 confirms this -- the wall does not move (tmp/mt/probe_floorfix.log).
%   The blended form contains that convex combination at s in (0,1), so the
%   sliding solution is a genuine root and Newton converges to it under the
%   unchanged newton_tol.
if nargin<6 || isempty(blend), blend=0; end
held = limited && direction_gain*e*limiter_residual>0;
if ~held, d=e; return; end
if blend<=0, d=0; return; end
s = min(1, abs(limiter_residual)/(blend*m));
d = e*(1-s);
held = s>=1;
end

function awb=anti_windup_blend(ec)
%ANTI_WINDUP_BLEND  Declared blend width for the anti-windup switch, or 0.
%   Read from event_context.anti_windup_blend, which the TS driver sets from its
%   own opt-in option. Absent (every historical caller) returns 0 and the hard
%   switch is taken, so the model is byte-identical.
awb=0;
if isempty(ec) || ~isstruct(ec) || ~isfield(ec,'anti_windup_blend'), return; end
v=ec.anti_windup_blend;
if isnumeric(v) && isscalar(v) && isfinite(v) && v>=0, awb=double(v); end
end

function frz=limiter_freeze(ec,key)
%LIMITER_FREEZE  Read a frozen limiter branch for this device, or [].
%   The solver publishes event_context.limiter_freeze.<key> = struct with
%   hold_d/hold_q while it holds the branch fixed inside one Newton solve.
%   Absent (every historical caller), this returns [] and the RHS takes its
%   live branch decision, so the model is byte-identical.
frz=[];
if isempty(ec) || ~isstruct(ec) || ~isfield(ec,'limiter_freeze'), return; end
lf=ec.limiter_freeze;
if ~isstruct(lf) || ~isscalar(lf) || ~isfield(lf,key), return; end
c=lf.(key);
if isstruct(c) && isscalar(c) && isfield(c,'hold_d') && isfield(c,'hold_q') && ...
        islogical(c.hold_d) && isscalar(c.hold_d) && ...
        islogical(c.hold_q) && isscalar(c.hold_q)
    frz=c;
end
end
