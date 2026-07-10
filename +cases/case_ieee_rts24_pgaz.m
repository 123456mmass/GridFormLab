function case_data = case_ieee_rts24_pgaz()
%CASE_IEEE_RTS24_PGAZ IEEE Reliability Test System 24-bus (RTS-1996).
%
%   Network data (buses, lines, transformers, shunt, slack/PV/PQ schedules)
%   are imported from the PGAz 1.3 data file:
%       C:\Users\User\Downloads\PGAz1.3 (2)\PGAz1.3\Data\case24_ieee_rts_mp.m
%   which is itself a conversion of the MATPOWER case24_ieee_rts case
%   (© PSERC, 3-Clause BSD License).  The PGAz file is used as a DATA SOURCE
%   / cross-validation reference only; no PGAz/MATPOWER solver is invoked.
%
%   Dynamic data (H, D, X'd) are NOT present in the PGAz file -- its Gen.con
%   contains only placeholder defaults (H=5, D=0, all reactances = 0).  The
%   real IEEE RTS-1996 dynamic data are taken from the official IEEE RTS-1996
%   report, Table 15 ("System Dynamic Data"), which explicitly states that a
%   CLASSICAL model is assumed for each generator.  These published values are
%   recorded in case_data.dynamic_assumptions and are NOT claimed to be the
%   PGAz file values.
%
%   PGAz column definitions were verified from the PGAz 1.3 source files:
%       pgaz_convert_matpower_case_to_pgaz_new.m  (the converter)
%       pgaz_import.m, pgaz_ybus.m, pgaz_sssa.m    (the readers)
%   The verified mapping is summarised in case_data.pgaz.column_map and in
%   the header comments of this file.
%
%   Source / version:
%       PGAz v1.3, file Data/case24_ieee_rts_mp.m  (header: "PGAz v1.1.1")
%       IEEE RTS-1996:  "The IEEE Reliability Test System-1996",
%           IEEE Trans. Power Systems, vol. 14, no. 3, pp. 1010-1020, 1999.
%           Table 15 dynamic data: https://labs.ece.uw.edu/pstca/rts/rts96/
%
%   Slack bus: bus 13 (230 kV), as specified in Slack.con.

% =========================================================================
% VERIFIED PGAz COLUMN MAPPING  (from PGAz 1.3 source code)
% =========================================================================
%   ABus.con  (6 cols): [bus, Type, Vb_kV, V0_pu, th0_deg, Area]
%       Type: 1=Slack, 2=PV, 0=PQ
%   ALine.con (13 cols): [i, j, Sn_MVA, Vn_kV, fn_Hz, l_km, R_pu, X_pu,
%                         B_total_pu, Tap, Smin_MVA, Smax_MVA, u]
%       B_total_pu (col 9) = TOTAL line charging; pgaz_ybus.m uses 0.5*col9.
%       Tap (col 10): 0 -> 1.
%   Slack.con (10 cols): [bus, Sn, Vn_kV, Vm_pu, Va_deg, Qmin_Mvar,
%                         Qmax_Mvar, Vmin, Vmax, u]
%   PV.con    (14 cols): [bus, Sn, Vn, Vm_pu, Pg_MW, Pgmin, Pgmax,
%                         Qgmin_Mvar, Qgmax_Mvar, Vmin, Vmax, t1, t2, u]
%   PQ.con    (14 cols): [bus, Sn, Vn, Pl_MW, Ql_Mvar, Plmin, Plmax,
%                         Qlmin, Qlmax, Vmin, Vmax, t1, t2, u]
%   AShunt.con(7 cols): [bus, Sn, Vn, fn, Gs_MW@1pu, Bs_Mvar@1pu, u]
%       Sign: positive Bs = capacitive (added +j*Bs/baseMVA to Ybus diag).
%   Gen.con   (25 cols): [bus, Sn, Vn, fn, Pmin_MW, Pmax_MW, cf, cl, cq,
%                         model, H, D, xl, ra, xd, xdp, xdd, xq, xqp, xqq,
%                         Td0p, Td0pp, Tq0p, Tq0pp, u]
%       Confirmed by pgaz_sssa.m: "1 bus, 10 model, 11 H, 12 D, 13 xl,
%       14 ra, 15 xd, 16 xdp, 17 xdd, 18 xq, 19 xqp, 20 xqq, 21 Td0p,
%       22 Td0pp, 23 Tq0p, 24 Tq0pp, 25 u".
% =========================================================================

Sbase = 100;          % system MVA base
freq  = 60;           % Hz

% --- Load the PGAz source matrices (data only, no solver) -----------------
pg = load_pgaz_source();

% =========================================================================
% Build bus_data  [bus type Vm Va_deg Pg Qg Pd Qd Gsh Bsh Qmin Qmax]
%   internal type: 1=REF/slack, 2=PV, 3=PQ
%   P/Q in pu on the 100 MVA system base.
% =========================================================================
ABus   = pg.ABus_con;
AShunt = pg.AShunt_con;
Slack  = pg.Slack_con;
PV     = pg.PV_con;
PQ     = pg.PQ_con;

nb = size(ABus,1);
bus_ids = ABus(:,1);

bus_data = zeros(nb,12);
bus_data(:,1) = bus_ids;
bus_data(:,3) = ABus(:,4);          % Vm initial
bus_data(:,4) = ABus(:,5);          % Va initial (deg)
bus_data(:,9) = 0;                  % Gsh
bus_data(:,10)= 0;                  % Bsh
bus_data(:,11)= -Inf;               % Qmin default
bus_data(:,12)=  Inf;               % Qmax default

% Map PGAz bus type: 1=Slack->1(REF), 2=PV->2, 0=PQ->3
bus_data(ABus(:,2)==1, 2) = 1;
bus_data(ABus(:,2)==2, 2) = 2;
bus_data(ABus(:,2)==0, 2) = 3;

% Loads from PQ.con (MW/Mvar -> pu)
for k = 1:size(PQ,1)
    b = PQ(k,1);
    r = find(bus_data(:,1)==b,1);
    bus_data(r,7) = PQ(k,4)/Sbase;   % Pd
    bus_data(r,8) = PQ(k,5)/Sbase;   % Qd
end

% Generation schedule and Q limits from Slack.con and PV.con (MW/Mvar->pu)
% Pgen/Qgen are left as the schedule; Qg for PV/slack is set by PF later.
for k = 1:size(Slack,1)
    b = Slack(k,1); r = find(bus_data(:,1)==b,1);
    bus_data(r,3) = Slack(k,4);          % Vm setpoint
    bus_data(r,4) = Slack(k,5);          % Va setpoint (deg)
    bus_data(r,5) = 0;                   % Pg result (slack)
    bus_data(r,6) = 0;                   % Qg result
    bus_data(r,11)= Slack(k,6)/Sbase;    % Qmin
    bus_data(r,12)= Slack(k,7)/Sbase;    % Qmax
end
for k = 1:size(PV,1)
    b = PV(k,1); r = find(bus_data(:,1)==b,1);
    bus_data(r,3) = PV(k,4);             % Vm setpoint
    bus_data(r,5) = PV(k,5)/Sbase;       % Pg schedule
    bus_data(r,6) = 0;                   % Qg result
    bus_data(r,11)= PV(k,8)/Sbase;       % Qmin
    bus_data(r,12)= PV(k,9)/Sbase;       % Qmax
end

% Shunt elements from AShunt.con (MW/Mvar @ V=1pu -> pu admittance)
% Sign convention (verified from pgaz_ybus.m): Ysh = (Gs + jBs)/baseMVA,
% i.e. positive Bs is CAPACITIVE and adds +j to the bus shunt admittance.
% Our bus_data Gsh/Bsh follow the same convention: Bsh>0 = capacitive.
for k = 1:size(AShunt,1)
    b = AShunt(k,1); r = find(bus_data(:,1)==b,1);
    bus_data(r,9)  = AShunt(k,5)/Sbase;   % Gsh (pu)
    bus_data(r,10) = AShunt(k,6)/Sbase;   % Bsh (pu, + = capacitive)
end

% =========================================================================
% Build line_data  [from to R_pu X_pu B_half_pu tap phase_deg]
%   PGAz ALine col 9 = TOTAL charging -> B_half = col9/2.
%   PGAz tap (col 10): 0 -> 1.
%   All phase shifts are 0 in this case (ALine has no phase-shifting xfmrs).
% =========================================================================
ALine = pg.ALine_con;
nl = size(ALine,1);
line_data = zeros(nl,7);
line_data(:,1) = ALine(:,1);          % from
line_data(:,2) = ALine(:,2);          % to
line_data(:,3) = ALine(:,7);          % R
line_data(:,4) = ALine(:,8);          % X
line_data(:,5) = ALine(:,9)/2;        % B_half (PGAz stores total)
tap = ALine(:,10);
tap(tap<=0) = 1;
line_data(:,6) = tap;                 % tap ratio
line_data(:,7) = 0;                   % phase shift deg (none in RTS-24)

% =========================================================================
% Machine dynamic data (per-unit generator, for transient stability)
%   The PGAz Gen.con contains only placeholder dynamic data (H=5, D=0,
%   all reactances = 0).  We instead use the official IEEE RTS-1996
%   Table 15 published dynamic data, which assumes a CLASSICAL model.
%
%   Each Gen.con row is matched to a unit group by its Pmax:
%       Pmax  20 -> U20,   76 -> U76,  100 -> U100, 197 -> U197,
%       Pmax  12 -> U12,   50 -> U50,  155 -> U155, 350 -> U350,
%       Pmax 400 -> U400,   0 -> Sync Condenser (bus 14)
%
%   RTS-1996 Table 15 (H in MJ/MW = s on MW base; X'd on unit MVA base):
%     group  Smva  X'd(pu@Smva)  H(s@MWbase)  D
%       U12    14     0.32        2.8        0.0
%       U20    24     0.32        2.8        0.0
%       U50    53     0.28        3.5        0.0
%       U76    89     0.30        3.0        0.0
%      U100   118     0.32        2.8        0.0
%      U155   182     0.30        3.0        0.0
%      U197   232     0.32        2.8        0.0
%      U350   412     0.30        3.0        0.0
%      U400   471     0.40        5.0        0.0
%
%   Conversion to 100 MVA system base:
%       H_sys   = H_table * (S_unit_MVA / S_base)        [kinetic energy]
%                 (Table 15 note 4: H given on MW base = s; the standard
%                  H-to-base conversion H_sys = H_mach * S_mach/S_sys keeps
%                  total stored kinetic energy 0.5*H_mach*S_mach constant.)
%       X'd_sys = X'd_table * (S_base / S_unit_MVA)
%       D_sys   = D_table * (S_unit_MVA / S_base)
%
%   Bus 14 synchronous condenser: Pmax=0, no mechanical power.  It is a
%   reactive device with no swing dynamics in the classical model.  It is
%   therefore EXCLUDED from the TS machine list (handled as a PV bus in PF
%   only).  This is documented as an assumption.
% =========================================================================
G = pg.Gen_con;
ng = size(G,1);

% Table 15 lookup by unit group name
unit_table = struct( ...
    'U12',  struct('Smva',14, 'Xdp',0.32,'H',2.8,'D',0.0), ...
    'U20',  struct('Smva',24, 'Xdp',0.32,'H',2.8,'D',0.0), ...
    'U50',  struct('Smva',53, 'Xdp',0.28,'H',3.5,'D',0.0), ...
    'U76',  struct('Smva',89, 'Xdp',0.30,'H',3.0,'D',0.0), ...
    'U100', struct('Smva',118,'Xdp',0.32,'H',2.8,'D',0.0), ...
    'U155', struct('Smva',182,'Xdp',0.30,'H',3.0,'D',0.0), ...
    'U197', struct('Smva',232,'Xdp',0.32,'H',2.8,'D',0.0), ...
    'U350', struct('Smva',412,'Xdp',0.30,'H',3.0,'D',0.0), ...
    'U400', struct('Smva',471,'Xdp',0.40,'H',5.0,'D',0.0));

group_by_pmax = {20,'U20'; 76,'U76'; 100,'U100'; 197,'U197';
                 12,'U12'; 50,'U50'; 155,'U155'; 350,'U350'; 400,'U400'};

units = repmat(struct('gen_id','', 'bus',0, 'group','', ...
    'Smva',0, 'H',0, 'D',0, 'Xdp',0, 'Pmin_MW',0, 'Pmax_MW',0, ...
    'model','classical', 'is_sync_condenser',false), ng, 1);

for k = 1:ng
    bus  = G(k,1);
    Pmax = G(k,6);
    Pmin = G(k,5);
    if Pmax == 0 && Pmin == 0
        % Synchronous condenser (bus 14): no active power, but it IS a
        % synchronous machine that participates in swing dynamics.  In
        % the IEEE RTS-96 it is a U197-type unit operated as a condenser
        % (Table 7 lists it at bus 14 with Q capability only).  We model
        % it with U197 classical dynamic data and Pm=0 so it swings as a
        % zero-power synchronous machine.  Documented as an assumption.
        if bus == 14
            name = 'U197'; t = unit_table.(name);
            units(k).gen_id = sprintf('%s@%d(cond)', name, bus);
            units(k).bus = bus;
            units(k).group = name;
            units(k).Smva = t.Smva;
            units(k).H   = t.H * (t.Smva / Sbase);
            units(k).D   = t.D * (t.Smva / Sbase);
            units(k).Xdp = t.Xdp * (Sbase / t.Smva);
            units(k).model = 'classical';
            units(k).is_sync_condenser = true;  % Pm will be set to 0
            units(k).Pmin_MW = Pmin; units(k).Pmax_MW = Pmax;
            continue;
        end
        units(k).gen_id = sprintf('SC@%d', bus);
        units(k).bus = bus;
        units(k).group = 'SyncCondenser';
        units(k).model = 'sync_condenser';
        units(k).is_sync_condenser = true;
        units(k).Pmin_MW = Pmin; units(k).Pmax_MW = Pmax;
        continue;
    end
    gi = find([group_by_pmax{:,1}]==Pmax, 1);
    if isempty(gi)
        error('case_ieee_rts24_pgaz:unknownUnit', ...
            'Gen row %d (bus %d, Pmax=%g) cannot be matched to a RTS-96 unit group.', ...
            k, bus, Pmax);
    end
    name = group_by_pmax{gi,2};
    t = unit_table.(name);
    units(k).gen_id = sprintf('%s@%d', name, bus);
    units(k).bus = bus;
    units(k).group = name;
    units(k).Smva = t.Smva;
    % Convert to 100 MVA system base.
    units(k).H   = t.H * (t.Smva / Sbase);     % keep kinetic energy
    units(k).D   = t.D * (t.Smva / Sbase);
    units(k).Xdp = t.Xdp * (Sbase / t.Smva);   % reactance to system base
    units(k).model = 'classical';
    units(k).Pmin_MW = Pmin; units(k).Pmax_MW = Pmax;
end

% Aggregation policy for PF: the PF solver schedules one Pg per generator
% bus.  Multiple generators at the same bus are summed (P and Q limits).
% This is done by standardize_case -> mpc.gen aggregation is implicit in
% bus_data (only one Pg per bus).  For TS the individual units are kept.

% =========================================================================
% Assemble case_data
% =========================================================================
case_data = struct();
case_data.system_name = 'IEEE RTS 24-Bus (RTS-1996, from PGAz data source)';
case_data.base_values = struct('S_base_MVA',Sbase, 'V_base_kV',230, ...
    'frequency_Hz',freq);
case_data.bus_data  = bus_data;
case_data.line_data = line_data;

% Machine struct (system-base classical units), including the bus-14
% synchronous condenser (Pm=0, U197 dynamic data).  ts_simulate handles
% the condenser by giving it Pm=0 via the balanced pm_mode.
case_data.machines = struct();
case_data.machines.base = struct('S_MVA',Sbase,'V_kV',230,'f_Hz',freq);
case_data.machines.units = units;

% PGAz source matrices (data provenance / cross-validation only).
case_data.pgaz = pg;
case_data.pgaz.column_map = struct( ...
    'ABus',  {{'bus','Type','Vb_kV','V0_pu','th0_deg','Area'}}, ...
    'ALine', {{'i','j','Sn_MVA','Vn_kV','fn_Hz','l_km','R_pu','X_pu', ...
              'B_total_pu','Tap','Smin_MVA','Smax_MVA','u'}}, ...
    'Slack', {{'bus','Sn','Vn_kV','Vm_pu','Va_deg','Qmin_Mvar', ...
              'Qmax_Mvar','Vmin','Vmax','u'}}, ...
    'PV',    {{'bus','Sn','Vn','Vm_pu','Pg_MW','Pgmin','Pgmax', ...
              'Qgmin_Mvar','Qgmax_Mvar','Vmin','Vmax','t1','t2','u'}}, ...
    'PQ',    {{'bus','Sn','Vn','Pl_MW','Ql_Mvar','Plmin','Plmax', ...
              'Qlmin','Qlmax','Vmin','Vmax','t1','t2','u'}}, ...
    'AShunt',{{'bus','Sn','Vn','fn','Gs_MW_at1pu','Bs_Mvar_at1pu','u'}}, ...
    'Gen',   {{'bus','Sn','Vn','fn','Pmin_MW','Pmax_MW','cf','cl','cq', ...
              'model','H','D','xl','ra','xd','xdp','xdd','xq','xqp','xqq', ...
              'Td0p','Td0pp','Tq0p','Tq0pp','u'}});

% Dynamic-data assumptions (NOT the PGAz file values).
case_data.dynamic_assumptions = struct();
case_data.dynamic_assumptions.source = ...
    'IEEE RTS-1996 Table 15 (https://labs.ece.uw.edu/pstca/rts/rts96/)';
case_data.dynamic_assumptions.model = 'classical (per Table 15 Note 1)';
case_data.dynamic_assumptions.note = { ...
    'The PGAz file Gen.con contains only placeholder dynamic data', ...
    '(H=5, D=0, all reactances = 0) from the PGAz conversion defaults.', ...
    'Real IEEE RTS-1996 Table 15 data are used instead. H is converted to', ...
    'the 100 MVA system base keeping total kinetic energy (H_sys=H*Sunit/Ssys).', ...
    'X''d is converted to the system base (Xdp_sys = Xdp*Ssys/Sunit).', ...
    'Bus 14 is a synchronous condenser (Pmax=0); it is excluded from the', ...
    'classical TS machine list and kept as a PV bus in PF only.'};
case_data.dynamic_assumptions.unit_table = unit_table;
case_data.dynamic_assumptions.conversion = struct( ...
    'H_sys','H_table * (S_unit_MVA / S_base)', ...
    'D_sys','D_table * (S_unit_MVA / S_base)', ...
    'Xdp_sys','Xdp_table * (S_base / S_unit_MVA)');

case_data.ts_defaults = struct( ...
    'fault_bus', 15, ...
    't_end', 15, 'dt', 0.01, ...
    't_fault', 1.0, 't_clear', 1.1, ...
    'Zf', 1i*0.1, 'model', 'classical', ...
    'fault_bus_rationale', ...
    ['Bus 15 is a 230 kV load bus with 5xU12 + 1xU155 generation ', ...
     'and a heavy load (317 MW); a fault there exercises the inter-area ', ...
     'swing between the 138 kV and 230 kV parts of the network.']);

case_data.reference = struct( ...
    'pgaz_file', 'C:\Users\User\Downloads\PGAz1.3 (2)\PGAz1.3\Data\case24_ieee_rts_mp.m', ...
    'pgaz_version', 'PGAz v1.1.1 (file header); packaged in PGAz v1.3', ...
    'rts96_table15', 'https://labs.ece.uw.edu/pstca/rts/rts96/Table-15.txt');

case_data = cases.standardize_case(case_data);
end

% =========================================================================
function pg = load_pgaz_source()
% Load the raw PGAz matrices from the data-source file.  This is a DATA
% read only; no PGAz solver code is executed.
src = 'C:\Users\User\Downloads\PGAz1.3 (2)\PGAz1.3\Data\case24_ieee_rts_mp.m';
if ~exist(src,'file')
    error('case_ieee_rts24_pgaz:noSource', ...
        'PGAz data source not found: %s', src);
end
S = struct();
ABus=struct(); ALine=struct(); Slack=struct(); PV=struct(); PQ=struct(); AShunt=struct(); Gen=struct();
run(src); %#ok<EVALNC>
% PGAz file stores each matrix as a struct with a .con field.
pg.ABus_con   = ABus.con;
pg.ALine_con  = ALine.con;
pg.Slack_con  = Slack.con;
pg.PV_con     = PV.con;
pg.PQ_con     = PQ.con;
pg.AShunt_con = AShunt.con;
pg.Gen_con    = Gen.con;
pg.source_file = src;
end
