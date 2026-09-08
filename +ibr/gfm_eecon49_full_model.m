function dev = gfm_eecon49_full_model(device_id,bus_id,bus_position,bus_ids,V0,params,P_ref,Q_ref,E_ref)
%GFM_EECON49_FULL_MODEL  EECON49 source-mapped full-state GFM plant.
%
% The reduced-6 branch is useful for the legacy study, but it omits the
% converter energy, voltage-loop and current-loop states that are present in
% the EECON49 block diagram.  This route keeps those states explicitly:
%
%   [i_d i_q V_dc theta omega E xi_Vd xi_Vq xi_Id xi_Iq]
%
% The equations are the positive-sequence VSG/voltage-forming equations from
% EECON49-P4 (eqs. 22--29) coupled to the common L-filter/DC-link and the
% shared inner PI structure from eqs. 16--19 and Fig. 2.  The command-delay
% lag (eqs. 20--21, T_d = 1.5/f_sw ~= 0.3 ms at f_sw = 5 kHz) is >300x below
% the phasor step dt = 0.10 s, so by singular perturbation it collapses onto
% its slow manifold v_del = v_cmd; the two delay states are removed
% algebraically and the AC current dynamics use the commanded voltage vcd/vcq
% directly (see gfl_eecon49_full_model and defect TD-2026-08-12-01).  The
% printed parameter table specifies kp_Idq=0.30 and ki_Idq=4.00.

arguments
    device_id (1,1) string
    bus_id (1,1) double
    bus_position (1,1) double
    bus_ids (1,:) double
    V0 (1,1) double
    params struct
    P_ref (1,1) double
    Q_ref (1,1) double
    E_ref (1,1) double = NaN
end
if ~isfinite(V0) || abs(V0)<=0
    error('ibr:gfm_eecon49:badV0','V0 must be finite and nonzero.');
end
if isnan(E_ref), E_ref=abs(V0); end
if ~isfinite(E_ref) || E_ref<=0
    error('ibr:gfm_eecon49:badEref','E_ref must be finite and positive.');
end
Sbase=100; Mbase=100; fbase=60;
if isfield(params,'Sbase'), Sbase=params.Sbase; end
if isfield(params,'Mbase'), Mbase=params.Mbase; end
if isfield(params,'fbase'), fbase=params.fbase; end
g=struct();
if isfield(params,'gfm_eecon49') && isstruct(params.gfm_eecon49), g=params.gfm_eecon49; end
dc=struct();
if isfield(params,'dc_source') && isstruct(params.dc_source), dc=params.dc_source; end
Lf=getv(g,'Lf',0.15); Rf=getv(g,'Rf',0.015); Cdc=getv(g,'Cdc',0.10);
Vdc_ref=getv(g,'Vdc_ref',1.0); Imax=getv(g,'Imax',1.2);
M=getv(g,'M',0.08); Dv=getv(g,'Dv',20.0); tauE=getv(g,'tauE',0.05);
kQ=getv(g,'kQ',0.25); kE=getv(g,'kE',8.0);
kpV=getv(g,'kpV',1.20); kiV=getv(g,'kiV',4.50);
kpI=getv(g,'kpI',0.30); kiI=getv(g,'kiI',4.00);
wb=2*pi*fbase; kappa=Sbase/Mbase;
dq_power_scale=1;
validateattributes([Lf Rf Cdc Vdc_ref Imax M Dv tauE kQ kE kpV kiV kpI kiI wb kappa],{'double'},{'finite'});
if any([Lf Cdc Vdc_ref Imax M tauE kpV kiV]<=0) || any([Rf Dv kQ kE kpI kiI]<0)
    error('ibr:gfm_eecon49:params','invalid GFM parameter sign or magnitude.');
end

% Non-ideal DC source, identical helper and identical arguments as the GFL
% branch, so Edc agrees between the two and the runtime transfer preserves
% dVdc/dt as well as V_dc itself. Derivation in ibr.dc_source_thevenin_params.
dcp=ibr.dc_source_thevenin_params(dc,Vdc_ref,Cdc,Rf,kappa,P_ref,Q_ref,V0);

nx_dev=10; if dcp.source_state, nx_dev=11; end
x0=equilibrium(V0,P_ref,Q_ref,kappa,Vdc_ref,Lf,Rf,kiV,dcp);
u0=[P_ref;Q_ref;E_ref];
% Runtime limiter-regime key; see the GFL branch for the derivation. The
% current limiter and its anti-windup are BRANCH SWITCHES recomputed inside
% every residual evaluation (:114, :136-137), so a coupled Newton solve whose
% FD perturbations straddle the switching surface assembles Jacobian columns
% from two different equations. The solver may freeze the branch for one solve
% via event_context.limiter_freeze.<key>; absent, every expression below is
% the historical one in the historical order.
limiter_key=matlab.lang.makeValidName(char(device_id), ...
    'ReplacementStyle','underscore');
f=@(t,x,y,u,ec) rhs(x,y,u,bus_position,kappa,wb,Lf,Rf,Cdc,Vdc_ref,Imax,dcp, ...
    M,Dv,tauE,kQ,kE,kpV,kiV,kpI,kiI,E_ref,limiter_freeze(ec,limiter_key), ...
    anti_windup_blend(ec));
current=@(t,x,y,u,ec) current_out(x,y,bus_position,kappa,Imax);
power=@(t,x,y,u,ec) real(busv(y,bus_position)*conj(current(0,x,y,u,struct())));
recon=@(t,x,y,u,ec) reconstruct(x,y,u,bus_position,kappa,wb,Lf,Rf,Cdc,Vdc_ref,Imax, ...
    M,Dv,tauE,kQ,kE,kpV,kiV,kpI,kiI,E_ref);
eq=@(V,P,Q,ec) equilibrium(V,P,Q,kappa,Vdc_ref,Lf,Rf,kiV,dcp);
% Regime oracle for the outer active-set loop: the UNFROZEN branch decision at
% this state, produced by the same arithmetic path as the RHS.
regime=@(t,x,y,u,ec) regime_only(x,y,u,bus_position,kappa,wb,Lf,Rf,Cdc, ...
    Vdc_ref,Imax,dcp,M,Dv,tauE,kQ,kE,kpV,kiV,kpI,kiI,E_ref, ...
    anti_windup_blend(ec));
dev=struct('name',char(device_id),'device_id',char(device_id),'bus_id',bus_id, ...
    'bus_position',bus_position,'bus_ids',bus_ids(:).','device_type','ibr_gfm_eecon49_full', ...
    'mode','GFM','nx',nx_dev,'nu',3, ...
    'state_names',{gfm_state_names_for(nx_dev)}, ...
    'input_names',{{'P_ref','Q_ref','E_ref'}},'x0',x0,'u0',u0,'f',f,'current_injection',current, ...
    'electrical_power',power,'reconstruct',recon,'equilibrium_initialize',eq, ...
    'active_state_indices',@(ec) 1:nx_dev, ...
    'limiter_regime',regime,'limiter_regime_key',limiter_key, ...
    'provenance',struct('model','EECON49_GFM_FULL_STATE_MAPPED', ...
        'source','EECON49-P4 eqs.(6)-(8),(16)-(29), Fig.2 and parameter table; command-delay eqs.(20)-(21) reduced (T_d<<dt)', ...
        'source_classification','SOURCE_MAPPED', ...
        'state_contract','AC L-filter + DC-link + VSG + voltage PI + current PI (command delay reduced, v_del=v_cmd)', ...
        'E_index',6,'theta_index',4,'omega_index',5, ...
    'params',struct('Sbase',Sbase,'Mbase',Mbase,'fbase',fbase,'omega_b',wb,'E_ref',E_ref, ...
            'Lf',Lf,'Rf',Rf,'Cdc',Cdc, ...
            'Vdc_ref',Vdc_ref,'Imax',Imax,'dc_source',dcp,'M',M,'Dv',Dv,'tauE',tauE, ...
            'kQ',kQ,'kE',kE,'kpV',kpV,'kiV',kiV,'kpI',kpI,'kiI',kiI, ...
            'kappa',kappa,'dq_power_scale',dq_power_scale), ...
        'readiness','SOURCE_IMPLEMENTED_PENDING_FULL_IBR_GATES'));
end

function [dx,reg]=rhs(x,y,u,bp,k,wb,L,R,C,Vdc0,Imax,dcp,M,Dv,tauE,kQ,kE,kpV,kiV,kpI,kiI,Eref0,frz,awb)
if nargin<23, frz=[]; end
if nargin<24 || isempty(awb), awb=0; end
V=busv(y,bp); id=x(1); iq=x(2);
vdc=x(3); th=x(4); om=x(5); E=x(6);
xiVd=x(7); xiVq=x(8); xiId=x(9); xiIq=x(10);
Vdq=V*exp(-1i*th); vd=real(Vdq); vq=imag(Vdq); Vmag=abs(V);
I=complex(id,iq)*exp(1i*th)/k; S=V*conj(I); Pinv=k*real(S); Qinv=k*imag(S);

% VSG swing and Q-V voltage-forming dynamics (EECON49 eqs. 22--25).
dw=(k*u(1)-Pinv-Dv*(om-1))/M; dth=wb*(om-1);
% The paper's Q sign is absorbed/load-positive; the project network uses
% generator injection S=V*conj(I), so eq.(24) maps to Qref-Q here.
Eref=Eref0; if numel(u)>=3, Eref=u(3); end
dE=(kQ*(k*u(2)-Qinv)-kE*(E-Eref))/tauE;
% E is the voltage-loop reference state itself: Vd_ref=E, Vq_ref=0.
% Do not place an additional virtual impedance between E and this loop;
% doing so changes both the published state meaning and its Q-V residual.
vdref=E; vqref=0;
evd=vdref-vd; evq=vqref-vq;
idref_raw=kpV*evd+kiV*xiVd;
iqref_raw=kpV*evq+kiV*xiVq;
[idref,iqref,sat]=limit_i(idref_raw,iqref_raw,Imax);
ri_d=idref_raw-idref; ri_q=iqref_raw-iqref;
% Unfrozen branch decision at this state, reported for the outer active-set
% loop. conditional_hold stays the SINGLE owner of the anti-windup predicate
% and now also returns which way it went. A freeze overrides ONLY the two
% voltage-loop integrator rows; the clipped references idref/iqref and
% therefore every other row are computed from the live limiter as before.
[dh_d,hold_d]=conditional_hold(evd,kiV,ri_d,sat,Imax,awb);
[dh_q,hold_q]=conditional_hold(evq,kiV,ri_q,sat,Imax,awb);
reg=struct('sat',sat,'hold_d',hold_d,'hold_q',hold_q);
if ~isempty(frz)
    if frz.hold_d, dh_d=0; else, dh_d=evd; end
    if frz.hold_q, dh_q=0; else, dh_q=evq; end
end
ed=idref-id; eq=iqref-iq;
vcd=vd+R*id-om*L*iq+kpI*ed+kiI*xiId;
vcq=vq+R*iq+om*L*id+kpI*eq+kiI*xiIq;
% PROJECT_DERIVED DC-source closure; the same physical port and the same
% Thevenin source parameters are shared across GFL/GFM. Derivation in
% ibr.dc_source_thevenin_params.
Pac=vcd*id+vcq*iq;
% Command-delay states reduced (T_d << dt, slow manifold v_del = v_cmd): the
% inner-loop commanded voltage vcd/vcq drives the AC current dynamics directly.
dx=zeros(numel(x),1);
dx(1)=(vcd-vd-R*id+om*L*iq)/(L/wb);
dx(2)=(vcq-vq-R*iq-om*L*id)/(L/wb);
if dcp.source_state, idc=x(11); else, idc=(dcp.Edc-vdc)/dcp.Rdc; end
dc_rows=ibr.dc_source_thevenin_rhs(vdc,idc,Pac,dcp);
dx(3)=dc_rows(1); dx(4)=dth; dx(5)=dw; dx(6)=dE;
if dcp.source_state, dx(11)=dc_rows(2); end
% Anti-windup belongs to the voltage-loop integrators because their output
% is the current-reference vector clipped by Imax. The inner current PI has
% no separate voltage-command clamp in this model and therefore integrates
% ed/eq normally.
dx(7)=dh_d;
dx(8)=dh_q;
dx(9)=ed; dx(10)=eq;
if any(~isfinite(dx)), error('ibr:gfm_eecon49:nonfinite','non-finite RHS.'); end
end

function reg=regime_only(x,y,u,bp,k,wb,L,R,C,Vdc0,Imax,dcp, ...
    M,Dv,tauE,kQ,kE,kpV,kiV,kpI,kiI,Eref0,awb)
%REGIME_ONLY  The UNFROZEN limiter branch at this state, for the outer loop.
[~,reg]=rhs(x,y,u,bp,k,wb,L,R,C,Vdc0,Imax,dcp, ...
    M,Dv,tauE,kQ,kE,kpV,kiV,kpI,kiI,Eref0,[],awb);
end

function out=reconstruct(x,y,u,bp,k,wb,L,R,C,Vdc0,Imax,M,Dv,tauE,kQ,kE,kpV,kiV,kpI,kiI,Eref0)
V=busv(y,bp); th=x(4); id=x(1); iq=x(2); I=complex(id,iq)*exp(1i*th)/k; S=V*conj(I);
Vdq=V*exp(-1i*th);
Eref=Eref0; if numel(u)>=3, Eref=u(3); end
out=struct('i_d',x(1),'i_q',x(2),'Vdc',x(3),'theta',th,'delta',th,'omega',x(5),'E',x(6), ...
    'xi_Vd',x(7),'xi_Vq',x(8),'xi_Id',x(9),'xi_Iq',x(10), ...
    'v_gd',real(Vdq),'v_gq',imag(Vdq),'v_d',real(Vdq),'v_q',imag(Vdq), ...
    'omega_pu',x(5),'f_hz',(wb/(2*pi))*x(5),'I_sys',I,'I_inv',I*k,'I_dq',complex(id,iq), ...
    'Pe',real(S),'Qe',imag(S),'P_inv_meas',k*real(S),'Q_inv_meas',k*imag(S), ...
    'Vbus',abs(V),'Vbus_phasor',V,'P_ref_inv',k*u(1),'Q_ref_inv',k*u(2),'E_ref',Eref, ...
    'Imax',Imax,'current_limited',abs(complex(x(1),x(2)))>=Imax-1e-9, ...
    'M',M,'Dv',Dv,'tauE',tauE,'kQ',kQ,'kE',kE,'kpV',kpV,'kiV',kiV,'kpI',kpI,'kiI',kiI, ...
    'L',L,'R',R,'readiness','SOURCE_IMPLEMENTED_PENDING_FULL_IBR_GATES');
end

function x=equilibrium(V,P,Q,k,Vdc,L,R,kiV,dcp) %#ok<INUSD>
if ~isfinite(V) || abs(V)<=0, error('ibr:gfm_eecon49:eq','low voltage.'); end
I_sys=conj(complex(P,Q)/V);
I_inv=k*I_sys;
th=angle(V); E=abs(V);
Idq=I_inv*exp(-1i*th); id=real(Idq); iq=imag(Idq);
% Index 11 is the DC-source current state, appended so indices 1..10 keep their
% published meaning.
x=[id;iq;Vdc;th;1;E;id/kiV;iq/kiV;0;0];
if dcp.source_state, x(11)=dcp.Idc0; end
end

function n=gfm_state_names_for(nx)
n={'i_d','i_q','V_dc','theta','omega','E','xi_Vd','xi_Vq','xi_Id','xi_Iq'};
if nx>=11, n{11}='I_dc'; end
end
function I=current_out(x,y,bp,k,Imax) %#ok<INUSD>
busv(y,bp); I=complex(x(1),x(2))*exp(1i*x(4))/k;
end
function V=busv(y,bp), V=complex(y(2*bp-1),y(2*bp)); if abs(V)<1e-8, error('ibr:gfm_eecon49:lowV','low voltage.'); end, end
function v=getv(s,n,d), if isfield(s,n)&&~isempty(s.(n)), v=s.(n); else, v=d; end, end
function [a,b,sat]=limit_i(a,b,m), r=hypot(a,b); sat=r>m; if sat, a=a*m/r; b=b*m/r; end, end
function [d,held]=conditional_hold(e,direction_gain,limiter_residual,limited,m,blend)
%CONDITIONAL_HOLD  Anti-windup on the voltage-loop PI: hold when the limiter is
%   active and the integrator is driving further into the limit. HELD reports
%   the branch taken so the solver can freeze it without duplicating the
%   predicate.
%
%   BLEND (default 0) is the declared NUMERICAL_METHOD regularization of the
%   switch; see the GFL branch for the derivation and the measured sliding mode.
%   blend = 0 is the historical hard switch expression for expression; blend > 0
%   engages the hold continuously over a band of width blend*m in the limiter
%   residual, so the RHS is Lipschitz instead of jumping by |e|. Outside the
%   band the two forms agree exactly.
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
%   Read from event_context.anti_windup_blend, set by the TS driver from its own
%   opt-in option. Absent (every historical caller) returns 0 and the hard
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
