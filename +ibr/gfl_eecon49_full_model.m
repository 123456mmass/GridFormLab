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
x0=[id0;iq0;Vdc_ref;th0;0;id0/kiP;-iq0/kiQ;0;0;0];
u0=[P_ref;Q_ref];
f=@(t,x,y,u,ec) rhs(x,y,u,bus_position,kappa,omega_b,Lf,Rf,Cdc,Vdc_ref,Imax,dcp, ...
    kpPLL,kiPLL,kpP,kiP,kpQ,kiQ,kpI,kiI);
current=@(t,x,y,u,ec) current_out(x,y,bus_position,kappa,Imax);
power=@(t,x,y,u,ec) real(busv(y,bus_position)*conj(current(0,x,y,u,struct())));
recon=@(t,x,y,u,ec) reconstruct(x,y,u,bus_position,kappa,omega_b,Lf,Rf,Cdc,Vdc_ref,Imax,kpPLL,kiPLL,kpP,kiP,kpQ,kiQ,kpI,kiI);
eq=@(V,P,Q,ec) equilibrium(V,P,Q,kappa,Vdc_ref,Lf,Rf,kiP,kiQ);
dev=struct('name',char(device_id),'device_id',char(device_id),'bus_id',bus_id, ...
    'bus_position',bus_position,'bus_ids',bus_ids(:).','device_type','ibr_gfl_eecon49_full', ...
    'mode','gfl','nx',10,'nu',2,'state_names',{{'i_d','i_q','V_dc','theta_PLL','xi_PLL','xi_P','xi_Q','xi_Id','xi_Iq','z_pad'}}, ...
    'input_names',{{'P_ref','Q_ref'}},'x0',x0,'u0',u0,'f',f,'current_injection',current, ...
    'electrical_power',power,'reconstruct',recon,'equilibrium_initialize',eq, ...
    'active_state_indices',@(ec) 1:9,'provenance',struct('model','EECON49_GFL_FULL_STATE_MAPPED', ...
    'source','EECON49-P4 eq.(6)-(19) and parameter table; command-delay eq.(20)-(21) reduced (T_d<<dt)','source_classification','SOURCE_MAPPED', ...
    'params',struct('Sbase',Sbase,'Mbase',Mbase,'fbase',fbase,'omega_b',omega_b, ...
        'Lf',Lf,'Rf',Rf,'Cdc',Cdc,'Vdc_ref',Vdc_ref,'Imax',Imax,'dc_source',dcp, ...
        'kpPLL',kpPLL,'kiPLL',kiPLL,'kpP',kpP,'kiP',kiP,'kpQ',kpQ,'kiQ',kiQ,'kpI',kpI,'kiI',kiI, ...
        'kappa',kappa,'dq_power_scale',dq_power_scale), ...
    'readiness','SOURCE_IMPLEMENTED_PENDING_FULL_IBR_GATES'));
end

function dx=rhs(x,y,u,bp,k,wb,L,R,C,Vdc0,Imax,dcp,kppl,kipl,kpp,kip,kpq,kiq,kpi,kii)
V=busv(y,bp); id=x(1); iq=x(2);
vdc=x(3); th=x(4); xiPLL=x(5); xiP=x(6); xiQ=x(7); xiId=x(8); xiIq=x(9);
Vdq=V*exp(-1i*th); vd=real(Vdq); vq=imag(Vdq); I=complex(id,iq)*exp(1i*th)/k; S=V*conj(I); Pinv=k*real(S); Qinv=k*imag(S);
dw=kppl*vq+kipl*xiPLL; w=1+dw/wb; eP=k*u(1)-Pinv; eQ=k*u(2)-Qinv;
    idref_raw=kpp*eP+kip*xiP; iqref_raw=-(kpq*eQ+kiq*xiQ);
    [idref,iqref,sat]=limit_i(idref_raw,iqref_raw,Imax);
    ri_d=idref_raw-idref; ri_q=iqref_raw-iqref;
ed=idref-id; eq=iqref-iq; vcd=vd+R*id-w*L*iq+kpi*ed+kii*xiId; vcq=vq+R*iq+w*L*id+kpi*eq+kii*xiIq;
% PROJECT_DERIVED DC-source closure. The source specifies the energy balance
% but no I_dc law. The project supplies a non-ideal source: an EMF behind its
% internal resistance, with an overvoltage chopper. P_ac is the converter-side
% power, i.e. the bus power plus the filter loss, which is what the DC bus
% actually has to supply.
P_ac=vcd*id+vcq*iq;
dvdc=ibr.dc_source_thevenin_rhs(vdc,P_ac,dcp);
% Command-delay states reduced (T_d << dt, slow manifold v_del = v_cmd): the
% inner-loop commanded voltage vcd/vcq drives the AC current dynamics directly.
dx=zeros(10,1); dx(1)=(vcd-vd-R*id+w*L*iq)/(L/wb); dx(2)=(vcq-vq-R*iq-w*L*id)/(L/wb);
    dx(3)=dvdc; dx(4)=dw; dx(5)=vq;
    % The P/Q integrators generate the current reference clipped by Imax;
    % their limiter residual therefore owns conditional anti-windup.  The
    % q-axis direction gain is -kiq because iqref_raw uses the project Q sign.
    dx(6)=conditional_hold(eP,kip,ri_d,sat);
    dx(7)=conditional_hold(eQ,-kiq,ri_q,sat);
    dx(8)=ed; dx(9)=eq;
dx(10)=0;
if any(~isfinite(dx)), error('ibr:gfl_eecon49:nonfinite','non-finite RHS.'); end
end

function out=reconstruct(x,y,u,bp,k,wb,L,R,C,Vdc0,Imax,kppl,kipl,kpp,kip,kpq,kiq,kpi,kii)
V=busv(y,bp); th=x(4); Vdq=V*exp(-1i*th); id=x(1); iq=x(2); I=complex(id,iq)*exp(1i*th)/k; S=V*conj(I); dw=kppl*imag(Vdq)+kipl*x(5);
out=struct('i_d',id,'i_q',iq,'Vdc',x(3),'delta_PLL',th,'xi_PLL',x(5),'xi_P',x(6),'xi_Q',x(7),'xi_Id',x(8),'xi_Iq',x(9), ...
    'v_d',real(Vdq),'v_q',imag(Vdq),'omega_PLL',wb+dw,'omega_PLL_pu',1+dw/wb,'f_hz',(wb+dw)/(2*pi), ...
    'I_sys',I,'I_inv',I*k,'I_dq',complex(id,iq),'Pe',real(S),'Qe',imag(S),'P_inv_meas',k*real(S),'Q_inv_meas',k*imag(S), ...
    'Vbus',abs(V),'Vbus_phasor',V,'P_ref_inv',k*u(1),'Q_ref_inv',k*u(2),'Imax',Imax,'current_limited',abs(complex(id,iq))>=Imax-1e-9,'readiness','SOURCE_IMPLEMENTED_PENDING_FULL_IBR_GATES');
end

function x=equilibrium(V,P,Q,k,Vdc,L,R,kiP,kiQ) %#ok<INUSD>
if abs(V)<=0, error('ibr:gfl_eecon49:eq','low voltage.'); end
th=angle(V); id=k*P/abs(V); iq=-k*Q/abs(V);
x=[id;iq;Vdc;th;0;id/kiP;-iq/kiQ;0;0;0];
end

function I=current_out(x,y,bp,k,Imax) %#ok<INUSD>
busv(y,bp); I=complex(x(1),x(2))*exp(1i*x(4))/k;
end
function V=busv(y,bp), V=complex(y(2*bp-1),y(2*bp)); if abs(V)<1e-8, error('ibr:gfl_eecon49:lowV','low voltage.'); end, end
function v=getv(s,n,d), if isfield(s,n)&&~isempty(s.(n)), v=s.(n); else, v=d; end, end
function [a,b,sat]=limit_i(a,b,m), r=hypot(a,b); sat=r>m; if sat, a=a*m/r; b=b*m/r; end, end
function d=conditional_hold(e,direction_gain,limiter_residual,limited)
if limited && direction_gain*e*limiter_residual>0, d=0; else, d=e; end
end
