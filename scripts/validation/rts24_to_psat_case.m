function psat_case = rts24_to_psat_case(case_data, varargin)
%RTS24_TO_PSAT_CASE  Convert in-house case_data to PSAT matrices.
%   psat_case = rts24_to_psat_case(CASE_DATA) builds a struct of PSAT-format
%   matrices (Bus.con, Line.con, SW.con, PV.con, PQ.con, Shunt.con, Syn.con,
%   Fault.con) from the in-house IEEE RTS-24 case, so that PSAT solves power
%   flow and transient stability from the SAME network input as the in-house
%   solver.  No PSAT solver is called here; this is pure data conversion.
%
%   Optional name-value:
%     'Zf', complex  -> fault impedance (default 0 + 0.1j pu)
%     'fault_bus', scalar -> fault bus (default 15)
%     't_fault', 't_clear' -> event times (default 1.0, 1.1)
%
%   PSAT column definitions verified from PSAT 2.1.11 source:
%     Bus.con  (6 cols):  [bus, Vb_kV, V0_pu, th0_rad, area, zone]
%     Line.con (16 cols): [from, to, Sn, Vn, fn, l_km, Vn2, R, X, B_total,
%                          tap, phase_deg, Smax, Smin, ?, u]
%       (col 10 = B_total; col 11 = tap; col 12 = phase_deg;
%        col 16 = u; verified from @LNclass/build_y.m)
%     SW.con  (13 cols):  [bus, Sn, Vn, Vm, Va_rad, Qmax, Qmin, Vmax, Vmin,
%                          Pgen_pu, area, zone, u]
%       (col 4=Vm, col 5=Va_rad, col 6=Qmax, col 7=Qmin, col 10=Pgen)
%     PV.con  (11 cols):  [bus, Sn, Vn, Pg_pu, Vm, Qmax, Qmin, Vmax, Vmin,
%                          area, u]
%     PQ.con  (9 cols):   [bus, Sn, Vn, P0_pu, Q0_pu, Vmax, Vmin, area, u]
%     Shunt.con(7 cols):  [bus, Sn, Vn, fn, Gs_pu, Bs_pu, u]
%       (Bs>0 = capacitive; verified from @SHclass/gcall.m)
%     Syn.con (28 cols):  [bus, Sn, Vn, fn, model, ?, ra, xd, xdp, xdpp,
%                          Td0p, Td0pp, xq, xqp, xqpp, Tq0p, Tq0pp,
%                          2H, D, Kw, Kp, Pg_frac, Qg_frac, Taa,
%                          sat1, sat2, ?, u]
%       (col 5=model; col 7=ra; col 8=xd; col 9=xdp; col 10=xdpp;
%        col 11=Td0p; col 13=xq; col 14=xqp; col 15=xqpp; col 16=Tq0p;
%        col 18=2H; col 19=D; col 28=u; verified from @SYclass/fcall.m)
%     Fault.con(8 cols):  [bus, Sn, Vn, fn, ?, tf_clear, Rf, Xf]
%       (col 7=Rf, col 8=Xf; Zf = col7 + j*col8;
%        verified from symfault.m: Zf = Fault.con(ff,7) + j*Fault.con(ff,8))

% --- Options ---------------------------------------------------------------
p = inputParser;
addParameter(p,'Zf', 0+0.1j, @isnumeric);
addParameter(p,'fault_bus', 15, @isnumeric);
addParameter(p,'t_fault', 1.0, @isnumeric);
addParameter(p,'t_clear', 1.1, @isnumeric);
parse(p, varargin{:});
opt = p.Results;
Zf = opt.Zf;

Sbase = case_data.base_values.S_base_MVA;
freq  = case_data.base_values.frequency_Hz;
bd = case_data.bus_data;     % [bus type Vm Va Pg Qg Pd Qd Gsh Bsh Qmin Qmax]
ld = case_data.line_data;    % [from to R X B_half tap phase_deg]
nb = size(bd,1);

% --- Bus.con: [bus, Vb_kV, V0, th0_rad, area, zone] ------------------------
% Vb from pgaz; area/zone from ABus.con if available.
area = ones(nb,1); zone = ones(nb,1);
if isfield(case_data,'pgaz') && isfield(case_data.pgaz,'ABus_con')
    AB = case_data.pgaz.ABus_con;
    for k=1:size(AB,1)
        r = find(bd(:,1)==AB(k,1),1);
        if ~isempty(r), area(r)=AB(k,6); zone(r)=AB(k,6); end
    end
    Vb = AB(:,3);
else
    Vb = case_data.base_values.V_base_kV * ones(nb,1);
end
Bus_con = [bd(:,1), Vb, bd(:,3), deg2rad(bd(:,4)), area, zone];

% --- Line.con: [from to Sn Vn fn l Vn2 R X B_total tap phase Smax Smin ? u] --
nl = size(ld,1);
% Vn per line from bus base kV
Vn_line = Vb(ld(:,1));
% B_total = 2 * B_half (in-house stores half; PSAT stores total)
B_total = 2 * ld(:,5);
tap = ld(:,6); tap(tap==0) = 1;
Line_con = zeros(nl,16);
Line_con(:,1) = ld(:,1);
Line_con(:,2) = ld(:,2);
Line_con(:,3) = Sbase;
Line_con(:,4) = Vn_line;
Line_con(:,5) = freq;
Line_con(:,6) = 0;          % length km (unused)
Line_con(:,7) = Vn_line;    % Vn2 (unused by solver)
Line_con(:,8) = ld(:,3);    % R
Line_con(:,9) = ld(:,4);    % X
Line_con(:,10) = B_total;   % TOTAL charging
Line_con(:,11) = tap;
Line_con(:,12) = ld(:,7);   % phase deg
Line_con(:,13) = 0;         % Smax (unused)
Line_con(:,14) = 0;         % Smin (unused)
Line_con(:,15) = 0;
Line_con(:,16) = 1;         % u (in service)

% --- SW.con / PV.con / PQ.con ----------------------------------------------
% Slack bus (type 1) -> SW; PV buses (type 2) -> PV; loads -> PQ
slack_idx = find(bd(:,2)==1);
pv_idx    = find(bd(:,2)==2);
% All buses with load (Pd or Qd != 0) -> PQ
load_idx  = find(bd(:,7)~=0 | bd(:,8)~=0);

% SW.con: [bus Sn Vn Vm Va_rad Qmax Qmin Vmax Vmin Pgen area zone u]
sw = slack_idx(1);
SW_con = [bd(sw,1), Sbase, Vb(sw), bd(sw,3), deg2rad(bd(sw,4)), ...
          bd(sw,12)*Sbase, bd(sw,11)*Sbase, 1.05, 0.95, ...
          0, area(sw), zone(sw), 1];  % Pgen=0 (slack result)

% PV.con: [bus Sn Vn Pg_pu Vm Qmax Qmin Vmax Vmin area u]
npv = numel(pv_idx);
PV_con = zeros(npv,11);
for k=1:npv
    r = pv_idx(k);
    PV_con(k,:) = [bd(r,1), Sbase, Vb(r), bd(r,5), bd(r,3), ...
                   bd(r,12)*Sbase, bd(r,11)*Sbase, 1.05, 0.95, area(r), 1];
end

% PQ.con: [bus Sn Vn P0_pu Q0_pu Vmax Vmin area u]
npq = numel(load_idx);
PQ_con = zeros(npq,9);
for k=1:npq
    r = load_idx(k);
    PQ_con(k,:) = [bd(r,1), Sbase, Vb(r), bd(r,7), bd(r,8), ...
                   1.05, 0.95, area(r), 1];
end

% --- Shunt.con: [bus Sn Vn fn Gs_pu Bs_pu u] -------------------------------
% Bus shunts (Gsh, Bsh) where non-zero
shunt_idx = find(bd(:,9)~=0 | bd(:,10)~=0);
nsh = numel(shunt_idx);
Shunt_con = zeros(nsh,7);
for k=1:nsh
    r = shunt_idx(k);
    Shunt_con(k,:) = [bd(r,1), Sbase, Vb(r), freq, bd(r,9), bd(r,10), 1];
end

% --- Syn.con: classical model (order 2) ------------------------------------
% Aggregate machines per bus: H_agg=sum(H), D_agg=sum(D), 1/Xdp_agg=sum(1/Xdp)
u = case_data.machines.units;
gen_buses = unique([u.bus]).';
ng = numel(gen_buses);
Syn_con = zeros(ng,29);
for k=1:ng
    b = gen_buses(k);
    idx = [u.bus]==b;
    Hk = [u(idx).H]; Dk = [u(idx).D]; Xk = [u(idx).Xdp];
    H_agg = sum(Hk); D_agg = sum(Dk); Xdp_agg = 1/sum(1./Xk);
    Vn_gen = Vb(find(bd(:,1)==b,1));
    is_sc = any([u(idx).is_sync_condenser]);
    % Classical model (order 2): set all reactances = X'd, large time constants
    Syn_con(k,1)  = b;            % bus
    Syn_con(k,2)  = Sbase;        % Sn
    Syn_con(k,3)  = Vn_gen;       % Vn
    Syn_con(k,4)  = freq;         % fn
    Syn_con(k,5)  = 2;            % model order (2 = classical/two-axis)
    Syn_con(k,7)  = 0;            % ra
    Syn_con(k,8)  = Xdp_agg;      % xd = X'd (classical)
    Syn_con(k,9)  = Xdp_agg;      % xdp = X'd
    Syn_con(k,10) = Xdp_agg;      % xdpp = X'd
    Syn_con(k,11) = 1000;         % Td0p (large -> constant flux)
    Syn_con(k,12) = 0.01;         % Td0pp
    Syn_con(k,13) = Xdp_agg;      % xq = X'd
    Syn_con(k,14) = Xdp_agg;      % xqp
    Syn_con(k,15) = Xdp_agg;      % xqpp
    Syn_con(k,16) = 1000;         % Tq0p
    Syn_con(k,17) = 0.01;         % Tq0pp
    Syn_con(k,18) = 2*H_agg;      % 2H (M)
    Syn_con(k,19) = D_agg;        % D
    Syn_con(k,22) = 0;            % Pgen fraction (PSAT uses PV/Supply Pg)
    Syn_con(k,23) = 1;            % Qgen fraction
    Syn_con(k,24) = 1;            % Taa (subtransient leakage time constant)
    Syn_con(k,28) = 1;            % u (in service)
    Syn_con(k,29) = 1;            % extra status col (PSAT setup handles)
    if is_sc
        Syn_con(k,22) = 0;        % sync condenser: Pm=0
    end
end

% --- Fault.con: [bus Sn Vn fn ? t_clear Rf Xf] -----------------------------
% Verified: Zf = Fault.con(ff,7) + j*Fault.con(ff,8)
fb = opt.fault_bus;
Vn_f = Vb(find(bd(:,1)==fb,1));
Fault_con = [fb, Sbase, Vn_f, freq, 1, opt.t_clear, real(Zf), imag(Zf)];

% --- Assemble --------------------------------------------------------------
psat_case = struct();
psat_case.Bus_con   = Bus_con;
psat_case.Line_con  = Line_con;
psat_case.SW_con    = SW_con;
psat_case.PV_con    = PV_con;
psat_case.PQ_con    = PQ_con;
psat_case.Shunt_con = Shunt_con;
psat_case.Syn_con   = Syn_con;
psat_case.Fault_con = Fault_con;
psat_case.Bus_names = compose('Bus%d', bd(:,1));
psat_case.Zf = Zf;
psat_case.fault_bus = fb;
psat_case.t_fault = opt.t_fault;
psat_case.t_clear = opt.t_clear;
psat_case.Sbase = Sbase;
psat_case.freq = freq;
psat_case.Line_con_ref = ld;  % [from to R X B_half tap phase] for diff reporting
psat_case.Bus_con_ref = bd;
end
