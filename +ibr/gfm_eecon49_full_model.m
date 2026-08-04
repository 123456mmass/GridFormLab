function dev = gfm_eecon49_full_model(device_id,bus_id,bus_position,bus_ids,V0,params,P_ref,Q_ref)
%GFM_EECON49_FULL_MODEL  EECON49 source-mapped full-state GFM plant.
%
% The reduced-6 branch is useful for the legacy study, but it omits the
% converter energy, voltage-loop and current-loop states that are present in
% the EECON49 block diagram.  This route keeps those states explicitly:
%
%   [i_d i_q V_dc theta omega E xi_Vd xi_Vq xi_Id xi_Iq Vd_del Vq_del]
%
% The equations are the positive-sequence VSG/voltage-forming equations from
% EECON49-P4 (eqs. 22--33) coupled to the L-filter, DC-link, inner PI and
% command-delay states.  The printed parameter table specifies kp_Idq=0.30
% and ki_Idq=4.00.

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
if ~isfinite(V0) || abs(V0)<=0
    error('ibr:gfm_eecon49:badV0','V0 must be finite and nonzero.');
end
Sbase=100; Mbase=100; fbase=60;
if isfield(params,'Sbase'), Sbase=params.Sbase; end
if isfield(params,'Mbase'), Mbase=params.Mbase; end
if isfield(params,'fbase'), fbase=params.fbase; end
g=struct();
if isfield(params,'gfm_eecon49') && isstruct(params.gfm_eecon49), g=params.gfm_eecon49; end
Lf=getv(g,'Lf',0.15); Rf=getv(g,'Rf',0.015); Cdc=getv(g,'Cdc',0.10);
Vdc_ref=getv(g,'Vdc_ref',1.0); Imax=getv(g,'Imax',1.2); Td=getv(g,'Td',0.02);
M=getv(g,'M',0.08); Dv=getv(g,'Dv',1.50); tauE=getv(g,'tauE',0.05);
kQ=getv(g,'kQ',0.25); kE=getv(g,'kE',8.0);
kpV=getv(g,'kpV',1.20); kiV=getv(g,'kiV',4.50);
kpI=getv(g,'kpI',0.30); kiI=getv(g,'kiI',4.00);
wb=2*pi*fbase; kappa=Sbase/Mbase;
validateattributes([Lf Rf Cdc Vdc_ref Imax Td M Dv tauE kQ kE kpV kiV kpI kiI wb kappa],{'double'},{'finite'});
if any([Lf Cdc Vdc_ref Imax Td M tauE kpV kiV]<=0) || any([Rf Dv kQ kE kpI kiI]<0)
    error('ibr:gfm_eecon49:params','invalid GFM parameter sign or magnitude.');
end

Vmag=abs(V0); th0=angle(V0); id0=kappa*P_ref/Vmag; iq0=-kappa*Q_ref/Vmag;
% Rotor-frame equilibrium is aligned to the terminal voltage.  The two
% voltage-PI integrators then hold the required d/q current references.
vd=Vmag; vq=0;
vcd0=vd+Rf*id0-Lf*iq0; vcq0=Rf*iq0+Lf*id0;
x0=[id0;iq0;Vdc_ref;th0;1;Vmag;id0/kiV; iq0/kiV;0;0;vcd0;vcq0];
u0=[P_ref;Q_ref];
f=@(t,x,y,u,ec) rhs(x,y,u,bus_position,kappa,wb,Lf,Rf,Cdc,Vdc_ref,Imax,Td, ...
    M,Dv,tauE,kQ,kE,kpV,kiV,kpI,kiI);
current=@(t,x,y,u,ec) current_out(x,y,bus_position,kappa,Imax);
power=@(t,x,y,u,ec) real(busv(y,bus_position)*conj(current(0,x,y,u,struct())));
recon=@(t,x,y,u,ec) reconstruct(x,y,u,bus_position,kappa,wb,Lf,Rf,Cdc,Vdc_ref,Imax,Td, ...
    M,Dv,tauE,kQ,kE,kpV,kiV,kpI,kiI);
eq=@(V,P,Q,ec) equilibrium(V,P,Q,kappa,Vdc_ref,Lf,Rf,kiV);
dev=struct('name',char(device_id),'device_id',char(device_id),'bus_id',bus_id, ...
    'bus_position',bus_position,'bus_ids',bus_ids(:).','device_type','ibr_gfm_eecon49_full', ...
    'mode','GFM','nx',12,'nu',2, ...
    'state_names',{{'i_d','i_q','V_dc','theta','omega','E','xi_Vd','xi_Vq','xi_Id','xi_Iq','Vd_del','Vq_del'}}, ...
    'input_names',{{'P_ref','Q_ref'}},'x0',x0,'u0',u0,'f',f,'current_injection',current, ...
    'electrical_power',power,'reconstruct',recon,'equilibrium_initialize',eq, ...
    'active_state_indices',@(ec) 1:12, ...
    'provenance',struct('model','EECON49_GFM_FULL_STATE_MAPPED', ...
        'source','EECON49-P4 eq.(22)-(33) and parameter table', ...
        'source_classification','SOURCE_MAPPED', ...
        'state_contract','AC L-filter + DC-link + VSG + voltage PI + current PI + command delay', ...
        'E_index',6,'theta_index',4,'omega_index',5, ...
        'params',struct('Sbase',Sbase,'Mbase',Mbase,'Lf',Lf,'Rf',Rf,'Cdc',Cdc, ...
            'Vdc_ref',Vdc_ref,'Imax',Imax,'Td',Td,'M',M,'Dv',Dv,'tauE',tauE, ...
            'kQ',kQ,'kE',kE,'kpV',kpV,'kiV',kiV,'kpI',kpI,'kiI',kiI,'kappa',kappa), ...
        'readiness','SOURCE_IMPLEMENTED_PENDING_FULL_IBR_GATES'));
end

function dx=rhs(x,y,u,bp,k,wb,L,R,C,Vdc0,Imax,Td,M,Dv,tauE,kQ,kE,kpV,kiV,kpI,kiI)
V=busv(y,bp); id_state=x(1); iq_state=x(2); [id,iq,~]=limit_i(id_state,iq_state,Imax);
vdc=x(3); th=x(4); om=x(5); E=x(6);
xiVd=x(7); xiVq=x(8); xiId=x(9); xiIq=x(10); vd_del=x(11); vq_del=x(12);
Vdq=V*exp(-1i*th); vd=real(Vdq); vq=imag(Vdq); Vmag=abs(V);
I=complex(id,iq)*exp(1i*th)/k; S=V*conj(I); Pinv=k*real(S); Qinv=k*imag(S);

% VSG swing and Q-V voltage-forming dynamics (EECON49 eqs. 22--25).
dw=(k*u(1)-Pinv-Dv*(om-1))/M; dth=wb*(om-1);
% The paper's Q sign is absorbed/load-positive; the project network uses
% generator injection S=V*conj(I), so eq.(24) maps to Qref-Q here.
dE=(kQ*(k*u(2)-Qinv)-kE*(E-Vmag))/tauE;
evd=E-vd; evq=-vq; idref=kpV*evd+kiV*xiVd; iqref=kpV*evq+kiV*xiVq;
[idref,iqref,sat]=limit_i(idref,iqref,Imax);
ed=idref-id; eq=iqref-iq;
vcd=vd+R*id-om*L*iq+kpI*ed+kiI*xiId;
vcq=vq+R*iq+om*L*id+kpI*eq+kiI*xiIq;
% EECON49 shows an ideal energy-source/storage port but does not publish its
% I_dc control law; close that port at instantaneous converter power so the
% printed Vdc state remains at its reference without inventing a gain.
Pac=vcd*id+vcq*iq; Idc=Pac/max(vdc,1e-4);
dx=zeros(12,1);
dx(1)=(vd_del-vd-R*id+om*L*iq)/(L/wb);
dx(2)=(vq_del-vq-R*iq-om*L*id)/(L/wb);
[dx(1),dx(2)]=limit_current_derivative(id_state,iq_state,dx(1),dx(2),Imax);
dx(3)=(Idc-Pac/max(vdc,1e-4))/C; dx(4)=dth; dx(5)=dw; dx(6)=dE;
dx(7)=evd; dx(8)=evq; dx(9)=antiwind(ed,sat,xiId); dx(10)=antiwind(eq,sat,xiIq);
dx(11)=(vcd-vd_del)/Td; dx(12)=(vcq-vq_del)/Td;
if any(~isfinite(dx)), error('ibr:gfm_eecon49:nonfinite','non-finite RHS.'); end
end

function out=reconstruct(x,y,u,bp,k,wb,L,R,C,Vdc0,Imax,Td,M,Dv,tauE,kQ,kE,kpV,kiV,kpI,kiI)
V=busv(y,bp); th=x(4); [id,iq,~]=limit_i(x(1),x(2),Imax); I=complex(id,iq)*exp(1i*th)/k; S=V*conj(I);
Vdq=V*exp(-1i*th);
out=struct('i_d',x(1),'i_q',x(2),'Vdc',x(3),'theta',th,'delta',th,'omega',x(5),'E',x(6), ...
    'xi_Vd',x(7),'xi_Vq',x(8),'xi_Id',x(9),'xi_Iq',x(10), ...
    'v_gd',real(Vdq),'v_gq',imag(Vdq),'v_d',real(Vdq),'v_q',imag(Vdq), ...
    'omega_pu',x(5),'f_hz',(wb/(2*pi))*x(5),'I_sys',I,'I_inv',I*k, ...
    'Pe',real(S),'Qe',imag(S),'P_inv_meas',k*real(S),'Q_inv_meas',k*imag(S), ...
    'Vbus',abs(V),'Vbus_phasor',V,'P_ref_inv',k*u(1),'Q_ref_inv',k*u(2), ...
    'Imax',Imax,'current_limited',abs(complex(x(1),x(2)))>=Imax-1e-9, ...
    'M',M,'Dv',Dv,'tauE',tauE,'kQ',kQ,'kE',kE,'kpV',kpV,'kiV',kiV,'kpI',kpI,'kiI',kiI, ...
    'L',L,'R',R,'readiness','SOURCE_IMPLEMENTED_PENDING_FULL_IBR_GATES');
end

function x=equilibrium(V,P,Q,k,Vdc,L,R,kiV)
if ~isfinite(V) || abs(V)<=0, error('ibr:gfm_eecon49:eq','low voltage.'); end
th=angle(V); vm=abs(V); id=k*P/vm; iq=-k*Q/vm; vd=vm;
vcd=vd+R*id-L*iq; vcq=R*iq+L*id;
x=[id;iq;Vdc;th;1;vm;id/kiV;iq/kiV;0;0;vcd;vcq];
end
function I=current_out(x,y,bp,k,Imax), busv(y,bp); [id,iq,~]=limit_i(x(1),x(2),Imax); I=complex(id,iq)*exp(1i*x(4))/k; end
function V=busv(y,bp), V=complex(y(2*bp-1),y(2*bp)); if abs(V)<1e-8, error('ibr:gfm_eecon49:lowV','low voltage.'); end, end
function v=getv(s,n,d), if isfield(s,n)&&~isempty(s.(n)), v=s.(n); else, v=d; end, end
function [a,b,sat]=limit_i(a,b,m), r=hypot(a,b); sat=r>m; if sat, a=a*m/r; b=b*m/r; end, end
function [da,db]=limit_current_derivative(i0,q0,da,db,m)
r=hypot(i0,q0); if r>m && i0*da+q0*db>0, c=(i0*da+q0*db)/(r^2); da=da-c*i0; db=db-c*q0; end
end
function d=antiwind(e,s,x), if s && e*x>0, d=0; else, d=e; end, end
