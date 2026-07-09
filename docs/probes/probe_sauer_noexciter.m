function probe_sauer_noexciter()
% 4-state model (E'q, E'd, delta, omega) with constant Efd, power-balance.
ws=2*pi*60;
H=[23.64 6.40 3.01]; M=2*H/ws; D=[0 0 0];
Xd=[0.146 0.8958 1.3125]; Xdp=[0.0608 0.1198 0.1813];
Xq=[0.0969 0.8645 1.2578]; Xqp=[0.0969 0.1969 0.25];
Tdo=[8.96 6.00 5.89]; Tqo=[0.31 0.535 0.60];
Efd0=[1.082 1.789 1.403];
ng=3;
mag=[1.04 1.025 1.025 1.026 0.996 1.013 1.026 1.016 1.032];
ang=deg2rad([0 9.3 4.7 -2.2 -4.0 -3.7 3.7 0.7 2.0]);
V=mag(:).*exp(1i*ang(:));
delta0=deg2rad([3.58 61.1 54.2]);
Eqp0=[1.056 0.788 0.768]; Edp0=[0 0.622 0.624];
x0=zeros(4*ng,1);
for k=1:ng
  ii=(k-1)*4; x0(ii+(1:4))=[Eqp0(k);Edp0(k);delta0(k);0];
end
y0=zeros(18,1); y0(1:2:end)=real(V); y0(2:2:end)=imag(V);
Tm=zeros(ng,1);
for k=1:ng
  Vm=abs(V(k)); th=angle(V(k));
  Iq=(Vm*sin(delta0(k)-th)-Edp0(k))/Xqp(k);
  Id=(Eqp0(k)-Vm*cos(delta0(k)-th))/Xdp(k);
  Pe=Edp0(k)*Id+Eqp0(k)*Iq+(Xqp(k)-Xdp(k))*Id*Iq;
  Tm(k)=Pe;
end
Y=ybus();
fx=dae_f(x0,y0); gx=dae_g(x0,y0);
fprintf('f res: %.3e  g res: %.3e\n', norm(fx), norm(gx));
model=struct(); model.x0=x0; model.y0=y0;
model.f=@(xx,yy)dae_f(xx,yy);
model.g=@(xx,yy)dae_g(xx,yy);
model.free_y=setdiff(1:18,2); model.fd_eps=1e-6;
r=stability.multimachine_ssa(model);
lam=r.eigenvalues;
fprintf('maxreal=%.4f\n', max(real(lam)));
lam_osc=lam(abs(imag(lam))>0.1 & imag(lam)>0);
[~,idx]=sort(abs(imag(lam_osc)),'descend'); lam_osc=lam_osc(idx);
fprintf('Oscillatory modes (no exciter):\n');
for k=1:numel(lam_osc)
  fprintf('  %+8.4f%+8.4fj  f=%.3f Hz  zeta=%.4f\n', real(lam_osc(k)), imag(lam_osc(k)), imag(lam_osc(k))/(2*pi), -real(lam_osc(k))/abs(lam_osc(k)));
end
  function f=dae_f(x,y)
  f=zeros(4*ng,1); Vc=complex(y(1:2:end),y(2:2:end));
  for k=1:ng
    ii=(k-1)*4; Eqp=x(ii+1); Edp=x(ii+2); delta=x(ii+3); omega=x(ii+4);
    Vt=Vc(k); Vm=abs(Vt); th=angle(Vt);
    Iq=(Vm*sin(delta-th)-Edp)/Xqp(k);
    Id=(Eqp-Vm*cos(delta-th))/Xdp(k);
    Pe=Edp*Id+Eqp*Iq+(Xqp(k)-Xdp(k))*Id*Iq;
    f(ii+1)=(-Eqp-(Xd(k)-Xdp(k))*Id+Efd0(k))/Tdo(k);
    f(ii+2)=(-Edp+(Xq(k)-Xqp(k))*Iq)/Tqo(k);
    f(ii+3)=omega;
    f(ii+4)=(Tm(k)-Pe-D(k)*omega)/M(k);
  end
  end
  function g=dae_g(x,y)
  Vc=complex(y(1:2:end),y(2:2:end));
  IY=Y*Vc; S_net=Vc.*conj(IY);
  P_gen=zeros(9,1); Q_gen=zeros(9,1);
  for k=1:ng
    ii=(k-1)*4; Eqp=x(ii+1); Edp=x(ii+2); delta=x(ii+3);
    Vt=Vc(k); Vm=abs(Vt); th=angle(Vt);
    Iq=(Vm*sin(delta-th)-Edp)/Xqp(k);
    Id=(Eqp-Vm*cos(delta-th))/Xdp(k);
    Igen=(Id+1i*Iq)*exp(1i*(delta-pi/2));
    Sgen=Vt*conj(Igen);
    P_gen(k)=real(Sgen); Q_gen(k)=imag(Sgen);
  end
  P_load=zeros(9,1); Q_load=zeros(9,1);
  P_load(5)=1.25; Q_load(5)=0.50; P_load(6)=0.90; Q_load(6)=0.30; P_load(8)=1.00; Q_load(8)=0.35;
  dP=P_gen-P_load-real(S_net); dQ=Q_gen-Q_load-imag(S_net);
  g=zeros(18,1); g(1:2:end)=dP; g(2:2:end)=dQ;
  end
  function Y=ybus()
  Y=zeros(9,9);
  br={[1,4,0,0.0576,0],[2,7,0,0.0625,0],[3,9,0,0.0586,0],...
      [4,5,0.010,0.085,0.088],[4,6,0.017,0.092,0.079],[5,7,0.032,0.161,0.153],...
      [6,9,0.039,0.170,0.179],[7,8,0.0085,0.072,0.0745],[8,9,0.0119,0.1008,0.1045]};
  for n=1:numel(br)
    i=br{n}(1); j=br{n}(2); r=br{n}(3); x=br{n}(4); bh=br{n}(5);
    y=1/(r+1i*x); Y(i,i)=Y(i,i)+y+1i*bh; Y(j,j)=Y(j,j)+y+1i*bh; Y(i,j)=Y(i,j)-y; Y(j,i)=Y(j,i)-y;
  end
  end
end
