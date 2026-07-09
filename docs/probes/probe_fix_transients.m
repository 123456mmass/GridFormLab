function probe_fix_transients()
%PROBE_FIX_TRANSIENTS Test whether fixing the transient-flux equations to the
%consistent damper-flux realization (Sauer-Pai 3.151-3.154 / ANDES GENROU)
%removes the damping error.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results',false,'verbose',false,'max_iter',50,'tolerance',1e-8,'enforce_q_limits',false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
opts = struct('load_model','cc_p_cz_q','use_saturation',false);
r = stability.kundur_ex126_sauer_pai_ssa('pf',pf,'options',opts);
fprintf('=== Current (mixed realization) ===\n');
print_modes(r.eigenvalues);

M = case_data.machines; R = M.reactances; base = case_data.base_values;
Sm = M.base.S_MVA; Sbase = base.S_base_MVA; zb = Sbase/Sm;
g_d1 = (R.Xdpp-R.Xl)/(R.Xdp-R.Xl); g_q1 = (R.Xqpp-R.Xl)/(R.Xqp-R.Xl);
gamma = struct('d1',g_d1,'q1',g_q1);
init = r.init; Ynet = r.Ynet;

f_param = @(xx,yy,ee,tt) dae_f_patched(xx,yy,ee,tt,init,M,Ynet,base,gamma,zb);
g_func  = @(xx,yy) dae_g_orig(xx,yy,init,M,Ynet,base,gamma,zb);

% RE-REFINE the operating point with the corrected equations (Efd, Tm free).
x = init.x0; y = init.y0; Efd = init.Efd; Tm = init.Tm;
ng = init.ng;
fixed_x = 1; free_x = setdiff(1:numel(x), fixed_x);
fixed_y = 2; free_y = setdiff(1:numel(y), fixed_y);
maxit = 500; tol = 1e-10; eps_p = 1e-6;
for it = 1:maxit
  fv = f_param(x,y,Efd,Tm); gv = g_func(x,y);
  res = [fv; gv]; nr = norm(res);
  if nr < tol; break; end
  nxr=numel(free_x); nyr=numel(free_y); ntot=nxr+nyr+2*ng;
  J = zeros(numel(fv)+numel(gv), ntot);
  for ii=1:nxr; i=free_x(ii); xp=x; xp(i)=xp(i)+eps_p; xm=x; xm(i)=xm(i)-eps_p;
    J(:,ii)=([f_param(xp,y,Efd,Tm);g_func(xp,y)]-[f_param(xm,y,Efd,Tm);g_func(xm,y)])/(2*eps_p); end
  for jj=1:nyr; j=free_y(jj); yp=y; yp(j)=yp(j)+eps_p; ym=y; ym(j)=ym(j)-eps_p;
    J(:,nxr+jj)=([f_param(x,yp,Efd,Tm);g_func(x,yp)]-[f_param(x,ym,Efd,Tm);g_func(x,ym)])/(2*eps_p); end
  for kk=1:ng; ep=Efd; ep(kk)=ep(kk)+eps_p; em=Efd; em(kk)=em(kk)-eps_p;
    J(:,nxr+nyr+kk)=([f_param(x,y,ep,Tm);g_func(x,y)]-[f_param(x,y,em,Tm);g_func(x,y)])/(2*eps_p); end
  for kk=1:ng; tp=Tm; tp(kk)=tp(kk)+eps_p; tm2=Tm; tm2(kk)=tm2(kk)-eps_p;
    J(:,nxr+nyr+ng+kk)=([f_param(x,y,Efd,tp);g_func(x,y)]-[f_param(x,y,Efd,tm2);g_func(x,y)])/(2*eps_p); end
  % Damped Gauss-Newton with pseudoinverse fallback for singular Jacobian.
  lambda = 1e-8;
  st = (J'*J + lambda*eye(ntot)) \ (J'*(-res));
  rn_best = inf; xb=x; yb=y; eb=Efd; tb=Tm;
  for tries = 1:40
    x_new=x; x_new(free_x)=x_new(free_x)+st(1:nxr);
    y_new=y; y_new(free_y)=y_new(free_y)+st(nxr+1:nxr+nyr);
    e_new=Efd + st(nxr+nyr+1:nxr+nyr+ng);
    t_new=Tm + st(nxr+nyr+ng+1:end);
    rn = norm([f_param(x_new,y_new,e_new,t_new);g_func(x_new,y_new)]);
    if rn < rn_best; rn_best = rn; xb=x_new; yb=y_new; eb=e_new; tb=t_new; end
    lambda = lambda*5;
    st = (J'*J + lambda*eye(ntot)) \ (J'*(-res));
  end
  if rn_best >= nr
    st = pinv(J) * (-res);
    x_new=x; x_new(free_x)=x_new(free_x)+st(1:nxr);
    y_new=y; y_new(free_y)=y_new(free_y)+st(nxr+1:nxr+nyr);
    e_new=Efd + st(nxr+nyr+1:nxr+nyr+ng);
    t_new=Tm + st(nxr+nyr+ng+1:end);
    rn = norm([f_param(x_new,y_new,e_new,t_new);g_func(x_new,y_new)]);
    if rn < nr; xb=x_new; yb=y_new; eb=e_new; tb=t_new; rn_best=rn; end
  end
  if rn_best >= nr; break; end
  x=xb; y=yb; Efd=eb; Tm=tb;
  if mod(it,20)==0; fprintf('  it=%d nr=%.3e\n',it,nr); end
end
init.x0 = x; init.y0 = y; init.Efd = Efd; init.Tm = Tm;
fprintf('\nRe-refine: iters=%d, residual=%.3e\n', it, norm([f_param(x,y,Efd,Tm);g_func(x,y)]));

nx = numel(init.x0); ny = numel(init.y0);
x0 = init.x0; y0 = init.y0;
Jxx = zeros(nx,nx); Jxy = zeros(nx,ny); Jyx = zeros(ny,nx); Jyy = zeros(ny,ny);
for i = 1:nx
  xp=x0; xp(i)=xp(i)+eps_p; xm=x0; xm(i)=xm(i)-eps_p;
  Jxx(:,i) = (f_param(xp,y0,Efd,Tm)-f_param(xm,y0,Efd,Tm))/(2*eps_p);
  Jyx(:,i) = (g_func(xp,y0)-g_func(xm,y0))/(2*eps_p);
end
for j = 1:ny
  yp=y0; yp(j)=yp(j)+eps_p; ym=y0; ym(j)=ym(j)-eps_p;
  Jxy(:,j) = (f_param(x0,yp,Efd,Tm)-f_param(x0,ym,Efd,Tm))/(2*eps_p);
  Jyy(:,j) = (g_func(x0,yp)-g_func(x0,ym))/(2*eps_p);
end
Ared = Jxx - Jxy*(Jyy\Jyx);
fprintf('\n=== Patched (consistent damper-flux realization) === ALL 24 ===\n');
lam=sort(eig(Ared));
fprintf('  %4s %14s %14s %10s %8s\n','No','Re','Im','f(Hz)','zeta');
for k=1:numel(lam); f=abs(imag(lam(k)))/(2*pi); z=-real(lam(k))/(abs(lam(k))+1e-12); fprintf('  %4d %+14.6f %+14.6f %10.4f %8.4f\n',k,real(lam(k)),imag(lam(k)),f,z); end
fprintf('Kundur E12.3: IA -0.111+/-3.43(0.545,0.032); L1 -0.492+/-6.82(1.087,0.072); L2 -0.506+/-7.02(1.117,0.072)\n');
end

function print_modes(lam)
[~,idx]=sort(real(lam),'descend'); lam=lam(idx);
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

% Patched differential equations with Efd, Tm as explicit parameters.
function f = dae_f_patched(x, y, Efd, Tm, init, M, Ynet, base, gamma, zb)
w0=init.w0; R=M.reactances; TC=M.time_constants; ng=init.ng;
f=zeros(6*ng,1); nb=numel(y)/2;
V_bus=complex(zeros(nb,1),zeros(nb,1));
for b=1:nb; V_bus(b)=complex(y(2*b-1),y(2*b)); end
for k=1:ng
  bidx=init.bus_idx(k); Vt=V_bus(bidx);
  delta=x((k-1)*6+1); omega_dev=x((k-1)*6+2);
  Eqp=x((k-1)*6+3); Edp=x((k-1)*6+4);
  Psipd=x((k-1)*6+5); Psipq=x((k-1)*6+6);
  Xd_n=R.Xd*zb; Xdp_n=R.Xdp*zb; Xdpp_n=R.Xdpp*zb;
  Xq_n=R.Xq*zb; Xqp_n=R.Xqp*zb; Xqpp_n=R.Xqpp*zb;
  Xl_n=R.Xl*zb; Ra_n=R.Ra*zb;
  Vd=sin(delta)*real(Vt)-cos(delta)*imag(Vt);
  Vq=cos(delta)*real(Vt)+sin(delta)*imag(Vt);
  Eqpp = gamma.d1*Eqp + (1-gamma.d1)*Psipd;
  Edpp = gamma.q1*Edp + (1-gamma.q1)*Psipq;
  rhs_d = Vd - Edpp; rhs_q = Vq - Eqpp;
  det = Xdpp_n*Xqpp_n + Ra_n*Ra_n;
  Id = (-Ra_n*rhs_d - Xqpp_n*rhs_q)/det;
  Iq = ( Xdpp_n*rhs_d - Ra_n*rhs_q)/det;
  Te = Vq*Iq + Vd*Id + Ra_n*(Id^2+Iq^2);
  H = init.H_sys(k); D = M.units(k).D*(zb);
  f((k-1)*6+1)=omega_dev*w0;
  f((k-1)*6+2)=(Tm(k)-Te-D*omega_dev)/(2*H);
  % FIXED: pure ANDES/Sauer-Pai damper-flux realization (states = psi_1d, psi_2q).
  % e1q: T'd0 de1q/dt = vf - e1q - (Xd-X'd)*Id + Se*psi2d   (psi2d=Eqpp)
  % e1d: T'q0 de1d/dt = -e1d + (Xq-X'q)*Iq + Se*gqd*psi2q  (psi2q=Edpp)
  % e2d: T''d0 de2d/dt = e1q - e2d - (X'd-Xl)*Id
  % e2q: T''q0 de2q/dt = e1d - e2q + (X'q-Xl)*Iq
  f((k-1)*6+3)=(Efd(k) - Eqp - (Xd_n-Xdp_n)*Id)/TC.Tpd0;
  f((k-1)*6+4)=(-Edp + (Xq_n-Xqp_n)*Iq)/TC.Tpq0;
  f((k-1)*6+5)=(Eqp - Psipd - (Xdp_n-Xl_n)*Id)/TC.Tppd0;
  f((k-1)*6+6)=(Edp - Psipq + (Xqp_n-Xl_n)*Iq)/TC.Tppq0;
end
end

function g = dae_g_orig(x, y, init, M, Ynet, base, gamma, zb)
R=M.reactances; ng=init.ng; nb=numel(y)/2;
V_bus=complex(zeros(nb,1),zeros(nb,1));
for b=1:nb; V_bus(b)=complex(y(2*b-1),y(2*b)); end
Inet = Ynet * V_bus;
g = zeros(2*nb,1);
for b=1:nb; g(2*b-1)=-real(Inet(b)); g(2*b)=-imag(Inet(b)); end
case_data = cases.case_kundur_two_area_classical();
BD = case_data.bus_data;
load_model = 'cc_p_cz_q';
for b = 1:nb
  Pload = BD(b,7); Qload = BD(b,8);
  if Pload ~= 0 || Qload ~= 0
    Vt = V_bus(b); Vop = abs(complex(init.y0(2*b-1), init.y0(2*b)));
    switch load_model
      case {'cz','cz_p_cz_q'}
      case {'cp','cp_p_cp_q','cp_p_cz_q'}
        if abs(Vt) <= eps; Iload = 0; else; Iload = conj((Pload + 1i*Qload) / Vt); end
        g(2*b-1) = g(2*b-1) - real(Iload); g(2*b) = g(2*b) - imag(Iload);
      case {'cc','cc_p_cc_q'}
        if abs(Vt) <= eps || Vop <= eps; Iload = 0; else; Iload = ((Pload + 1i*Qload) / Vop) * (Vt / abs(Vt)); end
        g(2*b-1) = g(2*b-1) - real(Iload); g(2*b) = g(2*b) - imag(Iload);
      otherwise
        if abs(Vt) <= eps || Vop <= eps; Iload_p = 0; else; Iload_p = (Pload / Vop) * (Vt / abs(Vt)); end
        g(2*b-1) = g(2*b-1) - real(Iload_p); g(2*b) = g(2*b) - imag(Iload_p);
    end
  end
end
for k=1:ng
  bidx=init.bus_idx(k); Vt=V_bus(bidx); delta=x((k-1)*6+1);
  Eqp=x((k-1)*6+3); Edp=x((k-1)*6+4); Psipd=x((k-1)*6+5); Psipq=x((k-1)*6+6);
  Xdpp_n=R.Xdpp*zb; Xqpp_n=R.Xqpp*zb; Ra_n=R.Ra*zb;
  Vd=sin(delta)*real(Vt)-cos(delta)*imag(Vt); Vq=cos(delta)*real(Vt)+sin(delta)*imag(Vt);
  Eqpp=gamma.d1*Eqp+(1-gamma.d1)*Psipd; Edpp=gamma.q1*Edp+(1-gamma.q1)*Psipq;
  rhs_d=Vd-Edpp; rhs_q=Vq-Eqpp; det=Xdpp_n*Xqpp_n+Ra_n*Ra_n;
  Id=(-Ra_n*rhs_d-Xqpp_n*rhs_q)/det; Iq=(Xdpp_n*rhs_d-Ra_n*rhs_q)/det;
  Ire=sin(delta)*Id+cos(delta)*Iq; Iim=-cos(delta)*Id+sin(delta)*Iq;
  Ig=complex(Ire,Iim);
  g(2*bidx-1)=real(Ig)-real(Inet(bidx)); g(2*bidx)=imag(Ig)-imag(Inet(bidx));
end
end
