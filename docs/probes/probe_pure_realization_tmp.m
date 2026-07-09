function probe_pure_realization_tmp()
%PROBE_PURE_REALIZATION Test the pure ANDES/Sauer-Pai damper-flux realization
%(states psi_1d, psi_2q; f3/f4 use REAL Id, Iq) with a robust fsolve refine.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results',false,'verbose',false,'max_iter',50,'tolerance',1e-8,'enforce_q_limits',false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
opts0 = struct('load_model','cc_p_cz_q','use_saturation',false);
r = stability.kundur_ex126_kundur_ssa('pf',pf,'options',opts0);
fprintf('=== Current (mixed realization) ===\n');
print_modes(r.eigenvalues);

M = case_data.machines; R = M.reactances; base = case_data.base_values;
Sm = M.base.S_MVA; Sbase = base.S_base_MVA; zb = Sbase/Sm;
gamma = struct('d1',(R.Xdpp-R.Xl)/(R.Xdp-R.Xl),'q1',(R.Xqpp-R.Xl)/(R.Xqp-R.Xl));
init = r.init; Ynet = r.Ynet; ng = init.ng;

g_func = @(z) dae_g_orig(z(2*ng+1:end), z(1:2*ng), init, M, Ynet, base, gamma, zb);
% State vector z = [Efd(ng); Tm(ng); x(nx); y(ny)]
Efd0 = init.Efd; Tm0 = init.Tm; x0 = init.x0; y0 = init.y0;
f_param = @(xx,yy,ee,tt) dae_f_pure(xx,yy,ee,tt,init,M,base,gamma,zb);

% Residual function for fsolve: unknowns = [x(free); y(free); Efd; Tm]
fixed_x = 1; free_x = setdiff(1:numel(x0), fixed_x);
fixed_y = 2; free_y = setdiff(1:numel(y0), fixed_y);
z0 = [x0(free_x); y0(free_y); Efd0; Tm0];
resfun = @(z) residual(z, free_x, free_y, ng, x0, y0, init, M, Ynet, base, gamma, zb);
fprintf('\nfsolve refining (pure realization)...\n');
opts = optimoptions('fsolve','Display','iter','FunctionTolerance',1e-12,...
  'StepTolerance',1e-14,'MaxIterations',500,'MaxFunctionEvaluations',3000);
[zsol,~,exitflag,output] = fsolve(resfun, z0, opts);
fprintf('fsolve exitflag=%d, residual=%.3e, iters=%d\n', exitflag, norm(resfun(zsol)), output.iterations);

% Reassemble
xsol = x0; xsol(free_x) = zsol(1:numel(free_x));
ysol = y0; ysol(free_y) = zsol(numel(free_x)+1:numel(free_x)+numel(free_y));
Efdsol = zsol(numel(free_x)+numel(free_y)+1:numel(free_x)+numel(free_y)+ng);
Tmsol = zsol(numel(free_x)+numel(free_y)+ng+1:end);
init.x0 = xsol; init.y0 = ysol; init.Efd = Efdsol; init.Tm = Tmsol;

% Build Jacobian with pure equations
nx = numel(xsol); ny = numel(ysol); eps_p = 1e-6;
Jxx = zeros(nx,nx); Jxy = zeros(nx,ny); Jyx = zeros(ny,nx); Jyy = zeros(ny,ny);
for i = 1:nx
  xp=xsol; xp(i)=xp(i)+eps_p; xm=xsol; xm(i)=xm(i)-eps_p;
  Jxx(:,i) = (f_param(xp,ysol,Efdsol,Tmsol)-f_param(xm,ysol,Efdsol,Tmsol))/(2*eps_p);
  Jyx(:,i) = (dae_g_orig(xp,ysol,init,M,Ynet,base,gamma,zb)-dae_g_orig(xm,ysol,init,M,Ynet,base,gamma,zb))/(2*eps_p);
end
for j = 1:ny
  yp=ysol; yp(j)=yp(j)+eps_p; ym=ysol; ym(j)=ym(j)-eps_p;
  Jxy(:,j) = (f_param(xsol,yp,Efdsol,Tmsol)-f_param(xsol,ym,Efdsol,Tmsol))/(2*eps_p);
  Jyy(:,j) = (dae_g_orig(xsol,yp,init,M,Ynet,base,gamma,zb)-dae_g_orig(xsol,ym,init,M,Ynet,base,gamma,zb))/(2*eps_p);
end
Ared = Jxx - Jxy*(Jyy\Jyx);
fprintf('\n=== Pure ANDES/Sauer-Pai realization (real Id in f3/f4) === ALL 24 ===\n');
lam=sort(eig(Ared));
fprintf('  %4s %14s %14s %10s %8s\n','No','Re','Im','f(Hz)','zeta');
for k=1:numel(lam); f=abs(imag(lam(k)))/(2*pi); z=-real(lam(k))/(abs(lam(k))+1e-12);
  fprintf('  %4d %+14.6f %+14.6f %10.4f %8.4f\n',k,real(lam(k)),imag(lam(k)),f,z); end
fprintf('\nKundur E12.3: IA -0.111+/-3.43(0.545,0.032); L1 -0.492+/-6.82(1.087,0.072); L2 -0.506+/-7.02(1.117,0.072)\n');
fprintf('              field -0.265,-0.276; q-damp -3.43,-4.14,-5.29,-5.30; d-damp -31..-38\n');
end

function res = residual(z, free_x, free_y, ng, x0, y0, init, M, Ynet, base, gamma, zb)
nxr = numel(free_x); nyr = numel(free_y);
x = x0; x(free_x) = z(1:nxr);
y = y0; y(free_y) = z(nxr+1:nxr+nyr);
Efd = z(nxr+nyr+1:nxr+nyr+ng);
Tm = z(nxr+nyr+ng+1:end);
f = dae_f_pure(x,y,Efd,Tm,init,M,base,gamma,zb);
g = dae_g_orig(x,y,init,M,Ynet,base,gamma,zb);
res = [f; g];
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

% Pure ANDES realization: f3/f4 use REAL Id, Iq (no Id_eff).
function f = dae_f_pure(x, y, Efd, Tm, init, M, base, gamma, zb)
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
  H = init.H_sys(k); D = M.units(k).D*zb;
  f((k-1)*6+1)=omega_dev*w0;
  f((k-1)*6+2)=(Tm(k)-Te-D*omega_dev)/(2*H);
% PURE Sauer-Pai 3.151/3.153 with the CORRECT Id_eff/Iq_eff.
%  Id_eff = Id - A_d*(psi_1d + (X'd-Xl)*Id - E'q),  A_d=(X'd-Xl)^2/(Xd-X'd)
%  Iq_eff = Iq - A_q*(psi_2q + (X'q-Xl)*Iq + E'd),  A_q=(X'q-Xl)^2/(Xq-X'q)
% Note: this is Sauer-Pai MOTOR convention form (3.151/3.153 text). The damper
% coupling sign matches the generator-convention stator eqs used here.
A_d = (Xdp_n-Xl_n)^2/(Xd_n-Xdp_n);
A_q = (Xqp_n-Xl_n)^2/(Xq_n-Xqp_n);
Id_eff = Id - A_d*(Psipd + (Xdp_n-Xl_n)*Id - Eqp);
Iq_eff = Iq - A_q*(Psipq + (Xqp_n-Xl_n)*Iq + Edp);
f((k-1)*6+3)=(Efd(k) - Eqp - (Xd_n-Xdp_n)*Id_eff)/TC.Tpd0;
f((k-1)*6+4)=(-Edp + (Xq_n-Xqp_n)*Iq_eff)/TC.Tpq0;
% Damper flux (ANDES e2d, e2q - matches code original f5/f6)
f((k-1)*6+5)=(-Psipd + Eqp - (Xdp_n-Xl_n)*Id)/TC.Tppd0;
f((k-1)*6+6)=(-Psipq + Edp + (Xqp_n-Xl_n)*Iq)/TC.Tppq0;
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
for b = 1:nb
  Pload = BD(b,7); Qload = BD(b,8);
  if Pload ~= 0 || Qload ~= 0
    Vt = V_bus(b); Vop = abs(complex(init.y0(2*b-1), init.y0(2*b)));
    if abs(Vt) <= eps || Vop <= eps; Iload_p = 0; else; Iload_p = (Pload / Vop) * (Vt / abs(Vt)); end
    g(2*b-1) = g(2*b-1) - real(Iload_p); g(2*b) = g(2*b) - imag(Iload_p);
    % Q is constant impedance (already in Ynet)
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
