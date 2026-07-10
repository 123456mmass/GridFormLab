function probe_gy()
%PROBE_GY Check conditioning of the network Jacobian g_y.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results', false, 'verbose', false, 'max_iter', 50, ...
    'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
opts = struct('load_model','cc_p_cz_q');
ssa = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', opts);
init = ssa.init;
M = case_data.machines; base = case_data.base_values;
R = M.reactances;
g_d1 = (R.Xdpp - R.Xl)/(R.Xdp - R.Xl);
g_q1 = (R.Xqpp - R.Xl)/(R.Xqp - R.Xl);
g_d2 = (1-g_d1)/(R.Xdp - R.Xl);
g_q2 = (1-g_q1)/(R.Xqp - R.Xl);
gamma = struct('d1',g_d1,'q1',g_q1,'d2',g_d2,'q2',g_q2);
% Rebuild Ynet via the internal build function is not accessible; use ssa.
% Instead, recompute Jacobians by finite difference on dae_g/dae_f.  But those
% are private.  Use the public Afull and the fact that Afull = Jxx - Jxy*Jyy\Jyx.
% We can recover Jyy conditioning by rebuilding it from dae_g finite diff.
% Since dae_g is private, approximate: build Ynet ourselves.
Ynet = build_y(pf, case_data, opts);
zb = init.zb_scale;
ny = numel(init.y0); nx = numel(init.x0);
Jyy = zeros(ny,ny); Jyx = zeros(ny,nx);
eps_p = 1e-6;
for j = 1:ny
    yp = init.y0; yp(j)=yp(j)+eps_p; ym = init.y0; ym(j)=ym(j)-eps_p;
    gp = dae_g_pub(init.x0, yp, init, M, Ynet, base, gamma, zb, case_data);
    gm = dae_g_pub(init.x0, ym, init, M, Ynet, base, gamma, zb, case_data);
    Jyy(:,j) = (gp-gm)/(2*eps_p);
end
for i = 1:nx
    xp = init.x0; xp(i)=xp(i)+eps_p; xm = init.x0; xm(i)=xm(i)-eps_p;
    gp = dae_g_pub(xp, init.y0, init, M, Ynet, base, gamma, zb, case_data);
    gm = dae_g_pub(xm, init.y0, init, M, Ynet, base, gamma, zb, case_data);
    Jyx(:,i) = (gp-gm)/(2*eps_p);
end
fprintf('Jyy size %dx%d, cond(Jyy) = %.4e, rcond = %.4e\n', size(Jyy,1), size(Jyy,2), cond(Jyy), rcond(Jyy));
fprintf('Eigenvalues of Jyy (smallest magnitude):\n');
ev = eig(Jyy); [~,idx]=sort(abs(ev));
for k=1:6; fprintf('  %12.4e %+12.4e i\n', real(ev(idx(k))), imag(ev(idx(k)))); end
end

function g = dae_g_pub(x, y, init, M, Ynet, base, gamma, zb, case_data)
%Replicate dae_g (must match the private function exactly).
R=M.reactances; ng=init.ng; nb=numel(y)/2;
V_bus=complex(zeros(nb,1),zeros(nb,1));
for b=1:nb; V_bus(b)=complex(y(2*b-1),y(2*b)); end
Inet = Ynet * V_bus;
g = zeros(2*nb,1);
for b=1:nb; g(2*b-1)=-real(Inet(b)); g(2*b)=imag(Inet(b)); end
BD = case_data.bus_data;
for b = 1:nb
    Pload = BD(b,7); Qload = BD(b,8);
    if Pload ~= 0
        Vt = V_bus(b); Vop = abs(complex(init.y0(2*b-1), init.y0(2*b)));
        if abs(Vt) <= eps || Vop <= eps; Iload_p = 0;
        else; Iload_p = (Pload / Vop) * (Vt / abs(Vt)); end
        g(2*b-1) = g(2*b-1) - real(Iload_p);
        g(2*b)   = g(2*b)   - imag(Iload_p);
    end
end
for k=1:ng
    bidx=init.bus_idx(k); Vt=V_bus(bidx);
    delta=x((k-1)*6+1); Eqp=x((k-1)*6+3); Edp=x((k-1)*6+4);
    Psipd=x((k-1)*6+5); Psipq=x((k-1)*6+6);
    Xdpp_n=R.Xdpp*zb; Xqpp_n=R.Xqpp*zb; Ra_n=R.Ra*zb;
    Vd=sin(delta)*real(Vt)-cos(delta)*imag(Vt);
    Vq=cos(delta)*real(Vt)+sin(delta)*imag(Vt);
    Eqpp=gamma.d1*Eqp+(1-gamma.d1)*Psipd;
    Edpp=gamma.q1*Edp+(1-gamma.q1)*Psipq;
    rhs_d=Vd-Edpp; rhs_q=Vq-Eqpp;
    det=Xdpp_n*Xqpp_n+Ra_n*Ra_n;
    Id=(-Ra_n*rhs_d-Xqpp_n*rhs_q)/det;
    Iq=(Xdpp_n*rhs_d-Ra_n*rhs_q)/det;
    Ire=sin(delta)*Id+cos(delta)*Iq;
    Iim=-cos(delta)*Id+sin(delta)*Iq;
    Ig=complex(Ire,Iim);
    g(2*bidx-1)=real(Ig)-real(Inet(bidx));
    g(2*bidx)=imag(Ig)-imag(Inet(bidx));
end
end

function Ynet = build_y(pf, case_data, opts)
nb = numel(pf.external_bus_ids);
Y = complex(zeros(nb), zeros(nb));
LD = case_data.line_data;
for l = 1:size(LD,1)
    f = find(pf.external_bus_ids == LD(l,1), 1);
    t = find(pf.external_bus_ids == LD(l,2), 1);
    z = complex(LD(l,3), LD(l,4)); y = 1/z;
    Y(f,f)=Y(f,f)+y+1i*LD(l,5); Y(t,t)=Y(t,t)+y+1i*LD(l,5);
    Y(f,t)=Y(f,t)-y; Y(t,f)=Y(t,f)-y;
end
BD = case_data.bus_data;
for k = 1:size(BD,1)
    b = find(pf.external_bus_ids == BD(k,1), 1);
    Y(b,b) = Y(b,b) + 1i*BD(k,10);
    Qload=BD(k,8); Vmag=pf.bus_voltage(b);
    if Vmag>0 && Qload~=0; Y(b,b) = Y(b,b) - 1i*Qload/(Vmag^2); end
end
Ynet = Y;
end
