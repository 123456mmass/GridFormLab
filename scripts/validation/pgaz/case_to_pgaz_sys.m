function sys = case_to_pgaz_sys(c, varargin)
%CASE_TO_PGAZ_SYS Build a PGAz 1.1.1 (PSAT-lite) sys struct from a project
%case, for REFERENCE cross-validation only (PGAz is not a production dep).
%   Classical model: H/D/X'd aggregated per generator bus (one online gen
%   per bus, as PGAz requires). Matches the project classical TS engine's
%   aggregation (H_sum, D_sum, 1/X'd = sum(1/X'd)).
%
%   sys fields produced: ABus, ALine, Slack, PV, PQ, Gen, AShunt, baseMVA,
%   nbus, Pl, Pg, Ql, Qmin, Qmax, Vm, Va, idx.slack.

mpc = c.mpc;
bus = mpc.bus; br = mpc.branch; gen = mpc.gen; baseMVA = mpc.baseMVA;
nb = size(bus,1);

% --- Machine data (H/D/Xdp) aggregated per generator bus -----------------
grows = gen(gen(:,8) ~= 0, :);                 % online generators
gbus_raw = grows(:,1);
[gbus,~,ic] = unique(gbus_raw, 'stable');
ng = numel(gbus);
[Hd, Dd, Xdpd] = machine_data(c, grows, gbus, ic);

% --- ABus [bus_i Type Vb V0 th0 area] -------------------------------------
% MATPOWER type: 3=ref -> PGAz 1(slack); 2=PV -> 2; 1=PQ -> 0.
pgtype = zeros(nb,1);
pgtype(bus(:,2)==3) = 1;
pgtype(bus(:,2)==2) = 2;
pgtype(bus(:,2)==1) = 0;
area = ones(nb,1); if size(bus,2)>=7, area = max(bus(:,7),1); end
ABus = [bus(:,1), pgtype, bus(:,10), bus(:,8), bus(:,9), area];

% --- ALine [f t Sn Vn fn l R X B Tap Smin Smax u] ------------------------
% pgaz_ybus: R=col7, X=col8, Bh=0.5*col9 -> col9 = TOTAL b. Tap=col10.
nl = size(br,1);
Sn = baseMVA*ones(nl,1);
Vn = bus(:,10); Vn = Vn(br(:,1));               % sending bus baseKV
fn = 60*ones(nl,1); ll = zeros(nl,1);
R = br(:,3); X = br(:,4); Btot = br(:,5);
tap = br(:,9); tap(tap==0) = 1;
Smin = zeros(nl,1); Smax = zeros(nl,1);
if size(br,2)>=6, Smax = br(:,6); end
u = ones(nl,1); if size(br,2)>=11, u = double(br(:,11)~=0); u(u==0)=1; end
ALine = [br(:,1), br(:,2), Sn, Vn, fn, ll, R, X, Btot, tap, Smin, Smax, u];

% --- Slack / PV / PQ ------------------------------------------------------
refbus = find(pgtype==1,1);
slk_row = bus(refbus,:);
Slack = [slk_row(1), baseMVA, slk_row(10), slk_row(8), slk_row(9), ...
         -999, 999, 0.95, 1.05, 1];
pvrows = find(pgtype==2);
PV = zeros(numel(pvrows),14);
for k=1:numel(pvrows)
    b = pvrows(k); brow = bus(b,:);
    % find gen at this bus
    gi = find(gbus==brow(1),1);
    Pg = 0; Qmin=-999; Qmax=999;
    if ~isempty(gi), Pg = grows(gi,2); Qmin=grows(gi,5); Qmax=grows(gi,4); end
    PV(k,:) = [brow(1), baseMVA, brow(10), brow(8), Pg, 0, grows(gi,9), Qmin, Qmax, 0.95, 1.05, 0, 0, 1];
end
pqrows = find(pgtype==0);
PQ = zeros(numel(pqrows),14);
for k=1:numel(pqrows)
    brow = bus(pqrows(k),:);
    PQ(k,:) = [brow(1), baseMVA, brow(10), brow(3), brow(4), brow(3), brow(3), brow(4), brow(4), 0.95, 1.05, 0, 0, 1];
end

% --- Gen [bus Sn Vn fn Pmin Pmax cf cl cq model H D xl ra xd xdp xdpp ... u]
Gen = zeros(ng,25);
for k=1:ng
    gi = find(gbus_raw==gbus(k),1);
    Gen(k,1) = gbus(k);
    Gen(k,2) = baseMVA;
    Gen(k,3) = bus(find(bus(:,1)==gbus(k),1),10);
    Gen(k,4) = 60;
    Gen(k,5) = grows(gi,10);    % Pmin
    Gen(k,6) = grows(gi,9);     % Pmax
    Gen(k,10) = 6;              % model: classical
    Gen(k,11) = Hd(k);
    Gen(k,12) = Dd(k);
    Gen(k,16) = Xdpd(k);        % x'd (col 16)
    Gen(k,25) = 1;              % u (online)
end

% --- Per-bus load/generation (pu) + Q limits + initial guess -------------
Pl = bus(:,3)/baseMVA; Ql = bus(:,4)/baseMVA;
Pg = zeros(nb,1); Qmin=-Inf(nb,1); Qmax=Inf(nb,1);
for k=1:size(grows,1)
    b = find(bus(:,1)==grows(k,1),1);
    Pg(b) = Pg(b) + grows(k,2)/baseMVA;
    Qmin(b) = grows(k,5)/baseMVA; Qmax(b) = grows(k,4)/baseMVA;
end
Vm = bus(:,8); Va = bus(:,9);

sys = struct();
sys.ABus=ABus; sys.ALine=ALine; sys.Slack=Slack; sys.PV=PV; sys.PQ=PQ;
sys.Gen=Gen; sys.AShunt=[]; sys.baseMVA=baseMVA; sys.nbus=nb;
sys.Pl=Pl; sys.Pg=Pg; sys.Ql=Ql; sys.Qmin=Qmin; sys.Qmax=Qmax;
sys.Vm0=Vm; sys.Va0=deg2rad(Va);
sys.idx = struct('slack', find(pgtype==1,1), 'pv', find(pgtype==2), 'pq', find(pgtype==0));
end

function [H,D,Xdp] = machine_data(c, grows, gbus, ic)
% Aggregate per bus: H_sum, D_sum, 1/X'd = sum(1/X'd). Defaults H=5,D=0,X'd=0.3.
ng = numel(gbus);
H = 5*ones(ng,1); D = zeros(ng,1); Xdp = 0.30*ones(ng,1);
if isfield(c,'machines') && ~isempty(c.machines) && isstruct(c.machines) && isfield(c.machines,'units')
    units = c.machines.units;
    mbus = [units.bus];
    for k=1:ng
        idx = find(mbus==gbus(k));
        if ~isempty(idx)
            H(k) = sum([units(idx).H]);
            D(k) = sum([units(idx).D]);
            Xdp(k) = 1/sum(1./[units(idx).Xdp]);
        end
    end
    % Convert to system base if machine-base data present (ratio = Sm/Ssys).
    if isfield(c.machines,'base') && isfield(c.machines.base,'S_MVA')
        ratio = c.machines.base.S_MVA / c.base_values.S_base_MVA;
        H = H * ratio; D = D * ratio; Xdp = Xdp / ratio;
    end
end
% (No external H/D/X'd override: machine data come from the case, matching the
%  production classical engine, so the comparison is apples-to-apples.)
end
