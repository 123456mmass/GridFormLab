function dev = gfm_decoupled_full_model(device_id,bus_id,bus_position,bus_ids,V0,params,P_ref,Q_ref,E_ref)
%GFM_DECOUPLED_FULL_MODEL  GFM plant with independent droop, damping, inertia.
%
% PROJECT_DERIVED structure.  Everything except the swing block is the
% unchanged EECON49-mapped plant of ibr.gfm_eecon49_full_model (L-filter, DC
% link, Q-V amplitude loop, voltage PI, current PI, circular current-reference
% limiter, conditional anti-windup); that file is retained byte-faithful as
% the comparison baseline and is NOT modified by this route.
%
% Motivation.  The baseline swing equation
%
%   M d(omega)/dt = kappa P_ref - P_inv - Dv (omega - 1)
%
% has ONE free coefficient, so the steady-state P-f droop (1/Dv) and the
% swing damping ratio (zeta = Dv / (2 sqrt(M omega_b K)) for synchronising
% coefficient K) cannot be chosen independently.  Adding a second
% proportional term does not help, because
%
%   -(1/R)(omega-1) - D (omega-1) = -(1/R + D)(omega-1)
%
% collapses to a single coefficient again; the in-repo REGFM_B1 reference
% model shows the same algebra explicitly as -(1/mp + D1)*omega_m
% (regfm_b1_vsg_model.m:629) and consequently ships D1 = 0.  Separating droop
% from damping therefore requires one additional state.
%
% Equations (this file's only structural change):
%
%   M d(omega)/dt   = kappa P_ref - P_inv - (1/R)(omega - 1)
%                                         - D_t (omega - omega_f)
%   d(theta)/dt     = omega_b (omega - 1)
%   d(omega_f)/dt   = w_D (omega - omega_f)
%
% Properties, each proved by an oracle in
% tests/test_ibr_decoupled_swing_decoupling_oracle.m:
%   * DROOP is R alone.  At any steady state omega_f = omega, the D_t term is
%     exactly zero, and omega - 1 = R (kappa P_ref - P_inv).  D_t and w_D
%     cannot move the steady-state characteristic.
%   * DAMPING adds D_t only transiently.  The washout transfer
%     D_t s/(s + w_D) contributes D_t w^2/(w^2 + w_D^2) of real damping at
%     frequency w, so the effective damping ratio is
%     zeta ~= [1/R + D_t w_n^2/(w_n^2 + w_D^2)] / (2 sqrt(M omega_b K)).
%   * INERTIA is M alone, unchanged in meaning from the baseline.
%   * D_t = 0 reproduces the baseline exactly with Dv = 1/R, which is the
%     equivalence oracle for this implementation.
%
% The washout structure is the two-term GFM damping of the NREL REGFM_B1
% reference model already implemented in this repository
% (regfm_b1_vsg_model.m:629-630, Table 1 SOURCE_VERBATIM D2 = 100, wD = 50),
% re-expressed in the EECON49 absolute-speed variables (omega = 1 at
% equilibrium) instead of REGFM_B1's deviation variable omega_m.  The numeric
% wD is NOT inherited: REGFM_B1's 2H is far larger, so its swing frequency and
% therefore its washout corner differ.  wD here is set from this plant's own
% measured swing frequency (see the parameter block below).
%
% State (11):
%   [i_d i_q V_dc theta omega E xi_Vd xi_Vq xi_Id xi_Iq omega_f]
% omega_f is appended LAST on purpose: theta/omega/E keep their published
% indices 4/5/6, the common plant keeps 1:3, and every existing index-based
% consumer of the 10-state layout stays valid.
%
% Parameter classification: R_droop, D_t and wD are PROJECT_DERIVED with the
% derivation recorded in docs/project/DECOUPLED_GFM_SOURCE_CONTRACT.md.  Every
% other parameter keeps the value, unit and role it has in the EECON49-mapped
% baseline.  Read from params.gfm_decoupled (no silent fall-back to another
% device's parameter block).

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
    error('ibr:gfm_decoupled:badV0','V0 must be finite and nonzero.');
end
if isnan(E_ref), E_ref=abs(V0); end
if ~isfinite(E_ref) || E_ref<=0
    error('ibr:gfm_decoupled:badEref','E_ref must be finite and positive.');
end
Sbase=100; Mbase=100; fbase=60;
if isfield(params,'Sbase'), Sbase=params.Sbase; end
if isfield(params,'Mbase'), Mbase=params.Mbase; end
if isfield(params,'fbase'), fbase=params.fbase; end
g=struct();
if isfield(params,'gfm_decoupled') && isstruct(params.gfm_decoupled)
    g=params.gfm_decoupled;
end
dc=struct();
if isfield(params,'dc_source') && isstruct(params.dc_source), dc=params.dc_source; end
Lf=getv(g,'Lf',0.15); Rf=getv(g,'Rf',0.015); Cdc=getv(g,'Cdc',0.10);
Vdc_ref=getv(g,'Vdc_ref',1.0); Imax=getv(g,'Imax',1.2);
Tdc=getv(dc,'Tdc',0.10);
M=getv(g,'M',0.08); tauE=getv(g,'tauE',0.05);
% R_droop / D_t / wD defaults are the PROJECT_DERIVED production values,
% derived in docs/project/DECOUPLED_GFM_SOURCE_CONTRACT.md from the MEASURED
% synchronising coefficient K = 0.1135..0.1862 pu/rad (full-KCL Schur-reduced
% SSSA of the IEEE14 all-GFM SG-online configuration), not from an estimate:
%   R_droop = 0.05   5 % P-f droop (WECC/CAISO 3-5 %, ERCOT GFM <= 5 %)
%   wD      = 3.0    wD/wn = 0.10..0.13 so the washout gain is >= 0.984 at the
%                    swing frequency, while tau = 1/wD = 0.333 s stays far
%                    inside the primary-frequency-response window
%   D_t     = 20.0   exact-cubic solution for zeta = 1/sqrt(2) at the measured
%                    K; the attained zeta is 0.7072..0.7151 across that range
Rd=getv(g,'R_droop',0.05); Dt=getv(g,'D_t',20.0); wD=getv(g,'wD',3.0);
kQ=getv(g,'kQ',0.25); kE=getv(g,'kE',8.0);
kpV=getv(g,'kpV',1.20); kiV=getv(g,'kiV',4.50);
kpI=getv(g,'kpI',0.30); kiI=getv(g,'kiI',4.00);
wb=2*pi*fbase; kappa=Sbase/Mbase;
dq_power_scale=1;
validateattributes([Lf Rf Cdc Vdc_ref Imax Tdc M Rd Dt wD tauE kQ kE ...
    kpV kiV kpI kiI wb kappa],{'double'},{'finite'});
% R_droop and wD must be strictly positive: R_droop = 0 removes the only
% steady-state P-omega characteristic, and wD = 0 freezes omega_f so the
% washout term degenerates into an unbounded proportional damping.
if any([Lf Cdc Vdc_ref Imax Tdc M Rd wD tauE kpV kiV]<=0) || ...
        any([Rf Dt kQ kE kpI kiI]<0)
    error('ibr:gfm_decoupled:params','invalid GFM parameter sign or magnitude.');
end

x0=equilibrium(V0,P_ref,Q_ref,kappa,Vdc_ref,Lf,Rf,kiV);
u0=[P_ref;Q_ref;E_ref];
f=@(t,x,y,u,ec) rhs(x,y,u,bus_position,kappa,wb,Lf,Rf,Cdc,Vdc_ref,Imax,Tdc, ...
    M,Rd,Dt,wD,tauE,kQ,kE,kpV,kiV,kpI,kiI,E_ref);
current=@(t,x,y,u,ec) current_out(x,y,bus_position,kappa,Imax);
power=@(t,x,y,u,ec) real(busv(y,bus_position)*conj(current(0,x,y,u,struct())));
recon=@(t,x,y,u,ec) reconstruct(x,y,u,bus_position,kappa,wb,Lf,Rf,Cdc,Vdc_ref,Imax, ...
    M,Rd,Dt,wD,tauE,kQ,kE,kpV,kiV,kpI,kiI,E_ref);
eq=@(V,P,Q,ec) equilibrium(V,P,Q,kappa,Vdc_ref,Lf,Rf,kiV);
dev=struct('name',char(device_id),'device_id',char(device_id),'bus_id',bus_id, ...
    'bus_position',bus_position,'bus_ids',bus_ids(:).', ...
    'device_type','ibr_gfm_decoupled_full', ...
    'mode','GFM','nx',11,'nu',3, ...
    'state_names',{{'i_d','i_q','V_dc','theta','omega','E','xi_Vd','xi_Vq', ...
        'xi_Id','xi_Iq','omega_f'}}, ...
    'input_names',{{'P_ref','Q_ref','E_ref'}},'x0',x0,'u0',u0,'f',f, ...
    'current_injection',current, ...
    'electrical_power',power,'reconstruct',recon,'equilibrium_initialize',eq, ...
    'active_state_indices',@(ec) 1:11, ...
    'provenance',struct('model','GFM_DECOUPLED_DROOP_DAMPING_INERTIA', ...
        'source',['Swing block PROJECT_DERIVED (washout damping structure ' ...
            'after regfm_b1_vsg_model.m:629-630); remaining plant and control ' ...
            'equations as mapped in gfm_eecon49_full_model, eqs.(6)-(8),' ...
            '(16)-(19),(23)-(29) with the command delay reduced'], ...
        'source_classification','PROJECT_DERIVED_SWING_OVER_MAPPED_PLANT', ...
        'state_contract',['AC L-filter + DC-link + decoupled VSG ' ...
            '(droop R_droop, washout damping D_t/wD, inertia M) + voltage PI ' ...
            '+ current PI (command delay reduced, v_del=v_cmd)'], ...
        'E_index',6,'theta_index',4,'omega_index',5,'omega_f_index',11, ...
        'params',struct('Sbase',Sbase,'Mbase',Mbase,'fbase',fbase, ...
            'omega_b',wb,'E_ref',E_ref,'Lf',Lf,'Rf',Rf,'Cdc',Cdc, ...
            'Vdc_ref',Vdc_ref,'Imax',Imax,'Tdc',Tdc,'M',M, ...
            'R_droop',Rd,'D_t',Dt,'wD',wD,'Dv_static_equivalent',1/Rd, ...
            'tauE',tauE,'kQ',kQ,'kE',kE,'kpV',kpV,'kiV',kiV, ...
            'kpI',kpI,'kiI',kiI, ...
            'kappa',kappa,'dq_power_scale',dq_power_scale), ...
        'readiness','PROJECT_MODEL_PENDING_DECOUPLED_GATES'));
end

function dx=rhs(x,y,u,bp,k,wb,L,R,C,Vdc0,Imax,Tdc,M,Rd,Dt,wD,tauE,kQ,kE, ...
    kpV,kiV,kpI,kiI,Eref0)
V=busv(y,bp); id=x(1); iq=x(2);
vdc=x(3); th=x(4); om=x(5); E=x(6);
xiVd=x(7); xiVq=x(8); xiId=x(9); xiIq=x(10); omf=x(11);
Vdq=V*exp(-1i*th); vd=real(Vdq); vq=imag(Vdq);
I=complex(id,iq)*exp(1i*th)/k; S=V*conj(I); Pinv=k*real(S); Qinv=k*imag(S);

% Decoupled VSG swing.  1/Rd is the ONLY steady-state P-omega coefficient, so
% the droop is Rd exactly.  Dt*(om-omf) is a washout (transient) term: omf
% integrates towards om with rate wD, so the term is identically zero at any
% steady state and cannot bias the droop.  M alone sets the inertial timescale.
% Dt=0 reduces this to the baseline swing with Dv=1/Rd.
dw=(k*u(1)-Pinv-(1/Rd)*(om-1)-Dt*(om-omf))/M; dth=wb*(om-1);
domf=wD*(om-omf);
% Q-V voltage-forming dynamics, unchanged from the mapped baseline.  The
% paper's Q sign is absorbed/load-positive; the project network uses generator
% injection S=V*conj(I), so the amplitude equation maps to Qref-Q here.
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
ed=idref-id; eq=iqref-iq;
vcd=vd+R*id-om*L*iq+kpI*ed+kiI*xiId;
vcq=vq+R*iq+om*L*id+kpI*eq+kiI*xiIq;
% PROJECT_DERIVED DC-source closure; the same physical port and declared Tdc
% are shared across GFL/GFM. See the GFL branch for the derivation.
Pac=vcd*id+vcq*iq;
% Command-delay states reduced (T_d << dt, slow manifold v_del = v_cmd): the
% inner-loop commanded voltage vcd/vcq drives the AC current dynamics directly.
dx=zeros(11,1);
dx(1)=(vcd-vd-R*id+om*L*iq)/(L/wb);
dx(2)=(vcq-vq-R*iq-om*L*id)/(L/wb);
dx(3)=dc_link_rhs(vdc,Vdc0,V,u,k,R,C,Tdc,Pac); dx(4)=dth; dx(5)=dw; dx(6)=dE;
% Anti-windup belongs to the voltage-loop integrators because their output
% is the current-reference vector clipped by Imax. The inner current PI has
% no separate voltage-command clamp in this model and therefore integrates
% ed/eq normally.
dx(7)=conditional_hold(evd,kiV,ri_d,sat);
dx(8)=conditional_hold(evq,kiV,ri_q,sat);
dx(9)=ed; dx(10)=eq; dx(11)=domf;
if any(~isfinite(dx)), error('ibr:gfm_decoupled:nonfinite','non-finite RHS.'); end
end

function out=reconstruct(x,y,u,bp,k,wb,L,R,C,Vdc0,Imax,M,Rd,Dt,wD,tauE, ...
    kQ,kE,kpV,kiV,kpI,kiI,Eref0)
V=busv(y,bp); th=x(4); id=x(1); iq=x(2); I=complex(id,iq)*exp(1i*th)/k; S=V*conj(I);
Vdq=V*exp(-1i*th);
Eref=Eref0; if numel(u)>=3, Eref=u(3); end
out=struct('i_d',x(1),'i_q',x(2),'Vdc',x(3),'theta',th,'delta',th, ...
    'omega',x(5),'E',x(6), ...
    'xi_Vd',x(7),'xi_Vq',x(8),'xi_Id',x(9),'xi_Iq',x(10),'omega_f',x(11), ...
    'omega_washout_deviation',x(5)-x(11), ...
    'v_gd',real(Vdq),'v_gq',imag(Vdq),'v_d',real(Vdq),'v_q',imag(Vdq), ...
    'omega_pu',x(5),'f_hz',(wb/(2*pi))*x(5),'I_sys',I,'I_inv',I*k, ...
    'I_dq',complex(id,iq), ...
    'Pe',real(S),'Qe',imag(S),'P_inv_meas',k*real(S),'Q_inv_meas',k*imag(S), ...
    'Vbus',abs(V),'Vbus_phasor',V,'P_ref_inv',k*u(1),'Q_ref_inv',k*u(2), ...
    'E_ref',Eref, ...
    'Imax',Imax,'current_limited',abs(complex(x(1),x(2)))>=Imax-1e-9, ...
    'M',M,'R_droop',Rd,'D_t',Dt,'wD',wD,'Dv_static_equivalent',1/Rd, ...
    'droop_percent',100*Rd, ...
    'tauE',tauE,'kQ',kQ,'kE',kE,'kpV',kpV,'kiV',kiV,'kpI',kpI,'kiI',kiI, ...
    'L',L,'R',R,'readiness','PROJECT_MODEL_PENDING_DECOUPLED_GATES');
end

function x=equilibrium(V,P,Q,k,Vdc,L,R,kiV) %#ok<INUSD>
% omega_f = 1 = omega at every equilibrium, so the washout term is exactly
% zero here and this vector is independent of R_droop, D_t, wD and M -- the
% same property the baseline equilibrium has with respect to Dv and M.
if ~isfinite(V) || abs(V)<=0, error('ibr:gfm_decoupled:eq','low voltage.'); end
I_sys=conj(complex(P,Q)/V);
I_inv=k*I_sys;
th=angle(V); E=abs(V);
Idq=I_inv*exp(-1i*th); id=real(Idq); iq=imag(Idq);
x=[id;iq;Vdc;th;1;E;id/kiV;iq/kiV;0;0;1];
end
function I=current_out(x,y,bp,k,Imax) %#ok<INUSD>
busv(y,bp); I=complex(x(1),x(2))*exp(1i*x(4))/k;
end
function V=busv(y,bp), V=complex(y(2*bp-1),y(2*bp)); if abs(V)<1e-8, error('ibr:gfm_decoupled:lowV','low voltage.'); end, end
function v=getv(s,n,d), if isfield(s,n)&&~isempty(s.(n)), v=s.(n); else, v=d; end, end
function [a,b,sat]=limit_i(a,b,m), r=hypot(a,b); sat=r>m; if sat, a=a*m/r; b=b*m/r; end, end
function d=conditional_hold(e,direction_gain,limiter_residual,limited)
if limited && direction_gain*e*limiter_residual>0, d=0; else, d=e; end
end
function dv=dc_link_rhs(vdc,Vdc0,V,u,k,R,C,Tdc,Pac) %#ok<INUSD>
if ~isfinite(vdc) || vdc<=1e-6
    error('ibr:gfm_decoupled:dcVoltage','V_dc must remain finite and positive.');
end
Idc=Pac/vdc+(C/Tdc)*(Vdc0-vdc);
dv=(Idc-Pac/vdc)/C;
end
