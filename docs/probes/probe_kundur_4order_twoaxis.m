function probe_kundur_4order_twoaxis()
%PROBE_KUNDUR_4ORDER_TWOAXIS Test two-axis transient 4th-order model for Kundur E12.3.
pf_init_paths;
case_data=cases.case_kundur_two_area_classical();
pf=pfsolver.powerflow_newton_raphson(case_data,struct('plot_results',false,'verbose',false,'max_iter',50,'tolerance',1e-8,'enforce_q_limits',false));
M=case_data.machines; R=M.reactances; TC=M.time_constants; base=case_data.base_values; Sm=M.base.S_MVA; Sbase=base.S_base_MVA; zb=Sbase/Sm;
r0=stability.kundur_ex126_kundur_ssa('pf',pf,'options',struct('load_model','cc_p_cz_q','use_saturation',false));
init=r0.init; Ynet=r0.Ynet; ng=init.ng; nb=numel(init.y0)/2;
x0=zeros(4*ng,1); y0=init.y0; Efd0=zeros(ng,1); Tm0=zeros(ng,1);
Xd=R.Xd*zb; Xdp=R.Xdp*zb; Xq=R.Xq*zb; Xqp=R.Xqp*zb; Ra=R.Ra*zb;
for k=1:ng
    delta=init.x0((k-1)*6+1); Id=init.Id(k); Iq=init.Iq(k); Vd=init.Vd(k); Vq=init.Vq(k);
    Eqp=Vq+Ra*Iq+Xdp*Id; Edp=Vd+Ra*Id-Xqp*Iq;
    Efd=Eqp+(Xd-Xdp)*Id; Tm=Vq*Iq+Vd*Id+Ra*(Id^2+Iq^2);
    x0((k-1)*4+1)=delta; x0((k-1)*4+2)=0; x0((k-1)*4+3)=Eqp; x0((k-1)*4+4)=Edp;
    Efd0(k)=Efd; Tm0(k)=Tm;
end
fixed_x=1; free_x=setdiff(1:numel(x0),fixed_x); fixed_y=2; free_y=setdiff(1:numel(y0),fixed_y);
z0=[x0(free_x);y0(free_y);Efd0;Tm0]; resfun=@(z)residual(z,free_x,free_y,ng,x0,y0,init,M,Ynet,base,zb);
opts=optimoptions('fsolve','Display','off','FunctionTolerance',1e-12,'StepTolerance',1e-14,'MaxIterations',500,'MaxFunctionEvaluations',5000);
[zsol,~,ef,out]=fsolve(resfun,z0,opts); fprintf('fsolve ef=%d res=%.3e it=%d\n',ef,norm(resfun(zsol)),out.iterations);
x=x0; y=y0; nx=numel(x0); ny=numel(y0); x(free_x)=zsol(1:numel(free_x)); y(free_y)=zsol(numel(free_x)+1:numel(free_x)+numel(free_y));
Efd=zsol(numel(free_x)+numel(free_y)+1:numel(free_x)+numel(free_y)+ng); Tm=zsol(numel(free_x)+numel(free_y)+ng+1:end);
epsp=1e-6; Jxx=zeros(nx,nx); Jxy=zeros(nx,ny); Jyx=zeros(ny,nx); Jyy=zeros(ny,ny);
for i=1:nx; xp=x; xm=x; xp(i)=xp(i)+epsp; xm(i)=xm(i)-epsp; Jxx(:,i)=(dae_f(xp,y,Efd,Tm,init,M,base,zb)-dae_f(xm,y,Efd,Tm,init,M,base,zb))/(2*epsp); Jyx(:,i)=(dae_g(xp,y,init,M,Ynet,base,zb)-dae_g(xm,y,init,M,Ynet,base,zb))/(2*epsp); end
for j=1:ny; yp=y; ym=y; yp(j)=yp(j)+epsp; ym(j)=ym(j)-epsp; Jxy(:,j)=(dae_f(x,yp,Efd,Tm,init,M,base,zb)-dae_f(x,ym,Efd,Tm,init,M,base,zb))/(2*epsp); Jyy(:,j)=(dae_g(x,yp,init,M,Ynet,base,zb)-dae_g(x,ym,init,M,Ynet,base,zb))/(2*epsp); end
lam=eig(Jxx-Jxy*(Jyy\Jyx)); osc=lam(abs(imag(lam))>0.1 & real(lam)<0 & imag(lam)>0); [~,idx]=sort(abs(imag(osc))); osc=osc(idx);
for k=1:min(3,numel(osc)); z=-real(osc(k))/abs(osc(k)); fprintf('mode%d %.6f+j%.6f f=%.4f z=%.4f\n',k,real(osc(k)),imag(osc(k)),imag(osc(k))/(2*pi),z); end
fprintf('target -0.111+j3.43 .032; -0.492+j6.82 .072; -0.506+j7.02 .072\n');
end
function res=residual(z,fx,fy,ng,x0,y0,init,M,Ynet,base,zb)
nx=numel(fx); ny=numel(fy); x=x0; y=y0; x(fx)=z(1:nx); y(fy)=z(nx+1:nx+ny); Efd=z(nx+ny+1:nx+ny+ng); Tm=z(nx+ny+ng+1:end); res=[dae_f(x,y,Efd,Tm,init,M,base,zb); dae_g(x,y,init,M,Ynet,base,zb)]; end
function f=dae_f(x,y,Efd,Tm,init,M,base,zb)
R=M.reactances; TC=M.time_constants; ng=init.ng; w0=init.w0; nb=numel(y)/2; V=complex(y(1:2:end),y(2:2:end)); Xd=R.Xd*zb; Xdp=R.Xdp*zb; Xq=R.Xq*zb; Xqp=R.Xqp*zb; Ra=R.Ra*zb; f=zeros(4*ng,1);
for k=1:ng; b=init.bus_idx(k); Vt=V(b); d=x((k-1)*4+1); w=x((k-1)*4+2); Eqp=x((k-1)*4+3); Edp=x((k-1)*4+4); Vd=sin(d)*real(Vt)-cos(d)*imag(Vt); Vq=cos(d)*real(Vt)+sin(d)*imag(Vt); rhs_d=Vd-Edp; rhs_q=Vq-Eqp; det=Xdp*Xqp+Ra^2; Id=(-Ra*rhs_d-Xqp*rhs_q)/det; Iq=(Xdp*rhs_d-Ra*rhs_q)/det; Te=Vq*Iq+Vd*Id+Ra*(Id^2+Iq^2); H=init.H_sys(k); D=M.units(k).D*zb; f((k-1)*4+1)=w0*w; f((k-1)*4+2)=(Tm(k)-Te-D*w)/(2*H); f((k-1)*4+3)=(Efd(k)-Eqp-(Xd-Xdp)*Id)/TC.Tpd0; f((k-1)*4+4)=(-Edp+(Xq-Xqp)*Iq)/TC.Tpq0; end
end
function g=dae_g(x,y,init,M,Ynet,base,zb)
R=M.reactances; ng=init.ng; nb=numel(y)/2; V=complex(y(1:2:end),y(2:2:end)); Inet=Ynet*V; g=zeros(2*nb,1); for b=1:nb; g(2*b-1)=-real(Inet(b)); g(2*b)=-imag(Inet(b)); end; BD=cases.case_kundur_two_area_classical().bus_data; for b=1:nb; P=BD(b,7); if P~=0; Vop=abs(complex(init.y0(2*b-1),init.y0(2*b))); if abs(V(b))>eps&&Vop>eps; I=(P/Vop)*(V(b)/abs(V(b))); g(2*b-1)=g(2*b-1)-real(I); g(2*b)=g(2*b)-imag(I); end; end; end; Xdp=R.Xdp*zb; Xqp=R.Xqp*zb; Ra=R.Ra*zb; for k=1:ng; bi=init.bus_idx(k); Vt=V(bi); d=x((k-1)*4+1); Eqp=x((k-1)*4+3); Edp=x((k-1)*4+4); Vd=sin(d)*real(Vt)-cos(d)*imag(Vt); Vq=cos(d)*real(Vt)+sin(d)*imag(Vt); rhs_d=Vd-Edp; rhs_q=Vq-Eqp; det=Xdp*Xqp+Ra^2; Id=(-Ra*rhs_d-Xqp*rhs_q)/det; Iq=(Xdp*rhs_d-Ra*rhs_q)/det; Ig=complex(sin(d)*Id+cos(d)*Iq,-cos(d)*Id+sin(d)*Iq); g(2*bi-1)=real(Ig)-real(Inet(bi)); g(2*bi)=imag(Ig)-imag(Inet(bi)); end
end
