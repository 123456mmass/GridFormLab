function dev = gfl_eecon49_full_model(device_id,bus_id,bus_position,bus_ids,V0,params,P_ref,Q_ref)
%GFL_EECON49_FULL_MODEL  EECON49 source-mapped GFL plant/controller.
% State order (12-state switching superset):
% [i_d i_q V_dc theta_PLL xi_PLL xi_P xi_Q xi_Id xi_Iq Vd_del Vq_del z_pad].
% The first eleven states are the source blocks (AC filter, DC link, PLL,
% outer P/Q PI, inner current PI and command delays); z_pad is an inactive
% zero state so GFL and GFM share a fixed 12-state transfer ABI.
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
Lf=getv(g,'Lf',0.15); Rf=getv(g,'Rf',0.015); Cdc=getv(g,'Cdc',0.10);
Vdc_ref=getv(g,'Vdc_ref',1.0); Imax=getv(g,'Imax',1.2); Td=getv(g,'Td',0.02);
kpPLL=getv(g,'kpPLL',1.20); kiPLL=getv(g,'kiPLL',5.00);
kpP=getv(g,'kpP',0.80); kiP=getv(g,'kiP',2.50); kpQ=getv(g,'kpQ',0.80); kiQ=getv(g,'kiQ',2.50);
kpI=getv(g,'kpI',0.30); kiI=getv(g,'kiI',4.00);
omega_b=2*pi*fbase; kappa=Sbase/Mbase;
validateattributes([Lf Rf Cdc Vdc_ref Td kpPLL kiPLL kpP kiP kpQ kiQ kpI kiI omega_b kappa],{'double'},{'finite'});
if Lf<=0 || Cdc<=0 || Td<=0 || Vdc_ref<=0 || Imax<=0, error('ibr:gfl_eecon49:params','invalid positive parameter.'); end

Vmag=abs(V0); th0=angle(V0); id0=kappa*P_ref/Vmag; iq0=-kappa*Q_ref/Vmag;
Vdq=V0*exp(-1i*th0); vd=real(Vdq); vq=imag(Vdq); %#ok<NASGU>
vcd0=vd+Rf*id0-1*Lf*iq0; vcq0=vq+Rf*iq0+1*Lf*id0;
x0=[id0;iq0;Vdc_ref;th0;0;id0/kiP;-iq0/kiQ;0;0;vcd0;vcq0;0];
u0=[P_ref;Q_ref];
f=@(t,x,y,u,ec) rhs(x,y,u,bus_position,kappa,omega_b,Lf,Rf,Cdc,Vdc_ref,Imax,Td, ...
    kpPLL,kiPLL,kpP,kiP,kpQ,kiQ,kpI,kiI);
current=@(t,x,y,u,ec) current_out(x,y,bus_position,kappa,Imax);
power=@(t,x,y,u,ec) real(busv(y,bus_position)*conj(current(0,x,y,u,struct())));
recon=@(t,x,y,u,ec) reconstruct(x,y,u,bus_position,kappa,omega_b,Lf,Rf,Cdc,Vdc_ref,Imax,Td,kpPLL,kiPLL,kpP,kiP,kpQ,kiQ,kpI,kiI);
eq=@(V,P,Q,ec) equilibrium(V,P,Q,kappa,Vdc_ref,Lf,Rf,Td,kiP,kiQ);
dev=struct('name',char(device_id),'device_id',char(device_id),'bus_id',bus_id, ...
    'bus_position',bus_position,'bus_ids',bus_ids(:).','device_type','ibr_gfl_eecon49_full', ...
    'mode','gfl','nx',12,'nu',2,'state_names',{{'i_d','i_q','V_dc','theta_PLL','xi_PLL','xi_P','xi_Q','xi_Id','xi_Iq','Vd_del','Vq_del','z_pad'}}, ...
    'input_names',{{'P_ref','Q_ref'}},'x0',x0,'u0',u0,'f',f,'current_injection',current, ...
    'electrical_power',power,'reconstruct',recon,'equilibrium_initialize',eq, ...
    'active_state_indices',@(ec) 1:11,'provenance',struct('model','EECON49_GFL_FULL_STATE_MAPPED', ...
    'source','EECON49-P4 eq.(6)-(21) and parameter table','source_classification','SOURCE_MAPPED', ...
    'params',struct('Sbase',Sbase,'Mbase',Mbase,'Lf',Lf,'Rf',Rf,'Cdc',Cdc,'Vdc_ref',Vdc_ref,'Imax',Imax,'Td',Td, ...
        'kpPLL',kpPLL,'kiPLL',kiPLL,'kpP',kpP,'kiP',kiP,'kpQ',kpQ,'kiQ',kiQ,'kpI',kpI,'kiI',kiI,'kappa',kappa), ...
    'readiness','SOURCE_IMPLEMENTED_PENDING_FULL_IBR_GATES'));
end

function dx=rhs(x,y,u,bp,k,wb,L,R,C,Vdc0,Imax,Td,kppl,kipl,kpp,kip,kpq,kiq,kpi,kii)
V=busv(y,bp); id_state=x(1); iq_state=x(2); [id,iq,~]=limit_i(id_state,iq_state,Imax);
vdc=x(3); th=x(4); xiPLL=x(5); xiP=x(6); xiQ=x(7); xiId=x(8); xiIq=x(9); vd_del=x(10); vq_del=x(11);
Vdq=V*exp(-1i*th); vd=real(Vdq); vq=imag(Vdq); I=complex(id,iq)*exp(1i*th)/k; S=V*conj(I); Pinv=k*real(S); Qinv=k*imag(S);
dw=kppl*vq+kipl*xiPLL; w=1+dw/wb; eP=k*u(1)-Pinv; eQ=k*u(2)-Qinv;
idref= kpp*eP+kip*xiP; iqref=-(kpq*eQ+kiq*xiQ); [idref,iqref,sat]=limit_i(idref,iqref,Imax);
ed=idref-id; eq=iqref-iq; vcd=vd+R*id-w*L*iq+kpi*ed+kii*xiId; vcq=vq+R*iq+w*L*id+kpi*eq+kii*xiIq;
% EECON49 shows an ideal energy-source/storage port but does not publish its
% I_dc control law.  The source-mapped diagnostic closes that port at the
% instantaneous converter power, preserving the printed Vdc state without
% inventing a DC-source gain (the missing I_dc law remains a readiness gap).
P_ac=vcd*id+vcq*iq; Idc=P_ac/max(vdc,1e-4); dvdc=(Idc-P_ac/max(vdc,1e-4))/C;
dx=zeros(12,1); dx(1)=(vd_del-vd-R*id+w*L*iq)/(L/wb); dx(2)=(vq_del-vq-R*iq-w*L*id)/(L/wb);
[dx(1),dx(2)]=limit_current_derivative(id_state,iq_state,dx(1),dx(2),Imax);
dx(3)=dvdc; dx(4)=dw; dx(5)=vq; dx(6)=eP; dx(7)=eQ;
dx(8)=antiwind(ed,sat,xiId); dx(9)=antiwind(eq,sat,xiIq);
dx(10)=(vcd-vd_del)/Td; dx(11)=(vcq-vq_del)/Td; dx(12)=0;
if any(~isfinite(dx)), error('ibr:gfl_eecon49:nonfinite','non-finite RHS.'); end
end

function out=reconstruct(x,y,u,bp,k,wb,L,R,C,Vdc0,Imax,Td,kppl,kipl,kpp,kip,kpq,kiq,kpi,kii)
V=busv(y,bp); th=x(4); Vdq=V*exp(-1i*th); [id,iq,~]=limit_i(x(1),x(2),Imax); I=complex(id,iq)*exp(1i*th)/k; S=V*conj(I); dw=kppl*imag(Vdq)+kipl*x(5);
out=struct('i_d',id,'i_q',iq,'Vdc',x(3),'delta_PLL',th,'xi_PLL',x(5),'xi_P',x(6),'xi_Q',x(7),'xi_Id',x(8),'xi_Iq',x(9), ...
    'v_d',real(Vdq),'v_q',imag(Vdq),'Vd_del',x(10),'Vq_del',x(11),'omega_PLL',wb+dw,'omega_PLL_pu',1+dw/wb,'f_hz',(wb+dw)/(2*pi), ...
    'I_sys',I,'I_inv',I*k,'Pe',real(S),'Qe',imag(S),'P_inv_meas',k*real(S),'Q_inv_meas',k*imag(S), ...
    'Vbus',abs(V),'Vbus_phasor',V,'P_ref_inv',k*u(1),'Q_ref_inv',k*u(2),'Imax',Imax,'current_limited',abs(complex(id,iq))>=Imax-1e-9,'readiness','SOURCE_IMPLEMENTED_PENDING_FULL_IBR_GATES');
end

function x=equilibrium(V,P,Q,k,Vdc,L,R,Td,kiP,kiQ)
if abs(V)<=0, error('ibr:gfl_eecon49:eq','low voltage.'); end
th=angle(V); id=k*P/abs(V); iq=-k*Q/abs(V); vd=abs(V); vq=0; vcd=vd+R*id-L*iq; vcq=R*iq+L*id;
x=[id;iq;Vdc;th;0;id/kiP;-iq/kiQ;0;0;vcd;vcq;0];
end

function I=current_out(x,y,bp,k,Imax), busv(y,bp); [id,iq,~]=limit_i(x(1),x(2),Imax); I=complex(id,iq)*exp(1i*x(4))/k;
end
function V=busv(y,bp), V=complex(y(2*bp-1),y(2*bp)); if abs(V)<1e-8, error('ibr:gfl_eecon49:lowV','low voltage.'); end, end
function v=getv(s,n,d), if isfield(s,n)&&~isempty(s.(n)), v=s.(n); else, v=d; end, end
function [a,b,sat]=limit_i(a,b,m), r=hypot(a,b); sat=r>m; if sat, a=a*m/r; b=b*m/r; end, end
function [da,db]=limit_current_derivative(i0,q0,da,db,m)
r=hypot(i0,q0); if r>m && i0*da+q0*db>0, c=(i0*da+q0*db)/(r^2); da=da-c*i0; db=db-c*q0; end
end
function d=antiwind(e,s,x), if s && e*x>0, d=0; else, d=e; end, end
