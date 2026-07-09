function out = sauer_pai_linearization(c)
%SAUER_PAI_LINEARIZATION Generic two-axis + IEEE-Type-I analytical linearizer.
% OUT = SAUER_PAI_LINEARIZATION(CASE) builds the reduced state matrix for a
% multimachine system using Sauer-Pai's two-level Schur complement.
%
% Required case fields:
%   ws, gen_buses, pq_buses, Ybus, V, theta, Pg, Qg
%   H,D, Xd,Xdp,Xq,Xqp, Tdo,Tqo
%   KA,TA,KE,TE,KF,TF, sat_A,sat_B
%
% State per machine: [delta, omega, Eq', Ed', Efd, VR, Rf].

ws=c.ws; gen=c.gen_buses(:); pq=c.pq_buses(:); Y=c.Ybus; V=c.V(:); th=c.theta(:);
ng=numel(gen); nb=numel(V); ns=7; npq=numel(pq);
H=c.H(:); D=c.D(:); M=2*H/ws;
Xd=c.Xd(:); Xdp=c.Xdp(:); Xq=c.Xq(:); Xqp=c.Xqp(:); Tdo=c.Tdo(:); Tqo=c.Tqo(:);
KA=c.KA(:); TA=c.TA(:); KE=c.KE(:); TE=c.TE(:); KF=c.KF(:); TF=c.TF(:);
Asat=c.sat_A; Bsat=c.sat_B;
Vg=V(gen); thg=th(gen); Pg=c.Pg(:); Qg=c.Qg(:);
I=conj((Pg+1i*Qg)./(Vg.*exp(1i*thg)));
delta=angle(Vg.*exp(1i*thg)+1i*Xq.*I);
Id=abs(I).*sin(delta-angle(I)); Iq=abs(I).*cos(delta-angle(I));
Edp=(Xq-Xqp).*Iq; Eqp=Vg.*cos(delta-thg)+Xdp.*Id; Efd=Eqp+(Xd-Xdp).*Id;
VR=(KE+Asat*exp(Bsat*Efd)).*Efd; Rf=(KF./TF).*Efd;

A1=[]; B1=[]; B2=[]; C1=[]; D1=[]; D2=[]; C2=[]; D3=[];
for i=1:ng
    s=sin(delta(i)-thg(i)); cc=cos(delta(i)-thg(i));
    SE=Asat*exp(Bsat*Efd(i)); SEp=Asat*Bsat*exp(Bsat*Efd(i));
    fsi=-(KE(i)+Efd(i)*SEp+SE)/TE(i);
    A1i=[0 1 0 0 0 0 0;
          0 -D(i)/M(i) -Iq(i)/M(i) -Id(i)/M(i) 0 0 0;
          0 0 -1/Tdo(i) 0 1/Tdo(i) 0 0;
          0 0 0 -1/Tqo(i) 0 0 0;
          0 0 0 0 fsi 1/TE(i) 0;
          0 0 0 0 -KA(i)*KF(i)/(TA(i)*TF(i)) -1/TA(i) KA(i)/TA(i);
          0 0 0 0 KF(i)/TF(i)^2 0 -1/TF(i)];
    B1i=[0 0;
          (Iq(i)*(Xdp(i)-Xqp(i))-Edp(i))/M(i), (Id(i)*(Xdp(i)-Xqp(i))-Eqp(i))/M(i);
          -(Xd(i)-Xdp(i))/Tdo(i), 0;
          0, (Xq(i)-Xqp(i))/Tqo(i);
          0 0; 0 0; 0 0];
    B2i=zeros(ns,2); B2i(6,2)=-KA(i)/TA(i);
    C1i=[-Vg(i)*cc 0 0 1 0 0 0; Vg(i)*s 0 1 0 0 0 0];
    D1i=[0 Xqp(i); -Xdp(i) 0];
    D2i=[Vg(i)*cc -s; -Vg(i)*s -cc];
    C2i=[Id(i)*Vg(i)*cc-Iq(i)*Vg(i)*s 0 0 0 0 0 0;
         -Iq(i)*Vg(i)*cc-Id(i)*Vg(i)*s 0 0 0 0 0 0];
    D3i=[Vg(i)*s Vg(i)*cc; Vg(i)*cc -Vg(i)*s];
    A1=blkdiag(A1,A1i); B1=blkdiag(B1,B1i); B2=blkdiag(B2,B2i);
    C1=blkdiag(C1,C1i); D1=blkdiag(D1,D1i); D2=blkdiag(D2,D2i);
    C2=blkdiag(C2,C2i); D3=blkdiag(D3,D3i);
end

D4=zeros(2*ng); D5=zeros(2*ng,2*npq);
for l=1:ng
    p=gen(l); m=p;
    for k=1:ng
        q=gen(k); n=q;
        if p==q
            s=sin(delta(p)-thg(p)); cc=cos(delta(p)-thg(p));
            D4(2*l-1,2*k-1)=-Id(p)*Vg(p)*cc+Iq(p)*Vg(p)*s;
            D4(2*l,2*k-1)= Iq(p)*Vg(p)*cc+Id(p)*Vg(p)*s;
            for kk=1:nb
                if kk~=m
                    a=thg(p)-th(kk)-angle(Y(m,kk));
                    D4(2*l-1,2*k-1)=D4(2*l-1,2*k-1)+Vg(p)*V(kk)*abs(Y(m,kk))*sin(a);
                    D4(2*l,2*k-1)=D4(2*l,2*k-1)-Vg(p)*V(kk)*abs(Y(m,kk))*cos(a);
                end
            end
            a=thg(p)-thg(p)-angle(Y(m,m));
            D4(2*l-1,2*k)=Id(p)*s+Iq(p)*cc - Vg(p)*abs(Y(m,m))*cos(a);
            D4(2*l,2*k)= -Iq(p)*s+Id(p)*cc - Vg(p)*abs(Y(m,m))*sin(a);
            for kk=1:nb
                a=thg(p)-th(kk)-angle(Y(m,kk));
                D4(2*l-1,2*k)=D4(2*l-1,2*k)-V(kk)*abs(Y(m,kk))*cos(a);
                D4(2*l,2*k)=D4(2*l,2*k)-V(kk)*abs(Y(m,kk))*sin(a);
            end
        else
            a=thg(p)-thg(q)-angle(Y(m,n));
            D4(2*l-1,2*k-1)=-Vg(p)*Vg(q)*abs(Y(m,n))*sin(a);
            D4(2*l,2*k-1)= Vg(p)*Vg(q)*abs(Y(m,n))*cos(a);
            D4(2*l-1,2*k)=-Vg(p)*abs(Y(m,n))*cos(a);
            D4(2*l,2*k)=-Vg(p)*abs(Y(m,n))*sin(a);
        end
    end
    for kp=1:npq
        kk=pq(kp); a=thg(p)-th(kk)-angle(Y(m,kk));
        D5(2*l-1,2*kp-1)=-Vg(p)*V(kk)*abs(Y(m,kk))*sin(a);
        D5(2*l,2*kp-1)= Vg(p)*V(kk)*abs(Y(m,kk))*cos(a);
        D5(2*l-1,2*kp)=-Vg(p)*abs(Y(m,kk))*cos(a);
        D5(2*l,2*kp)=-Vg(p)*abs(Y(m,kk))*sin(a);
    end
end

D6=zeros(2*npq,2*ng); D7=zeros(2*npq);
for l=1:npq
    m=pq(l);
    for kg=1:ng
        n=gen(kg); a=th(m)-th(n)-angle(Y(m,n));
        D6(2*l-1,2*kg-1)=-V(m)*V(n)*abs(Y(m,n))*sin(a);
        D6(2*l,2*kg-1)= V(m)*V(n)*abs(Y(m,n))*cos(a);
        D6(2*l-1,2*kg)=-V(m)*abs(Y(m,n))*cos(a);
        D6(2*l,2*kg)=-V(m)*abs(Y(m,n))*sin(a);
    end
    for k=1:npq
        n=pq(k);
        if m==n
            for kk=1:nb
                if kk~=m
                    a=th(m)-th(kk)-angle(Y(m,kk));
                    D7(2*l-1,2*k-1)=D7(2*l-1,2*k-1)+V(m)*V(kk)*abs(Y(m,kk))*sin(a);
                    D7(2*l,2*k-1)=D7(2*l,2*k-1)-V(m)*V(kk)*abs(Y(m,kk))*cos(a);
                end
            end
            a=th(m)-th(n)-angle(Y(m,n));
            D7(2*l-1,2*k)=-V(m)*abs(Y(m,n))*cos(a);
            D7(2*l,2*k)=-V(m)*abs(Y(m,n))*sin(a);
            for kk=1:nb
                a=th(m)-th(kk)-angle(Y(m,kk));
                D7(2*l-1,2*k)=D7(2*l-1,2*k)-V(kk)*abs(Y(m,kk))*cos(a);
                D7(2*l,2*k)=D7(2*l,2*k)-V(kk)*abs(Y(m,kk))*sin(a);
            end
        else
            a=th(m)-th(n)-angle(Y(m,n));
            D7(2*l-1,2*k-1)=-V(m)*V(n)*abs(Y(m,n))*sin(a);
            D7(2*l,2*k-1)= V(m)*V(n)*abs(Y(m,n))*cos(a);
            D7(2*l-1,2*k)=-V(m)*abs(Y(m,n))*cos(a);
            D7(2*l,2*k)=-V(m)*abs(Y(m,n))*sin(a);
        end
    end
end

Asys = A1 - B1/D1*C1 - (B2-B1/D1*D2) / (D4-D3/D1*D2-D5/D7*D6) * (C2-D3/D1*C1);
out=struct('A',Asys,'H',H,'x0',zeros(ns*ng,1),'ng',ng,'ns',ns);
for i=1:ng
    ii=(i-1)*ns; out.x0(ii+(1:ns))=[delta(i);0;Eqp(i);Edp(i);Efd(i);VR(i);Rf(i)];
end
out.blocks=struct('A1',A1,'B1',B1,'B2',B2,'C1',C1,'D1',D1,'D2',D2,'C2',C2,'D3',D3,'D4',D4,'D5',D5,'D6',D6,'D7',D7);
out.initial=struct('delta',delta,'Id',Id,'Iq',Iq,'Eqp',Eqp,'Edp',Edp,'Efd',Efd,'VR',VR,'Rf',Rf);
end
