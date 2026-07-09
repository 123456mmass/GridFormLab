function probe_kundur_true()
%PROBE_KUNDUR_TRUE True Kundur/GENTPJ form (no gamma, no Id_eff).
% States per machine: [delta, omega, E'q, E'd, E''q, E''d]
% de''q/dt = (e'q - e''q - id*(X'd-X''d))/T''d0
% de''d/dt = (e'd - e''d + iq*(X'q-X''q))/T''q0
% de'q/dt  = (Efd + e''q*(Xd-X'd)/(X'd-X''d) - e'q*(Xd-X''d)/(X'd-X''d))/T'd0
% de'd/dt  = (e''d*(Xq-X'q)/(X'q-X''q) - e'd*(Xq-X''q)/(X'q-X''q))/T'q0
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results',false,'verbose',false,'max_iter',50,'tolerance',1e-8,'enforce_q_limits',false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
r = stability.kundur_ex126_kundur_ssa('pf',pf,'options',struct('load_model','cc_p_cz_q'));
fprintf('=== Current (psi_1d realization) ===\n');
print_modes(r.eigenvalues);
M=case_data.machines; R=M.reactances; base=case_data.base_values;
Sm=M.base.S_MVA; Sbase=base.S_base_MVA; zb=Sbase/Sm;
% Precompute Kundur coefficients (machine pu, then *zb for system pu)
g_d1=(R.Xdpp-R.Xl)/(R.Xdp-R.Xl); g_q1=(R.Xqpp-R.Xl)/(R.Xqp-R.Xl);
init=r.init; Ynet=r.Ynet; ng=init.ng;
% Convert initial state 5,6 from psi_1d/psi_2q to E''q/E''d
for k=1:ng
  Eqp=init.x0((k-1)*6+3); Edp=init.x0((k-1)*6+4);
  Psipd=init.x0((k-1)*6+5); Psipq=init.x0((k-1)*6+6);
  init.x0((k-1)*6+5)=g_d1*Eqp+(1-g_d1)*Psipd;   % E''q
  init.x0((k-1)*6+6)=g_q1*Edp+(1-g_q1)*Psipq;   % E''d
end
f_param=@(x,y,ee,tt) dae_f(x,y,ee,tt,init,M,zb);
g_func=@(x,y) dae_g(x,y,init,M,Ynet,zb);
x=init.x0;y=init.y0;Efd=init.Efd;Tm=init.Tm;
fixed_x=1;free_x=setdiff(1:numel(x),fixed_x);fixed_y=2;free_y=setdiff(1:numel(y),fixed_y);
z0=[x(free_x);y(free_y);Efd;Tm];
resfun=@(z) residual(z,free_x,free_y,ng,x,y,init,M,Ynet,zb);
opts=optimoptions('fsolve','Display','iter','FunctionTolerance',1e-12,'StepTolerance',1e-14,'MaxIterations',500,'MaxFunctionEvaluations',5000);
fprintf('\nfsolve refining (true Kundur/GENTPJ form)...\n');
[zsol,~,exitflag,output]=fsolve(resfun,z0,opts);
fprintf('fsolve exitflag=%d, residual=%.3e, iters=%d\n',exitflag,norm(resfun(zsol)),output.iterations);
xsol=x;xsol(free_x)=zsol(1:numel(free_x));
ysol=y;ysol(free_y)=zsol(numel(free_x)+1:numel(free_x)+numel(free_y));
Efdsol=zsol(numel(free_x)+numel(free_y)+1:numel(free_x)+numel(free_y)+ng);
Tmsol=zsol(numel(free_x)+numel(free_y)+ng+1:end);
init.x0=xsol;init.y0=ysol;init.Efd=Efdsol;init.Tm=Tmsol;
nx=numel(xsol);ny=numel(ysol);eps_p=1e-6;
Jxx=zeros(nx,nx);Jxy=zeros(nx,ny);Jyx=zeros(ny,nx);Jyy=zeros(ny,ny);
for i=1:nx
  xp=xsol;xp(i)=xp(i)+eps_p;xm=xsol;xm(i)=xm(i)-eps_p;
  Jxx(:,i)=(f_param(xp,ysol,Efdsol,Tmsol)-f_param(xm,ysol,Efdsol,Tmsol))/(2*eps_p);
  Jyx(:,i)=(g_func(xp,ysol)-g_func(xm,ysol))/(2*eps_p);
end
for j=1:ny
  yp=ysol;yp(j)=yp(j)+eps_p;ym=ysol;ym(j)=ym(j)-eps_p;
  Jxy(:,j)=(f_param(xsol,yp,Efdsol,Tmsol)-f_param(xsol,ym,Efdsol,Tmsol))/(2*eps_p);
  Jyy(:,j)=(g_func(xsol,yp)-g_func(xsol,ym))/(2*eps_p);
end
Ared=Jxx-Jxy*(Jyy\Jyx);
fprintf('\n=== True Kundur/GENTPJ form (E''''q/E''''d states, no gamma) === ALL 24 ===\n');
lam=sort(eig(Ared));
fprintf('  %4s %14s %14s %10s %8s\n','No','Re','Im','f(Hz)','zeta');
for k=1:numel(lam); f=abs(imag(lam(k)))/(2*pi); z=-real(lam(k))/(abs(lam(k))+1e-12);
  fprintf('  %4d %+14.6f %+14.6f %10.4f %8.4f\n',k,real(lam(k)),imag(lam(k)),f,z); end
fprintf('\nKundur E12.3: IA -0.111+/-3.43(0.545,0.032); L1 -0.492+/-6.82(1.087,0.072); L2 -0.506+/-7.02(1.117,0.072)\n');
fprintf('              field -0.265,-0.276; q-damp -3.43,-4.14,-5.29,-5.30; d-damp -31..-38\n');
end

function res=residual(z,free_x,free_y,ng,x0,y0,init,M,Ynet,zb)
nxr=numel(free_x);nyr=numel(free_y);
x=x0;x(free_x)=z(1:nxr);y=y0;y(free_y)=z(nxr+1:nxr+nyr);
Efd=z(nxr+nyr+1:nxr+nyr+ng);Tm=z(nxr+nyr+ng+1:end);
f=dae_f(x,y,Efd,Tm,init,M,zb);
g=dae_g(x,y,init,M,Ynet,zb);
res=[f;g];
end

function print_modes(lam)
[~,idx]=sort(real(lam),'descend');lam=lam(idx);
ia=[];l1=[];l2=[];
for j=1:numel(lam); f=abs(imag(lam(j)))/(2*pi);
  if f>0.4&&f<0.7&&imag(lam(j))>0&&isempty(ia); ia=lam(j); end
  if f>0.9&&f<1.3&&imag(lam(j))>0;
    if f<1.05&&isempty(l1); l1=lam(j);
    elseif f>=1.05&&isempty(l2); l2=lam(j); end
  end
end
if ~isempty(ia); fprintf('  IA: %+.4f %+.4fj  f=%.4f z=%.4f\n',real(ia),imag(ia),abs(imag(ia))/(2*pi),-real(ia)/abs(ia)); end
if ~isempty(l1); fprintf('  L1: %+.4f %+.4fj  f=%.4f z=%.4f\n',real(l1),imag(l1),abs(imag(l1))/(2*pi),-real(l1)/abs(l1)); end
if ~isempty(l2); fprintf('  L2: %+.4f %+.4fj  f=%.4f z=%.4f\n',real(l2),imag(l2),abs(imag(l2))/(2*pi),-real(l2)/abs(l2)); end
end

function f=dae_f(x,y,Efd,Tm,init,M,zb)
% True Kundur/GENTPJ form. R in machine pu; multiply by zb for system pu.
w0=init.w0; R=M.reactances; TC=M.time_constants; ng=init.ng;
f=zeros(6*ng,1); nb=numel(y)/2;
V_bus=complex(zeros(nb,1),zeros(nb,1));
for b=1:nb;V_bus(b)=complex(y(2*b-1),y(2*b));end
% Kundur coefficients (system pu)
Xd=R.Xd*zb; Xdp=R.Xdp*zb; Xdpp=R.Xdpp*zb;
Xq=R.Xq*zb; Xqp=R.Xqp*zb; Xqpp=R.Xqpp*zb;
Ra=R.Ra*zb;
c_d=(Xd-Xdp)/(Xdp-Xdpp);   % (Xd-X'd)/(X'd-X''d)
d_d=(Xd-Xdpp)/(Xdp-Xdpp);  % (Xd-X''d)/(X'd-X''d)
c_q=(Xq-Xqp)/(Xqp-Xqpp);   % (Xq-X'q)/(X'q-X''q)
d_q=(Xq-Xqpp)/(Xqp-Xqpp);  % (Xq-X''q)/(X'q-X''q)
for k=1:ng
  bidx=init.bus_idx(k);Vt=V_bus(bidx);
  delta=x((k-1)*6+1);omega_dev=x((k-1)*6+2);
  Eqp=x((k-1)*6+3);Edp=x((k-1)*6+4);Eqpp=x((k-1)*6+5);Edpp=x((k-1)*6+6);
  Vd=sin(delta)*real(Vt)-cos(delta)*imag(Vt);
  Vq=cos(delta)*real(Vt)+sin(delta)*imag(Vt);
  % stator: Vd=E''d-Ra Id+X''q Iq; Vq=E''q-Ra Iq-X''d Id
  rhs_d=Vd-Edpp;rhs_q=Vq-Eqpp;det=Xdpp*Xqpp+Ra*Ra;
  Id=(-Ra*rhs_d-Xqpp*rhs_q)/det;Iq=(Xdpp*rhs_d-Ra*rhs_q)/det;
  Te=Vq*Iq+Vd*Id+Ra*(Id^2+Iq^2);
  H=init.H_sys(k);D=M.units(k).D*zb;
  f((k-1)*6+1)=omega_dev*w0;
  f((k-1)*6+2)=(Tm(k)-Te-D*omega_dev)/(2*H);
  % Kundur/GENTPJ transient equations (Sd=Sq=0):
  f((k-1)*6+3)=(Efd(k)+Eqpp*c_d-Eqp*d_d)/TC.Tpd0;
  f((k-1)*6+4)=(Edpp*c_q-Edp*d_q)/TC.Tpq0;
  % Kundur/GENTPJ subtransient equations (Sd=Sq=0):
  f((k-1)*6+5)=(Eqp-Eqpp-Id*(Xdp-Xdpp))/TC.Tppd0;
  f((k-1)*6+6)=(Edp-Edpp+Iq*(Xqp-Xqpp))/TC.Tppq0;
end
end

function g=dae_g(x,y,init,M,Ynet,zb)
R=M.reactances;ng=init.ng;nb=numel(y)/2;
V_bus=complex(zeros(nb,1),zeros(nb,1));
for b=1:nb;V_bus(b)=complex(y(2*b-1),y(2*b));end
Inet=Ynet*V_bus;g=zeros(2*nb,1);
for b=1:nb;g(2*b-1)=-real(Inet(b));g(2*b)=-imag(Inet(b));end
case_data=cases.case_kundur_two_area_classical();BD=case_data.bus_data;
for b=1:nb
  Pload=BD(b,7);Qload=BD(b,8);
  if Pload~=0||Qload~=0
    Vt=V_bus(b);Vop=abs(complex(init.y0(2*b-1),init.y0(2*b)));
    if abs(Vt)<=eps||Vop<=eps;Iload_p=0;else;Iload_p=(Pload/Vop)*(Vt/abs(Vt));end
    g(2*b-1)=g(2*b-1)-real(Iload_p);g(2*b)=g(2*b)-imag(Iload_p);
  end
end
Xdpp=R.Xdpp*zb;Xqpp=R.Xqpp*zb;Ra=R.Ra*zb;
for k=1:ng
  bidx=init.bus_idx(k);Vt=V_bus(bidx);delta=x((k-1)*6+1);
  Eqpp=x((k-1)*6+5);Edpp=x((k-1)*6+6);
  Vd=sin(delta)*real(Vt)-cos(delta)*imag(Vt);Vq=cos(delta)*real(Vt)+sin(delta)*imag(Vt);
  rhs_d=Vd-Edpp;rhs_q=Vq-Eqpp;det=Xdpp*Xqpp+Ra*Ra;
  Id=(-Ra*rhs_d-Xqpp*rhs_q)/det;Iq=(Xdpp*rhs_d-Ra*rhs_q)/det;
  Ire=sin(delta)*Id+cos(delta)*Iq;Iim=-cos(delta)*Id+sin(delta)*Iq;
  Ig=complex(Ire,Iim);g(2*bidx-1)=real(Ig)-real(Inet(bidx));g(2*bidx)=imag(Ig)-imag(Inet(bidx));
end
end
