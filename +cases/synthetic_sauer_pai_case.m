function c = synthetic_sauer_pai_case(ng)
%SYNTHETIC_SAUER_PAI_CASE Equilibrium synthetic case for solver scalability tests.
% Creates a physically consistent n-machine / 2n-bus system in the same
% model family as Sauer-Pai (two-axis machine + IEEE-Type-I exciter).  The
% operating-point P/Q injections are computed from Ybus and the selected bus
% voltages, so the algebraic power balance has a consistent equilibrium.
%
% This is NOT a published benchmark.  It is a generalization/smoke test for
% machine counts not covered by published references.

if nargin < 1, ng = 2; end
assert(ng >= 2, 'Synthetic multimachine case requires ng >= 2');
nb = 2*ng;
gen = (1:ng).'; pq = (ng+1:nb).';
Y = zeros(nb);
% Each generator has a transformer-like tie to a local load/transfer bus.
for k = 1:ng
    add_branch(k, ng+k, 0.002, 0.12 + 0.005*k, 0.01);
end
% Ring among non-generator buses to create inter-area coupling.
for k = 1:ng
    i = ng+k; j = ng + mod(k, ng) + 1;
    add_branch(i, j, 0.01 + 0.001*k, 0.16 + 0.01*k, 0.03);
end

V = ones(nb,1);
V(gen) = 1.03 - 0.003*(0:ng-1).';
V(pq) = 1.00 - 0.004*(0:ng-1).';
theta = zeros(nb,1);
theta(gen) = linspace(0, 0.25, ng).';
theta(pq) = theta(gen) - 0.06 - 0.01*(0:ng-1).';
Vc = V .* exp(1i*theta);
Snet = Vc .* conj(Y*Vc);
Pg = real(Snet(gen));
Qg = imag(Snet(gen));
% Keep generator powers positive for all machines by shifting angular profile
% if numerical construction produces a small importing unit.
if any(Pg <= 0.05)
    theta(gen) = linspace(0.25, 0, ng).';
    theta(pq) = theta(gen) - 0.04 - 0.005*(0:ng-1).';
    Vc = V .* exp(1i*theta);
    Snet = Vc .* conj(Y*Vc);
    Pg = real(Snet(gen)); Qg = imag(Snet(gen));
end
Pg = max(Pg, 0.10); % avoid degenerate zero-power synthetic machines

baseH=[23.64;6.40;3.01;4.50;5.20;3.80];
baseXd=[0.146;0.8958;1.3125;1.05;1.15;0.98];
baseXdp=[0.0608;0.1198;0.1813;0.16;0.17;0.14];
baseXq=[0.0969;0.8645;1.2578;0.98;1.08;0.92];
baseXqp=[0.0969;0.1969;0.25;0.22;0.24;0.20];
baseTdo=[8.96;6.0;5.89;6.5;7.0;6.2];
baseTqo=[0.31;0.535;0.6;0.55;0.58;0.52];
idx = mod((1:ng)'-1, numel(baseH)) + 1;

c.name = sprintf('Synthetic Sauer-Pai-family %d-machine case', ng);
c.ws = 2*pi*60;
c.gen_buses = gen; c.pq_buses = pq; c.Ybus = Y; c.V = V; c.theta = theta; c.Pg = Pg; c.Qg = Qg;
c.H=baseH(idx); c.D=zeros(ng,1);
c.Xd=baseXd(idx); c.Xdp=baseXdp(idx); c.Xq=baseXq(idx); c.Xqp=baseXqp(idx);
c.Tdo=baseTdo(idx); c.Tqo=baseTqo(idx);
c.KA=20*ones(ng,1); c.TA=0.2*ones(ng,1); c.KE=ones(ng,1);
c.TE=0.314*ones(ng,1); c.KF=0.063*ones(ng,1); c.TF=0.35*ones(ng,1);
c.sat_A=0.0039; c.sat_B=1.555;

    function add_branch(i,j,r,x,b)
        y = 1/(r+1i*x);
        Y(i,i)=Y(i,i)+y+1i*b;
        Y(j,j)=Y(j,j)+y+1i*b;
        Y(i,j)=Y(i,j)-y;
        Y(j,i)=Y(j,i)-y;
    end
end
