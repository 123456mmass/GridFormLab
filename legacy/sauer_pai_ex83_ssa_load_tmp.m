function result = sauer_pai_ex83_ssa_load_tmp(useConj)
if nargin<1; useConj=true; end
% 3-machine 9-bus WECC system from Sauer-Pai Example 7.1 with IEEE Type-1
% exciters.  State per machine: [E'q, E'd, delta, omega, Efd, Rf, VR].

baseMVA = 100; f0 = 60; ws = 2*pi*f0;
mp = machine_data(ws);
[V0, Sg] = loadflow_data();
Y = ybus_wscc9();
ng = 3; nb = 9;

% Initial states from Sauer-Pai Example 7.5.  Using these published
% values is important: solving only the scalar stator relation can converge
% to a different rotor-angle branch.
x0 = zeros(7*ng,1);
Eqp0   = [1.056; 0.788; 0.768];
Edp0   = [0.000; 0.622; 0.624];
delta0 = deg2rad([3.58; 61.1; 54.2]);
Efd0   = [1.082; 1.789; 1.403];
Rf0    = [0.195; 0.322; 0.252];
VR0    = [1.105; 1.902; 1.453];
Vref   = [1.095; 1.120; 1.090];
Tm     = [0.716; 1.630; 0.850];
for k = 1:ng
    ii = (k-1)*7;
    x0(ii+(1:7)) = [Eqp0(k); Edp0(k); delta0(k); 0; Efd0(k); Rf0(k); VR0(k)];
end

y0 = complex_to_y(V0);

% Refine equilibrium allowing x, y, Tm, Vref to adjust; fix delta_1 and bus1 imag.
fixed_x = 3; free_x = setdiff(1:numel(x0), fixed_x);
fixed_y = 2; free_y = setdiff(1:numel(y0), fixed_y);
z0 = [x0(free_x); y0(free_y); Tm; Vref];
resfun = @(z) residual(z,x0,y0,free_x,free_y,mp,Y,Tm,Vref,useConj);
opts = optimoptions('fsolve','Display','off','FunctionTolerance',1e-11,'StepTolerance',1e-12,'MaxIterations',300,'MaxFunctionEvaluations',6000);
[zsol,~,exitflag,out] = fsolve(resfun,z0,opts);
resn = norm(resfun(zsol));
x = x0; y = y0; x(free_x)=zsol(1:numel(free_x)); y(free_y)=zsol(numel(free_x)+1:numel(free_x)+numel(free_y));
Tm = zsol(numel(free_x)+numel(free_y)+1:numel(free_x)+numel(free_y)+ng);
Vref = zsol(numel(free_x)+numel(free_y)+ng+1:end);

% Linearize DAE [f;g].
nx=numel(x); ny=numel(y); h=1e-6;
Jxx=zeros(nx,nx); Jxy=zeros(nx,ny); Jyx=zeros(ny,nx); Jyy=zeros(ny,ny);
for i=1:nx
    xp=x; xm=x; xp(i)=xp(i)+h; xm(i)=xm(i)-h;
    Jxx(:,i)=(dae_f(xp,y,mp,Tm,Vref)-dae_f(xm,y,mp,Tm,Vref))/(2*h);
    Jyx(:,i)=(dae_g(xp,y,mp,Y,useConj)-dae_g(xm,y,mp,Y,useConj))/(2*h);
end
for j=1:ny
    yp=y; ym=y; yp(j)=yp(j)+h; ym(j)=ym(j)-h;
    Jxy(:,j)=(dae_f(x,yp,mp,Tm,Vref)-dae_f(x,ym,mp,Tm,Vref))/(2*h);
    Jyy(:,j)=(dae_g(x,yp,mp,Y,useConj)-dae_g(x,ym,mp,Y,useConj))/(2*h);
end
Afull = Jxx - Jxy(:,free_y) * (Jyy(free_y,free_y) \ Jyx(free_y,:));
lam = eig(Afull);

result = struct();
result.eigenvalues = lam;
result.A = Afull;
result.x0 = x; result.y0 = y; result.Tm = Tm; result.Vref = Vref;
result.residual = resn; result.exitflag = exitflag; result.iterations = out.iterations;
result.reference = cases.sauer_pai_reference_catalog().example_8_3_table_8_1;
end

function res = residual(z,x0,y0,free_x,free_y,mp,Y,Tm0,Vref0,useConj)
ng=3; nx=numel(free_x); ny=numel(free_y);
x=x0; y=y0; x(free_x)=z(1:nx); y(free_y)=z(nx+1:nx+ny);
Tm=z(nx+ny+1:nx+ny+ng); Vref=z(nx+ny+ng+1:end);
res=[dae_f(x,y,mp,Tm,Vref); dae_g(x,y,mp,Y,useConj)];
end

function f = dae_f(x,y,mp,Tm,Vref)
ng=3; f=zeros(7*ng,1); V=complex(y(1:2:end),y(2:2:end));
for k=1:ng
    ii=(k-1)*7; Eqp=x(ii+1); Edp=x(ii+2); delta=x(ii+3); omega=x(ii+4); Efd=x(ii+5); Rf=x(ii+6); VR=x(ii+7);
    Vt=V(k); Vm=abs(Vt); theta=angle(Vt);
    [Id,Iq]=stator(mp(k),Eqp,Edp,delta,Vt);
    Pe=Edp*Id + Eqp*Iq + (mp(k).Xqp-mp(k).Xdp)*Id*Iq;
    f(ii+1)=(-Eqp-(mp(k).Xd-mp(k).Xdp)*Id+Efd)/mp(k).Tdo;
    f(ii+2)=(-Edp+(mp(k).Xq-mp(k).Xqp)*Iq)/mp(k).Tqo;
    f(ii+3)=omega;
    f(ii+4)=(Tm(k)-Pe-mp(k).D*omega)/mp(k).M;
    f(ii+5)=(-mp(k).KE*Efd - sat(mp(k),Efd) + VR)/mp(k).TE;
    f(ii+6)=(-Rf + mp(k).KF/mp(k).TF*Efd)/mp(k).TF;
    f(ii+7)=(-VR - mp(k).KA*mp(k).KF/mp(k).TF*Efd + mp(k).KA*Rf + mp(k).KA*(Vref(k)-Vm))/mp(k).TA;
end
end

function g = dae_g(x,y,mp,Y,useConj)
V=complex(y(1:2:end),y(2:2:end)); Iinj=zeros(9,1);
for k=1:3
    ii=(k-1)*7; Eqp=x(ii+1); Edp=x(ii+2); delta=x(ii+3);
    [Id,Iq]=stator(mp(k),Eqp,Edp,delta,V(k));
    Iinj(k)=(Id+1i*Iq)*exp(1i*(delta-pi/2));
end
% Constant-power loads as negative current injections.
loads=zeros(9,1); loads(5)=1.25+1i*0.50; loads(6)=0.90+1i*0.30; loads(8)=1.00+1i*0.35;
for b=1:9
    if abs(loads(b))>0
        if useConj; Iinj(b)=Iinj(b)+conj((-loads(b))/V(b)); else; Iinj(b)=Iinj(b)+(-real(loads(b))+1i*imag(loads(b)))/V(b); end
    end
end
mis=Iinj - Y*V;
g=zeros(18,1); g(1:2:end)=real(mis); g(2:2:end)=imag(mis);
end

function [Id,Iq]=stator(m,Eqp,Edp,delta,Vt)
Vm=abs(Vt); theta=angle(Vt);
Iq=(Vm*sin(delta-theta)-Edp)/m.Xqp;
Id=(Eqp-Vm*cos(delta-theta))/m.Xdp;
end

function S=sat(m,Efd)
S = 0.0039*exp(1.555*Efd);
end

function mp=machine_data(ws)
H=[23.64 6.40 3.01]; D=[0 0 0];
Xd=[0.146 0.8958 1.3125]; Xdp=[0.0608 0.1198 0.1813];
Xq=[0.0969 0.8645 1.2578]; Xqp=[0.0969 0.1969 0.25];
Tdo=[8.96 6.00 5.89]; Tqo=[0.31 0.535 0.60];
for k=1:3
    mp(k)=struct('H',H(k),'M',2*H(k)/ws,'D',D(k),'Xd',Xd(k),'Xdp',Xdp(k),'Xq',Xq(k),'Xqp',Xqp(k), ...
        'Tdo',Tdo(k),'Tqo',Tqo(k),'KA',20,'TA',0.2,'KE',1.0,'TE',0.314,'KF',0.063,'TF',0.35); %#ok<AGROW>
end
end

function [V,Sg]=loadflow_data()
mag=[1.04 1.025 1.025 1.026 0.996 1.013 1.026 1.016 1.032];
ang=deg2rad([0 9.3 4.7 -2.2 -4.0 -3.7 3.7 0.7 2.0]);
V=mag(:).*exp(1i*ang(:));
Sg=zeros(9,1); Sg(1)=0.716+1i*0.270; Sg(2)=1.630+1i*0.067; Sg(3)=0.850-1i*0.109;
end

function y=complex_to_y(V)
y=zeros(2*numel(V),1); y(1:2:end)=real(V); y(2:2:end)=imag(V);
end

function Y=ybus_wscc9()
Y=zeros(9,9); add(1,4,0,0.0576,0); add(2,7,0,0.0625,0); add(3,9,0,0.0586,0);
add(4,5,0.010,0.085,0.088); add(4,6,0.017,0.092,0.079); add(5,7,0.032,0.161,0.153);
add(6,9,0.039,0.170,0.179); add(7,8,0.0085,0.072,0.0745); add(8,9,0.0119,0.1008,0.1045);
    function add(i,j,r,x,bh)
        y=1/(r+1i*x); Y(i,i)=Y(i,i)+y+1i*bh; Y(j,j)=Y(j,j)+y+1i*bh; Y(i,j)=Y(i,j)-y; Y(j,i)=Y(j,i)-y;
    end
end
