function probe_sauer_pai_exact()
%PROBE_SAUER_PAI_EXACT Exact Sauer-Pai/Kundur 6th-order damper-flux realization.
% States per machine: [delta, omega, E'q, E'd, psi_1d, psi_2q]
% OCR equations from Sauer-Pai (3.151)-(3.154):
%   T'd0  dE'q/dt   = Efd - E'q - (Xd-X'd) Id_eff
%   T'q0  dE'd/dt   = -E'd + (Xq-X'q) Iq_eff
%   T''d0 dpsi_1d/dt = -psi_1d + E'q - (X'd-Xl) Id
%   T''q0 dpsi_2q/dt = -psi_2q - E'd - (X'q-Xl) Iq
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results',false,'verbose',false,'max_iter',50,'tolerance',1e-8,'enforce_q_limits',false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
base = case_data.base_values; M = case_data.machines; R = M.reactances;
Sm = M.base.S_MVA; Sbase = base.S_base_MVA; zb = Sbase/Sm;
gamma = struct('d1',(R.Xdpp-R.Xl)/(R.Xdp-R.Xl), 'q1',(R.Xqpp-R.Xl)/(R.Xqp-R.Xl));

% Start from the current solved operating point and network/load model.
r0 = stability.kundur_ex126_kundur_ssa('pf',pf,'options',struct('load_model','cc_p_cz_q','use_saturation',false));
init = r0.init; Ynet = r0.Ynet; ng = init.ng;
x0 = init.x0; y0 = init.y0; Efd0 = init.Efd; Tm0 = init.Tm;

% Convert GENTPJ states [E''q,E''d] to Sauer-Pai damper-flux states.
for k = 1:ng
    Eqp  = x0((k-1)*6+3); Edp  = x0((k-1)*6+4);
    Eqpp = x0((k-1)*6+5); Edpp = x0((k-1)*6+6);
    x0((k-1)*6+5) = (Eqpp - gamma.d1*Eqp) / (1 - gamma.d1);       % psi_1d
    x0((k-1)*6+6) = (gamma.q1*Edp - Edpp) / (1 - gamma.q1);       % psi_2q, q-axis sign
end

fixed_x = 1; free_x = setdiff(1:numel(x0), fixed_x);
fixed_y = 2; free_y = setdiff(1:numel(y0), fixed_y);
z0 = [x0(free_x); y0(free_y); Efd0; Tm0];
resfun = @(z) residual(z, free_x, free_y, ng, x0, y0, init, M, Ynet, base, gamma, zb);
opts = optimoptions('fsolve','Display','off','FunctionTolerance',1e-12,'StepTolerance',1e-14, ...
    'MaxIterations',500,'MaxFunctionEvaluations',5000);
[zsol,~,exitflag,output] = fsolve(resfun, z0, opts);
resn = norm(resfun(zsol));
fprintf('fsolve exitflag=%d residual=%.3e iters=%d\n', exitflag, resn, output.iterations);

x = x0; x(free_x) = zsol(1:numel(free_x));
y = y0; y(free_y) = zsol(numel(free_x)+1:numel(free_x)+numel(free_y));
Efd = zsol(numel(free_x)+numel(free_y)+1:numel(free_x)+numel(free_y)+ng);
Tm  = zsol(numel(free_x)+numel(free_y)+ng+1:end);

nx = numel(x); ny = numel(y); eps_p = 1e-6;
Jxx=zeros(nx,nx); Jxy=zeros(nx,ny); Jyx=zeros(ny,nx); Jyy=zeros(ny,ny);
for i=1:nx
    xp=x; xm=x; xp(i)=xp(i)+eps_p; xm(i)=xm(i)-eps_p;
    Jxx(:,i)=(dae_f(xp,y,Efd,Tm,init,M,base,gamma,zb)-dae_f(xm,y,Efd,Tm,init,M,base,gamma,zb))/(2*eps_p);
    Jyx(:,i)=(dae_g(xp,y,init,M,Ynet,base,gamma,zb)-dae_g(xm,y,init,M,Ynet,base,gamma,zb))/(2*eps_p);
end
for j=1:ny
    yp=y; ym=y; yp(j)=yp(j)+eps_p; ym(j)=ym(j)-eps_p;
    Jxy(:,j)=(dae_f(x,yp,Efd,Tm,init,M,base,gamma,zb)-dae_f(x,ym,Efd,Tm,init,M,base,gamma,zb))/(2*eps_p);
    Jyy(:,j)=(dae_g(x,yp,init,M,Ynet,base,gamma,zb)-dae_g(x,ym,init,M,Ynet,base,gamma,zb))/(2*eps_p);
end
Ared = Jxx - Jxy*(Jyy\Jyx);
lam = eig(Ared);
print_modes(lam);
fprintf('\nAll electromechanical modes (upper half):\n');
osc = lam(abs(imag(lam))>0.1 & real(lam)<0 & imag(lam)>0);
[~,idx]=sort(abs(imag(osc))); osc=osc(idx);
for k=1:min(6,numel(osc))
    zeta = -real(osc(k))/abs(osc(k));
    fprintf('  %+.6f + j%.6f  f=%.4f Hz  zeta=%.4f\n', real(osc(k)), imag(osc(k)), imag(osc(k))/(2*pi), zeta);
end
fprintf('\nKundur target:\n  -0.111+j3.430 z=0.032\n  -0.492+j6.820 z=0.072\n  -0.506+j7.020 z=0.072\n');
end

function res = residual(z, free_x, free_y, ng, x0, y0, init, M, Ynet, base, gamma, zb)
nxr=numel(free_x); nyr=numel(free_y);
x=x0; y=y0;
x(free_x)=z(1:nxr);
y(free_y)=z(nxr+1:nxr+nyr);
Efd=z(nxr+nyr+1:nxr+nyr+ng);
Tm=z(nxr+nyr+ng+1:end);
res=[dae_f(x,y,Efd,Tm,init,M,base,gamma,zb); dae_g(x,y,init,M,Ynet,base,gamma,zb)];
end

function f = dae_f(x,y,Efd,Tm,init,M,base,gamma,zb)
w0=init.w0; R=M.reactances; TC=M.time_constants; ng=init.ng;
nb=numel(y)/2; f=zeros(6*ng,1);
V_bus=complex(zeros(nb,1),zeros(nb,1));
for b=1:nb; V_bus(b)=complex(y(2*b-1),y(2*b)); end
Xd=R.Xd*zb; Xdp=R.Xdp*zb; Xdpp=R.Xdpp*zb;
Xq=R.Xq*zb; Xqp=R.Xqp*zb; Xqpp=R.Xqpp*zb; Xl=R.Xl*zb; Ra=R.Ra*zb;
Kdamp_d = (Xdp-Xl)^2/(Xdp-Xdpp);
Kdamp_q = (Xqp-Xl)^2/(Xqp-Xqpp);
for k=1:ng
    bidx=init.bus_idx(k); Vt=V_bus(bidx);
    delta=x((k-1)*6+1); omega_dev=x((k-1)*6+2);
    Eqp=x((k-1)*6+3); Edp=x((k-1)*6+4); psid=x((k-1)*6+5); psiq=x((k-1)*6+6);
    Vd=sin(delta)*real(Vt)-cos(delta)*imag(Vt);
    Vq=cos(delta)*real(Vt)+sin(delta)*imag(Vt);
    Eqpp = gamma.d1*Eqp + (1-gamma.d1)*psid;
    Edpp = gamma.q1*Edp - (1-gamma.q1)*psiq;
    rhs_d=Vd-Edpp; rhs_q=Vq-Eqpp; det=Xdpp*Xqpp+Ra*Ra;
    Id=(-Ra*rhs_d-Xqpp*rhs_q)/det;
    Iq=( Xdpp*rhs_d-Ra*rhs_q)/det;
    Te=Vq*Iq+Vd*Id+Ra*(Id^2+Iq^2);
    H=init.H_sys(k); D=M.units(k).D*zb;
    br_d = psid + (Xdp-Xl)*Id - Eqp;
    br_q = psiq + (Xqp-Xl)*Iq + Edp;
    f((k-1)*6+1)=w0*omega_dev;
    f((k-1)*6+2)=(Tm(k)-Te-D*omega_dev)/(2*H);
    % Sauer-Pai (3.151), (3.153): coefficients after expanding
    % (X-X')*[I - ((X'-Xl)^2/((X-X')(X'-X'')))*bracket].
    f((k-1)*6+3)=(Efd(k)-Eqp-(Xd-Xdp)*Id + Kdamp_d*br_d)/TC.Tpd0;
    f((k-1)*6+4)=(-Edp+(Xq-Xqp)*Iq - Kdamp_q*br_q)/TC.Tpq0;
    f((k-1)*6+5)=(-psid+Eqp-(Xdp-Xl)*Id)/TC.Tppd0;
    f((k-1)*6+6)=(-psiq-Edp-(Xqp-Xl)*Iq)/TC.Tppq0;
end
end

function g = dae_g(x,y,init,M,Ynet,base,gamma,zb)
R=M.reactances; ng=init.ng; nb=numel(y)/2;
V_bus=complex(zeros(nb,1),zeros(nb,1));
for b=1:nb; V_bus(b)=complex(y(2*b-1),y(2*b)); end
Inet=Ynet*V_bus; g=zeros(2*nb,1);
for b=1:nb; g(2*b-1)=-real(Inet(b)); g(2*b)=-imag(Inet(b)); end
case_data=cases.case_kundur_two_area_classical(); BD=case_data.bus_data;
load_model='cc_p_cz_q';
for b=1:nb
    Pload=BD(b,7); Qload=BD(b,8);
    if Pload~=0 || Qload~=0
        Vt=V_bus(b); Vop=abs(complex(init.y0(2*b-1),init.y0(2*b)));
        if abs(Vt)>eps && Vop>eps
            Iload_p=(Pload/Vop)*(Vt/abs(Vt));
            g(2*b-1)=g(2*b-1)-real(Iload_p); g(2*b)=g(2*b)-imag(Iload_p);
        end
    end
end
Xdpp=R.Xdpp*zb; Xqpp=R.Xqpp*zb; Ra=R.Ra*zb;
for k=1:ng
    bidx=init.bus_idx(k); Vt=V_bus(bidx); delta=x((k-1)*6+1);
    Eqp=x((k-1)*6+3); Edp=x((k-1)*6+4); psid=x((k-1)*6+5); psiq=x((k-1)*6+6);
    Vd=sin(delta)*real(Vt)-cos(delta)*imag(Vt);
    Vq=cos(delta)*real(Vt)+sin(delta)*imag(Vt);
    Eqpp=gamma.d1*Eqp+(1-gamma.d1)*psid;
    Edpp=gamma.q1*Edp-(1-gamma.q1)*psiq;
    rhs_d=Vd-Edpp; rhs_q=Vq-Eqpp; det=Xdpp*Xqpp+Ra*Ra;
    Id=(-Ra*rhs_d-Xqpp*rhs_q)/det;
    Iq=( Xdpp*rhs_d-Ra*rhs_q)/det;
    Ire=sin(delta)*Id+cos(delta)*Iq; Iim=-cos(delta)*Id+sin(delta)*Iq;
    Ig=complex(Ire,Iim);
    g(2*bidx-1)=real(Ig)-real(Inet(bidx)); g(2*bidx)=imag(Ig)-imag(Inet(bidx));
end
end

function print_modes(lam)
osc=lam(abs(imag(lam))>0.1 & real(lam)<0 & imag(lam)>0);
[~,idx]=sort(abs(imag(osc))); osc=osc(idx);
labels={'IA','L1','L2'};
for k=1:min(3,numel(osc))
    z=-real(osc(k))/abs(osc(k));
    fprintf('%s: %+.6f + j%.6f  f=%.4f z=%.4f\n', labels{k}, real(osc(k)), imag(osc(k)), imag(osc(k))/(2*pi), z);
end
end
