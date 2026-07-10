function c = sauer_pai_ex83_case()
%SAUER_PAI_EX83_CASE Data plugin for Sauer-Pai Example 8.3 (WSCC 3-machine 9-bus).
% Provides only parameters and operating point; no eigenvalue fitting.

c.name = 'Sauer-Pai Example 8.3 / WSCC 3-machine 9-bus';
c.ws = 2*pi*60;
c.gen_buses = (1:3).';
c.pq_buses = (4:9).'; % all non-generator buses, including zero-injection buses
c.H=[23.64;6.40;3.01]; c.D=zeros(3,1);
c.Xd=[0.146;0.8958;1.3125]; c.Xdp=[0.0608;0.1198;0.1813];
c.Xq=[0.0969;0.8645;1.2578]; c.Xqp=[0.0969;0.1969;0.25];
c.Tdo=[8.96;6.00;5.89]; c.Tqo=[0.31;0.535;0.60];
c.KA=20*ones(3,1); c.TA=0.2*ones(3,1); c.KE=ones(3,1);
c.TE=0.314*ones(3,1); c.KF=0.063*ones(3,1); c.TF=0.35*ones(3,1);
c.sat_A=0.0039; c.sat_B=1.555;
c.V=[1.040000000000;1.025000000000;1.025000000000;1.025787263514;0.995630832841;1.012654329782;1.025769854591;1.015882434032;1.032353191373];
c.theta=[0.000000000000;0.161966234483;0.081393369680;-0.038679928399;-0.069603060755;-0.064406521087;0.064878986470;0.012711340210;0.034342336683];
c.Pg=[0.716352797962;1.630000000000;0.850000000000];
c.Qg=[0.270535092079;0.066475104982;-0.108620884347];
c.Ybus = local_ybus();
c=cases.standardize_study_case(c,'dynamic_benchmark');
end

function Y=local_ybus()
Y=zeros(9); br=[1 4 0 0.0576 0;2 7 0 0.0625 0;3 9 0 0.0586 0;4 5 0.010 0.085 0.088;4 6 0.017 0.092 0.079;5 7 0.032 0.161 0.153;6 9 0.039 0.170 0.179;7 8 0.0085 0.072 0.0745;8 9 0.0119 0.1008 0.1045];
for k=1:size(br,1)
    i=br(k,1); j=br(k,2); y=1/(br(k,3)+1i*br(k,4)); b=br(k,5);
    Y(i,i)=Y(i,i)+y+1i*b; Y(j,j)=Y(j,j)+y+1i*b; Y(i,j)=Y(i,j)-y; Y(j,i)=Y(j,i)-y;
end
end
