% Independent scalar swing/governor oracle for the chronology synchronizer.
H=2.5; D=1; w0=2*pi*60; Tsv=.2; Tch=.4; Tmax=1.3462;
dt=.01; T=125; n=round(T/dt); delta=0; omega=0; Psv=1.31895; Pm=Psv;
wgrid=-0.000153; theta=0;
ready=false; A=0; pulse_end=NaN; target=NaN;
for k=1:n
    t=(k-1)*dt; tau=T-t; coast=5*(2*H/D); prep=coast+10*Tch;
    if ~ready && tau<=prep && tau>coast
      pulse_end=T-coast;
      [d0,~]=forecast(delta,omega,Psv,Pm,t,T,pulse_end,0,H,D,w0,Tsv,Tch);
      [d1,~]=forecast(delta,omega,Psv,Pm,t,T,pulse_end,1,H,D,w0,Tsv,Tch);
      sens=d1-d0; th=theta+w0*wgrid*tau; n0=ceil((d0-th)/(2*pi));
      for m=n0:n0+ceil(abs(sens)*Tmax/(2*pi))+2
          q=(th+2*pi*m-d0)/sens;
          if q>=0 && q<=Tmax, A=q; target=th+2*pi*m; break; end
      end
      ready=true;
    end
    cmd=0; if ready && t<pulse_end,cmd=A;end
    esv=exp(-dt/Tsv); ech=exp(-dt/Tch);
    Psv1=cmd+(Psv-cmd)*esv;
    Pm1=cmd+(Pm-cmd)*ech+(Psv-cmd)*Tsv/(Tsv-Tch)*(esv-ech);
    omega1=omega+dt*(0.5*(Pm+Pm1)-D*omega)/(2*H);
    delta=delta+dt*w0*0.5*(omega+omega1);
    omega=omega1; Psv=Psv1; Pm=Pm1; theta=theta+dt*w0*wgrid;
end
fprintf('oracle omega=%.9g phase_deg=%.6f Pm=%.9g\n',omega, ...
    mod((delta-theta)*180/pi+180,360)-180,Pm);

function [delta,omega]=forecast(delta,omega,Psv,Pm,t,tend,pulse,A,H,D,w0,Tsv,Tch)
dt=.01;
while t<tend-1e-12
 h=min(dt,tend-t);cmd=0;if t<pulse,cmd=A;end
 es=exp(-h/Tsv);ec=exp(-h/Tch);ps=cmd+(Psv-cmd)*es;
 pm=cmd+(Pm-cmd)*ec+(Psv-cmd)*Tsv/(Tsv-Tch)*(es-ec);
 pav=.5*(Pm+pm);a=D/(2*H);wi=pav/D;ea=exp(-a*h);
 delta=delta+w0*(wi*h+(omega-wi)*(1-ea)/a);omega=wi+(omega-wi)*ea;
 Psv=ps;Pm=pm;t=t+h;
end
end
