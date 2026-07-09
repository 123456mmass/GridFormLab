function probe_sauer_conjv()
% Test CB with conj(V) load and check PB residual.
ws=2*pi*60; mp=machine_data(ws); Y=ybus_wscc9(); ng=3;
V0=loadflow_data();
x0=zeros(7*ng,1);
Eqp0=[1.056 0.788 0.768]; Edp0=[0 0.622 0.624];
delta0=deg2rad([3.58 61.1 54.2]); Efd0=[1.082 1.789 1.403];
Rf0=[0.195 0.322 0.252]; VR0=[1.105 1.902 1.453];
Vref=[1.095; 1.120; 1.090]; Tm=[0.716; 1.630; 0.850];
for k=1:ng
  ii=(k-1)*7; x0(ii+(1:7))=[Eqp0(k);Edp0(k);delta0(k);0;Efd0(k);Rf0(k);VR0(k)];
end
y0=zeros(18,1); y0(1:2:end)=real(V0); y0(2:2:end)=imag(V0);

for conjv = [true false]
  fixed_x=3; free_x=setdiff(1:numel(x0),fixed_x);
  fixed_y=2; free_y=setdiff(1:numel(y0),fixed_y);
  z0=[x0(free_x); y0(free_y); Tm; Vref];
  resfun=@(z)residual_cb(z,x0,y0,free_x,free_y,mp,Y,Tm,Vref,conjv);
  opts=optimoptions('fsolve','Display','off','FunctionTolerance',1e-12,'StepTolerance',1e-13,'MaxIterations',500,'MaxFunctionEvaluations',10000);
  [zsol,~,~,~]=fsolve(resfun,z0,opts);
  x=x0; y=y0; x(free_x)=zsol(1:numel(free_x)); y(free_y)=zsol(numel(free_x)+1:numel(free_x)+numel(free_y));
  Tm=zsol(numel(free_x)+numel(free_y)+1:numel(free_x)+numel(free_y)+ng);
  Vref=zsol(numel(free_x)+numel(free_y)+ng+1:end);
  cb_res = norm(resfun(zsol));
  pb_res = norm([dae_f(x,y,mp,Tm,Vref); dae_g_pb(x,y,mp,Y)]);
  fprintf('\n=== conjV=%d ===\n', conjv);
  fprintf('CB residual: %.3e\n', cb_res);
  fprintf('PB residual: %.3e\n', pb_res);
  
  model=struct(); model.x0=x; model.y0=y;
  model.f=@(xx,yy)dae_f(xx,yy,mp,Tm,Vref);
  model.g=@(xx,yy)dae_g_cb(xx,yy,mp,Y,conjv);
  model.free_y=free_y; model.fd_eps=1e-6;
  r=stability.multimachine_ssa(model);
  lam=r.eigenvalues;
  fprintf('maxreal=%.4f\n', max(real(lam)));
end
end

function res=residual_cb(z,x0,y0,free_x,free_y,mp,Y,Tm0,Vref0,conjv)
ng=3; nx=numel(free_x); ny=numel(free_y);
x=x0; y=y0; x(free_x)=z(1:nx); y(free_y)=z(nx+1:nx+ny);
Tm=z(nx+ny+1:nx+ny+ng); Vref=z(nx+ny+ng+1:end);
res=[dae_f(x,y,mp,Tm,Vref); dae_g_cb(x,y,mp,Y,conjv)];
end

function f=dae_f(x,y,mp,Tm,Vref)
ng=3; f=zeros(7*ng,1); V=complex(y(1:2:end),y(2:2:end));
for k=1:ng
  ii=(k-1)*7; Eqp=x(ii+1); Edp=x(ii+2); delta=x(ii+3); omega=x(ii+4); Efd=x(ii+5); Rf=x(ii+6); VR=x(ii+7);
  Vt=V(k); Vm=abs(Vt); theta=angle(Vt);
  Iq=(Vm*sin(delta-theta)-Edp)/mp(k).Xqp;
  Id=(Eqp-Vm*cos(delta-theta))/mp(k).Xdp;
  Pe=Edp*Id+Eqp*Iq+(mp(k).Xqp-mp(k).Xdp)*Id*Iq;
  f(ii+1)=(-Eqp-(mp(k).Xd-mp(k).Xdp)*Id+Efd)/mp(k).Tdo;
  f(ii+2)=(-Edp+(mp(k).Xq-mp(k).Xqp)*Iq)/mp(k).Tqo;
  f(ii+3)=omega;
  f(ii+4)=(Tm(k)-Pe-mp(k).D*omega)/mp(k).M;
  f(ii+5)=(-mp(k).KE*Efd-mp(k).KE_sat*exp(1.555*Efd)*Efd+VR)/mp(k).TE;
  f(ii+6)=(-Rf+mp(k).KF/mp(k).TF*Efd)/mp(k).TF;
  f(ii+7)=(-VR-mp(k).KA*mp(k).KF/mp(k).TF*Efd+mp(k).KA*Rf+mp(k).KA*(Vref(k)-Vm))/mp(k).TA;
end
end

function g=dae_g_cb(x,y,mp,Y,conjv)
V=complex(y(1:2:end),y(2:2:end)); Iinj=zeros(9,1);
for k=1:3
  ii=(k-1)*7; Eqp=x(ii+1); Edp=x(ii+2); delta=x(ii+3);
  Vt=V(k); Vm=abs(Vt); theta=angle(Vt);
  Iq=(Vm*sin(delta-theta)-Edp)/mp(k).Xqp;
  Id=(Eqp-Vm*cos(delta-theta))/mp(k).Xdp;
  Iinj(k)=(Id+1i*Iq)*exp(1i*(delta-pi/2));
end
loads=zeros(9,1); loads(5)=1.25+1i*0.50; loads(6)=0.90+1i*0.30; loads(8)=1.00+1i*0.35;
for b=1:9
  if abs(loads(b))>0
    if conjv
      Iinj(b)=Iinj(b)+conj(-loads(b)/V(b));
    else
      Iinj(b)=Iinj(b)+(-real(loads(b))+1i*imag(loads(b)))/V(b);
    end
  end
end
mis=Iinj-Y*V; g=zeros(18,1); g(1:2:end)=real(mis); g(2:2:end)=imag(mis);
end

function g=dae_g_pb(x,y,mp,Y)
V=complex(y(1:2:end),y(2:2:end));
IY=Y*V; S_net=V.*conj(IY);
P_net=real(S_net); Q_net=imag(S_net);
P_gen=zeros(9,1); Q_gen=zeros(9,1);
for k=1:3
  ii=(k-1)*7; Eqp=x(ii+1); Edp=x(ii+2); delta=x(ii+3);
  Vt=V(k); Vm=abs(Vt); theta=angle(Vt);
  Iq=(Vm*sin(delta-theta)-Edp)/mp(k).Xqp;
  Id=(Eqp-Vm*cos(delta-theta))/mp(k).Xdp;
  Igen=(Id+1i*Iq)*exp(1i*(delta-pi/2));
  Sgen=Vt*conj(Igen);
  P_gen(k)=real(Sgen); Q_gen(k)=imag(Sgen);
end
P_load=zeros(9,1); Q_load=zeros(9,1);
P_load(5)=1.25; Q_load(5)=0.50; P_load(6)=0.90; Q_load(6)=0.30; P_load(8)=1.00; Q_load(8)=0.35;
dP=P_gen-P_load-P_net; dQ=Q_gen-Q_load-Q_net;
g=zeros(18,1); g(1:2:end)=dP; g(2:2:end)=dQ;
end

function mp=machine_data(ws)
H=[23.64 6.40 3.01]; D=[0 0 0];
Xd=[0.146 0.8958 1.3125]; Xdp=[0.0608 0.1198 0.1813];
Xq=[0.0969 0.8645 1.2578]; Xqp=[0.0969 0.1969 0.25];
Tdo=[8.96 6.00 5.89]; Tqo=[0.31 0.535 0.60];
for k=1:3
  mp(k)=struct('H',H(k),'M',2*H(k)/ws,'D',D(k),'Xd',Xd(k),'Xdp',Xdp(k),'Xq',Xq(k),'Xqp',Xqp(k), ...
    'Tdo',Tdo(k),'Tqo',Tqo(k),'KA',20,'TA',0.2,'KE',1.0,'TE',0.314,'KF',0.063,'TF',0.35,'KE_sat',0.0039);
end
end

function V=loadflow_data()
mag=[1.04 1.025 1.025 1.026 0.996 1.013 1.026 1.016 1.032];
ang=deg2rad([0 9.3 4.7 -2.2 -4.0 -3.7 3.7 0.7 2.0]);
V=mag(:).*exp(1i*ang(:));
end

function Y=ybus_wscc9()
Y=zeros(9,9);
br={[1,4,0,0.0576,0],[2,7,0,0.0625,0],[3,9,0,0.0586,0],...
    [4,5,0.010,0.085,0.088],[4,6,0.017,0.092,0.079],[5,7,0.032,0.161,0.153],...
    [6,9,0.039,0.170,0.179],[7,8,0.0085,0.072,0.0745],[8,9,0.0119,0.1008,0.1045]};
for n=1:size(br,1)
  i=br{n}(1); j=br{n}(2); r=br{n}(3); x=br{n}(4); bh=br{n}(5);
  y=1/(r+1i*x); Y(i,i)=Y(i,i)+y+1i*bh; Y(j,j)=Y(j,j)+y+1i*bh; Y(i,j)=Y(i,j)-y; Y(j,i)=Y(j,i)-y;
end
end
