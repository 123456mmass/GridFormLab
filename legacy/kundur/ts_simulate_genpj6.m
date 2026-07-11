function result = ts_simulate_genpj6(case_data, opt)
%TS_SIMULATE_GENPJ6 6th-order GENTPJ transient simulation (general engine path).
%   Called by stability.ts_simulate when opt.model = 'genpj6'. Reuses the
%   validated Kundur 6th-order DAE (genpj6_dae) so the same engine entry
%   point runs both classical and 6th-order models.
%
%   opt fields: t_end, dt, fault_bus, t_fault, t_clear, Zf (empty => solid
%   fault), method ('trapezoidal'|'implicit'), corrector_iter, verbose.

dae = stability.genpj6_dae(case_data, opt);
init = dae.init; M = dae.M; base = dae.base; zb_scale = dae.zb_scale;
ng = dae.ng; nb = dae.nb; bus_ids = dae.bus_ids;
dae_f = dae.dae_f; dae_g = dae.dae_g;

tmp_init = init; tmp_init.opts.load_model = dae.load_model;

bus_fault = opt.fault_bus;
if isempty(bus_fault), bus_fault = bus_ids(1); end
tclear = opt.t_clear - opt.t_fault;
tfault_start = opt.t_fault;
dt = opt.dt; tmax = opt.t_end;
method = opt.method; corrector_iter = opt.corrector_iter;
solid_fault = isempty(opt.Zf);

Ypre = dae.Ynet;
Yfault = Ypre;
b_fault = find(bus_ids == bus_fault, 1);
if solid_fault
    Yfault(b_fault,:) = 0; Yfault(:,b_fault) = 0; Yfault(b_fault,b_fault) = 1;
else
    Yfault(b_fault,b_fault) = Yfault(b_fault,b_fault) + 1/opt.Zf;
end
Ypost = Ypre;

x = init.x0(:); y = init.y0(:);
t_vec = 0:dt:tmax; Nt = numel(t_vec);
delta_hist = zeros(Nt,ng); omega_hist = zeros(Nt,ng); Pe_hist = zeros(Nt,ng); Vbus_hist = zeros(Nt,nb);

newton_tol = 1e-8; nx = numel(x); ny = numel(y);
[Jxx,Jxy,Jyx,Jyy] = compute_jac_fd(x,y,tmp_init,M,Ypre,base,zb_scale,dae_f,dae_g);
Jyy_inv_Jyx = Jyy \ Jyx;
J_trap = eye(nx) - 0.5*dt*(Jxx + Jxy*(-Jyy_inv_Jyx));
Ynet = Ypre;

for it = 1:Nt
    t = t_vec(it);
    if t < tfault_start, Ynet = Ypre;
    elseif t < tfault_start + tclear, Ynet = Yfault;
    else, Ynet = Ypost; end
    if it==1 || it==round(tfault_start/dt)+1 || it==round((tfault_start+tclear)/dt)+1 || mod(it,5)==0
        [Jxx,Jxy,Jyx,Jyy] = compute_jac_fd(x,y,tmp_init,M,Ynet,base,zb_scale,dae_f,dae_g);
        Jyy_inv_Jyx = Jyy \ Jyx;
        J_trap = eye(nx) - 0.5*dt*(Jxx + Jxy*(-Jyy_inv_Jyx));
    end
    for k=1:ng
        ix=(k-1)*6+1; delta_hist(it,k)=x(ix); omega_hist(it,k)=x(ix+1);
    end
    Pe_hist(it,:) = compute_pe_6th(x,y,init,M,base,zb_scale,ng).';
    Vbus = abs(complex(y(1:2:end),y(2:2:end))); Vbus_hist(it,:)=Vbus.';

    if it < Nt
        y = solve_g(x,y,tmp_init,M,Ynet,base,zb_scale,dae_g,Jyy);
        fn = dae_f(x,y,tmp_init,M,Ynet,base,[]);
        switch lower(method)
            case {'trapezoidal','heun','predictor-corrector','predictor_corrector'}
                x_next = x + dt*fn; y_next = y;
                for cit=1:max(1,corrector_iter)
                    y_next = solve_g(x_next,y_next,tmp_init,M,Ynet,base,zb_scale,dae_g,Jyy);
                    fn_next = dae_f(x_next,y_next,tmp_init,M,Ynet,base,[]);
                    x_next = x + 0.5*dt*(fn+fn_next);
                end
                x = x_next; y = solve_g(x,y_next,tmp_init,M,Ynet,base,zb_scale,dae_g,Jyy);
            case {'implicit','implicit_trapezoidal'}
                x_next = x + dt*fn;
                for nit=1:15
                    y_next = solve_g(x_next,y,tmp_init,M,Ynet,base,zb_scale,dae_g,Jyy);
                    fn_next = dae_f(x_next,y_next,tmp_init,M,Ynet,base,[]);
                    R = x_next - x - 0.5*dt*(fn+fn_next);
                    if norm(R,inf)<newton_tol || nit==15, break; end
                    x_next = x_next + J_trap\(-R);
                end
                x = x_next; y = solve_g(x,y_next,tmp_init,M,Ynet,base,zb_scale,dae_g,Jyy);
            otherwise
                error('ts_simulate_genpj6:unknownMethod','Unknown method "%s".',method);
        end
    end
end

result = struct();
result.t = t_vec; result.delta = delta_hist; result.omega = omega_hist;
result.Pgen = Pe_hist*100; result.Pe_pu = Pe_hist; result.Vbus = Vbus_hist;
result.bus_ids = bus_ids; result.gen_buses = bus_ids(1:ng);
result.fault_bus = bus_fault; result.t_fault = opt.t_fault; result.t_clear = opt.t_clear;
result.Zf = opt.Zf; result.dt = dt; result.t_end = tmax; result.method = method;
result.model = '6th-order GENTPJ full nonlinear';
result.H_machine = [M.units(1).H; M.units(2).H; M.units(3).H; M.units(4).H];
result.H_sys = init.H_sys;
result.Pm = init.Tm;
result.integration_method = sprintf('%s predictor-corrector/Heun (corrector_iter=%d)',method,corrector_iter);
end

function [Jxx,Jxy,Jyx,Jyy] = compute_jac_fd(x,y,init,M,Ynet,base,zb_scale,dae_f,dae_g)
nx=numel(x); ny=numel(y); eps_j=1e-6;
f0=dae_f(x,y,init,M,Ynet,base,[]); g0=dae_g(x,y,init,M,Ynet,base,[],zb_scale);
Jxx=zeros(nx,nx); for j=1:nx, xp=x; xp(j)=xp(j)+eps_j; Jxx(:,j)=(dae_f(xp,y,init,M,Ynet,base,[])-f0)/eps_j; end
Jxy=zeros(nx,ny); for j=1:ny, yp=y; yp(j)=yp(j)+eps_j; Jxy(:,j)=(dae_f(x,yp,init,M,Ynet,base,[])-f0)/eps_j; end
Jyx=zeros(ny,nx); for j=1:nx, xp=x; xp(j)=xp(j)+eps_j; Jyx(:,j)=(dae_g(xp,y,init,M,Ynet,base,[],zb_scale)-g0)/eps_j; end
Jyy=zeros(ny,ny); for j=1:ny, yp=y; yp(j)=yp(j)+eps_j; Jyy(:,j)=(dae_g(x,yp,init,M,Ynet,base,[],zb_scale)-g0)/eps_j; end
end

function y_out = solve_g(x,y0,init,M,Ynet,base,zb_scale,dae_g,Jyy)
y=y0(:);
for nit=1:20
    g_cur=dae_g(x,y,init,M,Ynet,base,[],zb_scale);
    if norm(g_cur,inf)<1e-8, break; end
    y=y+Jyy\(-g_cur);
end
y_out=y;
end

function Pe = compute_pe_6th(x,y,init,M,base,zb_scale,ng)
R=M.reactances; Ra_n=R.Ra*zb_scale; Xdpp_n=R.Xdpp*zb_scale; Xqpp_n=R.Xqpp*zb_scale;
Pe=zeros(ng,1);
for k=1:ng
    ix=(k-1)*6+1; delta=x(ix); Eqpp=x(ix+4); Edpp=x(ix+5);
    bidx=init.bus_idx(k); Vt=complex(y(2*bidx-1),y(2*bidx));
    Vd=sin(delta)*real(Vt)-cos(delta)*imag(Vt);
    Vq=cos(delta)*real(Vt)+sin(delta)*imag(Vt);
    det_val=Xdpp_n*Xqpp_n+Ra_n*Ra_n;
    Id=(-Ra_n*(Vd-Edpp)-Xqpp_n*(Vq-Eqpp))/det_val;
    Iq=(Xdpp_n*(Vd-Edpp)-Ra_n*(Vq-Eqpp))/det_val;
    Pe(k)=Vd*Id+Vq*Iq+Ra_n*(Id^2+Iq^2);
end
end
